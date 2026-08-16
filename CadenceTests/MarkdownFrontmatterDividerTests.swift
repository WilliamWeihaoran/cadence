import Foundation
import Testing
#if os(macOS)
import AppKit
#endif

@testable import Cadence

#if os(macOS)
/// A note's YAML frontmatter is fenced by `---`, which is also this editor's horizontal-rule
/// syntax, so the divider pass decorates both fences before the frontmatter pass hides the block.
/// The frontmatter pass has to take that decoration back off: the layout manager draws divider
/// rules from the attribute alone, and the hidden block's line boxes are collapsed to 0.1pt, so a
/// surviving decoration paints a 160pt rule across the note's first visible line.
///
/// The iOS styler hit exactly this and fixed it the same way (`a43b8fd`). There is no way to
/// screenshot the macOS editor from an agent shell ([T-14] in `docs/TODO.md`), so the behaviour is
/// pinned on the attributed string instead.
struct MarkdownFrontmatterDividerTests {
    @MainActor
    private func styled(_ text: String) throws -> NSTextStorage {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        textView.string = text
        MarkdownStylist.apply(to: textView)
        return try #require(textView.textStorage)
    }

    @MainActor
    @Test func frontmatterFencesCarryNoDividerDecoration() throws {
        let text = "---\ntitle: Tagged note\ntags: [work]\n---\n\n# Heading\n\nBody."
        let storage = try styled(text)

        let frontmatter = try #require(MarkdownHiddenRangeSupport.frontmatterRange(in: storage))
        var decorated: [NSRange] = []
        storage.enumerateAttribute(.cadenceMarkdownDivider, in: frontmatter) { value, range, _ in
            if (value as? Bool) == true { decorated.append(range) }
        }
        #expect(decorated.isEmpty)
    }

    @MainActor
    @Test func aRealDividerStillCarriesItsDecoration() throws {
        // The removal must be scoped to the frontmatter block: a `---` in the body is a rule.
        let text = "---\ntitle: Tagged note\n---\n\nAbove\n\n---\n\nBelow"
        let storage = try styled(text)

        var decorated: [NSRange] = []
        storage.enumerateAttribute(
            .cadenceMarkdownDivider,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            if (value as? Bool) == true { decorated.append(range) }
        }

        #expect(decorated.count == 1)
        let frontmatter = try #require(MarkdownHiddenRangeSupport.frontmatterRange(in: storage))
        #expect(decorated.allSatisfy { $0.location >= NSMaxRange(frontmatter) })
    }
}
#endif
