package com.breathefree.app.core

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin

/**
 * The spoken prompts as decoded: mono samples at [rate], each from its first sound to its
 * last (see [trimToSound]). The recordings and how they were made are in voice/README.md.
 */
class VoiceClips(val rate: Int, val breatheIn: FloatArray, val hold: FloatArray, val breatheOut: FloatArray) {
    // Made on the decoding thread and read on the main one: volatile, so the main thread
    // sees it whole.
    @Volatile private var cached: Pair<Int, Array<VoicePrompt?>>? = null

    /** The prompts for a synth at [sampleRate], in phase order: in, hold full, out, hold empty. */
    fun prompts(sampleRate: Int): Array<VoicePrompt?> {
        cached?.let { (r, p) -> if (r == sampleRate) return p }
        val hold = VoicePrompt(resample(hold, rate, sampleRate), LEAD_HOLD)
        val prompts = arrayOf<VoicePrompt?>(
            VoicePrompt(resample(breatheIn, rate, sampleRate), LEAD_IN),
            hold,
            VoicePrompt(resample(breatheOut, rate, sampleRate), LEAD_OUT),
            hold,
        )
        cached = sampleRate to prompts
        return prompts
    }

    companion object {
        // How long after each recording's first sound its main vowel comes, in seconds.
        const val LEAD_IN = 0.164
        const val LEAD_HOLD = 0.167
        const val LEAD_OUT = 0.029

        /**
         * A sample at least this loud (-54 dBFS) is a clip's first or last sound. Anything
         * outside it is silence a decoder added, which would put the prompt late.
         */
        const val ONSET = 0.002f

        /** [samples] from the first sound to the last. */
        fun trimToSound(samples: FloatArray): FloatArray {
            val first = samples.indexOfFirst { kotlin.math.abs(it) >= ONSET }
            if (first < 0) return FloatArray(0)
            val last = samples.indexOfLast { kotlin.math.abs(it) >= ONSET }
            return samples.copyOfRange(first, last + 1)
        }

        /**
         * [x] at [from] Hz, resampled to [to] Hz: a windowed sinc 16 zero crossings wide,
         * its band edge at 0.9 of the new Nyquist when going down (the prompts hold
         * nothing above about 16 kHz anyway). Only used on a device that doesn't
         * run at the recordings' 48 kHz.
         */
        fun resample(x: FloatArray, from: Int, to: Int): FloatArray {
            if (from == to || x.isEmpty()) return x
            val step = from.toDouble() / to // source samples per output sample
            val cut = min(1.0, to.toDouble() / from) * 0.90
            val half = HALF_WIDTH / cut // kernel half-width, in source samples
            val n = floor(x.size / step).toInt()
            return FloatArray(n) { j ->
                val t = j * step
                var sum = 0.0
                var norm = 0.0
                for (k in ceil(t - half).toInt()..floor(t + half).toInt()) {
                    val d = t - k
                    val w = cut * sinc(cut * d) * (0.5 + 0.5 * cos(PI * d / half))
                    norm += w
                    if (k >= 0 && k < x.size) sum += x[k] * w
                }
                (sum / norm).toFloat()
            }
        }

        private const val HALF_WIDTH = 16.0

        private fun sinc(v: Double): Double = if (v == 0.0) 1.0 else sin(PI * v) / (PI * v)
    }
}
