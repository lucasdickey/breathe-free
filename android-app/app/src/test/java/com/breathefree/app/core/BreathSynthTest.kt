package com.breathefree.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.sqrt

class BreathSynthTest {
    private val rate = 48_000

    /** Renders a whole session with exact timing, in blocks of [block] frames. */
    private fun render(
        plan: SessionPlan,
        mode: SoundMode = SoundMode.AMBIENT,
        block: Int = 480,
        seconds: Double = plan.endTime + SessionPlan.CLOSING_SECONDS + 0.5,
        solo: Int = -1,
        configure: (BreathSynth) -> Unit = {},
    ): FloatArray {
        val synth = BreathSynth(rate, plan)
        synth.mode = mode
        synth.volume = 1.0
        synth.solo = solo
        configure(synth)
        val frames = (seconds * rate).toInt()
        val out = FloatArray(frames * 2)
        val buf = FloatArray(block * 2)
        var n = 0
        while (n < frames) {
            val count = minOf(block, frames - n)
            synth.render(buf, count, n.toDouble() / rate)
            System.arraycopy(buf, 0, out, n * 2, count * 2)
            n += count
        }
        return out
    }

    private fun rms(x: FloatArray, from: Double, to: Double): Double {
        val a = (from * rate).toInt() * 2
        val b = (to * rate).toInt() * 2
        var sum = 0.0
        for (i in a until b) sum += x[i].toDouble() * x[i]
        return sqrt(sum / (b - a))
    }

    private fun peak(x: FloatArray): Double = x.maxOf { abs(it.toDouble()) }

    @Test
    fun staysCleanAndInsideFullScale() {
        val out = render(SessionPlan(2))
        assertTrue(out.all { it.isFinite() })
        val p = peak(out)
        println("peak ${"%.3f".format(p)}")
        assertTrue("peak $p", p < 0.7)
    }

    @Test
    fun blockSizeDoesNotChangeTheSound() {
        val plan = SessionPlan(2)
        val a = render(plan, block = 256, seconds = 30.0)
        val b = render(plan, block = 997, seconds = 30.0)
        var worst = 0.0
        for (i in a.indices) worst = max(worst, abs(a[i].toDouble() - b[i]))
        assertTrue("largest difference $worst", worst < 1e-5)
    }

    @Test
    fun bellsLandOnThePhaseBoundaries() {
        val plan = SessionPlan(3)
        val cues = mutableListOf<Triple<Int, Double, Double>>()
        render(plan, mode = SoundMode.BELLS, block = 333) { s ->
            s.onCue = { kind, scheduled, actual -> cues.add(Triple(kind, scheduled, actual)) }
        }
        // welcome, every phase, closing
        assertEquals(plan.phaseCount + 2, cues.size)
        for ((i, cue) in cues.withIndex()) {
            val (_, scheduled, actual) = cue
            val late = actual - scheduled
            assertTrue("cue $i late by $late s", late >= 0.0 && late < 1.0 / rate + 1e-9)
        }
        for (i in 0 until plan.phaseCount) {
            assertEquals(i % 4, cues[i + 1].first)
            assertEquals(plan.phaseStart(i), cues[i + 1].second, 1e-9)
        }
    }

    @Test
    fun airMovesOnlyWhileBreathMoves() {
        val plan = SessionPlan(2)
        val air = render(plan, solo = 1)
        val inhale = rms(air, 9.0, 11.0)
        val holdFull = rms(air, 12.5, 15.5)
        val exhale = rms(air, 17.0, 19.0)
        val holdEmpty = rms(air, 20.5, 23.5)
        println("air rms inhale %.4f exhale %.4f holds %.6f %.6f".format(inhale, exhale, holdFull, holdEmpty))
        assertTrue(holdFull < inhale * 0.01)
        assertTrue(holdEmpty < exhale * 0.01)
    }

    @Test
    fun noClicks() {
        // A click is a sudden kink in the waveform. Measure the largest second difference
        // anywhere in a full session: the smooth layers reach about 0.004 at full volume
        // (the air at its brightest), while a click loud enough to hear is 0.01 or more.
        val out = render(SessionPlan(2))
        var worst = 0.0
        var at = 0
        for (c in 0 until 2) {
            for (i in 2 until out.size / 2) {
                val d = abs(out[2 * i + c] - 2.0 * out[2 * (i - 1) + c] + out[2 * (i - 2) + c])
                if (d > worst) {
                    worst = d
                    at = i
                }
            }
        }
        println("largest second difference %.5f at %.3f s".format(worst, at.toDouble() / rate))
        assertTrue("kink of $worst at ${at.toDouble() / rate}s", worst < 0.008)
    }

    @Test
    fun fadeOutFinishesQuietly() {
        val plan = SessionPlan(2)
        val synth = BreathSynth(rate, plan)
        synth.volume = 1.0
        val buf = FloatArray(960)
        var n = 0
        while (n < rate * 12) {
            synth.render(buf, 480, n.toDouble() / rate)
            n += 480
        }
        synth.fadeOut()
        var blocks = 0
        while (!synth.finished && blocks < 1000) {
            synth.render(buf, 480, n.toDouble() / rate)
            n += 480
            blocks++
        }
        assertTrue(synth.finished)
        assertTrue("took $blocks blocks", blocks < 60)
        synth.render(buf, 480, n.toDouble() / rate)
        assertTrue(buf.all { it == 0f })
    }

    @Test
    fun followsAClockThatRunsSlightlyFast() {
        // The device clock gains 100 ppm on the session clock: sound must stay with it.
        val plan = SessionPlan(2)
        val cues = mutableListOf<Pair<Double, Double>>()
        val synth = BreathSynth(rate, plan)
        synth.onCue = { _, scheduled, actual -> cues.add(scheduled to actual) }
        val buf = FloatArray(960)
        var n = 0L
        while (n < rate * 45L) {
            val heardAt = n.toDouble() / rate * (1.0 + 100e-6)
            synth.render(buf, 480, heardAt)
            n += 480
        }
        for ((scheduled, actual) in cues) {
            assertTrue("cue at $scheduled heard at $actual", abs(actual - scheduled) < 0.002)
        }
    }

    @Test
    fun joiningMidSessionFadesIn() {
        val plan = SessionPlan(4)
        val synth = BreathSynth(rate, plan)
        synth.volume = 1.0
        val buf = FloatArray(960)
        synth.render(buf, 480, 37.25)
        val first = buf.maxOf { abs(it) }
        assertTrue("first block peak $first", first < 0.01)
    }

    @Test
    fun levels() {
        val plan = SessionPlan(2)
        val pad = render(plan, solo = 0)
        val air = render(plan, solo = 1)
        val bells = render(plan, mode = SoundMode.BELLS)
        val all = render(plan)
        println("pad rms: hold-empty %.4f hold-full %.4f | air peak-flow rms %.4f | bell peak %.3f | mix peak %.3f rms %.4f".format(
            rms(pad, 20.5, 23.5), rms(pad, 12.5, 15.5), rms(air, 9.2, 10.2), peak(bells), peak(all), rms(all, 8.0, 40.0)))
        writeWav(File("build/preview/breathe-preview.wav"), all)
        writeWav(File("build/preview/breathe-bells.wav"), bells)
    }

    @Test
    fun renderIsFastEnough() {
        val plan = SessionPlan(10)
        val synth = BreathSynth(rate, plan)
        val buf = FloatArray(960)
        val frames = rate * 60
        val start = System.nanoTime()
        var n = 0
        while (n < frames) {
            synth.render(buf, 480, n.toDouble() / rate)
            n += 480
        }
        val ms = (System.nanoTime() - start) / 1e6
        println("60 s of audio rendered in %.0f ms".format(ms))
        assertTrue(ms < 6000)
    }

    private fun writeWav(file: File, stereo: FloatArray) {
        file.parentFile?.mkdirs()
        val data = ByteBuffer.allocate(stereo.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in stereo) data.putShort((s.coerceIn(-1f, 1f) * 32767f).toInt().toShort())
        RandomAccessFile(file, "rw").use { f ->
            f.setLength(0)
            val h = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            h.put("RIFF".toByteArray()).putInt(36 + data.capacity()).put("WAVE".toByteArray())
            h.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(2).putInt(rate)
                .putInt(rate * 4).putShort(4).putShort(16)
            h.put("data".toByteArray()).putInt(data.capacity())
            f.write(h.array())
            f.write(data.array())
        }
    }
}
