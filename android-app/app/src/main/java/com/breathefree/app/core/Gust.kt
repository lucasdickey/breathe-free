package com.breathefree.app.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * Which words the wind is carrying at one instant: the one blowing in (or settled) and the one
 * blowing away, each with the seconds since its gust began. Either may be "".
 */
data class GustWords(val arriving: String, val arriveSince: Double, val leaving: String, val leaveSince: Double)

/**
 * The words as specks of ink on the wind. Each word is blown in from the left, its left end
 * landing first, and settles under the box; the gust that brings the next word carries it off to
 * the right. The specks stay in a band round the words, so the wind passes under the box and orb
 * rather than across them; a few rise into place out of the clear sky below the words and sink
 * back into it as they go. Everything is a function of session time, like the rest of the
 * screen, so a paused session holds the specks where they are.
 */
object Gust {
    /** A word starts blowing in this long before its phase, so it can be read just after the phase begins... */
    const val ARRIVE_LEAD = 0.5

    /** ...and starts blowing away this long before the next, a moment ahead of the next word. */
    const val LEAVE_LEAD = 0.8

    /** How long one speck takes to come in from the left, and to go off to the right. */
    const val ARRIVE_SECONDS = 0.9
    const val LEAVE_SECONDS = 1.0

    /**
     * How much later the right end of a word sets off than the left, and each speck's own lag on
     * top: more of it leaving, so the wind takes a word apart rather than sliding it off whole.
     */
    const val ARRIVE_STAGGER = 0.25
    const val ARRIVE_SCATTER = 0.15
    const val LEAVE_STAGGER = 0.25
    const val LEAVE_SCATTER = 0.3

    /** Seconds from a word's gust to its last speck landing, and to its last speck gone. */
    const val ARRIVED = ARRIVE_STAGGER + ARRIVE_SCATTER + ARRIVE_SECONDS
    const val GONE = LEAVE_STAGGER + LEAVE_SCATTER + LEAVE_SECONDS

    /**
     * Each speck's own pace: up to this much quicker than the slowest, so specks overtake one
     * another rather than keeping step.
     */
    const val PACE = 0.12

    /**
     * How far a speck strays from its line while it is in the air, on slow gusts of its own: a
     * share of the screen's width along the wind, and dp across it, little enough to keep under the box.
     */
    const val WANDER = 0.02f
    const val WANDER_ACROSS = 5f

    /**
     * The share of specks that take the low road: up out of the clear sky from the lower left,
     * and down into it to the lower right, each to its own depth.
     */
    const val LOW = 0.25f

    /** How far a settled word swells with full lungs. */
    const val SWELL = 0.03

    /**
     * Where one speck is, written into [out] as x and y from the word's centre (pixels, y down)
     * and how much of it shows, 0..1.
     *
     * [tx], [ty] is where it belongs in the word, [along] how far across the word that is (0 the
     * left end, 1 the right), and [seed] picks its own path. [arriveSince] is the seconds since its
     * word started blowing in, [leaveSince] since it started blowing away (negative until then).
     * [reach] is how far the wind carries it, the screen's width, and [room] how far below the
     * words the sky is clear; [unit] is one dp in pixels; [level] is how full the lungs are, and
     * [t] session time, for the settled specks' shimmer.
     */
    fun place(
        tx: Float, ty: Float, along: Float, seed: Int,
        arriveSince: Double, leaveSince: Double,
        reach: Float, room: Float, unit: Float, level: Double, t: Double,
        out: FloatArray,
    ) {
        val swell = 1f + (SWELL * level).toFloat()
        var x = tx * swell
        var y = ty * swell

        // In from the left, out of a band a little above the words to a little below them,
        // swirling as it comes and steadying as it lands.
        val inDelay = along * ARRIVE_STAGGER + luck(seed, 0) * ARRIVE_SCATTER
        val q = ((arriveSince - inDelay) / (ARRIVE_SECONDS * (1 - PACE * luck(seed, 13)))).coerceIn(0.0, 1.0)
        val e = easeOut(q).toFloat()
        val left = 1f - e
        val swirl = left * 6f * unit
        x -= left * reach * (0.55f + 0.35f * luck(seed, 1))
        y += left * unit * (-10f + 50f * luck(seed, 2))
        y += sin(PI * e).toFloat() * (luck(seed, 3) - 0.5f) * 24f * unit
        x += sin(t * 3.0 + luck(seed, 4) * TAU).toFloat() * swirl
        y += cos(t * 2.3 + luck(seed, 5) * TAU).toFloat() * swirl
        // Taking the low road, it comes up from below as it closes in, rising into place.
        val low = maxOf(0f, (luck(seed, 19) - (1 - LOW)) / LOW) * room
        y += low * ((1 - q) * (1 - q)).toFloat()
        var alpha = smoothstep(0.0, 0.35, q)
        // Off its line until it is nearly down, so the specks don't come in on rails.
        var stray = 1f - smoothstep(0.3, 1.0, q).toFloat()

        // Settled, it stirs a little, as snow does in a breeze.
        x += sin(t * 1.7 + luck(seed, 6) * 9.0).toFloat() * 0.25f * unit
        y += cos(t * 1.3 + luck(seed, 7) * 9.0).toFloat() * 0.25f * unit

        // Off to the right, the left end of the word first, gathering speed and swirling as it goes.
        if (leaveSince > 0) {
            val outDelay = along * LEAVE_STAGGER + luck(seed, 8) * LEAVE_SCATTER
            val p = ((leaveSince - outDelay) / (LEAVE_SECONDS * (1 - PACE * luck(seed, 14)))).coerceIn(0.0, 1.0)
            // Moving off at once and swirling only as it picks up speed, so no letter shivers in place first.
            val g = (p * p).toFloat()
            val gusting = minOf(1f, 3f * g) * 6f * unit
            x += g * reach * (0.5f + 0.4f * luck(seed, 1)) + sin(t * 3.0 + luck(seed, 4) * TAU).toFloat() * gusting
            y += g * unit * (-10f + 36f * luck(seed, 9)) + cos(t * 2.3 + luck(seed, 5) * TAU).toFloat() * gusting
            // On the low road it sinks as it goes, down and away to the lower right.
            y += low * p.pow(1.5).toFloat()
            alpha *= 1.0 - smoothstep(0.35, 1.0, p)
            stray += smoothstep(0.0, 0.6, p).toFloat()
        }

        if (stray > 0f) {
            x += stray * WANDER * reach * sin(t * (1.5 + 2.0 * luck(seed, 15)) + luck(seed, 16) * TAU).toFloat()
            y += stray * WANDER_ACROSS * unit * sin(t * (1.5 + 2.0 * luck(seed, 17)) + luck(seed, 18) * TAU).toFloat()
        }

        out[0] = x
        out[1] = y
        out[2] = alpha.toFloat()
    }

    /** A speck's own number [k], 0..1: the same every time for the same speck. */
    fun luck(seed: Int, k: Int): Float {
        var h = seed * -0x61c88647 + k * -0x7a143589
        h = (h xor (h ushr 16)) * -0x7a143595
        h = (h xor (h ushr 13)) * -0x3d4d51cb
        h = h xor (h ushr 16)
        return (h ushr 8) / 16_777_216f
    }

    private const val TAU = 2 * PI

    private fun easeOut(x: Double) = 1 - (1 - x).pow(3)

    private fun smoothstep(a: Double, b: Double, v: Double): Double {
        val x = ((v - a) / (b - a)).coerceIn(0.0, 1.0)
        return x * x * (3 - 2 * x)
    }
}

/**
 * The words on the wind at session time [t]: each word blows in [Gust.ARRIVE_LEAD] before its
 * own words come up and away [Gust.LEAVE_LEAD] before the next ones do, so for a moment before
 * each change only the leaving word is in the air.
 */
fun SessionPlan.gustAt(t: Double): GustWords {
    val coming = promptAt(t + Gust.ARRIVE_LEAD)
    val going = promptAt(t + Gust.LEAVE_LEAD)
    // Between the two leads, the words coming up have begun to leave and the next are not on their way yet.
    val between = coming.since > going.since
    return GustWords(
        arriving = if (between) "" else coming.text,
        arriveSince = if (between) 0.0 else coming.since,
        leaving = going.previous,
        leaveSince = going.since,
    )
}
