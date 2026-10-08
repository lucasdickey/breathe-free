//
//  DaySky.swift
//  BreatheFree
//
//  The sky follows the clock. Kept in step with the Android app's DaySky.kt, so both apps
//  show the same sky at the same moment.
//

import Foundation

/// A colour in sRGB, 0...1 per channel.
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// A straight blend of the channels, the way a gradient draws between its stops.
    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// A blend through Oklab, which keeps brightness and hue even on the way; the Android
    /// app blends its sky colours the same way.
    func blend(_ other: RGB, _ t: Double) -> RGB {
        let a = oklab
        let o = other.oklab
        return RGB(oklab: (a.0 + (o.0 - a.0) * t, a.1 + (o.1 - a.1) * t, a.2 + (o.2 - a.2) * t))
    }

    /// Relative luminance, as WCAG defines it.
    var luminance: Double {
        0.2126 * Self.linear(r) + 0.7152 * Self.linear(g) + 0.0722 * Self.linear(b)
    }

    private var oklab: (Double, Double, Double) {
        let lr = Self.linear(r), lg = Self.linear(g), lb = Self.linear(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private init(oklab c: (Double, Double, Double)) {
        let l = pow(c.0 + 0.3963377774 * c.1 + 0.2158037573 * c.2, 3)
        let m = pow(c.0 - 0.1055613458 * c.1 - 0.0638541728 * c.2, 3)
        let s = pow(c.0 - 0.0894841775 * c.1 - 1.2914855480 * c.2, 3)
        r = Self.encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
        g = Self.encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
        b = Self.encoded(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}

/// Colours for one moment of the sky.
struct SkyPalette: Equatable {
    var top: RGB
    var mid: RGB
    var bottom: RGB
    var cloud: RGB
    var cloudAlpha: Double
    /// How bright the stars are: 0 by day, 1 at night.
    var stars: Double = 0

    func mix(_ o: SkyPalette, _ t: Double) -> SkyPalette {
        SkyPalette(top: top.blend(o.top, t), mid: mid.blend(o.mid, t), bottom: bottom.blend(o.bottom, t),
                   cloud: cloud.blend(o.cloud, t), cloudAlpha: cloudAlpha + (o.cloudAlpha - cloudAlpha) * t,
                   stars: stars + (o.stars - stars) * t)
    }

    /// The sky's colour `y` of the way down the window, blended as the gradient draws it.
    func at(_ y: Double) -> RGB {
        y <= 0.5 ? top.mix(mid, y / 0.5) : mid.mix(bottom, (y - 0.5) / 0.5)
    }
}

/// The sky for one moment of the day, and which way round the text goes on it.
struct DayLook: Equatable {
    let sky: SkyPalette
    /// Light text and controls when true, dark ones when false.
    let dark: Bool
    /// How far secondary text may fade from the main text colour: 1 is its own softer tone,
    /// 0 is the main colour. Below 1 only around dawn and dusk, while the sky is half lit.
    let softness: Double
}

/// The sky follows the clock: night, blue hour, a hazy violet as the light turns, sunrise,
/// morning, day, golden hour, sunset, the haze again, dusk and night, keyed to the day's
/// sunrise and sunset so a December evening darkens hours before a June one.
///
/// Sunrise and sunset come from the date alone, so no location is needed: latitude 40
/// degrees (south for the southern time zones in `southernZones`) and solar noon at 12:00 on
/// the zone's standard clock, moved by daylight saving and the equation of time.
///
/// Text colour is chosen for the sky behind it: light or dark, whichever reads better at its
/// worst spot among the places text sits. The hazy stops sit where the choice flips, so
/// neither has to work across a sky dark at the top and bright at the horizon; main and
/// secondary text keep at least 3:1 all day.
enum DaySky {
    /// Main and secondary text for a light sky, and for a dark one.
    static let darkText = (main: RGB(0x0F2A43), soft: RGB(0x2E4A63))
    static let lightText = (main: RGB(0xFFFFFF), soft: RGB(0xD3DEEC))

    static func look(at date: Date, in zone: TimeZone = .current) -> DayLook {
        let (rise, set) = sunTimes(on: date, in: zone)
        let c = calendar(zone).dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let sky = palette(atHour: hour, rise: rise, set: set)
        let dark = worstContrast(lightText.main, sky) > worstContrast(darkText.main, sky)
        let text = dark ? lightText : darkText
        let softness = min(max((worstContrast(text.soft, sky) - 2.6) / (3.4 - 2.6), 0), 1)
        return DayLook(sky: sky, dark: dark, softness: softness)
    }

    /// Sunrise and sunset on the day of `date`, in hours on the local clock.
    static func sunTimes(on date: Date, in zone: TimeZone) -> (rise: Double, set: Double) {
        let cal = calendar(zone)
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let latitude = (isSouthern(zone) ? -40.0 : 40.0) * .pi / 180
        let declination = 23.44 * .pi / 180 * sin(2 * .pi * (284 + day) / 365)
        // The sun's centre 0.833 degrees below the horizon: refraction and the sun's own size.
        let cosHalfDay = (sin(-0.833 * .pi / 180) - sin(latitude) * sin(declination)) /
            (cos(latitude) * cos(declination))
        let halfDayHours = acos(min(max(cosHalfDay, -1), 1)) * 180 / .pi / 15
        let b = 2 * .pi * (day - 81) / 364
        let equationOfTimeMinutes = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
        let noonDate = cal.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let saving = zone.daylightSavingTimeOffset(for: noonDate) / 3600
        let noon = 12 + saving - equationOfTimeMinutes / 60
        return (noon - halfDayHours, noon + halfDayHours)
    }

    static func isSouthern(_ zone: TimeZone) -> Bool {
        southernZones.contains { zone.identifier.hasPrefix($0) }
    }

    /// The sky `hour` hours after local midnight, on a day with the given sunrise and sunset.
    static func palette(atHour hour: Double, rise: Double, set: Double) -> SkyPalette {
        var previous = keys[0]
        var previousTime = previous.time(rise, set)
        if hour < previousTime { return night }
        for key in keys.dropFirst() {
            let time = key.time(rise, set)
            if hour < time {
                let x = (hour - previousTime) / (time - previousTime)
                return previous.sky.mix(key.sky, x * x * (3 - 2 * x))
            }
            previous = key
            previousTime = time
        }
        return night
    }

    /// The lowest contrast `ink` has against `sky` at the heights where text sits.
    static func worstContrast(_ ink: RGB, _ sky: SkyPalette) -> Double {
        textHeights.map { contrast(ink, sky.at($0)) }.min() ?? 1
    }

    /// WCAG contrast ratio between two colours.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    private enum Anchor { case sunrise, sunset }

    private struct Key {
        let anchor: Anchor
        let hours: Double
        let sky: SkyPalette

        func time(_ rise: Double, _ set: Double) -> Double { (anchor == .sunrise ? rise : set) + hours }
    }

    /// Fractions of the window's height where text and controls sit, top bar to bottom line.
    private static let textHeights = [0.06, 0.3, 0.5, 0.7, 0.9]

    private static let southernZones = [
        "Australia/", "Antarctica/", "Pacific/Auckland", "Pacific/Chatham", "NZ",
        "America/Argentina/", "America/Buenos_Aires", "America/Santiago", "Chile/",
        "America/Montevideo", "America/Sao_Paulo", "Brazil/East",
        "Africa/Johannesburg", "Africa/Maputo", "Africa/Windhoek",
    ]

    private static func sky(_ top: UInt32, _ mid: UInt32, _ bottom: UInt32, _ cloud: UInt32,
                            _ cloudAlpha: Double, stars: Double = 0) -> SkyPalette {
        SkyPalette(top: RGB(top), mid: RGB(mid), bottom: RGB(bottom), cloud: RGB(cloud), cloudAlpha: cloudAlpha, stars: stars)
    }

    static let night = sky(0x060D1F, 0x0D1B36, 0x1B2D52, 0x7C8BAD, 0.16, stars: 1)
    private static let blueHour = sky(0x13224A, 0x2C4275, 0x5A5A8C, 0xA8A3CC, 0.24, stars: 0.4)
    private static let dawnHaze = sky(0x5F6A9C, 0x7C7CA8, 0x9A8AA8, 0xD8C8DC, 0.35, stars: 0.1)
    private static let sunrise = sky(0x7E95C6, 0xC0A8C8, 0xF4C7A4, 0xFFE0CC, 0.55)
    private static let morning = sky(0x86B6E6, 0xC4DDF2, 0xF6E7D8, 0xFFFFFF, 0.8)
    static let day = sky(0x9FCFF2, 0xCBE6F8, 0xEEF7FD, 0xFFFFFF, 0.85)
    private static let afternoon = sky(0x98C6EC, 0xCBE2F3, 0xF4F0E8, 0xFFFFFF, 0.85)
    private static let golden = sky(0x86A9D6, 0xE6C6A8, 0xF5CF9E, 0xFFF0D8, 0.75)
    private static let sunset = sky(0x8E95C2, 0xDDA6A2, 0xF0B08A, 0xFFD2BC, 0.6)
    private static let duskHaze = sky(0x64669A, 0x86749A, 0xA07E92, 0xD2B8CC, 0.35, stars: 0.05)
    private static let dusk = sky(0x1B2A56, 0x3B477C, 0x6E5A88, 0xA898C0, 0.26, stars: 0.4)

    private static let keys: [Key] = [
        Key(anchor: .sunrise, hours: -1.5, sky: night),
        Key(anchor: .sunrise, hours: -0.75, sky: blueHour),
        Key(anchor: .sunrise, hours: -0.25, sky: dawnHaze),
        Key(anchor: .sunrise, hours: 0.15, sky: sunrise),
        Key(anchor: .sunrise, hours: 1.2, sky: morning),
        Key(anchor: .sunrise, hours: 3.0, sky: day),
        Key(anchor: .sunset, hours: -3.0, sky: afternoon),
        Key(anchor: .sunset, hours: -0.9, sky: golden),
        Key(anchor: .sunset, hours: 0.05, sky: sunset),
        Key(anchor: .sunset, hours: 0.35, sky: duskHaze),
        Key(anchor: .sunset, hours: 0.75, sky: dusk),
        Key(anchor: .sunset, hours: 1.5, sky: night),
    ]
}
