package com.flowsxr.aiseebin.usage

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Lines waiting to be uploaded, one JSON object per line in `queue.jsonl`.
 * Survives restarts: a line leaves the file only after its upload succeeded or
 * was rejected. Not thread-safe on its own; [UsageLog] drives it from one
 * serial executor.
 */
class UsageQueue(val directory: File) {
    val file: File get() = File(directory, "queue.jsonl")

    /** Appends one line. Starts on a fresh line if a crash left the last one unfinished. */
    fun append(line: String) {
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create $directory")
        val f = file
        val needsBreak = f.length() > 0 && f.inputStream().use { it.skip(f.length() - 1); it.read() } != '\n'.code
        FileOutputStream(f, true).use { out ->
            if (needsBreak) out.write('\n'.code)
            out.write((line + "\n").toByteArray(Charsets.UTF_8))
        }
    }

    /** The oldest [max] lines, without removing them. */
    fun peekBatch(max: Int): List<String> {
        if (!file.isFile) return emptyList()
        return file.useLines(Charsets.UTF_8) { seq -> seq.filter { it.isNotEmpty() }.take(max).toList() }
    }

    /** Removes the oldest [count] lines (after they were uploaded). */
    fun drop(count: Int) {
        val rest = lines().drop(count)
        if (rest.isEmpty()) {
            file.delete()
            return
        }
        val tmp = File(directory, "queue.jsonl.tmp")
        tmp.writeText(rest.joinToString(separator = "\n", postfix = "\n"), Charsets.UTF_8)
        if (!tmp.renameTo(file)) throw IOException("cannot replace $file")
    }

    /** Drops the oldest lines beyond [keepingLast]; returns how many were dropped. */
    fun trim(keepingLast: Int): Int {
        val excess = lines().size - keepingLast
        if (excess <= 0) return 0
        drop(excess)
        return excess
    }

    /** Throws on a read error, so a failed read never looks like an empty queue to [drop]. */
    private fun lines(): List<String> =
        if (!file.isFile) emptyList() else file.readLines(Charsets.UTF_8).filter { it.isNotEmpty() }
}
