package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.Screen
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId
import java.time.ZonedDateTime

/** Pause, resume and end, pressed on the real session screen with the frame clock under test control. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class SessionPauseTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))

    private fun nanos() = compose.mainClock.currentTime * 1_000_000L

    private fun startSession(): BreatheController {
        val context = ApplicationProvider.getApplicationContext<Context>()
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { nanos() }
        controller.chooseCycles(2)
        // No audio thread under the test clock: silent, and no voice (which speaks even then).
        controller.chooseSound(SoundMode.SILENT)
        controller.chooseVoice(false)
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.runOnUiThread { controller.begin() }
        return controller
    }

    @Test
    fun pauseHoldsTheSessionStillAndResumeCarriesOn() {
        val controller = startSession()
        compose.mainClock.advanceTimeBy(350 + 13_600) // 13.6 s in: the first full hold
        compose.onNodeWithContentDescription("Pause session").performClick()
        compose.waitForIdle()
        val stoppedAt = controller.session!!.timeAt(nanos())
        assertTrue(controller.isPaused)

        // Someone walks in; twenty seconds go by.
        compose.mainClock.advanceTimeBy(20_000)
        compose.onNodeWithText("Paused").assertIsDisplayed()
        assertEquals(stoppedAt, controller.session!!.timeAt(nanos()), 1e-9)
        assertEquals(Screen.SESSION, controller.screen)

        compose.onNodeWithContentDescription("Resume session").performClick()
        compose.waitForIdle()
        assertFalse(controller.isPaused)
        val resumedAt = nanos()
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(stoppedAt + (nanos() - resumedAt) / 1e9, controller.session!!.timeAt(nanos()), 1e-9)
        compose.onNodeWithContentDescription("Pause session").assertIsDisplayed()
    }

    @Test
    fun holdingTheCrossEndsTheSession() {
        val controller = startSession()
        compose.mainClock.advanceTimeBy(5_000)
        val cross = compose.onNodeWithContentDescription("End session")
        cross.performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(500)
        // Pressed, it opens and says what to do; half way there, the session carries on.
        compose.onNodeWithText("Hold to end").assertIsDisplayed()
        assertEquals(Screen.SESSION, controller.screen)
        compose.mainClock.advanceTimeBy(600)
        assertEquals(Screen.HOME, controller.screen)
        assertNull(controller.session)
    }

    @Test
    fun lettingGoTooSoonOrTappingDoesNotEnd() {
        val controller = startSession()
        compose.mainClock.advanceTimeBy(5_000)
        val cross = compose.onNodeWithContentDescription("End session")
        cross.performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(800)
        compose.onNodeWithText("Hold to end").performTouchInput { up() }
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(Screen.SESSION, controller.screen)
        // Taps, however many, only open it.
        repeat(2) {
            compose.onNodeWithText("Hold to end").performClick()
            compose.mainClock.advanceTimeBy(400)
        }
        assertEquals(Screen.SESSION, controller.screen)
        // A hold after a let-go fills from empty again, not from where it was.
        compose.onNodeWithText("Hold to end").performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(700)
        assertEquals(Screen.SESSION, controller.screen)
        compose.mainClock.advanceTimeBy(400)
        assertEquals(Screen.HOME, controller.screen)
    }

    @Test
    fun endSessionClosesAgainIfLeft() {
        val controller = startSession()
        compose.mainClock.advanceTimeBy(5_000)
        compose.onNodeWithContentDescription("End session").performClick()
        compose.mainClock.advanceTimeBy(100)
        compose.onNodeWithText("Hold to end").assertIsDisplayed()
        compose.mainClock.advanceTimeBy(4_500)
        compose.onNodeWithText("Hold to end").assertDoesNotExist()
        assertEquals(Screen.SESSION, controller.screen)
    }

    @Test
    fun backAsksBeforeEnding() {
        val controller = startSession()
        compose.mainClock.advanceTimeBy(5_000)
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.mainClock.advanceTimeBy(100)
        compose.onNodeWithText("End session").assertIsDisplayed()
        assertEquals(Screen.SESSION, controller.screen)
        compose.mainClock.advanceTimeBy(400)
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.waitForIdle()
        assertEquals(Screen.HOME, controller.screen)
    }
}
