package com.flowsxr.aiseebin.phone

import android.app.Activity
import android.content.Context
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import com.flowsxr.aiseebin.immersal.GlassesCamera
import com.flowsxr.aiseebin.immersal.GrayImage
import com.flowsxr.aiseebin.map.Vec2
import com.flowsxr.aiseebin.positioning.FloorPose
import com.flowsxr.aiseebin.positioning.PhoneShot
import com.google.ar.core.ArCoreApk
import com.google.ar.core.CameraConfig
import com.google.ar.core.CameraConfigFilter
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingFailureReason
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.UnavailableApkTooOldException
import com.google.ar.core.exceptions.UnavailableArcoreNotInstalledException
import com.google.ar.core.exceptions.UnavailableUserDeclinedInstallationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2

/** Whether this phone can track itself with ARCore. */
enum class ArSupport { CHECKING, SUPPORTED, UNSUPPORTED }

/**
 * The ARCore session behind phone-camera positioning: created when the camera
 * view first shows, resumed and paused with it, so the camera only runs while
 * Navigate is on screen (as on iOS, where the AR view is Navigate).
 */
class ArCamera(private val context: Context) {
    private val _support = MutableStateFlow(ArSupport.CHECKING)
    val support: StateFlow<ArSupport> = _support
    private val _error = MutableStateFlow<String?>(null)
    /** Why the session could not start, for the screen. */
    val error: StateFlow<String?> = _error

    var session: Session? = null; private set
    private var installRequested = false
    var log: (String) -> Unit = {}

    /** ARCore answers "checking" for a moment after start-up; ask again until it knows. */
    fun checkSupport() {
        val a = runCatching { ArCoreApk.getInstance().checkAvailability(context) }.getOrNull()
        _support.value = when {
            a == null -> ArSupport.UNSUPPORTED
            a.isTransient -> ArSupport.CHECKING
            a.isSupported -> ArSupport.SUPPORTED
            else -> ArSupport.UNSUPPORTED
        }
    }

    /** Creates (installing ARCore first if needed) and resumes the session. Main thread. */
    fun resume(activity: Activity): Boolean {
        if (session == null) {
            try {
                if (ArCoreApk.getInstance().requestInstall(activity, !installRequested) == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                    installRequested = true
                    _error.value = "Installing Google Play Services for AR…"
                    return false
                }
                session = Session(activity).also(::configure)
            } catch (e: UnavailableUserDeclinedInstallationException) {
                return fail("Google Play Services for AR is needed for the phone camera.")
            } catch (e: UnavailableArcoreNotInstalledException) {
                return fail("Google Play Services for AR is not installed.")
            } catch (e: UnavailableApkTooOldException) {
                return fail("Google Play Services for AR needs an update.")
            } catch (e: Exception) {
                return fail("The phone camera can't track: ${e.message ?: e.javaClass.simpleName}")
            }
        }
        return try {
            session?.resume()
            _error.value = null
            true
        } catch (e: Exception) {
            fail("The camera is busy or not allowed: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    fun pause() { runCatching { session?.pause() } }

    fun close() { runCatching { session?.close() }; session = null }

    private fun fail(why: String): Boolean { _error.value = why; log("arcore: $why"); return false }

    private fun configure(s: Session) {
        // The largest CPU image up to 1920 wide: Immersal gets ARKit-like detail, scaled to 960.
        val configs = s.getSupportedCameraConfigs(CameraConfigFilter(s).setFacingDirection(CameraConfig.FacingDirection.BACK))
        configs.filter { it.imageSize.width <= 1920 }.maxByOrNull { it.imageSize.width * it.imageSize.height }?.let {
            s.cameraConfig = it
            log("arcore camera: cpu ${it.imageSize.width}x${it.imageSize.height}, gpu ${it.textureSize.width}x${it.textureSize.height}")
        }
        s.configure(Config(s).apply {
            focusMode = Config.FocusMode.AUTO
            planeFindingMode = Config.PlaneFindingMode.DISABLED
            lightEstimationMode = Config.LightEstimationMode.DISABLED
            updateMode = Config.UpdateMode.BLOCKING
        })
    }

    companion object {
        /** The camera's floor pose in ARCore's frame. ARCore cameras look down −Z, like ARKit's. */
        fun floorPose(frame: Frame): FloorPose {
            val pose = frame.camera.pose
            val z = pose.zAxis
            // forward = −z; heading = atan2(forward.x, −forward.z) (NavigationGeometry.heading).
            return FloorPose(Vec2(pose.tx(), pose.tz()), atan2(-z[0], z[2]))
        }

        fun problem(frame: Frame): String? {
            val camera = frame.camera
            if (camera.trackingState == TrackingState.TRACKING) return null
            return when (camera.trackingFailureReason) {
                TrackingFailureReason.INSUFFICIENT_LIGHT -> "Too dark for the camera"
                TrackingFailureReason.EXCESSIVE_MOTION -> "Moving too fast"
                TrackingFailureReason.INSUFFICIENT_FEATURES -> "Point the camera at something with more detail"
                TrackingFailureReason.CAMERA_UNAVAILABLE -> "Camera in use by another app"
                TrackingFailureReason.BAD_STATE -> "Camera tracking failed"
                else -> "Move the phone slowly to start tracking"
            }
        }

        /** The luma plane and ARCore's intrinsics for it, or null if the image is not ready. */
        fun shot(frame: Frame): PhoneShot? = runCatching {
            frame.acquireCameraImage().use { image ->
                val plane = image.planes[0]
                val w = image.width; val h = image.height
                val src = plane.buffer
                val stride = plane.rowStride
                val out = ByteArray(w * h)
                if (stride == w) src.get(out, 0, w * h)
                else for (y in 0 until h) { src.position(y * stride); src.get(out, y * w, w) }
                val k = frame.camera.imageIntrinsics
                val f = k.focalLength; val c = k.principalPoint
                PhoneShot(GrayImage(w, h, out), GlassesCamera.Intrinsics(f[0], f[1], c[0], c[1]))
            }
        }.getOrNull()
    }
}

/**
 * Draws ARCore's camera image full screen and hands each frame on. Runs on
 * the GLSurfaceView's thread.
 */
class ArRenderer(private val camera: ArCamera, private val onFrame: (Frame) -> Unit) : GLSurfaceView.Renderer {
    private var texture = 0
    private var program = 0
    private var width = 0
    private var height = 0
    @Volatile var rotation = 0
    private val quad = floatBuffer(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
    private val uv = floatBuffer(FloatArray(8))
    private var geometrySet = false

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.047f, 0.043f, 0.071f, 1f)
        val t = IntArray(1)
        GLES20.glGenTextures(1, t, 0)
        texture = t[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        program = link(VERTEX, FRAGMENT)
        geometrySet = false
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        this.width = width; this.height = height
        geometrySet = false
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        // No session or a paused one: wait a frame rather than spin the GL thread.
        val session = camera.session ?: return Thread.sleep(IDLE_MS)
        if (!geometrySet && width > 0) { session.setDisplayGeometry(rotation, width, height); geometrySet = true }
        session.setCameraTextureName(texture)
        val frame = runCatching { session.update() }.getOrNull() ?: return Thread.sleep(IDLE_MS)
        if (frame.hasDisplayGeometryChanged()) {
            quad.position(0); uv.position(0)
            frame.transformCoordinates2d(Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES, quad, Coordinates2d.TEXTURE_NORMALIZED, uv)
        }
        if (frame.timestamp != 0L) draw()
        onFrame(frame)
    }

    private fun draw() {
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, texture)
        val pos = GLES20.glGetAttribLocation(program, "a_Position")
        val tex = GLES20.glGetAttribLocation(program, "a_TexCoord")
        quad.position(0); uv.position(0)
        GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 0, quad)
        GLES20.glVertexAttribPointer(tex, 2, GLES20.GL_FLOAT, false, 0, uv)
        GLES20.glEnableVertexAttribArray(pos)
        GLES20.glEnableVertexAttribArray(tex)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(pos)
        GLES20.glDisableVertexAttribArray(tex)
    }

    private companion object {
        const val IDLE_MS = 16L
        const val VERTEX = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() { gl_Position = a_Position; v_TexCoord = a_TexCoord; }
        """
        const val FRAGMENT = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES s_Texture;
            void main() { gl_FragColor = texture2D(s_Texture, v_TexCoord); }
        """

        fun floatBuffer(values: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(values); position(0) }

        fun link(vs: String, fs: String): Int {
            fun compile(type: Int, src: String) = GLES20.glCreateShader(type).also { GLES20.glShaderSource(it, src); GLES20.glCompileShader(it) }
            return GLES20.glCreateProgram().also {
                GLES20.glAttachShader(it, compile(GLES20.GL_VERTEX_SHADER, vs))
                GLES20.glAttachShader(it, compile(GLES20.GL_FRAGMENT_SHADER, fs))
                GLES20.glLinkProgram(it)
            }
        }
    }
}
