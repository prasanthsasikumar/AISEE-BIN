package com.flowsxr.aiseebin.nus

import com.flowsxr.aiseebin.map.NavigationEdge
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.NavigationPoi
import com.flowsxr.aiseebin.map.PoiCategory
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.positioning.PositioningState
import com.flowsxr.aiseebin.route.RouteGraph
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TourGuideTest {
    private fun poi(id: String, name: String, x: Float, y: Float?, category: PoiCategory = PoiCategory.DESTINATION) =
        NavigationPoi(id, name, Vec2(x, 0f), category, details = null, y = y)

    /** Four stops along a corridor; the third is upstairs, right above the second. */
    private val map = NavigationMap("NUS test", listOf(
        poi("start", "Lobby", -5f, 0f), poi("a", "Entrance", 0f, 0f), poi("b", "Seating", 10f, 0f),
        poi("c", "MPH 2", 10.5f, 4.5f), poi("top", "Stairs top", 12f, 4.5f, PoiCategory.JUNCTION),
        poi("j", "Junction", 15f, 0f, PoiCategory.JUNCTION), poi("d", "Maker Space", 20f, 0f),
    ), listOf(NavigationEdge("start", "a"), NavigationEdge("a", "b"), NavigationEdge("b", "j"), NavigationEdge("j", "d"),
        NavigationEdge("b", "top"), NavigationEdge("top", "c")),
        alignment = null, tourStart = "start")

    private inner class Host : TourHost {
        override val graph = RouteGraph(map)
        override val places get() = map.pois.filter { it.isDestination && it.id != map.tourStart }
        override var pose: MapPose? = null
        val navigated = mutableListOf<String>()
        var stops = 0
        val events = mutableListOf<Pair<String, JSONObject>>()
        override fun navigate(poiId: String) { navigated += poiId }
        override fun stopNavigation() { stops++ }
        override fun log(type: String, data: JSONObject) { events += type to data }
    }

    @Test fun theTourStartPointIsNotAStop() {
        assertEquals(listOf("a", "b", "c", "d"), Host().places.map { it.id })
    }

    @Test fun theTourStartsAtTheNearestStopOnceThePhoneKnowsWhereItIs() {
        val host = Host()
        val guide = TourGuide(host, scope = null)
        guide.startTour()
        assertEquals(TourPhase.LEADING, guide.state.value.phase)
        assertTrue(guide.state.value.startPending)
        assertTrue(host.navigated.isEmpty())

        // Found near Seating, on the ground floor: MPH 2 is closer on plan but a floor up.
        host.pose = MapPose(Vec2(10.4f, 0f), 0f, 0.1f)
        guide.positionIsReliable()
        val s = guide.state.value
        assertFalse(s.startPending)
        assertEquals(listOf("b", "c", "d", "a"), s.stops.map { it.id })
        assertEquals(listOf("b"), host.navigated)
        assertEquals("b", host.events.first { it.first == "tour.start_from" }.second.getString("id"))
        // A second "reliable" changes nothing.
        guide.positionIsReliable()
        assertEquals(listOf("b"), host.navigated)
    }

    @Test fun arrivingNextAndFinishing() {
        val host = Host().apply { pose = MapPose(Vec2(0f, 0f), 0f, 0f) }
        val guide = TourGuide(host, scope = null)
        guide.startTour()
        assertEquals(listOf("a"), host.navigated)
        guide.arrived("b")                      // not the stop being walked to
        assertEquals(TourPhase.LEADING, guide.state.value.phase)
        guide.arrived("a")
        assertEquals(TourPhase.ARRIVED, guide.state.value.phase)
        guide.nextStop()
        assertEquals(listOf("a", "b"), host.navigated)
        assertEquals(1, guide.state.value.index)
        guide.arrived("b"); guide.nextStop(); guide.arrived("c"); guide.nextStop(); guide.arrived("d")
        assertTrue(guide.state.value.isLastStop)
        guide.nextStop()
        assertEquals(TourPhase.FINISHED, guide.state.value.phase)
        assertEquals(4, host.events.count { it.first == "tour.stop_arrived" })
        assertEquals(4, host.events.first { it.first == "tour.end" }.second.getInt("stops"))
        guide.exit()
        assertEquals(TourState(), guide.state.value)
        assertTrue(host.events.none { it.first == "tour.abandon" })
    }

    @Test fun skippingSaysWhatIsNext() {
        val host = Host().apply { pose = MapPose(Vec2(9f, 0f), 0f, 0f) }
        val guide = TourGuide(host, scope = null)
        guide.startTour()                       // nearest: Seating
        guide.skipStop()
        assertEquals("Skipped Seating. Next: MPH 2, Level 2", guide.state.value.notice)
        assertEquals(listOf("b", "c"), host.navigated)
        // Arriving clears the line.
        guide.arrived("c")
        assertNull(guide.state.value.notice)
        assertEquals("Skipped A. Next: B", TourGuide.skipNotice("A", "B", null))
        // Skipping the last stop ends the tour, with nothing to say.
        guide.nextStop(); guide.nextStop()
        guide.skipStop()
        assertEquals(TourPhase.FINISHED, guide.state.value.phase)
        assertNull(guide.state.value.notice)
    }

    @Test fun onePlaceIsNotATour() {
        val host = Host().apply { pose = MapPose(Vec2(0f, 0f), 0f, 0f) }
        val guide = TourGuide(host, scope = null)
        guide.goTo(map.pois.first { it.id == "d" })
        assertFalse(guide.state.value.isTour)
        assertEquals(listOf("d"), host.navigated)
        guide.arrived("d")
        assertEquals(TourPhase.ARRIVED, guide.state.value.phase)
        guide.exit()
        assertEquals(TourPhase.HOME, guide.state.value.phase)
        assertTrue(host.events.none { it.first.startsWith("tour.") })
    }

    @Test fun leavingATourPartWayIsLogged() {
        val host = Host().apply { pose = MapPose(Vec2(0f, 0f), 0f, 0f) }
        val guide = TourGuide(host, scope = null)
        guide.startTour(); guide.arrived("a"); guide.nextStop()
        guide.exit()
        assertEquals(1, host.events.first { it.first == "tour.abandon" }.second.getInt("at"))
        assertEquals(TourPhase.HOME, guide.state.value.phase)
    }

    @Test fun statusLinesForTheHomeAndStaffScreens() {
        assertEquals("Getting the building map…", homeStatus(NusMaps(sync = MapSync.Checking)))
        assertEquals("Couldn't get the map: no network", homeStatus(NusMaps(sync = MapSync.Failed("no network"))))
        assertEquals("No building map has been published yet.", homeStatus(NusMaps(sync = MapSync.NonePublished)))
        assertEquals("NUS test", homeStatus(NusMaps(map = map, sync = MapSync.Checking)))
        assertEquals("Positioned", positioningStatus(PositioningState(running = true), positioned = true, problem = null))
        assertEquals("Camera not tracking", positioningStatus(PositioningState(running = true, tracking = "Too dark for the camera"), false, null))
        assertEquals("Finding where you are", positioningStatus(PositioningState(running = true), false, null))
        assertEquals("This build has no Immersal token.", positioningStatus(PositioningState(), false, "This build has no Immersal token."))
    }

    @Test
    fun `home map badges that overlap are moved apart and others stay put`() {
        val out = TourOverview.spread(listOf(Vec2(100f, 100f), Vec2(104f, 100f), Vec2(100f, 100f), Vec2(300f, 300f)), 26f)
        for (i in out.indices) for (j in i + 1 until out.size) {
            assertTrue("badges $i and $j", out[i].distanceTo(out[j]) > 20f)
        }
        assertEquals(300f, out[3].x, 0.001f)
        assertEquals(300f, out[3].z, 0.001f)
    }

    @Test
    fun `home map cloud keeps points near the paths and drops the rest`() {
        val cloud = floatArrayOf(0f, 0f, 0f, 500f, 0f, 0f, 1f, 90f, 1f, 2f, 1f, 2f)
        val kept = TourScene.sample(cloud, cx = 0f, cz = 0f, span = 100f, minY = -5f, maxY = 10f)
        assertEquals(listOf(0f, 0f, 0f, 2f, 1f, 2f), kept.toList())
        assertEquals(0, TourScene.sample(null, 0f, 0f, 100f, -5f, 10f).size)
    }
}
