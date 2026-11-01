#if canImport(AppKit)
import AppKit
import XCTest
@testable import BreatheCore

/// The words' specks blow in and out under the box, never across it: measured on the real words,
/// sampled in the session's own face, every speck followed through its whole gust. As the Android
/// app's WindClearanceTest.
final class WindClearanceTests: XCTestCase {
    private let words = [SessionPlan.settlePrompt] + Phase.allCases.map(\.prompt).reduce(into: [String]()) {
        if !$0.contains($1) { $0.append($1) }
    }

    /// The words' centre sits 58 points under the box's bottom edge (SessionView's promptY)...
    private let boxEdge = -58.0
    /// ...and the dot's glow reaches 16 points below that edge while the dot runs along the bottom.
    private var glowEdge: Double { boxEdge + 16 }

    func testTheWindPassesUnderTheBox() {
        let reach = 960.0, room = 200.0, frame = 1.0 / 120
        var settled = 0.0, top = 0.0
        for word in words {
            let s = WordSpecks(word)
            XCTAssertGreaterThan(s.count, 300, word)
            for i in 0..<s.count {
                // Full lungs, the word at its largest.
                settled = min(settled, s.ys[i] * (1 + Gust.swell))
                var a = 0.0
                while a <= Gust.arrived {
                    let p = Gust.place(tx: s.xs[i], ty: s.ys[i], along: s.along[i], seed: i, arriveSince: a, leaveSince: -1,
                                       reach: reach, room: room, unit: 1, level: 1, t: 8 + a)
                    if p.alpha > 0.02 { top = min(top, p.y) }
                    a += frame
                }
                var l = 0.0
                while l <= Gust.gone {
                    let p = Gust.place(tx: s.xs[i], ty: s.ys[i], along: s.along[i], seed: i, arriveSince: Gust.arrived + 1,
                                       leaveSince: l, reach: reach, room: room, unit: 1, level: 1, t: 11.2 + l)
                    if p.alpha > 0.02 { top = min(top, p.y) }
                    l += frame
                }
            }
        }
        print("letters' top \(settled) pt, highest speck \(top) pt; box edge \(boxEdge), dot glow \(glowEdge)")
        XCTAssertGreaterThan(top, glowEdge, "a speck reaches \(top) pt, into the dot's glow at \(glowEdge)")
    }

    func testTheSettledSpecksSitWhereTheWordsLettersDo() {
        // "Breathe in" has no descenders: its specks run from the top of the B down to the
        // baseline, centred across the word and on the line, as SwiftUI sets the text.
        let font = WordSpecks.sessionFont
        let s = WordSpecks("Breathe in")
        let line = font.ascender - font.descender + font.leading
        let capTop = -line / 2 + (font.ascender - font.capHeight)
        let baseline = -line / 2 + font.ascender
        XCTAssertEqual(s.ys.min()!, capTop, accuracy: 1)
        XCTAssertEqual(s.ys.max()!, baseline, accuracy: 1)
        let width = NSAttributedString(string: "Breathe in", attributes: [.font: font]).size().width
        XCTAssertEqual(s.xs.min()!, -width / 2, accuracy: 3)
        XCTAssertEqual(s.xs.max()!, width / 2, accuracy: 3)
        // From one end of the word to the other, a speck every two thirds of a point or so.
        XCTAssertEqual(s.along.min()!, 0, accuracy: 0.01)
        XCTAssertEqual(s.along.max()!, 1, accuracy: 0.01)
        XCTAssertTrue((1000...3000).contains(s.count), "\(s.count) specks")
    }
}
#endif
