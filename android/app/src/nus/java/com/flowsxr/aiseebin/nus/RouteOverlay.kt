package com.flowsxr.aiseebin.nus

import android.opengl.GLES20
import android.opengl.Matrix
import android.os.Handler
import android.os.Looper
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.phone.ArCamera
import com.flowsxr.aiseebin.phone.ArOverlay
import com.flowsxr.aiseebin.positioning.PhonePositioning
import com.flowsxr.aiseebin.route.BuildingLevels
import com.flowsxr.aiseebin.route.GuidePlacement
import com.flowsxr.aiseebin.route.RouteCue
import com.flowsxr.aiseebin.route.RouteGraph
import com.google.ar.core.Frame
import com.google.ar.core.TrackingState
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** Where the route's arrows are relative to the screen. */
enum class RouteHint { HIDDEN, VISIBLE, LEFT, RIGHT, DOWN }

/** What the camera view draws from, published by the screen whenever the tour or the route changes. */
class RouteScene(
    val phase: TourPhase,
    /** The stop being walked to, or stood at. */
    val stopId: String?,
    val nav: NavState,
    val graph: RouteGraph?,
)

/**
 * The way drawn on the live camera: arrows on the floor along the next few
 * metres of the route, a pin over the place being walked to, and a small 3D
 * staircase where the route goes up or down a floor. The Android half of iOS
 * `RouteARView`, drawn with OpenGL in ARCore's frame. GL thread throughout,
 * except [scene], which the screen sets.
 */
class RouteOverlay(private val phone: PhonePositioning, private val onHint: (RouteHint) -> Unit) : ArOverlay {
    @Volatile var scene: RouteScene? = null

    private val main = Handler(Looper.getMainLooper())
    private var program = 0
    private var aPos = 0; private var aNormal = 0
    private var uMvp = 0; private var uModel = 0; private var uColor = 0; private var uLit = 0

    private val view = FloatArray(16)
    private val proj = FloatArray(16)
    private val viewProj = FloatArray(16)
    private val model = FloatArray(16)
    private val mvp = FloatArray(16)
    private val scratch = FloatArray(16)

    private val arrowSlots = List(ARROW_COUNT) { Slot() }
    private val pinSlot = Slot()
    private val stairsUpSlot = Slot()
    private val stairsDownSlot = Slot()
    private var clock = 0f
    private var lastTick = 0L
    private var lastHint = RouteHint.HIDDEN

    /** One thing on screen: where it last was, and how visible it is while it fades in or out. */
    private class Slot {
        var opacity = 0f
        var x = 0f; var y = 0f; var z = 0f
        var yaw = 0f
        fun fade(target: Float) { opacity += (target - opacity) * 0.2f }
        val visible: Boolean get() = opacity >= 0.01f
    }

    override fun onSurfaceCreated() {
        program = link(VERTEX, FRAGMENT)
        aPos = GLES20.glGetAttribLocation(program, "a_Pos")
        aNormal = GLES20.glGetAttribLocation(program, "a_Normal")
        uMvp = GLES20.glGetUniformLocation(program, "u_MVP")
        uModel = GLES20.glGetUniformLocation(program, "u_Model")
        uColor = GLES20.glGetUniformLocation(program, "u_Color")
        uLit = GLES20.glGetUniformLocation(program, "u_Lit")
        lastTick = 0L
    }

    override fun draw(frame: Frame, width: Int, height: Int) {
        val now = System.nanoTime()
        val dt = if (lastTick == 0L) 0f else ((now - lastTick) / 1e9f).coerceAtMost(0.1f)
        lastTick = now
        clock += dt

        val camera = frame.camera
        val tracking = camera.trackingState == TrackingState.TRACKING
        val layout = if (tracking) layout(frame) else Layout()

        for ((i, slot) in arrowSlots.withIndex()) {
            val mark = layout.arrows.getOrNull(i)
            if (mark == null) { slot.fade(0f); continue }
            slot.x = mark.x; slot.y = mark.y + 0.03f; slot.z = mark.z
            slot.yaw = yaw(mark.facing)
            // A bright band runs forward along the trail; the far end fades out.
            val wave = 0.5f + 0.5f * sin(clock * 5 - mark.ahead * 1.6f)
            val far = ((TRAIL_REACH - mark.ahead) / 2).coerceIn(0f, 1f)
            val near = ((mark.ahead - 0.6f) / 0.6f).coerceIn(0f, 1f)
            slot.fade((0.45f + 0.55f * wave) * far * near)
        }
        place(pinSlot, layout.pin, 0f, 0.06f)
        place(stairsUpSlot, layout.stairs?.takeIf { it.up }?.position, layout.stairs?.yaw ?: 0f, 0.04f)
        place(stairsDownSlot, layout.stairs?.takeIf { !it.up }?.position, layout.stairs?.yaw ?: 0f, 0.04f)

        camera.getViewMatrix(view, 0)
        camera.getProjectionMatrix(proj, 0, 0.05f, 100f)
        Matrix.multiplyMM(viewProj, 0, proj, 0, view, 0)
        report(if (tracking) hint(layout, frame) else RouteHint.HIDDEN)

        if (!tracking || program == 0) return
        GLES20.glUseProgram(program)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glDisable(GLES20.GL_CULL_FACE)

        // Flat on the floor, nothing in front of them: no depth.
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        for (slot in arrowSlots) {
            if (!slot.visible) continue
            setModel(slot.x, slot.y, slot.z, slot.yaw)
            Models.arrowRim.draw(this, WHITE, slot.opacity, lit = false)
            Models.arrow.draw(this, ORANGE, slot.opacity, lit = false)
        }

        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glDepthFunc(GLES20.GL_LEQUAL)
        if (pinSlot.visible) {
            // The pin's white dot faces whoever is looking at it.
            val pose = camera.pose
            setModel(pinSlot.x, pinSlot.y, pinSlot.z, atan2(pose.tx() - pinSlot.x, pose.tz() - pinSlot.z))
            Models.pinRing.draw(this, ORANGE, pinSlot.opacity, lit = false)
            Models.pinBody.draw(this, ORANGE, pinSlot.opacity, lit = true)
            Models.pinDot.draw(this, WHITE, pinSlot.opacity, lit = false)
        }
        drawStairs(stairsUpSlot, up = true)
        drawStairs(stairsDownSlot, up = false)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    private fun place(slot: Slot, position: FloatArray?, yaw: Float, bob: Float) {
        if (position == null) { slot.fade(0f); return }
        slot.x = position[0]; slot.y = position[1] + sin(clock * 2) * bob; slot.z = position[2]
        slot.yaw = yaw
        slot.fade(1f)
    }

    private fun drawStairs(slot: Slot, up: Boolean) {
        if (!slot.visible) return
        // Going down, the steps are turned side-on, like a stairs sign: seen from
        // their top end, steps that really descend away read as a flat slab.
        setModel(slot.x, slot.y, slot.z, slot.yaw + if (up) 0f else (PI / 2).toFloat())
        val steps = if (up) Models.stairsUp else Models.stairsDown
        steps.sides.draw(this, BLUE, slot.opacity, lit = true)
        steps.treads.draw(this, WHITE, slot.opacity, lit = true)

        // The arrow floats above the treads and keeps travelling the way to walk.
        val t = clock % TRAVEL_CYCLE
        val along = (t / TRAVEL_MOVE).coerceIn(0f, 1f)
        val alpha = when {
            t < 0.15f -> t / 0.15f
            t < TRAVEL_MOVE -> 1f
            t < TRAVEL_MOVE + 0.2f -> 1f - (t - TRAVEL_MOVE) / 0.2f
            else -> 0f
        }
        val low = floatArrayOf(0f, Models.RISE + Models.CLEAR, Models.RUN / 2)
        val high = floatArrayOf(0f, Models.HEIGHT + Models.CLEAR, -Models.RUN / 2)
        val from = if (up) low else high
        val to = if (up) high else low
        Matrix.translateM(model, 0, from[0] + (to[0] - from[0]) * along, from[1] + (to[1] - from[1]) * along, from[2] + (to[2] - from[2]) * along)
        val slope = atan2(Models.HEIGHT - Models.RISE, Models.RUN)
        // Tip (the arrow's +y) along the way to walk: up the slope, or down it.
        Matrix.rotateM(model, 0, Math.toDegrees((if (up) slope - PI / 2 else slope + PI / 2).toDouble()).toFloat(), 1f, 0f, 0f)
        Models.travelArrow.draw(this, ORANGE, slot.opacity * alpha, lit = true)
    }

    private fun setModel(x: Float, y: Float, z: Float, yaw: Float) {
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, x, y, z)
        Matrix.rotateM(model, 0, Math.toDegrees(yaw.toDouble()).toFloat(), 0f, 1f, 0f)
    }

    // MARK: What to draw

    private class Mark(val x: Float, val y: Float, val z: Float, val facing: Vec2, val ahead: Float)
    private class Stairs(val position: FloatArray, val yaw: Float, val up: Boolean)
    private class Layout(val arrows: List<Mark> = emptyList(), val pin: FloatArray? = null, val stairs: Stairs? = null)

    /** Everything in ARCore's session frame for this frame. */
    private fun layout(frame: Frame): Layout {
        val scene = scene ?: return Layout()
        val graph = scene.graph ?: return Layout()
        // Graph frame → session frame, through the anchor the fixes keep current.
        val fit = phone.currentFit() ?: return Layout()
        val session = ArCamera.floorPose(frame)
        val camera = fit.apply(session)
        val levels = graph.levels
        fun near(p: FloatArray) = hypot(p[0] - session.position.x, p[2] - session.position.z) < LANDMARK_RANGE

        // Arrived: the pin stays over the place.
        if (scene.phase == TourPhase.ARRIVED) {
            val node = scene.stopId?.let(graph::node) ?: return Layout()
            val floor = levels.floorHeight(node.id) ?: (camera.y - BuildingLevels.CAMERA_HEIGHT)
            return Layout(pin = fit.toSession(node.position.x, floor, node.position.z))
        }
        val nav = scene.nav
        if (scene.phase != TourPhase.LEADING || !nav.navigating || nav.path.isEmpty()) return Layout()
        val path = nav.path
        val cue = RouteCue(path, nav.leg, camera.position, camera.y, levels) { graph.node(it)?.position }

        // The staircase stands at the first step while the visitor walks up to it.
        var stairs: Stairs? = null
        val stage = cue.stage
        if (stage is RouteCue.Stage.StairsAhead) {
            val run = stage.run
            graph.node(path[run.start])?.let { foot ->
                var facing = Vec2(0f, -1f)
                path.getOrNull(run.start + 1)?.let(graph::node)?.let { next ->
                    val d = next.position - foot.position
                    if (d.length() > 0.05f) facing = d * (1 / d.length())
                }
                val position = fit.toSession(foot.position.x, cue.userFloorY + if (run.up) 0.4f else 0.5f, foot.position.z)
                if (near(position)) stairs = Stairs(position, yaw(fit.toSessionDirection(facing)), run.up)
            }
        }
        // No arrows on the steps themselves: the route's heights there are too
        // rough to draw on, and the way is obvious.
        if (stage is RouteCue.Stage.OnStairs) return Layout(stairs = stairs)

        val stops = ArrayList<GuidePlacement.Stop>()
        for (i in cue.target until path.size) {
            val node = graph.node(path[i]) ?: continue
            val hold = cue.run?.start == i
            // On the visitor's own floor the arrows lie on the floor under the
            // phone; marked heights vary by a few tens of centimetres.
            val sameFloor = levels.levelOf(path[i]) == cue.userLevel
            stops += GuidePlacement.Stop(node.position, if (sameFloor) cue.userFloorY else levels.floorHeight(path[i]), hold)
            if (hold) break
        }
        val arrows = GuidePlacement.trail(cue.user, cue.userFloorY, stops, TRAIL_START, TRAIL_REACH, TRAIL_SPACING).map { mark ->
            val p = fit.toSession(mark.x, mark.y, mark.z)
            Mark(p[0], p[1], p[2], fit.toSessionDirection(mark.facing), mark.planar.distanceTo(cue.user))
        }
        // The pin marks the place itself once it is on this floor and close.
        var pin: FloatArray? = null
        val last = path.last()
        if (cue.run == null && levels.levelOf(last) == cue.userLevel) {
            graph.node(last)?.let { node ->
                val position = fit.toSession(node.position.x, cue.userFloorY, node.position.z)
                if (near(position)) pin = position
            }
        }
        return Layout(arrows, pin, stairs)
    }

    // MARK: Which way to turn

    private fun report(hint: RouteHint) {
        if (hint == lastHint) return
        lastHint = hint
        main.post { onHint(hint) }
    }

    /** Whether the nearest thing to follow is on screen, or which way to turn to see it. */
    private fun hint(layout: Layout, frame: Frame): RouteHint {
        fun point(m: Mark) = floatArrayOf(m.x, m.y, m.z)
        val focus = layout.arrows.firstOrNull()?.let(::point) ?: layout.stairs?.position ?: layout.pin ?: return RouteHint.HIDDEN
        val shown = layout.arrows.take(4).map(::point) + listOfNotNull(layout.stairs?.position, layout.pin)
        val clip = FloatArray(4)
        for (p in shown) {
            Matrix.multiplyMV(clip, 0, viewProj, 0, floatArrayOf(p[0], p[1], p[2], 1f), 0)
            if (clip[3] > 0 && abs(clip[0] / clip[3]) < 0.95f && abs(clip[1] / clip[3]) < 0.92f) return RouteHint.VISIBLE
        }
        val pose = frame.camera.displayOrientedPose
        val x = pose.xAxis; val z = pose.zAxis
        val to = floatArrayOf(focus[0] - pose.tx(), focus[1] - pose.ty(), focus[2] - pose.tz())
        val forward = -(to[0] * z[0] + to[1] * z[1] + to[2] * z[2])
        val side = to[0] * x[0] + to[1] * x[1] + to[2] * x[2]
        // Straight ahead but off the bottom edge: the phone is held too high to see the floor.
        if (forward > 0 && abs(side) < forward * 0.5f) return RouteHint.DOWN
        return if (side >= 0) RouteHint.RIGHT else RouteHint.LEFT
    }

    // MARK: Drawing

    /** Triangles with a normal each vertex. */
    class Mesh(internal val data: FloatArray) {
        private val count = data.size / 6
        private val buffer: FloatBuffer =
            ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(data); position(0) }

        fun draw(o: RouteOverlay, rgb: FloatArray, alpha: Float, lit: Boolean) {
            if (alpha <= 0.003f) return
            Matrix.multiplyMM(o.mvp, 0, o.viewProj, 0, o.model, 0)
            GLES20.glUniformMatrix4fv(o.uMvp, 1, false, o.mvp, 0)
            GLES20.glUniformMatrix4fv(o.uModel, 1, false, o.model, 0)
            GLES20.glUniform4f(o.uColor, rgb[0], rgb[1], rgb[2], alpha.coerceIn(0f, 1f))
            GLES20.glUniform1f(o.uLit, if (lit) 1f else 0f)
            buffer.position(0)
            GLES20.glVertexAttribPointer(o.aPos, 3, GLES20.GL_FLOAT, false, 24, buffer)
            GLES20.glEnableVertexAttribArray(o.aPos)
            buffer.position(3)
            GLES20.glVertexAttribPointer(o.aNormal, 3, GLES20.GL_FLOAT, false, 24, buffer)
            GLES20.glEnableVertexAttribArray(o.aNormal)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, count)
            GLES20.glDisableVertexAttribArray(o.aPos)
            GLES20.glDisableVertexAttribArray(o.aNormal)
        }
    }

    companion object {
        /** Arrows start this far ahead of the visitor and run this far, metres. */
        const val TRAIL_START = 1.2f
        const val TRAIL_REACH = 8f
        const val TRAIL_SPACING = 0.8f
        /** The pin and the staircase are drawn only within this distance, metres. */
        const val LANDMARK_RANGE = 18f
        private val ARROW_COUNT = ((TRAIL_REACH - TRAIL_START) / TRAIL_SPACING).toInt() + 2
        private const val TRAVEL_MOVE = 1.1f
        private const val TRAVEL_CYCLE = TRAVEL_MOVE + 0.2f + 0.15f

        private val ORANGE = floatArrayOf(0xEF / 255f, 0x7C / 255f, 0f)
        private val BLUE = floatArrayOf(0f, 0x3D / 255f, 0x7C / 255f)
        private val WHITE = floatArrayOf(1f, 1f, 1f)

        /** Turn about the vertical that points a model's forward (−z) along [facing] (x, z). */
        fun yaw(facing: Vec2): Float = atan2(-facing.x, -facing.z)

        private const val VERTEX = """
            uniform mat4 u_MVP;
            uniform mat4 u_Model;
            attribute vec3 a_Pos;
            attribute vec3 a_Normal;
            varying vec3 v_Normal;
            void main() {
                gl_Position = u_MVP * vec4(a_Pos, 1.0);
                v_Normal = (u_Model * vec4(a_Normal, 0.0)).xyz;
            }
        """
        private const val FRAGMENT = """
            precision mediump float;
            uniform vec4 u_Color;
            uniform float u_Lit;
            varying vec3 v_Normal;
            void main() {
                float d = max(dot(normalize(v_Normal), normalize(vec3(0.35, 1.0, 0.45))), 0.0);
                float shade = mix(1.0, 0.62 + 0.38 * d, u_Lit);
                gl_FragColor = vec4(u_Color.rgb * shade, u_Color.a);
            }
        """

        private fun link(vs: String, fs: String): Int {
            fun compile(type: Int, src: String) = GLES20.glCreateShader(type).also { GLES20.glShaderSource(it, src); GLES20.glCompileShader(it) }
            return GLES20.glCreateProgram().also {
                GLES20.glAttachShader(it, compile(GLES20.GL_VERTEX_SHADER, vs))
                GLES20.glAttachShader(it, compile(GLES20.GL_FRAGMENT_SHADER, fs))
                GLES20.glLinkProgram(it)
            }
        }
    }
}

/** The 3D shapes drawn on the camera view, in metres (iOS `RouteModels`). */
internal object Models {
    const val STEPS = 5
    const val DEPTH = 0.2f
    const val RISE = 0.14f
    const val RUN = DEPTH * STEPS
    const val HEIGHT = RISE * STEPS
    /** How far the travelling arrow floats above the treads. */
    const val CLEAR = 0.3f

    /** A chevron lying on the floor, pointing along −z; a white rim under the orange so it reads on any floor. */
    val arrowRim = RouteOverlay.Mesh(chevron(0.56f, 0.44f, 0.20f, 0f))
    val arrow = RouteOverlay.Mesh(chevron(0.46f, 0.34f, 0.14f, 0.004f))

    /** A map pin floating over the place, its tip about head height. */
    val pinBody = RouteOverlay.Mesh(Shape().sphere(0f, 1.62f, 0f, 0.14f).cone(1.55f, 1.25f, 0.11f).build())
    val pinDot = RouteOverlay.Mesh(Shape().sphere(0f, 1.62f, 0f, 0.055f, sz = 2.9f).build())
    val pinRing = RouteOverlay.Mesh(Shape().ring(0.03f, 0.30f, 0.34f).build())

    class Staircase(val sides: RouteOverlay.Mesh, val treads: RouteOverlay.Mesh)

    /** Five steps climbing away from the viewer along −z. */
    val stairsUp = staircase(0.8f)
    val stairsDown = staircase(0.5f)

    /** A cone on a shaft, tip along +y, about its own middle. */
    val travelArrow = RouteOverlay.Mesh(Shape().cone(0f, 0.24f, 0.11f).cylinder(-0.26f, 0f, 0.04f).build())

    private fun staircase(width: Float): Staircase {
        val sides = Shape(); val treads = Shape()
        for (k in 0 until STEPS) {
            val h = RISE * (k + 1)
            val z = RUN / 2 - DEPTH / 2 - k * DEPTH
            sides.box(0f, h / 2, z, width, h, DEPTH, top = false)
            treads.boxTop(0f, h, z, width, DEPTH)
        }
        return Staircase(RouteOverlay.Mesh(sides.build()), RouteOverlay.Mesh(treads.build()))
    }

    private fun chevron(w: Float, l: Float, notch: Float, lift: Float): FloatArray {
        // The shape in (x, forward): the tip, the two arms, the notch behind the tip.
        val tip = floatArrayOf(0f, l / 2)
        val inner = floatArrayOf(0f, l / 2 - notch)
        val shape = Shape()
        for (side in floatArrayOf(1f, -1f)) {
            val outer = floatArrayOf(side * w / 2, -l / 2 + notch)
            val back = floatArrayOf(side * w / 2, -l / 2)
            fun v(p: FloatArray) = floatArrayOf(p[0], lift, -p[1])   // forward is −z
            shape.quad(v(tip), v(outer), v(back), v(inner), floatArrayOf(0f, 1f, 0f))
        }
        return shape.build()
    }

    /** Collects triangles as x, y, z, nx, ny, nz. */
    private class Shape {
        private val data = ArrayList<Float>()

        fun build() = data.toFloatArray()

        private fun vertex(p: FloatArray, n: FloatArray) { data += p[0]; data += p[1]; data += p[2]; data += n[0]; data += n[1]; data += n[2] }

        fun tri(a: FloatArray, b: FloatArray, c: FloatArray, na: FloatArray, nb: FloatArray = na, nc: FloatArray = na) {
            vertex(a, na); vertex(b, nb); vertex(c, nc)
        }

        fun quad(a: FloatArray, b: FloatArray, c: FloatArray, d: FloatArray, n: FloatArray) { tri(a, b, c, n); tri(a, c, d, n) }

        fun sphere(cx: Float, cy: Float, cz: Float, r: Float, sz: Float = 1f): Shape {
            val stacks = 10; val slices = 16
            fun at(i: Int, j: Int): Pair<FloatArray, FloatArray> {
                val phi = PI.toFloat() * i / stacks
                val theta = 2 * PI.toFloat() * j / slices
                val n = floatArrayOf(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                return floatArrayOf(cx + r * n[0], cy + r * n[1], cz + r * n[2] * sz) to n
            }
            for (i in 0 until stacks) for (j in 0 until slices) {
                val (a, na) = at(i, j); val (b, nb) = at(i + 1, j); val (c, nc) = at(i + 1, j + 1); val (d, nd) = at(i, j + 1)
                tri(a, b, c, na, nb, nc); tri(a, c, d, na, nc, nd)
            }
            return this
        }

        /** A cone about the vertical axis: a disc of [radius] at [baseY], the point at [apexY]. */
        fun cone(baseY: Float, apexY: Float, radius: Float): Shape {
            val slices = 16
            val apex = floatArrayOf(0f, apexY, 0f)
            val lean = radius / (apexY - baseY)   // how far the side's normal tips toward the apex
            for (j in 0 until slices) {
                val t0 = 2 * PI.toFloat() * j / slices; val t1 = 2 * PI.toFloat() * (j + 1) / slices
                val a = floatArrayOf(radius * cos(t0), baseY, radius * sin(t0))
                val b = floatArrayOf(radius * cos(t1), baseY, radius * sin(t1))
                val tm = (t0 + t1) / 2
                tri(a, b, apex, floatArrayOf(cos(t0), lean, sin(t0)), floatArrayOf(cos(t1), lean, sin(t1)), floatArrayOf(cos(tm), lean, sin(tm)))
                tri(a, b, floatArrayOf(0f, baseY, 0f), floatArrayOf(0f, if (apexY > baseY) -1f else 1f, 0f))
            }
            return this
        }

        fun cylinder(y0: Float, y1: Float, radius: Float): Shape {
            val slices = 12
            for (j in 0 until slices) {
                val t0 = 2 * PI.toFloat() * j / slices; val t1 = 2 * PI.toFloat() * (j + 1) / slices
                val n0 = floatArrayOf(cos(t0), 0f, sin(t0)); val n1 = floatArrayOf(cos(t1), 0f, sin(t1))
                val a = floatArrayOf(radius * n0[0], y0, radius * n0[2]); val b = floatArrayOf(radius * n1[0], y0, radius * n1[2])
                val c = floatArrayOf(radius * n1[0], y1, radius * n1[2]); val d = floatArrayOf(radius * n0[0], y1, radius * n0[2])
                tri(a, b, c, n0, n1, n1); tri(a, c, d, n0, n1, n0)
                tri(a, b, floatArrayOf(0f, y0, 0f), floatArrayOf(0f, -1f, 0f))
            }
            return this
        }

        /** A flat ring on the floor. */
        fun ring(y: Float, inner: Float, outer: Float): Shape {
            val slices = 32
            val up = floatArrayOf(0f, 1f, 0f)
            for (j in 0 until slices) {
                val t0 = 2 * PI.toFloat() * j / slices; val t1 = 2 * PI.toFloat() * (j + 1) / slices
                quad(floatArrayOf(inner * cos(t0), y, inner * sin(t0)), floatArrayOf(outer * cos(t0), y, outer * sin(t0)),
                    floatArrayOf(outer * cos(t1), y, outer * sin(t1)), floatArrayOf(inner * cos(t1), y, inner * sin(t1)), up)
            }
            return this
        }

        /** A box about its centre; [top] false leaves the top face to [boxTop]. */
        fun box(cx: Float, cy: Float, cz: Float, w: Float, h: Float, l: Float, top: Boolean): Shape {
            val x0 = cx - w / 2; val x1 = cx + w / 2; val y0 = cy - h / 2; val y1 = cy + h / 2; val z0 = cz - l / 2; val z1 = cz + l / 2
            fun p(x: Float, y: Float, z: Float) = floatArrayOf(x, y, z)
            quad(p(x0, y0, z1), p(x1, y0, z1), p(x1, y1, z1), p(x0, y1, z1), floatArrayOf(0f, 0f, 1f))    // front
            quad(p(x1, y0, z0), p(x0, y0, z0), p(x0, y1, z0), p(x1, y1, z0), floatArrayOf(0f, 0f, -1f))   // back
            quad(p(x1, y0, z1), p(x1, y0, z0), p(x1, y1, z0), p(x1, y1, z1), floatArrayOf(1f, 0f, 0f))    // right
            quad(p(x0, y0, z0), p(x0, y0, z1), p(x0, y1, z1), p(x0, y1, z0), floatArrayOf(-1f, 0f, 0f))   // left
            quad(p(x0, y0, z0), p(x1, y0, z0), p(x1, y0, z1), p(x0, y0, z1), floatArrayOf(0f, -1f, 0f))   // bottom
            if (top) boxTop(cx, y1, cz, w, l)
            return this
        }

        fun boxTop(cx: Float, y: Float, cz: Float, w: Float, l: Float): Shape {
            val x0 = cx - w / 2; val x1 = cx + w / 2; val z0 = cz - l / 2; val z1 = cz + l / 2
            quad(floatArrayOf(x0, y, z1), floatArrayOf(x1, y, z1), floatArrayOf(x1, y, z0), floatArrayOf(x0, y, z0), floatArrayOf(0f, 1f, 0f))
            return this
        }
    }
}
