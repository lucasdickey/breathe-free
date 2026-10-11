package com.breathefree.app.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.sqrt

/**
 * The clouds round the orb, inside the box, stay as clear on a full breath as on an empty one.
 * A glow that veiled them as the lungs filled let them come back at the end of every cycle,
 * which looked like the sky starting over.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w800dp-h615dp-land-mdpi")
class CloudsThroughTheBreathTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun nanos() = compose.mainClock.currentTime * 1_000_000L

    private fun frames(at: ZonedDateTime): Pair<Bitmap, Bitmap> {
        val context = ApplicationProvider.getApplicationContext<Context>()
        // With animations off the clouds hold still, so any difference left is the breath's doing.
        Settings.Global.putFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 0f)
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { nanos() }
        controller.chooseCycles(2)
        controller.chooseSound(SoundMode.SILENT) // no audio thread under the test clock
        compose.setContent { BreatheApp(controller) { at } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.runOnUiThread { controller.begin() }
        val start = compose.mainClock.currentTime

        fun breathAt(seconds: Double): Bitmap {
            compose.mainClock.advanceTimeBy(start + 350 + (seconds * 1000).toLong() - compose.mainClock.currentTime)
            compose.waitForIdle()
            return compose.onRoot().captureToImage().asAndroidBitmap()
        }
        // Holding after the breath in, and after the breath out, once each ring has gone.
        return breathAt(14.5) to breathAt(22.5)
    }

    /**
     * How clearly clouds show in the band between the full orb and the box: for each distance
     * from the centre, how much the brightness varies round the circle (a glow round the orb
     * changes only with distance, so it isn't counted), averaged over the band.
     */
    private fun cloudContrast(image: Bitmap): Double {
        val g = SceneGeometry.of(image.width.toFloat(), image.height.toFloat())
        val bins = 12
        val inner = g.orbMax * 1.03f
        val outer = g.half * 0.95f
        val sums = DoubleArray(bins)
        val squares = DoubleArray(bins)
        val counts = IntArray(bins)
        for (y in (g.cy - outer).toInt()..(g.cy + outer).toInt()) {
            for (x in (g.cx - outer).toInt()..(g.cx + outer).toInt()) {
                val d = hypot(x - g.cx, y - g.cy)
                if (d < inner || d >= outer) continue
                // Leave out the top of the box, where the light and its trail go.
                if (atan2(g.cy - y, x - g.cx) in 0.6f..2.6f) continue
                val bin = (((d - inner) / (outer - inner)) * bins).toInt().coerceIn(0, bins - 1)
                val p = image.getPixel(x, y)
                val l = 0.2126 * Color.red(p) + 0.7152 * Color.green(p) + 0.0722 * Color.blue(p)
                sums[bin] += l
                squares[bin] += l * l
                counts[bin]++
            }
        }
        var total = 0.0
        for (b in 0 until bins) {
            val mean = sums[b] / counts[b]
            total += sqrt(maxOf(0.0, squares[b] / counts[b] - mean * mean))
        }
        return total / bins
    }

    private fun check(name: String, at: ZonedDateTime) {
        val (full, empty) = frames(at)
        val out = File("build/clouds-through-the-breath").apply { mkdirs() }
        full.compress(Bitmap.CompressFormat.PNG, 100, File(out, "$name-full.png").outputStream())
        empty.compress(Bitmap.CompressFormat.PNG, 100, File(out, "$name-empty.png").outputStream())
        val f = cloudContrast(full)
        val e = cloudContrast(empty)
        println("clouds round the orb at $name: contrast %.2f full, %.2f empty, ratio %.2f".format(f, e, f / e))
        assertTrue("at $name the clouds round the orb keep %.0f%% of their contrast on a full breath".format(100 * f / e), f / e > 0.9)
    }

    @Test
    fun atDusk() = check("dusk", ZonedDateTime.of(2026, 10, 7, 19, 10, 0, 0, ZoneId.of("America/Los_Angeles")))

    @Test
    fun atNight() = check("night", ZonedDateTime.of(2026, 10, 7, 22, 30, 0, 0, ZoneId.of("America/Los_Angeles")))

    @Test
    fun atMidday() = check("midday", ZonedDateTime.of(2026, 10, 7, 12, 47, 0, 0, ZoneId.of("America/Los_Angeles")))
}
