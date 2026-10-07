import XCTest
@testable import BreatheCore

final class BreathTimelineTests: XCTestCase {
    func testTheWordsFollowTheBox() {
        let plan = SessionPlan(cycles: 2)
        let seen = [0, 3, 8.1, 12.2, 16.05, 20, 24, 39.9, 40, 41].map { plan.prompt(at: $0) }
        let expected = [("Settle in", ""), ("Settle in", ""), ("Breathe in", "Settle in"), ("Hold", "Breathe in"),
                        ("Breathe out", "Hold"), ("Hold", "Breathe out"), ("Breathe in", "Hold"),
                        ("Hold", "Breathe out"), ("", "Hold"), ("", "Hold")]
        XCTAssertEqual(seen.map { $0.text }, expected.map { $0.0 })
        XCTAssertEqual(seen.map { $0.previous }, expected.map { $0.1 })
        XCTAssertEqual(plan.prompt(at: 12.2).since, 0.2, accuracy: 1e-9)
    }

    func testTheWordsCrossWithoutAFlash() {
        // At every change, what was fully showing just before is what starts fading out, and
        // the new words start from nothing: the screen goes straight from one to the other.
        let plan = SessionPlan(cycles: 3)
        for i in 0...plan.phaseCount {
            let change = i < plan.phaseCount ? plan.phaseStart(i) : plan.endTime
            let before = plan.prompt(at: change - 1e-6)
            let after = plan.prompt(at: change)
            XCTAssertEqual(before.fade, 1, accuracy: 1e-9)
            XCTAssertEqual(after.previous, before.text)
            XCTAssertEqual(after.fade, 0, accuracy: 1e-9)
        }
        var last = -1.0
        for n in 0...40 {
            let fade = Prompt(text: "Hold", previous: "Breathe in", since: Double(n) * 0.01).fade
            XCTAssertGreaterThanOrEqual(fade, last)
            last = fade
        }
        XCTAssertEqual(Prompt(text: "Hold", previous: "Breathe in", since: Prompt.fadeSeconds).fade, 1, accuracy: 1e-12)
    }

    private let plan = SessionPlan(cycles: 2)

    func testSettleCountsDownFromEight() {
        let start = plan.frame(at: 0)
        XCTAssertEqual(start.stage, .settle)
        XCTAssertNil(start.phase)
        XCTAssertEqual(start.countdown, 8)
        XCTAssertEqual(plan.frame(at: 0.5).countdown, 8)
        XCTAssertEqual(plan.frame(at: 1.0).countdown, 7)
        XCTAssertEqual(plan.frame(at: 7.999).countdown, 1)
        XCTAssertEqual(plan.frame(at: 7.999).level, 0)
    }

    func testPhasesTurnOnTheBoundaries() {
        let expected: [(Double, Phase)] = [
            (8, .inhale), (12, .holdFull), (16, .exhale), (20, .holdEmpty), (24, .inhale), (36, .holdEmpty),
        ]
        for (t, phase) in expected {
            let f = plan.frame(at: t)
            XCTAssertEqual(f.phase, phase, "phase at \(t)")
            XCTAssertEqual(f.countdown, 4, "countdown at \(t)")
            XCTAssertEqual(f.phaseElapsed, 0, accuracy: 1e-12)
        }
        XCTAssertEqual(plan.frame(at: 11.999).phase, .inhale)
        XCTAssertEqual(plan.frame(at: 11.999).countdown, 1)
        XCTAssertEqual(plan.frame(at: 13).countdown, 3)
        XCTAssertEqual(plan.frame(at: 24).cycle, 1)
    }

    func testLevelNeverJumps() {
        var last = plan.frame(at: 0).level
        var worst = 0.0
        var t = 0.0
        while t < plan.endTime + 2 {
            let l = plan.frame(at: t).level
            worst = max(worst, abs(l - last))
            last = l
            t += 0.001
        }
        XCTAssertLessThan(worst, 0.001)
    }

    func testEndsExactlyAfterTheLastHold() {
        XCTAssertEqual(plan.endTime, 40)
        let last = plan.frame(at: 39.999)
        XCTAssertEqual(last.stage, .breathing)
        XCTAssertEqual(last.phase, .holdEmpty)
        XCTAssertEqual(plan.frame(at: 40).stage, .complete)
        XCTAssertEqual(plan.frame(at: 9.5).remaining, 30.5, accuracy: 1e-12)
    }

    func testBoxSidesJoinUpAndStayOnTheOutline() {
        let h = 100.0, r = 18.0
        for side in 0..<4 {
            let a = BoxGeometry.point(side: side, f: 1, cx: 0, cy: 0, h: h, r: r)
            let b = BoxGeometry.point(side: side + 1, f: 0, cx: 0, cy: 0, h: h, r: r)
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
        let mid = BoxGeometry.point(side: 0, f: 0.5, cx: 0, cy: 0, h: h, r: r)
        XCTAssertEqual(mid.x, -h, accuracy: 1e-9)
        XCTAssertEqual(mid.y, 0, accuracy: 1e-9)
        for side in 0..<4 {
            for i in 0...100 {
                let p = BoxGeometry.point(side: side, f: Double(i) / 100, cx: 0, cy: 0, h: h, r: r)
                let x = abs(p.x), y = abs(p.y)
                let onEdge = (abs(x - h) < 1e-9 && y <= h - r + 1e-9) || (abs(y - h) < 1e-9 && x <= h - r + 1e-9)
                let onCorner = abs(hypot(x - (h - r), y - (h - r)) - r) < 1e-9
                XCTAssertTrue(onEdge || onCorner, "off outline at side \(side) f \(i)")
            }
        }
    }
}
