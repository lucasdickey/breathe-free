import XCTest
@testable import BreatheCore

/// The same checks as the Android app's DripTest, on the same numbers.
final class DripTests: XCTestCase {
    func testNothingHangsAtFirst() {
        let f = Drip.at(1)
        XCTAssertNil(f.hanging)
        XCTAssertNil(f.drop)
        XCTAssertEqual(f.orb, 0)
        XCTAssertEqual(Drip.countAlpha(1), 0)
    }

    func testTheDropFallsFromWhereItLetGo() throws {
        // The last moment it hangs and the first moment it falls are the same drop, in the same place.
        let hanging = try XCTUnwrap(Drip.at(4.15 - 1e-6).hanging)
        let falling = try XCTUnwrap(Drip.at(4.15).drop)
        XCTAssertEqual(hanging.by, falling.y, accuracy: 1e-4)
        XCTAssertEqual(hanging.rb, falling.r, accuracy: 1e-4)
    }

    func testItLandsInTheMiddleAsTheOrb() throws {
        let before = try XCTUnwrap(Drip.at(Drip.lands - 1e-6).drop)
        XCTAssertLessThan(abs(before.y), 1e-4)
        let landed = Drip.at(Drip.lands)
        XCTAssertNil(landed.drop)
        XCTAssertEqual(before.r, landed.orb, accuracy: 1e-9)
        XCTAssertEqual(Drip.countAlpha(Drip.lands), 0)
    }

    func testItHasSettledBeforeTheFirstBreath() {
        // By the breath in the orb is the empty orb, still, and the count has come in.
        let f = Drip.at(SessionPlan.settleSeconds - 1e-6)
        XCTAssertEqual(f.orb, BoxGeometry.orbMin, accuracy: 1e-6)
        XCTAssertLessThan(abs(f.squash), 1e-4)
        XCTAssertNil(f.hanging)
        XCTAssertNil(f.bead)
        XCTAssertNil(f.drop)
        XCTAssertNil(f.satellite)
        XCTAssertEqual(Drip.countAlpha(SessionPlan.settleSeconds), 1)
    }

    func testABeadStaysOnTheLineForAMoment() {
        XCTAssertNotNil(Drip.at(4.3).bead)
        XCTAssertNil(Drip.at(5).bead)
    }
}
