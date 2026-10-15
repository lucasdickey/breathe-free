import XCTest
@testable import BreatheCore

final class IconPathsTests: XCTestCase {
    /// Points along the pieces' curves and lines, as the path would be drawn.
    private func points(_ pieces: [PathPiece]) -> [SIMD2<Double>] {
        var at = SIMD2<Double>(0, 0)
        var out: [SIMD2<Double>] = []
        for piece in pieces {
            switch piece {
            case .move(let p):
                at = p
                out.append(p)
            case .line(let p):
                for n in 1...8 { out.append(at + (p - at) * Double(n) / 8) }
                at = p
            case .curve(let c1, let c2, let p):
                for n in 1...8 {
                    let t = Double(n) / 8, u = 1 - t
                    out.append(u * u * u * at + 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t * p)
                }
                at = p
            case .close:
                break
            }
        }
        return out
    }

    private func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { ((a - b) * (a - b)).sum().squareRoot() }

    func testACircleOfTwoArcsStaysOnItsCircle() {
        let pieces = IconPath.read("M5.5 8.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0z")
        XCTAssertEqual(pieces.first, .move(SIMD2(5.5, 8.5)))
        XCTAssertEqual(pieces.last, .close)
        let all = points(pieces)
        for p in all { XCTAssertEqual(distance(p, SIMD2(9, 8.5)), 3.5, accuracy: 0.01) }
        // Round the whole of it: below the middle first, then above.
        XCTAssertEqual(all.map(\.y).max()!, 12, accuracy: 0.01)
        XCTAssertEqual(all.map(\.y).min()!, 5, accuracy: 0.01)
    }

    func testTheBellsDomeIsOverTheTop() {
        let dome = points(IconPath.read("M6.5 11a5.5 5.5 0 0 1 11 0"))
        for p in dome {
            XCTAssertEqual(distance(p, SIMD2(12, 11)), 5.5, accuracy: 0.01)
            XCTAssertLessThanOrEqual(p.y, 11 + 1e-9)
        }
    }

    func testTheVoicesWavesBulgeAwayFromTheHead() {
        // A small arc between two points 5.6 apart, clockwise: its centre to their left.
        let wave = points(IconPath.read("M16 6.2a4 4 0 0 1 0 5.6"))
        let centre = SIMD2(16 - (16 - 2.8 * 2.8).squareRoot(), 9)
        for p in wave { XCTAssertEqual(distance(p, centre), 4, accuracy: 0.01) }
        XCTAssertEqual(wave.map(\.x).max()!, centre.x + 4, accuracy: 0.01)
        XCTAssertEqual(wave.last!, SIMD2(16, 11.8))
    }

    func testRelativeAndRepeatedCommands() {
        // The silent speaker: lines across, along and up, then a cross of two lines.
        let speaker = IconPath.read("M3 9h4l5-4.5v15L7 15H3zM15.5 9.5l5 5M20.5 9.5l-5 5")
        XCTAssertEqual(speaker, [
            .move(SIMD2(3, 9)), .line(SIMD2(7, 9)), .line(SIMD2(12, 4.5)), .line(SIMD2(12, 19.5)),
            .line(SIMD2(7, 15)), .line(SIMD2(3, 15)), .close,
            .move(SIMD2(15.5, 9.5)), .line(SIMD2(20.5, 14.5)), .move(SIMD2(20.5, 9.5)), .line(SIMD2(15.5, 14.5)),
        ])
        // The waves: a curve, then three more that mirror the one before.
        let wave = IconPath.read("M3 9c1.5-2 3-2 4.5 0s3 2 4.5 0 3-2 4.5 0 3 2 4.5 0")
        XCTAssertEqual(wave, [
            .move(SIMD2(3, 9)),
            .curve(SIMD2(4.5, 7), SIMD2(6, 7), SIMD2(7.5, 9)),
            .curve(SIMD2(9, 11), SIMD2(10.5, 11), SIMD2(12, 9)),
            .curve(SIMD2(13.5, 7), SIMD2(15, 7), SIMD2(16.5, 9)),
            .curve(SIMD2(18, 11), SIMD2(19.5, 11), SIMD2(21, 9)),
        ])
    }

    func testEveryIconReadsToTheEnd() {
        for (pieces, moves) in [(FanIcons.sound(.ambient), 2), (FanIcons.sound(.bells), 2), (FanIcons.sound(.silent), 3),
                                (FanIcons.voiceOn, 4), (FanIcons.voiceOff, 4)] {
            XCTAssertEqual(pieces.filter { if case .move = $0 { return true } else { return false } }.count, moves)
            // Everything on the grid.
            for p in points(pieces) {
                XCTAssertTrue((0...24).contains(p.x) && (0...24).contains(p.y), "\(p) off the grid")
            }
        }
    }
}
