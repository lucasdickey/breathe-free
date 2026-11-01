package com.breathefree.app.ui

import android.graphics.Paint
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import com.breathefree.app.core.Gust
import com.breathefree.app.core.GustWords
import kotlin.math.roundToInt

/**
 * A word as specks of ink: one for every few pixels its letters cover, taken from the same text
 * the screen would set, so the settled specks read as the word in its own face. Positions are
 * from the word's centre, in pixels.
 */
class WordSpecks(val xs: FloatArray, val ys: FloatArray, val along: FloatArray, val ink: FloatArray) {
    val size get() = xs.size
}

/**
 * Draws the session's words as specks on the wind ([Gust]), in [style]'s face and size. Each
 * word is sampled once, the first time it is drawn.
 */
class WindWords(private val measurer: TextMeasurer, private val style: TextStyle, private val density: Density) {
    private val words = HashMap<String, WordSpecks>()
    private val place = FloatArray(3)

    // The specks are drawn as points, in a few steps of opacity: one call to the canvas for each.
    private val points = Array(LEVELS) { FloatArray(512) }
    private val counts = IntArray(LEVELS)
    private val paint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    /** One speck for every [step] pixels each way, drawn a little wider so the settled word reads whole. */
    private val step = maxOf(2, (density.density * 0.7f).roundToInt())

    /** One dp, in pixels. */
    private val unit = density.density

    fun specks(text: String): WordSpecks = words.getOrPut(text) { sample(text) }

    /**
     * Draws [gust]'s words centred on ([cx], [cy]) in [color], with the sky clear for [room]
     * pixels below them: [level] is how full the lungs are, and [t] session time.
     */
    fun draw(scope: DrawScope, gust: GustWords, cx: Float, cy: Float, room: Float, level: Double, t: Double, color: Color) = with(scope) {
        counts.fill(0)
        val reach = size.width
        if (gust.leaving.isNotEmpty() && gust.leaveSince < Gust.GONE) {
            add(specks(gust.leaving), Gust.ARRIVED + 1.0, gust.leaveSince, cx, cy, reach, room, level, t)
        }
        if (gust.arriving.isNotEmpty()) {
            add(specks(gust.arriving), gust.arriveSince, -1.0, cx, cy, reach, room, level, t)
        }
        paint.strokeWidth = step * 1.25f
        drawIntoCanvas { canvas ->
            for (i in 0 until LEVELS) {
                if (counts[i] == 0) continue
                paint.color = color.copy(alpha = color.alpha * (i + 1) / LEVELS).toArgb()
                canvas.nativeCanvas.drawPoints(points[i], 0, counts[i] * 2, paint)
            }
        }
    }

    private fun add(
        w: WordSpecks, arriveSince: Double, leaveSince: Double,
        cx: Float, cy: Float, reach: Float, room: Float, level: Double, t: Double,
    ) {
        for (i in 0 until w.size) {
            Gust.place(w.xs[i], w.ys[i], w.along[i], i, arriveSince, leaveSince, reach, room, unit, level, t, place)
            val a = place[2] * w.ink[i]
            val bucket = (a * LEVELS).roundToInt() - 1
            if (bucket < 0) continue
            val b = minOf(bucket, LEVELS - 1)
            var into = points[b]
            val n = counts[b]
            if (2 * n + 2 > into.size) {
                into = into.copyOf(into.size * 2)
                points[b] = into
            }
            into[2 * n] = cx + place[0]
            into[2 * n + 1] = cy + place[1]
            counts[b] = n + 1
        }
    }

    /** Sets [text] as the screen would, then keeps a speck wherever its letters cover a pixel well. */
    private fun sample(text: String): WordSpecks {
        val layout = measurer.measure(text, style.copy(color = Color.Black))
        val w = layout.size.width
        val h = layout.size.height
        if (w <= 0 || h <= 0) return WordSpecks(FloatArray(0), FloatArray(0), FloatArray(0), FloatArray(0))
        val bitmap = ImageBitmap(w, h)
        CanvasDrawScope().draw(density, LayoutDirection.Ltr, Canvas(bitmap), Size(w.toFloat(), h.toFloat())) {
            drawText(layout)
        }
        val pixels = IntArray(w * h)
        bitmap.readPixels(pixels)

        // The letters' own left and right, for how far along the word each speck is.
        var first = w
        var last = 0
        val xs = ArrayList<Float>()
        val ys = ArrayList<Float>()
        val ink = ArrayList<Float>()
        var n = 0
        for (y in 0 until h step step) {
            for (x in 0 until w step step) {
                val a = (pixels[y * w + x] ushr 24) / 255f
                if (a < COVERED) continue
                // A little off the grid, so no rows or columns show.
                xs += x + (Gust.luck(n, 10) - 0.5f) * step * 0.6f - w / 2f
                ys += y + (Gust.luck(n, 11) - 0.5f) * step * 0.6f - h / 2f
                ink += a * (0.8f + 0.2f * Gust.luck(n, 12))
                first = minOf(first, x)
                last = maxOf(last, x)
                n++
            }
        }
        val span = maxOf(1f, (last - first).toFloat())
        val along = FloatArray(n) { ((xs[it] + w / 2f - first) / span).coerceIn(0f, 1f) }
        return WordSpecks(xs.toFloatArray(), ys.toFloatArray(), along, ink.toFloatArray())
    }

    private companion object {
        const val LEVELS = 16

        /** How much of a pixel the letters must cover for it to get a speck. */
        const val COVERED = 0.43f
    }
}
