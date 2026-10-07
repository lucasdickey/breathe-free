package com.breathefree.app.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.abs
import kotlin.math.max

class DaySkyTest {
    private val losAngeles = ZoneId.of("America/Los_Angeles")
    private val sydney = ZoneId.of("Australia/Sydney")
    private val dates = listOf(
        LocalDate.of(2026, 3, 20), LocalDate.of(2026, 6, 21),
        LocalDate.of(2026, 9, 22), LocalDate.of(2026, 12, 21),
    )

    private fun everyMinute(date: LocalDate, zone: ZoneId): Sequence<ZonedDateTime> {
        val start = ZonedDateTime.of(date, LocalTime.MIDNIGHT, zone)
        return generateSequence(start) { it.plusMinutes(1) }.takeWhile { it.toLocalDate() == date }
    }

    @Test
    fun daysAreLongInSummerAndShortInWinter() {
        val (juneRise, juneSet) = DaySky.sunTimes(LocalDate.of(2026, 6, 21), losAngeles)
        val (decRise, decSet) = DaySky.sunTimes(LocalDate.of(2026, 12, 21), losAngeles)
        assertEquals(15.0, juneSet - juneRise, 0.5)
        assertEquals(9.4, decSet - decRise, 0.5)
        // On the clock: daylight saving in June, none in December.
        assertEquals(20.5, juneSet, 0.5)
        assertEquals(16.7, decSet, 0.5)
    }

    @Test
    fun southernTimeZonesHaveTheirSummerInDecember() {
        assertTrue(DaySky.isSouthern(sydney))
        assertFalse(DaySky.isSouthern(losAngeles))
        val (rise, set) = DaySky.sunTimes(LocalDate.of(2026, 12, 21), sydney)
        assertEquals(15.0, set - rise, 0.5)
    }

    @Test
    fun noonIsDaylightAndLateEveningIsNight() {
        val noon = DaySky.at(ZonedDateTime.of(2026, 10, 7, 12, 30, 0, 0, losAngeles))
        assertFalse(noon.dark)
        assertEquals(0f, noon.sky.stars, 0f)
        val night = DaySky.at(ZonedDateTime.of(2026, 10, 7, 21, 30, 0, 0, losAngeles))
        assertTrue(night.dark)
        assertEquals(DaySky.NIGHT, night.sky)
    }

    @Test
    fun textStaysReadableAtEveryMinute() {
        for (zone in listOf(losAngeles, sydney)) for (date in dates) {
            for (time in everyMinute(date, zone)) {
                val look = DaySky.at(time)
                val ink = (if (look.dark) Ink.OnDark else Ink.OnLight).softened(look.softness)
                val main = DaySky.worstContrast(ink.deep, look.sky)
                val soft = DaySky.worstContrast(ink.soft, look.sky)
                assertTrue("main text $main:1 at $time", main >= 3f)
                assertTrue("secondary text $soft:1 at $time", soft >= 3f)
            }
        }
    }

    @Test
    fun theSkyNeverJumps() {
        for (zone in listOf(losAngeles, sydney)) for (date in dates) {
            var previous: SkyPalette? = null
            for (time in everyMinute(date, zone)) {
                val sky = DaySky.at(time).sky
                previous?.let { p ->
                    for ((a, b) in listOf(p.top to sky.top, p.mid to sky.mid, p.bottom to sky.bottom)) {
                        val step = max(abs(a.red - b.red), max(abs(a.green - b.green), abs(a.blue - b.blue)))
                        assertTrue("sky moved $step in a minute at $time", step < 0.05f)
                    }
                }
                previous = sky
            }
        }
    }
}
