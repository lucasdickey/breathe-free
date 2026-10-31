package com.breathefree.app.ui

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * Session length as liquid. When the picker opens, the other counts bud out of the chosen one
 * and pull free as drops; when one is picked, they all flow back into it. Drops run into one
 * another wherever they come close, as far as each drop's reach, and the reach eases to nothing
 * as a drop settles, so at rest they are plain circles. The settings fan (SettingsFan.kt) is
 * the same liquid, its drops going out on a slant (LiquidFan). Kept in step with the Mac app's
 * LiquidPicker.swift and the browser version's liquid.ts.
 */

/** One drop of liquid. A row's drops sit on its line, which is the default. */
data class LiquidDrop(
    /** Its centre along the row. */
    val x: Float,
    val radius: Float,
    /** How far it is drawn out along the way it moves; 1 is round. */
    val stretch: Float = 1f,
    /** How far it runs into the drops before it. */
    val reach: Float = 0f,
    /** Its centre below the row's line (0 on it). */
    val y: Float = 0f,
    /** The way it moves, in radians clockwise from along the row (0, the default). */
    val angle: Float = 0f,
) {
    /** Distance from its edge, negative inside: exact when round, close when stretched. */
    fun distance(px: Float, py: Float): Float = Shape(this).distance(px, py)
}

/** A drop ready to measure from: its centre, its half-lengths and the way it is drawn out. */
private class Shape(d: LiquidDrop) {
    val x = d.x
    val y = d.y
    val a = d.radius * d.stretch
    val b = d.radius / d.stretch
    val cos = cos(d.angle)
    val sin = sin(d.angle)
    val reach = d.reach

    fun distance(px: Float, py: Float): Float {
        val ox = px - x
        val oy = py - y
        // Along the way it moves, and across it.
        val dx = (ox * cos + oy * sin) / a
        val dy = (oy * cos - ox * sin) / b
        return (sqrt(dx * dx + dy * dy) - 1f) * b
    }
}

/** The outline of a row of drops that run into one another, so the row can be drawn as one shape. */
object LiquidOutline {
    /**
     * The outline round [drops], [inset] inside their edge, as closed loops of points (x and y
     * in turn). Each drop runs into those before it wherever they come within its reach (a
     * smooth minimum of their distances), so the drop the others leave and return to goes
     * first. Traced with marching squares over squares of side [cell].
     */
    fun loops(drops: List<LiquidDrop>, inset: Float = 0f, cell: Float = 1.5f): List<FloatArray> {
        val live = drops.filter { it.radius > 0.05f }
        if (live.isEmpty() || cell <= 0f) return emptyList()
        // The squares cover each drop as far as its reach along the way it moves, and a
        // quarter of that across it.
        var x0 = Float.MAX_VALUE
        var x1 = -Float.MAX_VALUE
        var y0 = Float.MAX_VALUE
        var y1 = -Float.MAX_VALUE
        for (d in live) {
            val along = d.radius * d.stretch + d.reach
            val across = d.radius + d.reach / 4
            val c = abs(cos(d.angle))
            val s = abs(sin(d.angle))
            val halfX = c * along + s * across
            val halfY = s * along + c * across
            x0 = min(x0, d.x - halfX)
            x1 = max(x1, d.x + halfX)
            y0 = min(y0, d.y - halfY)
            y1 = max(y1, d.y + halfY)
        }
        x0 -= 2 * cell
        x1 += 2 * cell
        y0 -= 2 * cell
        y1 += 2 * cell
        val nx = ceil((x1 - x0) / cell).toInt() + 1
        val ny = ceil((y1 - y0) / cell).toInt() + 1
        val shapes = live.map(::Shape)
        val v = FloatArray(nx * ny)
        for (j in 0 until ny) {
            val y = y0 + j * cell
            for (i in 0 until nx) v[j * nx + i] = fieldOf(shapes, x0 + i * cell, y) + inset
        }

        // Marching squares, inside where v < 0. A crossing is named by its grid edge: twice the
        // index of the point the edge starts from, plus one if it goes down rather than right.
        // Each crossing is linked to the two crossings it joins.
        val links = IntArray(4 * nx * ny) { -1 }
        fun join(a: Int, b: Int) {
            links[2 * a + if (links[2 * a] < 0) 0 else 1] = b
            links[2 * b + if (links[2 * b] < 0) 0 else 1] = a
        }
        for (j in 0 until ny - 1) {
            for (i in 0 until nx - 1) {
                val k = j * nx + i
                val tl = v[k]
                val tr = v[k + 1]
                val br = v[k + nx + 1]
                val bl = v[k + nx]
                val corners = (if (tl < 0) 1 else 0) or (if (tr < 0) 2 else 0) or
                    (if (br < 0) 4 else 0) or (if (bl < 0) 8 else 0)
                val top = 2 * k
                val bottom = 2 * (k + nx)
                val left = 2 * k + 1
                val right = 2 * (k + 1) + 1
                when (corners) {
                    1, 14 -> join(left, top)
                    2, 13 -> join(top, right)
                    3, 12 -> join(left, right)
                    4, 11 -> join(right, bottom)
                    6, 9 -> join(top, bottom)
                    7, 8 -> join(left, bottom)
                    5, 10 ->
                        // Opposite corners inside: joined through the middle if the middle is inside.
                        if ((corners == 5) == ((tl + tr + br + bl) / 4 < 0)) {
                            join(top, right)
                            join(bottom, left)
                        } else {
                            join(left, top)
                            join(right, bottom)
                        }
                }
            }
        }

        val loops = ArrayList<FloatArray>()
        val seen = BooleanArray(2 * nx * ny)
        val points = FloatArray(4 * nx * ny)
        for (start in 0 until 2 * nx * ny) {
            if (links[2 * start] < 0 || seen[start]) continue
            var n = 0
            var previous = -1
            var current = start
            while (!seen[current]) {
                seen[current] = true
                val k = current / 2
                val a = v[k]
                val down = current % 2 == 1
                val t = a / (a - v[if (down) k + nx else k + 1])
                points[n++] = x0 + (k % nx + if (down) 0f else t) * cell
                points[n++] = y0 + (k / nx + if (down) t else 0f) * cell
                val first = links[2 * current]
                val next = if (first != previous) first else links[2 * current + 1]
                if (next < 0) break
                previous = current
                current = next
            }
            if (n > 4) loops.add(points.copyOf(n))
        }
        return loops
    }

    /** The liquid's distance field: each drop run into those before it. */
    fun field(drops: List<LiquidDrop>, x: Float, y: Float): Float = fieldOf(drops.map(::Shape), x, y)

    private fun fieldOf(shapes: List<Shape>, x: Float, y: Float): Float {
        var u = shapes[0].distance(x, y)
        for (n in 1 until shapes.size) u = smoothMin(u, shapes[n].distance(x, y), shapes[n].reach)
        return u
    }

    /** The smaller of [a] and [b], rounded into a fillet where they are within [k] of each other. */
    fun smoothMin(a: Float, b: Float, k: Float): Float {
        if (k <= 1e-4f) return min(a, b)
        val h = max(k - abs(a - b), 0f) / k
        return min(a, b) - h * h * h * k / 6f
    }
}

/** One count's drop at a moment of the picker's motion. */
data class PickerDrop(
    val x: Float,
    val radius: Float,
    val stretch: Float,
    val reach: Float,
    /** How much of the chosen colour it wears: 1 for the chosen count. */
    val accent: Float,
    /** How clearly its count shows. */
    val label: Float,
) {
    val liquid get() = LiquidDrop(x, radius, stretch, reach)
}

/**
 * How the session-length drops move. Opening, the others bud out of the chosen drop and spring
 * to their places, those further out a moment later; closing, they all flow back into the
 * chosen one, which takes on the chosen colour if it was just picked. A drop's spread is 0 at
 * home inside the chosen drop and 1 in its place.
 */
object LiquidMotion {
    /** The springs, as SwiftUI's response 0.42 s and 0.34 s on the Mac. */
    const val OPEN_DAMPING = 0.68f
    const val OPEN_STIFFNESS = 224f
    const val CLOSE_STIFFNESS = 342f
    const val STAGGER_MS = 28L

    /** How long a picked drop takes to wear the chosen colour. */
    const val RECOLOUR_MS = 100

    /**
     * Every count's drop, from each drop's [spreads] and how fast they change ([rates], per
     * second) and the share of the chosen colour each wears, for drops [size] across set [step]
     * apart. [opening] says which way they are going.
     */
    fun drops(
        spreads: FloatArray,
        rates: FloatArray,
        accents: FloatArray,
        chosen: Int,
        opening: Boolean,
        size: Float,
        step: Float,
    ): List<PickerDrop> {
        val count = spreads.size
        val r = size / 2
        val out = (0 until count).filter { it != chosen }.map { spreads[it].coerceIn(0f, 1f) }.average().toFloat()
            .takeIf { it.isFinite() } ?: 0f
        val drops = (0 until count).map { i ->
            val s = spreads[i]
            val slot = (i - (count - 1) / 2f) * step
            // Drops on the move are drawn out along the way they go.
            val stretch = 1f + 0.14f * min(1f, abs(rates[i] * slot) / step / 13f)
            if (i == chosen) {
                // The chosen drop gives a little as the others leave it, and swells as they return.
                val swell = (if (opening) -0.04f else 0.06f) * sin(PI.toFloat() * out)
                PickerDrop(slot * s, r * (1 + swell), stretch, 0f, accents[i], 1f)
            } else {
                PickerDrop(slot * s, r * grow(s), stretch, 0.48f * size * (1 - s.coerceIn(0f, 1f)).pow(1.4f), accents[i], 0f)
            }
        }
        // A count shows once its drop is clear of the others.
        return drops.mapIndexed { i, d ->
            if (i == chosen) return@mapIndexed d
            val gap = drops.indices.filter { it != i && drops[it].radius > 0.05f }.minOfOrNull {
                abs(d.x - drops[it].x) - d.radius * d.stretch - drops[it].radius * drops[it].stretch
            } ?: Float.MAX_VALUE
            d.copy(label = smoothstep(0.72f, 0.97f, spreads[i]) * smoothstep(0f, 0.09f * size, gap))
        }
    }

    /** The order the drops run into one another: the chosen one first, then outwards. */
    fun order(count: Int, chosen: Int): List<Int> =
        (0 until count).sortedWith(compareBy({ abs(it - chosen) }, { it }))

    /**
     * A drop's size for its spread: nothing at home, its full size in place, and a little more
     * while the spring carries it past.
     */
    fun grow(s: Float): Float = if (s > 1f) 1f + 0.4f * (s - 1f) else max(0f, s * (2f - s))

    internal fun smoothstep(e0: Float, e1: Float, x: Float): Float {
        val t = ((x - e0) / (e1 - e0)).coerceIn(0f, 1f)
        return t * t * (3 - 2 * t)
    }
}

/** A setting's drop in the fan at a moment of its motion. */
data class FanDrop(
    val x: Float,
    val y: Float,
    val radius: Float,
    val stretch: Float,
    /** The way it moves, in radians clockwise from along the row. */
    val angle: Float,
    val reach: Float,
    /** How much of the lit colour it wears: how far its setting is on, once it arrives. */
    val accent: Float,
    /** How clearly its icon shows. */
    val label: Float,
) {
    val liquid get() = LiquidDrop(x, radius, stretch, reach, y, angle)
}

/** The fan at one moment: the round button's own drop, and the settings' drops in order. */
class FanShape(val home: LiquidDrop, val drops: List<FanDrop>)

/**
 * The settings fan, opening as a hand fan does. Folded, it lies flat to the button's left: the
 * drops come out of the round button ([button] across) together, as one drop, to [distance]
 * from its centre, and swing round it from there, down toward below it, each 45 degrees
 * round from the one before, the fan centred on the quarter circle (two at 22.5
 * and 67.5 degrees, three at 0, 45 and 90; four share it, at 0, 30, 60 and 90), the later
 * ones further, pulling free of the ones
 * before them as they go. A drop's out is 0 at home inside the button and 1 at its distance;
 * its sweep is 0 folded flat and 1 in its place. The rates say how fast they change (per
 * second), and [lit] how far each drop's setting is on. Kept in step with the browser
 * version's fanDrops, whose two drops sit where this puts two.
 */
object LiquidFan {
    fun drops(
        outs: FloatArray,
        outRates: FloatArray,
        sweeps: FloatArray,
        sweepRates: FloatArray,
        lit: FloatArray,
        opening: Boolean,
        size: Float,
        button: Float,
        distance: Float,
    ): FanShape {
        val count = outs.size
        val r = size / 2
        fun reachAt(s: Float) = 0.48f * size * (1 - s.coerceIn(0f, 1f)).pow(1.4f)
        val out = if (count > 0) outs.map { it.coerceIn(0f, 1f) }.average().toFloat() else 0f
        // The button gives a little as the drops leave it, and swells as they return.
        val swell = (if (opening) -0.04f else 0.06f) * sin(PI.toFloat() * out)
        val home = LiquidDrop(0f, (button / 2) * (1 + swell))
        val drops = (0 until count).map { i ->
            val s = outs[i]
            // How far round from the button's left its place is, toward below: 45 degrees on
            // from the one before, or for more than three, the quarter circle shared out among
            // them; the fan centred on the quarter circle.
            val step = if (count <= 3) PI.toFloat() / 4 else (PI.toFloat() / 2) / (count - 1)
            val swing = PI.toFloat() / 4 + step * (i - (count - 1) / 2f)
            val angle = PI.toFloat() - swing * sweeps[i]
            val along = distance * s
            // Its velocity: out from the button, and round it.
            val c = cos(angle)
            val sn = sin(angle)
            val outward = distance * outRates[i]
            val round = along * swing * sweepRates[i]
            val vx = outward * c + round * sn
            val vy = outward * sn - round * c
            // Drawn out along the way it goes, as much as a row's drop at the same speed.
            val stretch = 1f + 0.14f * min(1f, hypot(vx, vy) / (size + 8) / 13f)
            // Coming out it runs into the button; swinging round, into the drops it leaves.
            val sweepReach = if (i == 0) 0f else reachAt(sweeps[i])
            val arrived = min(s.coerceIn(0f, 1f), sweeps[i].coerceIn(0f, 1f))
            FanDrop(
                x = c * along,
                y = sn * along,
                radius = r * LiquidMotion.grow(s),
                stretch = stretch,
                angle = atan2(vy, vx),
                reach = max(reachAt(s), sweepReach),
                accent = lit[i] * LiquidMotion.smoothstep(0.45f, 0.95f, arrived),
                label = LiquidMotion.smoothstep(0.72f, 0.97f, arrived),
            )
        }
        // An icon shows once its drop is in its place and clear of the button and the others.
        val all = listOf(home) + drops.map { it.liquid }
        return FanShape(
            home,
            drops.mapIndexed { i, d ->
                var gap = Float.MAX_VALUE
                for ((j, o) in all.withIndex()) {
                    if (j == i + 1 || o.radius <= 0.05f) continue
                    gap = min(gap, hypot(d.x - o.x, d.y - o.y) - d.radius * d.stretch - o.radius * o.stretch)
                }
                d.copy(label = d.label * LiquidMotion.smoothstep(0f, 0.09f * size, gap))
            },
        )
    }
}
