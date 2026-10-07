package com.breathefree.app.core

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

/**
 * Renders the sound for the promo videos (promo/README.md) with the app's own synth: a
 * six-cycle session from its start, and the closing chord of a short session.
 * Run with: ./gradlew testDebugUnitTest -Ppromo --tests '*PromoAudioTest*'
 */
class PromoAudioTest {
    @Test
    fun sound() {
        assumeTrue("pass -Ppromo to render the promo", System.getProperty("promo") == "true")
        val out = File("build/promo/audio").apply { mkdirs() }
        write(File(out, "session.wav"), render(SessionPlan(6), 0.0, 34.0))
        val short = SessionPlan(2)
        write(File(out, "closing.wav"), render(short, short.endTime - 0.05, short.endTime + 8.0))
        println("wrote ${out.absolutePath}")
    }

    /** Interleaved stereo from session time [from] to [to], rendered from the start as the app plays it. */
    private fun render(plan: SessionPlan, from: Double, to: Double): FloatArray {
        val synth = BreathSynth(RATE, plan)
        synth.mode = SoundMode.AMBIENT
        val total = (to * RATE).roundToInt()
        val keepFrom = (from * RATE).roundToInt()
        val kept = FloatArray((total - keepFrom) * 2)
        val buf = FloatArray(BLOCK * 2)
        var n = 0
        while (n < total) {
            val count = minOf(BLOCK, total - n)
            synth.render(buf, count, n.toDouble() / RATE)
            for (i in 0 until count) {
                val at = n + i - keepFrom
                if (at >= 0) {
                    kept[2 * at] = buf[2 * i]
                    kept[2 * at + 1] = buf[2 * i + 1]
                }
            }
            n += count
        }
        return kept
    }

    /** 16-bit stereo WAV. */
    private fun write(file: File, samples: FloatArray) {
        val bytes = samples.size * 2
        DataOutputStream(FileOutputStream(file).buffered()).use { o ->
            fun int(v: Int) = o.writeInt(Integer.reverseBytes(v))
            fun short(v: Int) = o.writeShort(java.lang.Short.reverseBytes(v.toShort()).toInt())
            o.writeBytes("RIFF"); int(36 + bytes); o.writeBytes("WAVE")
            o.writeBytes("fmt "); int(16); short(1); short(2); int(RATE); int(RATE * 4); short(4); short(16)
            o.writeBytes("data"); int(bytes)
            for (s in samples) short((s.coerceIn(-1f, 1f) * 32767f).roundToInt())
        }
    }

    private companion object {
        const val RATE = 48_000
        const val BLOCK = 480
    }
}
