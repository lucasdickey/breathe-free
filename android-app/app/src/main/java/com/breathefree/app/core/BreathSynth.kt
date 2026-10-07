package com.breathefree.app.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan
import kotlin.math.tanh

enum class SoundMode(val label: String) {
    AMBIENT("Ambient"),
    BELLS("Bells only"),
    SILENT("Silent"),
}

/**
 * The session's sound, generated sample by sample from session time.
 *
 * Nothing here is a recording. Every layer is computed from the same breath curve the
 * picture uses, so a swell cannot land early or late and nothing is stretched to fit.
 *
 *  - Pad: a low D drone (D2, D3, A3) under F#4 and A4, the same chord every cycle, blooming
 *    as the lungs fill. It all sits below about 1 kHz, and no two voices beat faster than
 *    once every few seconds.
 *  - Air: soft filtered noise that moves only while air moves: rising and brightening on
 *    the inhale, falling and darkening on the exhale, silent during holds.
 *  - Bells: soft-mallet tones exactly on each phase change, one pitch per side of the box.
 *
 * Every cycle sounds the same, so the breath can settle into it: every pitch and every slow
 * beat between voices is a whole number of sixteenths of a hertz, so the pad comes round
 * exactly once a cycle, and the air's noise is worked out from where in the cycle it is
 * heard, so each breath's air is the same as the last.
 *
 * [render] runs only on the audio thread. [mode], [volume] and [fadeOut] may be used from
 * any thread; they are read once per control step.
 */
class BreathSynth(
    private val sampleRate: Int,
    private val plan: SessionPlan,
    seed: Int = 0x5EED,
) {
    @Volatile var mode: SoundMode = SoundMode.AMBIENT

    /** 0..1, as on a slider. */
    @Volatile var volume: Double = 1.0

    @Volatile private var fadeOutRequested = false

    /** True once the closing chord has died away, or a requested fade-out has finished. */
    @Volatile var finished: Boolean = false
        private set

    /** Fade to silence over a third of a second; [finished] turns true when done. */
    fun fadeOut() {
        fadeOutRequested = true
    }

    /**
     * Called on the audio thread as each cue's bells start, with the cue kind (0..3 the
     * phase, then welcome and closing), its scheduled time and the session time of the
     * sample it starts on. This is where spoken prompts will hook in.
     */
    internal var onCue: ((kind: Int, scheduled: Double, actual: Double) -> Unit)? = null

    /** For tests: hear one layer only (0 pad, 1 air, 2 bells), whatever the mode. */
    internal var solo: Int = -1

    private val dt = 1.0 / sampleRate

    // Session time of the next sample. It advances one sample per sample, at a rate
    // nudged by at most MAX_NUDGE to follow the time the platform says each block will be
    // heard, and jumps only after a real gap (a dropout, a new output device).
    private var clock = 0.0
    private var rate = 1.0
    private var anchored = false
    private var startFadeSeconds = START_FADE_FROM_ZERO

    // ---- Control-rate state. Targets are worked out every CONTROL samples and every
    // gain glides linearly to its target across the block, so nothing steps.
    private var controlLeft = 0
    private val noteGain = DoubleArray(NOTE_COUNT)
    private val noteGainStep = DoubleArray(NOTE_COUNT)
    private val harm = DoubleArray(NOTE_COUNT)
    private val harmStep = DoubleArray(NOTE_COUNT)
    private var airGain = 0.0
    private var airGainStep = 0.0
    private var bellGain = 0.0
    private var bellGainStep = 0.0
    private var master = 0.0
    private var masterStep = 0.0
    private var padMix = 0.0
    private var airMix = 0.0
    private var bellMix = 0.0
    private var volMix = -1.0
    private var fadeOutGain = 1.0
    private var startGain = 0.0
    private var airCutoff = 400.0

    private val mixCoef = 1.0 - exp(-CONTROL * dt / 0.25)
    private val volCoef = 1.0 - exp(-CONTROL * dt / 0.06)

    // ---- Pad oscillators: per note a centre voice plus a slightly flat copy on the left
    // and a slightly sharp copy on the right. Phases are 0..1 turns.
    private val phC = DoubleArray(NOTE_COUNT)
    private val phL = DoubleArray(NOTE_COUNT)
    private val phR = DoubleArray(NOTE_COUNT)
    private val incC = DoubleArray(NOTE_COUNT) { NOTES[it] * dt }
    private val incL = DoubleArray(NOTE_COUNT) { (NOTES[it] - DETUNE[it]) * dt }
    private val incR = DoubleArray(NOTE_COUNT) { (NOTES[it] + DETUNE[it]) * dt }

    // ---- Air: one independent noise channel per ear, so it feels wide rather than centred.
    private val airLeft = AirChannel(sampleRate)
    private val airRight = AirChannel(sampleRate)
    private val svf = Svf()
    private val cycleSamples = Math.round(SessionPlan.CYCLE_SECONDS * sampleRate)

    // ---- Bells: a small pool of voices, each four decaying partials.
    private val bellActive = BooleanArray(MAX_BELLS)
    private val bellDelay = IntArray(MAX_BELLS)
    private val bellAge = IntArray(MAX_BELLS)
    private val bellAmp = DoubleArray(MAX_BELLS)
    private val bellPhase = DoubleArray(MAX_BELLS * PARTIALS)
    private val bellInc = DoubleArray(MAX_BELLS * PARTIALS)
    private val bellEnv = DoubleArray(MAX_BELLS * PARTIALS)
    private val partialMult = DoubleArray(PARTIALS) { exp(-1.0 / (PARTIAL_DECAY[it] * sampleRate)) }
    private val attackSamples = (BELL_ATTACK * sampleRate).toInt()
    private val lifeSamples = (BELL_LIFE * sampleRate).toInt()
    private val releaseSamples = (BELL_RELEASE * sampleRate).toInt()

    // ---- Cues: the bell for every phase change, in time order.
    private val cueTimes: DoubleArray
    private val cueKinds: IntArray
    private var nextCue = 0
    private var nextCueTime: Double

    init {
        val count = plan.phaseCount + 2
        cueTimes = DoubleArray(count)
        cueKinds = IntArray(count)
        cueTimes[0] = WELCOME_AT
        cueKinds[0] = CUE_WELCOME
        for (i in 0 until plan.phaseCount) {
            cueTimes[i + 1] = plan.phaseStart(i)
            cueKinds[i + 1] = i % 4
        }
        cueTimes[count - 1] = plan.endTime
        cueKinds[count - 1] = CUE_CLOSING
        nextCueTime = cueTimes[0]

        // Start the oscillators at scattered phases so the first notes don't all line up.
        var s = seed or 1
        for (k in 0 until NOTE_COUNT) {
            s = xorshift(s); phC[k] = unit(s)
            s = xorshift(s); phL[k] = unit(s)
            s = xorshift(s); phR[k] = unit(s)
        }
    }

    /**
     * Fills [out] with [frames] interleaved stereo samples. [startTime] is the session
     * time at which the first of them will be heard.
     */
    fun render(out: FloatArray, frames: Int, startTime: Double) {
        follow(startTime)
        var i = 0
        while (i < frames) {
            if (controlLeft == 0) control()
            val n = min(controlLeft, frames - i)
            renderSamples(out, i, n)
            i += n
            controlLeft -= n
        }
    }

    private fun follow(target: Double) {
        if (!anchored) {
            anchored = true
            clock = target
            // Joining mid-session (sound switched on part way) fades in gently rather
            // than starting the pad at full level.
            startFadeSeconds = if (target > 1.0) START_FADE_MIDWAY else START_FADE_FROM_ZERO
            skipCuesBefore(target - STALE_CUE)
            return
        }
        val drift = target - clock
        if (abs(drift) > SNAP_SECONDS) {
            clock = target
            rate = 1.0
            skipCuesBefore(target - STALE_CUE)
        } else {
            rate = 1.0 + (drift / CATCH_UP_SECONDS).coerceIn(-MAX_NUDGE, MAX_NUDGE)
        }
    }

    private fun skipCuesBefore(t: Double) {
        while (nextCue < cueTimes.size && cueTimes[nextCue] < t) nextCue++
        nextCueTime = if (nextCue < cueTimes.size) cueTimes[nextCue] else Double.POSITIVE_INFINITY
    }

    private fun control() {
        controlLeft = CONTROL
        val step = CONTROL * dt * rate
        val t = clock + step // targets are for the end of this block

        // Where the breath is.
        val tb = t - SessionPlan.SETTLE_SECONDS
        var level = 0.0
        var air = 0.0
        if (tb >= 0.0 && tb < plan.breathingSeconds) {
            val index = min(plan.phaseCount - 1, floor(tb / SessionPlan.PHASE_SECONDS).toInt())
            val p = ((tb - index * SessionPlan.PHASE_SECONDS) / SessionPlan.PHASE_SECONDS).coerceIn(0.0, 1.0)
            when (index % 4) {
                0 -> {
                    level = BreathCurve.rise(p)
                    air = BreathCurve.flow(p) * AIR_INHALE
                    airCutoff = 300.0 + 1100.0 * BreathCurve.rise(p)
                }
                1 -> level = 1.0
                2 -> {
                    level = 1.0 - BreathCurve.rise(p)
                    air = BreathCurve.flow(p) * AIR_EXHALE
                    airCutoff = 1150.0 - 850.0 * BreathCurve.rise(p)
                }
                else -> level = 0.0
            }
        }

        // Which layers the listener wants.
        val m = mode
        val wantPad = if (solo >= 0) solo == 0 else m == SoundMode.AMBIENT
        val wantAir = if (solo >= 0) solo == 1 else m == SoundMode.AMBIENT
        val wantBells = if (solo >= 0) solo == 2 else m != SoundMode.SILENT
        padMix += ((if (wantPad) 1.0 else 0.0) - padMix) * mixCoef
        airMix += ((if (wantAir) 1.0 else 0.0) - airMix) * mixCoef
        bellMix += ((if (wantBells) 1.0 else 0.0) - bellMix) * mixCoef
        val v = volume.coerceIn(0.0, 1.0)
        val volTarget = v * v
        volMix = if (volMix < 0.0) volTarget else volMix + (volTarget - volMix) * volCoef

        // Pad.
        val padEnv = padEnvelope(t)
        val pedalBloom = 0.86 + 0.14 * level
        val upperBloom = 0.38 + 0.62 * level
        val padScale = padEnv * padMix
        for (k in 0 until NOTE_COUNT) {
            val target: Double
            val harmTarget: Double
            if (k < PEDAL_COUNT) {
                target = padScale * BASE_GAIN[k] * pedalBloom
                harmTarget = PEDAL_HARMONIC[k] * (0.6 + 0.4 * level)
            } else {
                target = padScale * BASE_GAIN[k] * upperBloom
                harmTarget = 0.05 + 0.15 * level
            }
            noteGainStep[k] = (target - noteGain[k]) / CONTROL
            harmStep[k] = (harmTarget - harm[k]) / CONTROL
        }

        // Air and bells.
        airGainStep = (air * AIR_LEVEL * airMix - airGain) / CONTROL
        svf.tune(airCutoff, AIR_Q, sampleRate)
        bellGainStep = (bellMix * BELL_LEVEL - bellGain) / CONTROL

        // Master: volume, the start fade and any requested fade-out.
        startGain = min(1.0, startGain + CONTROL * dt / startFadeSeconds)
        if (fadeOutRequested) {
            fadeOutGain = max(0.0, fadeOutGain - CONTROL * dt / FADE_OUT_SECONDS)
        }
        masterStep = (volMix * startGain * fadeOutGain - master) / CONTROL

        if ((fadeOutRequested && fadeOutGain == 0.0 && master < 1e-6) ||
            t > plan.endTime + SessionPlan.CLOSING_SECONDS
        ) {
            finished = true
        }
    }

    private fun padEnvelope(t: Double): Double {
        val outStart = plan.endTime + 1.0
        return when {
            t <= 0.0 -> 0.0
            t < PAD_FADE_IN -> raised(t / PAD_FADE_IN)
            t < outStart -> 1.0
            t < outStart + PAD_FADE_OUT -> 1.0 - raised((t - outStart) / PAD_FADE_OUT)
            else -> 0.0
        }
    }

    private fun renderSamples(out: FloatArray, offset: Int, count: Int) {
        val tick = dt * rate
        for (i in 0 until count) {
            while (clock + tick / 2 >= nextCueTime) {
                if (clock - nextCueTime <= STALE_CUE) {
                    startCue(cueKinds[nextCue])
                    onCue?.invoke(cueKinds[nextCue], nextCueTime, clock)
                }
                nextCue++
                nextCueTime = if (nextCue < cueTimes.size) cueTimes[nextCue] else Double.POSITIVE_INFINITY
            }

            // Pad.
            var padL = 0.0
            var padR = 0.0
            for (k in 0 until NOTE_COUNT) {
                val c = phC[k]
                var c2 = c + c
                if (c2 >= 1.0) c2 -= 1.0
                val body = sine(c) + harm[k] * sine(c2)
                val g = noteGain[k]
                padL += g * (body + SIDE * sine(phL[k]))
                padR += g * (body + SIDE * sine(phR[k]))
                phC[k] = wrap(c + incC[k])
                phL[k] = wrap(phL[k] + incL[k])
                phR[k] = wrap(phR[k] + incR[k])
                noteGain[k] += noteGainStep[k]
                harm[k] += harmStep[k]
            }

            // Air: the same noise at the same place in every cycle.
            val n = Math.round((clock - SessionPlan.SETTLE_SECONDS) * sampleRate) % cycleSamples
            val k = (if (n < 0) n + cycleSamples else n).toInt()
            val airL = svf.left(airLeft.next(noise(2 * k))) * airGain
            val airR = svf.right(airRight.next(noise(2 * k + 1))) * airGain
            airGain += airGainStep

            // Bells.
            var bell = 0.0
            for (b in 0 until MAX_BELLS) {
                if (!bellActive[b]) continue
                if (bellDelay[b] > 0) {
                    bellDelay[b]--
                    continue
                }
                var s = 0.0
                val base = b * PARTIALS
                for (p in 0 until PARTIALS) {
                    val j = base + p
                    s += sine(bellPhase[j]) * bellEnv[j]
                    bellPhase[j] = wrap(bellPhase[j] + bellInc[j])
                    bellEnv[j] *= partialMult[p]
                }
                val age = bellAge[b]
                val shape = when {
                    age < attackSamples -> 0.5 - 0.5 * cos(PI * age / attackSamples)
                    age > lifeSamples - releaseSamples -> (lifeSamples - age).toDouble() / releaseSamples
                    else -> 1.0
                }
                bell += s * bellAmp[b] * shape
                bellAge[b] = age + 1
                if (age + 1 >= lifeSamples) bellActive[b] = false
            }
            bell *= bellGain
            bellGain += bellGainStep

            val m = master
            master += masterStep
            val j = 2 * (offset + i)
            if (finished) {
                out[j] = 0f
                out[j + 1] = 0f
            } else {
                out[j] = soften((padL + airL + bell) * m * OUTPUT_GAIN).toFloat()
                out[j + 1] = soften((padR + airR + bell) * m * OUTPUT_GAIN).toFloat()
            }
            clock += tick
        }
    }

    private fun startCue(kind: Int) {
        val notes = CUE_NOTES[kind]
        var n = 0
        while (n < notes.size) {
            startBell(freq = notes[n], amp = notes[n + 1], delaySeconds = notes[n + 2])
            n += 3
        }
    }

    private fun startBell(freq: Double, amp: Double, delaySeconds: Double) {
        // A free voice, or else the oldest one (by then it is a faint tail).
        var slot = -1
        var oldest = -1
        for (b in 0 until MAX_BELLS) {
            if (!bellActive[b]) {
                slot = b
                break
            }
            if (oldest < 0 || bellAge[b] > bellAge[oldest]) oldest = b
        }
        if (slot < 0) slot = oldest
        bellActive[slot] = true
        bellDelay[slot] = (delaySeconds * sampleRate).toInt()
        bellAge[slot] = 0
        bellAmp[slot] = amp
        val base = slot * PARTIALS
        for (p in 0 until PARTIALS) {
            bellPhase[base + p] = 0.0
            bellInc[base + p] = freq * PARTIAL_RATIO[p] * dt
            bellEnv[base + p] = PARTIAL_AMP[p]
        }
    }

    /** White noise made pink-ish with the rumble taken out; filtered per ear by the shared [Svf] tuning. */
    private class AirChannel(sampleRate: Int) {
        private var b0 = 0.0
        private var b1 = 0.0
        private var b2 = 0.0
        private var hpX = 0.0
        private var hpY = 0.0
        private val hpA: Double

        init {
            val rc = 1.0 / (2.0 * PI * AIR_HIGHPASS)
            hpA = rc / (rc + 1.0 / sampleRate)
        }

        fun next(white: Double): Double {
            // Paul Kellet's economy pinking filter.
            b0 = 0.99765 * b0 + white * 0.0990460
            b1 = 0.96300 * b1 + white * 0.2965164
            b2 = 0.57000 * b2 + white * 1.0526913
            val pink = (b0 + b1 + b2 + white * 0.1848) * 0.11
            hpY = hpA * (hpY + pink - hpX)
            hpX = pink
            return hpY
        }
    }

    /** Two-pole low-pass (topology-preserving state-variable filter), one state per ear. */
    private class Svf {
        private var a1 = 0.0
        private var a2 = 0.0
        private var a3 = 0.0
        private var l1 = 0.0
        private var l2 = 0.0
        private var r1 = 0.0
        private var r2 = 0.0

        fun tune(cutoff: Double, q: Double, sampleRate: Int) {
            val g = tan(PI * cutoff.coerceIn(20.0, sampleRate * 0.45) / sampleRate)
            val k = 1.0 / q
            a1 = 1.0 / (1.0 + g * (g + k))
            a2 = g * a1
            a3 = g * a2
        }

        fun left(x: Double): Double {
            val v3 = x - l2
            val v1 = a1 * l1 + a2 * v3
            val v2 = l2 + a2 * l1 + a3 * v3
            l1 = 2.0 * v1 - l1
            l2 = 2.0 * v2 - l2
            return v2
        }

        fun right(x: Double): Double {
            val v3 = x - r2
            val v1 = a1 * r1 + a2 * v3
            val v2 = r2 + a2 * r1 + a3 * v3
            r1 = 2.0 * v1 - r1
            r2 = 2.0 * v2 - r2
            return v2
        }
    }

    companion object {
        private const val CONTROL = 32
        private const val OUTPUT_GAIN = 1.3

        // Following the device clock.
        private const val SNAP_SECONDS = 0.25
        private const val CATCH_UP_SECONDS = 2.0
        private const val MAX_NUDGE = 0.002
        private const val STALE_CUE = 0.12
        private const val START_FADE_FROM_ZERO = 0.03
        private const val START_FADE_MIDWAY = 0.8
        private const val FADE_OUT_SECONDS = 0.35

        // Pad. D2 D3 A3 hold the ground; F#4 A4 colour it. Each pitch is within 0.05 Hz of
        // equal temperament and a whole number of sixteenths of a hertz, as are the slight
        // detunings, so every beat between voices comes round exactly once a 16 s cycle.
        private val NOTES = doubleArrayOf(73.4375, 146.875, 220.0, 370.0, 440.0)
        private val NOTE_COUNT = NOTES.size
        private const val PEDAL_COUNT = 3
        private val BASE_GAIN = doubleArrayOf(0.12, 0.085, 0.06, 0.045, 0.045)
        private val DETUNE = doubleArrayOf(0.0625, 0.0625, 0.0625, 0.125, 0.125)
        private val PEDAL_HARMONIC = doubleArrayOf(0.0, 0.22, 0.16)
        private const val SIDE = 0.28
        private const val PAD_FADE_IN = 4.5
        private const val PAD_FADE_OUT = 6.5

        // Air.
        private const val AIR_LEVEL = 0.5
        private const val AIR_INHALE = 1.0
        private const val AIR_EXHALE = 0.9
        private const val AIR_Q = 0.6
        private const val AIR_HIGHPASS = 90.0

        // Bells: four partials, the top one slightly stretched for a bell rather than an organ.
        private const val BELL_LEVEL = 0.16
        private const val MAX_BELLS = 10
        private const val PARTIALS = 4
        private val PARTIAL_RATIO = doubleArrayOf(1.0, 2.0, 3.0, 4.16)
        private val PARTIAL_AMP = doubleArrayOf(1.0, 0.22, 0.06, 0.035)
        private val PARTIAL_DECAY = doubleArrayOf(2.4, 1.2, 0.6, 0.35)
        private const val BELL_ATTACK = 0.012
        private const val BELL_LIFE = 9.0
        private const val BELL_RELEASE = 1.0

        private const val WELCOME_AT = 0.3
        private const val CUE_WELCOME = 4
        private const val CUE_CLOSING = 5

        // Per cue: (frequency, amplitude, delay seconds) triples. Indexed by phase 0..3,
        // then welcome and closing.
        private val CUE_NOTES = arrayOf(
            doubleArrayOf(440.0, 1.0, 0.0), // inhale: A4
            doubleArrayOf(659.255, 0.32, 0.0), // hold full: E5, quiet
            doubleArrayOf(293.665, 0.9, 0.0), // exhale: D4
            doubleArrayOf(220.0, 0.38, 0.0), // hold empty: A3, quiet
            doubleArrayOf(293.665, 0.55, 0.0, 440.0, 0.35, 0.16), // welcome
            doubleArrayOf(146.832, 0.5, 0.0, 293.665, 0.8, 0.0, 440.0, 0.6, 0.2, 739.989, 0.4, 0.4), // closing
        )

        private const val TABLE_SIZE = 4096
        private val SINE = DoubleArray(TABLE_SIZE + 1) { sin(2.0 * PI * it / TABLE_SIZE) }

        /** Sine of a phase in turns (0..1), from a table with linear interpolation. */
        private fun sine(phase: Double): Double {
            val x = phase * TABLE_SIZE
            val i = x.toInt()
            val f = x - i
            val a = SINE[i]
            return a + (SINE[i + 1] - a) * f
        }

        private fun wrap(x: Double): Double = if (x >= 1.0) x - 1.0 else x

        private fun raised(x: Double): Double = 0.5 - 0.5 * cos(PI * x.coerceIn(0.0, 1.0))

        /** Gentle limiter: untouched below 0.6, rounds off smoothly towards 1.0 above it. */
        private fun soften(x: Double): Double {
            val a = abs(x)
            if (a <= 0.6) return x
            val y = 0.6 + 0.4 * tanh((a - 0.6) / 0.4)
            return if (x < 0) -y else y
        }

        private fun xorshift(x0: Int): Int {
            var x = x0
            x = x xor (x shl 13)
            x = x xor (x ushr 17)
            x = x xor (x shl 5)
            return x
        }

        private fun unit(x: Int): Double = (x ushr 8) / 16777216.0

        /** White noise in -1..1, the same for the same [k] (a 32-bit integer hash). */
        private fun noise(k: Int): Double {
            var x = k
            x = x xor (x ushr 16)
            x *= 0x7feb352d
            x = x xor (x ushr 15)
            x *= 0x846ca68b.toInt()
            x = x xor (x ushr 16)
            return x / 2147483648.0
        }
    }
}
