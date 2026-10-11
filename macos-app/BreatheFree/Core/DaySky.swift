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

/// The orb's colours for one moment of the sky, from empty lungs (low) to full (high): each of
/// the sky's keys has its own (`DaySky`), so the orb sits in the sky's light, cyan by night,
/// peach at sunrise, gold at golden hour, mauve as the light goes.
struct OrbColors: Equatable {
    let coreLow: RGB
    let coreHigh: RGB
    let edgeLow: RGB
    let edgeHigh: RGB
    /// The light round the orb, and round the dot that travels the box.
    let glow: RGB
    /// How strongly the glow adds its light: fully on a dark sky, faintly where the sky is already bright.
    var shine: Double = 1

    static let night = OrbColors(coreLow: RGB(0x7CC9E6), coreHigh: RGB(0xC6F6FB),
                                 edgeLow: RGB(0x1D6CA0), edgeHigh: RGB(0x39B6D8), glow: RGB(0x86E3F4))
    static let day = OrbColors(coreLow: RGB(0xBDEFF8), coreHigh: RGB(0xE6FBFE),
                               edgeLow: RGB(0x2B95C2), edgeHigh: RGB(0x3FB8D9), glow: RGB(0x7FD6EE), shine: 0.15)

    func mix(_ o: OrbColors, _ t: Double) -> OrbColors {
        OrbColors(coreLow: coreLow.blend(o.coreLow, t), coreHigh: coreHigh.blend(o.coreHigh, t),
                  edgeLow: edgeLow.blend(o.edgeLow, t), edgeHigh: edgeHigh.blend(o.edgeHigh, t),
                  glow: glow.blend(o.glow, t), shine: shine + (o.shine - shine) * t)
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
    /// Where the sun is, as an angle round the orb (`DaySky.sunAngle`): the side it is lit from.
    let sun: Double
    /// The orb's colours for this sky (`DaySky.orb(atHour:rise:set:)`).
    let orb: OrbColors
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
        let sun = sunAngle(atHour: hour, rise: rise, set: set, southern: isSouthern(zone))
        return DayLook(sky: sky, dark: dark, softness: softness, sun: sun,
                       orb: orb(atHour: hour, rise: rise, set: set))
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

    /// Where the sun is at `hour`, as an angle round the orb in radians, so the orb can be lit
    /// from that side: π at sunrise (the left), π/2 at midday (the top), 0 at sunset (the
    /// right), then on round underneath through the night, -π/2 in the middle of it. That is
    /// the sun's path as you face it, so south of the equator it runs the other way, rising on
    /// the right.
    static func sunAngle(atHour hour: Double, rise: Double, set: Double, southern: Bool) -> Double {
        let day = set - rise
        let angle: Double
        if hour >= rise && hour <= set {
            angle = .pi * (1 - (hour - rise) / day)
        } else {
            let sinceSunset = (hour - set + 24).truncatingRemainder(dividingBy: 24)
            angle = -.pi * sinceSunset / (24 - day)
        }
        return southern ? .pi - angle : angle
    }

    static func isSouthern(_ zone: TimeZone) -> Bool {
        southernZones.contains { zone.identifier.hasPrefix($0) }
    }

    /// The sky `hour` hours after local midnight, on a day with the given sunrise and sunset.
    static func palette(atHour hour: Double, rise: Double, set: Double) -> SkyPalette {
        guard let around = keysAround(hour, rise: rise, set: set) else { return night }
        return around.0.sky.mix(around.1.sky, around.2)
    }

    /// The orb's colours at the same moment. Each of the sky's keys has its own, blended the
    /// way the sky is, so the orb always sits in the sky's light: cyan by night, periwinkle at
    /// blue hour, peach at sunrise, sky blue by day, gold at golden hour, coral at sunset, mauve
    /// and violet as the light goes.
    static func orb(atHour hour: Double, rise: Double, set: Double) -> OrbColors {
        guard let around = keysAround(hour, rise: rise, set: set) else { return .night }
        return around.0.orb.mix(around.1.orb, around.2)
    }

    /// The keys either side of `hour` and how far it is from one to the other, eased; nil at night.
    private static func keysAround(_ hour: Double, rise: Double, set: Double) -> (Key, Key, Double)? {
        var previous = keys[0]
        var previousTime = previous.time(rise, set)
        if hour < previousTime { return nil }
        for key in keys.dropFirst() {
            let time = key.time(rise, set)
            if hour < time {
                let x = (hour - previousTime) / (time - previousTime)
                return (previous, key, x * x * (3 - 2 * x))
            }
            previous = key
            previousTime = time
        }
        return nil
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
        let orb: OrbColors

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

    // The orb for each sky: core and edge with the lungs empty and full, the glow, and how
    // strongly the glow shines. Kept in step with the Android app's DaySky.kt.
    private static func orb(_ coreLow: UInt32, _ coreHigh: UInt32, _ edgeLow: UInt32, _ edgeHigh: UInt32,
                            _ glow: UInt32, shine: Double) -> OrbColors {
        OrbColors(coreLow: RGB(coreLow), coreHigh: RGB(coreHigh), edgeLow: RGB(edgeLow), edgeHigh: RGB(edgeHigh),
                  glow: RGB(glow), shine: shine)
    }

    private static let blueHourOrb = orb(0xA6BFF1, 0xD5E2FF, 0x34509C, 0x5A7BD0, 0x9DB7F2, shine: 1)
    private static let dawnHazeOrb = orb(0xC0B8E8, 0xE3DCFA, 0x6A63A6, 0x9890CF, 0xCDC4F2, shine: 0.85)
    private static let sunriseOrb = orb(0xF4CDBF, 0xFFF0E6, 0xB8768E, 0xE09FA6, 0xFFD6C4, shine: 0.5)
    private static let morningOrb = orb(0xC2E4F8, 0xF2FAFF, 0x3F86C0, 0x6EAEDF, 0xC6E6FA, shine: 0.18)
    private static let afternoonOrb = orb(0xC6ECF6, 0xEEFBFD, 0x2F8FBF, 0x4FB3D6, 0x8AD6EC, shine: 0.15)
    private static let goldenOrb = orb(0xF7DDB2, 0xFFF5E3, 0xC2843F, 0xE8B06A, 0xFFE1B2, shine: 0.35)
    private static let sunsetOrb = orb(0xF6C4B4, 0xFFEDE5, 0xC06A6A, 0xE8958A, 0xFFCDBD, shine: 0.5)
    private static let duskHazeOrb = orb(0xCDB2DC, 0xEEDDF5, 0x7A5A92, 0xA887C0, 0xD9C2E8, shine: 0.85)
    private static let duskOrb = orb(0xBAB9F3, 0xE0DFFF, 0x46449A, 0x7470CC, 0xB2AFF4, shine: 1)

    private static let keys: [Key] = [
        Key(anchor: .sunrise, hours: -1.5, sky: night, orb: .night),
        Key(anchor: .sunrise, hours: -0.75, sky: blueHour, orb: blueHourOrb),
        Key(anchor: .sunrise, hours: -0.25, sky: dawnHaze, orb: dawnHazeOrb),
        Key(anchor: .sunrise, hours: 0.15, sky: sunrise, orb: sunriseOrb),
        Key(anchor: .sunrise, hours: 1.2, sky: morning, orb: morningOrb),
        Key(anchor: .sunrise, hours: 3.0, sky: day, orb: .day),
        Key(anchor: .sunset, hours: -3.0, sky: afternoon, orb: afternoonOrb),
        Key(anchor: .sunset, hours: -0.9, sky: golden, orb: goldenOrb),
        Key(anchor: .sunset, hours: 0.05, sky: sunset, orb: sunsetOrb),
        Key(anchor: .sunset, hours: 0.35, sky: duskHaze, orb: duskHazeOrb),
        Key(anchor: .sunset, hours: 0.75, sky: dusk, orb: duskOrb),
        Key(anchor: .sunset, hours: 1.5, sky: night, orb: .night),
    ]
}
