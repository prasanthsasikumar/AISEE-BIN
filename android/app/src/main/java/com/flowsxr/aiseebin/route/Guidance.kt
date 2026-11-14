package com.flowsxr.aiseebin.route

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Coarse turn bucket from the signed angle between the visitor's heading and
 * the bearing to the next node. Positive angles are to the right. Port of iOS
 * `TurnDirection`.
 */
enum class TurnDirection(val spokenPhrase: String) {
    STRAIGHT("continue straight"),
    SLIGHT_LEFT("turn slight left"), LEFT("turn left"), SHARP_LEFT("turn sharp left"),
    SLIGHT_RIGHT("turn slight right"), RIGHT("turn right"), SHARP_RIGHT("turn sharp right"),
    U_TURN("turn around");

    val isLeft: Boolean get() = this == SLIGHT_LEFT || this == LEFT || this == SHARP_LEFT
    val isRight: Boolean get() = this == SLIGHT_RIGHT || this == RIGHT || this == SHARP_RIGHT

    companion object {
        /** @param relativeAngle radians in (−π, π]; positive = clockwise = right. */
        fun of(relativeAngle: Float): TurnDirection {
            val degrees = abs(relativeAngle) * 180 / PI.toFloat()
            val right = relativeAngle > 0
            return when {
                degrees < 15 -> STRAIGHT
                degrees < 45 -> if (right) SLIGHT_RIGHT else SLIGHT_LEFT
                degrees < 120 -> if (right) RIGHT else LEFT
                degrees < 160 -> if (right) SHARP_RIGHT else SHARP_LEFT
                else -> U_TURN
            }
        }
    }
}

/** One guidance step: what to do, how far away it is, and where it leads. Port of iOS `NavigationInstruction`. */
data class NavigationInstruction(
    val direction: TurnDirection,
    /** Metres to the next node, which may be an unnamed waypoint. Times the cues; never shown as the distance to a place. */
    val distance: Float,
    /** The next named place along the route. */
    val nextNodeName: String,
    /** True when the next node is the destination itself. */
    val isFinal: Boolean,
    /** Metres to walk along the route to [nextNodeName]: the number the visitor hears. */
    val placeDistance: Float = distance,
) {
    private val roundedMetres: Int get() = maxOf(1, placeDistance.roundToInt())
    private val verb: String get() = direction.spokenPhrase.replaceFirstChar { it.uppercase() }

    /** Full sentence for the voice. The direction is the way to face now; the distance is to the named place. */
    val spokenText: String
        get() = "$verb. The $nextNodeName is $roundedMetres ${if (roundedMetres == 1) "meter" else "meters"} ahead."

    /** Short line for the on-screen card. */
    val bannerText: String get() = if (isFinal) "$verb to $nextNodeName" else "$verb toward $nextNodeName"
}

/** What the guidance layer should do right now (iOS `GuidanceCue`). */
sealed interface GuidanceCue {
    /** Inside the approach radius of the next node: pre-announce the turn. */
    data class Approaching(val instruction: NavigationInstruction) : GuidanceCue
    /** Just reached a node: announce the following instruction. */
    data class NodeReached(val instruction: NavigationInstruction) : GuidanceCue
    /** The destination (id) has been reached. */
    data class Arrived(val id: String) : GuidanceCue
    /** Periodic reassurance on a long leg. */
    data class Progress(val instruction: NavigationInstruction) : GuidanceCue
    data object OffRoute : GuidanceCue
    data object Relocalizing : GuidanceCue
}

/**
 * Decides whether to give a cue, never how. Port of iOS `GuidancePolicy`:
 * 1. Arrival and node-reached cues always fire.
 * 2. Tracking loss and off-route warnings repeat at `offRouteRepeatInterval`.
 * 3. The approach announcement fires once per node.
 * 4. Otherwise a progress reminder fires every `progressReminderInterval`.
 */
class GuidancePolicy(private val thresholds: GuidanceThresholds = GuidanceThresholds()) {
    private var lastSpeech: Double? = null
    private var lastWarning = -Double.MAX_VALUE
    private var announcedApproachFor: String? = null

    /** Clears per-route memory. Call when a new route starts. */
    fun reset() {
        lastSpeech = null
        lastWarning = -Double.MAX_VALUE
        announcedApproachFor = null
    }

    /** @param now seconds on any steady clock. */
    fun evaluate(instruction: NavigationInstruction, event: RouteEvent, isOffRoute: Boolean,
                 trackingReliable: Boolean, now: Double): GuidanceCue? {
        val last = lastSpeech ?: now
        if (lastSpeech == null) lastSpeech = now

        when (event) {
            is RouteEvent.Arrived -> { lastSpeech = now; return GuidanceCue.Arrived(event.id) }
            is RouteEvent.ReachedNode -> { lastSpeech = now; announcedApproachFor = null; return GuidanceCue.NodeReached(instruction) }
            RouteEvent.None -> Unit
        }
        if (!trackingReliable) return warningIfDue(GuidanceCue.Relocalizing, now)
        if (isOffRoute) return warningIfDue(GuidanceCue.OffRoute, now)

        val key = instruction.nextNodeName
        if (instruction.distance <= thresholds.approachDistance && announcedApproachFor != key) {
            announcedApproachFor = key
            lastSpeech = now
            return GuidanceCue.Approaching(instruction)
        }
        if (now - last >= thresholds.progressReminderInterval) {
            lastSpeech = now
            return GuidanceCue.Progress(instruction)
        }
        return null
    }

    private fun warningIfDue(cue: GuidanceCue, now: Double): GuidanceCue? {
        if (now - lastWarning < thresholds.offRouteRepeatInterval) return null
        lastWarning = now
        lastSpeech = now
        return cue
    }
}
