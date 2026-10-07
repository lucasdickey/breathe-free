package com.breathefree.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

class BreathTimelineTest {
    private val plan = SessionPlan(2)

    @Test
    fun theWordsFollowTheBox() {
        val plan = SessionPlan(2)
        val seen = listOf(0.0, 3.0, 8.1, 12.2, 16.05, 20.0, 24.0, 39.9, 40.0, 41.0).map { plan.promptAt(it) }
        assertEquals(
            listOf(
                "Settle in" to "", "Settle in" to "", "Breathe in" to "Settle in", "Hold" to "Breathe in",
                "Breathe out" to "Hold", "Hold" to "Breathe out", "Breathe in" to "Hold", "Hold" to "Breathe out",
                "" to "Hold", "" to "Hold",
            ),
            seen.map { it.text to it.previous },
        )
        assertEquals(0.2, plan.promptAt(12.2).since, 1e-9)
    }

    @Test
    fun theWordsCrossWithoutAFlash() {
        // At every change, what was fully showing just before is what starts fading out, and
        // the new words start from nothing: the screen goes straight from one to the other.
        val plan = SessionPlan(3)
        for (i in 0..plan.phaseCount) {
            val change = if (i < plan.phaseCount) plan.phaseStart(i) else plan.endTime
            val before = plan.promptAt(change - 1e-6)
            val after = plan.promptAt(change)
            assertEquals(1.0, before.fade, 1e-9)
            assertEquals(before.text, after.previous)
            assertEquals(0.0, after.fade, 1e-9)
        }
        // And the cross is smooth and done in a third of a second.
        var last = -1.0
        for (n in 0..40) {
            val fade = Prompt("Hold", "Breathe in", n * 0.01).fade
            assertTrue(fade >= last)
            last = fade
        }
        assertEquals(1.0, Prompt("Hold", "Breathe in", Prompt.FADE_SECONDS).fade, 1e-12)
    }

    @Test
    fun settleCountsDownFromEight() {
        val start = plan.frameAt(0.0)
        assertEquals(Stage.SETTLE, start.stage)
        assertNull(start.phase)
        assertEquals(8, start.countdown)
        assertEquals(8, plan.frameAt(0.5).countdown)
        assertEquals(7, plan.frameAt(1.0).countdown)
        assertEquals(1, plan.frameAt(7.999).countdown)
        assertEquals(0.0, plan.frameAt(7.999).level, 0.0)
    }

    @Test
    fun phasesTurnOnTheBoundaries() {
        val expected = listOf(
            8.0 to Phase.INHALE, 12.0 to Phase.HOLD_FULL, 16.0 to Phase.EXHALE,
            20.0 to Phase.HOLD_EMPTY, 24.0 to Phase.INHALE, 36.0 to Phase.HOLD_EMPTY,
        )
        for ((t, phase) in expected) {
            val f = plan.frameAt(t)
            assertEquals("phase at $t", phase, f.phase)
            assertEquals("countdown at $t", 4, f.countdown)
            assertEquals("elapsed at $t", 0.0, f.phaseElapsed, 1e-12)
        }
        assertEquals(Phase.INHALE, plan.frameAt(11.999).phase)
        assertEquals(1, plan.frameAt(11.999).countdown)
        assertEquals(3, plan.frameAt(13.0).countdown)
        assertEquals(1, plan.frameAt(24.0).cycle)
    }

    @Test
    fun levelFollowsTheBox() {
        assertEquals(0.0, plan.frameAt(8.0).level, 1e-12)
        assertEquals(1.0, plan.frameAt(12.0).level, 1e-12)
        assertEquals(1.0, plan.frameAt(15.9).level, 1e-12)
        assertEquals(1.0, plan.frameAt(16.0).level, 1e-12)
        assertEquals(0.0, plan.frameAt(20.0).level, 1e-12)
        assertTrue(plan.frameAt(10.0).level in 0.4..0.7)
    }

    @Test
    fun levelNeverJumps() {
        var last = plan.frameAt(0.0).level
        var worst = 0.0
        var t = 0.0
        while (t < plan.endTime + 2) {
            val l = plan.frameAt(t).level
            worst = max(worst, abs(l - last))
            last = l
            t += 0.001
        }
        // At 1 ms steps the fastest part of a 4 s breath moves well under 0.1%.
        assertTrue("largest step $worst", worst < 0.001)
    }

    @Test
    fun endsExactlyAfterTheLastHold() {
        assertEquals(40.0, plan.endTime, 0.0)
        val last = plan.frameAt(39.999)
        assertEquals(Stage.BREATHING, last.stage)
        assertEquals(Phase.HOLD_EMPTY, last.phase)
        assertEquals(1, last.cycle)
        val done = plan.frameAt(40.0)
        assertEquals(Stage.COMPLETE, done.stage)
        assertEquals(0.0, done.remaining, 0.0)
        assertEquals(32.0, plan.frameAt(8.0).remaining, 1e-12)
        assertEquals(30.5, plan.frameAt(9.5).remaining, 1e-12)
    }

    @Test
    fun boxSidesJoinUpAndStayOnTheOutline() {
        val h = 100.0
        val r = 18.0
        val a = DoubleArray(2)
        val b = DoubleArray(2)
        for (side in 0 until 4) {
            BoxGeometry.point(side, 1.0, 0.0, 0.0, h, r, a)
            BoxGeometry.point(side + 1, 0.0, 0.0, 0.0, h, r, b)
            assertEquals("x join $side", a[0], b[0], 1e-9)
            assertEquals("y join $side", a[1], b[1], 1e-9)
        }
        // Inhale runs up the left edge, so screen y decreases as f grows.
        BoxGeometry.point(0, 0.5, 0.0, 0.0, h, r, a)
        assertEquals(-h, a[0], 1e-9)
        assertEquals(0.0, a[1], 1e-9)
        BoxGeometry.point(1, 0.5, 0.0, 0.0, h, r, a)
        assertEquals(0.0, a[0], 1e-9)
        assertEquals(-h, a[1], 1e-9)
        // Every point is on the rounded square: on an edge, or exactly r from a corner centre.
        for (side in 0 until 4) {
            var f = 0.0
            while (f <= 1.0) {
                BoxGeometry.point(side, f, 0.0, 0.0, h, r, a)
                val x = abs(a[0])
                val y = abs(a[1])
                val onEdge = (abs(x - h) < 1e-9 && y <= h - r + 1e-9) || (abs(y - h) < 1e-9 && x <= h - r + 1e-9)
                val onCorner = abs(hypot(x - (h - r), y - (h - r)) - r) < 1e-9 && x > h - r - 1e-9 && y > h - r - 1e-9
                assertTrue("off outline at side $side f $f: $x,$y", onEdge || onCorner)
                f += 0.01
            }
        }
    }

    @Test
    fun dotFollowsTheBreath() {
        val f = plan.frameAt(10.0)
        assertEquals(0, f.boxSide())
        assertEquals(f.level, f.boxFraction(), 1e-12)
        val hold = plan.frameAt(14.0)
        assertEquals(1, hold.boxSide())
        assertEquals(0.5, hold.boxFraction(), 1e-12)
        val out = plan.frameAt(18.0)
        assertEquals(2, out.boxSide())
        assertEquals(1.0 - out.level, out.boxFraction(), 1e-12)
    }
}
