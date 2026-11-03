package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.core.SessionPlan
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
 * What TalkBack hears from the session length: each length said once, in words, with the
 * count in the drop not read again, and the chosen one marked when the row is open.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class SessionLengthTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))

    private fun home(cycles: Int) {
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(ApplicationProvider.getApplicationContext<Context>()) {
            compose.mainClock.currentTime * 1_000_000L
        }
        controller.chooseCycles(cycles)
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
    }

    @Test
    fun theDropSaysItsLengthOnceAndWhatAPressDoes() {
        home(6)
        val drop = compose.onNodeWithContentDescription("Session length: 6 cycles, 1 minute 36 seconds")
        drop.assertHasClickAction()
        val said = drop.fetchSemanticsNode().config
        assertFalse(SemanticsProperties.Text in said)
        assertEquals("change", said[SemanticsActions.OnClick].label)
        compose.onAllNodesWithText("6", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test
    fun openEachLengthIsSaidOnceAndTheChosenOneIsMarked() {
        home(6)
        compose.onNodeWithContentDescription("Session length:", substring = true).performClick()
        compose.mainClock.advanceTimeBy(1_500)
        for (n in SessionPlan.CYCLE_CHOICES) {
            val drop = compose.onNodeWithContentDescription("$n cycles, ${spokenClock(n * SessionPlan.CYCLE_SECONDS.toInt())}")
            drop.assertHasClickAction()
            if (n == 6) drop.assertIsSelected() else drop.assertIsNotSelected()
            assertFalse(SemanticsProperties.Text in drop.fetchSemanticsNode().config)
        }
        compose.onNodeWithContentDescription("6 cycles, 1 minute 36 seconds").assertHasClickAction()
    }
}
