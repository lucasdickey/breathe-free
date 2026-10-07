import XCTest
@testable import BreatheCore

final class BreathTimelineTests: XCTestCase {
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
