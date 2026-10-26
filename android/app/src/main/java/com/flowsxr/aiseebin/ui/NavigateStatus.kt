package com.flowsxr.aiseebin.ui

import com.flowsxr.aiseebin.glasses.Link
import com.flowsxr.aiseebin.glasses.Stream

/** What the bottom bar's main button does next. */
enum class NextStep { CHOOSE_MAP, CONNECT, START_CAMERA, START_POSITIONING, STOP_POSITIONING, NONE }

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
 * The Navigate screen's state, glasses edition. Amber means "not yet", never
 * an error; each state names the one thing that unblocks it. Mirrors the
 * design's states 01 (ready) and 02 (relocalizing).
 */
fun navigateStatus(i: NavigateInputs): NavigateStatus = when {
    i.mapLoading -> NavigateStatus("Loading map…", Tone.WAIT, true,
        "Getting ${i.mapName ?: "the map"} ready.", "Waiting for map", NextStep.NONE)
    i.mapName == null -> NavigateStatus("No map", Tone.WAIT, false,
        "Choose the space you are in with the map button above.", "Choose map", NextStep.CHOOSE_MAP)
    !i.hasAlignment -> NavigateStatus("Map can't be used", Tone.WAIT, false,
        "${i.mapName} has no glasses alignment yet. Choose another map, or align it on the iPhone.", "Choose map", NextStep.CHOOSE_MAP)
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
