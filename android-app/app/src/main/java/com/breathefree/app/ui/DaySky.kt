package com.breathefree.app.ui

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** The sky for one moment of the day, and which way round the text goes on it. */
@Immutable
data class DayLook(
    val sky: SkyPalette,
    /** Light text and controls when true, dark ones when false. */
    val dark: Boolean,
    /**
     * How far secondary text may fade from the main text colour: 1 is its own softer tone,
     * 0 is the main colour. Below 1 only around dawn and dusk, while the sky is half lit and
     * the softer tone would be hard to read.
     */
    val softness: Float,
)

/**
 * The sky follows the clock: night, blue hour, a hazy violet as the light turns, sunrise,
 * morning, day, golden hour, sunset, the haze again, dusk and night, keyed to the day's
 * sunrise and sunset so a December evening darkens hours before a June one.
 *
 * Sunrise and sunset come from the date alone, so no location is needed: latitude 40
 * degrees (south for the southern time zones in [SOUTHERN_ZONES]) and solar noon at 12:00 on
 * the zone's standard clock, moved by daylight saving and the equation of time. That is
 * within half an hour or so for most places people live, which is plenty for a sky.
 *
 * Text colour is chosen for the sky behind it: light or dark, whichever reads better at its
 * worst spot among the places text sits (the session's top bar down to the home screen's
 * buttons). The two hazy stops sit where the choice flips, so neither colour ever has to
 * work across a sky that is dark at the top and bright at the horizon. In practice the main
 * text never falls below 3:1, and the secondary text is held there too ([DayLook.softness]).
 */
object DaySky {
    fun at(time: ZonedDateTime): DayLook {
        val (rise, set) = sunTimes(time.toLocalDate(), time.zone)
        val hour = time.hour + time.minute / 60.0 + time.second / 3600.0
        val sky = paletteAt(hour, rise, set)
        val dark = worstContrast(Ink.OnDark.deep, sky) > worstContrast(Ink.OnLight.deep, sky)
        val ink = if (dark) Ink.OnDark else Ink.OnLight
        val softness = ((worstContrast(ink.soft, sky) - 2.6f) / (3.4f - 2.6f)).coerceIn(0f, 1f)
        return DayLook(sky, dark, softness)
    }

    /** Sunrise and sunset on [date], in hours on the local clock. */
    fun sunTimes(date: LocalDate, zone: ZoneId): Pair<Double, Double> {
        val day = date.dayOfYear
        val latitude = Math.toRadians(if (isSouthern(zone)) -40.0 else 40.0)
        val declination = Math.toRadians(23.44) * sin(2 * PI * (284 + day) / 365.0)
        // The sun's centre 0.833 degrees below the horizon: refraction and the sun's own size.
        val cosHalfDay = (sin(Math.toRadians(-0.833)) - sin(latitude) * sin(declination)) /
            (cos(latitude) * cos(declination))
        val halfDayHours = Math.toDegrees(acos(cosHalfDay.coerceIn(-1.0, 1.0))) / 15.0
        val b = 2 * PI * (day - 81) / 364.0
        val equationOfTimeMinutes = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
        val saving = zone.rules.getDaylightSavings(date.atTime(12, 0).atZone(zone).toInstant())
        val noon = 12.0 + saving.seconds / 3600.0 - equationOfTimeMinutes / 60.0
        return (noon - halfDayHours) to (noon + halfDayHours)
    }

    fun isSouthern(zone: ZoneId): Boolean = SOUTHERN_ZONES.any { zone.id.startsWith(it) }

    /** The sky [hour] hours after local midnight, on a day with the given sunrise and sunset. */
    fun paletteAt(hour: Double, rise: Double, set: Double): SkyPalette {
        var previous = KEYS.first()
        var previousTime = previous.time(rise, set)
        if (hour < previousTime) return NIGHT
        for (key in KEYS.drop(1)) {
            val time = key.time(rise, set)
            if (hour < time) {
                val x = ((hour - previousTime) / (time - previousTime)).toFloat()
                return previous.sky.mix(key.sky, x * x * (3 - 2 * x))
            }
            previous = key
            previousTime = time
        }
        return NIGHT
    }

    /** The lowest contrast [ink] has against [sky] at the heights where text sits. */
    fun worstContrast(ink: Color, sky: SkyPalette): Float {
        var worst = Float.MAX_VALUE
        for (y in TEXT_HEIGHTS) worst = min(worst, contrast(ink, sky.at(y)))
        return worst
    }

    /** WCAG contrast ratio between two opaque colours. */
    fun contrast(a: Color, b: Color): Float {
        val la = a.luminance()
        val lb = b.luminance()
        return (max(la, lb) + 0.05f) / (min(la, lb) + 0.05f)
    }

    private enum class Anchor { SUNRISE, SUNSET }

    private class Key(val anchor: Anchor, val hours: Double, val sky: SkyPalette) {
        fun time(rise: Double, set: Double) = (if (anchor == Anchor.SUNRISE) rise else set) + hours
    }

    /** Fractions of the screen height where text and controls sit, top bar to bottom line. */
    private val TEXT_HEIGHTS = floatArrayOf(0.06f, 0.3f, 0.5f, 0.7f, 0.9f)

    private val SOUTHERN_ZONES = listOf(
        "Australia/", "Antarctica/", "Pacific/Auckland", "Pacific/Chatham", "NZ",
        "America/Argentina/", "America/Buenos_Aires", "America/Santiago", "Chile/",
        "America/Montevideo", "America/Sao_Paulo", "Brazil/East",
        "Africa/Johannesburg", "Africa/Maputo", "Africa/Windhoek",
    )

    private fun sky(top: Long, mid: Long, bottom: Long, cloud: Long, cloudAlpha: Float, stars: Float = 0f) =
        SkyPalette(Color(top), Color(mid), Color(bottom), Color(cloud), cloudAlpha, stars)

    val NIGHT = sky(0xFF060D1F, 0xFF0D1B36, 0xFF1B2D52, 0xFF7C8BAD, 0.16f, stars = 1f)
    private val BLUE_HOUR = sky(0xFF13224A, 0xFF2C4275, 0xFF5A5A8C, 0xFFA8A3CC, 0.24f, stars = 0.4f)
    private val DAWN_HAZE = sky(0xFF5F6A9C, 0xFF7C7CA8, 0xFF9A8AA8, 0xFFD8C8DC, 0.35f, stars = 0.1f)
    private val SUNRISE = sky(0xFF7E95C6, 0xFFC0A8C8, 0xFFF4C7A4, 0xFFFFE0CC, 0.55f)
    private val MORNING = sky(0xFF86B6E6, 0xFFC4DDF2, 0xFFF6E7D8, 0xFFFFFFFF, 0.8f)
    val DAY = sky(0xFF9FCFF2, 0xFFCBE6F8, 0xFFEEF7FD, 0xFFFFFFFF, 0.85f)
    private val AFTERNOON = sky(0xFF98C6EC, 0xFFCBE2F3, 0xFFF4F0E8, 0xFFFFFFFF, 0.85f)
    private val GOLDEN = sky(0xFF86A9D6, 0xFFE6C6A8, 0xFFF5CF9E, 0xFFFFF0D8, 0.75f)
    private val SUNSET = sky(0xFF8E95C2, 0xFFDDA6A2, 0xFFF0B08A, 0xFFFFD2BC, 0.6f)
    private val DUSK_HAZE = sky(0xFF64669A, 0xFF86749A, 0xFFA07E92, 0xFFD2B8CC, 0.35f, stars = 0.05f)
    private val DUSK = sky(0xFF1B2A56, 0xFF3B477C, 0xFF6E5A88, 0xFFA898C0, 0.26f, stars = 0.4f)

    private val KEYS = listOf(
        Key(Anchor.SUNRISE, -1.5, NIGHT),
        Key(Anchor.SUNRISE, -0.75, BLUE_HOUR),
        Key(Anchor.SUNRISE, -0.25, DAWN_HAZE),
        Key(Anchor.SUNRISE, 0.15, SUNRISE),
        Key(Anchor.SUNRISE, 1.2, MORNING),
        Key(Anchor.SUNRISE, 3.0, DAY),
        Key(Anchor.SUNSET, -3.0, AFTERNOON),
        Key(Anchor.SUNSET, -0.9, GOLDEN),
        Key(Anchor.SUNSET, 0.05, SUNSET),
        Key(Anchor.SUNSET, 0.35, DUSK_HAZE),
        Key(Anchor.SUNSET, 0.75, DUSK),
        Key(Anchor.SUNSET, 1.5, NIGHT),
    )
}
