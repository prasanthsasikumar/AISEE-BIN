package com.flowsxr.aiseebin.nus

import android.app.Application
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.flowsxr.aiseebin.BuildConfig
import com.flowsxr.aiseebin.Haptics
import com.flowsxr.aiseebin.Speaker
import com.flowsxr.aiseebin.immersal.AriaServerLocalizer
import com.flowsxr.aiseebin.immersal.AutoLocalizer
import com.flowsxr.aiseebin.immersal.CloudLocalizer
import com.flowsxr.aiseebin.immersal.ImmersalMapCache
import com.flowsxr.aiseebin.immersal.Localizer
import com.flowsxr.aiseebin.immersal.NativeLocalizer
import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.ImmersalAlignment
import com.flowsxr.aiseebin.map.MapRepository
import com.flowsxr.aiseebin.map.MapSummary
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.PoiCategory
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.phone.ArCamera
import com.flowsxr.aiseebin.phone.ArSupport
import com.flowsxr.aiseebin.positioning.Fix
import com.flowsxr.aiseebin.positioning.FloorPose
import com.flowsxr.aiseebin.positioning.LocAttempt
import com.flowsxr.aiseebin.positioning.PhonePositioning
import com.flowsxr.aiseebin.positioning.ProximityAnnouncer
import com.flowsxr.aiseebin.route.GuidanceCue
import com.flowsxr.aiseebin.route.GuidancePolicy
import com.flowsxr.aiseebin.route.GuidanceThresholds
import com.flowsxr.aiseebin.route.NavigationInstruction
import com.flowsxr.aiseebin.route.RouteEvent
import com.flowsxr.aiseebin.route.RouteGraph
import com.flowsxr.aiseebin.route.RouteTracker
import com.flowsxr.aiseebin.route.TurnDirection
import com.flowsxr.aiseebin.usage.APP_PREFS
import com.flowsxr.aiseebin.usage.PoseSampler
import com.flowsxr.aiseebin.usage.Usage
import com.flowsxr.aiseebin.usage.usageArTracking
import com.flowsxr.aiseebin.usage.usageData
import com.flowsxr.aiseebin.usage.usageLocalizerName
import com.flowsxr.aiseebin.usage.usagePose
import com.flowsxr.aiseebin.usageSessionContext
import com.google.ar.core.Frame
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import kotlin.math.roundToInt

/** Where the building map stands against the server, for the home screen and the staff screen. */
sealed interface MapSync {
    data object Idle : MapSync
    data object Checking : MapSync
    data class UpToDate(val version: Int?) : MapSync
    data class Updated(val version: Int?) : MapSync
    /** The copy saved on the phone is in use because the server could not be reached. */
    data object Offline : MapSync
    data class Failed(val reason: String) : MapSync
    /** The server answered, and has no map named `nus-…`. */
    data object NonePublished : MapSync

    val label: String
        get() = when (this) {
            Idle -> ""
            Checking -> "Checking for a newer map…"
            is UpToDate -> "Up to date" + (version?.let { " (v$it)" } ?: "")
            is Updated -> "Updated" + (version?.let { " to v$it" } ?: "")
            Offline -> "Offline: using the map saved on this phone"
            is Failed -> "Couldn't get the map: $reason"
            NonePublished -> "No building map has been published yet."
        }
}

data class NusMaps(
    val available: List<MapSummary> = emptyList(),
    val slug: String? = null,
    val version: Int? = null,
    val map: NavigationMap? = null,
    val graph: RouteGraph? = null,
    val sync: MapSync = MapSync.Idle,
    val listing: Boolean = false,
    val listError: String? = null,
    /** The map being switched to from the staff screen. */
    val switchingTo: String? = null,
)

/** The active route, as the screen and the camera view read it. */
data class NavState(
    val navigating: Boolean = false,
    /** Route node ids, start to destination. */
    val path: List<String> = emptyList(),
    /** 1-based leg the visitor is on; 0 with no route. */
    val leg: Int = 0,
    val instruction: NavigationInstruction? = null,
    val remaining: Float = 0f,
    val offRoute: Boolean = false,
    /** Why a route could not be made, for the card. */
    val problem: String? = null,
)

/**
 * NUS Computing Tour: the AISEE-BIN positioning and routing with a tour of the
 * locations and the way drawn on the camera view. The Android half of iOS
 * `NavigationViewModel` as the NUS app uses it: the phone camera only, no
 * authoring, voice off unless the visitor turns it on.
 */
class NusModel(app: Application) : AndroidViewModel(app), TourHost {
    private val prefs = app.getSharedPreferences(APP_PREFS, Context.MODE_PRIVATE)
    private val mapDir = File(app.filesDir, "maps")
    private val cache = ImmersalMapCache(app.filesDir)
    private val speaker = Speaker(app)
    private val haptics = Haptics(app)

    /** The phone's camera with ARCore, as iOS uses ARKit. */
    val ar = ArCamera(app)
    val phone = PhonePositioning(viewModelScope)
    val guide = TourGuide(this, viewModelScope)

    private val _maps = MutableStateFlow(NusMaps(slug = prefs.getString(KEY_MAP, null)))
    val maps: StateFlow<NusMaps> = _maps

    private val _pose = MutableStateFlow<MapPose?>(null)
    /** The visitor on the map, or null while the phone does not know where it is. */
    val mapPose: StateFlow<MapPose?> = _pose

    private val _nav = MutableStateFlow(NavState())
    val nav: StateFlow<NavState> = _nav

    /** Spoken guidance on or off (off by default: the halls are loud and shared). */
    private val _voiceOn = MutableStateFlow(prefs.getBoolean(KEY_VOICE, false))
    val voiceOn: StateFlow<Boolean> = _voiceOn

    /** The welcome screen has been seen (it is shown once, on the first launch). */
    private val _introSeen = MutableStateFlow(prefs.getBoolean(KEY_INTRO, false))
    val introSeen: StateFlow<Boolean> = _introSeen

    fun finishIntro() {
        log("intro.done", JSONObject().put("first", !_introSeen.value))
        _introSeen.value = true
        prefs.edit().putBoolean(KEY_INTRO, true).apply()
    }

    fun setVoice(on: Boolean) {
        _voiceOn.value = on
        prefs.edit().putBoolean(KEY_VOICE, on).apply()
        if (!on) speaker.stop()
    }

    /** Where the fixes come from this run, for the staff screen ("aria server", "cloud", …). */
    private val _localizer = MutableStateFlow<String?>(null)
    val localizer: StateFlow<String?> = _localizer
    /** Why positioning could not start, for the staff screen. */
    private val _positioningProblem = MutableStateFlow<String?>(null)
    val positioningProblem: StateFlow<String?> = _positioningProblem

    // Route state: main thread only.
    private var tracker: RouteTracker? = null
    private val thresholds = GuidanceThresholds()
    private val policy = GuidancePolicy(thresholds)
    private var destination: NavigationPoi? = null
    private var pendingDestinationId: String? = null
    private var lastInstruction: NavigationInstruction? = null
    private var routeStartedAt = 0L
    private var walkedOnRoute = 0f
    private var lastWalkSample: Vec2? = null
    private var announcer: ProximityAnnouncer? = null
    private var saidFoundYou = false
    private var startJob: Job? = null
    private var downloadJob: Job? = null

    // Usage logging state. Fixes arrive on the main thread, ARCore frames on the GL thread.
    private val poseSampler = PoseSampler()
    @Volatile private var arTracking = "none"
    private var arTrackingLogged: Pair<String, String?>? = null
    private var loggedPositioning = false
    private var loggedLocalizer = ""
    /** The camera's pose in ARCore's own frame, for the debug "stand at" command. */
    @Volatile private var lastSession: FloorPose? = null

    init {
        ar.log = ::append
        phone.onFix = ::handleFix
        phone.onAttempt = ::append
        phone.onLocAttempt = ::logLocAttempt
        viewModelScope.launch {
            // ARCore may still be checking at start-up.
            repeat(20) { ar.checkSupport(); if (ar.support.value != ArSupport.CHECKING) return@launch; delay(300) }
        }
        viewModelScope.launch {
            phone.state.collect { s ->
                val reliable = s.running && s.anchored && s.tracking == null
                if (reliable && !saidFoundYou) {
                    saidFoundYou = true
                    speaker.say("Found you.", interrupt = true)
                }
                if (!reliable) {
                    positionLost()
                    if (s.running) warnTrackingLost()
                }
            }
        }
        Usage.record("mode.enter", usageData("mode" to MODE))
        Usage.onNewSession { logSessionContext() }
        refreshMaps()
    }

    // MARK: - Tour host

    /**
     * The locations in the order they were marked on the map (the tour order).
     * The tour's start point, if set, is not a stop.
     */
    override val places: List<NavigationPoi>
        get() = _maps.value.map?.let { map -> map.pois.filter { it.isDestination && it.id != map.tourStart } }.orEmpty()

    override val pose: MapPose? get() = _pose.value
    override val graph: RouteGraph? get() = _maps.value.graph

    override fun log(type: String, data: JSONObject) = Usage.record(type, data)

    // MARK: - Maps

    /**
     * Lists the published `nus-` maps and loads this phone's: the one chosen on
     * the staff screen, else the NUS default. A newer version on the server
     * replaces the one in memory.
     */
    fun refreshMaps() {
        _maps.update { it.copy(listing = true, listError = null, sync = MapSync.Checking) }
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { MapRepository.list(mapDir) } }
            result.onSuccess { (list, offline) ->
                _maps.update { it.copy(available = list, listing = false) }
                val now = _maps.value
                val pick = now.slug?.takeIf { s -> list.any { it.slug == s } } ?: MapRepository.nusStarterSlug(list)
                val version = list.firstOrNull { it.slug == pick }?.version
                when {
                    pick == null -> _maps.update { it.copy(sync = if (now.map != null) MapSync.Offline else MapSync.NonePublished) }
                    now.map != null && now.slug == pick && (offline || now.version == version) ->
                        _maps.update { it.copy(sync = if (offline) MapSync.Offline else MapSync.UpToDate(version)) }
                    else -> load(pick)
                }
            }.onFailure { e ->
                val reason = e.message ?: e.javaClass.simpleName
                append("map list failed: $e")
                logError("map.list", e)
                _maps.update { it.copy(listing = false, listError = reason, sync = MapSync.Failed(reason)) }
                // The last map used may still be saved on the phone.
                val saved = _maps.value.slug
                if (_maps.value.map == null && saved != null) load(saved)
            }
        }
    }

    /** Staff screen: use another published map. Ends whatever tour is running. */
    fun switchMap(slug: String) {
        if (_maps.value.switchingTo != null) return
        _maps.update { it.copy(switchingTo = slug) }
        guide.exit()
        load(slug)
    }

    private fun load(slug: String) {
        val loadStart = System.currentTimeMillis()
        val before = _maps.value
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { runCatching { MapRepository.load(slug, mapDir) } }
            result.onSuccess { (map, offline) ->
                // A different map (or a newer version of this one) changes the ground under a tour.
                if (before.map != null) guide.exit()
                stopNavigation("map_change")
                stopPositioning()
                val version = _maps.value.available.firstOrNull { it.slug == slug }?.version
                prefs.edit().putString(KEY_MAP, slug).apply()
                _maps.update {
                    it.copy(slug = slug, version = version, map = map, graph = RouteGraph(map), switchingTo = null,
                        sync = when {
                            offline -> MapSync.Offline
                            before.map != null && before.slug == slug -> MapSync.Updated(version)
                            else -> MapSync.UpToDate(version)
                        })
                }
                announcer = ProximityAnnouncer(map.pois)
                append("loaded map ${map.name} ($slug v$version): ${map.pois.size} nodes, ${places.size} stops")
                Usage.record("map.loaded", usageData("slug" to slug, "version" to version, "name" to map.name,
                    "source" to if (offline) "cache" else "network", "ms" to System.currentTimeMillis() - loadStart))
                startPositioning()
            }.onFailure { e ->
                val reason = e.message ?: e.javaClass.simpleName
                append("map load failed: $e")
                logError("map.switch", e)
                _maps.update { it.copy(switchingTo = null, sync = MapSync.Failed(reason)) }
            }
        }
    }

    // MARK: - Positioning

    /** Starts finding the phone in the loaded map. The camera view feeds it frames once it is on screen. */
    fun startPositioning() {
        val map = _maps.value.map ?: return
        val alignment = map.alignment?.takeIf { it.mapIds.isNotEmpty() }
        if (alignment == null) {
            _positioningProblem.value = "This map has nothing to position against."
            return append("map has no alignment: positioning cannot start")
        }
        if (startJob?.isActive == true || phone.state.value.running) return
        startJob = viewModelScope.launch {
            val localizer = withContext(Dispatchers.IO) { chooseLocalizer(alignment) } ?: return@launch
            // A stop or a map switch while the maps loaded wins.
            if (!isActive || _maps.value.map !== map) {
                Thread({ localizer.close() }, "localizer-close").start()
                return@launch
            }
            saidFoundYou = false
            _positioningProblem.value = null
            _localizer.value = localizer.label
            phone.start(localizer, alignment)
            logPositioningStart(localizer.label)
            append("positioning started with the phone camera (${localizer.label})")
        }
    }

    private fun stopPositioning() {
        startJob?.cancel()
        startJob = null
        logPositioningStop()
        phone.stop()
        positionLost()
    }

    /** Staff screen: start over, as if the app had just opened on this map. */
    fun restartPositioning() {
        stopPositioning()
        startPositioning()
    }

    /**
     * An Aria map answers from the Aria map server: no token, nothing to
     * download. Any other map is an Immersal one: on the phone when its maps
     * are cached, else Immersal's cloud; missing maps are fetched and
     * positioning restarts with them.
     */
    private fun chooseLocalizer(alignment: ImmersalAlignment): Localizer? {
        val ids = alignment.mapIds
        if (alignment.ariaServer != null) {
            val aria = AriaServerLocalizer(alignment.ariaServer, ids)
            append("localizer: Aria map server ${aria.endpoint}")
            return aria
        }
        val token = BuildConfig.IMMERSAL_TOKEN
        val cloud = token.takeIf { it.isNotBlank() }?.let { CloudLocalizer(it, ids) }
        val (native, why) = NativeLocalizer.open(ids, cache)
        if (native == null && cloud == null) {
            _positioningProblem.value = "This build has no Immersal token."
            append("localizer: none — no token and $why")
            return null
        }
        append("localizer: on-device ${if (native != null) "ready" else "unavailable: $why"}, cloud ${if (cloud != null) "ready" else "no token"}")
        if (native == null && token.isNotBlank()) fetchImmersalMaps(ids, token)
        return AutoLocalizer(cloud, native, ::hasInternet)
    }

    /** Fetches the Immersal maps for on-phone localizing (the cloud takes at most 8 maps a request), then restarts with them. */
    private fun fetchImmersalMaps(ids: List<Int>, token: String) {
        if (downloadJob?.isActive == true) return
        val map = _maps.value.map
        downloadJob = viewModelScope.launch {
            var bytes = 0L; var fetched = 0; var firstError: String? = null
            val started = System.currentTimeMillis()
            for (id in ids) {
                if (cache.has(id)) continue
                val error = withContext(Dispatchers.IO) { cache.download(token, id) }
                fetched++
                if (error == null) bytes += cache.size(id) else if (firstError == null) firstError = error
            }
            if (fetched > 0) Usage.record("map.download", usageData("slug" to _maps.value.slug, "version" to _maps.value.version,
                "bytes" to bytes, "ms" to System.currentTimeMillis() - started, "ok" to (firstError == null), "error" to firstError))
            append(if (firstError == null) "Immersal maps cached on this phone" else "Immersal maps not cached: $firstError")
            if (firstError == null && _maps.value.map === map && ids.all(cache::has)) restartPositioning()
        }
    }

    private fun hasInternet(): Boolean {
        val cm = getApplication<Application>().getSystemService(ConnectivityManager::class.java) ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    /** Each ARCore frame (GL thread) feeds positioning while it runs. */
    fun onArFrame(frame: Frame) {
        if (!phone.state.value.running) return
        logArFrame(frame)
        val problem = ArCamera.problem(frame)
        val session = if (problem == null) ArCamera.floorPose(frame) else null
        lastSession = session
        phone.onFrame(session, problem, System.currentTimeMillis()) { ArCamera.shot(frame) }
    }

    /** The camera stopped (the app left the screen): the last position says nothing about now. */
    fun cameraPaused() {
        lastSession = null
        positionLost()
    }

    /** No trusted position: the map and arrows go, and a route in progress waits. Main thread. */
    private fun positionLost() {
        if (_pose.value == null) return
        _pose.value = null
        lastWalkSample = null
    }

    /** On a route with the camera lost: "Tracking lost…", at most every few seconds, when the visitor wants the voice. */
    private fun warnTrackingLost() {
        val instruction = lastInstruction ?: return
        if (tracker == null) return
        val cue = policy.evaluate(instruction, RouteEvent.None, isOffRoute = false, trackingReliable = false, now = seconds())
        if (cue != null && _voiceOn.value) deliver(cue)
    }

    // MARK: - Routes

    /** Starts a route to a place, waiting for a position first if need be. */
    override fun navigate(poiId: String) {
        val poi = graph?.node(poiId) ?: return
        stopNavigation("new_route")
        destination = poi
        if (_pose.value != null) {
            startNavigation()
        } else {
            pendingDestinationId = poiId
            if (_voiceOn.value) speaker.say("Okay, ${poi.name}. Waiting for tracking. Please look around slowly.", interrupt = true)
        }
    }

    override fun stopNavigation() = stopNavigation("user")

    /** [reason] is for `nav.cancel`: "user" unless the app ended the route itself ("map_change", "new_route"). */
    private fun stopNavigation(reason: String) {
        pendingDestinationId = null
        if (_nav.value.problem != null) _nav.value = NavState()
        if (tracker == null) return
        Usage.record("nav.cancel", routeSummary().put("reason", reason))
        tracker = null
        lastInstruction = null
        _nav.value = NavState()
        speaker.stop()
    }

    private fun startNavigation() {
        val destination = destination ?: return
        val graph = graph ?: return
        val pose = _pose.value ?: return
        val start = graph.nearestNode(pose.position, pose.height) ?: return
        val path = graph.findPath(start.id, destination.id)
        val newTracker = if (path.isEmpty()) null else RouteTracker(path, thresholds, graph.levels.heights, origin = pose.position)
        Usage.record("nav.request", usageData("to_id" to destination.id, "to_name" to destination.name,
            "path_m" to newTracker?.remainingDistance(pose.position)?.let(::cm)))
        if (newTracker == null) {
            // Distinguish "the map is broken" from "you are standing somewhere odd".
            val reason = if (graph.isConnected(destination.id))
                "You are nearest the ${start.name}, which is not connected to the ${destination.name} on this map."
            else "The ${destination.name} is not connected to any path on this map."
            _nav.value = NavState(problem = "No route to ${destination.name}. $reason")
            speaker.say("I could not find a route to the ${destination.name}. $reason Please connect it in the map editor.", interrupt = true)
            return
        }
        tracker = newTracker
        policy.reset()
        routeStartedAt = System.currentTimeMillis()
        walkedOnRoute = 0f
        lastWalkSample = null
        Usage.record("nav.start")
        lastInstruction = null
        val instruction = makeInstruction(pose)
        if (instruction == null) {
            finishNavigation()
            guide.arrived(destination.id)
            return
        }
        lastInstruction = instruction
        _nav.value = NavState(navigating = true, path = path.map { it.id }, leg = 1, instruction = instruction,
            remaining = newTracker.remainingDistance(pose.position))
        if (_voiceOn.value) speaker.say("Starting route to the ${destination.name}. ${instruction.spokenText}", interrupt = true)
    }

    /** A position from the phone camera, about five times a second while it is trusted. Main thread. */
    private fun handleFix(fix: Fix) {
        if (!phone.state.value.running) return
        val pose = MapPose(fix.position, fix.heading, fix.height ?: 0f)
        _pose.value = pose
        logPose(pose)

        guide.positionIsReliable()
        startPendingNavigationIfNeeded()
        if (_voiceOn.value) announceProximity(pose)

        val tracker = tracker ?: return
        val event = tracker.update(pose.position, pose.height)
        if (event is RouteEvent.ReachedNode) Usage.record("nav.waypoint", usageData("id" to event.id))

        val instruction = makeInstruction(pose) ?: lastInstruction
            ?: NavigationInstruction(TurnDirection.STRAIGHT, 0f, destination?.name ?: "destination", isFinal = true)
        lastInstruction = instruction
        val offRoute = tracker.isOffRoute(pose.position)
        _nav.value = NavState(navigating = true, path = tracker.path.map { it.id },
            leg = minOf(tracker.targetIndex + 1, tracker.path.size), instruction = instruction,
            remaining = tracker.remainingDistance(pose.position), offRoute = offRoute)

        val cue = policy.evaluate(instruction, event, offRoute, trackingReliable = true, now = seconds()) ?: return
        // Voice off: act on the cue without saying it.
        if (_voiceOn.value) deliver(cue)
        when (cue) {
            is GuidanceCue.Arrived -> {
                val id = destination?.id ?: cue.id
                finishNavigation()
                guide.arrived(id)
            }
            GuidanceCue.OffRoute -> {
                Usage.record("nav.off_route", usageData("distance_m" to tracker.distanceFromLeg(pose.position)?.let(::cm)))
                replanRoute(pose)
            }
            else -> Unit
        }
    }

    private fun startPendingNavigationIfNeeded() {
        val id = pendingDestinationId ?: return
        pendingDestinationId = null
        destination = graph?.node(id) ?: return
        startNavigation()
    }

    /** Distance and turn toward the tracker's current target, or null when there is no target. */
    private fun makeInstruction(pose: MapPose): NavigationInstruction? {
        val tracker = tracker ?: return null
        val target = tracker.targetNode ?: return null
        return NavigationInstruction(
            direction = TurnDirection.of(Geometry.relativeBearing(pose.position, pose.heading, target.position)),
            distance = pose.position.distanceTo(target.position),
            nextNodeName = tracker.spokenTargetName ?: target.name,
            isFinal = tracker.isFinalLeg,
            placeDistance = tracker.distanceToSpokenTarget(pose.position),
        )
    }

    /** Recomputes the route from the nearest node after the visitor strays. */
    private fun replanRoute(pose: MapPose) {
        val destination = destination ?: return
        val graph = graph ?: return
        val start = graph.nearestNode(pose.position, pose.height) ?: return
        val path = graph.findPath(start.id, destination.id)
        if (path.isEmpty()) return
        val replanned = RouteTracker(path, thresholds, graph.levels.heights, origin = pose.position)
        tracker = replanned
        Usage.record("nav.reroute", usageData("path_m" to cm(replanned.remainingDistance(pose.position))))
        _nav.update { it.copy(path = path.map { p -> p.id }, leg = 1, remaining = replanned.remainingDistance(pose.position)) }
    }

    private fun finishNavigation() {
        Usage.record("nav.arrived", routeSummary())
        tracker = null
        lastInstruction = null
        _nav.value = NavState()
    }

    /** Passive commentary for exhibits and hazards, whether or not a route is active. */
    private fun announceProximity(pose: MapPose) {
        for (a in announcer?.update(pose.position, pose.heading).orEmpty()) {
            val hazard = a.poi.category == PoiCategory.HAZARD
            if (hazard) haptics.offRoute()
            speaker.say(a.spokenText, interrupt = hazard)
        }
    }

    /** A cue as speech and a tap, with iOS `GuidanceManager`'s wording. */
    private fun deliver(cue: GuidanceCue) {
        when (cue) {
            is GuidanceCue.Approaching -> { haptics.tick(); speaker.say(cue.instruction.spokenText, interrupt = true) }
            is GuidanceCue.NodeReached -> { haptics.confirm(); speaker.say(cue.instruction.spokenText, interrupt = true) }
            is GuidanceCue.Arrived -> {
                haptics.arrival()
                speaker.say("You have arrived at the ${destination?.name ?: graph?.node(cue.id)?.name ?: "destination"}.", interrupt = true)
            }
            is GuidanceCue.Progress -> speaker.say(cue.instruction.spokenText, interrupt = false)
            GuidanceCue.OffRoute -> { haptics.offRoute(); speaker.say("You are off route. Recalculating.", interrupt = true) }
            GuidanceCue.Relocalizing -> {
                haptics.offRoute()
                speaker.say("Tracking lost. Please pause and turn slowly until tracking resumes.", interrupt = true)
            }
        }
    }

    // MARK: - Debug (debug builds only; see NusActivity)

    /** Behave as if a fix had found the phone standing at [poiId], facing the way the camera faces now. */
    fun debugStandAt(poiId: String) {
        val node = graph?.node(poiId) ?: graph?.map?.pois?.firstOrNull { it.name.equals(poiId, ignoreCase = true) }
            ?: return append("debug: no place $poiId")
        val session = lastSession ?: return append("debug: the camera is not tracking yet")
        val y = graph?.levels?.heights?.get(node.id) ?: session.y
        phone.installAnchor(FloorPose(node.position, session.heading, y), session)
        append("debug: standing at ${node.name}")
    }

    /** Behave as if positioning produced this pose (phones and emulators without ARCore). */
    fun debugFix(x: Float, z: Float, heading: Float, height: Float) {
        if (!phone.state.value.running) return append("debug: positioning is not running")
        append("debug: injected fix x=$x z=$z heading=$heading height=$height")
        handleFix(Fix(Vec2(x, z), heading, System.currentTimeMillis(), null, height))
    }

    // MARK: - Log

    fun append(line: String) {
        Usage.record("diag", usageData("line" to line))
        Log.i("NUSTour", line)
    }

    private fun cm(v: Float) = Math.round(v * 100.0) / 100.0
    private fun seconds() = SystemClock.elapsedRealtime() / 1000.0

    private fun logError(where: String, e: Throwable) =
        Usage.record("error", usageData("where" to where, "message" to (e.message ?: e.javaClass.simpleName)))

    /** `to_id`, `seconds` and `walked_m` of the route being ended. */
    private fun routeSummary() = usageData("to_id" to destination?.id,
        "seconds" to Math.round((System.currentTimeMillis() - routeStartedAt) / 100.0) / 10.0, "walked_m" to cm(walkedOnRoute))

    /** One `pose` sample a second, in graph coordinates, and the walked-distance step. */
    private fun logPose(pose: MapPose) {
        if (!poseSampler.shouldSample(System.currentTimeMillis())) return
        usagePose(pose.position.x, pose.position.z, pose.heading, arTracking, true)?.let { Usage.record("pose", it) }
        if (tracker == null) { lastWalkSample = null; return }
        lastWalkSample?.let { walkedOnRoute += it.distanceTo(pose.position) }
        lastWalkSample = pose.position
    }

    private fun logLocAttempt(a: LocAttempt) {
        val r = a.result
        Usage.record("loc.attempt", usageData("source" to "phone", "localizer" to usageLocalizerName(a.localizer),
            "ok" to a.ok, "error" to if (a.ok) null else if (r.success) "malformed pose" else r.error,
            "map_id" to r.mapId, "ms" to r.latencyMs, "bytes" to r.requestBytes,
            "jump_m" to a.jump?.let(::cm), "accepted" to a.accepted))
    }

    private fun positioningStartData(label: String) = usageData("source" to "phone", "localizer" to usageLocalizerName(label))

    private fun logPositioningStart(label: String) {
        logPositioningStop()
        loggedPositioning = true
        loggedLocalizer = label
        poseSampler.reset()
        Usage.record("positioning.start", positioningStartData(label))
    }

    /** Ends the open `positioning.start`, if any, with its tries and fixes so far. */
    private fun logPositioningStop() {
        if (!loggedPositioning) return
        loggedPositioning = false
        val s = phone.state.value
        Usage.record("positioning.stop", usageData("source" to "phone", "attempts" to s.attempts, "fixes" to s.fixes))
    }

    /** A new usage session starts with only `app.foreground`; this repeats the context its replay needs. */
    private fun logSessionContext() {
        val m = _maps.value
        val map = m.map?.let { Triple(m.slug, m.version, it.name) }
        val positioning = if (loggedPositioning) positioningStartData(loggedLocalizer) else null
        for ((type, data) in usageSessionContext(map, MODE, positioning)) Usage.record(type, data)
    }

    /** `ar.tracking` on each change. GL thread. */
    private fun logArFrame(frame: Frame) {
        val camera = frame.camera
        val fields = usageArTracking(camera.trackingState.name, camera.trackingFailureReason.name)
        arTracking = when (fields.first) { "normal" -> "normal"; "limited" -> "limited"; else -> "none" }
        if (fields != arTrackingLogged) {
            arTrackingLogged = fields
            Usage.record("ar.tracking", usageData("state" to fields.first, "reason" to fields.second))
        }
    }

    override fun onCleared() {
        Usage.onNewSession(null)
        stopPositioning()
        ar.close()
        speaker.shutdown()
        super.onCleared()
    }

    companion object {
        private const val KEY_MAP = "map.slug"
        /** The same preference name as iOS. */
        private const val KEY_VOICE = "nus.voice"
        private const val KEY_INTRO = "nus.introSeen"
        /** `mode.enter`'s name for the visitor screen, as iOS logs it. */
        private const val MODE = "Navigate"

        /** "12 m": whole metres, never less than one. */
        fun metres(v: Float) = "${maxOf(1, v.roundToInt())} m"
    }
}
