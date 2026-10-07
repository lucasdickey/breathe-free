package com.breathefree.app.ui

import android.content.Context
import android.graphics.Bitmap
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.core.app.ApplicationProvider
import com.breathefree.app.BreatheController
import com.breathefree.app.core.SoundMode
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Renders the frames of the 30-second promo (promo/README.md) from the real app, following
 * promo/script.json: the home screen while the sky sweeps from morning to night, session
 * length fanning out and a count being picked, Begin, then a whole breathing cycle at its true
 * pace. Writes JPEG frames and where the taps landed to build/promo/android.
 * Run with: ./gradlew testDebugUnitTest -Ppromo --tests '*PromoTest*'
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w400dp-h860dp-xhdpi")
class PromoTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun onlyWhenAsked() {
        assumeTrue("pass -Ppromo to render the promo", System.getProperty("promo") == "true")
    }

    @Test
    fun frames() {
        val script = JSONObject(File("../../promo/script.json").readText())
        val fps = script.getInt("fps")
        val frames = (script.getDouble("seconds") * fps).toInt()
        val zone = ZoneId.of(script.getString("zone"))
        val midnight = LocalDate.parse(script.getString("date")).atStartOfDay(zone)
        val sweep = script.getJSONObject("sweep")
        val cycles = script.getJSONObject("cycles")
        val taps = script.getJSONObject("taps")
        val lag = script.getJSONObject("session").getDouble("lagSeconds")
        val out = File("build/promo/android").apply {
            deleteRecursively()
            mkdirs()
        }

        val context = ApplicationProvider.getApplicationContext<Context>()
        compose.mainClock.autoAdvance = false
        val controller = BreatheController(context) { compose.mainClock.currentTime * 1_000_000L }
        controller.chooseCycles(cycles.getInt("before"))
        controller.chooseSound(SoundMode.AMBIENT)

        // The sky's time of day eases from morning to night across the opening seconds.
        fun hourAt(v: Double): Double {
            val x = ((v - sweep.getDouble("start")) / (sweep.getDouble("end") - sweep.getDouble("start"))).coerceIn(0.0, 1.0)
            val eased = x * x * (3 - 2 * x)
            return sweep.getDouble("fromHour") + (sweep.getDouble("toHour") - sweep.getDouble("fromHour")) * eased
        }
        var hour = hourAt(0.0)
        compose.setContent { BreatheApp(controller) { midnight.plusSeconds((hour * 3600).roundToLong()) } }

        // Robolectric has no system bars. Give the app a phone's, a status bar with a camera hole
        // and a gesture bar, so it lays itself out below them as it does on a device.
        val density = context.resources.displayMetrics.density
        val statusBar = (STATUS_BAR_DP * density).roundToInt()
        val navigationBar = (NAVIGATION_BAR_DP * density).roundToInt()
        val bars = WindowInsetsCompat.Builder()
            .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, statusBar, 0, 0))
            .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, navigationBar))
            .build()
        compose.runOnIdle {
            val content = compose.activity.findViewById<ViewGroup>(android.R.id.content)
            ViewCompat.dispatchApplyWindowInsets(content.getChildAt(0), bars)
        }
        compose.mainClock.advanceTimeByFrame()

        val events = JSONArray()
        fun tap(name: String, node: SemanticsNodeInteraction, v: Double) {
            val bounds = node.fetchSemanticsNode().boundsInRoot
            events.put(JSONObject().put("name", name).put("v", v).put("x", bounds.center.x).put("y", bounds.center.y))
            node.performClick()
        }
        fun startsWith(prefix: String) = SemanticsMatcher("description starts with \"$prefix\"") { node ->
            node.config.getOrNull(SemanticsProperties.ContentDescription)?.any { it.startsWith(prefix) } == true
        }

        val start = compose.mainClock.currentTime
        var begun = -1L
        var opened = false
        var picked = false
        // The app draws each frame for the moment it reaches the glass, two refreshes ahead.
        val displayLeadMs = 2_000L / 60
        for (k in 0 until frames) {
            val v = k.toDouble() / fps
            hour = hourAt(v)
            val target = if (begun < 0) {
                start + (v * 1000).roundToLong()
            } else {
                begun + LEAD_MS + ((v - lag) * 1000).roundToLong() - displayLeadMs
            }
            compose.mainClock.advanceTimeBy(target - compose.mainClock.currentTime)

            if (!opened && v >= taps.getDouble("open")) {
                opened = true
                tap("open", compose.onNode(startsWith("Session length")), v)
            }
            if (!picked && v >= taps.getDouble("pick")) {
                picked = true
                tap("pick", compose.onNode(startsWith("${cycles.getInt("picked")} cycles,")), v)
            }
            if (begun < 0 && v >= taps.getDouble("begin")) {
                tap("begin", compose.onNodeWithText("Begin"), v)
                begun = compose.mainClock.currentTime
                // Straight on to this frame's moment in the session (an edit, like a cut).
                compose.mainClock.advanceTimeBy(begun + LEAD_MS + ((v - lag) * 1000).roundToLong() - displayLeadMs - compose.mainClock.currentTime)
            }

            compose.waitForIdle()
            val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
            File(out, "f%05d.jpg".format(k)).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 93, it) }
            if (k == 0) {
                File(out, "size.json").writeText(
                    JSONObject().put("w", bitmap.width).put("h", bitmap.height)
                        .put("statusBar", statusBar).put("navigationBar", navigationBar).toString(),
                )
            }
        }
        File(out, "taps.json").writeText(events.toString(2))
        println("wrote $frames frames to ${out.absolutePath}")
    }

    private companion object {
        /** BreatheController's lead between Begin and the session's first moment. */
        const val LEAD_MS = 350L

        /** A phone's status bar with a camera hole, and its gesture bar. */
        const val STATUS_BAR_DP = 32f
        const val NAVIGATION_BAR_DP = 24f
    }
}
