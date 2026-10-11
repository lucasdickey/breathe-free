package com.breathefree.app.ui

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
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

    @Test
    fun theOrbNeverJumps() {
        for (zone in listOf(losAngeles, sydney)) for (date in dates) {
            var previous: OrbColors? = null
            for (time in everyMinute(date, zone)) {
                val orb = DaySky.at(time).orb
                previous?.let { p ->
                    for ((a, b) in listOf(
                        p.coreLow to orb.coreLow, p.coreHigh to orb.coreHigh,
                        p.edgeLow to orb.edgeLow, p.edgeHigh to orb.edgeHigh, p.glow to orb.glow,
                    )) {
                        val step = max(abs(a.red - b.red), max(abs(a.green - b.green), abs(a.blue - b.blue)))
                        assertTrue("orb moved $step in a minute at $time", step < 0.05f)
                    }
                    assertTrue("glow strength moved in a minute at $time", abs(p.shine - orb.shine) < 0.05f)
                }
                previous = orb
            }
        }
    }

    @Test
    fun theOrbTakesTheSkysColours() {
        fun at(h: Int, m: Int) = DaySky.at(ZonedDateTime.of(2026, 10, 7, h, m, 0, 0, losAngeles)).orb
        val night = at(23, 0)
        assertEquals(OrbColors.Night, night)
        // Violet at dusk, where the night's cyan would clash: more red, less green.
        val dusk = at(19, 25)
        assertTrue("dusk glow ${dusk.glow}", dusk.glow.red > night.glow.red + 0.1f && dusk.glow.green < night.glow.green)
        // Warm at golden hour.
        val golden = at(17, 35)
        assertTrue("golden core ${golden.coreLow}", golden.coreLow.red > golden.coreLow.blue + 0.15f)
        // Its glow shines fully on a dark sky and only faintly on a bright one.
        assertEquals(1f, night.shine, 0f)
        assertTrue("midday shine ${at(12, 47).shine}", at(12, 47).shine < 0.3f)
    }

    @Test
    fun theCountStaysReadableOnTheOrb() {
        // The count is dark navy at 80% over the orb's core, which sits under it.
        val count = Color(0xFF0B3A55)
        for (zone in listOf(losAngeles, sydney)) for (date in dates) {
            for (time in everyMinute(date, zone)) {
                val orb = DaySky.at(time).orb
                for (core in listOf(orb.coreLow, orb.coreHigh)) {
                    val shown = Color(
                        core.red + (count.red - core.red) * 0.8f,
                        core.green + (count.green - core.green) * 0.8f,
                        core.blue + (count.blue - core.blue) * 0.8f,
                    )
                    val c = DaySky.contrast(shown, core)
                    assertTrue("the count on the orb is $c:1 at $time", c >= 4.2f)
                }
            }
        }
    }

    @Test
    fun theSunGoesRoundTheOrb() {
        // Which way the light comes from on screen (y down), on a day with sunrise at 7 and sunset at 19.
        fun light(hour: Double, southern: Boolean = false): Pair<Double, Double> {
            val a = DaySky.sunAngle(hour, 7.0, 19.0, southern)
            return cos(a) to -sin(a)
        }
        fun check(l: Pair<Double, Double>, x: Double, y: Double) {
            assertEquals(x, l.first, 1e-9)
            assertEquals(y, l.second, 1e-9)
        }
        check(light(7.0), -1.0, 0.0) // sunrise: the left
        check(light(13.0), 0.0, -1.0) // midday: the top
        check(light(19.0), 1.0, 0.0) // sunset: the right
        check(light(1.0), 0.0, 1.0) // the middle of the night: underneath
        // South of the equator it rises on the right and sets on the left.
        check(light(7.0, southern = true), 1.0, 0.0)
        check(light(13.0, southern = true), 0.0, -1.0)
        check(light(19.0, southern = true), -1.0, 0.0)
        // It moves on smoothly all day, with no jump at sunrise, sunset or midnight.
        var before = light(0.0)
        for (minute in 1..24 * 60) {
            val now = light(minute / 60.0)
            assertTrue("jump at minute $minute", hypot(now.first - before.first, now.second - before.second) < 0.01)
            before = now
        }
        // A real day in Los Angeles: from the left soon after sunrise, from above at lunch.
        val la = ZoneId.of("America/Los_Angeles")
        val morning = DaySky.at(ZonedDateTime.of(2026, 10, 7, 7, 30, 0, 0, la)).sun
        val lunch = DaySky.at(ZonedDateTime.of(2026, 10, 7, 13, 0, 0, 0, la)).sun
        assertTrue("morning light from $morning", cos(morning) < -0.9)
        assertTrue("lunch light from $lunch", sin(lunch) > 0.95)
    }
}
