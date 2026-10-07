package com.breathefree.app

import com.breathefree.app.core.SessionPlan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveSessionTest {
    private fun s(seconds: Double) = (seconds * 1e9).toLong()

    @Test
    fun pausedTimeStandsStill() {
        val running = ActiveSession(SessionPlan(2), s(100.0))
        assertFalse(running.isPaused)
        assertEquals(10.0, running.timeAt(s(110.0)), 1e-9)
        val held = running.pausedAt(s(110.0))
        assertTrue(held.isPaused)
        for (now in listOf(110.0, 111.0, 140.0, 10_000.0)) {
            assertEquals(10.0, held.timeAt(s(now)), 1e-9)
        }
    }

    @Test
    fun resumingCarriesOnFromTheMomentItStopped() {
        val plan = SessionPlan(2)
        val held = ActiveSession(plan, s(100.0)).pausedAt(s(113.25)) // 13.25 s in
        val resumed = held.resumedAt(s(400.0))
        assertFalse(resumed.isPaused)
        assertEquals(13.25, resumed.timeAt(s(400.0)), 1e-9)
        assertEquals(14.75, resumed.timeAt(s(401.5)), 1e-9)
        // The picture carries on from the same breath: same phase, same level, no jump.
        val before = plan.frameAt(held.timeAt(s(399.0)))
        val after = plan.frameAt(resumed.timeAt(s(400.0)))
        assertEquals(before.phaseIndex, after.phaseIndex)
        assertEquals(before.level, after.level, 1e-9)
        assertEquals(before.countdown, after.countdown)
    }

    @Test
    fun pausesAddUp() {
        var session = ActiveSession(SessionPlan(3), 0L)
        session = session.pausedAt(s(10.0)).resumedAt(s(30.0)) // 20 s away
        assertEquals(15.0, session.timeAt(s(35.0)), 1e-9)
        session = session.pausedAt(s(35.0)).resumedAt(s(95.0)) // another 60 s away
        assertEquals(15.0, session.timeAt(s(95.0)), 1e-9)
        assertEquals(20.0, session.timeAt(s(100.0)), 1e-9)
    }

    @Test
    fun pausingTwiceOrResumingARunningSessionChangesNothing() {
        val running = ActiveSession(SessionPlan(2), s(50.0))
        assertSame(running, running.resumedAt(s(70.0)))
        val held = running.pausedAt(s(60.0))
        assertSame(held, held.pausedAt(s(90.0)))
        // A clock that reads earlier than the pause never moves the session backwards.
        assertEquals(10.0, held.resumedAt(s(55.0)).timeAt(s(55.0)), 1e-9)
    }
}
