package com.breathefree.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.breathefree.app.core.SoundMode
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Sound, voice, vibration and focus mode, folded into one round button at the top right of the home screen,
// where a session's speaker is. Tapped, its sliders turn into a ✕ and the settings open out of
// it as a fan of drops of the same liquid as the session-length circle (LiquidFan): out of the
// button as one drop, then swinging round it, down and to the left, each pulling free of the
// one before it, each showing its setting's icon. A tap on a drop changes that setting and
// leaves the fan open, so more than one can be changed; the ✕, a touch anywhere else, or Back
// folds it: the drops swing back into one and go home. A drop wears the lit colour while its
// setting is on. Kept in step with the browser version's settings-fan.tsx, which has no focus
// mode yet.

/** The drops, the size of the session-length circle's. */
private val DROP = 48.dp

/** The round button, the size of a session's. */
private val BUTTON = 44.dp

/**
 * From the button's centre to each drop's. Four drops share the quarter circle, 30 degrees
 * apart (LiquidFan), so they sit further out than the browser version's three, to keep 10 dp
 * of sky between neighbours.
 */
private val DISTANCE = 112.dp

/** Opening, the drops come out together; this long after, they start to swing round. */
private const val SWEEP_AFTER_MS = 50L

/** Folding, they swing back into one; this long after, they go home into the button. */
private const val HOME_AFTER_MS = 110L

/** The springs out from the button and round it, with a little bounce, as a fan's blades. */
private const val OUT_DAMPING = 0.62f
private const val OUT_STIFFNESS = 260f
private const val SWEEP_DAMPING = 0.55f
private const val SWEEP_STIFFNESS = 200f

/** The button's sliders cross into the ✕ with a little overshoot, and their knobs go. */
private val CROSSING = CubicBezierEasing(0.34f, 1.45f, 0.5f, 1f)
private val EASE = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f)

private val SoundMode.named: String
    get() = when (this) {
        SoundMode.AMBIENT -> "Ambient"
        SoundMode.BELLS -> "Bells"
        SoundMode.SILENT -> "Silent"
    }

/**
 * The settings fan, laid over the whole home screen: its button sits in the top-right corner,
 * and while it is open, a touch anywhere but on it folds it and goes no further, so it doesn't
 * also press whatever is underneath. [open] says whether it is open; [onOpen] asks to open or
 * fold it.
 */
@Composable
fun SettingsFan(
    open: Boolean,
    onOpen: (Boolean) -> Unit,
    sound: SoundMode,
    onSound: (SoundMode) -> Unit,
    voice: Boolean,
    onVoice: (Boolean) -> Unit,
    vibrate: Boolean,
    onVibrate: (Boolean) -> Unit,
    focus: Boolean,
    onFocus: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val ink = LocalInk.current
    val setOpen by rememberUpdatedState(onOpen)
    BackHandler(enabled = open) { setOpen(false) }

    val lit = listOf(sound != SoundMode.SILENT, voice, vibrate, focus)
    val motion = remember { FanMotion(open, lit) }

    // Opening, the drops come out of the button together, then swing round to their places;
    // folding, they swing back into one, then go home. With animations turned off they are
    // simply there, or gone.
    LaunchedEffect(open) {
        val still = coroutineContext[MotionDurationScale]?.scaleFactor == 0f
        // Folding from a fan that has not swung open yet, the drops go home at once.
        val together = still || motion.sweep.all { it.value < 0.05f }
        for (i in lit.indices) {
            launch {
                if (open) {
                    motion.out[i].animateTo(1f, spring(OUT_DAMPING, OUT_STIFFNESS))
                } else {
                    if (!together) delay(HOME_AFTER_MS)
                    motion.out[i].animateTo(0f, spring(1f, LiquidMotion.CLOSE_STIFFNESS))
                }
            }
            launch {
                if (open) {
                    if (!still) delay(SWEEP_AFTER_MS)
                    motion.sweep[i].animateTo(1f, spring(SWEEP_DAMPING, SWEEP_STIFFNESS))
                } else {
                    motion.sweep[i].animateTo(0f, spring(1f, LiquidMotion.CLOSE_STIFFNESS))
                }
            }
        }
    }
    // A setting changed while open turns its drop's colour on or off.
    LaunchedEffect(lit) {
        for (i in lit.indices) {
            launch { motion.lit[i].animateTo(if (lit[i]) 1f else 0f, tween(LiquidMotion.RECOLOUR_MS)) }
        }
    }

    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val cross by animateFloatAsState(if (open) 1f else 0f, tween(320, easing = CROSSING), label = "cross")
    val knobs by animateFloatAsState(if (open) 0f else 1f, tween(200, easing = EASE), label = "knobs")

    Box(modifier) {
        if (open) {
            Box(
                Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        awaitEachGesture {
                            awaitFirstDown(requireUnconsumed = false).consume()
                            setOpen(false)
                        }
                    }
                    .clearAndSetSemantics { },
            )
        }
        Box(
            Modifier
                .align(Alignment.TopEnd)
                // Where a session's speaker is: 10 dp down, 16 dp in.
                .padding(top = 10.dp, end = 16.dp)
                .size(BUTTON)
                // The liquid, drawn from the button's centre out past its edges.
                .drawBehind { drawFan(motion.shape(this, open), ink, motion.settled, pressed) }
                .semantics { isTraversalGroup = true },
        ) {
            val next = SoundMode.entries[(sound.ordinal + 1) % SoundMode.entries.size]
            Drop(
                motion, 0, open,
                Modifier
                    .clickable(interactionSource = null, indication = null, onClickLabel = "change to ${next.named}", role = Role.Button) {
                        onSound(next)
                    }
                    .semantics {
                        contentDescription = "Sound"
                        stateDescription = sound.named
                    },
            ) { color ->
                FanIcons.draw(this, FanIcons.sound(sound), color)
            }
            Drop(
                motion, 1, open,
                Modifier
                    .toggleable(voice, interactionSource = null, indication = null, role = Role.Switch, onValueChange = onVoice)
                    .semantics { contentDescription = "Voice guidance" },
            ) { color ->
                FanIcons.draw(this, if (voice) FanIcons.voiceOn else FanIcons.voiceOff, color)
            }
            Drop(
                motion, 2, open,
                Modifier
                    .toggleable(vibrate, interactionSource = null, indication = null, role = Role.Switch, onValueChange = onVibrate)
                    .semantics { contentDescription = "Vibrate at each change" },
            ) { color ->
                FanIcons.draw(this, if (vibrate) FanIcons.vibrateOn else FanIcons.vibrateOff, color)
            }
            Drop(
                motion, 3, open,
                Modifier
                    .toggleable(focus, interactionSource = null, indication = null, role = Role.Switch, onValueChange = onFocus)
                    .semantics { contentDescription = "Focus mode" },
            ) { color ->
                FanIcons.draw(this, if (focus) FanIcons.focusOn else FanIcons.focusOff, color)
            }

            // The button itself, over the drops waiting inside it.
            Box(
                Modifier
                    .matchParentSize()
                    .clickable(interaction, indication = null, onClickLabel = if (open) "close" else "open", role = Role.Button) {
                        onOpen(!open)
                    }
                    .semantics {
                        contentDescription = "Settings"
                        stateDescription = if (open) "Expanded" else "Collapsed"
                        traversalIndex = -1f
                    },
                contentAlignment = Alignment.Center,
            ) {
                Canvas(Modifier.size(20.dp)) { sliders(ink.deep, cross, knobs) }
            }
        }
    }
}

/**
 * The fan's springs, a pair for each drop: how far it has come out of the button (0 at home
 * inside it, 1 at its distance) and how far it has swung round from the first (0 with it, 1 in
 * its own place); and how far its setting is on, for its colour.
 */
private class FanMotion(open: Boolean, on: List<Boolean>) {
    val out = on.map { Animatable(if (open) 1f else 0f) }
    val sweep = on.map { Animatable(if (open) 1f else 0f) }
    val lit = on.map { Animatable(if (it) 1f else 0f) }

    val settled: Boolean get() = (out + sweep).none { it.isRunning }

    /** The fan as it is this moment, read where it is drawn and placed, so the motion moves it without composing it again. */
    fun shape(density: Density, opening: Boolean): FanShape = with(density) {
        LiquidFan.drops(
            FloatArray(out.size) { out[it].value },
            FloatArray(out.size) { out[it].velocity },
            FloatArray(out.size) { sweep[it].value },
            FloatArray(out.size) { sweep[it].velocity },
            FloatArray(out.size) { lit[it].value },
            opening,
            DROP.toPx(),
            BUTTON.toPx(),
            DISTANCE.toPx(),
        )
    }
}

/**
 * A setting's drop: a real button over its circle in the liquid, moved with it, its icon as
 * clear as the drop is. Folded, it waits inside the fan's button, where it can't be pressed or
 * found.
 */
@Composable
private fun BoxScope.Drop(motion: FanMotion, i: Int, open: Boolean, touch: Modifier, icon: DrawScope.(Color) -> Unit) {
    val ink = LocalInk.current
    Box(
        Modifier
            .align(Alignment.Center)
            .offset { motion.shape(this, open).drops[i].run { IntOffset(x.roundToInt(), y.roundToInt()) } }
            .requiredSize(DROP)
            .semantics { traversalIndex = i.toFloat() }
            .then(if (open) touch else Modifier.clearAndSetSemantics { }),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(22.dp).graphicsLayer { alpha = motion.shape(this, open).drops[i].label }) {
            icon(lerp(ink.deep, ink.onAccent, motion.lit[i].value))
        }
    }
}

/**
 * The button and the drops: at rest, plain circles; on the move, all of them as one shape of
 * liquid, run together wherever they meet; with a rim inside the edge like a border, and the
 * drops whose setting is on solid on top.
 */
private fun DrawScope.drawFan(fan: FanShape, ink: Ink, settled: Boolean, pressed: Boolean) {
    val rim = 1.dp.toPx()
    translate(center.x, center.y) {
        if (settled) {
            circle(fan.home, if (pressed) ink.glassPressed else ink.field, ink.fieldBorder, rim)
            for (d in fan.drops) if (d.radius > 0.05f) circle(d.liquid, ink.field, ink.fieldBorder, rim)
        } else {
            val outline = Path().apply { fillType = PathFillType.EvenOdd }
            for (loop in LiquidOutline.loops(listOf(fan.home) + fan.drops.map { it.liquid }, inset = rim / 2, cell = 2.dp.toPx())) {
                outline.moveTo(loop[0], loop[1])
                for (n in 2 until loop.size step 2) outline.lineTo(loop[n], loop[n + 1])
                outline.close()
            }
            drawPath(outline, ink.field)
            drawPath(outline, ink.fieldBorder, style = Stroke(rim))
        }
        for (d in fan.drops) {
            if (d.accent <= 0f || d.radius <= 0.05f) continue
            // Drawn out along the way it is going.
            rotate(Math.toDegrees(d.angle.toDouble()).toFloat(), pivot = Offset(d.x, d.y)) {
                drawOval(
                    ink.accent.copy(alpha = ink.accent.alpha * d.accent.coerceAtMost(1f)),
                    topLeft = Offset(d.x - d.radius * d.stretch, d.y - d.radius / d.stretch),
                    size = Size(2 * d.radius * d.stretch, 2 * d.radius / d.stretch),
                )
            }
        }
    }
}

private fun DrawScope.circle(d: LiquidDrop, fill: Color, edge: Color, rim: Float) {
    drawCircle(fill, d.radius, Offset(d.x, d.y))
    drawCircle(edge, d.radius - rim / 2, Offset(d.x, d.y), style = Stroke(rim))
}

/**
 * The button's icon on a 24-unit grid: two sliders, each a bar with its knob, that meet in the
 * middle and cross into a ✕ as [cross] goes from 0 to 1, their knobs shrinking away as [knobs]
 * goes from 1 to 0.
 */
private fun DrawScope.sliders(color: Color, cross: Float, knobs: Float) {
    val k = size.minDimension / 24f
    scale(k, k, pivot = Offset.Zero) {
        for ((side, knob) in listOf(-1f to 15f, 1f to 9f)) {
            withTransform({
                translate(0f, side * 4.5f * (1 - cross))
                rotate(-side * 45f * cross, pivot = Offset(12f, 12f))
                scale(1 + 0.06f * cross, 1f, pivot = Offset(12f, 12f))
            }) {
                drawLine(color, Offset(4f, 12f), Offset(20f, 12f), strokeWidth = 2f, cap = StrokeCap.Round)
                if (knobs > 0f) drawCircle(color, 2.6f * knobs, Offset(knob, 12f))
            }
        }
    }
}

/** The settings' icons on a 24-unit grid, line for line as the browser version's. */
private object FanIcons {
    private fun path(d: String): Path = PathParser().parsePathString(d).toPath()

    /** Waves for Ambient, a bell for Bells, and the speaker crossed out for Silent. */
    private val ambient = path("M3 9c1.5-2 3-2 4.5 0s3 2 4.5 0 3-2 4.5 0 3 2 4.5 0M3 15c1.5-2 3-2 4.5 0s3 2 4.5 0 3-2 4.5 0 3 2 4.5 0")
    private val bells = path("M6.5 16v-5a5.5 5.5 0 0 1 11 0v5l1.5 2h-14zM10.2 20.6a2 2 0 0 0 3.6 0")
    private val silent = path("M3 9h4l5-4.5v15L7 15H3zM15.5 9.5l5 5M20.5 9.5l-5 5")

    fun sound(mode: SoundMode): Path = when (mode) {
        SoundMode.AMBIENT -> ambient
        SoundMode.BELLS -> bells
        SoundMode.SILENT -> silent
    }

    /** A head speaking, or with a cross where its words would be, as the silent speaker. */
    private const val HEAD = "M5.5 8.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0zM3 20c0-3.4 2.7-5.5 6-5.5s6 2.1 6 5.5"
    val voiceOn = path("${HEAD}M16 6.2a4 4 0 0 1 0 5.6M18.8 3.6a7.6 7.6 0 0 1 0 10.8")
    val voiceOff = path("${HEAD}M16 6.5l4.5 4.5M20.5 6.5L16 11")

    /** A phone buzzing, as Android's own ringer shows it; still, moved aside for the same cross. */
    val vibrateOn = path("M10.5 3.5h3a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2h-3a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2zM5 8.5v7M19 8.5v7M1.5 10.5v3M22.5 10.5v3")
    val vibrateOff = path("M6 3.5h3a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2h-3a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2zM15.5 9.5l5 5M20.5 9.5l-5 5")

    /** A viewfinder's corners round one point; struck through, for everything in view. */
    private const val FRAME = "M3 8V5.5A2.5 2.5 0 0 1 5.5 3H8M16 3h2.5A2.5 2.5 0 0 1 21 5.5V8" +
        "M21 16v2.5a2.5 2.5 0 0 1-2.5 2.5H16M8 21H5.5A2.5 2.5 0 0 1 3 18.5V16M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0z"
    val focusOn = path(FRAME)
    val focusOff = path("${FRAME}M6.5 17.5l11-11")

    fun draw(scope: DrawScope, path: Path, color: Color) = with(scope) {
        val k = size.minDimension / 24f
        scale(k, k, pivot = Offset.Zero) {
            drawPath(path, color, style = Stroke(2f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
    }
}
