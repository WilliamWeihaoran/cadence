import SwiftUI

/// [[T-10008]]: how one row of a note's heading outline reads, on both platforms.
///
/// Depth is carried by indent and by weight: a top-level heading (`#`, `##`) is semibold in the
/// text colour, anything deeper is regular in the muted one. macOS's outline popover
/// (`NoteOutlineJumpRow`) has drawn that since the side panel was retired; the iOS outline sheet
/// (`iOSMarkdownEditingSurface.outlineSheet`) drew every level in the same regular `Theme.text`, so
/// a phone outline of a long note was one undifferentiated column where the Mac's had a shape.
/// Nothing about touch forces that ([[T-8201]]); the point size stays each platform's own, the
/// anatomy is this.
enum CadenceNoteOutlineRowStyle {
    /// The deepest level still drawn as a top-level heading.
    static let prominentLevelLimit = 2

    /// One indent step per level below the first.
    static let indentStep: CGFloat = 12

    static func isProminent(level: Int) -> Bool {
        level <= prominentLevelLimit
    }

    static func weight(level: Int) -> Font.Weight {
        isProminent(level: level) ? .semibold : .regular
    }

    static func color(level: Int) -> Color {
        isProminent(level: level) ? Theme.text : Theme.muted
    }

    static func indent(level: Int) -> CGFloat {
        CGFloat(max(0, level - 1)) * indentStep
    }
}
