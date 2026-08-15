import CoreGraphics

/// Line-breaking for a row of chips that wraps instead of scrolling.
///
/// This exists because `iOSTaskRow`'s metadata strip was a horizontal `ScrollView` nested inside a
/// vertical one. The row's own tap gesture beat the inner scroll view, so the strip never actually
/// scrolled — anything past the right edge was unreachable rather than merely off-screen, and the
/// row quietly lied about how much it was showing. Adding a horizontal swipe gesture to the same
/// row made a third claimant for the same drag; the honest fix is to stop hiding content behind a
/// gesture at all.
///
/// The arithmetic lives here, outside `#if os(iOS)`, so `CadenceTests` (which builds for macOS)
/// can pin it. `CadenceWrappingHStack` is the thin `Layout` on top.
nonisolated enum CadenceFlowLayoutSupport {
    /// One laid-out line: which items are on it, and the extent they occupy.
    struct Line: Equatable {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    /// Greedy line-breaking, left to right.
    ///
    /// An item wider than `availableWidth` still gets a line of its own rather than being dropped —
    /// the caller narrows it at placement time. Nothing this function does can make an item
    /// disappear; that is the whole point of it.
    static func lines(itemSizes: [CGSize], availableWidth: CGFloat, spacing: CGFloat) -> [Line] {
        guard !itemSizes.isEmpty else { return [] }

        // An unspecified or degenerate proposal means "as wide as you like", which is what SwiftUI
        // asks for when it is measuring ideal size. Everything lands on one line.
        let limit = availableWidth.isFinite && availableWidth > 0 ? availableWidth : .infinity
        let gap = max(spacing, 0)

        var lines: [Line] = []
        var current = Line(indices: [], width: 0, height: 0)

        for (index, size) in itemSizes.enumerated() {
            let itemWidth = max(size.width, 0)
            let itemHeight = max(size.height, 0)

            if current.indices.isEmpty {
                current = Line(indices: [index], width: itemWidth, height: itemHeight)
                continue
            }

            let extended = current.width + gap + itemWidth
            if extended > limit {
                lines.append(current)
                current = Line(indices: [index], width: itemWidth, height: itemHeight)
            } else {
                current.indices.append(index)
                current.width = extended
                current.height = max(current.height, itemHeight)
            }
        }

        lines.append(current)
        return lines
    }

    /// The extent the given lines occupy. Width is the widest line, not the proposal — a strip with
    /// one short chip should not claim the full row width.
    static func size(ofLines lines: [Line], lineSpacing: CGFloat) -> CGSize {
        guard !lines.isEmpty else { return .zero }
        let width = lines.map(\.width).max() ?? 0
        let gaps = max(lineSpacing, 0) * CGFloat(lines.count - 1)
        let height = lines.reduce(0) { $0 + $1.height } + gaps
        return CGSize(width: width, height: height)
    }

    /// Top-left placement points, indexed to match `itemSizes`.
    ///
    /// Items are centred vertically within their line, so a taller chip does not drag its shorter
    /// neighbours' baselines around.
    static func placements(
        itemSizes: [CGSize],
        lines: [Line],
        origin: CGPoint,
        spacing: CGFloat,
        lineSpacing: CGFloat
    ) -> [CGPoint] {
        var points = [CGPoint](repeating: origin, count: itemSizes.count)
        let gap = max(spacing, 0)
        var y = origin.y

        for line in lines {
            var x = origin.x
            for index in line.indices {
                guard itemSizes.indices.contains(index) else { continue }
                let height = max(itemSizes[index].height, 0)
                points[index] = CGPoint(x: x, y: y + (line.height - height) / 2)
                x += max(itemSizes[index].width, 0) + gap
            }
            y += line.height + max(lineSpacing, 0)
        }

        return points
    }
}
