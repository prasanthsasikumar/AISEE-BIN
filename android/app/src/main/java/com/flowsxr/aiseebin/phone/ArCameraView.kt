package com.flowsxr.aiseebin.phone

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.ar.core.Frame

/**
 * The phone camera, full bleed, with ARCore tracking behind it. The session
 * runs while this is on screen and the app is in front, and pauses otherwise.
 */
@Composable
fun ArCameraView(camera: ArCamera, onFrame: (Frame) -> Unit, modifier: Modifier = Modifier) {
    val activity = LocalContext.current as Activity
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val renderer = remember(camera) { ArRenderer(camera, onFrame) }
    val view = remember(camera) {
        GlTextureView(activity, renderer)
    }
    DisposableEffect(lifecycle, camera) {
        fun resume() {
            renderer.rotation = view.display?.rotation ?: 0
            if (camera.resume(activity)) view.onResume()
        }
        fun pause() { view.onPause(); camera.pause() }
        val observer = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> resume()
                Lifecycle.Event.ON_PAUSE -> pause()
                else -> Unit
            }
        }
        if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) resume()
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer); pause() }
    }
    AndroidView(factory = { view }, modifier = modifier)
}
