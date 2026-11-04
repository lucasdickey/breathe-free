package com.breathefree.app.ui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.lerp
import com.breathefree.app.core.BoxGeometry
import com.breathefree.app.core.BreathCurve
import com.breathefree.app.core.BreathFrame
import com.breathefree.app.core.Phase
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.Stage
import kotlin.math.PI
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

/**
 * Orb colours, from empty lungs (low) to full (high), for one moment of the sky: each of the
 * sky's keys has its own ([DaySky]), so the orb sits in the sky's light, cyan by night,
 * peach at sunrise, gold at golden hour, mauve as the light goes.
 */
@Immutable
data class OrbColors(
    val coreLow: Color,
    val coreHigh: Color,
    val edgeLow: Color,
    val edgeHigh: Color,
    /** The light round the orb, and round the dot that travels the box. */
    val glow: Color,
    /** How strongly the glow adds its light: fully on a dark sky, faintly where the sky is already bright. */
    val shine: Float = 1f,
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
            glow = Color(0xFF7FD6EE), shine = 0.15f,
        )

        fun between(a: OrbColors, b: OrbColors, t: Float) = OrbColors(
            coreLow = lerp(a.coreLow, b.coreLow, t),
            coreHigh = lerp(a.coreHigh, b.coreHigh, t),
            edgeLow = lerp(a.edgeLow, b.edgeLow, t),
            edgeHigh = lerp(a.edgeHigh, b.edgeHigh, t),
            glow = lerp(a.glow, b.glow, t),
            shine = a.shine + (b.shine - a.shine) * t,
        )
    }
}

/** How far the glow reaches, as a multiple of the orb's radius. */
private const val GLOW_REACH = 1.55f

/** The deep blue the orb's rim darkens toward. */
private val SHADE = Color(0xFF0B1D3A)

/**
 * The orb, as a ball of glass: thin in the middle so the sky shows through, thicker toward the
 * rim, with the sky's reflection and a sharp glint on the side the sun is on ([sun], an angle
 * round the orb, so the light goes round it through the day) and the light gathered inside on
 * the far side. Every layer is a plain radial gradient filling the orb's circle, so the Mac and
 * the web draw the same ball.
 */
fun DrawScope.drawOrb(center: Offset, radius: Float, level: Float, colors: OrbColors, sun: Float, alpha: Float = 1f) {
    if (alpha <= 0f || radius <= 0f) return
    // Glow: light added round the orb in its own colour, falling away smoothly. Added, not
    // painted over, so the clouds behind keep their contrast at every breath: a glow that
    // veiled them as the lungs filled let them come back at the end of each cycle, which
    // looked like the sky starting over. Faint where the sky is already bright.
    val glowRadius = radius * GLOW_REACH
    val strength = (0.20f + 0.08f * level) * colors.shine * alpha
    if (strength > 0.002f) {
        val edge = 1f / GLOW_REACH
        // (1 - f)² from the orb's edge out, f going 0 to 1 across the glow.
        fun at(f: Float) = (edge + (1f - edge) * f) to colors.glow.copy(alpha = strength * (1f - f) * (1f - f))
        drawCircle(
            brush = Brush.radialGradient(
                0f to colors.glow.copy(alpha = strength),
                at(0f), at(0.25f), at(0.5f), at(0.75f), at(1f),
                center = center,
                radius = glowRadius,
            ),
            radius = glowRadius,
            center = center,
            blendMode = BlendMode.Plus,
        )
    }
    // [k] radii from the middle, toward the sun (or away from it, for negative k).
    val toward = Offset(cos(sun), -sin(sun))
    fun along(k: Float) = center + toward * (radius * k)
    fun layer(at: Offset, reach: Float, vararg stops: Pair<Float, Color>) = drawCircle(
        brush = Brush.radialGradient(*stops, center = at, radius = radius * reach),
        radius = radius,
        center = center,
    )
    fun Color.at(a: Float) = copy(alpha = a * alpha)
    val white = Color.White
    val core = lerp(colors.coreLow, colors.coreHigh, level)
    val edge = lerp(colors.edgeLow, colors.edgeHigh, level)

    // The glass itself: thin enough by day for the sky to show through, fuller after dark, lit
    // from within as the glow shines, so the count in the middle still reads on a night sky.
    val within = ((colors.shine - OrbColors.Day.shine) / (1f - OrbColors.Day.shine)).coerceIn(0f, 1f)
    layer(
        center, 1f,
        0f to core.at(0.24f + 0.4f * within), 0.5f to core.at(0.34f + 0.34f * within),
        0.8f to lerp(core, edge, 0.55f).at(0.6f + 0.1f * within),
        0.94f to edge.at(0.9f), 1f to lerp(edge, SHADE, 0.4f).at(0.95f),
    )
    // The sky's reflection across the lit side.
    layer(along(0.6f), 0.66f, 0f to white.at(0.42f), 0.6f to white.at(0.12f), 1f to white.at(0f))
    // Light gathered inside, opposite the sun.
    val inner = lerp(colors.coreHigh, white, 0.5f)
    layer(along(-0.5f), 0.62f, 0f to inner.at(0.72f), 0.5f to inner.at(0.29f), 1f to inner.at(0f))
    // The glint: a sharp oval toward the sun, lying across the light.
    withTransform({
        translate(along(0.58f).x, along(0.58f).y)
        rotate(-sun * 180f / PI.toFloat(), pivot = Offset.Zero)
        scale(0.1f, 0.17f, pivot = Offset.Zero)
    }) {
        drawCircle(
            brush = Brush.radialGradient(
                0f to white.at(0.98f), 0.5f to white.at(0.92f), 0.8f to white.at(0.35f), 1f to white.at(0f),
                center = Offset.Zero,
                radius = radius,
            ),
            radius = radius,
            center = Offset.Zero,
        )
    }
    // And a small one on the far side, where the glass catches the sky.
    val far = along(-0.8f)
    drawCircle(
        brush = Brush.radialGradient(0f to white.at(0.6f), 1f to white.at(0f), center = far, radius = radius * 0.07f),
        radius = radius * 0.07f,
        center = far,
    )
    // A hairline where the glass meets the sky.
    drawCircle(
        color = white.at(0.4f),
        radius = radius - density * 0.5f,
        center = center,
        style = Stroke(width = density),
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
