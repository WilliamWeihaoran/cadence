import Foundation
import Testing

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

    @Test func plainTextLocationsAreUnchanged() {
        let storage = NSMutableAttributedString(string: "plain text")

        #expect(MarkdownHiddenRangeSupport.hiddenRange(containing: 3, in: storage) == nil)
        #expect(MarkdownHiddenRangeSupport.snappedCaretLocation(3, in: storage) == 3)
        #expect(MarkdownHiddenRangeSupport.nextVisibleCaretLocation(from: 3, movingForward: true, in: storage) == 4)
    }
}
