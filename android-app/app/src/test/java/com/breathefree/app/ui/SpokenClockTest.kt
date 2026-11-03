package com.breathefree.app.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** How the session lengths and the time left are said to TalkBack. */
class SpokenClockTest {
    @Test
    fun oneIsSaidInTheSingular() {
        assertEquals("1 second", spokenClock(1))
        assertEquals("1 minute", spokenClock(60))
        assertEquals("1 minute 1 second", spokenClock(61))
        assertEquals("1 minute 36 seconds", spokenClock(96))
        assertEquals("2 minutes 1 second", spokenClock(121))
    }

    @Test
    fun everythingElseInThePlural() {
        assertEquals("0 seconds", spokenClock(0))
        assertEquals("32 seconds", spokenClock(32))
        assertEquals("2 minutes 40 seconds", spokenClock(160))
        assertEquals("13 minutes 20 seconds", spokenClock(800))
        assertEquals("5 minutes", spokenClock(300))
    }
}
