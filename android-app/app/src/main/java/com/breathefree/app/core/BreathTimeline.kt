package com.breathefree.app.core

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** The four sides of the box, in the order they are breathed. */
enum class Phase(val prompt: String) {
    INHALE("Breathe in"),
    HOLD_FULL("Hold"),
    EXHALE("Breathe out"),
    HOLD_EMPTY("Hold"),
}

enum class Stage { SETTLE, BREATHING, COMPLETE }

/** Everything the screen shows at one instant of a session. */
data class BreathFrame(
    val stage: Stage,
    /** Null while settling and once complete. */
    val phase: Phase?,
    /** Phases begun since breathing started: -1 while settling, phaseCount once complete. */
    val phaseIndex: Int,
    /** Seconds into the current phase (or into the settle, or since completion). */
    val phaseElapsed: Double,
    /** 0..1 through the current phase, or through the settle. */
    val progress: Double,
    /** How full the lungs are: 0 empty, 1 full. Drives the orb, the dot and the sound. */
    val level: Double,
    /** 0-based cycle number. */
    val cycle: Int,
    /** Whole seconds left in the phase: 4..1 (8..1 while settling). */
    val countdown: Int,
    /** Breathing seconds left, not counting the settle. */
    val remaining: Double,
) {
    /**
     * Where the dot sits on the box: which side (0 left going up, 1 top going right,
     * 2 right going down, 3 bottom going left) and how far along it, 0..1.
     * On the two moving sides the dot rises and falls with the breath itself, so its
     * height always matches the orb.
     */
    fun boxSide(): Int = if (stage == Stage.BREATHING) phaseIndex % 4 else 0

    fun boxFraction(): Double = when (phase) {
        Phase.INHALE, Phase.EXHALE -> BreathCurve.rise(progress)
        Phase.HOLD_FULL, Phase.HOLD_EMPTY -> progress
        null -> 0.0
    }
}

/** The shape of one breath. */
object BreathCurve {
    // Below 1 the motion gets going a little sooner after the cue than a plain sine
    // would, while still starting and ending at rest.
    private const val SKEW = 0.8

    /** Lung level across an inhale, 0 → 1. An exhale is 1 - rise(p). */
    fun rise(p: Double): Double {
        val q = p.coerceIn(0.0, 1.0).pow(SKEW)
        return 0.5 - 0.5 * cos(PI * q)
    }

    /** How much air is moving across an inhale or exhale: 0 at both ends, peak just before the middle. */
    fun flow(p: Double): Double {
        val q = p.coerceIn(0.0, 1.0).pow(SKEW)
        return sin(PI * q)
    }
}

/**
 * A session laid out on one time axis, starting at 0 when Begin is pressed:
 * an 8 second settle, then [cycles] rounds of in-4, hold-4, out-4, hold-4.
 *
 * Both the picture and the sound are computed from this, so they cannot disagree.
 */
class SessionPlan(val cycles: Int) {
    init {
        require(cycles > 0) { "cycles must be positive" }
    }

    val breathingSeconds: Double = cycles * CYCLE_SECONDS

    /** Session time at which the last hold ends. */
    val endTime: Double = SETTLE_SECONDS + breathingSeconds

    val phaseCount: Int = cycles * 4

    fun phaseStart(index: Int): Double = SETTLE_SECONDS + index * PHASE_SECONDS

    fun frameAt(t: Double): BreathFrame {
        if (t < SETTLE_SECONDS) {
            val e = max(0.0, t)
            return BreathFrame(
                stage = Stage.SETTLE,
                phase = null,
                phaseIndex = -1,
                phaseElapsed = e,
                progress = e / SETTLE_SECONDS,
                level = 0.0,
                cycle = 0,
                countdown = wholeSecondsLeft(SETTLE_SECONDS - e, SETTLE_SECONDS),
                remaining = breathingSeconds,
            )
        }
        val tb = t - SETTLE_SECONDS
        if (tb >= breathingSeconds) {
            return BreathFrame(
                stage = Stage.COMPLETE,
                phase = null,
                phaseIndex = phaseCount,
                phaseElapsed = tb - breathingSeconds,
                progress = 1.0,
                level = 0.0,
                cycle = cycles,
                countdown = 0,
                remaining = 0.0,
            )
        }
        val index = min(phaseCount - 1, floor(tb / PHASE_SECONDS).toInt())
        val elapsed = tb - index * PHASE_SECONDS
        val p = (elapsed / PHASE_SECONDS).coerceIn(0.0, 1.0)
        val phase = Phase.entries[index % 4]
        val level = when (phase) {
            Phase.INHALE -> BreathCurve.rise(p)
            Phase.HOLD_FULL -> 1.0
            Phase.EXHALE -> 1.0 - BreathCurve.rise(p)
            Phase.HOLD_EMPTY -> 0.0
        }
        return BreathFrame(
            stage = Stage.BREATHING,
            phase = phase,
            phaseIndex = index,
            phaseElapsed = elapsed,
            progress = p,
            level = level,
            cycle = index / 4,
            countdown = wholeSecondsLeft(PHASE_SECONDS - elapsed, PHASE_SECONDS),
            remaining = breathingSeconds - tb,
        )
    }

    // 4.0 → 4, 3.5 → 4, 3.0 → 3, ... 0.2 → 1. The epsilon keeps 3.0000000001 from reading 4.
    private fun wholeSecondsLeft(left: Double, full: Double): Int =
        ceil(left - 1e-9).toInt().coerceIn(1, full.toInt())

    companion object {
        const val SETTLE_SECONDS = 8.0
        const val PHASE_SECONDS = 4.0
        const val CYCLE_SECONDS = PHASE_SECONDS * 4

        /** How long the closing chord rings after the last hold. */
        const val CLOSING_SECONDS = 8.0

        val CYCLE_CHOICES = intArrayOf(2, 6, 10, 20, 36, 50)
        const val DEFAULT_CYCLES = 10
    }
}

/**
 * The box the dot travels around: a rounded square, walked clockwise from the
 * bottom-left corner. Every side is the same length (half a corner, a straight,
 * half a corner), so side + fraction also measures the whole outline in quarters.
 */
object BoxGeometry {
    /**
     * Writes the screen position (y down) into [out] for a point [f] (0..1) along [side],
     * on a square centred at (cx, cy) with half-size [h] and corner radius [r].
     */
    fun point(side: Int, f: Double, cx: Double, cy: Double, h: Double, r: Double, out: DoubleArray) {
        val arc = PI * r / 4.0
        val straight = 2.0 * (h - r)
        val d = f.coerceIn(0.0, 1.0) * (straight + 2.0 * arc)
        val c = h - r
        // Side 0 in y-up coordinates: half of the bottom-left corner, up the left edge,
        // half of the top-left corner.
        var x: Double
        var y: Double
        if (d <= arc) {
            val a = 1.25 * PI - d / r
            x = -c + r * cos(a)
            y = -c + r * sin(a)
        } else if (d <= arc + straight) {
            x = -h
            y = -c + (d - arc)
        } else {
            val a = PI - (d - arc - straight) / r
            x = -c + r * cos(a)
            y = c + r * sin(a)
        }
        // The other sides are the same walk turned clockwise by a quarter each.
        repeat(((side % 4) + 4) % 4) {
            val nx = y
            y = -x
            x = nx
        }
        out[0] = cx + x
        out[1] = cy - y
    }
}
