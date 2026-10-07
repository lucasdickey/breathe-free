package com.breathefree.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object Ink {
    val Deep = Color(0xFF0F2A43)
    val Soft = Color(0xFF3D5A73)
    val Accent = Color(0xFF0E5A73)
    val AccentPressed = Color(0xFF0A4559)
}

private fun Modifier.pressable(
    interaction: MutableInteractionSource,
    role: Role,
    onClick: () -> Unit,
): Modifier = clickable(interactionSource = interaction, indication = null, role = role, onClick = onClick)

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, light: Boolean = false) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val background = when {
        light -> Color.White.copy(alpha = if (pressed) 0.8f else 0.95f)
        pressed -> Ink.AccentPressed
        else -> Ink.Accent
    }
    Box(
        modifier
            .scale(if (pressed) 0.98f else 1f)
            .widthIn(max = 380.dp)
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(background)
            .pressable(interaction, Role.Button, onClick),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text,
            style = TextStyle(
                color = if (light) Ink.Deep else Color.White,
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.3.sp,
            ),
        )
    }
}

@Composable
fun OutlineButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        modifier
            .widthIn(max = 380.dp)
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(Color.White.copy(alpha = if (pressed) 0.18f else 0.06f))
            .border(1.dp, Color.White.copy(alpha = 0.6f), RoundedCornerShape(26.dp))
            .pressable(interaction, Role.Button, onClick),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(text, style = TextStyle(color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Medium))
    }
}

@Composable
fun Chip(text: String, selected: Boolean, onClick: () -> Unit, description: String) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .defaultMinSize(minWidth = 46.dp)
            .height(44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(if (selected) Ink.Accent else Color.White.copy(alpha = 0.55f))
            .border(1.dp, if (selected) Ink.Accent else Color.White.copy(alpha = 0.85f), RoundedCornerShape(22.dp))
            .pressable(interaction, Role.RadioButton, onClick)
            .semantics {
                this.selected = selected
                contentDescription = description
            }
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        BasicText(
            text,
            style = TextStyle(
                color = if (selected) Color.White else Ink.Deep,
                fontSize = 17.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .widthIn(max = 380.dp)
            .fillMaxWidth()
            .height(44.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(Color.White.copy(alpha = 0.45f))
            .border(1.dp, Color.White.copy(alpha = 0.85f), RoundedCornerShape(22.dp))
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
                    .background(if (on) Ink.Accent else Color.Transparent)
                    .pressable(interaction, Role.RadioButton) { onSelect(i) }
                    .semantics { this.selected = on },
                contentAlignment = Alignment.Center,
            ) {
                BasicText(
                    label,
                    style = TextStyle(
                        color = if (on) Color.White else Ink.Deep,
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
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = if (pressed) 0.24f else 0.12f))
            .pressable(interaction, Role.Button, onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(22.dp)) { icon(Color.White) }
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
