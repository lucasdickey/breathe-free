//
//  WordSpecks.swift
//  BreatheFree
//
//  A word as specks of ink, for the wind to carry (Gust.swift). Kept in step with the Android
//  app's WindWords.kt, which samples its words the same way.
//

import Foundation

/// A word as specks of ink: one for every few pixels its letters cover, taken from the word set
/// as the screen sets it, so the settled specks read as the word in its own face. Positions are
/// in points from the word's centre, y down; `along` is how far across the word each speck is
/// (0 the left end, 1 the right) and `ink` how much of it shows once settled.
struct WordSpecks {
    var xs: [Double] = []
    var ys: [Double] = []
    var along: [Double] = []
    var ink: [Double] = []

    var count: Int { xs.count }

    /// Set three pixels to the point and sampled every second pixel each way: a speck every
    /// two thirds of a point, as on Android's phones.
    static let scale = 3
    static let step = 2
    /// How far apart the specks are, in points.
    static let spacing = Double(step) / Double(scale)

    /// How much of a pixel the letters must cover for it to get a speck.
    static let covered = 0.43
}

#if canImport(AppKit)
import AppKit
import CoreText

extension WordSpecks {
    /// The session's words, as SessionView sets them: 30 points, light.
    static let sessionFont = NSFont.systemFont(ofSize: 30, weight: .light)

    /// Sets `text` in `font`, then keeps a speck wherever its letters cover a pixel well.
    init(_ text: String, font: NSFont = WordSpecks.sessionFont) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = Double(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = Double(ascent + descent + leading)
        // A little room round the line for any letter that reaches past its advance.
        let margin = 4.0
        let k = Double(Self.scale)
        let w = Int(((width + 2 * margin) * k).rounded(.up))
        let h = Int(((height + 2 * margin) * k).rounded(.up))
        guard width > 0, let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                                 space: CGColorSpaceCreateDeviceGray(),
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.scaleBy(x: k, y: k)
        // As the letters are drawn on screen, without the extra weight of font smoothing.
        context.setShouldSmoothFonts(false)
        // White on black, so each pixel's grey is how much of it the letters cover; the line's
        // top `margin` below the bitmap's (y is up here).
        let white = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        context.textPosition = CGPoint(x: margin, y: Double(h) / k - margin - Double(ascent))
        CTLineDraw(CTLineCreateWithAttributedString(white), context)
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return }

        // The letters' own left and right, for how far along the word each speck is.
        var first = Double.infinity, last = -Double.infinity
        var n = 0
        // Rows from the top: a bitmap context keeps its top row first.
        for y in stride(from: 0, to: h, by: Self.step) {
            for x in stride(from: 0, to: w, by: Self.step) {
                let a = Double(data[y * w + x]) / 255
                guard a >= Self.covered else { continue }
                // A little off the grid, so no rows or columns show.
                xs.append((Double(x) + (Gust.luck(n, 10) - 0.5) * Double(Self.step) * 0.6) / k - margin - width / 2)
                ys.append((Double(y) + (Gust.luck(n, 11) - 0.5) * Double(Self.step) * 0.6) / k - margin - height / 2)
                ink.append(a * (0.8 + 0.2 * Gust.luck(n, 12)))
                first = min(first, Double(x) / k)
                last = max(last, Double(x) / k)
                n += 1
            }
        }
        let span = max(1 / k, last - first)
        along = xs.map { min(1, max(0, ($0 + margin + width / 2 - first) / span)) }
    }
}
#endif
