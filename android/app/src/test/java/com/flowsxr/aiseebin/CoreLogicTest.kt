package com.flowsxr.aiseebin

import com.flowsxr.aiseebin.immersal.GlassesCamera
import com.flowsxr.aiseebin.immersal.GrayImage
import com.flowsxr.aiseebin.immersal.ImmersalClient
import com.flowsxr.aiseebin.immersal.ImmersalPose
import com.flowsxr.aiseebin.immersal.ImmersalRawPose
import com.flowsxr.aiseebin.immersal.NativeLocalizer
import com.flowsxr.aiseebin.map.Geometry
import com.flowsxr.aiseebin.map.ImmersalAlignment
import com.flowsxr.aiseebin.map.LocationDescriber
import com.flowsxr.aiseebin.map.NavigationMap
import com.flowsxr.aiseebin.map.RelativeSide
import com.flowsxr.aiseebin.map.Vec2
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.util.zip.CRC32
import java.util.zip.InflaterInputStream
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

class CoreLogicTest {
    private val eps = 1e-4f

    // MARK: pose

    /** Identity rotation: a CV camera looks down +Z, i.e. heading π (the graph's "toward the viewer"). */
    @Test fun identityRotationFacesPlusZ() {
        val pose = ImmersalRawPose(1f, 2f, 3f, floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f))
        val planar = ImmersalPose.planar(pose)!!
        assertEquals(1f, planar.x, eps)
        assertEquals(3f, planar.z, eps)
        assertEquals(PI.toFloat(), kotlin.math.abs(planar.heading), eps)
    }

    /** A CV camera turned so its +Z points along map −Z faces heading 0 (straight ahead). */
    @Test fun cameraLookingDownMinusZHasHeadingZero() {
        // Rotation 180° about Y: columns (−1,0,0), (0,1,0), (0,0,−1); row-major terms below.
        val pose = ImmersalRawPose(0f, 0f, 0f, floatArrayOf(-1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, -1f))
        assertEquals(0f, ImmersalPose.planar(pose)!!.heading, eps)
    }

    @Test fun malformedPoseIsRejected() {
        assertNull(ImmersalPose.planar(ImmersalRawPose(Float.NaN, 0f, 0f, FloatArray(9))))
        assertNull(ImmersalPose.planar(ImmersalRawPose(0f, 0f, 0f, FloatArray(8))))
    }

    /** The quaternion conversion must agree with the matrix the REST call would return. */
    @Test fun quaternionMatchesRotationMatrix() {
        val angle = 0.7f // about Y
        val q = floatArrayOf(0f, sin(angle / 2), 0f, cos(angle / 2))
        val raw = NativeLocalizer.rawPose(0f, 0f, 0f, q[0], q[1], q[2], q[3])
        val expected = floatArrayOf(cos(angle), 0f, sin(angle), 0f, 1f, 0f, -sin(angle), 0f, cos(angle))
        assertArrayEquals(expected, raw.r, eps)
    }

    @Test fun restResponseParses() {
        val body = """{"error":"none","success":true,"map":151658,"px":1.5,"py":0.2,"pz":-2,
            "r00":1,"r01":0,"r02":0,"r10":0,"r11":1,"r12":0,"r20":0,"r21":0,"r22":1}"""
        val r = ImmersalClient.parse(body, 200, 12, 34)
        assertTrue(r.success)
        assertEquals(151658, r.mapId)
        assertEquals(-2f, r.pose!!.pz, eps)
    }

    @Test fun restRejectionKeepsImmersalsReason() {
        val r = ImmersalClient.parse("""{"error":"auth"}""", 400, 5, 6)
        assertFalse(r.success)
        assertEquals("auth", r.error)
        assertFalse(ImmersalClient.parse("<html>", 502, 5, 6).success)
    }

    @Test fun intrinsicsScaleWithWidth() {
        val k = GlassesCamera(1100f).intrinsics(960, 540)
        assertEquals(825f, k.fx, eps)
        assertEquals(480f, k.ox, eps)
        assertEquals(270f, k.oy, eps)
    }

    // MARK: alignment + geometry

    @Test fun alignmentRotatesAndTranslates() {
        val a = ImmersalAlignment(listOf(1), (PI / 2).toFloat(), 10f, 0f, 8, null)
        val p = a.toGraph(Vec2(1f, 0f))
        assertEquals(10f, p.x, eps)
        assertEquals(1f, p.z, eps)
        assertEquals((PI / 2).toFloat(), a.toGraphHeading(0f), eps)
    }

    @Test fun relativeSides() {
        // Facing heading 0 (−z); a point at +x is on the right.
        assertEquals(RelativeSide.RIGHT, RelativeSide.of(Geometry.relativeBearing(Vec2(0f, 0f), 0f, Vec2(5f, 0f))))
        assertEquals(RelativeSide.AHEAD, RelativeSide.of(Geometry.relativeBearing(Vec2(0f, 0f), 0f, Vec2(0f, -5f))))
        assertEquals(RelativeSide.BEHIND, RelativeSide.of(Geometry.relativeBearing(Vec2(0f, 0f), 0f, Vec2(0f, 5f))))
    }

    // MARK: map + describer

    private val mapJson = """{"name":"Test","pois":[
        {"id":"a","name":"Table","x":0,"z":0,"category":"destination"},
        {"id":"j","name":"J","x":5,"z":0,"category":"junction"},
        {"id":"b","name":"Plant","x":10,"z":0,"category":"exhibit","details":null}],
        "edges":[{"from":"a","to":"j"},{"from":"j","to":"b"}],
        "immersalAlignment":{"mapIDs":[151658],"yaw":0,"tx":0,"tz":0,"pairCount":0,"rmsError":0}}"""

    @Test fun mapParsesWithAlignment() {
        val map = NavigationMap.parse(JSONObject(mapJson))
        assertEquals(3, map.pois.size)
        assertEquals(listOf(151658), map.alignment!!.mapIds)
        assertNull(map.alignment!!.origin)
    }

    @Test fun nullPoiNameFallsBackToId() {
        val map = NavigationMap.parse(JSONObject("""{"name":"T","pois":[{"id":"n1","name":null,"x":0,"z":0}],"edges":[]}"""))
        assertEquals("n1", map.pois[0].name)
    }

    @Test fun describerAtAndBetween() {
        val d = LocationDescriber(NavigationMap.parse(JSONObject(mapJson)))
        assertEquals("You are at the Table.", d.describe(Vec2(0.5f, 0f), 0f))
        val between = d.describe(Vec2(4f, 0.5f), (PI / 2).toFloat())!!
        assertTrue(between, between.startsWith("You are between the Table and the Plant"))
    }

    // MARK: image

    @Test fun downscaleAveragesAndKeepsAspect() {
        val src = GrayImage(4, 2, byteArrayOf(0, 100, 200.toByte(), 50, 0, 100, 200.toByte(), 50))
        val half = src.scaledToWidth(2)
        assertEquals(2, half.width)
        assertEquals(1, half.height)
        assertEquals(50, half.pixels[0].toInt() and 0xFF)
        assertEquals(125, half.pixels[1].toInt() and 0xFF)
        assertTrue(src.scaledToWidth(8) === src)
    }

    @Test fun pngIsWellFormed() {
        val img = GrayImage(3, 2, byteArrayOf(1, 2, 3, 4, 5, 6))
        val png = img.toPng()
        assertArrayEquals(byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 13, 10, 26, 10),
            png.copyOfRange(0, 8))
        // IHDR: length 13, type, width 3, height 2, depth 8, colour 0.
        assertEquals(13, int(png, 8))
        assertEquals("IHDR", String(png, 12, 4))
        assertEquals(3, int(png, 16)); assertEquals(2, int(png, 20))
        assertEquals(8, png[24].toInt()); assertEquals(0, png[25].toInt())
        val crc = CRC32().apply { update(png, 12, 17) }.value.toInt()
        assertEquals(crc, int(png, 29))
        // IDAT inflates back to filter byte + row, twice.
        val idatLen = int(png, 33)
        assertEquals("IDAT", String(png, 37, 4))
        val raw = InflaterInputStream(ByteArrayInputStream(png, 41, idatLen)).readBytes()
        assertArrayEquals(byteArrayOf(0, 1, 2, 3, 0, 4, 5, 6), raw)
        assertNotNull(String(png, png.size - 8, 4).takeIf { it == "IEND" })
    }

    private fun int(b: ByteArray, at: Int) =
        ((b[at].toInt() and 0xFF) shl 24) or ((b[at + 1].toInt() and 0xFF) shl 16) or
            ((b[at + 2].toInt() and 0xFF) shl 8) or (b[at + 3].toInt() and 0xFF)
}
