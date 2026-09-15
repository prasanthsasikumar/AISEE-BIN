//
// AiSeeConnectionService.swift — AiSeeGlassKit
//
// Scan → connect → activate for the AiSee glasses over the Realtek profile
// connection model. Two discovery paths run at once, because the glasses may
// reach the phone as an LE peripheral (scan) or as a GATT-over-BREDR device
// already paired in iOS Settings (retrieve + monitor) — the vendor's own
// discovery screen does both.
//
// Owns the one RTKProfileConnectionManager. Hands `connection` to the other
// kit files; the UI never sees SDK types.
//

import CoreBluetooth
import Foundation
import Observation

#if canImport(RTKAIDeviceConnection)
import RTKAIDeviceConnection
import RTKLEFoundation
import RTKAudioConnectSDK

@MainActor
@Observable
final class AiSeeConnectionService: NSObject {
    static let lastPeripheralKey = "aisee_last_peripheral"

    var state: AiSeeConnectionState = .disconnected
    var discovered: [AiSeeDiscoveredDevice] = []
    var battery: Int?
    var bluetoothReady = false

    @ObservationIgnored private(set) var connection: IntelligenceDeviceConnection?
    @ObservationIgnored private var manager: RTKProfileConnectionManager!
    @ObservationIgnored private var candidates: [UUID: IntelligenceDeviceConnection] = [:]
    @ObservationIgnored private let log: AiSeeLog

    init(log: @escaping AiSeeLog) {
        self.log = log
        super.init()
        manager = RTKProfileConnectionManager(delegate: self)
        manager.registerConnectionClass(forInstantiateGATTPeripheral: IntelligenceDeviceConnection.self)
    }

    // MARK: Discovery

    func startScan() {
        // Early-return leaves `pendingReconnect` untouched — the GATT-availability
        // handler below (`profileManagerDidUpdateGATTAvailability`) re-drives this
        // scan once Bluetooth is actually ready.
        guard bluetoothReady else { log("connection: Bluetooth not ready"); return }
        discovered = []
        candidates = [:]
        if case .disconnected = state { state = .scanning }
        // Already-paired glasses do not advertise; list them straight away.
        for conn in manager.retrieveConnectedPeripheralConnections() {
            remember(conn, rssi: 0)
            // `remember` may have matched a pending reconnect and started connecting.
            // Restarting the scan on top of that would immediately stop it again.
            if case .connecting = state { return }
        }
        manager.startMonitoringNewConnectionWithPeripheral()
        manager.scanForPeripherals()
        log("connection: scanning")
    }

    func stopScan() {
        manager.stopScan()
        if case .scanning = state { state = .disconnected }
    }

    // MARK: Connect / disconnect

    func connect(_ id: UUID) {
        guard let conn = candidates[id] else { log("connection: unknown device \(id)"); return }
        manager.stopScan()
        state = .connecting
        Task { await activate(conn) }
    }

    func disconnect() {
        guard let conn = connection else { return }
        userInitiatedDisconnect = true
        // A deliberate disconnect must not come back on the next launch, and must
        // not trip the auto-reconnect in the delegate paths below.
        UserDefaults.standard.removeObject(forKey: Self.lastPeripheralKey)
        Task {
            do { _ = try await conn.deactivate() } catch { self.log("connection: deactivate failed: \(error)") }
            self.clearConnection()
            self.userInitiatedDisconnect = false
            self.log("connection: disconnected by user")
        }
    }

    func refreshBattery() async {
        guard let conn = connection else { return }
        do {
            try await conn.basicRoutine?.budInfo()
            battery = conn.basicRoutine?.singleOrLeftBattery?.intValue
            log("connection: battery \(battery.map(String.init) ?? "?")%")
        } catch {
            log("connection: budInfo failed: \(error)")
        }
    }

    /// Reconnects to the last device if it is reachable. Call once at launch.
    func reconnectLastDevice() {
        guard let raw = UserDefaults.standard.string(forKey: Self.lastPeripheralKey),
              let id = UUID(uuidString: raw) else { return }
        log("connection: looking for last device \(id)")
        pendingReconnect = id
        startScan()
    }

    @ObservationIgnored private var pendingReconnect: UUID?
    @ObservationIgnored private var userInitiatedDisconnect = false

    // MARK: Internals

    private func activate(_ conn: IntelligenceDeviceConnection) async {
        do {
            try await conn.activate()
            conn.delegate = self
            connection = conn
            state = .connected(name: conn.deviceName ?? "AiSee")
            UserDefaults.standard.set(conn.peripheral.identifier.uuidString, forKey: Self.lastPeripheralKey)
            log("connection: active — \(conn.deviceName ?? "unnamed")")
            await refreshBattery()
        } catch {
            log("connection: activate failed: \(error)")
            state = .disconnected
        }
    }

    private func clearConnection() {
        connection?.delegate = nil
        connection = nil
        battery = nil
        state = .disconnected
    }

    /// Both disconnect delegate paths land here. An unexpected drop of the
    /// remembered device re-arms the same reconnect the app does at launch, so a
    /// glasses power-cycle or a walk out of range recovers on its own.
    private func handleDisconnection(reason: String) {
        let id = connection?.peripheral.identifier
        let deliberate = userInitiatedDisconnect
        clearConnection()
        log("connection: \(reason)")
        guard !deliberate, let id,
              UserDefaults.standard.string(forKey: Self.lastPeripheralKey) == id.uuidString else { return }
        log("connection: will try to reconnect to \(id)")
        pendingReconnect = id
        startScan()
    }

    private func remember(_ conn: RTKProfileConnection, rssi: Int) {
        guard let aiConn = conn as? IntelligenceDeviceConnection else { return }
        let id = aiConn.peripheral.identifier
        candidates[id] = aiConn
        let device = AiSeeDiscoveredDevice(id: id, name: aiConn.deviceName ?? "AiSee (\(id.uuidString.prefix(4)))", rssi: rssi)
        if let i = discovered.firstIndex(where: { $0.id == id }) { discovered[i] = device } else { discovered.append(device) }
        if pendingReconnect == id {
            pendingReconnect = nil
            connect(id)
        }
    }
}

extension AiSeeConnectionService: RTKProfileConnectionManagerDelegate {
    nonisolated func profileManagerDidUpdateGATTAvailability(_ manager: RTKProfileConnectionManager) {
        let ready = manager.gattAvailable
        Task { @MainActor in
            self.bluetoothReady = ready
            self.log("connection: GATT available = \(ready)")
            // `reconnectLastDevice()` may run before Bluetooth powers on, in which case
            // `startScan()` no-ops (guarded on `bluetoothReady`, see there) while leaving
            // `pendingReconnect` set. Once GATT actually becomes available, resume the
            // scan here so a pending reconnect isn't silently dropped at launch.
            if ready, self.pendingReconnect != nil, !self.state.isConnected {
                self.startScan()
            }
        }
    }

    nonisolated func profileManager(_ manager: RTKProfileConnectionManager,
                                    didDiscoverPeripheralOf connection: RTKProfileConnection,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in self.remember(connection, rssi: RSSI.intValue) }
    }

    nonisolated func profileManager(_ manager: RTKProfileConnectionManager, didDetectConnectionOf connection: RTKProfileConnection) {
        Task { @MainActor in self.remember(connection, rssi: 0) }
    }

    nonisolated func profileManager(_ manager: RTKProfileConnectionManager, didDetectDisconnectionOf connection: RTKProfileConnection) {
        Task { @MainActor in
            guard self.connection === connection else { return }
            self.handleDisconnection(reason: "device disconnected")
        }
    }
}

// `IntelligenceDeviceConnection.delegate` (inherited from `RTKConnectionUponGATT`)
// is typed `RTKConnectionUponGATTDelegate`, a subprotocol of
// `RTKProfileConnectionDelegate` — conforming to the base protocol alone is
// not sufficient for `conn.delegate = self` to type-check. All of the extra
// requirements are `@optional`, so this conformance needs no more methods.
extension AiSeeConnectionService: RTKConnectionUponGATTDelegate {
    nonisolated func profileConnection(_ connection: RTKProfileConnection, deviceDidBeDisconnected error: Error?) {
        Task { @MainActor in
            guard self.connection === connection else { return }
            self.handleDisconnection(reason: "link dropped\(error.map { " — \($0)" } ?? "")")
        }
    }
}

#else

/// Simulator / no-SDK stub so consumers compile. Always disconnected.
@MainActor
@Observable
final class AiSeeConnectionService {
    static let lastPeripheralKey = "aisee_last_peripheral"
    var state: AiSeeConnectionState = .disconnected
    var discovered: [AiSeeDiscoveredDevice] = []
    var battery: Int?
    var bluetoothReady = false
    init(log: @escaping AiSeeLog) {}
    func startScan() {}
    func stopScan() {}
    func connect(_ id: UUID) {}
    func disconnect() {}
    func refreshBattery() async {}
    func reconnectLastDevice() {}
}

#endif
