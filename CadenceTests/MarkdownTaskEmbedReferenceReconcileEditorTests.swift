import Foundation
import Testing
#if os(macOS)
import AppKit
#endif

@testable import Cadence

#if os(macOS)
/// The macOS half of the stale task-embed reference bug (`T-88`), the twin of the iOS fix in
/// `D-56`.
///
/// A task embed's title is stored twice: on the `AppTask`, and inside the note's own
/// `[[task:UUID|Title]]` source. macOS rewrote the note only for the inline rename over the card —
/// renaming the same task from the inspector wrote `task.title` alone, and the card went on looking
/// right because it is drawn from the live task rather than from the text under it. The drift only
/// surfaces where the reference text is the only title left: an exported note, a content search, or
/// a deleted task, whose card is rendered by `MarkdownTaskEmbedRenderInfo.missing(reference:)`.
///
/// macOS UI cannot be screenshot-verified from the agent shell (`T-14`), so these run the real
/// `CadenceTextView` and assert on its text and selection rather than on anything drawn. The
/// platform-free rules — which references move and what a title may look like inside one — are
/// `MarkdownTaskEmbedParser`'s, and are covered by `MarkdownTaskEmbedReferenceReconcileTests`.
@MainActor
struct MarkdownTaskEmbedReferenceReconcileEditorTests {
    private static let taskID = UUID(uuidString: "7C2E1A44-9B0D-4F65-9C2A-0E1D2B3C4D5E")!
    private static let otherID = UUID(uuidString: "1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D")!

    private static func reference(_ id: UUID, _ title: String) -> String {
        "[[task:\(id.uuidString)|\(title)]]"
    }

    private static func textView(_ markdown: String) -> CadenceTextView {
        let textView = CadenceTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        textView.string = markdown
        return textView
    }

    // MARK: - Reconciling the open note

    /// The bug itself: the task was renamed somewhere that is not the note, and the note catches up.
    @Test func rewritesAReferenceWhoseTaskWasRenamedOutsideTheNote() {
        let view = Self.textView("# Errands\n\n\(Self.reference(Self.taskID, "Buy milk"))\n")

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "Buy oat milk"])

        #expect(view.string == "# Errands\n\n\(Self.reference(Self.taskID, "Buy oat milk"))\n")
    }

    /// A note can embed the same task twice, and both cards read the live title, so both runs of
    /// source have to move or one note disagrees with itself.
    @Test func rewritesEveryReferenceToTheSameTask() {
        let view = Self.textView(
            "\(Self.reference(Self.taskID, "Buy milk"))\n\nlater\n\n\(Self.reference(Self.taskID, "Buy milk"))\n"
        )

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "Buy oat milk"])

        #expect(view.string.components(separatedBy: "Buy oat milk").count == 3)
        #expect(view.string.contains("Buy milk") == false)
    }

    /// Several embeds, one rename: the others are not rewritten just because they were handed over.
    @Test func leavesReferencesThatAlreadyAgreeUntouched() {
        let markdown = "\(Self.reference(Self.taskID, "Buy milk"))\n\(Self.reference(Self.otherID, "Call Sam"))\n"
        let view = Self.textView(markdown)

        view.reconcileEmbeddedTaskReferenceTitles(
            titles: [Self.taskID: "Buy oat milk", Self.otherID: "Call Sam"]
        )

        #expect(view.string == "\(Self.reference(Self.taskID, "Buy oat milk"))\n\(Self.reference(Self.otherID, "Call Sam"))\n")
    }

    /// A reference to a task the editor was never handed — deleted, or in another context — keeps
    /// its own text. That stale title is the only name that reference has left, and it is what the
    /// missing-task card is drawn from.
    @Test func leavesAReferenceWithNoKnownTaskAlone() {
        let markdown = Self.reference(Self.otherID, "Call Sam")
        let view = Self.textView(markdown)

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "Buy oat milk"])

        #expect(view.string == markdown)
    }

    /// Closing the inspector without renaming anything must not touch the note at all — the note is
    /// a document the user is editing, and a write here would ripple out to `updatedAt`.
    @Test func doesNothingWhenEveryReferenceAlreadyAgrees() {
        let markdown = "# Errands\n\n\(Self.reference(Self.taskID, "Buy milk"))\n"
        let view = Self.textView(markdown)
        view.setSelectedRange(NSRange(location: 3, length: 0))

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "Buy milk"])

        #expect(view.string == markdown)
        #expect(view.selectedRange() == NSRange(location: 3, length: 0))
    }

    /// An empty task title is not written into the source as an empty run — the reference would
    /// stop parsing as one. It takes the same fallback the card draws.
    @Test func writesTheFallbackTitleForATaskWithNoTitle() {
        let view = Self.textView(Self.reference(Self.taskID, "Buy milk"))

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "   "])

        #expect(view.string == Self.reference(Self.taskID, MarkdownTaskEmbedRenderInfo.untitledTaskTitle))
    }

    // MARK: - Applying it to a note somebody is sitting in

    /// The reason this is not `textView.string = reconciled`. The caret is further down the note
    /// than the reference that moved, so it has to travel with the text rather than stay at an
    /// absolute offset or drop to the top.
    @Test func keepsTheCaretOnTheSameCharacterAfterAShorterTitle() {
        let body = "\(Self.reference(Self.taskID, "Buy oat milk"))\n\nnotes after"
        let view = Self.textView(body)
        let caret = (body as NSString).range(of: "after").location
        view.setSelectedRange(NSRange(location: caret, length: 0))

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "Buy milk"])

        let expected = (view.string as NSString).range(of: "after").location
        #expect(view.selectedRange() == NSRange(location: expected, length: 0))
    }

    /// The same in the other direction, and above the edit rather than below it: a caret ahead of
    /// the reference does not move at all.
    @Test func leavesACaretAheadOfTheEditWhereItWas() {
        let view = Self.textView("# Errands\n\n\(Self.reference(Self.taskID, "Buy milk"))")
        view.setSelectedRange(NSRange(location: 4, length: 0))

        view.reconcileEmbeddedTaskReferenceTitles(titles: [Self.taskID: "Buy a great deal of oat milk"])

        #expect(view.selectedRange() == NSRange(location: 4, length: 0))
    }

    /// The edit handed to the text storage is the run that differs, not the document. Whole-document
    /// replacement is what drops the scroll position and collapses the undo stack of a note.
    ///
    /// "Buy milk" to "Buy oat milk" shares both ends, so the edit is the insertion of `oat ` — four
    /// characters, in a note whose prose before and after the card is never touched.
    @Test func replacesOnlyTheRunThatDiffers() {
        let before = "# Errands\n\n\(Self.reference(Self.taskID, "Buy milk"))\n\ntrailing prose" as NSString
        let after = "# Errands\n\n\(Self.reference(Self.taskID, "Buy oat milk"))\n\ntrailing prose" as NSString

        let edit = MarkdownTextEditDiff.minimalEdit(from: before, to: after)

        #expect(edit.range == NSRange(location: before.range(of: "milk").location, length: 0))
        #expect(after.substring(with: edit.replacementRange) == "oat ")
    }

    /// The same, shortening rather than lengthening: a pure deletion, and again only of the run
    /// that moved.
    @Test func shorteningATitleDeletesOnlyTheRunThatWent() {
        let before = "\(Self.reference(Self.taskID, "Buy oat milk"))\n\ntrailing prose" as NSString
        let after = "\(Self.reference(Self.taskID, "Buy milk"))\n\ntrailing prose" as NSString

        let edit = MarkdownTextEditDiff.minimalEdit(from: before, to: after)

        #expect(before.substring(with: edit.range) == "oat ")
        #expect(edit.replacementRange.length == 0)
    }

    /// Identical strings produce an empty edit rather than a whole-document one, so the guard in
    /// `reconcileEmbeddedTaskReferenceTitles` is not the only thing standing between a no-op and a
    /// rewrite.
    @Test func minimalEditOfAnUnchangedStringIsEmpty() {
        let text = "# Errands\n\nnothing moved" as NSString

        let edit = MarkdownTextEditDiff.minimalEdit(from: text, to: text)

        #expect(edit.range.length == 0)
        #expect(edit.replacementRange.length == 0)
    }

    /// A selection sitting inside the run that was rewritten has had the ground taken out from
    /// under it, so it collapses to the run's start instead of pointing at arbitrary characters.
    @Test func collapsesASelectionInsideTheEditedRun() {
        let before = "abc def ghi" as NSString
        let after = "abc XY ghi" as NSString
        let edit = MarkdownTextEditDiff.minimalEdit(from: before, to: after)

        let moved = MarkdownTextEditDiff.selection(
            NSRange(location: 5, length: 0),
            after: edit,
            in: after.length
        )

        #expect(moved == NSRange(location: edit.range.location, length: 0))
    }
}
#endif
