import Foundation
import Testing

@testable import Cadence

/// Covers bringing a note's `[[task:UUID|Title]]` text back in line with the tasks it points at.
///
/// The inline title field over an iOS embed card is gone: a finger cannot tell a rename target from
/// an open target, and macOS only gets away with the split because a hover highlight warns you
/// first. Tapping anywhere on the card now opens the task sheet, which means renaming an embed goes
/// through the same field as every other task edit — and *that* is the path that used to write only
/// half the story. The card relabels itself immediately, because it is drawn from the live task;
/// the note's own source keeps the old title until this runs.
///
/// Stale reference text is invisible right up until it is the only name left: an exported note, a
/// content search, or a deleted task, whose card is rendered from the reference itself.
///
/// The iOS half of this is verified on a simulator. macOS UI cannot be screenshot-verified from the
/// agent shell (T-14), so this is also what pins the shared rules the Mac's inline rename calls.
struct MarkdownTaskEmbedReferenceReconcileTests {
    private static let taskID = UUID(uuidString: "E61773C7-6340-46EB-AED8-3F9DB88CE535")!
    private static let otherID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private static let missingID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!
    private static let fallback = "Untitled Task"

    private static func reference(_ id: UUID, _ title: String) -> String {
        "[[task:\(id.uuidString)|\(title)]]"
    }

    private static func reconciled(_ markdown: String, _ titles: [UUID: String]) -> String? {
        MarkdownTaskEmbedParser.reconcilingReferenceTitles(
            in: markdown,
            titles: titles,
            fallback: fallback
        )
    }

    /// The whole point: rename in the task sheet, and the note agrees again.
    @Test func rewritesAReferenceWhoseTaskWasRenamedElsewhere() {
        let markdown = """
        # Groceries

        \(Self.reference(Self.taskID, "Buy milk"))
        """

        let result = Self.reconciled(markdown, [Self.taskID: "Buy oat milk"])

        #expect(result == """
        # Groceries

        \(Self.reference(Self.taskID, "Buy oat milk"))
        """)
    }

    /// Nil rather than an unchanged copy, so dismissing the sheet without renaming anything does
    /// not push a write through the note's draft and bump its `updatedAt`.
    @Test func returnsNilWhenEveryReferenceAlreadyAgrees() {
        let markdown = Self.reference(Self.taskID, "Buy milk")
        #expect(Self.reconciled(markdown, [Self.taskID: "Buy milk"]) == nil)
    }

    @Test func returnsNilWhenTheNoteHasNoTaskReferences() {
        #expect(Self.reconciled("Just prose, and a [[Note Link]].", [Self.taskID: "Buy milk"]) == nil)
    }

    /// A note can embed the same task twice; both drawn cards read the live title, so both runs of
    /// source have to move or the two halves of one note disagree with each other.
    @Test func rewritesEveryOccurrenceOfTheSameTask() {
        let markdown = """
        \(Self.reference(Self.taskID, "Buy milk"))

        and again later

        \(Self.reference(Self.taskID, "Buy milk"))
        """

        let result = Self.reconciled(markdown, [Self.taskID: "Buy oat milk"])

        #expect(result?.components(separatedBy: "Buy oat milk").count == 3)
        #expect(result?.contains("Buy milk") == false)
    }

    @Test func rewritesSeveralTasksInOneNote() {
        let markdown = """
        \(Self.reference(Self.taskID, "Buy milk"))
        \(Self.reference(Self.otherID, "Call plumber"))
        """

        let result = Self.reconciled(markdown, [
            Self.taskID: "Buy oat milk",
            Self.otherID: "Call the plumber"
        ])

        #expect(result == """
        \(Self.reference(Self.taskID, "Buy oat milk"))
        \(Self.reference(Self.otherID, "Call the plumber"))
        """)
    }

    /// One task renamed, one untouched: the untouched reference must come through byte for byte,
    /// or every dismissal of the sheet rewrites the whole note.
    @Test func leavesReferencesToUnchangedTasksExactlyAsTheyWere() {
        let markdown = """
        \(Self.reference(Self.taskID, "Buy milk"))
        \(Self.reference(Self.otherID, "Call plumber"))
        """

        let result = Self.reconciled(markdown, [
            Self.taskID: "Buy oat milk",
            Self.otherID: "Call plumber"
        ])

        #expect(result?.contains(Self.reference(Self.otherID, "Call plumber")) == true)
    }

    /// A reference to a task the caller cannot see — deleted, or out of scope — keeps its title.
    /// That stale string is the only name the card has left to render itself as "Missing Task" with.
    @Test func leavesAReferenceAloneWhenItsTaskIsNotAvailable() {
        let markdown = """
        \(Self.reference(Self.missingID, "Deleted thing"))
        \(Self.reference(Self.taskID, "Buy milk"))
        """

        let result = Self.reconciled(markdown, [Self.taskID: "Buy oat milk"])

        #expect(result?.contains(Self.reference(Self.missingID, "Deleted thing")) == true)
    }

    /// Renaming a task to something containing `]` or `|` must not be allowed to end the reference
    /// early — the card would vanish and leave raw brackets in the note.
    @Test func sanitizesATitleThatWouldBreakTheReference() {
        let markdown = Self.reference(Self.taskID, "Read chapter")

        let result = Self.reconciled(markdown, [Self.taskID: "Read [ch. 3] | notes"])

        #expect(result == Self.reference(Self.taskID, "Read (ch. 3) - notes"))
        #expect(MarkdownTaskEmbedParser.standaloneTaskReference(in: result ?? "") != nil)
    }

    /// A task whose title is cleared in the sheet still has to leave a parseable reference behind.
    @Test func fallsBackWhenTheRenamedTitleIsEmpty() {
        let markdown = Self.reference(Self.taskID, "Buy milk")

        let result = Self.reconciled(markdown, [Self.taskID: "   "])

        #expect(result == Self.reference(Self.taskID, Self.fallback))
    }

    /// Reconciling must not disturb the surrounding note — the reference is a run inside a
    /// document the user is also writing.
    @Test func leavesTheRestOfTheNoteUntouched() {
        let markdown = """
        # Monday

        - a list item with [[task: in prose
        \(Self.reference(Self.taskID, "Buy milk"))

        > a quote mentioning Buy milk in plain text
        """

        let result = Self.reconciled(markdown, [Self.taskID: "Buy oat milk"])

        #expect(result?.contains("- a list item with [[task: in prose") == true)
        #expect(result?.contains("> a quote mentioning Buy milk in plain text") == true)
    }

    // MARK: - T-3249 item (1): the selection moves with the rewrite

    private static func reconciled(
        _ markdown: String,
        caret: Int,
        _ titles: [UUID: String]
    ) -> (text: String, selection: NSRange)? {
        MarkdownTaskEmbedParser.reconcilingReferenceTitles(
            in: markdown,
            selection: NSRange(location: caret, length: 0),
            titles: titles,
            fallback: fallback
        )
    }

    /// The defect: a caret just past `]]`, a rename that lengthens the title, and the old offset
    /// lands inside the rewritten run, where the completion context reads a `[[task:` being typed.
    /// The moved caret sits just past the new `]]`, so no strip opens.
    @Test func aCaretPastARenamedReferenceStaysPastItAndOpensNoCompletion() throws {
        let markdown = "See \(Self.reference(Self.taskID, "Milk")) then"
        let caret = ("See \(Self.reference(Self.taskID, "Milk"))" as NSString).length

        let result = try #require(Self.reconciled(markdown, caret: caret, [Self.taskID: "Buy oat milk today"]))

        let expected = ("See \(Self.reference(Self.taskID, "Buy oat milk today"))" as NSString).length
        #expect(result.selection == NSRange(location: expected, length: 0))
        #expect(MarkdownReferenceCompletionSupport.context(in: result.text, selection: result.selection) == nil)
        // The stale offset is what opened the strip: it reads as a task query inside the new run.
        #expect(MarkdownReferenceCompletionSupport.context(
            in: result.text,
            selection: NSRange(location: caret, length: 0)
        )?.kind == .task)
    }

    /// Every renamed run before the caret counts, not only the nearest; a caret ahead of every run
    /// does not move; a range keeps both ends on their characters.
    @Test func eachSelectionEndMovesByTheRunsBeforeIt() throws {
        let first = Self.reference(Self.taskID, "A")
        let second = Self.reference(Self.otherID, "B")
        let markdown = "x \(first) y \(second) z"
        let titles = [Self.taskID: "AAAA", Self.otherID: "BBBBBB"]
        let zOffset = (markdown as NSString).length - 1
        let newZOffset = zOffset + 3 + 5

        let behind = try #require(Self.reconciled(markdown, caret: zOffset, titles))
        #expect(behind.selection == NSRange(location: newZOffset, length: 0))
        #expect((behind.text as NSString).substring(with: NSRange(location: newZOffset, length: 1)) == "z")

        let ahead = try #require(Self.reconciled(markdown, caret: 1, titles))
        #expect(ahead.selection == NSRange(location: 1, length: 0))

        let spanning = try #require(MarkdownTaskEmbedParser.reconcilingReferenceTitles(
            in: markdown,
            selection: NSRange(location: 0, length: zOffset + 1),
            titles: titles,
            fallback: Self.fallback
        ))
        #expect(spanning.selection == NSRange(location: 0, length: newZOffset + 1))
    }

    /// Nothing renamed, nothing to move: the same nil the text-only spelling answers.
    @Test func theSelectionSpellingReturnsNilWhenNothingChanged() {
        #expect(Self.reconciled(Self.reference(Self.taskID, "Milk"), caret: 0, [Self.taskID: "Milk"]) == nil)
    }

    /// The iOS surface is the caller that holds text and selection apart, so its reconcile must
    /// write both from the one answer. A surface that went back to `updateDraft(reconciled)` alone
    /// would compile against the text-only spelling and bring the strip back.
    @Test func theIOSSurfaceMovesItsSelectionWithTheReconciledText() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        )
        let body = try #require(CadenceSourceScan.functionBody(named: "reconcileEmbeddedTaskReferenceTitles", in: source))
        #expect(body.contains("selection: selectedRange"))
        #expect(body.contains("updateDraft(reconciled.text)"))
        #expect(body.contains("selectedRange = reconciled.selection"))
    }
}
