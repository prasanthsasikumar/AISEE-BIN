package com.flowsxr.aiseebin

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.flowsxr.aiseebin.glasses.GlassesController
import com.flowsxr.aiseebin.glasses.GlassesFrames
import com.flowsxr.aiseebin.glasses.Stream
import com.flowsxr.aiseebin.immersal.AutoLocalizer
import com.flowsxr.aiseebin.immersal.CloudLocalizer
import com.flowsxr.aiseebin.immersal.GlassesCamera
import com.flowsxr.aiseebin.immersal.ImmersalMapCache
import com.flowsxr.aiseebin.immersal.ImmersalNative
import com.flowsxr.aiseebin.immersal.Localizer
import com.flowsxr.aiseebin.immersal.NativeLocalizer
import com.flowsxr.aiseebin.map.LocationDescriber
import com.flowsxr.aiseebin.map.MapRepository
import com.flowsxr.aiseebin.map.MapSummary
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.positioning.Fix
import com.flowsxr.aiseebin.positioning.GlassesPositioning
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class MapState(
    val available: List<MapSummary> = emptyList(),
    val selectedSlug: String? = null,
    val map: NavigationMap? = null,
    val loading: Boolean = false,
    val status: String? = null,
    /** Immersal map ids of the selected map that are cached on the phone. */
    val cached: List<Int> = emptyList(),
    val downloading: Boolean = false,
    /** The map came from the copy saved on the phone because the server was unreachable. */
    val offline: Boolean = false,
)

class AppModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("app", Context.MODE_PRIVATE)
    private val cache = ImmersalMapCache(app.filesDir)
    private val mapDir = java.io.File(app.filesDir, "maps")
    val speaker = Speaker(app)
    val glasses = GlassesController(app, viewModelScope)
    /** Debug: a still image fed to positioning in place of glasses frames. */
    @Volatile var frameOverride: com.flowsxr.aiseebin.immersal.GrayImage? = null
    private var fakeSeq = 0L
    val odometer = com.flowsxr.aiseebin.positioning.Odometer(app)
    val positioning = GlassesPositioning(viewModelScope, {
        frameOverride?.let { com.flowsxr.aiseebin.glasses.TimedFrame(it, ++fakeSeq, System.currentTimeMillis()) }
            ?: GlassesFrames.latest()
    }, app.getExternalFilesDir(null), walked = { odometer.walked })

    /** Speak exhibits and hazards on the way past (iOS ProximityAnnouncer). */
    private val _announcePlaces = MutableStateFlow(prefs.getBoolean(KEY_ANNOUNCE, true))
    val announcePlaces: StateFlow<Boolean> = _announcePlaces
    @Volatile private var announcer: com.flowsxr.aiseebin.positioning.ProximityAnnouncer? = null

    /** True while a positioning start is loading maps; the button stays disabled. */
    private val _starting = MutableStateFlow(false)
    val starting: StateFlow<Boolean> = _starting
    private var startJob: kotlinx.coroutines.Job? = null

    private val _maps = MutableStateFlow(MapState(selectedSlug = prefs.getString(KEY_MAP, null)))
    val maps: StateFlow<MapState> = _maps

    private val _log = MutableStateFlow<List<String>>(emptyList())
    val log: StateFlow<List<String>> = _log

    private val _spoken = MutableStateFlow<String?>(null)
    val spoken: StateFlow<String?> = _spoken

    /** Where localization runs, chosen in Settings. */
    enum class LocalizerMode(val label: String) { AUTO("Auto"), ON_PHONE("On phone"), SERVER("Immersal server") }

    private val _localizerMode = MutableStateFlow(
        runCatching { LocalizerMode.valueOf(prefs.getString(KEY_LOCALIZER, null) ?: "") }.getOrDefault(LocalizerMode.AUTO))
    val localizerMode: StateFlow<LocalizerMode> = _localizerMode

    fun setLocalizerMode(mode: LocalizerMode) {
        if (mode == _localizerMode.value) return
        _localizerMode.value = mode
        prefs.edit().putString(KEY_LOCALIZER, mode.name).apply()
        append("localization set to ${mode.label}")
        // A running session switches straight away.
        if (positioning.state.value.running) { stopPositioning(); startPositioning() }
    }

    private val _focalPx = MutableStateFlow(prefs.getFloat(KEY_FOCAL, GlassesCamera.DEFAULT_FOCAL_PX))
    val focalPx: StateFlow<Float> = _focalPx

    private val _tokenOverride = MutableStateFlow(prefs.getString(KEY_TOKEN, "") ?: "")
    val tokenOverride: StateFlow<String> = _tokenOverride

    val hasBuiltInToken: Boolean get() = BuildConfig.IMMERSAL_TOKEN.isNotBlank()
    val nativeAvailable: Boolean get() = ImmersalNative.available
    private val token: String get() = _tokenOverride.value.trim().ifEmpty { BuildConfig.IMMERSAL_TOKEN }

    private var announcedFirstFix = false
    // Declared before init: init already logs.
    private val clock = java.time.format.DateTimeFormatter.ofPattern("MM-dd HH:mm:ss")
    /** Also kept on disk for after a walk: `adb pull /sdcard/Android/data/com.flowsxr.aiseebin/files/diag.log`. */
    private val diagFile = app.getExternalFilesDir(null)?.let { java.io.File(it, "diag.log") }

    init {
        viewModelScope.launch { glasses.log.collect { append("glasses: $it") } }
        viewModelScope.launch { glasses.buttons.collect { whereAmI(trigger = "button ($it)") } }
        positioning.onAttempt = { append(it) }
        // The stream dropping (link loss, player failure, stop) ends positioning too.
        viewModelScope.launch {
            glasses.state.collect { g ->
                if (g.stream != Stream.PLAYING && frameOverride == null && (positioning.state.value.running || startJob?.isActive == true)) {
                    cancelStart()
                    positioning.stop()
                    append("positioning stopped: camera is ${g.stream.name.lowercase()}")
                }
            }
        }
        positioning.onFix = { fix ->
            if (!announcedFirstFix) {
                announcedFirstFix = true
                viewModelScope.launch { describe(fix)?.let { speak("Located. $it") } }
            }
            val passing = if (_announcePlaces.value) announcer?.update(fix.position, fix.heading).orEmpty() else emptyList()
            if (passing.isNotEmpty()) viewModelScope.launch {
                for (a in passing) {
                    val hazard = a.poi.category == com.flowsxr.aiseebin.map.PoiCategory.HAZARD
                    append("announce ${a.poi.name} (%.1f m, radius %.1f m)".format(a.distance, a.poi.announceRadius))
                    if (hazard) buzzWarning()
                    // Hazards cut in; exhibits wait their turn, as on iOS.
                    speak(a.spokenText, interrupt = hazard)
                }
            }
        }
        viewModelScope.launch {
            positioning.state.collect { if (!it.running) odometer.stop() }
        }
        append("native Immersal plugin: ${if (ImmersalNative.available) "available" else "missing (cloud only)"}")
        append("built-in Immersal token: ${if (hasBuiltInToken) "yes" else "no"}")
        refreshMaps()
        glasses.reconnectLast()
    }

    // MARK: - Maps

    fun refreshMaps() {
        _maps.update { it.copy(loading = true, status = "Loading maps from the server…") }
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { MapRepository.list(mapDir) } }
            result.onSuccess { (list, offline) ->
                _maps.update { it.copy(available = list, loading = false, offline = offline, status = null) }
                if (offline) append("map server unreachable: using the map list saved on this phone")
                append("server maps: ${list.joinToString { "${it.slug}${if (it.immersalMapIds.isEmpty()) "" else it.immersalMapIds}" }}")
                val pick = _maps.value.selectedSlug?.takeIf { s -> list.any { it.slug == s } }
                    ?: list.firstOrNull { it.immersalMapIds.isNotEmpty() }?.slug
                if (pick != null && _maps.value.map == null) selectMap(pick)
            }.onFailure { e ->
                _maps.update { it.copy(loading = false, status = "Could not reach the map server: ${e.message}") }
                append("map list failed: $e")
                // The last map used may still be saved on the phone.
                _maps.value.selectedSlug?.let { if (_maps.value.map == null) selectMap(it) }
            }
        }
    }

    fun selectMap(slug: String) {
        cancelStart()
        positioning.stop()
        prefs.edit().putString(KEY_MAP, slug).apply()
        _maps.update { it.copy(selectedSlug = slug, map = null, loading = true, status = "Loading $slug…") }
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { MapRepository.load(slug, mapDir) } }
            result.onSuccess { (map, offline) ->
                if (offline) append("map server unreachable: using the copy of $slug saved on this phone")
                announcer = com.flowsxr.aiseebin.positioning.ProximityAnnouncer(map.pois)
                val ids = map.alignment?.mapIds.orEmpty()
                _maps.update {
                    it.copy(map = map, loading = false, offline = offline, cached = ids.filter(cache::has),
                        status = if (ids.isEmpty()) "This map has no Immersal alignment, so the glasses cannot position in it." else null)
                }
                append("loaded map ${map.name}: ${map.pois.size} places, Immersal $ids")
                if (!offline && ids.any { !cache.has(it) }) downloadMaps()
            }.onFailure { e ->
                _maps.update { it.copy(loading = false, status = "Could not load $slug: ${e.message}") }
                append("map load failed: $e")
            }
        }
    }

    /** Fetches the selected map's Immersal files for on-device localization. Needs internet. */
    fun downloadMaps() {
        val ids = _maps.value.map?.alignment?.mapIds.orEmpty()
        if (ids.isEmpty() || token.isBlank() || _maps.value.downloading) return
        _maps.update { it.copy(downloading = true) }
        viewModelScope.launch {
            for (id in ids) {
                if (cache.has(id)) continue
                val error = withContext(Dispatchers.IO) { cache.download(token, id) }
                append(if (error == null) "Immersal map $id cached on this phone" else "Immersal map $id not cached: $error")
            }
            _maps.update { it.copy(downloading = false, cached = ids.filter(cache::has)) }
        }
    }

    // MARK: - Positioning

    fun startPositioning() {
        val map = _maps.value.map ?: return append("no map loaded")
        val alignment = map.alignment?.takeIf { it.mapIds.isNotEmpty() } ?: return append("map has no Immersal alignment")
        if (startJob?.isActive == true) return
        announcedFirstFix = false
        _starting.value = true
        startJob = viewModelScope.launch {
            try {
                val localizer = withContext(Dispatchers.IO) { chooseLocalizer(alignment.mapIds) } ?: return@launch
                // A stop, camera stop or map switch while the maps loaded wins.
                if (!isActive || _maps.value.map !== map) {
                    Thread({ localizer.close() }, "localizer-close").start()
                    append("positioning start abandoned")
                    return@launch
                }
                announcer = com.flowsxr.aiseebin.positioning.ProximityAnnouncer(map.pois)
                odometer.start()
                append("walked distance from the ${odometer.source}")
                positioning.start(localizer, alignment, GlassesCamera(_focalPx.value))
                append("positioning started (${localizer.label}, focal ${_focalPx.value.toInt()} px)")
            } finally {
                _starting.value = false
            }
        }
    }

    private fun cancelStart() {
        startJob?.cancel()
        startJob = null
        _starting.value = false
    }

    private fun chooseLocalizer(ids: List<Int>): Localizer? {
        val cloud = token.takeIf { it.isNotBlank() }?.let { CloudLocalizer(it, ids) }
        when (_localizerMode.value) {
            LocalizerMode.SERVER -> {
                if (cloud == null) { append("localizer: none — Immersal server chosen but no token"); return null }
                append("localizer: Immersal server (chosen in Settings)")
                return cloud
            }
            LocalizerMode.ON_PHONE -> {
                val (native, why) = NativeLocalizer.open(ids, cache)
                if (native != null) { append("localizer: on phone (chosen in Settings), $why"); return native }
                append("localizer: on phone chosen but $why; using the server")
                return cloud
            }
            LocalizerMode.AUTO -> Unit
        }
        val (native, why) = NativeLocalizer.open(ids, cache)
        if (native == null && cloud == null) { append("localizer: none — no token and $why"); return null }
        append("localizer: auto (on-device ${if (native != null) "ready" else "unavailable: $why"}, cloud ${if (cloud != null) "ready" else "no token"})")
        return AutoLocalizer(cloud, native, ::hasInternet)
    }

    /** Whether the default network (not the glasses' hotspot, which the SDK requests separately) reaches the internet. */
    private fun hasInternet(): Boolean {
        val cm = getApplication<Application>().getSystemService(android.net.ConnectivityManager::class.java) ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    /** Debug: both localizers on a synthetic frame, to prove the plumbing (expect "no match"). */
    fun selfTest(pattern: String = "checker") {
        val ids = _maps.value.map?.alignment?.mapIds.orEmpty()
        if (ids.isEmpty()) return append("selftest: no map with Immersal ids")
        viewModelScope.launch(Dispatchers.IO) {
            val frame = testFrame(pattern) ?: return@launch append("selftest: no frame for '$pattern'")
            val w = frame.width; val h = frame.height
            append("selftest '$pattern' ${w}x$h")
            val k = GlassesCamera(_focalPx.value).intrinsics(w, h)
            val (native, why) = NativeLocalizer.open(ids, cache)
            if (native != null) {
                val r = native.localize(frame, k)
                append("selftest native: success=${r.success} error=${r.error} ${r.latencyMs} ms")
                native.close()
            } else append("selftest native: unavailable ($why)")
            if (token.isNotBlank()) {
                val r = CloudLocalizer(token, ids).localize(frame, k)
                append("selftest cloud: success=${r.success} error=${r.error} ${r.latencyMs} ms ${r.requestBytes} B")
            }
        }
    }

    fun fakeFrames(pattern: String?) {
        viewModelScope.launch(Dispatchers.IO) {
            frameOverride = pattern?.let { testFrame(it) }
            append("debug: fake frames ${pattern ?: "off"} → ${frameOverride?.let { "${it.width}x${it.height}" } ?: "none"}")
        }
    }

    internal fun testFrame(pattern: String): com.flowsxr.aiseebin.immersal.GrayImage? {
        val w = 960; val h = 540
        return when (pattern) {
            "flat" -> com.flowsxr.aiseebin.immersal.GrayImage(w, h, ByteArray(w * h) { 128.toByte() })
            "noise" -> java.util.Random(1).let { r -> com.flowsxr.aiseebin.immersal.GrayImage(w, h, ByteArray(w * h) { r.nextInt(256).toByte() }) }
            "file" -> {
                val f = java.io.File(getApplication<Application>().getExternalFilesDir(null), "test.png")
                val bmp = android.graphics.BitmapFactory.decodeFile(f.path) ?: return null
                val px = IntArray(bmp.width * bmp.height).also { bmp.getPixels(it, 0, bmp.width, 0, 0, bmp.width, bmp.height) }
                val gray = ByteArray(px.size) { i ->
                    val c = px[i]
                    (((c shr 16 and 0xFF) * 77 + (c shr 8 and 0xFF) * 150 + (c and 0xFF) * 29) shr 8).toByte()
                }
                com.flowsxr.aiseebin.immersal.GrayImage(bmp.width, bmp.height, gray).scaledToWidth(960)
            }
            else -> com.flowsxr.aiseebin.immersal.GrayImage(w, h, ByteArray(w * h) { i -> (((i % w) / 40 + (i / w) / 40) % 2 * 200 + 20).toByte() })
        }
    }

    fun stopPositioning() {
        cancelStart()
        positioning.stop()
        append("positioning stopped")
    }

    fun whereAmI(trigger: String = "screen") {
        val fix = positioning.state.value.lastFix
        val text = when {
            fix == null -> if (positioning.state.value.running) "No position yet. Look around slowly." else "Positioning is off."
            else -> {
                val age = (System.currentTimeMillis() - fix.atMillis) / 1000
                val base = describe(fix) ?: "Position known, but this map has no named places."
                if (age > STALE_SECONDS) "$base That was $age seconds ago." else base
            }
        }
        append("where am I ($trigger): $text")
        speak(text)
    }

    private fun describe(fix: Fix): String? = _maps.value.map?.let { LocationDescriber(it).describe(fix.position, fix.heading) }

    private fun speak(text: String, interrupt: Boolean = true) {
        _spoken.value = text
        speaker.say(text, interrupt)
    }

    private fun buzzWarning() {
        val vibrator = getApplication<Application>().getSystemService(android.os.Vibrator::class.java) ?: return
        runCatching { vibrator.vibrate(android.os.VibrationEffect.createWaveform(longArrayOf(0, 120, 80, 120, 80, 250), -1)) }
    }

    /** Debug: behave as if positioning produced this fix (announcements, where-am-I). */
    fun injectFix(x: Float, z: Float, heading: Float) {
        val fix = Fix(com.flowsxr.aiseebin.map.Vec2(x, z), heading, System.currentTimeMillis(), null)
        append("debug: injected fix x=$x z=$z heading=$heading")
        positioning.onFix?.invoke(fix)
    }

    fun setAnnouncePlaces(on: Boolean) {
        _announcePlaces.value = on
        prefs.edit().putBoolean(KEY_ANNOUNCE, on).apply()
    }

    // MARK: - Glasses

    fun startCamera() = glasses.startStream()

    fun stopCamera() {
        cancelStart()
        positioning.stop()
        glasses.stopStream()
    }

    val streaming: Boolean get() = glasses.state.value.stream == Stream.PLAYING

    // MARK: - Settings

    fun setFocal(px: Float) {
        _focalPx.value = px
        prefs.edit().putFloat(KEY_FOCAL, px).apply()
    }

    fun setTokenOverride(value: String) {
        _tokenOverride.value = value
        prefs.edit().putString(KEY_TOKEN, value).apply()
    }

    // MARK: - Log

    fun append(line: String) {
        val stamped = "${java.time.LocalDateTime.now().format(clock)} $line"
        android.util.Log.i("AISEEBIN", line)
        _log.update { (it + stamped).takeLast(120) }
        diagFile?.let { f ->
            runCatching {
                synchronized(f) {
                    if (f.length() > 2_000_000) f.renameTo(java.io.File(f.parentFile, "diag.old.log"))
                    f.appendText("$stamped\n")
                }
            }
        }
    }

    override fun onCleared() {
        cancelStart()
        positioning.stop()
        glasses.stopStream()
        glasses.release()
        speaker.shutdown()
        super.onCleared()
    }

    companion object {
        private const val KEY_MAP = "map.slug"
        private const val KEY_FOCAL = "glasses.focalPx"
        private const val KEY_TOKEN = "immersal.token"
        private const val KEY_ANNOUNCE = "announce.places"
        private const val KEY_LOCALIZER = "immersal.localizerMode"
        private const val STALE_SECONDS = 10
    }
}
