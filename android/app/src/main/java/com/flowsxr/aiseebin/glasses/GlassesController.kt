package com.flowsxr.aiseebin.glasses

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ResultReceiver
import android.util.Log
import com.realsil.sdk.audioconnect.ai.AISoundPool
import com.realsil.sdk.audioconnect.smartwear.ActionStateNotification
import com.realsil.sdk.audioconnect.smartwear.SmartWearModelCallback
import com.realsil.sdk.audioconnect.smartwear.SmartWearModelClient
import com.realsil.sdk.audioconnect.smartwear.SmartWearModelProxy
import com.realsil.sdk.audioconnect.smartwear.config.LiveStreamingConfigInfo
import com.realsil.sdk.audioconnect.smartwear.entity.WifiAccessInfo
import com.realsil.sdk.audioconnect.smartwear.live.PlayerServiceContract
import com.realsil.sdk.audioconnect.smartwear.live.RTKMediaPlayerService
import com.realsil.sdk.audioconnect.smartwear.live.SessionConfig
import com.realsil.sdk.bbpro.MultiPeripheralConnectionManager
import com.realsil.sdk.bbpro.PeripheralConnectionManager
import com.realsil.sdk.bbpro.core.peripheral.ConnectionParameters
import com.realsil.sdk.bbpro.core.peripheral.PeripheralParameters
import com.realsil.sdk.bbpro.model.DeviceInfo
import com.realsil.sdk.bbpro.vendor.VendorModelCallback
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class Link { DISCONNECTED, CONNECTING, CONNECTED, READY }
enum class Stream { OFF, STARTING, PLAYING, STOPPING }

data class GlassesState(
    val link: Link = Link.DISCONNECTED,
    val address: String? = null,
    val name: String? = null,
    val battery: Int? = null,
    val stream: Stream = Stream.OFF,
    val fps: Int = 0,
    val error: String? = null,
)

data class BondedGlasses(val address: String, val name: String)

/**
 * The AiSee glasses through Realtek's SmartWear SDK: classic-Bluetooth control
 * link, and the camera over the glasses' own Wi-Fi hotspot (WIFI_AP), decoded by
 * the SDK's native player. The SDK joins the hotspot itself with a network
 * request, so the phone's default network — and every Immersal request — stays
 * on mobile data or whatever Wi-Fi it had.
 *
 * Built from the vendor reference app (AIGlass 0.5.55) and SmartWear guide §5.
 */
class GlassesController(context: Context, private val scope: CoroutineScope) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val prefs = app.getSharedPreferences("glasses", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(GlassesState(address = prefs.getString(KEY_ADDRESS, null),
        name = prefs.getString(KEY_NAME, null)))
    val state: StateFlow<GlassesState> = _state

    /** A temple-button gesture reached the phone; the string says which event carried it. */
    private val _buttons = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val buttons: SharedFlow<String> = _buttons

    private val _log = MutableSharedFlow<String>(extraBufferCapacity = 64)
    val log: SharedFlow<String> = _log

    private var connection: PeripheralConnectionManager? = null
    private var client: SmartWearModelClient? = null
    private var fpsJob: Job? = null
    private var startTimeout: Job? = null
    private var playerStarted = false
    private var connectTimeout: Job? = null

    init {
        // The glasses' AI-assistant press also makes the SDK play tones on the phone; silence them.
        runCatching {
            val sp = AISoundPool.getInstance()
            sp.init(app)
            sp.setStartConversationSound(app, AISoundPool.MUTE_SOUND)
            sp.setStopConversationSound(app, AISoundPool.MUTE_SOUND)
            sp.setAIThinkingSound(app, AISoundPool.MUTE_SOUND)
            sp.setAIConnectedSound(app, AISoundPool.MUTE_SOUND)
            sp.setDeviceBusySound(app, AISoundPool.MUTE_SOUND)
            sp.setTakePhotoSound(app, AISoundPool.MUTE_SOUND)
        }.onFailure { say("could not mute SDK tones: $it") }
    }

    // MARK: - Connection

    /** Paired devices, AiSee-looking ones first. The glasses must be paired in Bluetooth settings first. */
    @SuppressLint("MissingPermission")
    fun bondedDevices(): List<BondedGlasses> {
        val adapter = app.getSystemService(BluetoothManager::class.java)?.adapter ?: return emptyList()
        return runCatching {
            adapter.bondedDevices.map { BondedGlasses(it.address, it.name ?: it.address) }
                .sortedWith(compareBy({ !looksLikeGlasses(it.name) }, { it.name }))
        }.getOrElse { say("bonded devices unavailable: ${it.message}"); emptyList() }
    }

    fun connect(address: String, name: String) {
        disconnectQuietly()
        prefs.edit().putString(KEY_ADDRESS, address).putString(KEY_NAME, name).apply()
        _state.update { it.copy(link = Link.CONNECTING, address = address, name = name, error = null, battery = null) }
        say("connecting to $name ($address)")
        val mgr = MultiPeripheralConnectionManager.getInstance(app).getPeripheralConnectionManager(address)
        connection = mgr
        mgr.registerVendorModelCallback(vendorCallback)
        if (mgr.isConnected) {
            onLinkReady(address)
            return
        }
        val peripheral = PeripheralParameters.Builder()
            .syncDataWhenConnected(true)
            .connectA2dp(true)
            .listenHfp(true)
            .build()
        val params = ConnectionParameters.Builder(address)
            .channelType(ConnectionParameters.CHANNEL_TYPE_SPP)
            .peripheralParameters(peripheral)
            .build()
        val result = mgr.startConnect(params)
        say("startConnect → $result")
        connectTimeout?.cancel()
        connectTimeout = scope.launch {
            delay(25_000)
            if (_state.value.link == Link.CONNECTING) {
                say("connect timed out")
                disconnectQuietly()
                _state.update { it.copy(link = Link.DISCONNECTED, error = "The glasses did not answer. Are they on and nearby?") }
            }
        }
    }

    /** Drops our SDK callbacks; call when the owner goes away. */
    fun release() {
        connectTimeout?.cancel()
        startTimeout?.cancel()
        stopFps()
        disconnectQuietly()
    }

    /** Reconnects to the glasses used last time, if any. */
    fun reconnectLast() {
        val address = prefs.getString(KEY_ADDRESS, null) ?: return
        if (_state.value.link != Link.DISCONNECTED) return
        connect(address, prefs.getString(KEY_NAME, null) ?: address)
    }

    fun disconnect() {
        if (_state.value.stream != Stream.OFF) stopStream()
        val err = client?.connectionManager?.disconnect() ?: connection?.disconnect()
        say("disconnect → ${err?.code}")
        disconnectQuietly()
        _state.update { it.copy(link = Link.DISCONNECTED, battery = null, stream = Stream.OFF, fps = 0) }
    }

    private fun disconnectQuietly() {
        client?.unregisterCallback(modelCallback)
        client?.connectionManager?.unregisterVendorModelCallback(vendorCallback)
        connection?.unregisterVendorModelCallback(vendorCallback)
        client = null
        connection = null
    }

    private fun onLinkReady(address: String) {
        connectTimeout?.cancel()
        val c = SmartWearModelProxy.getInstance().getModelClient(address)
        client = c
        c.registerCallback(modelCallback)
        _state.update { it.copy(link = Link.CONNECTED, error = null) }
        say("link ready; initialising glasses")
        c.initSmartWearDevice()
    }

    private val vendorCallback = object : VendorModelCallback() {
        override fun onStateChanged(state: Int) {
            super.onStateChanged(state)
            say("link state $state")
            when (state) {
                PeripheralConnectionManager.STATE_DATA_PREPARED -> main.post {
                    _state.value.address?.let { if (client == null) onLinkReady(it) }
                }
                PeripheralConnectionManager.STATE_DEVICE_DISCONNECTED -> main.post {
                    // The glasses are gone; tear down our side of the stream (player
                    // service, its Wi-Fi request, the frame tap) without talking to them.
                    connectTimeout?.cancel()
                    teardownLocal()
                    _state.update { it.copy(link = Link.DISCONNECTED, battery = null) }
                    disconnectQuietly()
                }
                PeripheralConnectionManager.STATE_DATA_SYNC_FAILED -> _state.update {
                    it.copy(error = "Bluetooth link set up but the data sync failed; try again")
                }
            }
        }

        override fun onDeviceInfoChanged(indicator: Int, deviceInfo: DeviceInfo) {
            super.onDeviceInfoChanged(indicator, deviceInfo)
            if (indicator == DeviceInfo.INDICATOR_BUD_INFO) {
                val level = runCatching { deviceInfo.deviceStatusInfo?.lchBatteryValue }.getOrNull()
                if (level != null && level in 0..100) _state.update { it.copy(battery = level) }
            }
        }

        override fun onKeyeventReported(keyEvent: Int) {
            super.onKeyeventReported(keyEvent)
            say("key event $keyEvent")
        }
    }

    private val modelCallback = object : SmartWearModelCallback() {
        override fun onSmartWearDeviceInitSuccess() {
            super.onSmartWearDeviceInitSuccess()
            say("glasses initialised")
            _state.update { it.copy(link = Link.READY) }
            client?.getBudInfo()
            client?.getDeviceBatteryInfo()
        }

        override fun onSmartWearDeviceInitFail() {
            super.onSmartWearDeviceInitFail()
            say("glasses init failed")
            // Still usable for streaming in the reference app; keep going.
            _state.update { it.copy(link = Link.READY, error = "Glasses reported an init failure") }
        }

        override fun onReceivedDeviceBatteryInfo(primaryBattery: Int, secondaryBattery: Int) {
            super.onReceivedDeviceBatteryInfo(primaryBattery, secondaryBattery)
            if (primaryBattery in 0..100) _state.update { it.copy(battery = primaryBattery) }
        }

        override fun onStartLiveStreaming(liveChannel: Byte, startResult: Boolean, wifiAccessInfo: WifiAccessInfo?) {
            super.onStartLiveStreaming(liveChannel, startResult, wifiAccessInfo)
            say("onStartLiveStreaming channel=$liveChannel ok=$startResult ssid=${wifiAccessInfo?.ssid}")
            main.post {
                if (!startResult) {
                    if (_state.value.stream != Stream.STARTING) return@post
                    // The glasses may already have their hotspot up; turn it off again.
                    stopStream()
                    _state.update {
                        it.copy(error = "The phone could not join the glasses' Wi-Fi. Keep this app on screen, " +
                            "tap Connect on the system prompt, and make sure Wi-Fi is switched on.")
                    }
                    return@post
                }
                // A late answer after Stop or the timeout must not restart anything.
                if (_state.value.stream != Stream.STARTING) return@post
                if (liveChannel == LiveStreamingConfigInfo.LiveStreamingChannel.WIFI_AP) startPlayer()
            }
        }

        // The glasses' firmware turns the assistant press into a voice session. We
        // are not a voice assistant: treat it as our button and end the session.
        override fun onStartReceiveUserVoice() {
            super.onStartReceiveUserVoice()
            say("button: voice session started")
            _buttons.tryEmit("voice")
            runCatching { client?.stopUserVoiceInput() }
        }

        override fun onDeviceTriggeredTakePhoto() {
            super.onDeviceTriggeredTakePhoto()
            say("button: take photo")
            _buttons.tryEmit("photo")
        }

        override fun onReceivedDeviceAction(actionType: Int) {
            super.onReceivedDeviceAction(actionType)
            say("button: device action $actionType")
            _buttons.tryEmit("action $actionType")
        }

        override fun onActionStateNotificationChanged(notification: ActionStateNotification) {
            super.onActionStateNotificationChanged(notification)
            say("action state $notification")
        }
    }

    // MARK: - Camera stream

    /** Must run while the app is in the foreground: Android only lets a foreground app join a Wi-Fi hotspot. */
    fun startStream(fps: Int = 30, kbps: Int = 1000) {
        val c = client ?: run { _state.update { it.copy(error = "Connect the glasses first") }; return }
        if (_state.value.stream == Stream.STARTING || _state.value.stream == Stream.PLAYING) return
        GlassesFrames.start()
        val cfg = LiveStreamingConfigInfo().apply {
            liveStreamingChannel = LiveStreamingConfigInfo.LiveStreamingChannel.WIFI_AP
            videoEncoding = LiveStreamingConfigInfo.VideoEncoding.H264
            videoPictureWidth = 1280
            videoPictureHeight = 720
            this.fps = fps
            bps = kbps * 1000
        }
        _state.update { it.copy(stream = Stream.STARTING, error = null) }
        say("starting camera stream: 720p $fps fps $kbps kbps")
        c.liveStreamingManager.startLiveStreaming(cfg)
        startTimeout?.cancel()
        startTimeout = scope.launch {
            delay(45_000)
            if (_state.value.stream == Stream.STARTING) {
                say("stream start timed out")
                stopStream()
                _state.update { it.copy(error = "The camera took too long to start; try again") }
            }
        }
    }

    private fun startPlayer() {
        val session = SessionConfig().apply {
            mSessionType = SessionConfig.SESSION_TYPE_PREVIEW
            mEnableMediaRecord = false
        }
        val intent = Intent(app, RTKMediaPlayerService::class.java)
            .setAction(RTKMediaPlayerService.ACTION_START)
            .putExtra(RTKMediaPlayerService.EXTRA_PLAY_PARAMS, session)
            .putExtra(RTKMediaPlayerService.EXTRA_PLAY_RESULT, playerResult)
        runCatching { app.startForegroundService(intent); playerStarted = true }
            .onFailure {
                say("player service failed to start: $it")
                stopStream()
                _state.update { s -> s.copy(error = "Video player could not start: ${it.message}") }
            }
    }

    private val playerResult = object : ResultReceiver(Handler(Looper.getMainLooper())) {
        override fun onReceiveResult(resultCode: Int, resultData: Bundle?) {
            say("player result $resultCode")
            when {
                resultCode == PlayerServiceContract.RESULT_SUCCESS -> {
                    if (_state.value.stream != Stream.STARTING) return
                    startTimeout?.cancel()
                    _state.update { it.copy(stream = Stream.PLAYING, error = null) }
                    startFps()
                }
                resultCode < 0 -> {
                    val why = runCatching { PlayerServiceContract.error2Str(resultCode) }.getOrDefault("$resultCode")
                    stopStream()
                    _state.update { it.copy(error = "Video player failed: $why") }
                }
            }
        }
    }

    fun stopStream() {
        _state.update { it.copy(stream = Stream.STOPPING) }
        say("stopping camera stream")
        teardownLocal()
    }

    /** Our side of the stream: player service, the SDK's Wi-Fi request, frame tap, fps counter. */
    private fun teardownLocal() {
        startTimeout?.cancel()
        stopFps()
        if (playerStarted) {
            playerStarted = false
            runCatching { app.startService(Intent(app, RTKMediaPlayerService::class.java).setAction(RTKMediaPlayerService.ACTION_STOP)) }
                .onFailure { say("player stop: $it") }
        }
        client?.liveStreamingManager?.let {
            runCatching { it.stopLiveStreaming(LiveStreamingConfigInfo.LiveStreamingChannel.WIFI_AP) }
            runCatching { it.release() }
        }
        GlassesFrames.stop()
        _state.update { it.copy(stream = Stream.OFF, fps = 0) }
    }

    private fun startFps() {
        fpsJob?.cancel()
        fpsJob = scope.launch {
            var last = GlassesFrames.frameCount
            while (true) {
                delay(1000)
                val now = GlassesFrames.frameCount
                _state.update { it.copy(fps = (now - last).toInt()) }
                last = now
            }
        }
    }

    private fun stopFps() {
        fpsJob?.cancel()
        fpsJob = null
    }

    private fun say(line: String) {
        Log.i(TAG, line)
        _log.tryEmit(line)
    }

    companion object {
        private const val TAG = "Glasses"
        private const val KEY_ADDRESS = "address"
        private const val KEY_NAME = "name"

        fun looksLikeGlasses(name: String) = name.contains("aisee", ignoreCase = true) ||
            name.contains("glass", ignoreCase = true) || name.startsWith("AI", ignoreCase = false)
    }
}
