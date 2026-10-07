package com.breathefree.app.ui

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * Session length as liquid. When the picker opens, the other counts bud out of the chosen one
 * and pull free as drops; when one is picked, they all flow back into it. Drops run into one
 * another wherever they come close, as far as each drop's reach, and the reach eases to nothing
 * as a drop settles, so at rest they are plain circles. Kept in step with the Mac app's
 * LiquidPicker.swift.
 */

/** One drop of a row of liquid, centred on the row's line. */
data class LiquidDrop(
    /** Its centre along the row. */
    val x: Float,
    val radius: Float,
    /** How far it is drawn out along the row as it moves; 1 is round. */
    val stretch: Float = 1f,
    /** How far it runs into the drops before it in the row. */
    val reach: Float = 0f,
) {
    /** Distance from its edge, negative inside: exact when round, close when stretched. */
    fun distance(px: Float, py: Float): Float {
        val a = radius * stretch
        val b = radius / stretch
        val dx = (px - x) / a
        val dy = py / b
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
        var x0 = Float.MAX_VALUE
        var x1 = -Float.MAX_VALUE
        var half = 0f
        for (d in live) {
            x0 = min(x0, d.x - d.radius * d.stretch - d.reach)
            x1 = max(x1, d.x + d.radius * d.stretch + d.reach)
            half = max(half, d.radius + d.reach / 4)
        }
        x0 -= 2 * cell
        x1 += 2 * cell
        half += 2 * cell
        val y0 = -half
        val nx = ceil((x1 - x0) / cell).toInt() + 1
        val ny = ceil(2 * half / cell).toInt() + 1
        val v = FloatArray(nx * ny)
        for (j in 0 until ny) {
            val y = y0 + j * cell
            for (i in 0 until nx) v[j * nx + i] = field(live, x0 + i * cell, y) + inset
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

    /** The row's distance field: each drop run into those before it. */
    fun field(drops: List<LiquidDrop>, x: Float, y: Float): Float {
        var u = drops[0].distance(x, y)
        for (n in 1 until drops.size) u = smoothMin(u, drops[n].distance(x, y), drops[n].reach)
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

    private fun smoothstep(e0: Float, e1: Float, x: Float): Float {
        val t = ((x - e0) / (e1 - e0)).coerceIn(0f, 1f)
        return t * t * (3 - 2 * t)
    }
}
