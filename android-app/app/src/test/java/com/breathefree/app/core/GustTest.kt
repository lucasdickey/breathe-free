package com.breathefree.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot

class GustTest {
    private val plan = SessionPlan(2)
    private val out = FloatArray(3)

    /** A phone 400 dp wide at 3 pixels to the dp, as in the screenshots. */
    private val unit = 3f
    private val reach = 1200f

    private fun at(tx: Float, ty: Float, along: Float, seed: Int, arrive: Double, leave: Double, t: Double = 10.0): FloatArray {
        Gust.place(tx, ty, along, seed, arrive, leave, reach, unit, 0.0, t, out)
        return out.copyOf()
    }

    @Test
    fun theWindTakesEachWordAsItBringsTheNext() {
        // Mid-phase: the inhale's words are settled and the settle's are long gone.
        val mid = plan.gustAt(10.0)
        assertEquals("Breathe in", mid.arriving)
        assertEquals("Settle in", mid.leaving)
        assertTrue(mid.leaveSince > Gust.GONE)

        // Just before the hold: "Breathe in" has begun to leave and "Hold" is not yet on its way.
        val change = plan.phaseStart(1)
        val between = (Gust.LEAVE_LEAD + Gust.ARRIVE_LEAD) / 2
        val before = plan.gustAt(change - between)
        assertEquals("", before.arriving)
        assertEquals("Breathe in", before.leaving)
        assertEquals(Gust.LEAVE_LEAD - between, before.leaveSince, 1e-9)

        // Then "Hold" comes on the same gust.
        val after = plan.gustAt(change - Gust.ARRIVE_LEAD + 0.1)
        assertEquals("Hold", after.arriving)
        assertEquals(0.1, after.arriveSince, 1e-9)
        assertEquals("Breathe in", after.leaving)

        // At the end the last hold blows away and nothing comes.
        val end = plan.gustAt(plan.endTime + 0.5)
        assertEquals("", end.arriving)
        assertEquals("Hold", end.leaving)
    }

    @Test
    fun noWordIsInTheAirTwice() {
        // At every moment the arriving and leaving words are different words of the session,
        // or one of them is nothing.
        var t = 0.0
        while (t < plan.endTime + 3) {
            val g = plan.gustAt(t)
            val same = g.arriving.isNotEmpty() && g.arriving == g.leaving && g.leaveSince < Gust.GONE
            assertTrue("at $t: $g", !same)
            t += 0.01
        }
    }

    @Test
    fun eachWordHasLandedSoonAfterItsPhaseBegins() {
        assertTrue(Gust.ARRIVED - Gust.ARRIVE_LEAD < 1.0)
        for (seed in 0 until 500) {
            val along = (seed % 11) / 10f
            val p = at(40f, -20f, along, seed, Gust.ARRIVED, -1.0)
            // Where it belongs, give or take the shimmer of a settled speck.
            assertEquals(40f, p[0], 0.3f * unit)
            assertEquals(-20f, p[1], 0.3f * unit)
            assertEquals(1f, p[2], 1e-6f)
        }
    }

    @Test
    fun theWindComesFromTheLeftAndGoesOffToTheRight() {
        for (seed in 0 until 500) {
            val start = at(0f, 0f, 0.5f, seed, 0.0, -1.0)
            assertTrue(start[0] < -0.5f * reach)
            assertEquals(0f, start[2], 1e-6f)
            val gone = at(0f, 0f, 0.5f, seed, Gust.ARRIVED + 1, Gust.GONE)
            assertTrue(gone[0] > 0.45f * reach)
            assertEquals(0f, gone[2], 1e-6f)
        }
    }

    @Test
    fun theLeftEndOfAWordLandsFirst() {
        fun landed(along: Float, seed: Int): Double {
            var s = 0.0
            while (abs(at(0f, 0f, along, seed, s, -1.0)[0]) > 2 * unit) s += 0.005
            return s
        }
        val left = (0 until 200).map { landed(0f, it) }.average()
        val right = (0 until 200).map { landed(1f, it) }.average()
        assertTrue("left $left, right $right", right - left > 0.2)
    }

    @Test
    fun theSpecksKeepClearOfTheBox() {
        // The box's lowest edge is 58 dp above the words' centre; the dot's glow reaches 16 dp
        // below that. A speck from the top of a letter never rises past 42 dp.
        val top = -16f * unit
        for (seed in 0 until 300) {
            var s = 0.0
            while (s < Gust.ARRIVED) {
                val p = at(0f, top, (seed % 5) / 4f, seed, s, -1.0, t = s)
                assertTrue("seed $seed at $s: ${p[1] / unit} dp", p[1] > -42f * unit)
                s += 0.01
            }
            s = 0.0
            while (s < Gust.GONE) {
                val p = at(0f, top, (seed % 5) / 4f, seed, Gust.ARRIVED + 1, s, t = s)
                assertTrue("seed $seed leaving at $s: ${p[1] / unit} dp", p[1] > -42f * unit)
                s += 0.01
            }
        }
    }

    @Test
    fun noSpeckJumps() {
        // Frame to frame at 120 Hz, from blowing in through settling to blowing away, each
        // speck moves smoothly: never more than the wind's top speed allows in one frame.
        val frame = 1.0 / 120
        for (seed in 0 until 200) {
            var last: FloatArray? = null
            var s = 0.0
            while (s < Gust.ARRIVED + 1 + Gust.GONE) {
                val leave = s - (Gust.ARRIVED + 1)
                val p = at(0f, 0f, 0.5f, seed, s, leave, t = s)
                last?.let { assertTrue("seed $seed at $s", hypot(p[0] - it[0], p[1] - it[1]) < 0.06f * reach) }
                last = p
                s += frame
            }
        }
    }

    @Test
    fun luckIsTheSameEachTimeAndSpreadEvenly() {
        assertEquals(Gust.luck(7, 3), Gust.luck(7, 3))
        val draws = (0 until 10_000).map { Gust.luck(it, 1) }
        assertTrue(draws.all { it in 0f..1f })
        assertEquals(0.5, draws.average(), 0.02)
        assertTrue(draws.count { it < 0.1f } in 800..1200)
    }
}
