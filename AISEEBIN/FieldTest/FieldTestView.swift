import SwiftUI
import simd

/// On-site testing for a sighted tester: line the map's Immersal scans up by
/// walking (phone only), mark where each tour point really is, and check how
/// far the app's position is from a marked point, in glasses or phone mode.
/// Every mark, check and link is posted to `ab_field_results`, so the team can
/// read a test run the same day without being there.
struct FieldTestView: View {
    @Bindable var viewModel: NavigationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var busy: String?
    @State private var marks: [String: SIMD2<Float>] = [:]
    @State private var checks: [String: String] = [:]
    @State private var linkResult: [Int: ScanLinkSolver.Link] = [:]
    @State private var message: String?
    @State private var messageIsError = false

    /// Points parked off the route by the editor script until they are marked on site.
    private static let parkedX: Float = -40

    private var linker: ScanLinker { viewModel.scanLinker }
    private var map: NavigationMap { viewModel.currentMap }
    private var points: [NavigationPOI] { map.pois.filter { $0.category != .junction } }
    private var scans: [ImmersalAlignment.MapPlacement] {
        if let maps = map.immersalAlignment?.maps, !maps.isEmpty { return maps }
        return (map.immersalAlignment?.mapIDs ?? []).map { ImmersalAlignment.MapPlacement(id: $0, yaw: 0, tx: 0, tz: 0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                linkSection
                markSection
                checkSection
                logSection
            }
            .navigationTitle("Field test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Done") { dismiss() } } }
            .disabled(busy != nil && busy != "link")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            LabeledContent("Map", value: "\(map.name) · v\(viewModel.localVersion?.version ?? 0)")
            LabeledContent("Positioning", value: "\(viewModel.fieldMode) · \(viewModel.fieldLocalizer.isEmpty ? "starting" : viewModel.fieldLocalizer)")
            let c = viewModel.fieldCounters
            LabeledContent("Fixes", value: "\(c.fixes) of \(c.attempts) tries")
            LabeledContent("Position", value: viewModel.mapPose.map { String(format: "x %.1f  z %.1f", $0.position.x, $0.position.y) } ?? "not found yet")
            if let busy, busy != "link" { Label(busy, systemImage: "hourglass").foregroundStyle(.secondary) }
            if let message { Text(message).font(.footnote).foregroundStyle(messageIsError ? .red : .secondary) }
        } footer: {
            Text("Pick the space's map in Settings first. Glasses or phone positioning is chosen on the Glasses screen; each check is recorded with the mode it ran in.")
        }
    }

    // MARK: - 1 · Link scans

    private var linkSection: some View {
        Section {
            if viewModel.positioningSource == .glasses {
                Text("Linking needs phone positioning: on the Glasses screen, hand positioning back to the phone, then come back here.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if scans.count < 2 {
                Text(scans.isEmpty ? "This map has no Immersal scans." : "This map has one Immersal scan; nothing to link.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                if linker.running {
                    Button("Stop walk", role: .destructive) { linker.stop(); busy = nil; solveLinks() }
                } else {
                    Button(linker.samples.isEmpty ? "Start walk" : "Start again") {
                        linkResult = [:]
                        linker.start(maps: scans.map { ($0.id, $0.name ?? "Immersal \($0.id)") }, token: ImmersalConfig.token)
                        busy = "link"
                    }
                }
                ForEach(linker.stats) { s in
                    let link = linkResult[s.id]
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(s.name, value: "\(s.fixes) fixes / \(s.tries)")
                        if let link {
                            Text(link.via == nil ? "reference: stays where it is"
                                 : String(format: "placed via %d · %d pairs · spread %.2f m, %.1f°", link.via!, link.pairs, link.spreadMetres, link.spreadDegrees))
                                .font(.caption).foregroundStyle(link.spreadMetres < 0.5 ? Color.green : Color.orange)
                        } else if !linker.running, !linker.samples.isEmpty {
                            Text("not linked: needs fixes on this scan within 15 s of a linked one").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let e = linker.lastError { Text(e).font(.caption).foregroundStyle(.orange) }
                if !linker.running, linkResult.count > 1 {
                    Button("Publish linked placements") { Task { await publishLinks() } }
                }
            }
        } header: {
            Text("1 · Link scans (phone)")
        } footer: {
            Text("Walk the whole route slowly with the phone held up, pausing where two scans meet. Every scan needs fixes, and neighbouring scans need fixes within a few seconds of each other. Needs internet.")
        }
    }

    private func solveLinks() {
        guard let ref = scans.first(where: { id in linker.samples.contains { $0.mapID == id.id } }) else {
            show("No scan answered during the walk.", error: true); return
        }
        let first = scans[0]
        let refPlacement = Placement4(ref, ty: ref.ty ?? 0)
        linkResult = linker.solve(reference: ref.id, referencePlacement: refPlacement)
        let placed = linkResult.count, total = scans.count
        show(ref.id == first.id ? "Linked \(placed) of \(total) scans to \(first.name ?? "the first scan")."
             : "The first scan never answered; linked \(placed) of \(total) scans to \(ref.name ?? "\(ref.id)") instead.")
    }

    private func publishLinks() async {
        var graph = map
        guard var alignment = graph.immersalAlignment else { return }
        var maps = scans
        for i in maps.indices { if let link = linkResult[maps[i].id] {
            maps[i].yaw = link.placement.yaw; maps[i].tx = link.placement.tx; maps[i].tz = link.placement.tz
        } }
        alignment.maps = maps
        alignment.mapIDs = maps.map(\.id)
        if let first = maps.first { alignment.yaw = first.yaw; alignment.tx = first.tx; alignment.tz = first.tz }
        graph.immersalAlignment = alignment
        await publish(graph, note: "Scans linked on site by walking (\(linkResult.count) of \(maps.count))") { version in
            var payload: [String: FieldTestClient.JSONValue] = ["published_version": .number(Double(version))]
            payload["links"] = .array(linkResult.values.sorted { $0.mapID < $1.mapID }.map { l in
                .object(["id": .number(Double(l.mapID)), "yaw": .number(Double(l.placement.yaw)), "tx": .number(Double(l.placement.tx)),
                         "tz": .number(Double(l.placement.tz)), "pairs": .number(Double(l.pairs)), "spread_m": .number(Double(l.spreadMetres)),
                         "spread_deg": .number(Double(l.spreadDegrees)), "via": l.via.map { .number(Double($0)) } ?? .null])
            })
            payload["scans"] = .array(linker.stats.map { .object(["id": .number(Double($0.id)), "tries": .number(Double($0.tries)), "fixes": .number(Double($0.fixes))]) })
            return FieldTestClient.Row(kind: "link", map_slug: viewModel.mapSlug, map_version: version, mode: "phone", localizer: "cloud", payload: payload)
        }
    }

    // MARK: - 2 · Mark points

    private var markSection: some View {
        Section {
            ForEach(points) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                        Text(markStatus(p)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Mark") { Task { await mark(p) } }.buttonStyle(.bordered)
                }
            }
            if !marks.isEmpty {
                Button("Publish \(marks.count) mark\(marks.count == 1 ? "" : "s")") { Task { await publishMarks() } }
            }
        } header: {
            Text("2 · Mark points")
        } footer: {
            Text("Stand exactly on the point and keep still while it listens for 5 seconds. Then publish, so the tour and the checks use the real positions.")
        }
    }

    private func markStatus(_ p: NavigationPOI) -> String {
        if let m = marks[p.id] { return String(format: "measured x %.1f z %.1f · not published yet", m.x, m.y) }
        return p.x == Self.parkedX ? "not marked yet" : String(format: "at x %.1f z %.1f", p.x, p.z)
    }

    private func mark(_ p: NavigationPOI) async {
        guard let samples = await listen(seconds: 5, label: "Marking \(p.name)…"), samples.count >= 3 else {
            show("No steady position while marking \(p.name). Stay still where the app has found you, and try again.", error: true); return
        }
        let x = ScanLinkSolver.median(samples.map(\.x)), z = ScanLinkSolver.median(samples.map(\.y))
        let spread = ScanLinkSolver.median(samples.map { hypot($0.x - x, $0.y - z) })
        marks[p.id] = SIMD2(x, z)
        show(String(format: "%@ measured at x %.2f z %.2f (spread %.2f m from %d readings).", p.name, x, z, spread, samples.count))
        await post(.init(kind: "mark", map_slug: viewModel.mapSlug, map_version: viewModel.localVersion?.version,
                         mode: viewModel.fieldMode, localizer: viewModel.fieldLocalizer, point_id: p.id, point_name: p.name,
                         payload: ["x": .number(Double(x)), "z": .number(Double(z)), "spread_m": .number(Double(spread)),
                                   "readings": .number(Double(samples.count))]))
    }

    private func publishMarks() async {
        var graph = map
        for i in graph.pois.indices { if let m = marks[graph.pois[i].id] { graph.pois[i].x = m.x; graph.pois[i].z = m.y } }
        let count = marks.count
        await publish(graph, note: "\(count) point(s) marked on site") { version in
            FieldTestClient.Row(kind: "mark", map_slug: viewModel.mapSlug, map_version: version, mode: viewModel.fieldMode,
                                localizer: viewModel.fieldLocalizer, payload: ["published_marks": .number(Double(count))])
        }
        marks = [:]
    }

    // MARK: - 3 · Accuracy check

    private var checkSection: some View {
        Section {
            ForEach(points.filter { $0.x != Self.parkedX }) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name)
                        if let r = checks[p.id] { Text(r).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("I'm here") { Task { await check(p) } }.buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text("3 · Accuracy check")
        } footer: {
            Text("Stand on a marked point and tap I'm here: for 10 seconds the app records where it thinks you are and how far that is from the point. Try it with the glasses and with the phone.")
        }
    }

    private func check(_ p: NavigationPOI) async {
        let before = viewModel.fieldCounters
        let samples = await listen(seconds: 10, label: "Checking at \(p.name)…") ?? []
        let after = viewModel.fieldCounters
        let target = SIMD2(p.x, p.z)
        var payload: [String: FieldTestClient.JSONValue] = [
            "target_x": .number(Double(p.x)), "target_z": .number(Double(p.z)),
            "readings": .number(Double(samples.count)),
            "tries": .number(Double(after.attempts - before.attempts)), "fixes": .number(Double(after.fixes - before.fixes)),
        ]
        let summary: String
        if samples.isEmpty {
            summary = "no position in 10 s"
        } else {
            let errors = samples.map { simd_distance($0, target) }.sorted()
            let mean = samples.reduce(SIMD2<Float>.zero, +) / Float(samples.count)
            let err = simd_distance(mean, target), p90 = errors[min(errors.count - 1, Int(Float(errors.count) * 0.9))]
            payload["error_m"] = .number(Double(err)); payload["p90_m"] = .number(Double(p90))
            payload["mean_x"] = .number(Double(mean.x)); payload["mean_z"] = .number(Double(mean.y))
            payload["samples"] = .array(samples.map { .array([.number(Double($0.x)), .number(Double($0.y))]) })
            summary = String(format: "%.1f m off (90%% within %.1f m) · %d/%d fixes · %@", err, p90,
                             after.fixes - before.fixes, after.attempts - before.attempts, viewModel.fieldMode)
        }
        checks[p.id] = summary
        show("\(p.name): \(summary)")
        await post(.init(kind: "check", map_slug: viewModel.mapSlug, map_version: viewModel.localVersion?.version,
                         mode: viewModel.fieldMode, localizer: viewModel.fieldLocalizer, point_id: p.id, point_name: p.name,
                         payload: payload))
    }

    // MARK: - 4 · Log

    private var logSection: some View {
        Section {
            Button("Send log") {
                Task {
                    busy = "Sending log…"
                    do { let path = try await FieldTestClient.uploadLog(mapSlug: viewModel.mapSlug); show("Log sent (\(path)).") }
                    catch { show("Log not sent: \(error.localizedDescription)", error: true) }
                    busy = nil
                }
            }
        } footer: {
            Text("Uploads this phone's positioning log for the team. Send one at the end of a session.")
        }
    }

    // MARK: - Helpers

    /// Positions (map x, z) the app reports over `seconds`, one per update.
    private func listen(seconds: Double, label: String) async -> [SIMD2<Float>]? {
        busy = label
        defer { busy = nil }
        var out: [SIMD2<Float>] = []
        var last: MapPose?
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let pose = viewModel.mapPose, pose != last { out.append(pose.position); last = pose }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return out
    }

    private func publish(_ graph: NavigationMap, note: String, row: (Int) -> FieldTestClient.Row) async {
        busy = "Publishing…"
        defer { busy = nil }
        do {
            let version = try await viewModel.publishFieldMap(graph, note: note)
            show("Published as version \(version). The app has reloaded it.")
            await post(row(version))
        } catch {
            show("Could not publish: \(error.localizedDescription)", error: true)
        }
    }

    private func post(_ row: FieldTestClient.Row) async {
        do { try await FieldTestClient.post(row) }
        catch { show("Result kept here but not uploaded: \(error.localizedDescription)", error: true) }
    }

    private func show(_ text: String, error: Bool = false) {
        message = text; messageIsError = error
        DiagnosticsLog.write("field-test: \(text)")
    }
}
