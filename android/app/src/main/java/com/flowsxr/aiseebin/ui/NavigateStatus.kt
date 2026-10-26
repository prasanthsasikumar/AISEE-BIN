package com.flowsxr.aiseebin.ui

import com.flowsxr.aiseebin.glasses.Link
import com.flowsxr.aiseebin.glasses.Stream

/** What the bottom bar's main button does next. */
enum class NextStep { CHOOSE_MAP, CONNECT, START_CAMERA, ALLOW_CAMERA, USE_GLASSES, START_POSITIONING, STOP_POSITIONING, NONE }

data class NavigateStatus(
    val pill: String,
    val tone: Tone,
    val pulse: Boolean,
    val hint: String,
    /** Disabled steps relabel themselves to the reason ("Waiting for map"). */
    val action: String,
    val step: NextStep,
) {
    val enabled: Boolean get() = step != NextStep.NONE
}

/** Inputs to [navigateStatus], all plain values so the rules can be unit-tested. */
data class NavigateInputs(
    /** True when the phone's own camera (ARCore) positions, false for the glasses. */
    val phone: Boolean = false,
    val cameraAllowed: Boolean = true,
    /** Why the ARCore session could not start. */
    val arError: String? = null,
    /** Why ARCore is not tracking right now. */
    val tracking: String? = null,
    val link: Link,
    val stream: Stream,
    val mapName: String?,
    val mapLoading: Boolean,
    val hasAlignment: Boolean,
    val starting: Boolean,
    val running: Boolean,
    /** Seconds since the last fix, or null with none this session. */
    val fixAgeSeconds: Long?,
    /** The last fix in words ("Near the orchids, ahead of you"). */
    val whereText: String?,
)

/**
 * The Navigate screen's state. Amber means "not yet", never an error; each
 * state names the one thing that unblocks it. Mirrors the design's states 01
 * (ready) and 02 (relocalizing), for the phone camera and for the glasses.
 */
fun navigateStatus(i: NavigateInputs): NavigateStatus = mapStatus(i) ?: if (i.phone) phoneStatus(i) else glassesStatus(i)

private fun mapStatus(i: NavigateInputs): NavigateStatus? = when {
    i.mapLoading -> NavigateStatus("Loading map…", Tone.WAIT, true,
        "Getting ${i.mapName ?: "the map"} ready.", "Waiting for map", NextStep.NONE)
    i.mapName == null -> NavigateStatus("No map", Tone.WAIT, false,
        "Choose the space you are in with the map button above.", "Choose map", NextStep.CHOOSE_MAP)
    !i.hasAlignment -> NavigateStatus("Map can't be used", Tone.WAIT, false,
        "${i.mapName} has no Immersal alignment yet. Choose another map, or align it on the iPhone.", "Choose map", NextStep.CHOOSE_MAP)
    else -> null
}

private fun phoneStatus(i: NavigateInputs): NavigateStatus = when {
    !i.cameraAllowed -> NavigateStatus("Camera not allowed", Tone.WAIT, false,
        "Allow the camera so the phone can work out where you are.", "Allow camera", NextStep.ALLOW_CAMERA)
    i.arError != null -> NavigateStatus("Camera can't start", Tone.WAIT, false,
        i.arError, "Use the glasses instead", NextStep.USE_GLASSES)
    i.starting -> NavigateStatus("Preparing map…", Tone.WAIT, true,
        "Loading ${i.mapName} so the phone can recognise it.", "Waiting for map", NextStep.NONE)
    !i.running -> NavigateStatus("Positioning off", Tone.WAIT, false,
        "Start positioning, then hold the phone up and pan it slowly.", "Start positioning", NextStep.START_POSITIONING)
    i.tracking != null -> NavigateStatus("Relocalizing…", Tone.WAIT, true,
        "${i.tracking}.", "Stop positioning", NextStep.STOP_POSITIONING)
    i.fixAgeSeconds == null || i.fixAgeSeconds > STALE_SECONDS -> NavigateStatus("Relocalizing…", Tone.WAIT, true,
        "Pan the phone slowly across the room so it can recognise the space.", "Stop positioning", NextStep.STOP_POSITIONING)
    else -> NavigateStatus("Tracking ready", Tone.READY, false,
        i.whereText ?: "Ask where you are.", "Stop positioning", NextStep.STOP_POSITIONING)
}

private fun glassesStatus(i: NavigateInputs): NavigateStatus = when {
    i.link == Link.DISCONNECTED -> NavigateStatus("Glasses not connected", Tone.WAIT, false,
        "Turn the AiSee glasses on, then connect them.", "Connect glasses", NextStep.CONNECT)
    i.link != Link.READY -> NavigateStatus("Connecting to glasses…", Tone.WAIT, true,
        "Keep the glasses close to the phone.", "Waiting for glasses", NextStep.NONE)
    i.stream == Stream.OFF -> NavigateStatus("Camera off", Tone.WAIT, false,
        "The glasses' camera works out where you are. Start it to begin.", "Start camera", NextStep.START_CAMERA)
    i.stream == Stream.STARTING -> NavigateStatus("Starting camera…", Tone.WAIT, true,
        "Tap Connect on Android's Wi-Fi prompt. Keep the app open until the camera is live.", "Waiting for camera", NextStep.NONE)
    i.stream == Stream.STOPPING -> NavigateStatus("Stopping camera…", Tone.WAIT, true,
        "One moment.", "Waiting for camera", NextStep.NONE)
    i.starting -> NavigateStatus("Preparing map…", Tone.WAIT, true,
        "Loading ${i.mapName} so the glasses can recognise it.", "Waiting for map", NextStep.NONE)
    !i.running -> NavigateStatus("Positioning off", Tone.WAIT, false,
        "Start positioning, then look around slowly.", "Start positioning", NextStep.START_POSITIONING)
    i.fixAgeSeconds == null || i.fixAgeSeconds > STALE_SECONDS -> NavigateStatus("Relocalizing…", Tone.WAIT, true,
        "Look around slowly so the glasses can recognise the space.", "Stop positioning", NextStep.STOP_POSITIONING)
    else -> NavigateStatus("Tracking ready", Tone.READY, false,
        i.whereText ?: "Ask where you are, or press the button on the glasses.", "Stop positioning", NextStep.STOP_POSITIONING)
}

/** A fix older than this no longer counts as "tracking" (AppModel speaks its age past the same mark). */
const val STALE_SECONDS = 10L
