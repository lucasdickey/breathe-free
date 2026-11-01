package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.DpRect
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
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.sqrt

/**
 * Sound, voice, vibration and focus mode, folded into the button in the home screen's top-right corner: it
 * opens into a fan of drops, left of the button and down below it, each changing its setting
 * and leaving the fan open. The ✕, a touch anywhere else (which goes no further) or Back folds
 * it, and folded, its drops can't be pressed or found.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class SettingsFanTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val drops = listOf("Sound", "Voice guidance", "Vibrate at each change", "Focus mode")

    private fun home(): BreatheController {
        val controller = BreatheController(context, loadVoice = { null }) { 0L }
        compose.mainClock.autoAdvance = false // the orb and the sky never stop moving
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(500)
        return controller
    }

    private val button get() = compose.onNodeWithContentDescription("Settings")

    private fun tapTheButton() {
        button.performClick()
        compose.mainClock.advanceTimeBy(800)
    }

    private fun state(text: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, text)

    private fun assertFolded() {
        button.assert(state("Collapsed"))
        for (name in drops) compose.onNodeWithContentDescription(name).assertDoesNotExist()
    }

    private val DpRect.centre get() = Pair((left + right).value / 2, (top + bottom).value / 2)

    @Test
    fun theButtonOpensTheFanAndTheCrossFoldsIt() {
        home()
        assertFolded()
        tapTheButton()
        button.assert(state("Expanded"))
        for (name in drops) compose.onNodeWithContentDescription(name).assertIsDisplayed()
        tapTheButton()
        assertFolded()
    }

    @Test
    fun openTheDropsShareTheQuarterCircleFromLeftOfTheButtonToBelowIt() {
        home()
        tapTheButton()
        val (bx, by) = button.getBoundsInRoot().centre
        // In the corner, where a session's speaker is: 16 dp in and 10 dp down, 44 dp across.
        assertEquals(400f - 16f - 22f, bx, 0.5f)
        assertEquals(10f + 22f, by, 0.5f)
        // Four, 30 degrees apart, 112 dp out.
        val near = 112f * sqrt(3f) / 2
        val far = 112f / 2
        for ((name, place) in drops.zip(listOf(-112f to 0f, -near to far, -far to near, 0f to 112f))) {
            val (x, y) = compose.onNodeWithContentDescription(name).getBoundsInRoot().centre
            assertEquals("$name across", place.first, x - bx, 0.5f)
            assertEquals("$name down", place.second, y - by, 0.5f)
        }
    }

    @Test
    fun soundGoesRoundAmbientBellsSilentAndIsKept() {
        val controller = home()
        tapTheButton()
        val sound = compose.onNodeWithContentDescription("Sound")
        sound.assert(state("Ambient"))
        for ((name, mode) in listOf("Bells" to SoundMode.BELLS, "Silent" to SoundMode.SILENT, "Ambient" to SoundMode.AMBIENT)) {
            sound.performClick()
            compose.mainClock.advanceTimeBy(150)
            sound.assert(state(name))
            assertEquals(mode, controller.soundMode)
            assertEquals(mode, BreatheController(context, loadVoice = { null }).soundMode)
        }
        // Open all along.
        button.assert(state("Expanded"))
    }

    @Test
    fun vibratingIsItsOwnSwitch() {
        val controller = home()
        tapTheButton()
        val vibrate = compose.onNodeWithContentDescription("Vibrate at each change")
        vibrate.assertIsOn()
        vibrate.performClick()
        compose.mainClock.advanceTimeBy(150)
        vibrate.assertIsOff()
        assertFalse(controller.hapticsOn)
        assertFalse(BreatheController(context, loadVoice = { null }).hapticsOn)
        // Nothing else changes.
        assertTrue(controller.voiceOn)
        assertEquals(SoundMode.AMBIENT, controller.soundMode)
    }

    @Test
    fun focusModeIsItsOwnSwitchOffAtFirst() {
        val controller = home()
        tapTheButton()
        val focus = compose.onNodeWithContentDescription("Focus mode")
        focus.assertIsOff()
        focus.performClick()
        compose.mainClock.advanceTimeBy(150)
        focus.assertIsOn()
        assertTrue(controller.focusOn)
        assertTrue(BreatheController(context, loadVoice = { null }).focusOn)
        // Nothing else changes.
        assertTrue(controller.voiceOn)
        assertTrue(controller.hapticsOn)
        assertEquals(SoundMode.AMBIENT, controller.soundMode)
    }

    @Test
    fun aTouchAnywhereElseFoldsItAndGoesNoFurther() {
        val controller = home()
        controller.chooseSound(SoundMode.SILENT) // no audio thread under the test clock
        controller.chooseVoice(false)
        tapTheButton()
        compose.onNodeWithText("Begin").performClick()
        compose.mainClock.advanceTimeBy(800)
        assertFolded()
        assertEquals(Screen.HOME, controller.screen)
        // Folded, Begin begins.
        compose.onNodeWithText("Begin").performClick()
        compose.mainClock.advanceTimeBy(100)
        assertEquals(Screen.SESSION, controller.screen)
    }

    @Test
    fun backFoldsIt() {
        val controller = home()
        tapTheButton()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.mainClock.advanceTimeBy(800)
        assertFolded()
        assertEquals(Screen.HOME, controller.screen)
    }

    @Test
    fun foldedNothingIsLeftWhereTheDropsWere() {
        val controller = home()
        tapTheButton()
        val voiceAt = compose.onNodeWithContentDescription("Voice guidance").getBoundsInRoot().centre
        tapTheButton()
        compose.onRoot().performTouchInput {
            click(Offset(voiceAt.first * density, voiceAt.second * density))
        }
        compose.mainClock.advanceTimeBy(800)
        assertTrue(controller.voiceOn)
        assertFolded()
    }
}
