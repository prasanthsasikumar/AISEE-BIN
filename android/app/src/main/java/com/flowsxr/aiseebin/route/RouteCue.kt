package com.flowsxr.aiseebin.route

import com.flowsxr.aiseebin.map.Vec2
import kotlin.math.floor
import kotlin.math.hypot

/**
 * Where the visitor is on the active route, worked out once and read by the
 * floor arrows, the small map and the instruction card so they always agree.
 * Port of iOS `RouteCue`.
 */
class RouteCue(
    /** Route node ids, start to destination. */
    val path: List<String>,
    /** 1-based leg the visitor is on (the view model's `routeLeg`). */
    routeLeg: Int,
    val user: Vec2,
    cameraY: Float,
    levels: BuildingLevels,
    position: (String) -> Vec2?,
) {
    sealed interface Stage {
        /** Walking on one floor. */
        data object Walk : Stage
        /** Stairs or a lift are close: [metres] along the route to the first step. */
        data class StairsAhead(val run: StairRun, val metres: Float) : Stage
        /** Between the first and last step (or in the lift). */
        data class OnStairs(val run: StairRun) : Stage
    }

    /** Index in [path] of the node the visitor is heading to. */
    val target: Int = (routeLeg - 1).coerceIn(0, maxOf(0, path.size - 1))
    /** The visitor's floor, 1-based. */
    val userLevel: Int = levels.level(cameraY)
    /** Floor height under the visitor. */
    val userFloorY: Float = cameraY - BuildingLevels.CAMERA_HEIGHT
    val stage: Stage

    init {
        val run = levels.stairRun(path, target)
        stage = when {
            run == null -> Stage.Walk
            target > run.start -> Stage.OnStairs(run)
            else -> {
                // Along the route from the visitor to the first step.
                var metres = 0f
                var from = user
                for (i in target..run.start) {
                    val p = position(path[i]) ?: continue
                    metres += from.distanceTo(p)
                    from = p
                }
                if (metres <= STAIRS_NOTICE) Stage.StairsAhead(run, metres) else Stage.Walk
            }
        }
    }

    val run: StairRun?
        get() = when (val s = stage) {
            Stage.Walk -> null
            is Stage.StairsAhead -> s.run
            is Stage.OnStairs -> s.run
        }

    /** "Take the stairs up to Level 2", or null when no stairs are near. */
    val stairsText: String?
        get() = when (val s = stage) {
            Stage.Walk -> null
            is Stage.StairsAhead -> "Take the ${s.run.kind.word} ${if (s.run.up) "up" else "down"} to Level ${s.run.toLevel}"
            is Stage.OnStairs ->
                if (s.run.kind == LevelChangeKind.LIFT) "Ride the lift to Level ${s.run.toLevel}"
                else "Keep going ${if (s.run.up) "up" else "down"} to Level ${s.run.toLevel}"
        }

    companion object {
        /** How close the stairs have to be before the app starts talking about them. */
        const val STAIRS_NOTICE = 10f
    }
}

/**
 * Where things on the floor go, a little way ahead of the visitor along the
 * route. Pure geometry in the graph frame: x/z on the floor plan, y the floor
 * height. Port of iOS `GuidePlacement`.
 */
object GuidePlacement {
    /** One stop on the remaining route. */
    data class Stop(
        val planar: Vec2,
        /** Floor height under the node, if known. */
        val floorY: Float? = null,
        /** The trail ends here (the first step of the stairs, the lift door). */
        val holdHere: Boolean = false,
    )

    data class Result(
        val x: Float, val y: Float, val z: Float,
        /** Planar direction of travel at that point (unit length, or zero). */
        val facing: Vec2,
        /** True when the walk stopped short of the look-ahead: at a hold point or the end. */
        val waiting: Boolean,
    ) {
        val planar: Vec2 get() = Vec2(x, z)
    }

    /**
     * Walks [lookAhead] metres (on the floor plan) from the visitor along
     * [stops], the remaining route starting with the node they are heading to.
     * Floor height is interpolated along each leg.
     */
    fun place(user: Vec2, userFloorY: Float, stops: List<Stop>, lookAhead: Float): Result? {
        if (stops.isEmpty()) return null
        var point = user
        var pointY = userFloorY
        var remaining = lookAhead
        var facing = Vec2(0f, 0f)
        for (stop in stops) {
            val stopY = stop.floorY ?: pointY
            val leg = stop.planar - point
            val length = hypot(leg.x, leg.z)
            if (length > EPSILON) facing = leg * (1 / length)
            if (length >= remaining) {
                val t = if (length > EPSILON) remaining / length else 1f
                val p = point + leg * t
                return Result(p.x, pointY + (stopY - pointY) * t, p.z, facing, waiting = false)
            }
            remaining -= length
            point = stop.planar
            pointY = stopY
            if (stop.holdHere) break
        }
        return Result(point.x, pointY, point.z, facing, waiting = true)
    }

    /**
     * Floor marks every [spacing] metres along the route, from [start] to
     * [reach] metres ahead of the visitor, nearest first (the floor arrows).
     * Marks are counted from the first stop, so they stay put on the floor as
     * the visitor walks instead of sliding along with them. The trail ends at
     * a hold point or the destination.
     */
    fun trail(user: Vec2, userFloorY: Float, stops: List<Stop>, start: Float, reach: Float, spacing: Float): List<Result> {
        val first = stops.firstOrNull() ?: return emptyList()
        if (spacing <= 0 || reach <= start) return emptyList()
        val toFirst = first.planar.distanceTo(user)
        // Distances ahead of the visitor that fall on the spacing grid anchored at the first stop.
        var ahead = toFirst - spacing * floor((toFirst - start) / spacing)
        val marks = mutableListOf<Result>()
        while (ahead <= reach) {
            val mark = place(user, userFloorY, stops, ahead) ?: break
            if (mark.waiting) break
            marks += mark
            ahead += spacing
        }
        return marks
    }

    private const val EPSILON = 1e-6f
}
