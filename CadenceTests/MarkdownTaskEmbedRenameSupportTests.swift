import Foundation
import Testing

@testable import Cadence

/// Covers renaming a task embed *after* it exists.
///
/// A card's title is stored twice — on the `AppTask` and inside the note's own
/// `[[task:UUID|Title]]` reference — so a rename that updates one and not the other leaves the card
/// drawn over source that disagrees with it. macOS renames from an inline field over the card; iOS
/// had no rename at all. Both now go through the functions tested here, which is the point: the
/// rule about what a title may look like inside a reference is written once.
///
/// macOS UI cannot be screenshot-verified from the agent shell (T-14), so these tests are what pins
/// the Mac's half of the change.
struct MarkdownTaskEmbedRenameSupportTests {
    private static let taskID = UUID(uuidString: "E61773C7-6340-46EB-AED8-3F9DB88CE535")!
    private static let otherID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private static let fallback = "Untitled Task"

    // MARK: - Sanitizing

    @Test func keepsAnOrdinaryTitleAsTyped() {
        #expect(
            MarkdownTaskEmbedParser.sanitizedReferenceTitle("Buy milk", fallback: Self.fallback) == "Buy milk"
        )
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(
            MarkdownTaskEmbedParser.sanitizedReferenceTitle("   Buy milk \t", fallback: Self.fallback) == "Buy milk"
        )
    }

    /// `]`, `|` and a newline each terminate the reference early, which would turn the embed into
    /// text the parser no longer recognises — the card disappears and raw brackets are left behind.
    @Test func substitutesCharactersThatWouldBreakTheReference() {
        let sanitized = MarkdownTaskEmbedParser.sanitizedReferenceTitle(
            "Read [ch. 3]\nthen | rest",
            fallback: Self.fallback
        )
        #expect(sanitized == "Read (ch. 3) then - rest")
        #expect(MarkdownTaskEmbedParser.standaloneTaskReference(in: "[[task:\(Self.taskID.uuidString)|\(sanitized)]]") != nil)
    }

    @Test func fallsBackWhenTheTitleIsEmpty() {
        #expect(MarkdownTaskEmbedParser.sanitizedReferenceTitle("   ", fallback: Self.fallback) == Self.fallback)
    }

    // MARK: - Finding the title runs

    @Test func findsTheTitleRunOfAReference() {
        let markdown = "Notes\n[[task:\(Self.taskID.uuidString)|Buy milk]]\n"
        let ranges = MarkdownTaskEmbedParser.referenceTitleRanges(of: Self.taskID, in: markdown)
        #expect(ranges.count == 1)
        #expect((markdown as NSString).substring(with: ranges[0]) == "Buy milk")
    }

    @Test func findsEveryReferenceToTheSameTask() {
        let markdown = """
        [[task:\(Self.taskID.uuidString)|Buy milk]]
        Something else
        [[task:\(Self.taskID.uuidString)|Buy milk]]
        """
        #expect(MarkdownTaskEmbedParser.referenceTitleRanges(of: Self.taskID, in: markdown).count == 2)
    }

    @Test func ignoresReferencesToOtherTasks() {
        let markdown = "[[task:\(Self.otherID.uuidString)|Call Sam]]"
        #expect(MarkdownTaskEmbedParser.referenceTitleRanges(of: Self.taskID, in: markdown).isEmpty)
    }

    // MARK: - Rewriting

    @Test func rewritesTheTitleInPlace() {
        let markdown = "Before\n[[task:\(Self.taskID.uuidString)|Buy milk]]\nAfter"
        let rewritten = MarkdownTaskEmbedParser.replacingReferenceTitles(
            of: Self.taskID,
            in: markdown,
            with: "Buy oat milk",
            fallback: Self.fallback
        )
        #expect(rewritten == "Before\n[[task:\(Self.taskID.uuidString)|Buy oat milk]]\nAfter")
    }

    /// Back-to-front application is what keeps the second reference from being written over the
    /// wrong offsets once the first one has changed length.
    @Test func rewritesEveryReferenceEvenWhenLengthsChange() {
        let markdown = """
        [[task:\(Self.taskID.uuidString)|Buy milk]]
        middle
        [[task:\(Self.taskID.uuidString)|Buy milk]]
        """
        let rewritten = MarkdownTaskEmbedParser.replacingReferenceTitles(
            of: Self.taskID,
            in: markdown,
            with: "A considerably longer title",
            fallback: Self.fallback
        )
        let expected = """
        [[task:\(Self.taskID.uuidString)|A considerably longer title]]
        middle
        [[task:\(Self.taskID.uuidString)|A considerably longer title]]
        """
        #expect(rewritten == expected)
    }

    @Test func rewrittenReferenceStillParsesAsAnEmbed() {
        let markdown = "[[task:\(Self.taskID.uuidString)|Buy milk]]"
        let rewritten = MarkdownTaskEmbedParser.replacingReferenceTitles(
            of: Self.taskID,
            in: markdown,
            with: "Read [ch. 3]",
            fallback: Self.fallback
        )
        let reference = MarkdownTaskEmbedParser.standaloneTaskReference(in: rewritten ?? "")
        #expect(reference?.id == Self.taskID)
        #expect(reference?.title == "Read (ch. 3)")
    }

    @Test func reportsNoChangeWhenTheTitleIsAlreadyRight() {
        let markdown = "[[task:\(Self.taskID.uuidString)|Buy milk]]"
        #expect(
            MarkdownTaskEmbedParser.replacingReferenceTitles(
                of: Self.taskID,
                in: markdown,
                with: "Buy milk",
                fallback: Self.fallback
            ) == nil
        )
    }

    @Test func anEmptyRenameFallsBackRatherThanEmptyingTheReference() {
        let markdown = "[[task:\(Self.taskID.uuidString)|Buy milk]]"
        let rewritten = MarkdownTaskEmbedParser.replacingReferenceTitles(
            of: Self.taskID,
            in: markdown,
            with: "   ",
            fallback: Self.fallback
        )
        #expect(rewritten == "[[task:\(Self.taskID.uuidString)|\(Self.fallback)]]")
    }
}
