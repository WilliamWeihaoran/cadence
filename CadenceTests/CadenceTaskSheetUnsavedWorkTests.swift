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
        draft.isSettled = true
        #expect(!Self.unsaved(draft), "Complete made the sheet refuse its swipe-down")
        draft.isSettled = false
        #expect(!Self.unsaved(draft))
    }

    @Test func aRealEditStillCountsWhenTheTaskWasAlsoCompleted() {
        var draft = Self.opened()
        draft.isSettled = true
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

    // MARK: - T-5175, the tag half: an unsent tag is added when its popover dismisses

    /// Owner decision 2026-10-24, option (a). The popover's own body, not the strip's, carries the
    /// dismiss handler, and it is `addTag` itself, so blank input, an existing name and a refused
    /// store keep the `+` button's rules. Option (b), clearing the field, was declined.
    @Test func dismissingTheTagPopoverAddsTheTypedNameThroughAddTag() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        #expect(raw.count > 1_000)
        let file = CadenceSourceScan.codeOnly(CadenceSourceScan.strippingComments(raw))
        let popover = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskTagPickerPopover: View", in: file)
        )
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: popover))
        #expect(body.contains(".onDisappear(perform: addTagOnDismiss)"))
        let onDismiss = try #require(CadenceSourceScan.functionBody(named: "addTagOnDismiss", in: popover))
        #expect(onDismiss.contains("addTag()"), "the dismiss path no longer goes through addTag itself")
        // [[T-17935]]: the field is a search field, so the dismiss adds only a name that matched no
        // row, and asks that before anything else -- the decision `CadenceTagPickerQueryTests`
        // drives as values.
        // [[T-17962]]: a query the gate does not commit is cleared, so it does not pre-filter the
        // next open (the Mac's field always opens empty). Read with literals intact, since
        // `codeOnly` blanks the `""` this needs.
        let popoverWithLiterals = try #require(CadenceSourceScan.declarationBody(
            "struct iOSTaskTagPickerPopover: View", in: CadenceSourceScan.strippingComments(raw)
        ))
        let dismissWithLiterals = try #require(
            CadenceSourceScan.functionBody(named: "addTagOnDismiss", in: popoverWithLiterals)
        )
        let gated = try #require(
            dismissWithLiterals.range(
                of: #"guard TagSupport\.pickerDismissCommits\(newTagName, in: allTags\) else \{\s*newTagName = ""\s*return\s*\}"#,
                options: .regularExpression
            ),
            "the dismiss commits a partial query that matched a row (T-17935), or keeps it in the field (T-17962)"
        )
        let added = try #require(dismissWithLiterals.range(of: "addTag()"))
        #expect(gated.lowerBound < added.lowerBound, "addTag runs before the dismiss gate")
        #expect(CadenceSourceScan.matchCount(#"\.onDisappear"#, in: popover) == 1)
        // Read with string literals intact: `codeOnly` blanks them, which made this a check of
        // nothing (found while landing [[T-17935]]).
        let literals = CadenceSourceScan.strippingComments(raw)
        let strip = try #require(CadenceSourceScan.declarationBody("struct iOSTaskTagStrip: View", in: literals))
        #expect(strip.contains("newTagName"), "non-vacuity: wrong strip read")
        #expect(!strip.contains("newTagName = \"\""), "the strip clears the typed tag (option (b), declined)")
        let add = try #require(CadenceSourceScan.functionBody(named: "addTag", in: popover))
        // [[T-12772]]: blank input still returns early, now through the list's own decision, and
        // an archived match takes the Unarchive row's path rather than `committedTag`.
        #expect(add.contains("switch TagSupport.pickerFieldCommit(newTagName, in: allTags) {"))
        #expect(add.range(of: #"case \.nothing:\s*return"#, options: .regularExpression) != nil)
        // The call, not the `case let .unarchive(archived):` pattern, which spells the same text.
        let unarchived = try #require(
            add.range(of: #"case let \.unarchive\(archived\):\s*unarchive\(archived\)\s*return"#, options: .regularExpression),
            "an archived match no longer goes through unarchive(_:)"
        )
        let resolved = try #require(add.range(of: "TagSupport.committedTag(named: name, in: modelContext)"))
        #expect(unarchived.lowerBound < resolved.lowerBound, "an archived match reaches committedTag")
    }

    /// [[T-17935]]: tapping a row answers the query, so `toggle(_:)` clears the field. Left in
    /// place, `wor` typed to find `work` re-filtered the next open and fed the dismiss-add. Both
    /// callers -- the task sheet's strip and the note tag control -- present this one popover.
    @Test func tappingATagRowClearsTheSearchField() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        #expect(raw.count > 1_000)
        // Comments stripped, string literals kept: `codeOnly` blanks the `""` this looks for.
        let file = CadenceSourceScan.strippingComments(raw)
        let popover = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskTagPickerPopover: View", in: file)
        )
        let toggle = try #require(CadenceSourceScan.functionBody(named: "toggle", in: popover))
        #expect(toggle.contains("selectedTags"), "non-vacuity: wrong toggle read")
        #expect(toggle.contains("newTagName = \"\""), "a tapped row leaves its query in the field (T-17935)")

        let note = CadenceSourceScan.codeOnly(CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNoteTagControl.swift")
        ))
        #expect(note.contains("iOSTaskTagPickerPopover("), "the note control no longer shares the popover")
    }

    // MARK: - T-6471: a refusal on the dismiss path is named by the strip, which is still on screen

    /// [[T-6471]]. On the dismiss path `addTag()` writes its refusal into the popover's own notice,
    /// and the popover is the surface that is closing. The dismiss wrapper hands that sentence to
    /// `onDismissRefusal`, which the strip answers by setting the notice it already draws.
    @Test func aRefusedDismissAddIsNamedByTheStripRatherThanTheClosingPopover() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        #expect(raw.count > 1_000)
        let file = CadenceSourceScan.codeOnly(CadenceSourceScan.strippingComments(raw))
        let popover = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskTagPickerPopover: View", in: file)
        )
        let onDismiss = try #require(CadenceSourceScan.functionBody(named: "addTagOnDismiss", in: popover))
        let cleared = try #require(onDismiss.range(of: "tagFailureNotice = nil"))
        let added = try #require(onDismiss.range(of: "addTag()"))
        let reported = try #require(onDismiss.range(of: "onDismissRefusal(tagFailureNotice)"))
        #expect(cleared.lowerBound < added.lowerBound, "an older refusal would be re-reported by an empty dismiss")
        #expect(added.lowerBound < reported.lowerBound, "the refusal is handed on before addTag made it")
        #expect(onDismiss.contains("if let tagFailureNotice {"), "a committed add is reported as a refusal")

        // The open popover's `+` and Return keep their own notice: only the dismiss path hands it on.
        let add = try #require(CadenceSourceScan.functionBody(named: "addTag", in: popover))
        #expect(!add.contains("onDismissRefusal"))

        let strip = try #require(CadenceSourceScan.declarationBody("struct iOSTaskTagStrip: View", in: file))
        let presented = try #require(
            CadenceSourceScan.declarationBody(".popover(isPresented: $showPicker)", in: strip)
        )
        #expect(presented.contains("onDismissRefusal: { tagFailureNotice = $0 }"))
        #expect(strip.contains("CadenceInlineFailureNotice(text: tagFailureNotice)"))
    }
}
