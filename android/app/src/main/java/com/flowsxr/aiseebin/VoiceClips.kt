package com.flowsxr.aiseebin

import android.content.res.AssetFileDescriptor
import android.content.res.AssetManager
import android.util.Log
import org.json.JSONObject

/**
 * Recorded clips for the fixed phrases the app speaks most (see `voice/` in the
 * repo). [Speaker] plays a clip when the text matches one exactly, and the
 * system voice speaks everything else.
 */
class VoiceClips(private val assets: AssetManager, private val files: Map<String, String>) {

    fun has(text: String) = normalise(text) in files

    /** The clip for [text], if one was recorded. The caller closes it. */
    fun open(text: String): AssetFileDescriptor? {
        val file = files[normalise(text)] ?: return null
        return runCatching { assets.openFd("clips/$file") }.getOrNull()
    }

    companion object {
        /** Must match `normalise` in voice/generate.py and VoiceClips.swift. */
        fun normalise(text: String): String =
            text.replace('’', '\'').lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

        fun load(assets: AssetManager): VoiceClips {
            val files = runCatching {
                val clips = JSONObject(assets.open("clips/index.json").bufferedReader().use { it.readText() })
                    .getJSONObject("clips")
                clips.keys().asSequence().associateWith { clips.getJSONObject(it).getString("file") }
            }.getOrElse {
                Log.w("Speaker", "no recorded clips: $it")
                emptyMap()
            }
            return VoiceClips(assets, files)
        }
    }
}
