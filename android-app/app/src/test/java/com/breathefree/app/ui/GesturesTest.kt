package com.breathefree.app.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.Screen
import com.breathefree.app.core.SoundMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.ZoneId
import java.time.ZonedDateTime

/** The session length slid with one finger, and the orb pulled about, on the real home screen. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class GesturesTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val noon = ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, ZoneId.of("America/Los_Angeles"))

    private fun home(cycles: Int): BreatheController {
        val context = ApplicationProvider.getApplicationContext<Context>()
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { compose.mainClock.currentTime * 1_000_000L }
        controller.chooseCycles(cycles)
        controller.chooseSound(SoundMode.SILENT)
        controller.chooseVoice(false)
        compose.setContent { BreatheApp(controller) { noon } }
        compose.mainClock.advanceTimeBy(1_000)
        return controller
    }

    /** One drop along the session-length row: a 48 dp drop and the 8 dp between. */
    private val step = 56.dp

    /**
     * Opens the session length and slides it from the chosen drop, [chosen] cycles, by [by]
     * steps, in [moves] moves, without lifting.
     */
    private fun slide(chosen: Int, by: Float, moves: Int = 12, frameMs: Long = 16) {
        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(700)
        val drop = compose.onNode(
            SemanticsMatcher("is $chosen cycles") {
                it.config.getOrNull(SemanticsProperties.ContentDescription)?.firstOrNull()?.startsWith("$chosen cycles,") == true
            },
        ).getBoundsInRoot()
        val px = with(compose.density) { step.toPx() } * by
        val at = with(compose.density) { Offset(((drop.left + drop.right) / 2).toPx(), ((drop.top + drop.bottom) / 2).toPx()) }
        compose.onRoot().performTouchInput {
            down(at)
            repeat(moves) { moveBy(Offset(px / moves, 0f), delayMillis = frameMs) }
        }
    }

    private fun letGo() {
        compose.onRoot().performTouchInput { up() }
    }

    @Test
    fun slidingTheSessionLengthPicksWhereItIsLetGo() {
        val controller = home(6)
        slide(6, 2.2f, frameMs = 40)
        compose.mainClock.advanceTimeBy(300)
        letGo()
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(20, controller.cycles)
        compose.onNodeWithContentDescription("Session length: 20 cycles", substring = true).assertExists()
    }

    @Test
    fun aFlickCarriesOnToTheDropItWasHeadingFor() {
        val controller = home(6)
        // Fast: 1.6 drops in a tenth of a second, let go mid-move.
        slide(6, 1.6f, moves = 6)
        letGo()
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(36, controller.cycles)
    }

    @Test
    fun pastTheLastDropItHoldsBackAndPicksTheLast() {
        val controller = home(36)
        slide(36, 4f, frameMs = 40)
        compose.mainClock.advanceTimeBy(300)
        letGo()
        compose.mainClock.advanceTimeBy(1_000)
        assertEquals(50, controller.cycles)
    }

    @Test
    fun foldedASlideOnlyOpensIt() {
        val controller = home(6)
        val drop = compose.onNodeWithContentDescription("Session length", substring = true).getBoundsInRoot()
        val at = with(compose.density) { Offset(((drop.left + drop.right) / 2).toPx(), ((drop.top + drop.bottom) / 2).toPx()) }
        compose.onRoot().performTouchInput {
            down(at)
            moveBy(Offset(30f, 0f))
            up()
        }
        compose.mainClock.advanceTimeBy(700)
        assertEquals(6, controller.cycles)
        compose.onNodeWithContentDescription("10 cycles,", substring = true).assertExists()
    }

    @Test
    fun aTapStillOpensTheRowAndATapPicks() {
        val controller = home(6)
        compose.onNodeWithContentDescription("Session length", substring = true).performClick()
        compose.mainClock.advanceTimeBy(700)
        compose.onNodeWithContentDescription("10 cycles,", substring = true).performClick()
        compose.mainClock.advanceTimeBy(700)
        assertEquals(10, controller.cycles)
    }

    @Test
    fun pullingTheOrbPressesNothingElse() {
        val controller = home(6)
        val title = compose.onNodeWithText("Breathe Free").getBoundsInRoot()
        val orb = with(compose.density) { Offset(((title.left + title.right) / 2).toPx(), (title.top - 8.dp - 66.dp).toPx()) }
        compose.onRoot().performTouchInput {
            down(orb)
            moveBy(Offset(0f, 900f))
        }
        compose.mainClock.advanceTimeBy(100)
        compose.onRoot().performTouchInput { up() }
        compose.mainClock.advanceTimeBy(1_500)
        assertEquals(Screen.HOME, controller.screen)
        assertEquals(6, controller.cycles)
    }
}
