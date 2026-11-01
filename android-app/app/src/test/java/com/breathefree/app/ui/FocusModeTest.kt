package com.breathefree.app.ui

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.Screen
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Focus mode, on the real session screen: the top bar and the cycle count stay in sight for a
 * few seconds, then keep out of it until the screen is touched; pausing, ending and TalkBack
 * keep them in sight. Without focus mode they never go.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class FocusModeTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    private fun startSession(focus: Boolean): BreatheController {
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { compose.mainClock.currentTime * 1_000_000L }
        controller.chooseCycles(2)
        // No audio thread under the test clock: silent, and no voice (which speaks even then).
        controller.chooseSound(SoundMode.SILENT)
        controller.chooseVoice(false)
        controller.chooseFocus(focus)
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.runOnUiThread { controller.begin() }
        compose.mainClock.advanceTimeBy(1_000)
        return controller
    }

    private val pause get() = compose.onNodeWithContentDescription("Pause session")

    /** The count under the box: "Starting soon" through the settle, then which cycle. */
    private val count get() = compose.onNode(hasText("Starting soon").or(hasText("Cycle", substring = true)))

    private fun assertInSight() {
        pause.assertIsDisplayed()
        count.assertIsDisplayed()
    }

    private fun assertOutOfSight() {
        pause.assertDoesNotExist()
        count.assertDoesNotExist()
    }

    /** A tap on the open sky between the words and the cycle count. */
    private fun tapTheSky() {
        compose.onRoot().performTouchInput { click(Offset(width * 0.2f, height * 0.75f)) }
        compose.mainClock.advanceTimeBy(400)
    }

    @Test
    fun withoutFocusModeTheyStay() {
        startSession(focus = false)
        compose.mainClock.advanceTimeBy(6_000)
        assertInSight()
    }

    @Test
    fun focusModeIsOffUntilSwitchedOn() {
        assertFalse(BreatheController(context).focusOn)
    }

    @Test
    fun theyGoAfterAFewSecondsAndATouchBringsThemBack() {
        val controller = startSession(focus = true)
        // In sight as the session begins, then off to the edges.
        assertInSight()
        compose.mainClock.advanceTimeBy(2_700)
        assertOutOfSight()

        tapTheSky()
        assertInSight()
        // The tap only brought them back.
        assertFalse(controller.isPaused)
        assertEquals(Screen.SESSION, controller.screen)

        // Every touch starts the wait again.
        compose.mainClock.advanceTimeBy(2_000)
        tapTheSky()
        compose.mainClock.advanceTimeBy(2_000)
        assertInSight()
        compose.mainClock.advanceTimeBy(1_400)
        assertOutOfSight()
    }

    @Test
    fun pausedTheyStay() {
        val controller = startSession(focus = true)
        compose.mainClock.advanceTimeBy(2_700)
        tapTheSky()
        pause.performClick()
        compose.mainClock.advanceTimeBy(10_000)
        assertTrue(controller.isPaused)
        compose.onNodeWithContentDescription("Resume session").assertIsDisplayed()

        // Resumed, they stay a few seconds more, then go.
        compose.onNodeWithContentDescription("Resume session").performClick()
        compose.mainClock.advanceTimeBy(2_000)
        pause.assertIsDisplayed()
        compose.mainClock.advanceTimeBy(1_800)
        pause.assertDoesNotExist()
    }

    @Test
    fun backBringsTheEndOfTheSessionIntoSight() {
        startSession(focus = true)
        compose.mainClock.advanceTimeBy(2_700)
        assertOutOfSight()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.mainClock.advanceTimeBy(400)
        compose.onNodeWithText("End session").assertIsDisplayed()
    }

    @Test
    fun withTalkBackTheyStay() {
        shadowOf(compose.activity.getSystemService(AccessibilityManager::class.java)).setTouchExplorationEnabled(true)
        startSession(focus = true)
        compose.mainClock.advanceTimeBy(6_000)
        assertInSight()
    }
}
