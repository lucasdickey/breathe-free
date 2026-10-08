package com.breathefree.app.ui

import android.content.Context
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.Screen
import com.breathefree.app.core.SessionPlan
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Renders the real screens at chosen moments and times of day, and saves them as PNGs in
 * build/screenshots. Run with: ./gradlew testDebugUnitTest -Pscreenshots --tests '*ScreenshotTest*'
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class ScreenshotTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val zone = ZoneId.of("America/Los_Angeles")
    private fun today(hour: Int, minute: Int) = ZonedDateTime.of(2026, 10, 7, hour, minute, 0, 0, zone)

    @Before
    fun onlyWhenAsked() {
        assumeTrue("pass -Pscreenshots to render screenshots", System.getProperty("screenshots") == "true")
    }

    private fun shot(name: String) {
        compose.waitForIdle()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        val file = File("build/screenshots/$name.png")
        file.parentFile?.mkdirs()
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        println("saved ${file.absolutePath}")
    }

    private fun controller(): BreatheController {
        val context = ApplicationProvider.getApplicationContext<Context>()
        compose.mainClock.autoAdvance = false
        return BreatheController(context) { compose.mainClock.currentTime * 1_000_000L }
    }

    /** Runs a session from [controller]'s home screen, shooting the moments named. */
    private fun session(controller: BreatheController, prefix: String, moments: List<Pair<Double, String>>) {
        controller.chooseSound(SoundMode.SILENT) // no audio thread under the test clock
        compose.runOnUiThread { controller.begin() }
        val start = compose.mainClock.currentTime
        // Session time t is reached when the frame clock passes start + lead + t (less the
        // two-frame display lead, which is within a frame of these marks).
        for ((t, name) in moments) {
            val target = start + 350 + (t * 1000).toLong()
            compose.mainClock.advanceTimeBy(target - compose.mainClock.currentTime)
            shot("$prefix-$name")
        }
    }

    @Test
    fun aWholeSessionAtNight() {
        val controller = controller()
        controller.chooseCycles(2)
        compose.setContent { BreatheApp(controller) { today(20, 49) } }
        compose.mainClock.advanceTimeBy(2_500)
        shot("night-1-home")
        session(
            controller, "night",
            listOf(
                3.0 to "2-settle", 9.9 to "3-inhale", 13.6 to "4-hold-full", 17.6 to "5-exhale",
                22.4 to "6-hold-empty", SessionPlan(2).endTime + 2.5 to "7-done",
            ),
        )
        assertEquals(Screen.DONE, controller.screen)
    }

    @Test
    fun aSessionAtNoon() {
        val controller = controller()
        controller.chooseCycles(2)
        compose.setContent { BreatheApp(controller) { today(12, 30) } }
        compose.mainClock.advanceTimeBy(2_500)
        session(controller, "noon", listOf(3.0 to "2-settle", 9.9 to "3-inhale", 17.6 to "5-exhale", SessionPlan(2).endTime + 2.5 to "7-done"))
    }

    @Test
    fun pausedAtNoon() {
        val controller = controller()
        controller.chooseCycles(2)
        compose.setContent { BreatheApp(controller) { today(12, 30) } }
        compose.mainClock.advanceTimeBy(2_500)
        session(controller, "paused-noon", listOf(13.6 to "1-holding"))
        compose.onNodeWithContentDescription("Pause session").performClick()
        compose.mainClock.advanceTimeBy(5_000)
        shot("paused-noon-2-paused")
    }

    @Test
    fun pausedAtNight() {
        val controller = controller()
        controller.chooseCycles(2)
        compose.setContent { BreatheApp(controller) { today(20, 49) } }
        compose.mainClock.advanceTimeBy(2_500)
        session(controller, "paused-night", listOf(13.6 to "1-holding"))
        compose.onNodeWithContentDescription("Pause session").performClick()
        compose.mainClock.advanceTimeBy(5_000)
        shot("paused-night-2-paused")
    }

    @Test
    fun homeThroughTheDay() {
        val controller = controller()
        var now = today(6, 0)
        compose.setContent { BreatheApp(controller) { now } }
        for ((hour, minute) in listOf(6 to 0, 6 to 50, 7 to 30, 12 to 30, 17 to 45, 18 to 40, 19 to 15, 22 to 0)) {
            now = today(hour, minute)
            compose.mainClock.advanceTimeBy(2_000) // the text eases across in 1.2 s
            shot("day-%02d%02d".format(hour, minute))
        }
    }

    @Test
    fun sessionLengthFansOutAndFolds() {
        val controller = controller()
        controller.chooseCycles(6)
        compose.setContent { BreatheApp(controller) { today(12, 30) } }
        compose.mainClock.advanceTimeBy(1_000)
        shot("picker-1-folded")

        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(90)
        shot("picker-2-opening")
        compose.mainClock.advanceTimeBy(700)
        shot("picker-3-open")

        compose.onNodeWithContentDescription("36 cycles,", substring = true).performClick()
        compose.mainClock.advanceTimeBy(120)
        shot("picker-4-folding")
        compose.mainClock.advanceTimeBy(700)
        shot("picker-5-picked-36")
        assertEquals(36, controller.cycles)

        // A touch anywhere else folds it, and goes no further: Begin is not pressed.
        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(700)
        compose.onNodeWithText("Begin").performClick()
        compose.mainClock.advanceTimeBy(700)
        shot("picker-6-folded-by-a-touch-elsewhere")
        assertEquals(Screen.HOME, controller.screen)
        assertEquals(36, controller.cycles)

        // So does Back.
        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(700)
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.mainClock.advanceTimeBy(700)
        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(700)
        shot("picker-7-reopened-after-back")
        assertEquals(Screen.HOME, controller.screen)
    }

    @Test
    fun sessionLengthOpenAtNight() {
        val controller = controller()
        controller.chooseCycles(10)
        compose.setContent { BreatheApp(controller) { today(21, 30) } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(800)
        shot("picker-night-open")
    }
}
