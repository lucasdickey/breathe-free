package com.breathefree.app.ui

import kotlin.math.PI
import kotlin.math.cbrt
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A drop hanging under the top of the box: from the line at [ax], with its bulb of radius [rb]
 * centred at ([bx], [by]), a neck [wn] either side of [ax] where it meets the line, and the
 * neck leaving the bulb [phi] radians either side of its top.
 */
data class Hanging(val ax: Double, val bx: Double, val by: Double, val rb: Double, val wn: Double, val phi: Double)

/** A falling drop of radius [r] at ([x], [y]), drawn out [sy] tall and [sx] wide by its speed. */
data class Falling(val x: Double, val y: Double, val r: Double, val sx: Double, val sy: Double)

/**
 * One instant of the opening. [orb] is the orb's radius once the drop has landed (0 before),
 * squashed [squash] wider than tall as it wobbles.
 */
class DripFrame(
    val hanging: Hanging?,
    val bead: Hanging?,
    val drop: Falling?,
    val satellite: Falling?,
    val orb: Double,
    val squash: Double,
)

/**
 * The opening, during the settle: a drop gathers under the middle of the top of the box,
 * swaying a little in the breeze, necks and lets go, and falls into the middle, where it lands
 * as the orb with a wobble and a ring; the bead it leaves on the line springs back into it.
 * Everything here is in half-sizes of the box from its centre, y down, so the top is at y = -1.
 * The Mac and the web follow the same numbers.
 */
object Drip {
    private const val GATHERS = 1.8
    private const val GATHERED = 3.6
    private const val LETS_GO = 4.15
    private const val FALL = 0.42

    /** When the drop lands in the middle of the box. */
    const val LANDS = LETS_GO + FALL

    /** How long the orb takes to swell from the drop to its size for the settle. */
    private const val SWELL = 0.85

    /** The drop's radius once it has gathered. */
    private const val R = 0.24
    private const val SWAY = 0.035

    private fun clamp(x: Double) = x.coerceIn(0.0, 1.0)
    private fun lerp(a: Double, b: Double, t: Double) = a + (b - a) * t
    private fun ease(x: Double) = 0.5 - 0.5 * cos(PI * clamp(x))
    private fun easeOut(x: Double) = 1 - (1 - clamp(x)).let { it * it * it }
    private fun easeIn(x: Double) = clamp(x).let { it * it }
    private fun degrees(d: Double) = d * PI / 180

    /** How much wider than tall the orb is [tau] seconds after landing: a wobble dying away. */
    private fun wobble(tau: Double) = if (tau < 0) 0.0 else 0.26 * exp(-4.2 * tau) * cos(2 * PI * 2.4 * tau)

    /** How far the count on the orb has faded in: it waits for the drop to land. */
    fun countAlpha(t: Double): Float = clamp((t - LANDS) / 0.6).toFloat()

    fun at(t: Double): DripFrame {
        var hanging: Hanging? = null
        var bead: Hanging? = null
        var drop: Falling? = null
        var satellite: Falling? = null
        if (t >= GATHERS && t < LETS_GO) {
            // Gathering (g, 0 to 1), then necking (u) until it lets go.
            val g = ease((t - GATHERS) / (GATHERED - GATHERS))
            val u = if (t < GATHERED) 0.0 else easeIn((t - GATHERED) / (LETS_GO - GATHERED))
            val rb = max(0.012, R * cbrt(g))
            val breeze = SWAY * sin((t - GATHERS) * 2.6) * g * (1 - u)
            val yb = rb * lerp(0.35, 1.05, g) + u * 0.2
            val wn = rb * lerp(1.1, 0.75, g) * lerp(1.0, 0.18, u)
            hanging = Hanging(0.0, breeze, -1 + yb, rb, wn, degrees(lerp(80.0, 62.0, g) - 40 * u))
        } else if (t >= LETS_GO) {
            val since = t - LETS_GO
            // The bead left on the line springs back into it.
            if (since < 0.8) {
                val rb = R * 0.32 * (1 - easeOut(since / 0.8))
                if (rb > 0.004) {
                    val yb = rb * (0.55 + 0.5 * exp(-5 * since) * cos(2 * PI * 3 * since))
                    bead = Hanging(0.0, 0.0, -1 + yb, rb, rb * 1.1, degrees(85.0))
                }
            }
            // Falling faster all the way, drawn out by its speed, from where it let go to the middle.
            val from = -1 + R * 1.05 + 0.2
            if (t < LANDS) {
                val f = since / FALL
                val stretch = 1 + 0.16 * (1 - f) + 0.14 * f
                drop = Falling(0.0, from * (1 - f * f), R, 1 / sqrt(stretch), stretch)
            }
            // A small drop pinched off behind it, following it down.
            val sf = (since - 0.05) / FALL
            if (sf > 0 && sf < 1) satellite = Falling(0.0, (from - R * 0.9) * (1 - sf * sf), 0.032, 1.0, 1.0)
        }
        val orb = if (t < LANDS) 0.0 else lerp(R, SceneGeometry.ORB_MIN.toDouble(), easeOut((t - LANDS) / SWELL))
        return DripFrame(hanging, bead, drop, satellite, orb, wobble(t - LANDS))
    }
}
