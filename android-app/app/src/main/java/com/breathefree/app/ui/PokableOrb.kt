package com.breathefree.app.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotateRad
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import kotlin.math.abs
import kotlin.math.atan2
import kotlinx.coroutines.launch

/**
 * How far something held at an edge goes when pulled [overshoot] past it: a little over half as
 * far at first, then less and less, never as far as [limit]. Apple's rubber band, as a scroll
 * view's at its end.
 */
fun rubberBand(overshoot: Float, limit: Float, constant: Float = 0.55f): Float =
    overshoot * limit * constant / (limit + constant * abs(overshoot))

/** The pull that [rubberBand] takes as far as [band]: the other way round. */
fun unRubberBand(band: Float, limit: Float, constant: Float = 0.55f): Float {
    val b = band.coerceIn(-0.999f * limit, 0.999f * limit)
    return b * limit / (constant * (limit - abs(b)))
}

private fun rubberBand(pull: Offset, limit: Float): Offset {
    val d = pull.getDistance()
    return if (d == 0f) pull else pull * (rubberBand(d, limit) / d)
}

private fun unRubberBand(band: Offset, limit: Float): Offset {
    val d = band.getDistance()
    return if (d == 0f) band else band * (unRubberBand(d, limit) / d)
}

/** The furthest the orb goes however far it is pulled, as a share of its canvas. */
private const val REACH = 0.35f

/** How far it is drawn out toward the finger at its furthest. */
private const val STRETCH = 0.32f

/** How much smaller it gets under the finger. */
private const val DENT = 0.05f

/** The ring it sends out when let go: how long it lasts, and how far out it gets. */
private const val RING_SECONDS = 1.6
private const val RING_SPREAD = 1.3f

/** Home with a little bounce, as a thing let go of. */
private val HOME = spring(dampingRatio = 0.55f, stiffness = 300f, visibilityThreshold = Offset(0.5f, 0.5f))

/** The drop's wobble as it lands in a session (Drip.kt): 2.4 times a second, dying away as e^(-4.2 t). */
private val WOBBLE = spring(dampingRatio = 0.28f, stiffness = 227f, visibilityThreshold = 0.001f)

/** Asked for less motion: home without overshooting. */
private val HOME_STILL = spring(dampingRatio = 1f, stiffness = Spring.StiffnessMedium, visibilityThreshold = Offset(0.5f, 0.5f))
private val SETTLE_STILL = spring(dampingRatio = 1f, stiffness = Spring.StiffnessMedium, visibilityThreshold = 0.001f)

/**
 * The orb on the home and done screens, which can be poked. It gives a little under the finger,
 * follows a drag a short way, held back more the further it goes and drawn out toward the
 * finger; let go, it springs home at the speed it was going, wobbling as the drop does when it
 * lands in a session, and sends out a ring. It can be caught again on its way. Asked for less
 * motion, it still follows the finger, but goes home without the wobble or the ring. [radius]
 * (a share of the canvas) and [level] give its size and how full it is at each moment.
 */
@Composable
fun PokableOrb(
    frameNanos: State<Long>,
    still: Boolean,
    radius: (Double) -> Float,
    level: (Double) -> Float,
    modifier: Modifier = Modifier,
) {
    val ink = LocalInk.current
    val scope = rememberCoroutineScope()
    val radiusNow by rememberUpdatedState(radius)
    // Where it is from its place, and how far it is drawn out along `axis` (squashed when less than 0).
    val pull = remember { Animatable(Offset.Zero, Offset.VectorConverter, Offset(0.5f, 0.5f)) }
    val drawnOut = remember { Animatable(0f, visibilityThreshold = 0.001f) }
    var axis by remember { mutableFloatStateOf(0f) }
    // Where the finger has taken it, while the finger is down.
    var held by remember { mutableStateOf<Offset?>(null) }
    val dent = remember { Animatable(0f) }
    var ringAt by remember { mutableLongStateOf(Long.MIN_VALUE) }
    var ringFrom by remember { mutableFloatStateOf(0f) }
    var ringStrength by remember { mutableFloatStateOf(0f) }

    Canvas(
        modifier.pointerInput(still) {
            val side = minOf(size.width, size.height).toFloat()
            val reach = side * REACH
            fun stretchOf(p: Offset) = STRETCH * p.getDistance() / reach
            awaitEachGesture {
                val down = awaitFirstDown()
                down.consume()
                // Caught on its way home, it carries on from where it is.
                val from = unRubberBand(pull.value, reach)
                held = pull.value
                scope.launch { pull.stop() }
                scope.launch { drawnOut.stop() }
                scope.launch { dent.animateTo(1f, tween(100, easing = LinearOutSlowInEasing)) }
                val tracker = VelocityTracker()
                tracker.addPosition(down.uptimeMillis, pull.value)
                while (true) {
                    val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) {
                        // Held still before it was let go, it was going nowhere.
                        tracker.addPosition(change.uptimeMillis, held ?: Offset.Zero)
                        break
                    }
                    val p = rubberBand(from + (change.position - down.position), reach)
                    held = p
                    axis = atan2(p.y, p.x)
                    tracker.addPosition(change.uptimeMillis, p)
                    change.consume()
                }
                val let = held ?: Offset.Zero
                val velocity = tracker.calculateVelocity()
                val stretch = stretchOf(let)
                scope.launch {
                    pull.snapTo(let)
                    drawnOut.snapTo(stretch)
                    held = null
                    launch { pull.animateTo(Offset.Zero, if (still) HOME_STILL else HOME, Offset(velocity.x, velocity.y)) }
                    launch { drawnOut.animateTo(0f, if (still) SETTLE_STILL else WOBBLE) }
                }
                scope.launch { dent.animateTo(0f, if (still) SETTLE_STILL else WOBBLE) }
                if (!still) {
                    ringAt = frameNanos.value
                    ringFrom = side * radiusNow(frameNanos.value / 1e9)
                    ringStrength = 0.16f + 0.16f * (let.getDistance() / reach)
                }
            }
        },
    ) {
        val t = frameNanos.value / 1e9
        val r = size.minDimension * radius(t) * (1 - DENT * dent.value)
        val p = held ?: pull.value
        val stretch = held?.let { STRETCH * it.getDistance() / (size.minDimension * REACH) } ?: drawnOut.value
        val c = center + p
        val age = (frameNanos.value - ringAt) / 1e9
        if (age in 0.0..RING_SECONDS) {
            val fade = (1 - age / RING_SECONDS).toFloat()
            drawCircle(
                color = ink.line.copy(alpha = ringStrength * fade * fade),
                radius = ringFrom * (1 + RING_SPREAD * (1 - fade * fade)),
                center = center,
                style = Stroke(width = density * 1.5f),
            )
        }
        // Drawn out along the way it was pulled, and narrower across it.
        withTransform({
            rotateRad(axis, c)
            scale(1 + stretch, 1 / (1 + stretch), c)
            rotateRad(-axis, c)
        }) {
            drawOrb(c, r, level(t), ink.orb, ink.sun)
        }
    }
}
