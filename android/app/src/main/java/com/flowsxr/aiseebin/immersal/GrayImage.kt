package com.flowsxr.aiseebin.immersal

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.zip.CRC32
import java.util.zip.Deflater

/**
 * An 8-bit grayscale image, one byte per pixel, rows packed with no padding.
 * The glasses' Y (luma) plane is exactly this, which is what Immersal wants.
 */
class GrayImage(val width: Int, val height: Int, val pixels: ByteArray) {
    init {
        require(width > 0 && height > 0 && pixels.size >= width * height) { "bad gray image ${width}x$height" }
    }

    /**
     * Area-averaged resize to [targetWidth] pixels wide, aspect kept. Never
     * upscales. 1280 → 960 halves the PNG, which is most of a fix's latency
     * over a phone connection (same choice as iOS `GlassesPositioning`).
     */
    fun scaledToWidth(targetWidth: Int): GrayImage {
        if (targetWidth >= width) return this
        val w = targetWidth.coerceAtLeast(1)
        val h = (height.toLong() * w / width).toInt().coerceAtLeast(1)
        val out = ByteArray(w * h)
        val sx = width.toDouble() / w
        val sy = height.toDouble() / h
        for (y in 0 until h) {
            val y0 = (y * sy).toInt()
            val y1 = ((y + 1) * sy).toInt().coerceIn(y0 + 1, height)
            for (x in 0 until w) {
                val x0 = (x * sx).toInt()
                val x1 = ((x + 1) * sx).toInt().coerceIn(x0 + 1, width)
                var sum = 0
                for (yy in y0 until y1) {
                    val row = yy * width
                    for (xx in x0 until x1) sum += pixels[row + xx].toInt() and 0xFF
                }
                out[y * w + x] = (sum / ((y1 - y0) * (x1 - x0))).toByte()
            }
        }
        return GrayImage(w, h, out)
    }

    /** Minimal PNG writer: 8-bit grayscale, filter 0 on every row, zlib-deflated. */
    fun toPng(): ByteArray {
        val raw = ByteArray((width + 1) * height)
        for (y in 0 until height) {
            raw[y * (width + 1)] = 0 // filter type: none
            System.arraycopy(pixels, y * width, raw, y * (width + 1) + 1, width)
        }
        val deflater = Deflater(Deflater.BEST_SPEED)
        deflater.setInput(raw)
        deflater.finish()
        val compressed = ByteArrayOutputStream(raw.size / 2)
        val buffer = ByteArray(64 * 1024)
        while (!deflater.finished()) {
            val n = deflater.deflate(buffer)
            compressed.write(buffer, 0, n)
        }
        deflater.end()

        val png = ByteArrayOutputStream(compressed.size() + 64)
        val out = DataOutputStream(png)
        out.write(byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 13, 10, 26, 10))
        val ihdr = ByteArrayOutputStream()
        DataOutputStream(ihdr).apply {
            writeInt(width); writeInt(height)
            writeByte(8)  // bit depth
            writeByte(0)  // colour type: grayscale
            writeByte(0); writeByte(0); writeByte(0) // compression, filter, interlace
        }
        writeChunk(out, "IHDR", ihdr.toByteArray())
        writeChunk(out, "IDAT", compressed.toByteArray())
        writeChunk(out, "IEND", ByteArray(0))
        return png.toByteArray()
    }

    private fun writeChunk(out: DataOutputStream, type: String, data: ByteArray) {
        val typeBytes = type.toByteArray(Charsets.US_ASCII)
        out.writeInt(data.size)
        out.write(typeBytes)
        out.write(data)
        val crc = CRC32()
        crc.update(typeBytes)
        crc.update(data)
        out.writeInt(crc.value.toInt())
    }
}
