package com.flowsxr.aiseebin

import com.flowsxr.aiseebin.immersal.AriaServerLocalizer
import com.flowsxr.aiseebin.map.MapRepository
import com.flowsxr.aiseebin.map.NavigationEdge
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.PoiCategory
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.positioning.FloorPose
import com.flowsxr.aiseebin.positioning.PlanarAnchor
import com.flowsxr.aiseebin.positioning.SessionJumpDetector
import com.flowsxr.aiseebin.route.BuildingLevels
import com.flowsxr.aiseebin.route.GuidanceCue
import com.flowsxr.aiseebin.route.GuidancePolicy
import com.flowsxr.aiseebin.route.GuidanceThresholds
import com.flowsxr.aiseebin.route.GuidePlacement
import com.flowsxr.aiseebin.route.LevelChangeKind
import com.flowsxr.aiseebin.route.NavigationInstruction
import com.flowsxr.aiseebin.route.RouteCue
import com.flowsxr.aiseebin.route.RouteEvent
import com.flowsxr.aiseebin.route.RouteGraph
import com.flowsxr.aiseebin.route.RouteTracker
import com.flowsxr.aiseebin.route.StairRun
import com.flowsxr.aiseebin.route.TurnDirection
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Floors, stairs, routes and the camera anchor: the cases iOS tests in BuildingLevelsTests and RouteTrackerTests. */
class RouteLogicTest {
    private fun poi(id: String, name: String, x: Float, z: Float, y: Float?, category: PoiCategory = PoiCategory.DESTINATION) =
        NavigationPoi(id, name, Vec2(x, z), category, details = null, y = y)

    private fun edges(vararg pairs: Pair<String, String>) = pairs.map { NavigationEdge(it.first, it.second) }

    /** Two stacked floors: a corridor on Level 1 (y ≈ 1.4), stairs and a lift up to a corridor directly above (y ≈ 5.0). */
    private val twoFloors = NavigationMap("nus-test", listOf(
        poi("entrance", "Entrance", 0f, 0f, 1.4f),
        poi("wp-1", "Waypoint 1", 5f, 0f, null, PoiCategory.JUNCTION),
        poi("stairs-1", "Stairs bottom", 10f, 0f, 1.3f, PoiCategory.JUNCTION),
        poi("stairs-2", "Stairs top", 10f, -3f, 5.0f, PoiCategory.JUNCTION),
        poi("lab", "Robotics Lab", 0f, -3f, 5.1f),
        poi("lift-1", "Lift L1", 2f, 2f, 1.4f, PoiCategory.JUNCTION),
        poi("lift-2", "Lift L2", 2f, 2f, 5.0f, PoiCategory.JUNCTION),
        poi("cafe", "Cafe", 0f, -0.5f, 1.5f),
    ), edges("entrance" to "wp-1", "wp-1" to "stairs-1", "stairs-1" to "stairs-2", "stairs-2" to "lab",
        "entrance" to "lift-1", "lift-1" to "lift-2", "lift-2" to "lab", "entrance" to "cafe"), alignment = null)

    /** A switchback staircase whose level change falls on a middle edge, as in the NUS Computing map. */
    private val switchback = NavigationMap("nus-test", listOf(
        poi("seating", "Seating", 0f, 0f, 0.1f),
        poi("junction", "Junction", 6f, 0f, 0.1f, PoiCategory.JUNCTION),
        poi("s1", "MPH stairs 1", 12f, 0f, null, PoiCategory.JUNCTION),
        poi("s2", "MPH stairs 2", 14f, 0f, null, PoiCategory.JUNCTION),
        poi("s3", "MPH stairs 3", 14f, -2f, null, PoiCategory.JUNCTION),
        poi("s4", "MPH stairs 4", 12f, -2f, null, PoiCategory.JUNCTION),
        poi("corridor", "MPH corridor", 8f, -2f, 4.5f, PoiCategory.JUNCTION),
        poi("mph", "MPH 2", 0f, -2f, 4.5f),
    ), edges("seating" to "junction", "junction" to "s1", "s1" to "s2", "s2" to "s3", "s3" to "s4", "s4" to "corridor",
        "corridor" to "mph"), alignment = null)
    private val up = listOf("seating", "junction", "s1", "s2", "s3", "s4", "corridor", "mph")

    @Test fun heightsAndTheAriaServerAreReadFromTheMapJson() {
        val json = JSONObject("""{"name":"m","tourStart":"a","pois":[{"id":"a","name":"A","x":1,"z":2,"y":-4.5},{"id":"b","name":"B","x":1,"z":2}],
            "edges":[],"immersalAlignment":{"mapIDs":[900002],"yaw":0,"tx":0,"tz":0,"pairCount":0,"ariaServer":"",
            "maps":[{"id":7,"yaw":1,"tx":2,"tz":3,"ty":4.5}]}}""")
        val map = NavigationMap.parse(json)
        assertEquals(-4.5f, map.pois[0].y)
        assertNull(map.pois[1].y)
        assertEquals("a", map.tourStart)
        assertEquals("", map.alignment?.ariaServer)
        assertEquals(4.5f, map.alignment!!.placement(7).ty)
        assertEquals(0f, map.alignment!!.placement(900002).ty)
        // A map that never names the Aria server is an Immersal one.
        val old = NavigationMap.parse(JSONObject("""{"name":"m","pois":[],"edges":[],"immersalAlignment":{"mapIDs":[1]}}"""))
        assertNull(old.alignment?.ariaServer)
        assertNull(old.tourStart)
    }

    @Test fun ariaServerAddressDefaultsAndNormalises() {
        assertEquals("https://loc.flowsxr.com/localizeb64", AriaServerLocalizer.localizeUrl(""))
        assertEquals("https://loc.flowsxr.com/localizeb64", AriaServerLocalizer.localizeUrl(null))
        assertEquals("https://example.org/localizeb64", AriaServerLocalizer.localizeUrl(" example.org/ "))
        assertEquals("http://10.0.0.2:8000/localizeb64", AriaServerLocalizer.localizeUrl("http://10.0.0.2:8000"))
    }

    @Test fun eachAppListsItsOwnMaps() {
        assertTrue(MapRepository.lists("nus-hub", nusApp = true))
        assertFalse(MapRepository.lists("labeltransfertest", nusApp = true))
        assertFalse(MapRepository.lists("nus-hub", nusApp = false))
        assertTrue(MapRepository.lists("aria-nus-computing", nusApp = false))
        fun row(slug: String, version: Int, at: String) = JSONObject().put("map_slug", slug).put("version", version).put("created_at", at).put("name", slug)
        val rows = JSONArray(listOf(row("nus-old", 1, "2026-11-01"), row("labeltransfertest", 3, "2026-11-09"), row("nus-new", 1, "2026-11-05"),
            row("nus-new", 2, "2026-11-06"), row("aria-nus-computing", 7, "2026-11-13")))
        val nus = MapRepository.parseList(rows, nusApp = true)
        assertEquals(setOf("nus-old", "nus-new"), nus.map { it.slug }.toSet())
        assertEquals(2, nus.first { it.slug == "nus-new" }.version)
        assertEquals(setOf("labeltransfertest", "aria-nus-computing"), MapRepository.parseList(rows, nusApp = false).map { it.slug }.toSet())
        // The starter is the NUS default when it is published, else the newest nus- map.
        assertEquals("nus-new", MapRepository.nusStarterSlug(nus))
        assertEquals("nus-computing", MapRepository.nusStarterSlug(nus + MapRepository.parseList(JSONArray(listOf(row("nus-computing", 2, "2026-10-01"))), true)))
        assertNull(MapRepository.nusStarterSlug(emptyList()))
    }

    @Test fun levelsClusterAndWaypointsInherit() {
        val levels = BuildingLevels(twoFloors)
        assertEquals(2, levels.levelHeights.size)
        assertTrue(levels.isMultiLevel)
        assertEquals(1, levels.levelOf("entrance"))
        assertEquals(2, levels.levelOf("lab"))
        assertEquals(1, levels.levelOf("wp-1"))
        assertEquals("Level 2", levels.levelName("lab"))
        assertEquals(2, levels.level(4.6f))
    }

    @Test fun mapWithoutHeightsIsOneLevel() {
        val flat = twoFloors.copy(pois = twoFloors.pois.map { it.copy(y = null) })
        val levels = BuildingLevels(flat)
        assertFalse(levels.isMultiLevel)
        assertNull(levels.levelName("lab"))
        assertNull(levels.levelChange("stairs-1", "stairs-2"))
    }

    @Test fun levelChangeIsStairsUnlessNamedALift() {
        val levels = BuildingLevels(twoFloors)
        assertEquals(LevelChangeKind.STAIRS, levels.levelChange("stairs-1", "stairs-2"))
        assertEquals(LevelChangeKind.LIFT, levels.levelChange("lift-1", "lift-2"))
        assertNull(levels.levelChange("entrance", "wp-1"))
    }

    @Test fun nearestNodeStaysOnYourFloor() {
        val graph = RouteGraph(twoFloors)
        // On Level 2 right above the Cafe: planar nearest is the Cafe (0.5 m), but it is a floor down.
        assertEquals("lab", graph.nearestNode(Vec2(0f, -1f), 5.0f)?.id)
        assertEquals("cafe", graph.nearestNode(Vec2(0f, -1f), 1.4f)?.id)
        assertEquals("cafe", graph.nearestNode(Vec2(0f, -1f), null)?.id)
    }

    @Test fun routeIsTheShortestWayAndSkipsBrokenEdges() {
        val graph = RouteGraph(twoFloors.copy(edges = twoFloors.edges + NavigationEdge("lab", "deleted-place")))
        // Via the lift is shorter (≈ 2.8 + 0 + 5.4) than via the stairs (5 + 5 + 3 + 10).
        assertEquals(listOf("entrance", "lift-1", "lift-2", "lab"), graph.findPath("entrance", "lab").map { it.id })
        assertEquals(listOf("cafe"), graph.findPath("cafe", "cafe").map { it.id })
        assertTrue(graph.findPath("cafe", "nowhere").isEmpty())
        val islands = RouteGraph(twoFloors.copy(edges = edges("entrance" to "cafe")))
        assertTrue(islands.findPath("entrance", "lab").isEmpty())
        assertFalse(islands.isConnected("lab"))
    }

    @Test fun trackerWalksThePathAndWaitsForTheClimb() {
        val graph = RouteGraph(twoFloors)
        val path = listOf("stairs-1", "stairs-2", "lab").mapNotNull(graph::node)
        val tracker = RouteTracker(path, GuidanceThresholds(arrivalDistance = 3.5f), graph.levels.heights)
        assertEquals("stairs-2", tracker.targetNode?.id)
        // At the stairs bottom, within planar reach of the top: not reached until you are up there.
        assertEquals(RouteEvent.None, tracker.update(Vec2(10f, -1f), 1.3f))
        assertEquals(RouteEvent.ReachedNode("stairs-2"), tracker.update(Vec2(10f, -2f), 4.9f))
        assertEquals("Robotics Lab", tracker.spokenTargetName)
        assertEquals(8f, tracker.remainingDistance(Vec2(8f, -3f)), 1e-4f)
        assertEquals(RouteEvent.Arrived("lab"), tracker.update(Vec2(1f, -3f), 5f))
        assertTrue(tracker.hasArrived)
        assertEquals(0f, tracker.remainingDistance(Vec2(0f, 0f)), 0f)
    }

    @Test fun trackerNamesTheNextPlaceAndKnowsOffRoute() {
        val graph = RouteGraph(twoFloors)
        val path = listOf("entrance", "wp-1", "stairs-1", "stairs-2", "lab").mapNotNull(graph::node)
        // Planned from 2 m to the side of the entrance: the straight line to the first target is the route too.
        val tracker = RouteTracker(path, origin = Vec2(0f, 4f))
        assertEquals("wp-1", tracker.targetNode?.id)
        assertEquals("Robotics Lab", tracker.spokenTargetName)   // waypoints are skipped
        assertEquals(1f + 5f + 3f + 10f, tracker.distanceToSpokenTarget(Vec2(4f, 0f)), 1e-4f)
        assertFalse(tracker.isOffRoute(Vec2(2.5f, 2f)))
        assertTrue(tracker.isOffRoute(Vec2(2.5f, -4f)))
        // A one-node path is still a place to walk to.
        val single = RouteTracker(listOfNotNull(graph.node("cafe")))
        assertFalse(single.hasArrived)
        assertEquals(RouteEvent.Arrived("cafe"), single.update(Vec2(0f, 0f)))
        assertTrue(RouteTracker(emptyList()).hasArrived)
    }

    @Test fun staircaseRunsFromFirstStepToLast() {
        val levels = BuildingLevels(switchback)
        assertEquals(StairRun(2, 5, LevelChangeKind.STAIRS, up = true, toLevel = 2), levels.stairRun(up, 1))
        // Still the same staircase while on it; gone once past the top.
        assertEquals(2, levels.stairRun(up, 5)?.start)
        assertNull(levels.stairRun(up, 6))
        assertEquals(StairRun(2, 5, LevelChangeKind.STAIRS, up = false, toLevel = 1), levels.stairRun(up.reversed(), 0))
        assertNull(levels.stairRun(listOf("seating", "junction"), 1))
    }

    @Test fun cueStagesAlongTheRoute() {
        val levels = BuildingLevels(switchback)
        val at = switchback.pois.associate { it.id to it.position }
        fun cue(leg: Int, x: Float, z: Float, y: Float) = RouteCue(up, leg, Vec2(x, z), y, levels) { at[it] }
        // 12 m from the first step: nothing about stairs yet.
        assertEquals(RouteCue.Stage.Walk, cue(2, 0f, 0f, 1.4f).stage)
        // 4 m away: stairs ahead.
        val ahead = cue(3, 8f, 0f, 1.4f)
        val stage = ahead.stage as RouteCue.Stage.StairsAhead
        assertEquals(4f, stage.metres, 1e-3f)
        assertTrue(stage.run.up)
        assertEquals("Take the stairs up to Level 2", ahead.stairsText)
        assertEquals(1, ahead.userLevel)
        // Heading to the second stair node: on the stairs.
        val on = cue(4, 13f, 0f, 2f)
        assertEquals(RouteCue.Stage.OnStairs(stage.run), on.stage)
        assertEquals("Keep going up to Level 2", on.stairsText)
        // Past the top: walking again, upstairs.
        val top = cue(7, 10f, -2f, 5.8f)
        assertEquals(RouteCue.Stage.Walk, top.stage)
        assertEquals(2, top.userLevel)
        assertNull(top.stairsText)
    }

    /** A map made from a recorded walk: a height on every node, and a long ramp joining the same two floors. */
    @Test fun measuredStairsAndARamp() {
        val pois = mutableListOf(poi("lobby", "Lobby", -4f, 0f, -4.55f, PoiCategory.JUNCTION), poi("a", "Entrance", 0f, 0f, -4.6f),
            poi("b", "Hall", 4f, 0f, -4.5f, PoiCategory.JUNCTION), poi("lab2", "Lab annexe", 18f, 0f, 0.05f, PoiCategory.JUNCTION))
        // Stairs: 4.5 m up over 6 m.
        for (k in 1..5) pois += poi("st$k", "Step $k", 4f + k, 0f, -4.5f + 0.75f * k, PoiCategory.JUNCTION)
        pois += poi("top", "Landing", 10f, 0f, 0f, PoiCategory.JUNCTION)
        pois += poi("lab", "Lab", 14f, 0f, 0.1f)
        // Ramp: the same climb over 90 m, back round to the hall.
        for (k in 1..17) pois += poi("r$k", "Slope $k", 14f, 5f * k, -0.02f - 0.25f * (k - 1), PoiCategory.JUNCTION)
        val stairs = listOf("a", "b", "st1", "st2", "st3", "st4", "st5", "top", "lab")
        val ramp = listOf("lab") + (1..17).map { "r$it" } + "b"
        val all = mutableListOf(NavigationEdge("lobby", "a"), NavigationEdge("lab", "lab2"))
        for (path in listOf(stairs, ramp)) path.zipWithNext { x, y -> all += NavigationEdge(x, y) }
        val levels = BuildingLevels(NavigationMap("walk", pois, all, alignment = null))
        assertEquals(2, levels.levelHeights.size)
        assertEquals(1, levels.levelOf("a"))
        assertEquals(2, levels.levelOf("lab"))
        // The staircase is every climbing edge, found from the heights, not from names.
        assertEquals(StairRun(1, 7, LevelChangeKind.STAIRS, up = true, toLevel = 2), levels.stairRun(stairs, 0))
        // The ramp changes floor without anything to climb.
        assertNull(levels.stairRun(ramp, 0))
        assertNull(levels.levelChange("r8", "r9"))
    }

    @Test fun floorMarksWalkAheadClimbAndHold() {
        val stops = listOf(GuidePlacement.Stop(Vec2(4f, 0f), 0f), GuidePlacement.Stop(Vec2(4f, -4f), 3.6f))
        val flat = GuidePlacement.place(Vec2(0f, 0f), 0f, stops, 2.5f)!!
        assertEquals(2.5f, flat.x, 1e-4f); assertEquals(0f, flat.y, 1e-4f); assertFalse(flat.waiting)
        val climbing = GuidePlacement.place(Vec2(3f, 0f), 0f, stops, 3f)!!
        assertEquals(-2f, climbing.z, 1e-4f); assertEquals(1.8f, climbing.y, 1e-4f); assertEquals(Vec2(0f, -1f), climbing.facing)
        val door = listOf(GuidePlacement.Stop(Vec2(1f, 0f), 0f, holdHere = true), GuidePlacement.Stop(Vec2(1f, 0f), 3.6f), GuidePlacement.Stop(Vec2(5f, 0f), 3.6f))
        val held = GuidePlacement.place(Vec2(0f, 0f), 0f, door, 2.5f)!!
        assertEquals(1f, held.x, 0f); assertEquals(0f, held.y, 0f); assertTrue(held.waiting)
    }

    @Test fun trailStaysPutAndStopsAtTheStairs() {
        val stops = listOf(GuidePlacement.Stop(Vec2(10.1f, 0f), 0f, holdHere = true), GuidePlacement.Stop(Vec2(10.1f, -10f), 4f))
        val a = GuidePlacement.trail(Vec2(0f, 0f), 0f, stops, 1.2f, 8f, 0.8f)
        val b = GuidePlacement.trail(Vec2(0.3f, 0f), 0f, stops, 1.2f, 8f, 0.8f)
        assertEquals(1.3f, a.first().x, 1e-3f)
        assertEquals(9, a.size)
        // A step forward drops the nearest mark; the rest have not moved.
        assertEquals(a[1].x, b.first().x, 1e-3f)
        // Near the stairs the trail ends at the first step and never climbs.
        val near = GuidePlacement.trail(Vec2(7f, 0f), 0f, stops, 1.2f, 8f, 0.8f)
        assertTrue(near.isNotEmpty())
        assertTrue(near.all { it.z == 0f && it.y == 0f && it.x < 10.11f })
    }

    @Test fun turnsAndTheirWording() {
        fun deg(d: Float) = Math.toRadians(d.toDouble()).toFloat()
        assertEquals(TurnDirection.STRAIGHT, TurnDirection.of(deg(10f)))
        assertEquals(TurnDirection.SLIGHT_LEFT, TurnDirection.of(deg(-30f)))
        assertEquals(TurnDirection.RIGHT, TurnDirection.of(deg(90f)))
        assertEquals(TurnDirection.SHARP_LEFT, TurnDirection.of(deg(-150f)))
        assertEquals(TurnDirection.U_TURN, TurnDirection.of(deg(175f)))
        val i = NavigationInstruction(TurnDirection.LEFT, 2f, "Seating", isFinal = false, placeDistance = 12.4f)
        assertEquals("Turn left. The Seating is 12 meters ahead.", i.spokenText)
        assertEquals("Turn left toward Seating", i.bannerText)
        assertEquals("Continue straight to Seating", i.copy(direction = TurnDirection.STRAIGHT, isFinal = true).bannerText)
        assertEquals("Turn around. The Seating is 1 meter ahead.", i.copy(direction = TurnDirection.U_TURN, placeDistance = 0.2f).spokenText)
    }

    @Test fun cuesFireOncePerNodeAndWarningsRepeatSlowly() {
        val policy = GuidancePolicy()
        val far = NavigationInstruction(TurnDirection.STRAIGHT, 9f, "Seating", isFinal = false)
        val close = far.copy(distance = 2f)
        assertNull(policy.evaluate(far, RouteEvent.None, isOffRoute = false, trackingReliable = true, now = 0.0))
        assertEquals(GuidanceCue.Approaching(close), policy.evaluate(close, RouteEvent.None, false, true, 1.0))
        assertNull(policy.evaluate(close, RouteEvent.None, false, true, 2.0))
        assertEquals(GuidanceCue.NodeReached(far), policy.evaluate(far, RouteEvent.ReachedNode("x"), false, true, 3.0))
        assertEquals(GuidanceCue.OffRoute, policy.evaluate(far, RouteEvent.None, true, true, 4.0))
        assertNull(policy.evaluate(far, RouteEvent.None, true, true, 6.0))
        assertEquals(GuidanceCue.OffRoute, policy.evaluate(far, RouteEvent.None, true, true, 12.5))
        assertEquals(GuidanceCue.Relocalizing, policy.evaluate(far, RouteEvent.None, false, false, 21.0))
        assertEquals(GuidanceCue.Progress(far), policy.evaluate(far, RouteEvent.None, false, true, 34.0))
        assertEquals(GuidanceCue.Arrived("mph"), policy.evaluate(far, RouteEvent.Arrived("mph"), false, true, 35.0))
    }

    @Test fun anchorCarriesHeightAndMapsBackToTheSession() {
        val a = PlanarAnchor()
        // Session: at (1, 0), 1.2 m up, heading 0. The map says that camera is at (5, 5), −3.3 m, facing π/2.
        assertTrue(a.update(FloorPose(Vec2(5f, 5f), (Math.PI / 2).toFloat(), -3.3f), FloorPose(Vec2(1f, 0f), 0f, 1.2f)))
        val up = a.toGraph(FloorPose(Vec2(1f, -1f), 0f, 1.5f))!!
        assertEquals(6f, up.position.x, 1e-4f); assertEquals(5f, up.position.z, 1e-4f)
        assertEquals(-3.0f, up.y, 1e-4f)
        // And back: a graph point lands where the session saw it.
        val s = a.fit!!.toSession(6f, -3.0f, 5f)
        assertEquals(1f, s[0], 1e-4f); assertEquals(1.5f, s[1], 1e-4f); assertEquals(-1f, s[2], 1e-4f)
        // The graph's +x (the way the camera faced) is the session's −z.
        val d = a.fit!!.toSessionDirection(Vec2(1f, 0f))
        assertEquals(0f, d.x, 1e-4f); assertEquals(-1f, d.z, 1e-4f)
    }

    @Test fun aFarJumpNeedsSixInARow() {
        val a = PlanarAnchor()
        val session = FloorPose(Vec2(0f, 0f), 0f)
        a.update(FloorPose(Vec2(0f, 0f), 0f), session)
        val far = FloorPose(Vec2(30f, 0f), 0f)
        repeat(5) { assertFalse(a.update(far, session)) }
        assertTrue(a.update(far, session))
        assertEquals(30f, a.toGraph(session)!!.position.x, 1e-4f)
    }

    @Test fun aSessionJumpIsMoreThanWalkingAllows() {
        val d = SessionJumpDetector()
        assertNull(d.jump(FloorPose(Vec2(0f, 0f), 0f), 0))
        assertNull(d.jump(FloorPose(Vec2(0.5f, 0f), 0f), 500))        // walking
        assertNull(d.jump(FloorPose(Vec2(9f, 0f), 0f), 2500))         // 8.5 m after a 2 s gap in tracking
        assertEquals(45f, d.jump(FloorPose(Vec2(54f, 0f), 0f), 2533)!!, 1e-3f)
        assertNull(d.jump(FloorPose(Vec2(54.1f, 0f), 0f), 2566))      // the new frame carries on
    }
}
