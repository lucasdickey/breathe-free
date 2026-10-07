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
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.abs

/**
 * The breath lives in the orb and its glow. The sky goes on as it is, so the clouds out in it
 * never fade on a breath in and come back on the breath out, which looked like them starting over.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w800dp-h615dp-land-mdpi")
class SteadySkyTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 13, 30, 0, 0, ZoneId.of("America/Los_Angeles"))

    private fun nanos() = compose.mainClock.currentTime * 1_000_000L

    @Test
    fun theSkyBesideTheBoxIsTheSameOnAFullAndAnEmptyBreath() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        // With animations off the clouds hold still, so any difference left is the breath's doing.
        Settings.Global.putFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 0f)
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { nanos() }
        controller.chooseCycles(2)
        controller.chooseSound(SoundMode.SILENT) // no audio thread under the test clock
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.runOnUiThread { controller.begin() }
        val start = compose.mainClock.currentTime

        fun breathAt(seconds: Double): Pair<Double, Bitmap> {
            compose.mainClock.advanceTimeBy(start + 350 + (seconds * 1000).toLong() - compose.mainClock.currentTime)
            compose.waitForIdle()
            val active = controller.session!!
            return active.plan.frameAt(active.timeAt(nanos())).level to
                compose.onRoot().captureToImage().asAndroidBitmap()
        }
        val (fullLevel, full) = breathAt(14.0) // holding after the breath in
        val (emptyLevel, empty) = breathAt(22.0) // holding after the breath out
        assertTrue("lungs full at 14 s, level $fullLevel", fullLevel > 0.99)
        assertTrue("lungs empty at 22 s, level $emptyLevel", emptyLevel < 0.01)

        // Either side of the box, level with it: open sky, clear of the orb's glow at any breath.
        val g = SceneGeometry.of(full.width.toFloat(), full.height.toFloat())
        val clear = g.half * 1.25f
        var largest = 0
        for (y in (g.cy - clear).toInt()..(g.cy + clear).toInt()) {
            for (x in 0 until full.width) {
                if (abs(x - g.cx) < clear) continue
                largest = maxOf(largest, gap(full.getPixel(x, y), empty.getPixel(x, y)))
            }
        }
        assertTrue("the sky beside the box changed by $largest between the two breaths", largest <= 2)
    }

    private fun gap(a: Int, b: Int) = maxOf(
        abs(Color.red(a) - Color.red(b)),
        abs(Color.green(a) - Color.green(b)),
        abs(Color.blue(a) - Color.blue(b)),
    )
}
