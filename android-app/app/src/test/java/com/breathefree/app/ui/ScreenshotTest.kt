package com.breathefree.app.ui

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
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

/**
 * Renders the real screens at chosen moments of a session and saves them as PNGs in
 * build/screenshots. Run with: ./gradlew testDebugUnitTest -Pscreenshots --tests '*ScreenshotTest*'
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class ScreenshotTest {
    @get:Rule
    val compose = createComposeRule()

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

    @Test
    fun aWholeSession() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { compose.mainClock.currentTime * 1_000_000L }
        controller.chooseCycles(2)
        controller.chooseSound(SoundMode.AMBIENT)
        compose.setContent { BreatheApp(controller) }
        compose.mainClock.advanceTimeBy(2_500)
        shot("1-home")

        controller.chooseSound(SoundMode.SILENT) // no audio thread under the test clock
        compose.runOnUiThread { controller.begin() }
        val start = compose.mainClock.currentTime
        // Session time t is reached when the frame clock passes start + lead + t (less the
        // two-frame display lead, which is within a frame of these marks).
        fun at(t: Double) {
            val target = start + 350 + (t * 1000).toLong()
            compose.mainClock.advanceTimeBy(target - compose.mainClock.currentTime)
        }
        at(3.0); shot("2-settle")
        at(9.9); shot("3-inhale")
        at(13.6); shot("4-hold-full")
        at(17.6); shot("5-exhale")
        at(22.4); shot("6-hold-empty")
        at(SessionPlan(2).endTime + 2.5); shot("7-done")
        assertEquals(Screen.DONE, controller.screen)
    }
}
