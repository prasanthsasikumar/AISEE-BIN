package com.flowsxr.aiseebin

import android.content.Context
import android.media.AudioAttributes
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

/**
 * Spoken output. Uses the media stream, so with the glasses connected as a
 * Bluetooth headset it plays over A2DP — the iOS lesson was that the call
 * (HFP) route made the glasses say "call ended" after every utterance.
 */
class Speaker(context: Context) {
    private var ready = false
    private val pending = mutableListOf<String>()
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
            configure()
            synchronized(pending) { pending.forEach { say(it, interrupt = false) }; pending.clear() }
        } else {
            Log.w("Speaker", "TextToSpeech init failed: $status")
        }
    }

    private fun configure() {
        tts.language = Locale.getDefault().takeIf { tts.isLanguageAvailable(it) >= TextToSpeech.LANG_AVAILABLE } ?: Locale.US
        tts.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
    }

    fun say(text: String, interrupt: Boolean = true) {
        if (!ready) { synchronized(pending) { pending += text }; return }
        tts.speak(text, if (interrupt) TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD, null, text.hashCode().toString())
    }

    fun shutdown() = tts.shutdown()
}
