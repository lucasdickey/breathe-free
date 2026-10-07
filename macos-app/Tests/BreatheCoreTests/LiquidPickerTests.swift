import XCTest
@testable import BreatheCore

final class LiquidPickerTests: XCTestCase {
    private let size = 46.0, step = 54.0

    // MARK: The outline

    func testARoundDropTracesItsCircle() {
        let loops = LiquidOutline.loops([LiquidDrop(x: 10, radius: 23)], inset: 0.5)
        XCTAssertEqual(loops.count, 1)
        XCTAssertGreaterThan(loops[0].count, 60)
        for p in loops[0] {
            XCTAssertEqual(((p.x - 10) * (p.x - 10) + p.y * p.y).squareRoot(), 22.5, accuracy: 0.05)
        }
    }

    func testDropsAtRestStaySeparate() {
        let row = (0..<6).map { LiquidDrop(x: (Double($0) - 2.5) * step, radius: size / 2) }
        XCTAssertEqual(LiquidOutline.loops(row).count, 6)
    }

    func testDropsWithinReachRunTogether() {
        // 4 points apart: separate on their own, joined by a neck when the second reaches.
        let apart = [LiquidDrop(x: 0, radius: 23), LiquidDrop(x: 50, radius: 23)]
        XCTAssertEqual(LiquidOutline.loops(apart).count, 2)
        var reaching = apart
        reaching[1].reach = 22
        let joined = LiquidOutline.loops(reaching)
        XCTAssertEqual(joined.count, 1)
        // The neck is narrower than the drops.
        let neck = joined[0].filter { abs($0.x - 25) < 1 }.map { abs($0.y) }.max() ?? 0
        XCTAssertGreaterThan(neck, 2)
        XCTAssertLessThan(neck, 20)
    }

    func testADropInsideAnotherAddsNothingWithoutReach() {
        let loops = LiquidOutline.loops([LiquidDrop(x: 0, radius: 23), LiquidDrop(x: 3, radius: 10)])
        XCTAssertEqual(loops.count, 1)
        for p in loops[0] {
            XCTAssertEqual((p.x * p.x + p.y * p.y).squareRoot(), 23, accuracy: 0.05)
        }
    }

    func testNoDropsNoOutline() {
        XCTAssertTrue(LiquidOutline.loops([]).isEmpty)
        XCTAssertTrue(LiquidOutline.loops([LiquidDrop(x: 0, radius: 0)]).isEmpty)
    }

    // MARK: The motion

    func testAtRestOpenEveryCountShowsInItsPlace() {
        let drops = PickerMotion(count: 6, open: true, chosen: 2).drops(at: 0, size: size, step: step)
        for (i, d) in drops.enumerated() {
            XCTAssertEqual(d.x, (Double(i) - 2.5) * step, accuracy: 1e-9)
            XCTAssertEqual(d.radius, 23, accuracy: 1e-9)
            XCTAssertEqual(d.stretch, 1, accuracy: 1e-9)
            XCTAssertEqual(d.reach, 0, accuracy: 1e-9)
            XCTAssertEqual(d.accent, i == 2 ? 1 : 0)
            XCTAssertEqual(d.label, 1, accuracy: 1e-9)
        }
    }

    func testAtRestClosedOnlyTheChosenCountShows() {
        let drops = PickerMotion(count: 6, open: false, chosen: 2).drops(at: 0, size: size, step: step)
        XCTAssertEqual(drops[2].x, 0, accuracy: 1e-9)
        XCTAssertEqual(drops[2].radius, 23, accuracy: 1e-9)
        for i in [0, 1, 3, 4, 5] {
            XCTAssertEqual(drops[i].radius, 0, accuracy: 1e-9)
            XCTAssertEqual(drops[i].label, 0, accuracy: 1e-9)
        }
    }

    func testOpeningBudsOutOfTheChosenDropAndSettles() {
        let motion = PickerMotion(count: 6, open: false, chosen: 2).changed(open: true, chosen: 2, at: 5)
        let start = motion.drops(at: 5, size: size, step: step)
        for i in [0, 1, 3, 4, 5] { XCTAssertEqual(start[i].radius, 0, accuracy: 1e-9) }
        // Partway, the drops near the chosen one are out and running into it.
        let partway = motion.drops(at: 5.12, size: size, step: step)
        XCTAssertGreaterThan(partway[1].radius, 5)
        XCTAssertGreaterThan(partway[1].reach, 1)
        XCTAssertLessThan(partway[0].x, 0)
        XCTAssertEqual(LiquidOutline.loops(motion.order.map { partway[$0].liquid }).count, 1)
        // The ones further out start later.
        XCTAssertLessThan(motion.spread(0, at: 5.05).value, motion.spread(1, at: 5.05).value)
        XCTAssertFalse(motion.isSettled(at: 5.5))
        XCTAssertTrue(motion.isSettled(at: 6.3))
        let end = motion.drops(at: 6.3, size: size, step: step)
        for (i, d) in end.enumerated() {
            XCTAssertEqual(d.x, (Double(i) - 2.5) * step, accuracy: 0.01)
            XCTAssertEqual(d.radius, 23, accuracy: 0.01)
            XCTAssertEqual(d.label, 1, accuracy: 0.01)
        }
        XCTAssertEqual(LiquidOutline.loops(motion.order.map { end[$0].liquid }).count, 6)
    }

    func testPickingFlowsIntoThePickedDropWhichTakesTheColour() {
        let open = PickerMotion(count: 6, open: true, chosen: 2)
        let motion = open.changed(open: false, chosen: 1, at: 3)
        let start = motion.drops(at: 3, size: size, step: step)
        XCTAssertEqual(start[1].accent, 0, accuracy: 1e-9)
        XCTAssertEqual(start[2].accent, 1, accuracy: 1e-9)
        XCTAssertEqual(start[1].x, -1.5 * step, accuracy: 1e-9)
        let soon = motion.drops(at: 3 + PickerMotion.recolour, size: size, step: step)
        XCTAssertEqual(soon[1].accent, 1, accuracy: 1e-9)
        XCTAssertEqual(soon[2].accent, 0, accuracy: 1e-9)
        // Counts other than the picked one fade as their drops leave their places.
        XCTAssertLessThan(motion.drops(at: 3.08, size: size, step: step)[4].label, 0.5)
        let end = motion.drops(at: 4.3, size: size, step: step)
        XCTAssertEqual(end[1].x, 0, accuracy: 0.01)
        XCTAssertEqual(end[1].radius, 23, accuracy: 0.01)
        for i in [0, 2, 3, 4, 5] { XCTAssertEqual(end[i].radius, 0, accuracy: 0.01) }
        XCTAssertEqual(LiquidOutline.loops(motion.order.map { end[$0].liquid }).count, 1)
    }

    func testAChangeMidwayCarriesOnFromWhereTheDropsAre() {
        let opening = PickerMotion(count: 6, open: false, chosen: 2).changed(open: true, chosen: 2, at: 0)
        let closing = opening.changed(open: false, chosen: 2, at: 0.15)
        for i in 0..<6 {
            XCTAssertEqual(closing.spread(i, at: 0.15).value, opening.spread(i, at: 0.15).value, accuracy: 1e-9)
        }
        XCTAssertTrue(closing.drops(at: 1.5, size: size, step: step).allSatisfy { $0.x.isFinite && $0.radius.isFinite })
    }

    func testTheSpringMatchesItsEnds() {
        for (response, damping) in [(0.42, 0.68), (0.34, 1.0)] {
            XCTAssertEqual(PickerMotion.spring(0, response: response, damping: damping).0, 0)
            XCTAssertEqual(PickerMotion.spring(3, response: response, damping: damping).0, 1, accuracy: 1e-6)
            // The rate is the slope of the value.
            let t = 0.1, h = 1e-6
            let slope = (PickerMotion.spring(t + h, response: response, damping: damping).0
                - PickerMotion.spring(t - h, response: response, damping: damping).0) / (2 * h)
            XCTAssertEqual(PickerMotion.spring(t, response: response, damping: damping).1, slope, accuracy: 1e-4)
        }
    }
}
