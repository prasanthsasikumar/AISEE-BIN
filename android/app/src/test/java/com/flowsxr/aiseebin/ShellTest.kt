package com.flowsxr.aiseebin

import com.flowsxr.aiseebin.glasses.Link
import com.flowsxr.aiseebin.glasses.Stream
import com.flowsxr.aiseebin.ui.FiveTaps
import com.flowsxr.aiseebin.ui.NavigateInputs
import com.flowsxr.aiseebin.ui.NextStep
import com.flowsxr.aiseebin.ui.Tone
import com.flowsxr.aiseebin.ui.navigateStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShellTest {
    private val ready = NavigateInputs(
        link = Link.READY, stream = Stream.PLAYING, mapName = "Flower Dome", mapLoading = false,
        hasAlignment = true, starting = false, running = true, fixAgeSeconds = 2, whereText = "Near the orchids.",
    )

    @Test fun freshFixIsTrackingReadyAndSaysWhere() {
        val s = navigateStatus(ready)
        assertEquals("Tracking ready", s.pill)
        assertEquals(Tone.READY, s.tone)
        assertEquals("Near the orchids.", s.hint)
        assertEquals(NextStep.STOP_POSITIONING, s.step)
    }

    @Test fun staleOrMissingFixIsRelocalizing() {
        assertEquals("Relocalizing…", navigateStatus(ready.copy(fixAgeSeconds = 11)).pill)
        assertEquals("Relocalizing…", navigateStatus(ready.copy(fixAgeSeconds = null)).pill)
        assertEquals(Tone.WAIT, navigateStatus(ready.copy(fixAgeSeconds = null)).tone)
    }

    @Test fun eachBlockNamesItsNextStep() {
        assertEquals(NextStep.CONNECT, navigateStatus(ready.copy(link = Link.DISCONNECTED)).step)
        assertEquals(NextStep.START_CAMERA, navigateStatus(ready.copy(stream = Stream.OFF, running = false)).step)
        assertEquals(NextStep.START_POSITIONING, navigateStatus(ready.copy(running = false)).step)
        assertEquals(NextStep.CHOOSE_MAP, navigateStatus(ready.copy(mapName = null)).step)
        assertEquals(NextStep.CHOOSE_MAP, navigateStatus(ready.copy(hasAlignment = false)).step)
    }

    @Test fun waitingStatesAreDisabledAndRelabelled() {
        val loading = navigateStatus(ready.copy(mapLoading = true))
        assertFalse(loading.enabled)
        assertEquals("Waiting for map", loading.action)
        val camera = navigateStatus(ready.copy(stream = Stream.STARTING, running = false))
        assertFalse(camera.enabled)
        assertEquals("Waiting for camera", camera.action)
        assertFalse(navigateStatus(ready.copy(link = Link.CONNECTING)).enabled)
    }

    @Test fun fiveTapsWithinThreeSecondsUnlockWithTicksFromTheThird() {
        var ticks = 0; var unlocked = 0
        val taps = FiveTaps({ ticks++ }, { unlocked++ })
        listOf(0L, 400, 800, 1200).forEach { taps.tap(it) }
        assertEquals(2, ticks)
        assertEquals(0, unlocked)
        taps.tap(1600)
        assertEquals(3, ticks)
        assertEquals(1, unlocked)
    }

    @Test fun slowTapsNeverUnlock() {
        var unlocked = false
        val taps = FiveTaps({}, { unlocked = true })
        (0 until 10).forEach { taps.tap(it * 900L) }
        assertFalse(unlocked)
        val again = FiveTaps({}, { unlocked = true })
        (0 until 5).forEach { again.tap(10_000L + it * 700L) }
        assertTrue(unlocked)
    }
}
