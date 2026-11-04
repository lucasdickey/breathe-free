package com.breathefree.app.ui

import com.breathefree.app.core.SessionPlan
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class DripTest {
    @Test
    fun nothingHangsAtFirst() {
        val f = Drip.at(1.0)
        assertNull(f.hanging)
        assertNull(f.drop)
        assertEquals(0.0, f.orb, 0.0)
        assertEquals(0f, Drip.countAlpha(1.0))
    }

    @Test
    fun theDropFallsFromWhereItLetGo() {
        // The last moment it hangs and the first moment it falls are the same drop, in the same place.
        val hanging = Drip.at(4.15 - 1e-6).hanging!!
        val falling = Drip.at(4.15).drop!!
        assertEquals(hanging.by, falling.y, 1e-4)
        assertEquals(hanging.rb, falling.r, 1e-4)
    }

    @Test
    fun itLandsInTheMiddleAsTheOrb() {
        val before = Drip.at(Drip.LANDS - 1e-6)
        assertTrue(abs(before.drop!!.y) < 1e-4)
        val landed = Drip.at(Drip.LANDS)
        assertNull(landed.drop)
        assertEquals(before.drop!!.r, landed.orb, 1e-9)
        assertEquals(0f, Drip.countAlpha(Drip.LANDS))
    }

    @Test
    fun itHasSettledBeforeTheFirstBreath() {
        // By the breath in the orb is the empty orb, still, and the count has come in.
        val f = Drip.at(SessionPlan.SETTLE_SECONDS - 1e-6)
        assertEquals(SceneGeometry.ORB_MIN.toDouble(), f.orb, 1e-6)
        assertTrue(abs(f.squash) < 1e-4)
        assertNull(f.hanging)
        assertNull(f.bead)
        assertNull(f.drop)
        assertNull(f.satellite)
        assertEquals(1f, Drip.countAlpha(SessionPlan.SETTLE_SECONDS))
    }

    @Test
    fun aBeadStaysOnTheLineForAMoment() {
        assertNotNull(Drip.at(4.3).bead)
        assertNull(Drip.at(5.0).bead)
    }
}
