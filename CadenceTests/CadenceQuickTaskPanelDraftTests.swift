// macOS only: the quick-capture panel is an `NSPanel` the desktop app owns.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-5302]] — the Mac quick-capture panel keeps a half-typed task when it closes.**
///
/// `show()` built a fresh hosting controller every open ("Always create a fresh hosting
/// controller so @State resets on each open") and the panel closes on resign-key, so clicking
/// the browser to copy a URL and pressing the hotkey again gave a blank form. The owner kept the
/// close — a panel that will not go away when you click elsewhere is its own irritation — and
/// asked for the draft back instead, cleared on save or Escape.
///
/// The retention rule is a value type and is driven directly; the controller is not, because
/// `show()` wants a real `ModelContainer` and puts a floating panel on the screen. The paths that
/// drive it are pinned as source, which is the only way to tell a *keeping* close from a
/// *clearing* one without a window.
@MainActor
struct CadenceQuickTaskPanelDraftTests {

    // MARK: - The rule

    /// The defect, stated as the rule that fixes it.
    @Test func aPanelClosedByFocusLossHandsTheNextOpenItsForm() {
        var retention = QuickTaskPanelDraftRetention()
        #expect(!retention.reusesTheStandingForm(hasForm: true, seedIsEmpty: true), "nothing typed yet")

        retention.panelClosedWithTheDraftUnresolved()
        #expect(retention.holdsDraft)
        #expect(retention.reusesTheStandingForm(hasForm: true, seedIsEmpty: true))
    }

    /// The two acts the owner named. Either one and the next open starts blank.
    @Test func savingOrEscapingClearsTheDraft() {
        var retention = QuickTaskPanelDraftRetention()
        retention.panelClosedWithTheDraftUnresolved()
        retention.draftResolved()
        #expect(!retention.holdsDraft)
        #expect(!retention.reusesTheStandingForm(hasForm: true, seedIsEmpty: true))

        // And resolving twice is not a way back in.
        retention.draftResolved()
        #expect(!retention.reusesTheStandingForm(hasForm: true, seedIsEmpty: true))
    }

    /// A held draft with no form standing restores nothing: after a successful capture the
    /// success view has taken the form's place, and handing that back would reopen a tick.
    @Test func aHeldDraftWithNoFormStandingRestoresNothing() {
        var retention = QuickTaskPanelDraftRetention()
        retention.panelClosedWithTheDraftUnresolved()
        #expect(!retention.reusesTheStandingForm(hasForm: false, seedIsEmpty: true))
    }

    /// A caller that pre-fills the panel is asking for *that* form, so a stale draft stands down.
    @Test func aSeedThatAsksForSomethingWinsOverAStandingDraft() {
        var retention = QuickTaskPanelDraftRetention()
        retention.panelClosedWithTheDraftUnresolved()
        #expect(!retention.reusesTheStandingForm(hasForm: true, seedIsEmpty: false))
    }

    // MARK: - [[T-6202]] the success beat's timer

    /// The defect: capture, then reopen inside the 0.95 s beat. The old timer closed the new
    /// panel, through the path that discards its draft.
    @Test func aSuccessTimerCannotCloseAPanelReopenedInsideTheBeat() {
        var dismissal = QuickTaskPanelSuccessDismissal()
        let token = dismissal.successShown()
        #expect(dismissal.timerMayClose(token: token), "control: an undisturbed beat closes itself")

        dismissal.presentationEnded() // the hotkey's close
        dismissal.presentationEnded() // and the reopen
        #expect(!dismissal.timerMayClose(token: token))
        #expect(!dismissal.isShowingSuccess)
    }

    /// A second capture in the reopened panel schedules its own timer; the first one's is still
    /// stale and the second one's still closes.
    @Test func onlyTheLatestCapturesTimerMayClose() {
        var dismissal = QuickTaskPanelSuccessDismissal()
        let first = dismissal.successShown()
        dismissal.presentationEnded()
        let second = dismissal.successShown()
        #expect(!dismissal.timerMayClose(token: first))
        #expect(dismissal.timerMayClose(token: second))
    }

    /// The wiring, read as source: every presentation change moves the token on, the timer asks
    /// before it closes, and a close during the beat does not keep the tick as a "draft".
    @Test func theControllerTokensTheSuccessTimerAndEveryPresentationChangeMovesIt() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Services/QuickTaskPanelController.swift")
        let success = try #require(CadenceSourceScan.declarationBody("private func showCaptureSuccessThenClose()", in: source))
        #expect(success.contains("let token = successDismissal.successShown()"))
        #expect(success.contains("guard let self, self.successDismissal.timerMayClose(token: token) else { return }"))

        let show = try #require(CadenceSourceScan.declarationBody("func show(seed: TaskCreationSeed", in: source))
        #expect(show.contains("successDismissal.presentationEnded()"))
        let orderOut = try #require(CadenceSourceScan.declarationBody("private func orderPanelOut()", in: source))
        #expect(orderOut.contains("successDismissal.presentationEnded()"))

        let close = try #require(CadenceSourceScan.declarationBody("func close()", in: source))
        let beat = try #require(close.range(of: "if successDismissal.isShowingSuccess"))
        let keep = try #require(close.range(of: "draftRetention.panelClosedWithTheDraftUnresolved()"))
        #expect(beat.lowerBound < keep.lowerBound, "a close during the beat must discard before it can keep")
    }

    // MARK: - What counts as an empty seed

    @Test func afreshSeedIsEmptyAndAnyFilledFieldIsNot() {
        #expect(QuickTaskPanelController.seedIsEmpty(TaskCreationSeed()))

        var filled: [TaskCreationSeed] = []
        var seed = TaskCreationSeed(); seed.title = "Call the bank"; filled.append(seed)
        seed = TaskCreationSeed(); seed.notes = "account number"; filled.append(seed)
        seed = TaskCreationSeed(); seed.dueDateKey = "2026-10-25"; filled.append(seed)
        seed = TaskCreationSeed(); seed.doDateKey = "2026-10-25"; filled.append(seed)
        seed = TaskCreationSeed(); seed.scheduledStartMin = 540; filled.append(seed)
        seed = TaskCreationSeed(); seed.estimatedMinutes = 45; filled.append(seed)
        seed = TaskCreationSeed(); seed.priority = .high; filled.append(seed)
        seed = TaskCreationSeed(); seed.container = .inbox; seed.sectionName = "Later"; filled.append(seed)
        seed = TaskCreationSeed(); seed.subtaskTitles = ["First"]; filled.append(seed)

        // Nine fields, nine seeds: a field dropped from the comparison is a draft silently
        // overwritten by a seed that asked for something.
        #expect(filled.count == 9)
        for candidate in filled {
            #expect(!QuickTaskPanelController.seedIsEmpty(candidate), "\(candidate.title)/\(candidate.sectionName)")
        }
    }

    // MARK: - Which path drives which

    /// The asymmetry, where it actually lives. `close()` keeps and `closeDiscardingDraft()`
    /// clears, so this reads the two bodies apart: a test that only checked both names exist
    /// would pass with them swapped.
    @Test func closingKeepsTheDraftAndOnlyEscapeSaveAndCancelClearIt() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Services/QuickTaskPanelController.swift")
        #expect(
            !source.contains("Always create a fresh hosting controller"),
            "the open path still rebuilds the form, which is the defect"
        )

        let close = try #require(CadenceSourceScan.declarationBody("func close()", in: source))
        #expect(close.contains("draftRetention.panelClosedWithTheDraftUnresolved()"))
        #expect(!close.contains("draftRetention.draftResolved()"))

        let discarding = try #require(CadenceSourceScan.declarationBody("func closeDiscardingDraft()", in: source))
        #expect(discarding.contains("draftRetention.draftResolved()"))
        #expect(discarding.contains("hostingController = nil"))
        #expect(!discarding.contains("panelClosedWithTheDraftUnresolved"))

        // Escape, and the sheet's own Cancel ✕, both clear.
        let cancel = try #require(CadenceSourceScan.declarationBody("override func cancelOperation", in: source))
        #expect(cancel.contains("QuickTaskPanelController.shared.closeDiscardingDraft()"))
        #expect(source.contains("dismissAction: { [weak self] in self?.closeDiscardingDraft() }"))

        // A capture that landed spends the draft before the success view replaces the form.
        let success = try #require(CadenceSourceScan.declarationBody("private func showCaptureSuccessThenClose()", in: source))
        #expect(success.contains("draftRetention.draftResolved()"))
        #expect(success.contains("self.closeDiscardingDraft()"))

        // And the open path asks, rather than always rebuilding.
        let show = try #require(CadenceSourceScan.declarationBody("func show(seed: TaskCreationSeed", in: source))
        #expect(show.contains("draftRetention.reusesTheStandingForm("))
        #expect(show.contains("seedIsEmpty: Self.seedIsEmpty(seed)"))
        #expect(show.contains("if restoring, let standing = hostingController"))
    }
}
#endif
