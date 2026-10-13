package com.breathefree.app.core

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

/**
 * The real prompts through the app's own synth: the six-cycle session PromoAudioTest renders,
 * with the voice on, to listen to and to compare with the session without it.
 * Run with: ./gradlew testDebugUnitTest -PvoicePreview=<dir> --tests '*VoicePreviewTest*'
 * where <dir> holds breathe-in.f32, hold.f32 and breathe-out.f32: the prompts decoded to
 * 48 kHz mono 32-bit float, as the phone's decoder gives them (voice/README.md).
 */
class VoicePreviewTest {
    @Test
    fun sessionWithTheVoice() {
        val dir = System.getProperty("voicePreview").orEmpty()
        assumeTrue("pass -PvoicePreview=<dir> to render", dir.isNotEmpty())
        fun read(name: String): FloatArray {
            val bytes = File(dir, name).readBytes()
            val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            return FloatArray(b.remaining()).also { b.get(it) }
        }
        val clips = VoiceClips(
            RATE,
            VoiceClips.trimToSound(read("breathe-in.f32")),
            VoiceClips.trimToSound(read("hold.f32")),
            VoiceClips.trimToSound(read("breathe-out.f32")),
        )
        val synth = BreathSynth(RATE, SessionPlan(6), voice = clips.prompts(RATE))
        synth.mode = SoundMode.AMBIENT
        val total = (34.0 * RATE).roundToInt()
        val out = FloatArray(total * 2)
        val buf = FloatArray(BLOCK * 2)
        var n = 0
        while (n < total) {
            val count = minOf(BLOCK, total - n)
            synth.render(buf, count, n.toDouble() / RATE)
            System.arraycopy(buf, 0, out, n * 2, count * 2)
            n += count
        }
        val file = File("build/promo/audio/session-voice.wav").apply { parentFile?.mkdirs() }
        DataOutputStream(FileOutputStream(file).buffered()).use { o ->
            fun int(v: Int) = o.writeInt(Integer.reverseBytes(v))
            fun short(v: Int) = o.writeShort(java.lang.Short.reverseBytes(v.toShort()).toInt())
            val bytes = out.size * 2
            o.writeBytes("RIFF"); int(36 + bytes); o.writeBytes("WAVE")
            o.writeBytes("fmt "); int(16); short(1); short(2); int(RATE); int(RATE * 4); short(4); short(16)
            o.writeBytes("data"); int(bytes)
            for (s in out) short((s.coerceIn(-1f, 1f) * 32767f).roundToInt())
        }
        println("wrote ${file.absolutePath}; peak %.3f".format(out.maxOf { kotlin.math.abs(it) }))
    }

    private companion object {
        const val RATE = 48_000
        const val BLOCK = 480
    }
}
