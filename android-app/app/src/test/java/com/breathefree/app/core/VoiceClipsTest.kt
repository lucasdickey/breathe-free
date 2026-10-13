package com.breathefree.app.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

class VoiceClipsTest {
    private fun sine(freq: Double, rate: Int, seconds: Double, level: Double = 0.5) =
        FloatArray((seconds * rate).toInt()) { (level * sin(2 * PI * freq * it / rate)).toFloat() }

    private fun rms(x: FloatArray, from: Int, to: Int): Double {
        var s = 0.0
        for (i in from until to) s += x[i].toDouble() * x[i]
        return sqrt(s / (to - from))
    }

    @Test
    fun aClipStartsAtItsFirstSound() {
        // A decoder's silence before and after (zeros, and noise far below the threshold) goes;
        // the sound itself stays, from its first sample at the threshold to its last.
        val sound = floatArrayOf(0.002f, 0.3f, -0.4f, 0.1f, -0.002f)
        val padded = FloatArray(100) { 0.0001f * (it % 3 - 1) } + sound + FloatArray(50)
        assertArrayEquals(sound, VoiceClips.trimToSound(padded), 0f)
        assertEquals(0, VoiceClips.trimToSound(FloatArray(10)).size)
    }

    @Test
    fun theSameRateIsLeftAlone() {
        val x = sine(300.0, 48_000, 0.1)
        assertSame(x, VoiceClips.resample(x, 48_000, 48_000))
    }

    @Test
    fun resamplingKeepsPitchLengthAndLevel() {
        // 48 kHz to 44.1 kHz: a 1 kHz tone stays 1 kHz and as loud, and the clip as long.
        val x = sine(1000.0, 48_000, 0.5)
        val y = VoiceClips.resample(x, 48_000, 44_100)
        assertEquals(x.size * 44_100.0 / 48_000, y.size.toDouble(), 1.0)
        var crossings = 0
        for (i in 1 until y.size) if ((y[i - 1] < 0) != (y[i] < 0)) crossings++
        assertEquals(1000.0, crossings / 2.0 / (y.size / 44_100.0), 5.0)
        val a = rms(x, 2000, x.size - 2000)
        val b = rms(y, 2000, y.size - 2000)
        assertEquals(1.0, b / a, 0.01)
    }

    @Test
    fun resamplingDownLeavesOutWhatTheNewRateCannotHold() {
        // 23 kHz fits at 48 kHz but not at 44.1 kHz (whose limit is 22.05 kHz): it must not fold
        // back as a lower, audible tone.
        val x = sine(23_000.0, 48_000, 0.5)
        val y = VoiceClips.resample(x, 48_000, 44_100)
        val left = rms(y, 2000, y.size - 2000) / rms(x, 2000, x.size - 2000)
        println("23 kHz left after resampling to 44.1 kHz: %.1f dB".format(20 * kotlin.math.log10(left)))
        assertTrue("left at $left", left < 0.03)
    }

    @Test
    fun promptsComeInPhaseOrderWithOneHold() {
        val clips = VoiceClips(48_000, sine(300.0, 48_000, 1.0), sine(300.0, 48_000, 0.8), sine(300.0, 48_000, 0.9))
        val p = clips.prompts(48_000)
        assertEquals(4, p.size)
        assertSame(clips.breatheIn, p[0]!!.samples)
        assertSame(clips.hold, p[1]!!.samples)
        assertSame(clips.breatheOut, p[2]!!.samples)
        assertSame(p[1], p[3])
        assertEquals(VoiceClips.LEAD_IN, p[0]!!.lead, 0.0)
        assertEquals(VoiceClips.LEAD_HOLD, p[1]!!.lead, 0.0)
        assertEquals(VoiceClips.LEAD_OUT, p[2]!!.lead, 0.0)
        // At another rate they are resampled once and kept.
        val q = clips.prompts(44_100)
        assertTrue(abs(clips.breatheIn.size * 44_100 / 48_000 - q[0]!!.samples.size) <= 1)
        assertSame(q, clips.prompts(44_100))
    }
}
