package com.breathefree.app.ui

import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitHorizontalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Colours for everything drawn on the sky: [OnLight] for the daytime sky, [OnDark] from dusk to
 * dawn. [DaySky] says which the sky needs, and the app eases from one to the other ([between])
 * as it turns.
 */
@Immutable
data class Ink(
    /** Main text. */
    val deep: Color,
    /** Labels and secondary text. */
    val soft: Color,
    /** The main button and the chosen option. */
    val accent: Color,
    val accentPressed: Color,
    /** Text on [accent]. */
    val onAccent: Color,
    /** The options not chosen. */
    val field: Color,
    val fieldBorder: Color,
    /** The session's round buttons. */
    val glass: Color,
    val glassPressed: Color,
    /** Lines drawn on the sky: the box, its trail, the ripples. */
    val line: Color,
    /** The dot that travels round the box, and its glow. */
    val dot: Color,
    val dotGlow: Color,
    val orb: OrbColors,
    /** Where the sun is, as an angle round the orb ([DaySky.sunAngle]): the side the orb is lit from. The upper left until a look says otherwise. */
    val sun: Float = 2.29f,
) {
    /** Secondary text pulled toward the main colour by 1 - [softness] (see [DayLook.softness]). */
    fun softened(softness: Float): Ink = if (softness >= 1f) this else copy(soft = lerp(deep, soft, softness))

    companion object {
        val OnLight = Ink(
            deep = Color(0xFF0F2A43),
            soft = Color(0xFF2E4A63),
            accent = Color(0xFF0E5A73),
            accentPressed = Color(0xFF0A4559),
            onAccent = Color.White,
            field = Color.White.copy(alpha = 0.55f),
            fieldBorder = Color.White.copy(alpha = 0.85f),
            glass = Color.White.copy(alpha = 0.45f),
            glassPressed = Color.White.copy(alpha = 0.7f),
            line = Color(0xFF0F2A43),
            dot = Color(0xFF0E5A73),
            dotGlow = Color(0xFF7FD6EE),
            orb = OrbColors.Day,
        )

        val OnDark = Ink(
            deep = Color.White,
            soft = Color(0xFFD3DEEC),
            accent = Color.White.copy(alpha = 0.94f),
            accentPressed = Color.White.copy(alpha = 0.78f),
            onAccent = Color(0xFF0F2A43),
            field = Color.White.copy(alpha = 0.12f),
            fieldBorder = Color.White.copy(alpha = 0.35f),
            glass = Color.White.copy(alpha = 0.12f),
            glassPressed = Color.White.copy(alpha = 0.24f),
            line = Color.White,
            dot = Color.White,
            dotGlow = Color(0xFFBDF3FA),
            orb = OrbColors.Night,
        )

        fun between(a: Ink, b: Ink, t: Float): Ink = when {
            t <= 0f -> a
            t >= 1f -> b
            else -> Ink(
                deep = lerp(a.deep, b.deep, t),
                soft = lerp(a.soft, b.soft, t),
                accent = lerp(a.accent, b.accent, t),
                accentPressed = lerp(a.accentPressed, b.accentPressed, t),
                onAccent = lerp(a.onAccent, b.onAccent, t),
                field = lerp(a.field, b.field, t),
                fieldBorder = lerp(a.fieldBorder, b.fieldBorder, t),
                glass = lerp(a.glass, b.glass, t),
                glassPressed = lerp(a.glassPressed, b.glassPressed, t),
                line = lerp(a.line, b.line, t),
                dot = lerp(a.dot, b.dot, t),
                dotGlow = lerp(a.dotGlow, b.dotGlow, t),
                orb = OrbColors.between(a.orb, b.orb, t),
            )
        }
    }
}

val LocalInk = compositionLocalOf { Ink.OnLight }

private fun Modifier.pressable(
    interaction: MutableInteractionSource,
    role: Role,
    onClick: () -> Unit,
): Modifier = clickable(interactionSource = interaction, indication = null, role = role, onClick = onClick)

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val ink = LocalInk.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier
            .scale(if (pressed) 0.98f else 1f)
            .widthIn(max = 380.dp)
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(if (pressed) ink.accentPressed else ink.accent)
            .pressable(interaction, Role.Button, onClick),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text,
            style = TextStyle(
                color = ink.onAccent,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.3.sp,
            ),
        )
    }
}

@Composable
fun OutlineButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val ink = LocalInk.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier
            .widthIn(max = 380.dp)
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(ink.deep.copy(alpha = if (pressed) 0.16f else 0.05f))
            .border(1.dp, ink.deep.copy(alpha = 0.55f), RoundedCornerShape(26.dp))
            .pressable(interaction, Role.Button, onClick),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(text, style = TextStyle(color = ink.deep, fontSize = 17.sp, fontWeight = FontWeight.Medium))
    }
}

/**
 * Session length as one drop showing the current count. Tapping it opens the row: the other
 * counts bud out of it as liquid and pull free to its left and right, nearest first; tapping
 * one picks it, and they all flow back into it (LiquidPicker.kt). The caller folds the row too
 * on a touch anywhere else, for which [onBounds] reports where the row is, and on Back.
 *
 * Open, it can be slid too: pressed and slid sideways, the chosen colour comes away under the
 * finger as a bead of the same liquid, running into each drop it passes, with a [tick] at each.
 * Let go, it carries on to the drop it was heading for, and that one is picked. Past the last
 * drop it holds back. Folded, it only opens: the row opens round its middle, not round the drop
 * that was pressed, so a slide from there would land somewhere the finger never chose.
 */
@Composable
fun CyclePicker(
    choices: List<Int>,
    selected: Int,
    open: Boolean,
    onOpen: () -> Unit,
    onPick: (Int) -> Unit,
    describe: (Int) -> String,
    onBounds: (LayoutCoordinates) -> Unit,
    modifier: Modifier = Modifier,
    tick: () -> Unit = {},
) {
    val ink = LocalInk.current
    val chosen = choices.indexOf(selected).coerceAtLeast(0)
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val openNow by rememberUpdatedState(open)
    val pick by rememberUpdatedState(onPick)
    val tickNow by rememberUpdatedState(tick)
    // The bead: where it is along the row from its middle, held under the finger or on its way
    // to a drop once let go, and how fast it is going; out while either.
    val bead = remember { Animatable(0f, visibilityThreshold = 0.5f) }
    var beadHeld by remember { mutableStateOf<Float?>(null) }
    var beadSpeed by remember { mutableFloatStateOf(0f) }
    var beadOut by remember { mutableStateOf(false) }
    // How far each drop has come out of the chosen one: 0 at home inside it, 1 in its place.
    val spread = remember(choices) { choices.map { Animatable(if (open) 1f else 0f) } }
    // How much of the chosen colour each drop wears.
    val accent = remember(choices) { choices.indices.map { Animatable(if (it == chosen) 1f else 0f) } }
    LaunchedEffect(open, chosen) {
        for (i in choices.indices) {
            launch {
                if (open) {
                    delay(LiquidMotion.STAGGER_MS * abs(i - chosen))
                    spread[i].animateTo(
                        1f,
                        spring(dampingRatio = LiquidMotion.OPEN_DAMPING, stiffness = LiquidMotion.OPEN_STIFFNESS),
                    )
                } else {
                    spread[i].animateTo(0f, spring(dampingRatio = 1f, stiffness = LiquidMotion.CLOSE_STIFFNESS))
                }
            }
            launch { accent[i].animateTo(if (i == chosen) 1f else 0f, tween(LiquidMotion.RECOLOUR_MS)) }
        }
    }
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val gap = 8.dp
        val size = min(48.dp, (maxWidth - gap * (choices.size - 1)) / choices.size)
        val step = size + gap

        // The drops as they are this frame, read where they are drawn, so the motion redraws
        // the row without composing it again.
        fun Density.drops() = LiquidMotion.drops(
            FloatArray(choices.size) { spread[it].value },
            FloatArray(choices.size) { spread[it].velocity },
            FloatArray(choices.size) { accent[it].value },
            chosen,
            open,
            size.toPx(),
            step.toPx(),
        )
        fun beadAt(): Float? = if (beadOut) beadHeld ?: bead.value else null
        // How much of the bead lies over the drop at [x].
        fun Density.under(x: Float): Float {
            val b = beadAt() ?: return 0f
            return LiquidMotion.smoothstep(0f, 1f, 1 - abs(b - x) / size.toPx())
        }
        Box(
            Modifier
                .width(size * choices.size + gap * (choices.size - 1))
                .height(size)
                .onGloballyPositioned(onBounds)
                .pointerInput(choices) {
                    val r = size.toPx() / 2
                    val stepPx = step.toPx()
                    fun slot(i: Int) = stepPx * (i - (choices.size - 1) / 2f)
                    fun nearest(x: Float) = ((x / stepPx) + (choices.size - 1) / 2f).roundToInt().coerceIn(0, choices.size - 1)
                    val first = slot(0)
                    val last = slot(choices.size - 1)
                    fun held(x: Float) = when {
                        x < first -> first + rubberBand(x - first, r)
                        x > last -> last + rubberBand(x - last, r)
                        else -> x
                    }
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        if (!openNow) return@awaitEachGesture
                        val x0 = down.position.x - this.size.width / 2f
                        val start = slot(nearest(x0)) * spread[nearest(x0)].value
                        // Slid far enough to mean it, it stops being a tap on the drop underneath.
                        val slid = awaitHorizontalTouchSlopOrCancellation(down.id) { change, _ -> change.consume() }
                            ?: return@awaitEachGesture
                        scope.launch { bead.stop() }
                        val tracker = VelocityTracker()
                        var over = nearest(start)
                        fun follow(x: Float, at: Long) {
                            val b = held(start + x - down.position.x)
                            beadHeld = b
                            beadOut = true
                            tracker.addPosition(at, Offset(b, 0f))
                            beadSpeed = tracker.calculateVelocity().x
                            if (nearest(b) != over) {
                                over = nearest(b)
                                tickNow()
                            }
                        }
                        follow(slid.position.x, slid.uptimeMillis)
                        horizontalDrag(down.id) { change ->
                            follow(change.position.x, change.uptimeMillis)
                            change.consume()
                        }
                        // Held still before it was let go, it was going nowhere.
                        currentEvent.changes.firstOrNull { it.id == down.id }?.let {
                            tracker.addPosition(it.uptimeMillis, Offset(beadHeld ?: start, 0f))
                        }
                        // Let go, it carries on the way it was going, to the drop it would come
                        // to rest at, and becomes the chosen drop there.
                        val let = beadHeld ?: start
                        val speed = tracker.calculateVelocity().x
                        val target = nearest((let + speed * PROJECTION_S).coerceIn(first, last))
                        scope.launch {
                            bead.snapTo(let)
                            beadHeld = null
                            bead.animateTo(slot(target), BEAD_HOME, speed)
                            for (i in choices.indices) accent[i].snapTo(if (i == target) 1f else 0f)
                            beadOut = false
                            beadSpeed = 0f
                            if (target != over) tickNow()
                            pick(choices[target])
                        }
                    }
                }
                .drawBehind {
                    val b = beadAt()
                    val speed = if (beadHeld != null) beadSpeed else bead.velocity
                    drawLiquid(
                        drops(),
                        chosen,
                        ink,
                        settled = b == null && (spread + accent).none { it.isRunning },
                        bead = b?.let {
                            val stretch = 1f + 0.14f * min(1f, abs(speed) / step.toPx() / 13f)
                            PickerDrop(it, size.toPx() / 2, stretch, BEAD_REACH * size.toPx(), 1f, 0f)
                        },
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            for (i in choices.indices) {
                key(choices[i]) {
                    val current = i == chosen
                    val slot = step * (i - (choices.size - 1) / 2f)
                    val interaction = remember { MutableInteractionSource() }
                    val touch = when {
                        open -> Modifier
                            .pressable(interaction, Role.RadioButton) { onPick(choices[i]) }
                            .semantics {
                                this.selected = current
                                contentDescription = describe(choices[i])
                            }
                        current -> Modifier
                            .pressable(interaction, Role.Button, onOpen)
                            .semantics { contentDescription = "Session length: ${describe(choices[i])}. Tap to change." }
                        else -> Modifier.clearAndSetSemantics { }
                    }
                    Box(
                        Modifier
                            .offset { IntOffset((slot.toPx() * spread[i].value).roundToInt(), 0) }
                            .size(size)
                            .then(touch),
                        contentAlignment = Alignment.Center,
                    ) {
                        // Half under the bead, a count fades out, and comes back light on it or dark off it.
                        fun under() = if (beadOut) with(density) { under(slot.toPx() * spread[i].value) } else null
                        BasicText(
                            choices[i].toString(),
                            modifier = Modifier.graphicsLayer {
                                alpha = drops()[i].label * (under()?.let { abs(2 * it - 1) } ?: 1f)
                            },
                            style = TextStyle(
                                fontSize = 17.sp,
                                fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal,
                                textAlign = TextAlign.Center,
                            ),
                            color = {
                                val on = under()?.let { if (it < 0.5f) 0f else 1f } ?: accent[i].value
                                lerp(ink.deep, ink.onAccent, on)
                            },
                        )
                    }
                }
            }
        }
    }
}

/** Let go, how far ahead of the bead the drop it carries on to is looked for: as far as it would go in this long. */
private const val PROJECTION_S = 0.1f

/** The bead on its way to a drop: quickly, with the least bounce, as it was thrown. */
private val BEAD_HOME = spring(dampingRatio = 0.8f, stiffness = 600f, visibilityThreshold = 0.5f)

/** How far the bead runs into the drops it passes, as a share of a drop's size. */
private const val BEAD_REACH = 0.4f

/**
 * The drops: all of them as one shape of liquid in the unchosen colours, run together wherever
 * they meet, with a rim inside its edge like a border, and the chosen one solid on top. While
 * the chosen colour is out as a [bead], it is part of the liquid too, solid on top in its place.
 */
private fun DrawScope.drawLiquid(drops: List<PickerDrop>, chosen: Int, ink: Ink, settled: Boolean, bead: PickerDrop? = null) {
    val rim = 1.dp.toPx()
    translate(center.x, center.y) {
        if (settled) {
            // At rest the drops are plain circles, with no need to trace them.
            for (d in drops) {
                if (d.radius <= 0.05f) continue
                drawCircle(ink.field, d.radius, Offset(d.x, 0f))
                drawCircle(ink.fieldBorder, d.radius - rim / 2, Offset(d.x, 0f), style = Stroke(rim))
            }
        } else {
            val outline = Path().apply { fillType = PathFillType.EvenOdd }
            val row = LiquidMotion.order(drops.size, chosen).map { drops[it].liquid } + listOfNotNull(bead?.liquid)
            for (loop in LiquidOutline.loops(row, inset = rim / 2, cell = 2.dp.toPx())) {
                outline.moveTo(loop[0], loop[1])
                for (n in 2 until loop.size step 2) outline.lineTo(loop[n], loop[n + 1])
                outline.close()
            }
            drawPath(outline, ink.field)
            drawPath(outline, ink.fieldBorder, style = Stroke(rim))
        }
        for (d in if (bead != null) listOf(bead) else drops) {
            if (d.accent <= 0f || d.radius <= 0.05f) continue
            drawOval(
                ink.accent.copy(alpha = ink.accent.alpha * d.accent),
                topLeft = Offset(d.x - d.radius * d.stretch, -d.radius / d.stretch),
                size = Size(2 * d.radius * d.stretch, 2 * d.radius / d.stretch),
            )
        }
    }
}

/** A round, see-through button for the session's top bar, with an icon drawn in place. */
@Composable
fun RoundIconButton(
    description: String,
    onClick: () -> Unit,
    size: Dp = 44.dp,
    icon: DrawScope.(Color) -> Unit,
) {
    val ink = LocalInk.current
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .background(if (pressed) ink.glassPressed else ink.glass)
            .pressable(interaction, Role.Button, onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(22.dp)) { icon(ink.deep) }
    }
}

/**
 * The ✕ that ends a session. With [hold], it ends it when held for [HOLD_MS]: pressed, it opens
 * (the caller hears [onHolding]) and fills from the left at an even pace, as time passing does;
 * let go too soon, the fill drains away quickly, and once full, [onHeld] ends the session. A tap
 * only opens it. Without [hold], for TalkBack, a tap does [onTap], and the caller opens it on the
 * first and ends the session on the second; accessibility services that act rather than touch
 * do the same with a hold. [open] says whether it shows [label].
 */
@Composable
fun EndSessionButton(
    open: Boolean,
    label: String,
    hold: Boolean,
    onTap: () -> Unit,
    onHolding: (Boolean) -> Unit,
    onHeld: () -> Unit,
) {
    val ink = LocalInk.current
    val interaction = remember { MutableInteractionSource() }
    val tapped by interaction.collectIsPressedAsState()
    var held by remember { mutableStateOf(false) }
    val fill = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    val holdingNow by rememberUpdatedState(onHolding)
    val heldNow by rememberUpdatedState(onHeld)
    val touch = if (hold) {
        Modifier
            .pointerInput(Unit) {
                awaitEachGesture {
                    awaitFirstDown().consume()
                    held = true
                    holdingNow(true)
                    val filling = scope.launch {
                        fill.animateTo(1f, tween(((1 - fill.value) * HOLD_MS).roundToInt(), easing = LinearEasing))
                        heldNow()
                    }
                    // Up, or slid off it.
                    waitForUpOrCancellation()?.consume()
                    held = false
                    holdingNow(false)
                    if (filling.isActive) {
                        filling.cancel()
                        scope.launch { fill.animateTo(0f, tween(DRAIN_MS, easing = LinearOutSlowInEasing)) }
                    }
                }
            }
            .semantics {
                role = Role.Button
                onClick { onTap(); true }
            }
    } else {
        Modifier.pressable(interaction, Role.Button, onTap)
    }
    Row(
        Modifier
            .height(44.dp)
            .clip(CircleShape)
            .background(if (held || tapped) ink.glassPressed else ink.glass)
            .drawBehind {
                if (fill.value > 0f) drawRect(ink.deep.copy(alpha = 0.2f), size = size.copy(width = size.width * fill.value))
            }
            .then(touch)
            .semantics {
                contentDescription = when {
                    !open -> "End session"
                    hold -> "Hold to end the session"
                    else -> "Tap again to end the session"
                }
            }
            .animateContentSize(tween(220))
            .padding(horizontal = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Canvas(Modifier.size(22.dp)) { Icons.close(this, ink.deep) }
        if (open) {
            BasicText(
                label,
                Modifier.padding(start = 6.dp, end = 5.dp),
                style = TextStyle(color = ink.deep, fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
            )
        }
    }
}

/** How long the ✕ is held to end a session, and how quickly its fill drains if let go. */
const val HOLD_MS = 1_000
private const val DRAIN_MS = 200

/** Line icons on a 24-unit grid. */
object Icons {
    private fun DrawScope.u(): Float = size.minDimension / 24f

    private fun DrawScope.line(color: Color, vararg pts: Float) {
        val k = u()
        val p = Path()
        p.moveTo(pts[0] * k, pts[1] * k)
        var i = 2
        while (i < pts.size) {
            p.lineTo(pts[i] * k, pts[i + 1] * k)
            i += 2
        }
        drawPath(p, color, style = Stroke(width = 2f * k, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }

    private fun DrawScope.speaker(color: Color) {
        val k = u()
        val p = Path().apply {
            moveTo(3f * k, 9f * k)
            lineTo(7f * k, 9f * k)
            lineTo(12f * k, 4.5f * k)
            lineTo(12f * k, 19.5f * k)
            lineTo(7f * k, 15f * k)
            lineTo(3f * k, 15f * k)
            close()
        }
        drawPath(p, color, style = Stroke(width = 2f * k, join = StrokeJoin.Round))
    }

    fun pause(scope: DrawScope, color: Color) = with(scope) {
        line(color, 9f, 6f, 9f, 18f)
        line(color, 15f, 6f, 15f, 18f)
    }

    fun play(scope: DrawScope, color: Color) = with(scope) {
        val k = u()
        val p = Path().apply {
            moveTo(8.5f * k, 5.5f * k)
            lineTo(18.5f * k, 12f * k)
            lineTo(8.5f * k, 18.5f * k)
            close()
        }
        drawPath(p, color, style = Stroke(width = 2f * k, join = StrokeJoin.Round))
    }

    fun close(scope: DrawScope, color: Color) = with(scope) {
        line(color, 6f, 6f, 18f, 18f)
        line(color, 18f, 6f, 6f, 18f)
    }

    /**
     * The volume button: a speaker with one, two or three waves for how loud [level] (0 to 1)
     * is, as the Mac's menu bar shows it, and crossed out at nothing.
     */
    fun volume(scope: DrawScope, color: Color, level: Float) = with(scope) {
        if (level < 0.01f) return silent(this, color)
        speaker(color)
        val k = u()
        val waves = when {
            level < 0.34f -> 1
            level < 0.67f -> 2
            else -> 3
        }
        for (i in 1..waves) {
            val r = 3f * i
            drawArc(
                color, -45f, 90f, false,
                Offset((12.5f - r) * k, (12f - r) * k),
                androidx.compose.ui.geometry.Size(2 * r * k, 2 * r * k),
                style = Stroke(2f * k, cap = StrokeCap.Round),
            )
        }
    }

    /** The quiet end of the volume slider: a speaker with no waves. */
    fun quiet(scope: DrawScope, color: Color) = with(scope) { speaker(color) }

    fun silent(scope: DrawScope, color: Color) = with(scope) {
        speaker(color)
        line(color, 15.5f, 9.5f, 20.5f, 14.5f)
        line(color, 20.5f, 9.5f, 15.5f, 14.5f)
    }
}
