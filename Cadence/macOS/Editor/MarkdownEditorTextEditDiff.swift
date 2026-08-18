#if os(macOS)
import AppKit

/// Turning a rewritten *document* back into a single `NSTextStorage` edit.
///
/// `MarkdownTaskEmbedParser.reconcilingReferenceTitles` answers in whole strings, because that is
/// the only spelling both platforms share — iOS pushes the result straight through its SwiftUI
/// draft binding. A `CadenceTextView` cannot: assigning `string` wholesale drops the caret to the
/// top, throws away the scroll position and registers no undo, and a note being edited is exactly
/// where a reference can go stale. So the reconciled text is applied as the one run of characters
/// that actually differs, which for a title rewrite is the title itself.
enum MarkdownTextEditDiff {
    struct Edit {
        /// The run to replace, in the current text.
        let range: NSRange
        /// The run to replace it with, in the reconciled text.
        let replacementRange: NSRange
    }

    /// The shortest single replacement that turns `current` into `updated`.
    ///
    /// Common prefix and suffix are peeled off by UTF-16 unit. A boundary can in principle land
    /// inside a surrogate pair; the composed result is still exactly `updated`, because prefix +
    /// replacement + suffix is `updated` by construction.
    static func minimalEdit(from current: NSString, to updated: NSString) -> Edit {
        var prefix = 0
        while prefix < current.length,
              prefix < updated.length,
              current.character(at: prefix) == updated.character(at: prefix) {
            prefix += 1
        }

        var suffix = 0
        while suffix < current.length - prefix,
              suffix < updated.length - prefix,
              current.character(at: current.length - 1 - suffix) == updated.character(at: updated.length - 1 - suffix) {
            suffix += 1
        }

        return Edit(
            range: NSRange(location: prefix, length: current.length - prefix - suffix),
            replacementRange: NSRange(location: prefix, length: updated.length - prefix - suffix)
        )
    }

    /// Where a selection sits once `edit` has been applied.
    ///
    /// Ahead of the edit it does not move; behind it, it shifts by the length the edit added or
    /// removed. A selection *inside* the edited run has had the ground taken out from under it, so
    /// it collapses to the run's start — a reference title is hidden text under a drawn card, so in
    /// practice nothing ever selects one.
    static func selection(_ selection: NSRange, after edit: Edit, in length: Int) -> NSRange {
        let delta = edit.replacementRange.length - edit.range.length
        let location: Int
        if selection.location >= NSMaxRange(edit.range) {
            location = selection.location + delta
        } else if selection.location > edit.range.location {
            location = edit.range.location
        } else {
            location = selection.location
        }
        let clamped = min(max(location, 0), length)
        return NSRange(location: clamped, length: min(selection.length, length - clamped))
    }
}
#endif
