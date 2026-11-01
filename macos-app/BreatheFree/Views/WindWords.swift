//
//  WindWords.swift
//  BreatheFree
//
//  Draws the session's words as specks on the wind (Gust), in the session's own face and size.
//  Kept in step with the Android app's WindWords.kt.
//

import SwiftUI

final class WindWords {
    static let shared = WindWords()

    /// Each word, sampled the first time it is drawn.
    private var words: [String: WordSpecks] = [:]

    /// The specks are drawn in a few steps of opacity: one fill for each.
    private static let levels = 16

    /// Each speck is drawn a little wider than the space between them, so the settled word reads whole.
    private static let diameter = WordSpecks.spacing * 1.25

    func specks(_ text: String) -> WordSpecks {
        if let known = words[text] { return known }
        let sampled = WordSpecks(text)
        words[text] = sampled
        return sampled
    }

    /// Draws `gust`'s words centred on (`cx`, `cy`) in `color`, the wind reaching `reach` across
    /// and the sky clear for `room` points below them: `level` is how full the lungs are, and `t`
    /// session time.
    func draw(_ context: inout GraphicsContext, gust: GustWords, cx: Double, cy: Double, reach: Double, room: Double,
              level: Double, t: Double, color: Paint) {
        var paths = [Path](repeating: Path(), count: Self.levels)
        if !gust.leaving.isEmpty && gust.leaveSince < Gust.gone {
            add(specks(gust.leaving), arriveSince: Gust.arrived + 1, leaveSince: gust.leaveSince,
                cx: cx, cy: cy, reach: reach, room: room, level: level, t: t, into: &paths)
        }
        if !gust.arriving.isEmpty {
            add(specks(gust.arriving), arriveSince: gust.arriveSince, leaveSince: -1,
                cx: cx, cy: cy, reach: reach, room: room, level: level, t: t, into: &paths)
        }
        for (i, path) in paths.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(color.color(Double(i + 1) / Double(Self.levels))))
        }
    }

    private func add(_ w: WordSpecks, arriveSince: Double, leaveSince: Double, cx: Double, cy: Double,
                     reach: Double, room: Double, level: Double, t: Double, into paths: inout [Path]) {
        let d = Self.diameter
        for i in 0..<w.count {
            let p = Gust.place(tx: w.xs[i], ty: w.ys[i], along: w.along[i], seed: i,
                               arriveSince: arriveSince, leaveSince: leaveSince,
                               reach: reach, room: room, unit: 1, level: level, t: t)
            let bucket = Int((p.alpha * w.ink[i] * Double(Self.levels)).rounded()) - 1
            guard bucket >= 0 else { continue }
            paths[min(bucket, Self.levels - 1)].addEllipse(in: CGRect(x: cx + p.x - d / 2, y: cy + p.y - d / 2,
                                                                      width: d, height: d))
        }
    }
}
