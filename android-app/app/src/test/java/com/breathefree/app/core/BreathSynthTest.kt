package com.breathefree.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
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
        voice: Array<VoicePrompt?>? = null,
        configure: (BreathSynth) -> Unit = {},
    ): FloatArray {
        val synth = BreathSynth(rate, plan, voice = voice)
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
            // Each starts on the sample nearest its time, so on the same sample of every cycle.
            val late = actual - scheduled
            assertTrue("cue $i off by $late s", abs(late) <= 0.5 / rate + 1e-9)
        }
        for (i in 0 until plan.phaseCount) {
            assertEquals(i % 4, cues[i + 1].first)
            assertEquals(plan.phaseStart(i), cues[i + 1].second, 1e-9)
        }
    }

    @Test
    fun everyCycleSoundsTheSame() {
        // After the first, every cycle is the same sound, sample for sample: the same chord,
        // the same slow shimmer, the same air and bells. (The first has no bell tails from a
        // cycle before it.)
        val plan = SessionPlan(5)
        val cycle = (SessionPlan.CYCLE_SECONDS * rate).toInt() * 2
        val second = ((SessionPlan.SETTLE_SECONDS + SessionPlan.CYCLE_SECONDS) * rate).toInt() * 2
        val worst = listOf(0 to "pad", 1 to "air", 2 to "bells", -1 to "all").associate { (solo, layer) ->
            val out = render(plan, seconds = SessionPlan.SETTLE_SECONDS + 4 * SessionPlan.CYCLE_SECONDS, solo = solo)
            var d = 0.0
            for (i in 0 until cycle) d = max(d, abs(out[second + i].toDouble() - out[second + cycle + i]))
            println("$layer: largest difference between cycles 2 and 3 %.7f".format(d))
            layer to d
        }
        for ((layer, d) in worst) assertTrue("$layer: cycles 2 and 3 differ by up to $d", d < 1e-5)
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

    // ---- Voice. Stand-in prompts: a steady tone each, of a different length per phase, so
    // each phase's prompt can be told apart and timed to the sample.

    private fun tone(seconds: Double, lead: Double, level: Double = 0.2) =
        VoicePrompt(FloatArray((seconds * rate).toInt()) { (level * cos(2 * PI * 300.0 * it / rate)).toFloat() }, lead)

    private val hold = tone(0.25, 0.10)
    private val prompts = arrayOf<VoicePrompt?>(tone(0.40, 0.15), hold, tone(0.35, 0.05), hold)

    /** The runs of sound in [x] (left channel): (first sample, length), gaps under 5 ms joined. */
    private fun soundRuns(x: FloatArray): List<Pair<Int, Int>> {
        val runs = mutableListOf<Pair<Int, Int>>()
        var start = -1
        var last = -1
        for (i in 0 until x.size / 2) {
            if (x[2 * i] != 0f) {
                if (start < 0 || i - last > rate / 200) {
                    if (start >= 0) runs.add(start to last - start + 1)
                    start = i
                }
                last = i
            }
        }
        if (start >= 0) runs.add(start to last - start + 1)
        return runs
    }

    @Test
    fun eachPromptStartsItsLeadBeforeItsChange() {
        // Silent, so the voice is all there is: one run of sound per phase, starting on the
        // sample nearest (change - lead), as long as that phase's prompt.
        val plan = SessionPlan(2)
        val out = render(plan, mode = SoundMode.SILENT, block = 333, voice = prompts)
        val runs = soundRuns(out)
        assertEquals(plan.phaseCount, runs.size)
        for ((i, run) in runs.withIndex()) {
            val p = prompts[i % 4]!!
            val due = Math.round((plan.phaseStart(i) - p.lead) * rate).toInt()
            assertTrue("phase $i starts at ${run.first}, due at $due", abs(run.first - due) <= 1)
            assertEquals("phase $i plays its own prompt", p.samples.size, run.second)
        }
    }

    @Test
    fun aPromptIsNeverJoinedPartWay() {
        // Carrying on after a pause starts a new synth part way through the session. A prompt
        // already 0.1 s under way is let go; one only 20 ms under way still plays, from its start.
        val plan = SessionPlan(2)
        val due = plan.phaseStart(1) - hold.lead
        fun soundFrom(start: Double): List<Pair<Int, Int>> {
            val synth = BreathSynth(rate, plan, voice = prompts)
            synth.mode = SoundMode.SILENT
            val out = FloatArray(rate * 2 * 2)
            val buf = FloatArray(960)
            for (b in 0 until rate * 2 / 480) {
                synth.render(buf, 480, start + b * 480.0 / rate)
                System.arraycopy(buf, 0, out, b * 960, 960)
            }
            return soundRuns(out)
        }
        val late = soundFrom(due + 0.1)
        assertTrue("a prompt joined part way: $late", late.all { it.first > 0.5 * rate })
        // From its first sample to its last (the very first is silent: joining part way, the
        // sound fades in from nothing).
        val (start, length) = soundFrom(due + 0.02).first()
        assertTrue("starts at $start", start <= 1)
        assertEquals(hold.samples.size, start + length)
    }

    @Test
    fun underAVoiceTheRestPlaysFiveDecibelsQuieter() {
        // Before the first prompt (it is due at 7.85 s), compare the pad with and without.
        val plan = SessionPlan(2)
        val plain = render(plan, seconds = 7.6)
        val voiced = render(plan, seconds = 7.6, voice = prompts)
        val ratio = rms(voiced, 5.0, 7.5) / rms(plain, 5.0, 7.5)
        println("bed under a voice: %.2f dB".format(20 * kotlin.math.log10(ratio)))
        assertEquals(0.562, ratio, 0.003)
    }

    @Test
    fun theVolumeTurnsTheVoiceDownToo() {
        val plan = SessionPlan(2)
        val full = render(plan, mode = SoundMode.SILENT, seconds = 9.0, voice = prompts)
        val half = render(plan, mode = SoundMode.SILENT, seconds = 9.0, voice = prompts) { it.volume = 0.5 }
        // The slider is squared, as for everything else: half way is a quarter of the level.
        assertEquals(0.25, peak(half) / peak(full), 0.01)
    }

    @Test
    fun aSessionWithItsVoiceStaysInsideFullScale() {
        // Prompts as loud as the real ones (peaks near 0.5 at -20 LUFS), faded in and out as
        // they are, over the full pad: nothing past full scale, nothing broken.
        fun shaped(seconds: Double, lead: Double) = VoicePrompt(FloatArray((seconds * rate).toInt()) {
            val t = it.toDouble() / rate
            val env = minOf(1.0, t / 0.01, (seconds - t) / 0.04)
            (0.5 * env * sin(2 * PI * 140.0 * t) * (0.6 + 0.4 * sin(2 * PI * 7.0 * t))).toFloat()
        }, lead)
        val h = shaped(0.85, 0.167)
        val out = render(SessionPlan(2), voice = arrayOf(shaped(1.03, 0.164), h, shaped(0.91, 0.029), h))
        assertTrue(out.all { it.isFinite() })
        val p = peak(out)
        println("peak with the voice %.3f".format(p))
        assertTrue("peak $p", p < 1.0)
    }

    @Test
    fun blockSizeDoesNotChangeTheVoice() {
        val plan = SessionPlan(2)
        val a = render(plan, block = 256, seconds = 30.0, voice = prompts)
        val b = render(plan, block = 997, seconds = 30.0, voice = prompts)
        var worst = 0.0
        for (i in a.indices) worst = max(worst, abs(a[i].toDouble() - b[i]))
        assertTrue("largest difference $worst", worst < 1e-5)
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
