package com.breathefree.app.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

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
 * Session length as one circle showing the current count. Tapping it fans the other counts
 * out to its left and right, nearest first; tapping one picks it, and they fold back into it.
 * The caller folds it too on a touch anywhere else, for which [onBounds] reports where the row
 * of circles is, and on Back.
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
) {
    val chosen = choices.indexOf(selected).coerceAtLeast(0)
    // How far each circle has come out from the current one: 0 folded, 1 in its place.
    val spread = remember(choices) { choices.map { Animatable(0f) } }
    LaunchedEffect(open, chosen) {
        for (i in choices.indices) {
            launch {
                if (open) {
                    delay(FAN_STAGGER_MS * abs(i - chosen))
                    spread[i].animateTo(1f, spring(dampingRatio = 0.68f, stiffness = 420f))
                } else {
                    spread[i].animateTo(0f, spring(dampingRatio = 1f, stiffness = 700f))
                }
            }
        }
    }
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val gap = 8.dp
        val size = min(48.dp, (maxWidth - gap * (choices.size - 1)) / choices.size)
        val step = size + gap
        Box(
            Modifier
                .width(size * choices.size + gap * (choices.size - 1))
                .height(size)
                .onGloballyPositioned(onBounds),
            contentAlignment = Alignment.Center,
        ) {
            // The others are drawn first, so the current count stays on top as they come out
            // from behind it.
            for (i in choices.indices.sortedBy { it == chosen }) {
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
                    CountCircle(
                        text = choices[i].toString(),
                        selected = current,
                        size = size,
                        modifier = Modifier
                            .offset { IntOffset((slot.toPx() * spread[i].value).roundToInt(), 0) }
                            .graphicsLayer {
                                if (!current) {
                                    val s = spread[i].value
                                    alpha = s.coerceIn(0f, 1f)
                                    scaleX = 0.55f + 0.45f * s
                                    scaleY = 0.55f + 0.45f * s
                                }
                            }
                            .then(touch),
                    )
                }
            }
        }
    }
}

private const val FAN_STAGGER_MS = 28L

@Composable
private fun CountCircle(text: String, selected: Boolean, size: Dp, modifier: Modifier) {
    val ink = LocalInk.current
    Box(
        modifier
            .size(size)
            .clip(CircleShape)
            .background(if (selected) ink.accent else ink.field)
            .border(1.dp, if (selected) ink.accent else ink.fieldBorder, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text,
            style = TextStyle(
                color = if (selected) ink.onAccent else ink.deep,
                fontSize = 17.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val ink = LocalInk.current
    Row(
        modifier
            .widthIn(max = 380.dp)
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(ink.field)
            .border(1.dp, ink.fieldBorder, RoundedCornerShape(22.dp))
            .padding(3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            val interaction = remember { MutableInteractionSource() }
            Box(
                Modifier
                    .weight(1f)
                    .height(38.dp)
                    .clip(RoundedCornerShape(19.dp))
                    .background(if (on) ink.accent else Color.Transparent)
                    .pressable(interaction, Role.RadioButton) { onSelect(i) }
                    .semantics { this.selected = on },
                contentAlignment = Alignment.Center,
            ) {
                BasicText(
                    label,
                    style = TextStyle(
                        color = if (on) ink.onAccent else ink.deep,
                        fontSize = 15.sp,
                        fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal,
                    ),
                )
            }
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

    fun close(scope: DrawScope, color: Color) = with(scope) {
        line(color, 6f, 6f, 18f, 18f)
        line(color, 18f, 6f, 6f, 18f)
    }

    fun ambient(scope: DrawScope, color: Color) = with(scope) {
        speaker(color)
        val k = u()
        drawArc(color, -50f, 100f, false, Offset(10f * k, 8f * k), androidx.compose.ui.geometry.Size(6f * k, 8f * k), style = Stroke(2f * k, cap = StrokeCap.Round))
        drawArc(color, -50f, 100f, false, Offset(10f * k, 4.5f * k), androidx.compose.ui.geometry.Size(11f * k, 15f * k), style = Stroke(2f * k, cap = StrokeCap.Round))
    }

    fun bells(scope: DrawScope, color: Color) = with(scope) {
        val k = u()
        val p = Path().apply {
            moveTo(6f * k, 17f * k)
            cubicTo(7.5f * k, 15f * k, 7f * k, 13f * k, 7f * k, 10.5f * k)
            cubicTo(7f * k, 7.5f * k, 9.2f * k, 5f * k, 12f * k, 5f * k)
            cubicTo(14.8f * k, 5f * k, 17f * k, 7.5f * k, 17f * k, 10.5f * k)
            cubicTo(17f * k, 13f * k, 16.5f * k, 15f * k, 18f * k, 17f * k)
            close()
        }
        drawPath(p, color, style = Stroke(width = 2f * k, join = StrokeJoin.Round))
        line(color, 10f, 20f, 14f, 20f)
    }

    fun silent(scope: DrawScope, color: Color) = with(scope) {
        speaker(color)
        line(color, 15.5f, 9.5f, 20.5f, 14.5f)
        line(color, 20.5f, 9.5f, 15.5f, 14.5f)
    }
}
