package com.flowsxr.aiseebin

import com.flowsxr.aiseebin.usage.PoseSampler
import com.flowsxr.aiseebin.usage.SessionHeader
import com.flowsxr.aiseebin.usage.UsageHttpException
import com.flowsxr.aiseebin.usage.UsageLog
import com.flowsxr.aiseebin.usage.UsageQueue
import com.flowsxr.aiseebin.usage.UsageUploader
import com.flowsxr.aiseebin.usage.UsageUploading
import com.flowsxr.aiseebin.usage.UsageValue
import com.flowsxr.aiseebin.usage.usageArTracking
import com.flowsxr.aiseebin.usage.usageData
import com.flowsxr.aiseebin.usage.usageLocalizerName
import com.flowsxr.aiseebin.usage.usageSetting
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * The usage log's core, as on iOS (UsageLogTests): sequence numbers, the
 * on-disk queue surviving failed uploads and restarts, idempotent retries,
 * session boundaries, and the unclean-exit marker.
 */
class UsageLogTest {

    /** Records what it was asked to upload; throws while [failing] is set. */
    private class FakeUploader : UsageUploading {
        val sessions = mutableListOf<JSONObject>()
        val events = mutableListOf<JSONObject>()
        var failing = false

        override fun upload(sessions: List<JSONObject>, events: List<JSONObject>) {
            if (failing) throw IOException("no network")
            this.sessions += sessions
            this.events += events
        }
    }

    /** One captured request; answers with [status]. */
    private class FakeConnection(url: URL, private val status: Int) : HttpURLConnection(url) {
        val body = ByteArrayOutputStream()
        override fun connect() {}
        override fun disconnect() {}
        override fun usingProxy() = false
        override fun getOutputStream(): OutputStream = body
        override fun getResponseCode() = status
        override fun getInputStream(): InputStream = ByteArrayInputStream(ByteArray(0))
        override fun getErrorStream(): InputStream = ByteArrayInputStream("boom".toByteArray())
    }

    private lateinit var dir: File
    private var clock = 1_800_000_000_000L
    private val direct = Executor { it.run() }
    private var status = 201
    private val requests = mutableListOf<FakeConnection>()

    @Before fun setUp() {
        dir = Files.createTempDirectory("usage").toFile()
    }

    @After fun tearDown() {
        dir.deleteRecursively()
    }

    private fun header(id: String = UUID.randomUUID().toString()) = SessionHeader(
        sessionId = id, installId = "install", platform = "android", device = "test", osVersion = "15",
        appVersion = "1.0 (1)", buildConfig = "debug", simulator = true, staff = false, startedAt = clock,
    )

    private fun makeLog(uploader: UsageUploading, maxQueueLines: Int = UsageLog.MAX_QUEUE_LINES) =
        UsageLog(dir, uploader, { clock }, header(), direct, maxQueueLines, uploadExecutor = direct)

    private fun stubbedUploader() = UsageUploader { url -> FakeConnection(url, status).also { requests += it } }

    private fun queued() = UsageQueue(dir).peekBatch(100).size

    @Test fun seqMonotonic() {
        val uploader = FakeUploader()
        val log = makeLog(uploader)
        log.onLaunch()
        log.log("map.loaded", usageData("slug" to "x", "ms" to 12))
        log.log("mode.enter", usageData("mode" to "Navigate"))
        log.log("beacon", usageData("on" to true))
        log.flushBlocking()

        assertEquals(listOf(0, 1, 2, 3), uploader.events.map { it.getInt("seq") })
        assertEquals(listOf("app.launch", "map.loaded", "mode.enter", "beacon"), uploader.events.map { it.getString("type") })
        val data = uploader.events[1].getJSONObject("data")
        assertEquals("x", data.getString("slug"))
        assertEquals(12, data.getInt("ms"))
        assertEquals(listOf(log.sessionId), uploader.sessions.map { it.getString("session_id") })
        assertTrue(uploader.events.all { it.getString("session_id") == log.sessionId })
        assertEquals("2027-01-15T08:00:00.000Z", uploader.events[0].getString("t"))
        val s = uploader.sessions[0]
        assertEquals("android", s.getString("platform"))
        assertEquals("2027-01-15T08:00:00.000Z", s.getString("started_at"))
        assertEquals(false, s.getBoolean("staff"))
        assertEquals(true, s.getBoolean("simulator"))
        assertEquals("debug", s.getString("build_config"))
    }

    @Test fun queueSurvivesReopen() {
        val failing = FakeUploader().apply { this.failing = true }
        val first = makeLog(failing)
        first.log("a")
        first.log("b")
        first.flushBlocking()
        assertTrue(failing.events.isEmpty())

        val working = FakeUploader()
        val second = makeLog(working)
        second.flushBlocking()
        assertEquals(listOf("a", "b"), working.events.map { it.getString("type") })
        assertEquals(listOf(first.sessionId), working.sessions.map { it.getString("session_id") })

        second.flushBlocking()
        assertEquals("delivered once", 2, working.events.size)
    }

    @Test fun failedUploadKeepsBatch() {
        val log = makeLog(stubbedUploader())
        log.log("a")
        log.log("b")
        log.log("c")

        status = 500
        log.flushBlocking()
        assertEquals("one header line plus three events still on disk", 4, queued())

        status = 201
        log.flushBlocking()
        assertEquals(0, queued())
    }

    @Test fun uploaderSendsIgnoreDuplicates() {
        val log = makeLog(stubbedUploader())
        log.log("a")
        log.flushBlocking()

        assertEquals(2, requests.size)
        assertTrue(requests[0].url.toString().endsWith("/rest/v1/ab_sessions?on_conflict=session_id"))
        assertTrue(requests[1].url.toString().endsWith("/rest/v1/ab_events?on_conflict=session_id,seq"))
        for (r in requests) {
            assertEquals("POST", r.requestMethod)
            assertEquals("resolution=ignore-duplicates,return=minimal", r.getRequestProperty("Prefer"))
            assertTrue(r.getRequestProperty("apikey").isNotEmpty())
            assertEquals("Bearer ${r.getRequestProperty("apikey")}", r.getRequestProperty("Authorization"))
            assertEquals("application/json", r.getRequestProperty("Content-Type"))
        }
        val events = JSONArray(requests[1].body.toString(Charsets.UTF_8.name()))
        assertEquals(1, events.length())
        assertEquals("a", events.getJSONObject(0).getString("type"))
        assertEquals(0, events.getJSONObject(0).getInt("seq"))
        val sessions = JSONArray(requests[0].body.toString(Charsets.UTF_8.name()))
        assertEquals(log.sessionId, sessions.getJSONObject(0).getString("session_id"))
    }

    @Test fun rejectedBatchIsDroppedSoLaterEventsFlow() {
        val log = makeLog(stubbedUploader())
        log.log("bad")
        status = 400
        log.flushBlocking()
        assertEquals("a permanent 4xx drops the batch", 0, queued())

        log.log("good")
        requests.clear()
        status = 201
        log.flushBlocking()
        assertEquals("only the new event, no retry of the rejected batch", 1, requests.size)
        assertTrue(requests[0].url.toString().contains("ab_events"))
        assertEquals(0, queued())
    }

    @Test fun retryableErrorsKeepBatch() {
        val log = makeLog(stubbedUploader())
        log.log("a")
        for (s in listOf(408, 429, 503)) {
            status = s
            log.flushBlocking()
            assertEquals("status $s", 2, queued())
        }
        assertTrue(UsageLog.isRejection(UsageHttpException(404, "")))
        assertTrue(!UsageLog.isRejection(UsageHttpException(429, "")))
        assertTrue(!UsageLog.isRejection(IOException("offline")))
    }

    @Test fun queueCapDropsOldestLines() {
        val failing = FakeUploader().apply { this.failing = true }
        val log = makeLog(failing, maxQueueLines = 5)
        for (i in 0 until 10) log.log("e$i")
        log.flushBlocking()

        val working = FakeUploader()
        makeLog(working).flushBlocking()
        assertEquals(listOf("e5", "e6", "e7", "e8", "e9"), working.events.map { it.getString("type") })
        assertEquals(50_000, UsageLog.MAX_QUEUE_LINES)
    }

    @Test fun newSessionAfterLongBackground() {
        val uploader = FakeUploader()
        val log = makeLog(uploader)
        log.onLaunch()
        val first = log.sessionId

        log.onBackground()
        clock += 299_000
        log.onForeground()
        assertEquals(first, log.sessionId)

        log.onBackground()
        clock += 301_000
        log.onForeground()
        val second = log.sessionId
        assertNotEquals(first, second)
        log.log("x")
        log.flushBlocking()

        val firstEvents = uploader.events.filter { it.getString("session_id") == first }
        assertEquals(listOf("app.launch", "app.background", "app.foreground", "app.background"), firstEvents.map { it.getString("type") })
        assertEquals(listOf(0, 1, 2, 3), firstEvents.map { it.getInt("seq") })
        val secondEvents = uploader.events.filter { it.getString("session_id") == second }
        assertEquals(listOf("app.foreground", "x"), secondEvents.map { it.getString("type") })
        assertEquals(listOf(0, 1), secondEvents.map { it.getInt("seq") })
        assertEquals(setOf(first, second), uploader.sessions.map { it.getString("session_id") }.toSet())
        assertEquals(UsageLog.timestamp(clock),
            uploader.sessions.first { it.getString("session_id") == second }.getString("started_at"))
    }

    @Test fun foregroundWithoutBackgroundLogsNothing() {
        val uploader = FakeUploader()
        val log = makeLog(uploader)
        log.onLaunch()
        log.onForeground()
        log.flushBlocking()
        assertEquals(listOf("app.launch"), uploader.events.map { it.getString("type") })
    }

    @Test fun uncleanExitReported() {
        val firstUploader = FakeUploader()
        val firstLog = makeLog(firstUploader)
        firstLog.onLaunch()
        firstLog.flushBlocking()
        val first = firstLog.sessionId
        assertEquals(JSONObject.NULL, firstUploader.events.first().getJSONObject("data").get("unclean_previous"))

        val uploader = FakeUploader()
        val second = makeLog(uploader)
        second.onLaunch()
        second.flushBlocking()
        val launch = uploader.events.first { it.getString("session_id") == second.sessionId }
        assertEquals(first, launch.getJSONObject("data").getString("unclean_previous"))
    }

    @Test fun cleanExitNotReported() {
        val firstLog = makeLog(FakeUploader())
        firstLog.onLaunch()
        firstLog.onBackground()

        val uploader = FakeUploader()
        val second = makeLog(uploader)
        second.onLaunch()
        second.flushBlocking()
        val launch = uploader.events.first { it.getString("session_id") == second.sessionId }
        assertEquals(JSONObject.NULL, launch.getJSONObject("data").get("unclean_previous"))
    }

    @Test fun slowUploadDoesNotHoldUpLogging() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val uploaded = mutableListOf<String>()
        val blocking = object : UsageUploading {
            override fun upload(sessions: List<JSONObject>, events: List<JSONObject>) {
                entered.countDown()
                release.await()
                synchronized(uploaded) { uploaded += events.map { it.getString("type") } }
            }
        }
        val state = Executors.newSingleThreadExecutor()
        val upload = Executors.newSingleThreadExecutor()
        try {
            val log = UsageLog(dir, blocking, { clock }, header(), state, uploadExecutor = upload)
            log.log("a")
            log.flush()
            assertTrue("upload started", entered.await(5, TimeUnit.SECONDS))

            val logger = Thread { log.log("x"); log.onBackground() }
            logger.start()
            logger.join(5_000)
            // The state executor is free: a sessionId read returns while the upload is stuck.
            log.sessionId
            val lines = UsageQueue(dir).peekBatch(100)
            assertTrue("x reached queue.jsonl during the upload", lines.any { it.contains("\"type\":\"x\"") })
            assertTrue("background recorded during the upload", lines.any { it.contains("app.background") })

            release.countDown()
            log.flushBlocking()
            assertEquals(listOf("a", "x", "app.background"), synchronized(uploaded) { uploaded.toList() })
            assertEquals("uploaded lines dropped, nothing lost", 0, UsageQueue(dir).peekBatch(100).size)
        } finally {
            release.countDown()
            state.shutdownNow()
            upload.shutdownNow()
        }
    }

    @Test fun valueEncoding() {
        val long = "a".repeat(5_000)
        val data = usageData(
            "nan" to Double.NaN, "inf" to Double.POSITIVE_INFINITY, "fnan" to Float.NaN, "s" to long,
            "n" to 1.5, "i" to 3, "b" to false, "a" to listOf("x", null), "nul" to "a\u0000b", "none" to null,
            "o" to mapOf("k" to "v", "d" to Double.NaN),
        )
        val uploader = FakeUploader()
        val log = makeLog(uploader)
        log.log("t", data)
        // A JSONObject built by hand is cleaned too.
        log.log("u", JSONObject().put("s", long).put("arr", JSONArray().put("a\u0000")))
        log.flushBlocking()

        val json = JSONObject(uploader.events[0].getJSONObject("data").toString())
        assertEquals(JSONObject.NULL, json.get("nan"))
        assertEquals(JSONObject.NULL, json.get("inf"))
        assertEquals(JSONObject.NULL, json.get("fnan"))
        assertEquals(UsageValue.MAX_STRING_LENGTH, json.getString("s").length)
        assertEquals(4_000, UsageValue.MAX_STRING_LENGTH)
        assertEquals(1.5, json.getDouble("n"), 0.0)
        assertEquals(3, json.getInt("i"))
        assertEquals(false, json.getBoolean("b"))
        assertEquals(2, json.getJSONArray("a").length())
        assertEquals(JSONObject.NULL, json.getJSONArray("a").get(1))
        assertEquals("ab", json.getString("nul"))
        assertEquals(JSONObject.NULL, json.get("none"))
        assertEquals("v", json.getJSONObject("o").getString("k"))
        assertEquals(JSONObject.NULL, json.getJSONObject("o").get("d"))

        val hand = uploader.events[1].getJSONObject("data")
        assertEquals(4_000, hand.getString("s").length)
        assertEquals("a", hand.getJSONArray("arr").getString(0))
    }

    // MARK: - Task 6: instrumentation helpers

    @Test fun poseSamplerOnePerSecond() {
        val sampler = PoseSampler()
        val results = listOf(0L, 400L, 1000L, 1500L, 2100L).map { sampler.shouldSample(1_000_000L + it) }
        assertEquals(listOf(true, false, true, false, true), results)
    }

    @Test fun visitorModeChangeLogsLeaveThenEnter() {
        val events = usageForVisitorMode(AppModel.VisitorMode.NAVIGATE, AppModel.VisitorMode.EXPLORE, 12.34)
        assertEquals(listOf("mode.leave", "mode.enter"), events.map { it.first })
        assertEquals("Navigate", events[0].second.getString("mode"))
        assertEquals(12.3, events[0].second.getDouble("seconds"), 0.0)
        assertEquals("Explore", events[1].second.getString("mode"))
        assertTrue(usageForVisitorMode(AppModel.VisitorMode.EXPLORE, AppModel.VisitorMode.EXPLORE, 1.0).isEmpty())
    }

    @Test fun settingChangeOnlyWhenDifferentAndSecretsHidden() {
        assertEquals(null, usageSetting("k", "a", "a"))
        val plain = usageSetting("localizer_mode", "auto", "server")!!
        assertEquals("auto", plain.getString("old")); assertEquals("server", plain.getString("new"))
        val secret = usageSetting("immersal_token", "", "abc123secret", secret = true)!!
        assertEquals("empty", secret.getString("old")); assertEquals("set", secret.getString("new"))
        assertTrue(!secret.toString().contains("abc123"))
    }

    @Test fun localizerNamesMatchIos() {
        assertEquals("cloud", usageLocalizerName("cloud"))
        assertEquals("on device", usageLocalizerName("on-device"))
        assertEquals("on device", usageLocalizerName("auto · on-device"))
        assertEquals("cloud", usageLocalizerName("auto · cloud"))
    }

    @Test fun arTrackingFieldsMatchIos() {
        assertEquals("normal" to null, usageArTracking("TRACKING", null))
        assertEquals("limited" to "excessive_motion", usageArTracking("PAUSED", "EXCESSIVE_MOTION"))
        assertEquals("limited" to "initializing", usageArTracking("PAUSED", "NONE"))
        assertEquals("not_available" to null, usageArTracking("STOPPED", null))
    }
}

