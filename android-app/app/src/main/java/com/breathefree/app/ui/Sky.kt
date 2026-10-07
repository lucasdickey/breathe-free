package com.breathefree.app.ui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.RadialGradientShader
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.lerp
import kotlin.math.PI
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** Colours for one moment of the sky ([DaySky] picks them from the clock). */
@Immutable
data class SkyPalette(
    val top: Color,
    val mid: Color,
    val bottom: Color,
    val cloud: Color,
    val cloudAlpha: Float,
    /** How bright the stars are: 0 by day, 1 at night. */
    val stars: Float = 0f,
) {
    fun mix(other: SkyPalette, t: Float) = SkyPalette(
        top = lerp(top, other.top, t),
        mid = lerp(mid, other.mid, t),
        bottom = lerp(bottom, other.bottom, t),
        cloud = lerp(cloud, other.cloud, t),
        cloudAlpha = cloudAlpha + (other.cloudAlpha - cloudAlpha) * t,
        stars = stars + (other.stars - stars) * t,
    )

    /** The sky's colour [y] of the way down the screen, blended as the gradient draws it. */
    fun at(y: Float): Color =
        if (y <= 0.5f) blend(top, mid, y / 0.5f) else blend(mid, bottom, (y - 0.5f) / 0.5f)

    private fun blend(a: Color, b: Color, t: Float) =
        Color(a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t, a.blue + (b.blue - a.blue) * t)
}

/**
 * The sky's gradient. It holds steady through the breath so the clouds drift on unchanged: a sky
 * that lightened with each breath in washed them out, and their coming back on the breath out
 * looked like them starting over every cycle.
 */
fun DrawScope.drawSky(p: SkyPalette) {
    drawRect(Brush.verticalGradient(listOf(p.top, p.mid, p.bottom)))
}

/**
 * A fixed scatter of stars, more of them high up, twinkling slowly. [amount] (the palette's
 * stars) fades them in through dusk and out at dawn.
 */
class StarField(seed: Int = 7031, count: Int = 90) {
    private val x = FloatArray(count)
    private val y = FloatArray(count)
    private val radius = FloatArray(count)
    private val brightness = FloatArray(count)
    private val speed = FloatArray(count)
    private val phase = FloatArray(count)

    init {
        val rand = Mulberry32(seed)
        for (i in 0 until count) {
            x[i] = rand.next().toFloat()
            y[i] = (rand.next().pow(1.4) * 0.75).toFloat()
            radius[i] = (0.45 + rand.next().pow(3.0) * 1.1).toFloat() // mostly faint, a few bright
            brightness[i] = (0.35 + rand.next() * 0.6).toFloat()
            speed[i] = (0.4 + rand.next() * 1.2).toFloat()
            phase[i] = (rand.next() * 2 * PI).toFloat()
        }
    }

    fun draw(scope: DrawScope, timeSeconds: Double, amount: Float) = with(scope) {
        if (amount <= 0.01f) return@with
        for (i in x.indices) {
            val twinkle = 0.7f + 0.3f * sin(timeSeconds * speed[i] + phase[i]).toFloat()
            drawCircle(
                Color.White,
                radius = radius[i] * density,
                center = Offset(x[i] * size.width, y[i] * size.height),
                alpha = (amount * brightness[i] * twinkle).coerceIn(0f, 1f),
            )
        }
    }
}

/** A soft round puff, drawn once and stamped many times to build the clouds. */
fun makePuffSprite(size: Int = 128): ImageBitmap {
    val bitmap = ImageBitmap(size, size)
    val canvas = Canvas(bitmap)
    val c = size / 2f
    val paint = Paint().apply {
        shader = RadialGradientShader(
            center = Offset(c, c),
            radius = c,
            colors = listOf(
                Color.White, Color.White.copy(alpha = 0.9f), Color.White.copy(alpha = 0.55f),
                Color.White.copy(alpha = 0.2f), Color.White.copy(alpha = 0f),
            ),
            colorStops = listOf(0f, 0.3f, 0.55f, 0.78f, 1f),
        )
    }
    canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)
    return bitmap
}

/**
 * Procedural clouds. Each is a cluster of soft puffs whose offsets and sizes sway on slow,
 * unrelated sine waves, so the clouds gently change shape while they drift, nearer ones
 * faster. Positions are worked out from the time alone (no per-frame state), so the sky is
 * the same however irregularly frames arrive.
 */
class CloudField(seed: Int = 20240607, private val count: Int = 9) {
    private class Puff(
        val dx: Float, val dy: Float, val r: Float, val alpha: Float,
        val ax1: Float, val wx1: Float, val px1: Float,
        val ax2: Float, val wx2: Float, val px2: Float,
        val ay1: Float, val wy1: Float, val py1: Float,
        val ar1: Float, val wr1: Float, val pr1: Float,
        val ar2: Float, val wr2: Float, val pr2: Float,
    )

    private class Cloud(
        val id: Int, val x0: Double, val depth: Float, val speed: Double, val opacity: Float,
        val bobAmp: Float, val bobFreq: Float, val bobPhase: Float, val puffs: List<Puff>,
    )

    private val clouds: List<Cloud>

    init {
        val rand = Mulberry32(seed)
        clouds = (0 until count).map { i ->
            // Spread the starting points so the sky never starts empty or bunched up.
            val x0 = -MARGIN + ((i + rand.next() * 0.8) / count) * (1 + 2 * MARGIN)
            makeCloud(i, rand, x0)
        }.sortedBy { it.depth } // far clouds first, so near ones layer over them
    }

    fun draw(scope: DrawScope, timeSeconds: Double, palette: SkyPalette, sprite: ImageBitmap) = with(scope) {
        val w = size.width
        val h = size.height
        val filter = ColorFilter.tint(palette.cloud, BlendMode.Modulate)
        val sizeBase = min(max(w, 480f * density), 1600f * density)
        val span = 1 + 2 * MARGIN
        val t = timeSeconds
        val spriteSize = sprite.width.toFloat()
        for (c in clouds) {
            val travelled = c.x0 + MARGIN + c.speed * t
            val laps = floor(travelled / span)
            val xFrac = travelled - laps * span - MARGIN
            // Each time a cloud comes round again it enters at a new height.
            val yFrac = 0.06 + 0.74 * hash01(c.id, laps.toInt())
            val cloudSize = sizeBase * (0.09f + c.depth * 0.13f)
            val cx = (xFrac * w).toFloat()
            val cy = (yFrac * h).toFloat() + (sin(t * c.bobFreq * 2 * PI + c.bobPhase) * c.bobAmp * cloudSize).toFloat()
            for (p in c.puffs) {
                val px = cx + (p.dx + p.ax1 * sin(t * p.wx1 + p.px1) + p.ax2 * sin(t * p.wx2 + p.px2)).toFloat() * cloudSize
                val py = cy + (p.dy + p.ay1 * sin(t * p.wy1 + p.py1)).toFloat() * cloudSize
                val pr = (p.r * (1 + p.ar1 * sin(t * p.wr1 + p.pr1) + p.ar2 * sin(t * p.wr2 + p.pr2))).toFloat() * cloudSize
                val alpha = (c.opacity * p.alpha * palette.cloudAlpha).coerceIn(0f, 1f)
                if (alpha <= 0.003f) continue
                withTransform({
                    translate(px - pr, py - pr)
                    scale(2 * pr / spriteSize, 2 * pr / spriteSize, pivot = Offset.Zero)
                }) {
                    drawImage(sprite, alpha = alpha, colorFilter = filter)
                }
            }
        }
    }

    private fun makePuff(rand: Mulberry32, spreadX: Double): Puff = Puff(
        dx = ((rand.next() * 2 - 1) * spreadX).toFloat(),
        dy = ((rand.next() * 2 - 1) * 0.16).toFloat(),
        r = (0.22 + rand.next() * 0.2).toFloat(),
        alpha = (0.55 + rand.next() * 0.45).toFloat(),
        ax1 = (0.015 + rand.next() * 0.03).toFloat(), wx1 = (0.15 + rand.next() * 0.25).toFloat(), px1 = (rand.next() * 2 * PI).toFloat(),
        ax2 = (0.008 + rand.next() * 0.015).toFloat(), wx2 = (0.4 + rand.next() * 0.35).toFloat(), px2 = (rand.next() * 2 * PI).toFloat(),
        ay1 = (0.012 + rand.next() * 0.025).toFloat(), wy1 = (0.12 + rand.next() * 0.22).toFloat(), py1 = (rand.next() * 2 * PI).toFloat(),
        ar1 = (0.04 + rand.next() * 0.05).toFloat(), wr1 = (0.1 + rand.next() * 0.18).toFloat(), pr1 = (rand.next() * 2 * PI).toFloat(),
        ar2 = (0.02 + rand.next() * 0.03).toFloat(), wr2 = (0.3 + rand.next() * 0.3).toFloat(), pr2 = (rand.next() * 2 * PI).toFloat(),
    )

    private fun makeCloud(id: Int, rand: Mulberry32, x0: Double): Cloud {
        val depth = rand.next()
        val puffCount = 6 + (rand.next() * 4).toInt()
        val puffs = ArrayList<Puff>(puffCount + 1)
        repeat(puffCount) { puffs.add(makePuff(rand, 0.55)) }
        // A flatter, fuller puff along the bottom gives each cloud a level base.
        val base = makePuff(rand, 0.35)
        puffs.add(
            Puff(
                base.dx, 0.16f, 0.34f, 0.8f, base.ax1, base.wx1, base.px1, base.ax2, base.wx2, base.px2,
                base.ay1, base.wy1, base.py1, base.ar1, base.wr1, base.pr1, base.ar2, base.wr2, base.pr2,
            ),
        )
        return Cloud(
            id = id,
            x0 = x0,
            depth = depth.toFloat(),
            // Nearer clouds drift faster: roughly 45 to 110 seconds to cross the screen.
            speed = (0.009 + depth * 0.013) * (if (rand.next() < 0.5) 1.0 else 1.15),
            opacity = (0.3 + depth * 0.45).toFloat(),
            bobAmp = (0.02 + rand.next() * 0.03).toFloat(),
            bobFreq = (0.03 + rand.next() * 0.05).toFloat(),
            bobPhase = (rand.next() * 2 * PI).toFloat(),
            puffs = puffs,
        )
    }

    private companion object {
        const val MARGIN = 0.22 // clouds enter and leave fully formed

        fun hash01(a: Int, b: Int): Double {
            var x = a * 0x27d4eb2d xor (b * 0x165667b1) xor 0x5bd1e995
            x = x xor (x ushr 15)
            x *= 0x2c1b3c6d
            x = x xor (x ushr 12)
            x *= 0x297a2d39
            x = x xor (x ushr 15)
            return (x.toLong() and 0xffffffffL) / 4294967296.0
        }
    }
}

/** The small seeded generator the web version uses, so every platform draws the same sky. */
class Mulberry32(seed: Int) {
    private var a = seed

    fun next(): Double {
        a += 0x6D2B79F5
        var t = (a xor (a ushr 15)) * (1 or a)
        t = (t + ((t xor (t ushr 7)) * (61 or t))) xor t
        return ((t xor (t ushr 14)).toLong() and 0xffffffffL) / 4294967296.0
    }
}
