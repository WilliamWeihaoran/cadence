import Foundation

/// What a rendered block shows, and what it admits it is not showing.
struct MarkdownRenderedBlockTruncation: Equatable {
    let visibleCount: Int
    let overflowCount: Int

    var isTruncated: Bool { overflowCount > 0 }

    /// The line a renderer puts under a truncated block. `nil` when nothing was cut.
    func overflowLabel(unit: String) -> String? {
        guard overflowCount > 0 else { return nil }
        return "+ \(overflowCount) more \(unit)\(overflowCount == 1 ? "" : "s")"
    }
}

/// **How much of a long block a rendered canvas draws, and why it draws a cap at all.**
///
/// A note editor that silently shows eight rows of a twenty-row table is lying about the note, so
/// the honest options were "render the whole thing" or "cut it and say so". Rendering the whole
/// thing loses: each canvas is a raster rebuilt on *every* styling pass — which is every keystroke
/// — and its cost is width × height × screen scale, so an unbounded table makes typing next to one
/// progressively slower. So: cut, and say so, with the count of what was cut.
///
/// The limits live here rather than inside the canvas because the live canvas and the read-only
/// preview render the same block from the same parse and had drifted to different answers — the
/// canvas capped rows and ellipsised cells, the preview did neither, and the same table therefore
/// looked like two different tables depending on which surface you were on. A shared constant is
/// what stops that recurring; a shared *number* is the only part of it a test can pin.
enum MarkdownRenderedBlockLimits {
    /// Raised from 8. Eight rows cut ordinary notes — a fortnight of dailies, a team roster — for
    /// no reason a reader could see.
    static let tableRowLimit = 16

    /// Raised from 12. Twelve lines cut most real functions in half.
    static let codeLineLimit = 24

    static func truncation(ofTotal total: Int, limit: Int) -> MarkdownRenderedBlockTruncation {
        let clampedTotal = max(0, total)
        let visible = min(clampedTotal, max(0, limit))
        return MarkdownRenderedBlockTruncation(visibleCount: visible, overflowCount: clampedTotal - visible)
    }

    static func tableRowTruncation(ofTotal total: Int) -> MarkdownRenderedBlockTruncation {
        truncation(ofTotal: total, limit: tableRowLimit)
    }

    static func codeLineTruncation(ofTotal total: Int) -> MarkdownRenderedBlockTruncation {
        truncation(ofTotal: total, limit: codeLineLimit)
    }
}
