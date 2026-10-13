package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import androidx.compose.ui.unit.DpRect
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.Screen
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * The speaker in a session sets how loud it is, with a slider that floats under it, as on the
 * Mac. Opening the slider moves nothing in the top bar (the sound-type label it replaces made
 * the bar jump), and the sound itself stays as chosen on the home screen. With the voice on,
 * the tone and the voice each have a slider.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class VolumeTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    private fun nanos() = compose.mainClock.currentTime * 1_000_000L

    private fun startSession(): BreatheController {
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { nanos() }
        controller.chooseCycles(2)
        controller.chooseSound(SoundMode.SILENT) // no audio thread under the test clock
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.runOnUiThread { controller.begin() }
        compose.mainClock.advanceTimeBy(5_000)
        return controller
    }

    /** Where the top bar's ✕, clock, pause and speaker are. */
    private fun topBar(speaker: String): List<DpRect> = listOf(
        compose.onNodeWithContentDescription("End session").getBoundsInRoot(),
        compose.onNodeWithContentDescription(" left", substring = true).getBoundsInRoot(),
        compose.onNodeWithContentDescription("Pause session").getBoundsInRoot(),
        compose.onNodeWithContentDescription(speaker).getBoundsInRoot(),
    )

    @Test
    fun theSpeakerOpensAVolumeSliderAndNothingMoves() {
        val controller = startSession()
        val before = topBar("Volume, 100%")
        compose.onNodeWithContentDescription("Volume, 100%").performClick()
        compose.mainClock.advanceTimeBy(200)
        compose.onNodeWithContentDescription("Volume").assertIsDisplayed()
        assertEquals(before, topBar("Volume, 100%"))
        // It no longer switches the sound, nor shows a label for it.
        assertEquals(SoundMode.SILENT, controller.soundMode)
        for (label in listOf("Ambient", "Bells", "Silent")) compose.onNodeWithText(label).assertDoesNotExist()
    }

    @Test
    fun theSliderSetsTheVolumeAndItIsKept() {
        val controller = startSession()
        compose.onNodeWithContentDescription("Volume, 100%").performClick()
        compose.mainClock.advanceTimeBy(200)
        val slider = compose.onNodeWithContentDescription("Volume")
        slider.performTouchInput { swipeLeft(startX = centerX, endX = left) }
        compose.mainClock.advanceTimeBy(100)
        assertEquals(0f, controller.volume, 1e-6f)
        compose.onNodeWithContentDescription("Volume, 0%").assertIsDisplayed()
        slider.performTouchInput { swipeRight(startX = centerX, endX = right) }
        compose.mainClock.advanceTimeBy(100)
        assertEquals(1f, controller.volume, 1e-6f)
        // TalkBack sets it directly.
        slider.performSemanticsAction(SemanticsActions.SetProgress) { it(0.4f) }
        compose.mainClock.advanceTimeBy(100)
        assertEquals(0.4f, controller.volume, 1e-6f)
        compose.onNodeWithContentDescription("Volume, 40%").assertIsDisplayed()
        // Kept for next time.
        assertEquals(0.4f, BreatheController(context).volume, 1e-6f)
    }

    @Test
    fun withTheVoiceOnTheToneAndTheVoiceEachHaveASlider() {
        compose.mainClock.autoAdvance = false
        // A tone volume chosen before the voice had one of its own: the voice starts there.
        BreatheController(context, loadVoice = { null }).chooseVolume(0.6f)
        val controller = BreatheController(context, loadVoice = { null }) { nanos() }
        assertEquals(0.6f, controller.voiceVolume, 1e-6f)
        controller.chooseVoice(true)
        controller.chooseCycles(2)
        controller.chooseSound(SoundMode.SILENT) // and no clips: no audio thread under the test clock
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
        compose.runOnUiThread { controller.begin() }
        compose.mainClock.advanceTimeBy(5_000)

        compose.onNodeWithContentDescription("Volume, tone 60%, voice 60%").performClick()
        compose.mainClock.advanceTimeBy(200)
        val tone = compose.onNodeWithContentDescription("Tone volume")
        val voice = compose.onNodeWithContentDescription("Voice volume")
        tone.assertIsDisplayed()
        voice.assertIsDisplayed()
        // Each moves only its own.
        voice.performSemanticsAction(SemanticsActions.SetProgress) { it(0.3f) }
        compose.mainClock.advanceTimeBy(100)
        assertEquals(0.3f, controller.voiceVolume, 1e-6f)
        assertEquals(0.6f, controller.volume, 1e-6f)
        tone.performSemanticsAction(SemanticsActions.SetProgress) { it(0.8f) }
        compose.mainClock.advanceTimeBy(100)
        assertEquals(0.8f, controller.volume, 1e-6f)
        assertEquals(0.3f, controller.voiceVolume, 1e-6f)
        compose.onNodeWithContentDescription("Volume, tone 80%, voice 30%").assertIsDisplayed()

        // Each is kept for next time.
        val next = BreatheController(context, loadVoice = { null })
        assertEquals(0.3f, next.voiceVolume, 1e-6f)
        assertEquals(0.8f, next.volume, 1e-6f)
    }

    @Test
    fun theSliderClosesWhenLeftAloneOrTappedAway() {
        val controller = startSession()
        compose.onNodeWithContentDescription("Volume, 100%").performClick()
        compose.mainClock.advanceTimeBy(200)
        compose.onNodeWithContentDescription("Volume").assertIsDisplayed()
        compose.mainClock.advanceTimeBy(3_600)
        compose.onNodeWithContentDescription("Volume").assertDoesNotExist()

        // A tap elsewhere closes it, and only that: the session carries on unpaused.
        compose.onNodeWithContentDescription("Volume, 100%").performClick()
        compose.mainClock.advanceTimeBy(200)
        compose.onNodeWithContentDescription("Volume").assertIsDisplayed()
        compose.onRoot().performTouchInput { click(Offset(centerX, centerY)) }
        compose.mainClock.advanceTimeBy(200)
        compose.onNodeWithContentDescription("Volume").assertDoesNotExist()
        assertFalse(controller.isPaused)
        assertEquals(Screen.SESSION, controller.screen)
    }

    @Test
    fun backClosesTheSliderBeforeAskingToEnd() {
        val controller = startSession()
        compose.onNodeWithContentDescription("Volume, 100%").performClick()
        compose.mainClock.advanceTimeBy(200)
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.mainClock.advanceTimeBy(200)
        compose.onNodeWithContentDescription("Volume").assertDoesNotExist()
        compose.onNodeWithText("End session").assertDoesNotExist()
        assertEquals(Screen.SESSION, controller.screen)
        // With it closed, Back asks to end as before.
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }
        compose.mainClock.advanceTimeBy(100)
        compose.onNodeWithText("End session").assertIsDisplayed()
    }

    @Test
    fun theVolumeStaysBetweenNothingAndFull() {
        val controller = BreatheController(context) { 0L }
        assertEquals(1f, controller.volume, 1e-6f)
        controller.chooseVolume(1.5f)
        assertEquals(1f, controller.volume, 1e-6f)
        controller.chooseVolume(-0.2f)
        assertEquals(0f, controller.volume, 1e-6f)
    }
}
