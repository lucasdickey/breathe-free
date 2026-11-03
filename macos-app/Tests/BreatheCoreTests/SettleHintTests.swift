import XCTest
@testable import BreatheCore

/// The line under "Settle in" comes and goes with its words.
final class SettleHintTests: XCTestCase {
    func testOnTheWindItGoesAsItsWordSetsOff() {
        let plan = SessionPlan(cycles: 2)
        let off = SessionPlan.settleSeconds - Gust.leaveLead
        // Not yet as the session begins, all there once "Settle in" has landed...
        XCTAssertEqual(plan.hint(at: -Gust.arriveLead, onTheWind: true), 0, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: 1, onTheWind: true), 1, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: off, onTheWind: true), 1, accuracy: 1e-9)
        // ...going as the word sets off, and gone before the first breath.
        XCTAssertTrue((0.3...0.7).contains(plan.hint(at: off + 0.3, onTheWind: true)))
        XCTAssertEqual(plan.hint(at: off + SessionPlan.hintFadeSeconds, onTheWind: true), 0, accuracy: 1e-9)
        for t in [SessionPlan.settleSeconds, 12, plan.endTime, plan.endTime + 3] {
            XCTAssertEqual(plan.hint(at: t, onTheWind: true), 0)
        }
    }

    func testInPlaceItCrossesWithTheWords() {
        let plan = SessionPlan(cycles: 2)
        let cross = Prompt.fadeSeconds
        // In with "Settle in" as the session begins, and out with it as "Breathe in" comes.
        XCTAssertEqual(plan.hint(at: 0, onTheWind: false), 0, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: cross / 2, onTheWind: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: 7.9, onTheWind: false), 1, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: SessionPlan.settleSeconds, onTheWind: false), 1, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: SessionPlan.settleSeconds + cross / 2, onTheWind: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: SessionPlan.settleSeconds + cross, onTheWind: false), 0, accuracy: 1e-9)
        XCTAssertEqual(plan.hint(at: 12, onTheWind: false), 0, accuracy: 1e-9)
    }

    func testItNeverJumps() {
        let plan = SessionPlan(cycles: 2)
        for onTheWind in [true, false] {
            var t = -1.0
            var last = plan.hint(at: t, onTheWind: onTheWind)
            while t < 12 {
                t += 1.0 / 120
                let now = plan.hint(at: t, onTheWind: onTheWind)
                XCTAssertLessThan(abs(now - last), 0.06, "at \(t)")
                last = now
            }
        }
    }
}
