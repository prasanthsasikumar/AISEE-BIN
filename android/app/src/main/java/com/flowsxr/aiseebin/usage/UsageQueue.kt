package com.flowsxr.aiseebin.usage

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile

/**
 * Lines waiting to be uploaded, one JSON object per line in `queue.jsonl`.
 * Survives restarts: a line leaves the queue only after its upload succeeded or
 * was rejected. Not thread-safe on its own; [UsageLog] drives it from one
 * serial executor.
 *
 * Draining is linear: `queue.offset` holds how many bytes at the front of the
 * file are already uploaded. Dropping lines only advances that offset; the file
 * is rewritten (compacted) only once the consumed part is more than half of it,
 * so a long backlog is copied a handful of times, not once per batch.
 *
 * Crash safety: the offset only ever points at or before the first line not yet
 * uploaded. Whenever the file is replaced or removed, the offset is reset first,
 * so a crash in between re-uploads lines (the server ignores duplicates)
 * instead of skipping any.
 *
 * @param onCompact called after each compaction (the file rewritten); tests count them.
 */
class UsageQueue(val directory: File, private val onCompact: (() -> Unit)? = null) {
    val file: File get() = File(directory, "queue.jsonl")
    val offsetFile: File get() = File(directory, "queue.offset")

    /** Appends one line. Starts on a fresh line if a crash left the last one unfinished. */
    fun append(line: String) {
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create $directory")
        val f = file
        // An offset left from an earlier file would skip lines of this one.
        if (!f.exists()) removeIfPresent(offsetFile)
        val needsBreak = f.length() > 0 && f.inputStream().use { it.skip(f.length() - 1); it.read() } != '\n'.code
        FileOutputStream(f, true).use { out ->
            if (needsBreak) out.write('\n'.code)
            out.write((line + "\n").toByteArray(Charsets.UTF_8))
        }
    }

    /** The oldest [max] lines, without removing them. Throws on a read error. */
    fun peekBatch(max: Int): List<String> =
        scan(offset(), max, keep = true).lines.map { it.toString(Charsets.UTF_8) }

    /** Removes the oldest [count] lines (after they were uploaded). Throws on a read error without touching the queue. */
    fun drop(count: Int) {
        if (count <= 0) return
        advance(scan(offset(), count, keep = false).end)
    }

    /** Drops the oldest lines beyond [keepingLast]; returns how many were dropped. */
    fun trim(keepingLast: Int): Int {
        val start = offset()
        // Every line takes at least two bytes with its newline: a short file cannot be over the cap.
        if (file.length() - start < 2L * (keepingLast + 1)) return 0
        val excess = scan(start, Int.MAX_VALUE, keep = false).count - keepingLast
        if (excess <= 0) return 0
        drop(excess)
        return excess
    }

    // Offset.

    /** Bytes at the front of the file already uploaded; 0 if unknown or stale. */
    private fun offset(): Long {
        if (!offsetFile.exists()) return 0
        val value = offsetFile.readText(Charsets.UTF_8).trim().toLongOrNull() ?: return 0
        return if (value in 0..file.length()) value else 0
    }

    private fun writeOffset(value: Long) {
        val tmp = File(directory, "queue.offset.tmp")
        tmp.writeText(value.toString(), Charsets.UTF_8)
        if (!tmp.renameTo(offsetFile)) throw IOException("cannot replace $offsetFile")
    }

    /** Marks everything before [end] as uploaded: removes the queue when it is all
     *  consumed, compacts it when more than half is, else moves the offset. */
    private fun advance(end: Long) {
        val size = file.length()
        when {
            end >= size -> {
                removeIfPresent(offsetFile)
                removeIfPresent(file)
            }
            end > size / 2 -> {
                val tmp = File(directory, "queue.jsonl.tmp")
                FileInputStream(file).use { input ->
                    input.channel.position(end)
                    FileOutputStream(tmp).use { out -> input.copyTo(out); out.fd.sync() }
                }
                writeOffset(0)
                if (!tmp.renameTo(file)) throw IOException("cannot replace $file")
                onCompact?.invoke()
            }
            else -> writeOffset(end)
        }
    }

    // Reading.

    private class Scan(val lines: List<ByteArray>, val count: Int, val end: Long)

    /** Up to [max] non-empty lines from byte [start], and the offset just past the
     *  last one. A final line without a newline (a crash mid-append) counts as a
     *  line. [keep] false only counts. */
    private fun scan(start: Long, max: Int, keep: Boolean): Scan {
        if (max <= 0 || !file.exists()) return Scan(emptyList(), 0, start)
        val lines = mutableListOf<ByteArray>()
        var count = 0
        var end = start
        RandomAccessFile(file, "r").use { raf ->
            raf.seek(start)
            val buf = ByteArray(CHUNK)
            val pending = java.io.ByteArrayOutputStream()
            var pendingLength = 0L
            var chunkStart = start
            while (count < max) {
                val n = raf.read(buf)
                if (n <= 0) {
                    if (pendingLength > 0) {
                        if (keep) lines += pending.toByteArray()
                        count += 1
                        end = chunkStart
                    }
                    break
                }
                var lineStart = 0
                var i = 0
                while (i < n && count < max) {
                    if (buf[i] == NEWLINE) {
                        if (pendingLength + (i - lineStart) > 0) {
                            if (keep) { pending.write(buf, lineStart, i - lineStart); lines += pending.toByteArray() }
                            count += 1
                        }
                        pending.reset()
                        pendingLength = 0
                        lineStart = i + 1
                        end = chunkStart + lineStart
                    }
                    i++
                }
                if (count < max) {
                    if (keep) pending.write(buf, lineStart, n - lineStart)
                    pendingLength += n - lineStart
                }
                chunkStart += n
            }
        }
        return Scan(lines, count, end)
    }

    private fun removeIfPresent(f: File) {
        if (f.exists() && !f.delete()) throw IOException("cannot delete $f")
    }

    private companion object {
        const val CHUNK = 64 * 1024
        const val NEWLINE = '\n'.code.toByte()
    }
}
