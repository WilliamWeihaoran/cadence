import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import Cadence

/// The styling decisions that used to live under `#if os(iOS)`.
///
/// Every function exercised here was inside `iOSMarkdownStyler` until T-121, in `Cadence/iOS/` —
/// which this test target cannot see, on either platform. That is the whole reason the iOS editor's
/// user-visible failures (a marker that will not hide, a block that renders when the caret is
/// inside it, an inline pass that styles a table's pipes) shipped with no coverage at all: the
/// arithmetic was correct-looking and unobserved.
///
/// These are ordinary unit tests rather than source scans, because the logic is now pure.
struct MarkdownStyleRangeSupportTests {

    // MARK: - Heading marker visibility

    /// The `#` is hidden when there is something after it to read.
    @Test
    func aHeadingWithContentHasVisibleContent() throws {
        let line = "## Nested work"
        let heading = try #require(MarkdownBlockSupport.headingLineInfo(in: line))
        #expect(MarkdownStyleRanges.hasVisibleHeadingContent(in: line, markerRange: heading.markerRange))
    }

    /// **A heading whose content is only whitespace keeps its marker.**
    ///
    /// This is the case the predicate exists for. `headingLineInfo` already requires *a* character
    /// after the hashes, so the marker range can swallow the whole line and hiding it would leave a
    /// row that looks empty and cannot be clicked back into — which is why the styler dims the
    /// marker instead.
    @Test
    func aHeadingWithOnlyWhitespaceAfterTheMarkerHasNoVisibleContent() throws {
        let line = "#    "
        let heading = try #require(MarkdownBlockSupport.headingLineInfo(in: line))
        #expect(MarkdownStyleRanges.hasVisibleHeadingContent(in: line, markerRange: heading.markerRange) == false)
    }

    /// A marker range running past the end of the line must not trap, and must not claim content.
    @Test
    func aMarkerRangePastTheEndOfTheLineHasNoVisibleContent() {
        #expect(
            MarkdownStyleRanges.hasVisibleHeadingContent(
                in: "# Hi",
                markerRange: NSRange(location: 0, length: 999)
            ) == false
        )
    }

    // MARK: - Combined block ranges

    /// The span of a multi-line block includes the newlines between its lines.
    ///
    /// Measured end-to-end rather than by summing line lengths, so the run addresses the block as
    /// one paragraph — a sum would leave every terminator carrying the base style and a collapsed
    /// code block would keep one full-height row per line.
    @Test
    func aCombinedLineRangeSpansTheTerminatorsBetweenItsLines() {
        let markdown = "```\nlet x = 1\n```"
        let records = MarkdownSourceLines.lines(in: markdown)
        let byIndex = Dictionary(uniqueKeysWithValues: records.map { ($0.index, $0) })

        let range = MarkdownStyleRanges.combinedLineRange(for: 0...2, recordsByIndex: byIndex)
        #expect(range == NSRange(location: 0, length: (markdown as NSString).length))
    }

    @Test
    func aCombinedLineRangeIsNilWhenNoLineIsKnown() {
        #expect(MarkdownStyleRanges.combinedLineRange(for: 7...9, recordsByIndex: [:]) == nil)
    }

    // MARK: - Reveal

    @Test
    func nothingIsRevealedWhenTheCaretIsOutsideEveryBlock() {
        #expect(MarkdownStyleRanges.isRevealed(NSRange(location: 0, length: 10), by: nil) == false)
        #expect(
            MarkdownStyleRanges.isRevealed(
                NSRange(location: 0, length: 10),
                by: NSRange(location: 20, length: 4)
            ) == false
        )
    }

    /// A caret *abutting* a block is not inside it — the intersection has to have length.
    @Test
    func aBlockTouchedOnlyAtItsEdgeIsNotRevealed() {
        #expect(
            MarkdownStyleRanges.isRevealed(
                NSRange(location: 0, length: 10),
                by: NSRange(location: 10, length: 0)
            ) == false
        )
    }

    @Test
    func aBlockOverlappingTheCaretIsRevealed() {
        #expect(
            MarkdownStyleRanges.isRevealed(
                NSRange(location: 0, length: 10),
                by: NSRange(location: 4, length: 1)
            )
        )
    }

    // MARK: - Inline exclusions

    private func exclusions(in markdown: String) -> [NSRange] {
        MarkdownStyleRanges.inlineStyleExclusionRanges(
            lineRecords: MarkdownSourceLines.lines(in: markdown),
            tableRows: MarkdownTableParser.rowStyles(in: markdown),
            codeBlocks: MarkdownBlockSupport.fencedCodeBlocks(in: markdown)
        )
    }

    private func covers(_ ranges: [NSRange], _ substring: String, in markdown: String) -> Bool {
        let target = (markdown as NSString).range(of: substring)
        guard target.location != NSNotFound else { return false }
        return ranges.contains { NSIntersectionRange($0, target).length == target.length }
    }

    /// A `*` inside a fence must not turn the code italic.
    @Test
    func aFencedCodeBlockIsExcludedFromInlineStyling() {
        let markdown = "before\n```swift\nlet a = b * c\n```\nafter"
        let ranges = exclusions(in: markdown)
        #expect(covers(ranges, "let a = b * c", in: markdown))
        #expect(covers(ranges, "before", in: markdown) == false)
        #expect(covers(ranges, "after", in: markdown) == false)
    }

    /// Every row of a table is excluded, so the inline pass cannot marker-hide its pipes.
    @Test
    func everyTableRowIsExcludedFromInlineStyling() {
        let markdown = "| Col A | Col B |\n| --- | --- |\n| 1 | 2 |"
        let ranges = exclusions(in: markdown)
        #expect(covers(ranges, "| Col A | Col B |", in: markdown))
        #expect(covers(ranges, "| --- | --- |", in: markdown))
        #expect(covers(ranges, "| 1 | 2 |", in: markdown))
    }

    /// A divider's whole line is already replaced by a drawn rule; styling it again conflicts.
    @Test
    func aDividerLineIsExcludedFromInlineStyling() {
        let markdown = "text\n***\nmore"
        #expect(covers(exclusions(in: markdown), "***", in: markdown))
    }

    @Test
    func aStandaloneTaskEmbedLineIsExcludedFromInlineStyling() {
        let embed = "[[task:11111111-2222-3333-4444-555555555555|Ship it]]"
        let markdown = "intro\n\(embed)\noutro"
        #expect(covers(exclusions(in: markdown), embed, in: markdown))
    }

    @Test
    func aStandaloneImageLineIsExcludedFromInlineStyling() {
        let image = "![Diagram](cadence-image://11111111-2222-3333-4444-555555555555)"
        let markdown = "intro\n\(image)"
        #expect(covers(exclusions(in: markdown), image, in: markdown))
    }

    /// Ordinary prose is never excluded, and neither is a blank line's zero-length range.
    @Test
    func plainProseIsNotExcludedAndNoZeroLengthRangeIsReported() {
        let markdown = "just some **bold** prose\n\nand more"
        let ranges = exclusions(in: markdown)
        #expect(ranges.isEmpty)
    }

    /// **The `.whitespaces` → `classificationText` switch in `inlineStyleExclusionRanges` is inert.**
    ///
    /// The two spellings can only disagree about a line made of whitespace plus a newline-class
    /// character, which is what a CRLF note's blank line looks like once the source is split on
    /// `"\n"` alone. Under the old spelling such a line was not skipped and was then rejected by all
    /// three predicates; under the new one it is skipped up front. Same output — this pins that
    /// rather than trusting the comment saying so.
    @Test
    func aCRLFBlankLineIsNotExcludedUnderEitherEmptinessSpelling() {
        let markdown = "text\r\n \r\nmore\r\n\u{2028}\r\ntail"
        #expect(exclusions(in: markdown).isEmpty)
    }

    /// And the divider it *does* have to keep finding still carries its `\r`.
    ///
    /// `isDividerLine` trims `.whitespacesAndNewlines` itself, so it reaches the same answer whether
    /// it is handed the raw line or either trimming of it. That internal trim is the load-bearing
    /// half; a "simplification" that removed it would drop every divider in a CRLF note.
    @Test
    func aCRLFDividerLineIsStillExcluded() {
        let markdown = "text\r\n***\r\nmore"
        #expect(covers(exclusions(in: markdown), "***", in: markdown))
    }
}

/// Which characters of an inline marker disappear.
struct MarkdownInlineMarkerRangeTests {

    // MARK: - Hashtags

    @Test
    func aHashtagIsMatchedAtItsOwnOffset() {
        let markdown = "a #tag here"
        #expect(MarkdownInlineMarkerRanges.hashtagRanges(in: markdown) == [NSRange(location: 2, length: 4)])
    }

    /// `C#` is not a tag: the lookbehind rejects a `#` glued to a word.
    @Test
    func aHashGluedToAWordIsNotAHashtag() {
        #expect(MarkdownInlineMarkerRanges.hashtagRanges(in: "written in C# mostly").isEmpty)
        #expect(MarkdownInlineMarkerRanges.hashtagRanges(in: "id_#4").isEmpty)
    }

    /// The body must start with an alphanumeric, so `#-` and `#_` are not tags.
    @Test
    func aHashFollowedByPunctuationIsNotAHashtag() {
        #expect(MarkdownInlineMarkerRanges.hashtagRanges(in: "#- #_ #").isEmpty)
    }

    @Test
    func aHashtagMayHoldDigitsUnderscoresAndDashes() {
        let markdown = "#q3_plan-2026"
        #expect(MarkdownInlineMarkerRanges.hashtagRanges(in: markdown) == [NSRange(location: 0, length: 13)])
    }

    // MARK: - Image references

    @Test
    func anImageReferenceReportsItsLabelAndIDSeparately() throws {
        let markdown = "![Diagram](cadence-image://11111111-2222-3333-4444-555555555555)"
        let reference = try #require(MarkdownInlineMarkerRanges.imageReferences(in: markdown).first)

        #expect(reference.fullRange == NSRange(location: 0, length: (markdown as NSString).length))
        #expect((markdown as NSString).substring(with: reference.labelRange) == "Diagram")
        #expect((markdown as NSString).substring(with: reference.idRange) == "11111111-2222-3333-4444-555555555555")
        #expect(reference.hasLabel)
    }

    /// An empty alt text is a *present* label of zero length, which is a different case from a
    /// missing one — the styler shows the raw id instead of hiding it.
    @Test
    func anImageReferenceWithNoAltTextHasNoLabel() throws {
        let markdown = "![](cadence-image://11111111-2222-3333-4444-555555555555)"
        let reference = try #require(MarkdownInlineMarkerRanges.imageReferences(in: markdown).first)
        #expect(reference.hasLabel == false)
    }

    /// The three hidden runs are exactly `![`, `](cadence-image://` and the id plus `)` — nothing
    /// of the alt text, and nothing past the reference.
    @Test
    func theHiddenRunsOfAnImageReferenceAreItsSyntaxOnly() throws {
        let markdown = "![Diagram](cadence-image://11111111-2222-3333-4444-555555555555)"
        let nsMarkdown = markdown as NSString
        let reference = try #require(MarkdownInlineMarkerRanges.imageReferences(in: markdown).first)

        let hidden = MarkdownInlineMarkerRanges.hiddenRanges(for: reference).map { nsMarkdown.substring(with: $0) }
        #expect(hidden == ["![", "](cadence-image://", "11111111-2222-3333-4444-555555555555)"])
    }

    // MARK: - Links

    /// `[label](url)` hides `[`, `](` and `)`, and the middle run is *measured* rather than assumed
    /// to be two characters.
    @Test
    func theHiddenRunsOfALinkAreItsBrackets() throws {
        let markdown = "see [the docs](https://example.com) now"
        let nsMarkdown = markdown as NSString
        let link = try #require(MarkdownLinkSupport.linkRanges(in: markdown).first)

        let hidden = MarkdownInlineMarkerRanges
            .hiddenRanges(forLink: link.fullRange, label: link.labelRange, url: link.urlRange)
            .map { nsMarkdown.substring(with: $0) }
        #expect(hidden == ["[", "](", ")"])
    }

    // MARK: - Wiki references

    @Test
    func theHiddenRunsOfANoteReferenceAreItsDoubleBrackets() {
        let full = NSRange(location: 4, length: 12)
        let hidden = MarkdownInlineMarkerRanges.hiddenRanges(forReference: full, hiddenPrefixUTF16Length: 0)
        #expect(hidden == [NSRange(location: 4, length: 2), NSRange(location: 14, length: 2)])
    }

    /// A task reference also hides the `task:` the display form drops, and hides it *inside* the
    /// brackets rather than at the reference's start.
    @Test
    func aTaskReferenceAlsoHidesTheDroppedPrefix() {
        let full = NSRange(location: 0, length: 20)
        let hidden = MarkdownInlineMarkerRanges.hiddenRanges(forReference: full, hiddenPrefixUTF16Length: 5)
        #expect(hidden.count == 3)
        #expect(hidden[2] == NSRange(location: 2, length: 5))
    }

    // MARK: - Range shifting

    @Test
    func shiftingARangeMovesItsLocationAndKeepsItsLength() {
        #expect(NSRange(location: 3, length: 4).shifted(by: 10) == NSRange(location: 13, length: 4))
        #expect(NSRange(location: 3, length: 4).shifted(by: 0) == NSRange(location: 3, length: 4))
    }
}

#if os(macOS)
/// **macOS's styler goes through `MarkdownStyleRanges.hasVisibleHeadingContent`.**
///
/// `MarkdownEditorSupport.heading` had its own copy of the test, trimming `.whitespaces` where the
/// shared function trims `.whitespacesAndNewlines`. That is not a cosmetic difference: the styler
/// splits the document on `"\n"` alone (`MarkdownSourceLines` explains why), so a CRLF note leaves
/// the `\r` as the last character of every line, and `"# \r"` therefore looked like a heading *with*
/// content — marker hidden, line set in 30pt bold, nothing left on screen to click the caret back
/// into. `NSTextView` does not normalise line endings on paste, so that content arrives intact.
///
/// The heading pass is `private`, so these observe it through `MarkdownStylist.apply(to:)` on the
/// attributed string, the same way `MarkdownFrontmatterDividerTests` does. Reverting the call site
/// to the inline `.whitespaces` copy fails the first test here.
struct MacMarkdownHeadingVisibleContentTests {
    @MainActor
    private func styled(_ text: String) throws -> NSTextStorage {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        textView.string = text
        MarkdownStylist.apply(to: textView)
        return try #require(textView.textStorage)
    }

    @MainActor
    private func isHidden(_ storage: NSTextStorage, at location: Int) -> Bool {
        (storage.attribute(.cadenceMarkdownHidden, at: location, effectiveRange: nil) as? Bool) == true
    }

    @MainActor
    private func font(_ storage: NSTextStorage, at location: Int) throws -> NSFont {
        try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    /// The mutation target: a CRLF heading holding only its terminator keeps a visible, dimmed `#`.
    @MainActor
    @Test func aCRLFHeadingWithNothingAfterTheMarkerKeepsItsMarkerVisible() throws {
        let storage = try styled("# \r\nBody")

        #expect(isHidden(storage, at: 0) == false)
        #expect(try font(storage, at: 0) == MarkdownStylist.baseFont)
        #expect(
            storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == MarkdownStylist.dimColor
        )
    }

    /// Non-vacuity: a heading with real content still hides its marker and goes bold.
    @MainActor
    @Test func aHeadingWithContentStillHidesItsMarker() throws {
        let storage = try styled("# Title\nBody")

        #expect(isHidden(storage, at: 0))
        let titleFont = try font(storage, at: 2)
        #expect(titleFont.pointSize == 30)
        #expect(titleFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    /// The LF case both spellings already agreed on, so the CRLF expectation above is not just
    /// "empty headings dim their marker" restated.
    @MainActor
    @Test func anLFHeadingWithNothingAfterTheMarkerAlsoKeepsItsMarkerVisible() throws {
        let storage = try styled("# \nBody")

        #expect(isHidden(storage, at: 0) == false)
        #expect(try font(storage, at: 0) == MarkdownStylist.baseFont)
    }
}
#endif
