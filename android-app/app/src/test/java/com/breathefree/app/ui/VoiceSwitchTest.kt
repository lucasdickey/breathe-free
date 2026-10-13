package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.core.VoiceClips
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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * "Voice guidance" on the home screen: off until chosen, kept for next time, and the
 * prompts are decoded once, off the main thread, as soon as it is switched on.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class VoiceSwitchTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))
    private val context get() = ApplicationProvider.getApplicationContext<Context>()

    private val decoded = AtomicInteger()
    private val ready = CountDownLatch(1)
    private val clips = VoiceClips(48_000, FloatArray(4_800), FloatArray(4_800), FloatArray(4_800))

    private fun loader(): (Context) -> VoiceClips? = {
        decoded.incrementAndGet()
        ready.countDown()
        clips
    }

    private fun switchState(on: Boolean) =
        SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, if (on) "On" else "Off")

    @Test
    fun speakingIsOffUntilChosenThenKept() {
        val controller = BreatheController(context, loadVoice = loader()) { 0L }
        compose.mainClock.autoAdvance = false // the orb and the sky never stop moving
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(500)
        val row = compose.onNodeWithText("Voice guidance")
        row.assert(switchState(false))
        assertFalse(controller.voiceOn)
        assertEquals("nothing decoded while it is off", 0, decoded.get())

        row.performClick()
        compose.mainClock.advanceTimeBy(100)
        row.assert(switchState(true))
        assertTrue(controller.voiceOn)
        assertTrue("decoded once switched on", ready.await(5, TimeUnit.SECONDS))

        // Kept: the next start of the app has it on, and decodes the prompts straight away.
        val next = BreatheController(context, loadVoice = loader()) { 0L }
        assertTrue(next.voiceOn)
        val until = System.nanoTime() + 5_000_000_000L
        while (decoded.get() < 2 && System.nanoTime() < until) Thread.sleep(10)
        assertEquals(2, decoded.get())

        // And off again.
        row.performClick()
        compose.mainClock.advanceTimeBy(100)
        row.assert(switchState(false))
        assertFalse(BreatheController(context, loadVoice = loader()) { 0L }.voiceOn)
    }

    @Test
    fun vibratingIsStillItsOwnSwitch() {
        val controller = BreatheController(context, loadVoice = loader()) { 0L }
        compose.mainClock.autoAdvance = false
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(500)
        val before = controller.hapticsOn
        compose.onNodeWithText("Vibrate at each change").performClick()
        compose.mainClock.advanceTimeBy(100)
        assertEquals(!before, controller.hapticsOn)
        assertFalse(controller.voiceOn)
    }
}
