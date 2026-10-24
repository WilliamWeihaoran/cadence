import Foundation
import Testing
@testable import Cadence

/// What the iOS task sheet would lose if it closed now ([[T-5359]], [[T-5173]], [[T-5175]]).
///
/// The decision is `CadenceTaskSheetUnsavedWork`, compiled here and tested as values. The sheet is
/// `#if os(iOS)` and this target is macOS-built, so its wiring — the swipe guard, the Focus
/// button and Save reading that one answer — is pinned by source shape below.
@MainActor
struct CadenceTaskSheetUnsavedWorkTests {

    private static func opened() -> CadenceScheduleDraft {
        CadenceScheduleDraft(dateKey: "2026-10-23", startMin: 9 * 60, kind: .task)
    }

    private static func unsaved(
        _ draft: CadenceScheduleDraft,
        notesPending: Bool = false,
        subtask: String = ""
    ) -> Bool {
        CadenceTaskSheetUnsavedWork.hasUnsavedWork(
            draft: draft,
            opened: opened(),
            notesHavePendingEdit: notesPending,
            pendingSubtaskTitle: subtask
        )
    }

    // MARK: - T-5359: completion is not an edit

    @Test func anUntouchedDraftHasNothingToLose() {
        #expect(!Self.unsaved(Self.opened()))
    }

    @Test func completingTheTaskFromTheSheetIsNotAnUnsavedEdit() {
        var draft = Self.opened()
        draft.isDone = true
        #expect(!Self.unsaved(draft), "Complete made the sheet refuse its swipe-down")
        draft.isDone = false
        #expect(!Self.unsaved(draft))
    }

    @Test func aRealEditStillCountsWhenTheTaskWasAlsoCompleted() {
        var draft = Self.opened()
        draft.isDone = true
        draft.title = "Retitled"
        #expect(Self.unsaved(draft))
    }

    @Test func everyUserFieldStillCounts() {
        var dated = Self.opened()
        dated.dueDateKey = "2026-10-30"
        var estimated = Self.opened()
        estimated.estimateMinutes += 15
        var noted = Self.opened()
        noted.notes = "typed"
        for draft in [dated, estimated, noted] {
            #expect(Self.unsaved(draft))
        }
    }

    @Test func notesTheWellHasNotWrittenYetCount() {
        #expect(Self.unsaved(Self.opened(), notesPending: true))
    }

    // MARK: - T-5175: an unsent subtask is the user's work

    @Test func aSubtaskTypedButNotSentCounts() {
        #expect(Self.unsaved(Self.opened(), subtask: "Call Sam"))
        #expect(CadenceTaskSheetUnsavedWork.hasPendingComposerEntry("Call Sam"))
    }

    @Test func whitespaceInTheComposerIsNothingToLose() {
        #expect(!Self.unsaved(Self.opened(), subtask: "  \n\t "))
        #expect(!CadenceTaskSheetUnsavedWork.hasPendingComposerEntry(""))
        #expect(!CadenceTaskSheetUnsavedWork.hasPendingComposerEntry(" \n"))
    }

    // MARK: - Source shape: the sheet reads the one answer

    private static func sheet() throws -> String {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheet.swift")
        #expect(raw.count > 1_000)
        return CadenceSourceScan.codeOnly(CadenceSourceScan.strippingComments(raw))
    }

    @Test func theSwipeGuardReadsTheSharedAnswerWithBothPendingInputs() throws {
        let sheet = try Self.sheet()
        #expect(sheet.contains(".interactiveDismissDisabled(hasUnsavedWork)"))
        #expect(!sheet.contains("interactiveDismissDisabled(draft != openedDraft"))
        let property = try #require(CadenceSourceScan.declarationBody("private var hasUnsavedWork: Bool", in: sheet))
        #expect(property.contains("CadenceTaskSheetUnsavedWork.hasUnsavedWork("))
        #expect(property.contains("notesHavePendingEdit: notesFlush.hasPendingEdit"))
        #expect(property.contains("pendingSubtaskTitle: newSubtaskTitle"))
    }

    /// T-5173: the handoff closes the sheet, so it is disabled, and refuses, while work is unsaved.
    @Test func focusThisTaskIsOfferedOnlyWhenClosingLosesNothing() throws {
        let sheet = try Self.sheet()
        let focus = try #require(CadenceSourceScan.declarationBody("private var focusSection: some View", in: sheet))
        #expect(focus.contains("isDisabled: blocked"))
        #expect(focus.contains("let blocked = hasUnsavedWork"))
        let guardAt = try #require(focus.range(of: "guard !hasUnsavedWork else { return }"))
        let requestAt = try #require(focus.range(of: "CadenceFocusHandoffCenter.shared.request("))
        #expect(guardAt.lowerBound < requestAt.lowerBound)
        #expect(focus.contains("CadenceTaskSheetUnsavedWork.focusBlockedCaption"))
    }

    /// T-5175: Save adds the unsent subtask before the draft's commit, and stops if it is refused.
    @Test func saveAddsTheUnsentSubtaskBeforeCommittingTheDraft() throws {
        let sheet = try Self.sheet()
        let apply = try #require(CadenceSourceScan.functionBody(named: "applySave", in: sheet))
        let addAt = try #require(apply.range(of: "guard addSubtask() else { return }"))
        let commitAt = try #require(apply.range(of: "CadenceTaskEditDraftCommit.save("))
        #expect(addAt.lowerBound < commitAt.lowerBound)
        #expect(apply.contains("if canAddSubtask {"))
        let canAdd = try #require(CadenceSourceScan.declarationBody("private var canAddSubtask: Bool", in: sheet))
        #expect(canAdd.contains("CadenceTaskSheetUnsavedWork.hasPendingComposerEntry(newSubtaskTitle)"))
    }
}
