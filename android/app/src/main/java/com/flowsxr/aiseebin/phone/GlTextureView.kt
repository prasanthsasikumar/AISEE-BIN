package com.flowsxr.aiseebin.phone

import android.content.Context
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLSurfaceView
import android.view.TextureView

/**
 * A TextureView driving a [GLSurfaceView.Renderer] on its own GL thread.
 * Not a GLSurfaceView: a SurfaceView under Compose punched the window
 * transparent beyond its own bounds on these phones (the header vanished over
 * the camera), while a TextureView composites like any other view.
 */
class GlTextureView(context: Context, private val renderer: GLSurfaceView.Renderer) : TextureView(context), TextureView.SurfaceTextureListener {
    private val lock = Object()
    private var thread: Thread? = null
    private var texture: SurfaceTexture? = null
    private var width = 0
    private var height = 0
    private var sizeChanged = false
    private var paused = true
    private var exiting = false
    /** The GL thread is parked between frames, so the AR session can be paused safely. */
    private var parked = true

    init {
        surfaceTextureListener = this
        isOpaque = true
    }

    fun onResume() = synchronized(lock) { paused = false; lock.notifyAll() }

    /** Returns once the GL thread has finished its frame, like GLSurfaceView.onPause. */
    fun onPause() = synchronized(lock) {
        paused = true
        lock.notifyAll()
        val until = System.currentTimeMillis() + 500
        while (!parked && thread != null && System.currentTimeMillis() < until) lock.wait(50)
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, w: Int, h: Int) {
        synchronized(lock) {
            texture = surface; width = w; height = h; sizeChanged = true; exiting = false
            thread = Thread(::loop, "ar-gl").also { it.start() }
        }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, w: Int, h: Int) =
        synchronized(lock) { width = w; height = h; sizeChanged = true }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        val t = synchronized(lock) { exiting = true; lock.notifyAll(); thread.also { thread = null } }
        t?.join(1000)
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    private fun loop() {
        val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 1)
        val configs = arrayOfNulls<EGLConfig>(1)
        EGL14.eglChooseConfig(display, intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_NONE,
        ), 0, configs, 0, 1, IntArray(1), 0)
        val context: EGLContext = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        val surface: EGLSurface = EGL14.eglCreateWindowSurface(display, configs[0], synchronized(lock) { texture }, intArrayOf(EGL14.EGL_NONE), 0)
        EGL14.eglMakeCurrent(display, surface, surface, context)
        renderer.onSurfaceCreated(null, null)
        try {
            while (true) {
                val (w, h, changed) = synchronized(lock) {
                    while (paused && !exiting) { parked = true; lock.notifyAll(); lock.wait() }
                    if (exiting) return
                    parked = false
                    Triple(width, height, sizeChanged).also { sizeChanged = false }
                }
                if (changed) renderer.onSurfaceChanged(null, w, h)
                renderer.onDrawFrame(null)
                EGL14.eglSwapBuffers(display, surface)
            }
        } catch (_: InterruptedException) {
        } finally {
            synchronized(lock) { parked = true; lock.notifyAll() }
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroySurface(display, surface)
            EGL14.eglDestroyContext(display, context)
            // No eglTerminate: the default display is shared with the system UI renderer.
        }
    }
}
