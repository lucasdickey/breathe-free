import XCTest
@testable import BreatheCore

final class DaySkyTests: XCTestCase {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let sydney = TimeZone(identifier: "Australia/Sydney")!
    private let dates = [(2026, 3, 20), (2026, 6, 21), (2026, 9, 22), (2026, 12, 21)]

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 0, _ minute: Int = 0, in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    /// Every minute of the local day.
    private func everyMinute(_ y: Int, _ m: Int, _ d: Int, in zone: TimeZone) -> [Date] {
        let start = date(y, m, d, in: zone)
        let end = date(y, m, d + 1, in: zone)
        return stride(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, by: 60).map {
            Date(timeIntervalSince1970: $0)
        }
    }

    func testDaysAreLongInSummerAndShortInWinter() {
        let june = DaySky.sunTimes(on: date(2026, 6, 21, 12, in: losAngeles), in: losAngeles)
        let december = DaySky.sunTimes(on: date(2026, 12, 21, 12, in: losAngeles), in: losAngeles)
        XCTAssertEqual(june.set - june.rise, 15.0, accuracy: 0.5)
        XCTAssertEqual(december.set - december.rise, 9.4, accuracy: 0.5)
        // On the clock: daylight saving in June, none in December.
        XCTAssertEqual(june.set, 20.5, accuracy: 0.5)
        XCTAssertEqual(december.set, 16.7, accuracy: 0.5)
    }

    func testSouthernTimeZonesHaveTheirSummerInDecember() {
        XCTAssertTrue(DaySky.isSouthern(sydney))
        XCTAssertFalse(DaySky.isSouthern(losAngeles))
        let times = DaySky.sunTimes(on: date(2026, 12, 21, 12, in: sydney), in: sydney)
        XCTAssertEqual(times.set - times.rise, 15.0, accuracy: 0.5)
    }

    func testNoonIsDaylightAndLateEveningIsNight() {
        let noon = DaySky.look(at: date(2026, 10, 7, 12, 30, in: losAngeles), in: losAngeles)
        XCTAssertFalse(noon.dark)
        XCTAssertEqual(noon.sky.stars, 0)
        let night = DaySky.look(at: date(2026, 10, 7, 21, 30, in: losAngeles), in: losAngeles)
        XCTAssertTrue(night.dark)
        XCTAssertEqual(night.sky, DaySky.night)
    }

    func testTextStaysReadableAtEveryMinute() {
        for zone in [losAngeles, sydney] {
            for (y, m, d) in dates {
                for time in everyMinute(y, m, d, in: zone) {
                    let look = DaySky.look(at: time, in: zone)
                    let text = look.dark ? DaySky.lightText : DaySky.darkText
                    let soft = text.main.blend(text.soft, look.softness)
                    let main = DaySky.worstContrast(text.main, look.sky)
                    let secondary = DaySky.worstContrast(soft, look.sky)
                    XCTAssertGreaterThanOrEqual(main, 3, "main text at \(time) in \(zone.identifier)")
                    XCTAssertGreaterThanOrEqual(secondary, 3, "secondary text at \(time) in \(zone.identifier)")
                }
            }
        }
    }

    func testTheSkyNeverJumps() {
        for zone in [losAngeles, sydney] {
            for (y, m, d) in dates {
                var previous: SkyPalette?
                for time in everyMinute(y, m, d, in: zone) {
                    let sky = DaySky.look(at: time, in: zone).sky
                    if let p = previous {
                        for (a, b) in [(p.top, sky.top), (p.mid, sky.mid), (p.bottom, sky.bottom)] {
                            let step = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
                            XCTAssertLessThan(step, 0.05, "sky jumped at \(time) in \(zone.identifier)")
                        }
                    }
                    previous = sky
                }
            }
        }
    }

    func testTextSwitchesAroundSunriseAndSunset() {
        // On 7 October in Los Angeles (sunrise about 7:04, sunset about 6:29 pm): dark text
        // from shortly before sunrise, light text again shortly after sunset.
        let morning = (6 * 60 + 40)...(7 * 60 + 10)
        let evening = (18 * 60 + 30)...(19 * 60)
        var switches: [Int] = []
        var last: Bool?
        for (i, time) in everyMinute(2026, 10, 7, in: losAngeles).enumerated() {
            let dark = DaySky.look(at: time, in: losAngeles).dark
            if let l = last, l != dark { switches.append(i) }
            last = dark
        }
        XCTAssertEqual(switches.count, 2)
        XCTAssertTrue(morning.contains(switches[0]), "morning switch at minute \(switches[0])")
        XCTAssertTrue(evening.contains(switches[1]), "evening switch at minute \(switches[1])")
    }

    func testTheSunGoesRoundTheOrb() {
        // Which way the light comes from on screen (y down), on a day with sunrise at 7 and sunset at 19.
        func light(_ hour: Double, southern: Bool = false) -> (x: Double, y: Double) {
            let a = DaySky.sunAngle(atHour: hour, rise: 7, set: 19, southern: southern)
            return (cos(a), -sin(a))
        }
        func check(_ l: (x: Double, y: Double), _ x: Double, _ y: Double, line: UInt = #line) {
            XCTAssertEqual(l.x, x, accuracy: 1e-9, line: line)
            XCTAssertEqual(l.y, y, accuracy: 1e-9, line: line)
        }
        check(light(7), -1, 0)   // sunrise: the left
        check(light(13), 0, -1)  // midday: the top
        check(light(19), 1, 0)   // sunset: the right
        check(light(1), 0, 1)    // the middle of the night: underneath
        // South of the equator it rises on the right and sets on the left.
        check(light(7, southern: true), 1, 0)
        check(light(13, southern: true), 0, -1)
        check(light(19, southern: true), -1, 0)
        // It moves on smoothly all day, with no jump at sunrise, sunset or midnight.
        var before = light(0)
        for minute in 1...(24 * 60) {
            let now = light(Double(minute) / 60)
            XCTAssertLessThan(hypot(now.x - before.x, now.y - before.y), 0.01, "jump at minute \(minute)")
            before = now
        }
        // A real day in Los Angeles: from the left soon after sunrise, from above at lunch.
        let morning = DaySky.look(at: date(2026, 10, 7, 7, 30, in: losAngeles), in: losAngeles).sun
        let lunch = DaySky.look(at: date(2026, 10, 7, 13, 0, in: losAngeles), in: losAngeles).sun
        XCTAssertLessThan(cos(morning), -0.9)
        XCTAssertGreaterThan(sin(lunch), 0.95)
    }
}
