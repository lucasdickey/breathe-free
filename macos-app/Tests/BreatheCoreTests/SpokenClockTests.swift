import XCTest
@testable import BreatheCore

/// How the session lengths and the time left are said to VoiceOver.
final class SpokenClockTests: XCTestCase {
    func testOneIsSaidInTheSingular() {
        XCTAssertEqual(spokenClock(1), "1 second")
        XCTAssertEqual(spokenClock(60), "1 minute")
        XCTAssertEqual(spokenClock(61), "1 minute 1 second")
        XCTAssertEqual(spokenClock(96), "1 minute 36 seconds")
        XCTAssertEqual(spokenClock(121), "2 minutes 1 second")
    }

    func testEverythingElseInThePlural() {
        XCTAssertEqual(spokenClock(0), "0 seconds")
        XCTAssertEqual(spokenClock(32), "32 seconds")
        XCTAssertEqual(spokenClock(160), "2 minutes 40 seconds")
        XCTAssertEqual(spokenClock(300), "5 minutes")
    }
}
