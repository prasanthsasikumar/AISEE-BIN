package com.flowsxr.aiseebin

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

/**
 * Spoken output. Phrases with a recorded clip ([VoiceClips]) play the clip;
 * everything else goes to the system TextToSpeech. Both use the media stream, so
 * with the glasses connected as a Bluetooth headset it plays over A2DP — the iOS
 * lesson was that the call (HFP) route made the glasses say "call ended" after
 * every utterance.
 *
 * Clips and speech share one queue, kept on the main thread, so a clip waits
 * behind a sentence the system voice is still reading and the other way round.
 */
class Speaker(context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val clips = VoiceClips.load(context.applicationContext.assets)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private var ready = false
    private val queue = ArrayDeque<String>()
    private var player: MediaPlayer? = null
    private var currentId: String? = null
    private var nextId = 0

    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        main.post {
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                configure()
                if (!busy) next()
            } else {
                Log.w("Speaker", "TextToSpeech init failed: $status")
            }
        }
    }

    private val busy get() = player != null || currentId != null

    private fun configure() {
        tts.language = Locale.getDefault().takeIf { tts.isLanguageAvailable(it) >= TextToSpeech.LANG_AVAILABLE } ?: Locale.US
        tts.setAudioAttributes(attributes)
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) = finished(utteranceId)
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) = finished(utteranceId)
            override fun onStop(utteranceId: String?, interrupted: Boolean) = finished(utteranceId)
        })
    }

    fun say(text: String, interrupt: Boolean = true) {
        main.post {
            if (interrupt) stopNow()
            queue.addLast(text)
            if (!busy) next()
        }
    }

    private fun stopNow() {
        queue.clear()
        player?.run { stop(); release() }
        player = null
        if (currentId != null) {
            currentId = null
            if (ready) tts.stop()
        }
    }

    private fun next() {
        val text = queue.removeFirstOrNull() ?: return
        if (playClip(text)) return
        if (!ready) {
            // Wait for TextToSpeech; init posts next() when it is up.
            queue.addFirst(text)
            return
        }
        val id = "u${nextId++}"
        currentId = id
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
    }

    private fun playClip(text: String): Boolean {
        val fd = clips.open(text) ?: return false
        val mp = MediaPlayer()
        return runCatching {
            fd.use { mp.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            mp.setAudioAttributes(attributes)
            mp.setOnCompletionListener { done(it) }
            mp.setOnErrorListener { p, _, _ -> done(p); true }
            mp.prepare()
            player = mp
            mp.start()
        }.onFailure {
            Log.w("Speaker", "clip failed, using the system voice: $it")
            if (player === mp) player = null
            mp.release()
        }.isSuccess
    }

    private fun done(mp: MediaPlayer) {
        if (player !== mp) return
        mp.release()
        player = null
        next()
    }

    private fun finished(utteranceId: String?) {
        main.post {
            if (utteranceId == null || utteranceId != currentId) return@post
            currentId = null
            next()
        }
    }

    fun shutdown() {
        main.post { stopNow() }
        tts.shutdown()
    }
}
