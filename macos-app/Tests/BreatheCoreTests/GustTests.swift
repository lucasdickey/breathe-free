import XCTest
@testable import BreatheCore

/// The same checks as the Android app's GustTest, on the same numbers.
final class GustTests: XCTestCase {
    private let plan = SessionPlan(cycles: 2)

    /// A phone 400 points wide at 3 pixels to the point, as in the Android tests.
    private let unit = 3.0
    private let reach = 1200.0
    private let room = 600.0

    private func at(_ tx: Double, _ ty: Double, along: Double, seed: Int, arrive: Double, leave: Double,
                    t: Double = 10, room: Double? = nil) -> (x: Double, y: Double, alpha: Double) {
        Gust.place(tx: tx, ty: ty, along: along, seed: seed, arriveSince: arrive, leaveSince: leave,
                   reach: reach, room: room ?? self.room, unit: unit, level: 0, t: t)
    }

    func testTheWindTakesEachWordAsItBringsTheNext() {
        // Mid-phase: the inhale's words are settled and the settle's are long gone.
        let mid = plan.gust(at: 10)
        XCTAssertEqual(mid.arriving, "Breathe in")
        XCTAssertEqual(mid.leaving, "Settle in")
        XCTAssertGreaterThan(mid.leaveSince, Gust.gone)

        // Just before the hold: "Breathe in" has begun to leave and "Hold" is not yet on its way.
        let change = plan.phaseStart(1)
        let between = (Gust.leaveLead + Gust.arriveLead) / 2
        let before = plan.gust(at: change - between)
        XCTAssertEqual(before.arriving, "")
        XCTAssertEqual(before.leaving, "Breathe in")
        XCTAssertEqual(before.leaveSince, Gust.leaveLead - between, accuracy: 1e-9)

        // Then "Hold" comes on the same gust.
        let after = plan.gust(at: change - Gust.arriveLead + 0.1)
        XCTAssertEqual(after.arriving, "Hold")
        XCTAssertEqual(after.arriveSince, 0.1, accuracy: 1e-9)
        XCTAssertEqual(after.leaving, "Breathe in")

        // At the end the last hold blows away and nothing comes.
        let end = plan.gust(at: plan.endTime + 0.5)
        XCTAssertEqual(end.arriving, "")
        XCTAssertEqual(end.leaving, "Hold")
    }

    func testNoWordIsInTheAirTwice() {
        // At every moment the arriving and leaving words are different words of the session,
        // or one of them is nothing.
        var t = 0.0
        while t < plan.endTime + 3 {
            let g = plan.gust(at: t)
            let same = !g.arriving.isEmpty && g.arriving == g.leaving && g.leaveSince < Gust.gone
            XCTAssertFalse(same, "at \(t): \(g)")
            t += 0.01
        }
    }

    func testEachWordHasLandedSoonAfterItsPhaseBegins() {
        XCTAssertLessThan(Gust.arrived - Gust.arriveLead, 1)
        for seed in 0..<500 {
            let along = Double(seed % 11) / 10
            let p = at(40, -20, along: along, seed: seed, arrive: Gust.arrived, leave: -1)
            // Where it belongs, give or take the shimmer of a settled speck.
            XCTAssertEqual(p.x, 40, accuracy: 0.3 * unit)
            XCTAssertEqual(p.y, -20, accuracy: 0.3 * unit)
            XCTAssertEqual(p.alpha, 1, accuracy: 1e-6)
        }
    }

    func testTheWindComesFromTheLeftAndGoesOffToTheRight() {
        for seed in 0..<500 {
            let start = at(0, 0, along: 0.5, seed: seed, arrive: 0, leave: -1)
            XCTAssertLessThan(start.x, -0.5 * reach)
            XCTAssertEqual(start.alpha, 0, accuracy: 1e-6)
            let gone = at(0, 0, along: 0.5, seed: seed, arrive: Gust.arrived + 1, leave: Gust.gone)
            XCTAssertGreaterThan(gone.x, 0.45 * reach)
            XCTAssertEqual(gone.alpha, 0, accuracy: 1e-6)
        }
    }

    func testTheLeftEndOfAWordLandsFirst() {
        func landed(_ along: Double, _ seed: Int) -> Double {
            var s = 0.0
            while abs(at(0, 0, along: along, seed: seed, arrive: s, leave: -1).x) > 2 * unit { s += 0.005 }
            return s
        }
        let left = (0..<200).map { landed(0, $0) }.reduce(0, +) / 200
        let right = (0..<200).map { landed(1, $0) }.reduce(0, +) / 200
        XCTAssertGreaterThan(right - left, 0.2, "left \(left), right \(right)")
    }

    func testTheSpecksKeepClearOfTheBox() {
        // The box's lowest edge is 58 points above the words' centre; the dot's glow reaches 16
        // below that. A speck from the top of a letter never rises past 42.
        let top = -16 * unit
        for seed in 0..<300 {
            var s = 0.0
            while s < Gust.arrived {
                let p = at(0, top, along: Double(seed % 5) / 4, seed: seed, arrive: s, leave: -1, t: s)
                XCTAssertGreaterThan(p.y, -42 * unit, "seed \(seed) at \(s): \(p.y / unit)")
                s += 0.01
            }
            s = 0
            while s < Gust.gone {
                let p = at(0, top, along: Double(seed % 5) / 4, seed: seed, arrive: Gust.arrived + 1, leave: s, t: s)
                XCTAssertGreaterThan(p.y, -42 * unit, "seed \(seed) leaving at \(s): \(p.y / unit)")
                s += 0.01
            }
        }
    }

    func testAFewSpecksTakeTheLowRoad() {
        // About a quarter of the specks rise into place from the clear sky below the words and
        // sink back into it as they go, each to its own depth but never past the clear sky.
        func deepest(_ seed: Int, _ room: Double) -> Double {
            var y = -Double.infinity
            var s = 0.0
            while s < Gust.arrived {
                let p = at(0, 0, along: 0.5, seed: seed, arrive: s, leave: -1, t: s, room: room)
                if p.alpha > 0.02 { y = max(y, p.y) }
                s += 0.01
            }
            s = 0
            while s < Gust.gone {
                let p = at(0, 0, along: 0.5, seed: seed, arrive: Gust.arrived + 1, leave: s, t: s, room: room)
                if p.alpha > 0.02 { y = max(y, p.y) }
                s += 0.01
            }
            return y
        }
        var low = 0
        for seed in 0..<1000 {
            let drop = deepest(seed, room) - deepest(seed, 0)
            XCTAssertLessThanOrEqual(drop, room, "seed \(seed) sinks \(drop / unit) under its band")
            if drop > 0.2 * room { low += 1 }
        }
        XCTAssertTrue((150...250).contains(low), "\(low) of 1000 take the low road")
    }

    func testNoSpeckJumps() {
        // Frame to frame at 120 Hz, from blowing in through settling to blowing away, each
        // speck moves smoothly: never more than the wind's top speed allows in one frame.
        let frame = 1.0 / 120
        for seed in 0..<200 {
            var last: (x: Double, y: Double, alpha: Double)?
            var s = 0.0
            while s < Gust.arrived + 1 + Gust.gone {
                let p = at(0, 0, along: 0.5, seed: seed, arrive: s, leave: s - (Gust.arrived + 1), t: s)
                if let last { XCTAssertLessThan(hypot(p.x - last.x, p.y - last.y), 0.06 * reach, "seed \(seed) at \(s)") }
                last = p
                s += frame
            }
        }
    }

    func testLuckIsTheSameEachTimeAndSpreadEvenly() {
        XCTAssertEqual(Gust.luck(7, 3), Gust.luck(7, 3))
        let draws = (0..<10_000).map { Gust.luck($0, 1) }
        XCTAssertTrue(draws.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(draws.reduce(0, +) / 10_000, 0.5, accuracy: 0.02)
        XCTAssertTrue((800...1200).contains(draws.filter { $0 < 0.1 }.count))
    }

    func testLuckMatchesTheAndroidApps() {
        // From Gust.luck in the Android app, so every speck takes the same path on both.
        XCTAssertEqual(Gust.luck(0, 0), 0)
        XCTAssertEqual(Gust.luck(1, 0), 0.5733975768089294)
        XCTAssertEqual(Gust.luck(7, 3), 0.3930155038833618)
        XCTAssertEqual(Gust.luck(42, 19), 0.7001794576644897)
        XCTAssertEqual(Gust.luck(1000, 13), 0.7917946577072144)
        XCTAssertEqual(Gust.luck(123_456, 7), 0.6970556974411011)
    }
}
