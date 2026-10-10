package com.breathefree.app.ui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import com.breathefree.app.core.BoxGeometry
import com.breathefree.app.core.BreathCurve
import com.breathefree.app.core.BreathFrame
import com.breathefree.app.core.Phase
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.Stage
import kotlin.math.cos
import kotlin.math.sin

/** Where the box and orb sit, in pixels. The text layout uses the same numbers. */
class SceneGeometry(val cx: Float, val cy: Float, val half: Float) {
    val corner = half * 0.2f
    val orbMin = half * 0.36f
    val orbMax = half * 0.82f

    fun orbRadius(level: Double) = orbMin + (orbMax - orbMin) * level.toFloat()

    companion object {
        fun of(width: Float, height: Float): SceneGeometry {
            val portrait = height >= width
            val half = if (portrait) minOf(width * 0.34f, height * 0.2f) else minOf(width * 0.2f, height * 0.27f)
            return SceneGeometry(width / 2f, height * (if (portrait) 0.43f else 0.45f), half)
        }
    }
}

/** Orb colours, from empty lungs (low) to full (high). */
class OrbColors(
    val coreLow: Color,
    val coreHigh: Color,
    val edgeLow: Color,
    val edgeHigh: Color,
    val glow: Color,
) {
    companion object {
        val Night = OrbColors(
            coreLow = Color(0xFF7CC9E6), coreHigh = Color(0xFFC6F6FB),
            edgeLow = Color(0xFF1D6CA0), edgeHigh = Color(0xFF39B6D8),
            glow = Color(0xFF86E3F4),
        )
        val Day = OrbColors(
            coreLow = Color(0xFFBDEFF8), coreHigh = Color(0xFFE6FBFE),
            edgeLow = Color(0xFF2B95C2), edgeHigh = Color(0xFF3FB8D9),
            glow = Color(0xFF7FD6EE),
        )

        fun between(a: OrbColors, b: OrbColors, t: Float) = OrbColors(
            coreLow = lerp(a.coreLow, b.coreLow, t),
            coreHigh = lerp(a.coreHigh, b.coreHigh, t),
            edgeLow = lerp(a.edgeLow, b.edgeLow, t),
            edgeHigh = lerp(a.edgeHigh, b.edgeHigh, t),
            glow = lerp(a.glow, b.glow, t),
        )
    }
}

/** How far from the middle the orb's brightest spot sits, as a fraction of its radius. */
private const val LIGHT_REACH = 0.5f

fun DrawScope.drawOrb(center: Offset, radius: Float, level: Float, colors: OrbColors, sun: Float, alpha: Float = 1f) {
    if (alpha <= 0f || radius <= 0f) return
    // Halo: strongest at the rim, then fading over much the same width at every breath, so it
    // stays close to the orb and leaves the clouds beyond the box alone.
    val haloRadius = radius * (1.9f - 0.45f * level)
    val haloAlpha = (0.26f + 0.22f * level) * alpha
    val rim = (radius / haloRadius) * 0.92f
    drawCircle(
        brush = Brush.radialGradient(
            0f to colors.glow.copy(alpha = haloAlpha),
            rim to colors.glow.copy(alpha = haloAlpha),
            1f to colors.glow.copy(alpha = 0f),
            center = center,
            radius = haloRadius,
        ),
        radius = haloRadius,
        center = center,
    )
    // Body: lit from where the sun is ([sun], an angle round the orb), so the light goes round
    // it through the day.
    val light = Offset(center.x + radius * LIGHT_REACH * cos(sun), center.y - radius * LIGHT_REACH * sin(sun))
    val core = lerp(colors.coreLow, colors.coreHigh, level)
    val edge = lerp(colors.edgeLow, colors.edgeHigh, level)
    drawCircle(
        brush = Brush.radialGradient(
            0f to Color.White.copy(alpha = 0.95f * alpha),
            0.35f to core.copy(alpha = alpha),
            1f to edge.copy(alpha = alpha),
            center = light,
            radius = radius * 1.45f,
        ),
        radius = radius,
        center = center,
    )
    drawCircle(
        color = Color.White.copy(alpha = 0.22f * alpha),
        radius = radius - density * 0.75f,
        center = center,
        style = Stroke(width = density * 1.5f),
    )
}

/**
 * Draws the box, the trail of the current cycle, the travelling dot, the ripples and the orb
 * for one instant of a session, in the colours [ink] has for the sky. [t] is session time in
 * seconds.
 */
class SessionPainter {
    private val outline = Path()
    private val trail = Path()
    private val point = DoubleArray(2)

    fun draw(scope: DrawScope, g: SceneGeometry, plan: SessionPlan, frame: BreathFrame, t: Double, ink: Ink) = with(scope) {
        val settling = frame.stage == Stage.SETTLE
        val cx = g.cx.toDouble()
        val cy = g.cy.toDouble()
        val h = g.half.toDouble()
        val r = g.corner.toDouble()

        // The outline draws itself during the first seconds of the settle.
        val outlineFraction = if (settling) BreathCurve.rise(t / 2.5) else 1.0
        buildPath(outline, 0.0, 4.0 * outlineFraction, cx, cy, h, r)
        drawPath(
            outline,
            ink.line.copy(alpha = 0.18f),
            style = Stroke(width = density * 1.5f, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )

        val side = frame.boxSide()
        val along = frame.boxFraction()
        if (frame.stage == Stage.BREATHING) {
            buildPath(trail, 0.0, side + along, cx, cy, h, r)
            drawPath(
                trail,
                ink.line.copy(alpha = 0.5f),
                style = Stroke(width = density * 2.2f, cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }

        // Ripples: a ring leaves the orb at each change of phase and spreads as far as the box.
        if (frame.stage == Stage.BREATHING) {
            ripple(g, frame.phase!!, frame.phaseElapsed, ink.line)
            if (frame.phaseIndex > 0) {
                ripple(g, Phase.entries[(frame.phaseIndex - 1) % 4], frame.phaseElapsed + SessionPlan.PHASE_SECONDS, ink.line)
            }
        }

        val orbAlpha = if (settling) (t / 1.2).coerceIn(0.0, 1.0).toFloat() else 1f
        drawOrb(Offset(g.cx, g.cy), g.orbRadius(frame.level), frame.level.toFloat(), ink.orb, ink.sun, orbAlpha)

        // The dot: fades in at the start corner as the settle ends.
        val dotAlpha = when {
            settling -> ((t - (SessionPlan.SETTLE_SECONDS - 1.5)) / 1.5).coerceIn(0.0, 1.0).toFloat()
            frame.stage == Stage.BREATHING -> 1f
            else -> 0f
        }
        if (dotAlpha > 0f) {
            BoxGeometry.point(side, along, cx, cy, h, r, point)
            val p = Offset(point[0].toFloat(), point[1].toFloat())
            val glow = density * 16f
            drawCircle(
                brush = Brush.radialGradient(
                    0f to ink.dotGlow.copy(alpha = 0.7f * dotAlpha),
                    1f to ink.dotGlow.copy(alpha = 0f),
                    center = p,
                    radius = glow,
                ),
                radius = glow,
                center = p,
            )
            drawCircle(ink.dot.copy(alpha = dotAlpha), radius = density * 5f, center = p)
        }
    }

    private fun DrawScope.ripple(g: SceneGeometry, phase: Phase, age: Double, color: Color) {
        val start = (if (phase == Phase.INHALE || phase == Phase.HOLD_EMPTY) g.orbMin else g.orbMax).toDouble()
        val h = g.half.toDouble()
        val life = BoxGeometry.rippleSeconds(start, h)
        if (age >= life) return
        val strength = if (phase == Phase.INHALE || phase == Phase.EXHALE) 0.32f else 0.2f
        val fade = (1 - age / life).toFloat()
        drawCircle(
            color = color.copy(alpha = strength * fade * fade),
            radius = BoxGeometry.rippleRadius(start, age, h).toFloat(),
            center = Offset(g.cx, g.cy),
            style = Stroke(width = density * 1.5f),
        )
    }

    /** Fills [path] with the outline from quarter-position [from] to [to] (0..4 = once round). */
    private fun buildPath(path: Path, from: Double, to: Double, cx: Double, cy: Double, h: Double, r: Double) {
        path.reset()
        if (to <= from) return
        val steps = ((to - from) * STEPS_PER_SIDE).toInt().coerceAtLeast(1)
        for (i in 0..steps) {
            val q = from + (to - from) * i / steps
            val s = minOf(3, q.toInt())
            BoxGeometry.point(s, q - s, cx, cy, h, r, point)
            if (i == 0) path.moveTo(point[0].toFloat(), point[1].toFloat())
            else path.lineTo(point[0].toFloat(), point[1].toFloat())
        }
    }

    private companion object {
        const val STEPS_PER_SIDE = 96
    }
}
