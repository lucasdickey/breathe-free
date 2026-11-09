import XCTest
@testable import BreatheCore

/// The motion behind the four gestures, on the same cases as the Android app's GesturesTest and
/// SessionPauseTest.
final class GesturesTests: XCTestCase {
    // MARK: The spring and the rubber band

    func testASpringStartsWhereItWasLetGoAndComesHome() {
        for spring in [DampedSpring(damping: 0.28, stiffness: 227), DampedSpring(damping: 1, stiffness: 1500),
                       DampedSpring(damping: 1.4, stiffness: 400)] {
            let start = spring.at(0, from: 40, speed: -300)
            XCTAssertEqual(start.value, 40)
            XCTAssertEqual(start.velocity, -300)
            XCTAssertEqual(spring.at(5, from: 40, speed: -300).value, 0, accuracy: 1e-3)
            // Its speed is how fast its place changes.
            let t = 0.05, h = 1e-6
            let rate = (spring.at(t + h, from: 40, speed: -300).value - spring.at(t - h, from: 40, speed: -300).value) / (2 * h)
            XCTAssertEqual(spring.at(t, from: 40, speed: -300).velocity, rate, accuracy: 1e-3)
        }
    }

    func testItIsThePickersSpringFromRest() {
        // SwiftUI's spring(response:dampingFraction:) is this spring with stiffness (2π / response)².
        let response = PickerMotion.openResponse, damping = PickerMotion.openDamping
        let spring = DampedSpring(damping: damping, stiffness: pow(2 * .pi / response, 2))
        for t in stride(from: 0.02, to: 1.2, by: 0.07) {
            XCTAssertEqual(1 + spring.at(t, from: -1, speed: 0).value,
                           PickerMotion.spring(t, response: response, damping: damping).0, accuracy: 1e-9)
        }
    }

    func testTheWobbleOvershootsAndTheStillOneDoesNot() {
        let wobble = OrbPoke.wobble, still = OrbPoke.homeStill
        let wobbleLow = stride(from: 0.0, to: 1.5, by: 0.005).map { wobble.at($0, from: 1, speed: 0).value }.min()!
        let stillLow = stride(from: 0.0, to: 1.5, by: 0.005).map { still.at($0, from: 1, speed: 0).value }.min()!
        XCTAssertLessThan(wobbleLow, -0.3)
        XCTAssertGreaterThanOrEqual(stillLow, -1e-9)
    }

    func testTheRubberBandHoldsBackMoreTheFurtherItGoes() {
        XCTAssertEqual(rubberBand(0, limit: 40), 0)
        XCTAssertEqual(rubberBand(10, limit: 40), 10 * 40 * 0.55 / (40 + 5.5), accuracy: 1e-12)
        XCTAssertEqual(rubberBand(-10, limit: 40), -rubberBand(10, limit: 40))
        XCTAssertLessThan(rubberBand(1e6, limit: 40), 40)
        XCTAssertLessThan(rubberBand(80, limit: 40) - rubberBand(40, limit: 40), rubberBand(40, limit: 40))
        for band in [-30.0, -5, 0.5, 12, 39] {
            XCTAssertEqual(rubberBand(unRubberBand(band, limit: 40), limit: 40), band, accuracy: 1e-9)
        }
    }

    func testThePointersSpeedIsHowFastItWent() {
        var tracker = VelocityTracker()
        for i in 0..<10 { tracker.add(SIMD2(Double(i) * 8, Double(i) * -2), at: Double(i) * 0.016) }
        XCTAssertEqual(tracker.velocity.x, 8 / 0.016, accuracy: 1)
        XCTAssertEqual(tracker.velocity.y, -2 / 0.016, accuracy: 1)
        // Let go as it moves, it is going as fast as it was; held still first, it was going nowhere.
        XCTAssertEqual(tracker.velocity(at: 0.15).x, 8 / 0.016, accuracy: 1)
        XCTAssertEqual(tracker.velocity(at: 0.4), .zero)
    }

    // MARK: The orb

    func testPulledFarTheOrbIsHeldBackShortOfItsReach() {
        var poke = OrbPoke(side: 112, still: false)
        poke.down(SIMD2(56, 56), at: 1)
        poke.move(SIMD2(56, 456), at: 1.1)
        let reach = 112 * OrbPoke.reach
        let p = poke.pull(at: 1.1)
        XCTAssertEqual(p.x, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(p.y, 0.8 * reach)
        XCTAssertLessThan(p.y, reach)
        // Drawn out toward the pointer, and pressed in a little.
        XCTAssertEqual(poke.axis, .pi / 2, accuracy: 1e-9)
        XCTAssertGreaterThan(poke.stretch(at: 1.1), 0.25)
        XCTAssertEqual(poke.dent(at: 1.1), 1, accuracy: 1e-9)
    }

    func testLetGoItSpringsHomeWithAWobbleAndARing() {
        var poke = OrbPoke(side: 112, still: false)
        poke.down(SIMD2(0, 0), at: 1)
        for i in 1...6 { poke.move(SIMD2(Double(i) * 6, Double(i) * 5), at: 1 + Double(i) * 0.016) }
        poke.up(at: 1.1, radius: 30)
        XCTAssertFalse(poke.isHeld)
        // It overshoots its place on the way home, then comes to rest there.
        let path = stride(from: 1.1, to: 3, by: 0.004).map { poke.pull(at: $0) }
        XCTAssertLessThan(path.map(\.x).min()!, -0.5)
        XCTAssertEqual(norm(poke.pull(at: 4)), 0, accuracy: 0.01)
        XCTAssertEqual(poke.stretch(at: 4), 0, accuracy: 1e-3)
        XCTAssertEqual(poke.dent(at: 4), 0, accuracy: 1e-3)
        // The ring leaves the orb's edge, spreads and fades.
        let ring = try? XCTUnwrap(poke.ring(at: 1.1))
        XCTAssertEqual(ring?.radius ?? 0, 30, accuracy: 1e-9)
        XCTAssertGreaterThan(poke.ring(at: 2)!.radius, 30)
        XCTAssertLessThan(poke.ring(at: 2)!.alpha, ring?.alpha ?? 0)
        XCTAssertNil(poke.ring(at: 1.1 + OrbPoke.ringSeconds + 0.01))
    }

    func testCaughtOnItsWayHomeItCarriesOnFromWhereItIs() {
        var poke = OrbPoke(side: 112, still: false)
        poke.down(SIMD2(0, 0), at: 1)
        poke.move(SIMD2(60, 0), at: 1.05)
        poke.up(at: 1.2, radius: 30)
        let flying = poke.pull(at: 1.25)
        poke.down(SIMD2(200, 200), at: 1.25)
        XCTAssertEqual(poke.pull(at: 1.25).x, flying.x, accuracy: 1e-9)
        XCTAssertEqual(poke.pull(at: 1.25).y, flying.y, accuracy: 1e-9)
        // And the pointer takes it on from there, without a jump.
        poke.move(SIMD2(201, 200), at: 1.27)
        XCTAssertEqual(poke.pull(at: 1.27).x, flying.x, accuracy: 1.5)
    }

    func testWithReduceMotionItGoesHomeWithoutAWobbleOrARing() {
        var poke = OrbPoke(side: 112, still: true)
        poke.down(SIMD2(0, 0), at: 1)
        poke.move(SIMD2(40, 0), at: 1.05)
        poke.up(at: 1.3, radius: 30)
        let xs = stride(from: 1.3, to: 2.5, by: 0.004).map { poke.pull(at: $0).x }
        XCTAssertGreaterThanOrEqual(xs.min()!, -1e-6)
        XCTAssertNil(poke.ring(at: 1.4))
        XCTAssertGreaterThanOrEqual(stride(from: 1.3, to: 2.5, by: 0.004).map { poke.dent(at: $0) }.min()!, -1e-6)
    }

    // MARK: The session length

    /// The Mac's row: drops 46 across, 8 apart.
    private func slide(from chosen: Int, by steps: Double, moves: Int = 12, frame: Double = 0.016,
                       stillFor: Double = 0) -> (picked: Int, ticks: Int, slide: BeadSlide) {
        let choices = SessionPlan.cycleChoices
        let step = 54.0
        var slide = BeadSlide(count: choices.count, step: step, size: 46, pointer: 0)
        let x0 = slide.slot(choices.firstIndex(of: chosen)!)
        slide = BeadSlide(count: choices.count, step: step, size: 46, pointer: x0)
        var ticks = 0
        var t = 0.0
        for i in 1...moves {
            t += frame
            if slide.move(x0 + step * steps * Double(i) / Double(moves), at: t) { ticks += 1 }
        }
        let to = slide.up(at: t + stillFor)
        return (choices[to], ticks, slide)
    }

    func testSlidingTheSessionLengthPicksWhereItIsLetGo() {
        let (picked, ticks, slide) = slide(from: 6, by: 2.2, frame: 0.04, stillFor: 0.3)
        XCTAssertEqual(picked, 20)
        XCTAssertEqual(ticks, 2)
        // It arrives at the drop, and quickly.
        let arrives = try? XCTUnwrap(slide.arrivesAt)
        XCTAssertLessThan((arrives ?? 99) - slide.letGoAt, 0.5)
        XCTAssertEqual(slide.bead(at: arrives ?? 0), slide.slot(3), accuracy: BeadSlide.arrived)
    }

    func testAFlickCarriesOnToTheDropItWasHeadingFor() {
        // Fast: 1.6 drops in a tenth of a second, let go mid-move.
        XCTAssertEqual(slide(from: 6, by: 1.6, moves: 6).picked, 36)
    }

    func testPastTheLastDropItHoldsBackAndPicksTheLast() {
        let (picked, _, slide) = slide(from: 36, by: 4, frame: 0.04, stillFor: 0.3)
        XCTAssertEqual(picked, 50)
        // Held back: never more than half a drop past the last.
        var held = BeadSlide(count: 6, step: 54, size: 46, pointer: slide.slot(4))
        held.move(slide.slot(4) + 4 * 54, at: 0.1)
        XCTAssertLessThan(held.bead(at: 0.1), slide.slot(5) + 23)
        XCTAssertGreaterThan(held.bead(at: 0.1), slide.slot(5))
    }

    func testTheBeadRunsIntoTheDropItIsOver() {
        let row = BeadSlide(count: 6, step: 54, size: 46, pointer: 0)
        var slide = BeadSlide(count: 6, step: 54, size: 46, pointer: row.slot(1))
        slide.move(row.slot(3), at: 0.1)
        XCTAssertEqual(slide.under(slide.slot(3), at: 0.1), 1, accuracy: 1e-9)
        XCTAssertEqual(slide.under(slide.slot(1), at: 0.1), 0)
    }

    // MARK: The volume

    func testTheVolumeGivesAndSpringsBack() {
        var give = Give()
        give.drag(past: 0, at: 0)
        XCTAssertEqual(give.stretch(at: 0), 0)
        for i in 1...12 { give.drag(past: Double(i) * 10, at: Double(i) * 0.016) }
        let s = give.stretch(at: 0.2)
        XCTAssertGreaterThan(s, 0.7 * Give.limit)
        XCTAssertLessThan(s, Give.limit)
        give.release(at: 0.2)
        XCTAssertEqual(give.stretch(at: 0.2), s, accuracy: 1e-9)
        XCTAssertEqual(give.stretch(at: 2), 0, accuracy: 1e-3)
        // Past the start, the other way.
        give.drag(past: -30, at: 3)
        XCTAssertLessThan(give.stretch(at: 3), 0)
    }

    // MARK: The ✕

    func testHoldingTheCrossFillsItAndThenItIsFull() {
        var hold = HoldFill()
        hold.press(at: 5)
        XCTAssertEqual(hold.fill(at: 5.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(hold.fullAt ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(hold.fill(at: 6.2), 1)
    }

    func testLettingGoTooSoonDrainsItAndAHoldAfterFillsFromEmpty() {
        var hold = HoldFill()
        hold.press(at: 5)
        hold.release(at: 5.8)
        XCTAssertFalse(hold.isHeld)
        XCTAssertNil(hold.fullAt)
        XCTAssertEqual(hold.fill(at: 5.8), 0.8, accuracy: 1e-9)
        // Drains quickly: most of the way in the first half of its time.
        XCTAssertLessThan(hold.fill(at: 5.9), 0.25)
        XCTAssertEqual(hold.fill(at: 6.0), 0, accuracy: 1e-9)
        hold.press(at: 6.8)
        XCTAssertEqual(hold.fullAt ?? 0, 7.8, accuracy: 1e-9)
    }

    func testCaughtWhileDrainingItFillsOnFromThere() {
        var hold = HoldFill()
        hold.press(at: 0)
        hold.release(at: 0.6)
        let left = hold.fill(at: 0.65)
        hold.press(at: 0.65)
        XCTAssertEqual(hold.fullAt ?? 0, 0.65 + (1 - left), accuracy: 1e-9)
    }

    func testTheEasingRunsFromStartToEndAndSettlesSlowly() {
        XCTAssertEqual(linearOutSlowIn(0), 0, accuracy: 1e-9)
        XCTAssertEqual(linearOutSlowIn(1), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(linearOutSlowIn(0.5), 0.8)
        XCTAssertGreaterThan(linearOutSlowIn(0.1), linearOutSlowIn(0.05))
    }
}
