import Foundation
import Testing
#if os(macOS)
import AppKit
#endif

@testable import Cadence

struct MarkdownHiddenRangeSupportTests {
    @Test func findsHiddenRangeByAttribute() throws {
        let storage = NSMutableAttributedString(string: "**bold**")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 0, length: 2))
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 6, length: 2))

        let opening = try #require(MarkdownHiddenRangeSupport.hiddenRange(containing: 1, in: storage))
        let closing = try #require(MarkdownHiddenRangeSupport.hiddenRange(containing: 7, in: storage))

        #expect(opening == NSRange(location: 0, length: 2))
        #expect(closing == NSRange(location: 6, length: 2))
    }

    @Test func snapsCaretForwardOutOfHiddenSyntax() {
        let storage = NSMutableAttributedString(string: "**bold**")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 0, length: 2))

        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(1, in: storage, preferringForward: true) == 2)
    }

    @Test func doesNotSnapCaretRestingAtHiddenRangeBoundary() {
        // A caret sitting exactly at the start of a hidden run (e.g. right before a
        // closing "`"/"**" marker) is a normal resting place, not "stuck inside" it —
        // typing there must extend the adjacent visible content instead of being
        // ejected past the marker. Regression test for the caret-ejection bug where
        // this snapped forward on every keystroke once restyling became synchronous.
        let storage = NSMutableAttributedString(string: "**bold**")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 0, length: 2))

        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(0, in: storage, preferringForward: true) == 0)
    }

    @Test func snapsCaretBackwardOutOfHiddenSyntax() {
        let storage = NSMutableAttributedString(string: "**bold**")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 6, length: 2))

        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(7, in: storage, preferringForward: false) == 6)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(8, in: storage, preferringForward: false) == 8)
    }

    @Test func findsNextVisibleCaretAroundHiddenRanges() {
        let storage = NSMutableAttributedString(string: "**bold**")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 0, length: 2))
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 6, length: 2))

        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 0, movingForward: true, in: storage) == 2)
        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 8, movingForward: false, in: storage) == 5)
    }

    // MARK: - Hidden frontmatter

    /// `---\ntags: ["a"]\n---\n\nBody` with the block (and its trailing blank line) hidden.
    /// Body starts at 22.
    private func frontmatterStorage() -> NSMutableAttributedString {
        let text = "---\ntags: [\"a\"]\n---\n\nBody"
        let storage = NSMutableAttributedString(string: text)
        let block = NSRange(location: 0, length: 21)
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: block)
        storage.addAttribute(.cadenceMarkdownFrontmatter, value: true, range: block)
        return storage
    }

    @Test func findsHiddenFrontmatterBlockAndItsBodyStart() throws {
        let storage = frontmatterStorage()

        #expect(MarkdownHiddenRangeSupport.frontmatterRange(in: storage) == NSRange(location: 0, length: 21))
        #expect(MarkdownHiddenRangeSupport.bodyStartLocation(in: storage) == 21)
    }

    @Test func caretAtStartOfNoteSnapsPastHiddenFrontmatter() {
        let storage = frontmatterStorage()

        // The whole point: a caret at the very start of a note is *not* a valid resting place
        // when a hidden block sits there. Unlike an inline marker's leading edge, there is no
        // visible text before it, so typing at 0 would break the YAML.
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(0, in: storage) == 21)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(7, in: storage) == 21)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(21, in: storage) == 21)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(23, in: storage) == 23)
    }

    @Test func frontmatterSnapIsForwardEvenWhenPreferringBackward() {
        let storage = frontmatterStorage()

        // Backward is not an option — there is nowhere behind the block to go.
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(5, in: storage, preferringForward: false) == 21)
    }

    @Test func arrowingBackwardStopsAtBodyStartRatherThanEnteringFrontmatter() {
        let storage = frontmatterStorage()

        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 22, movingForward: false, in: storage) == 21)
        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 21, movingForward: false, in: storage) == 21)
        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 0, movingForward: false, in: storage) == 21)
    }

    @Test func arrowingForwardFromInsideFrontmatterLandsInTheBody() {
        let storage = frontmatterStorage()

        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 0, movingForward: true, in: storage) == 22)
        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 21, movingForward: true, in: storage) == 22)
    }

    @Test func inlineHiddenMarkersKeepTheirBoundaryRestingPlace() {
        // Regression guard for the two rules living side by side: adding the frontmatter rule must
        // not turn a plain hidden marker at location 0 into an ejecting one.
        let storage = NSMutableAttributedString(string: "**bold**")
        storage.addAttribute(.cadenceMarkdownHidden, value: true, range: NSRange(location: 0, length: 2))

        #expect(MarkdownHiddenRangeSupport.frontmatterRange(in: storage) == nil)
        #expect(MarkdownHiddenRangeSupport.bodyStartLocation(in: storage) == 0)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(0, in: storage) == 0)
    }

#if os(macOS)
    // MARK: - Frontmatter vs. dividers, through the real stylist

    @MainActor
    private func styled(_ text: String) throws -> NSTextStorage {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        textView.string = text
        MarkdownStylist.apply(to: textView)
        return try #require(textView.textStorage)
    }

    /// `---` is also this editor's horizontal-rule syntax, so "divider, prose, divider" looks
    /// exactly like a frontmatter block to a fence-matching parser. Hiding that span would swallow
    /// the prose with no reveal-on-caret and no toggle to get it back.
    @MainActor
    @Test func dividerPairAroundProseIsNotHiddenAsFrontmatter() throws {
        let text = "---\nA thought worth keeping.\n\nAnd another.\n---\n\nAfter"
        let storage = try styled(text)

        #expect(MarkdownHiddenRangeSupport.frontmatterRange(in: storage) == nil)
        #expect(MarkdownHiddenRangeSupport.bodyStartLocation(in: storage) == 0)
        // The prose between the two rules stays visible.
        #expect(storage.attribute(.cadenceMarkdownHidden, at: 4, effectiveRange: nil) == nil)
    }

    /// The block Cadence itself writes still disappears.
    @MainActor
    @Test func realFrontmatterBlockIsStillHidden() throws {
        let text = "---\ntags: [\"a\"]\n---\n\nBody"
        let storage = try styled(text)

        // 20 characters of block plus the blank line the stylist swallows after it.
        #expect(MarkdownHiddenRangeSupport.frontmatterRange(in: storage) == NSRange(location: 0, length: 21))
        #expect(MarkdownHiddenRangeSupport.bodyStartLocation(in: storage) == 21)
        #expect(storage.attribute(.cadenceMarkdownHidden, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.cadenceMarkdownHidden, at: 21, effectiveRange: nil) == nil)
    }

    /// A property block and a divider further down: the block goes, the body stays.
    @MainActor
    @Test func frontmatterHidesOnlyItsOwnBlockWhenTheBodyAlsoHasADivider() throws {
        let text = "---\ntags: [\"a\"]\n---\n\nIntro\n\n---\n\nOutro"
        let storage = try styled(text)

        #expect(MarkdownHiddenRangeSupport.frontmatterRange(in: storage) == NSRange(location: 0, length: 21))
        let intro = (text as NSString).range(of: "Intro").location
        let outro = (text as NSString).range(of: "Outro").location
        #expect(storage.attribute(.cadenceMarkdownHidden, at: intro, effectiveRange: nil) == nil)
        #expect(storage.attribute(.cadenceMarkdownHidden, at: outro, effectiveRange: nil) == nil)
    }

    /// Boundaries of the "at least one property" rule. Neither block carries anything Cadence
    /// reads back, so neither is worth hiding — and both are reachable by typing two rules.
    @MainActor
    @Test func propertylessBlocksAreDividersNotFrontmatter() throws {
        for text in ["---\n---\n\nBody", "---\nDraft\n---\n\nBody"] {
            let storage = try styled(text)
            #expect(MarkdownHiddenRangeSupport.frontmatterRange(in: storage) == nil)
            #expect(MarkdownHiddenRangeSupport.bodyStartLocation(in: storage) == 0)
        }
    }
#endif

    @Test func plainTextLocationsAreUnchanged() {
        let storage = NSMutableAttributedString(string: "plain text")

        #expect(MarkdownHiddenRangeSupport.hiddenRange(containing: 3, in: storage) == nil)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(3, in: storage) == 3)
        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 3, movingForward: true, in: storage) == 4)
    }
}
