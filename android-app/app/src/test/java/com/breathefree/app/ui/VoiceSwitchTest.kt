package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
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
 * "Voice guidance", in the settings fan: on from the first start, with the prompts decoded
 * once, off the main thread, straight away; switched off and on again in the fan, and kept for
 * next time either way.
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

    @Test
    fun speakingIsOnUntilSwitchedOffAndKeptEitherWay() {
        val controller = BreatheController(context, loadVoice = loader()) { 0L }
        assertTrue(controller.voiceOn)
        assertTrue("decoded straight away", ready.await(5, TimeUnit.SECONDS))
        compose.mainClock.autoAdvance = false // the orb and the sky never stop moving
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(500)
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.mainClock.advanceTimeBy(800)
        val voice = compose.onNodeWithContentDescription("Voice guidance")
        voice.assertIsOn()

        voice.performClick()
        compose.mainClock.advanceTimeBy(100)
        voice.assertIsOff()
        assertFalse(controller.voiceOn)
        // Kept: the next start of the app has it off, and decodes nothing.
        assertFalse(BreatheController(context, loadVoice = loader()) { 0L }.voiceOn)
        assertEquals(1, decoded.get())

        // On again, kept too: the next start decodes the prompts straight away.
        voice.performClick()
        compose.mainClock.advanceTimeBy(100)
        voice.assertIsOn()
        assertTrue(controller.voiceOn)
        assertTrue(BreatheController(context, loadVoice = loader()) { 0L }.voiceOn)
        val until = System.nanoTime() + 5_000_000_000L
        while (decoded.get() < 2 && System.nanoTime() < until) Thread.sleep(10)
        assertEquals(2, decoded.get())
    }
}
