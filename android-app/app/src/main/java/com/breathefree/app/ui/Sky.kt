package com.breathefree.app.ui

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
import kotlin.math.sin

/** Colours for one mood of the sky. "Lift" colours are where it brightens to on a full breath. */
class SkyPalette(
    val top: Color,
    val mid: Color,
    val bottom: Color,
    val liftTop: Color = top,
    val liftMid: Color = mid,
    val liftBottom: Color = bottom,
    val cloud: Color,
    val cloudAlpha: Float,
) {
    fun mix(other: SkyPalette, t: Float) = SkyPalette(
        top = lerp(top, other.top, t),
        mid = lerp(mid, other.mid, t),
        bottom = lerp(bottom, other.bottom, t),
        liftTop = lerp(liftTop, other.liftTop, t),
        liftMid = lerp(liftMid, other.liftMid, t),
        liftBottom = lerp(liftBottom, other.liftBottom, t),
        cloud = lerp(cloud, other.cloud, t),
        cloudAlpha = cloudAlpha + (other.cloudAlpha - cloudAlpha) * t,
    )

    companion object {
        /** Home: a clear daytime sky. */
        val Day = SkyPalette(
            top = Color(0xFF9FCFF2), mid = Color(0xFFCBE6F8), bottom = Color(0xFFEEF7FD),
            cloud = Color.White, cloudAlpha = 0.85f,
        )

        /** During a session: dusk, brightening a little as the lungs fill. */
        val Dusk = SkyPalette(
            top = Color(0xFF081A33), mid = Color(0xFF12375C), bottom = Color(0xFF23607F),
            liftTop = Color(0xFF0E2A52), liftMid = Color(0xFF1C4F7E), liftBottom = Color(0xFF317C9B),
            cloud = Color(0xFFAFC3E0), cloudAlpha = 0.30f,
        )

        /** Finished: first light. */
        val Dawn = SkyPalette(
            top = Color(0xFF1D3B66), mid = Color(0xFF5F86B5), bottom = Color(0xFFF0C9A9),
            cloud = Color(0xFFFFE8DA), cloudAlpha = 0.55f,
        )
    }
}

/** Eases the sky from one palette to another over [seconds], restarting cleanly if retargeted mid-way. */
class PaletteTransition(initial: SkyPalette, private val seconds: Double = 1.8) {
    private var from = initial
    private var to = initial
    private var startNanos = 0L

    fun retarget(target: SkyPalette, nowNanos: Long) {
        if (target === to) return
        from = at(nowNanos)
        to = target
        startNanos = nowNanos
    }

    fun at(nowNanos: Long): SkyPalette {
        if (from === to) return to
        val x = ((nowNanos - startNanos) / 1e9 / seconds).coerceIn(0.0, 1.0).toFloat()
        if (x >= 1f) {
            from = to
            return to
        }
        return from.mix(to, x * x * (3f - 2f * x))
    }
}

fun DrawScope.drawSky(p: SkyPalette, level: Float) {
    val lift = level * 0.65f
    drawRect(
        Brush.verticalGradient(
            listOf(lerp(p.top, p.liftTop, lift), lerp(p.mid, p.liftMid, lift), lerp(p.bottom, p.liftBottom, lift)),
        ),
    )
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
