package com.breathefree.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import com.breathefree.app.core.Gust
import com.breathefree.app.core.Phase
import com.breathefree.app.core.SessionPlan
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The words' specks blow in and out under the box, never across it: measured on the real words,
 * sampled in the screen's own face, every speck followed through its whole gust.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xxhdpi")
class WindClearanceTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** The session's words, as SessionScreen sets them. */
    private val style = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Light, letterSpacing = 0.5.sp)
    private val words = listOf(SessionPlan.SETTLE_PROMPT) + Phase.entries.map { it.prompt }.distinct()

    /** The words' centre sits 58 dp under the box's bottom edge (SessionScreen's promptY). */
    private val boxEdge = -58f

    /** The dot's glow reaches 16 dp below that edge while the dot runs along the bottom. */
    private val glowEdge = boxEdge + 16f

    private class Reach(val settledTop: Float, val windTop: Float)

    /** For each of [fontScales]: how high, in dp above the words' centre, the letters sit once settled, and the highest any speck goes. */
    private fun reach(vararg fontScales: Float): List<Reach> {
        val set = arrayOfNulls<Pair<TextMeasurer, Density>>(fontScales.size)
        compose.setContent {
            val screen = LocalDensity.current
            fontScales.forEachIndexed { k, scale ->
                CompositionLocalProvider(LocalDensity provides Density(screen.density, scale)) {
                    set[k] = rememberTextMeasurer() to LocalDensity.current
                }
            }
        }
        compose.waitForIdle()
        return set.map { reach(it!!.first, it.second) }
    }

    private fun reach(measurer: TextMeasurer, density: Density): Reach {
        val wind = WindWords(measurer, style, density)
        val unit = density.density
        val reach = 400f * unit
        val room = 200f * unit
        val out = FloatArray(3)
        var settled = 0f
        var top = 0f
        val frame = 1.0 / 120
        for (word in words) {
            val s = wind.specks(word)
            for (i in 0 until s.size) {
                // Full lungs, the word at its largest.
                settled = minOf(settled, s.ys[i] * (1f + Gust.SWELL.toFloat()))
                var a = 0.0
                while (a <= Gust.ARRIVED) {
                    Gust.place(s.xs[i], s.ys[i], s.along[i], i, a, -1.0, reach, room, unit, 1.0, 8.0 + a, out)
                    if (out[2] > 0.02f) top = minOf(top, out[1])
                    a += frame
                }
                var l = 0.0
                while (l <= Gust.GONE) {
                    Gust.place(s.xs[i], s.ys[i], s.along[i], i, Gust.ARRIVED + 1, l, reach, room, unit, 1.0, 11.2 + l, out)
                    if (out[2] > 0.02f) top = minOf(top, out[1])
                    l += frame
                }
            }
        }
        return Reach(settled / unit, top / unit)
    }

    @Test
    fun theWindPassesUnderTheBox() {
        // At the default text size and with larger text set in Android's settings.
        val scales = floatArrayOf(1f, 1.3f, 2f)
        for ((scale, r) in scales.zip(reach(*scales))) {
            println("font scale $scale: letters' top ${r.settledTop} dp, highest speck ${r.windTop} dp; box edge $boxEdge, dot glow $glowEdge")
            assertTrue("at font scale $scale a speck reaches ${r.windTop} dp, into the dot's glow at $glowEdge", r.windTop > glowEdge)
        }
    }
}
