import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-633: iOS's two recurrence scope dialogs closed themselves, then swallowed the commit.**
///
/// `iOSTaskRowRecurrenceScopeDialogModifier.applyPendingRecurrenceRule` and
/// `iOSTaskDetailSheet.apply(_:scope:)` each ran `CadenceTaskRecurrenceWorkflowSupport`'s rule/end
/// write, set the pending change to `nil` — **which is what closes the dialog** — and ended
/// `try? modelContext.save()`. That is half 2 of the rule (`AGENTS.md`, "The `try? save()` rule"),
/// and for `.thisAndFuture` it is the expensive spelling of it: the rule is rewritten on every
/// later occurrence of the series in memory, the dialog closes exactly as it does on success, and
/// the row's own "Couldn't Update the Series" alert had no path that could ever fire it.
///
/// **The unit is `CadenceTaskFieldEditCommit.commit(_:alsoRestoring:in:)`**, not a fourth
/// hand-rolled snapshot: it is what macOS's `TaskEmbedFieldEditorPopover` reaches this same dialog
/// through, and its `alsoRestoring:` exists for exactly this edit — the caller passes the list the
/// edit itself walks rather than deriving the same list a second way.
///
/// Two halves, for the reason `CadenceNoteMoveCommitTests` gives: the undo is behavioural, against
/// a real container with a `commit` that throws, because a `save()` that throws cannot be provoked
/// out of an in-memory container; the two dialogs are `private` members of SwiftUI views that
/// nothing can call, so their ordering is a source scan.
@MainActor
struct CadenceRecurrenceScopeCommitTests {

    private struct CommitRefused: Error {}

    private static let rowPath = "Cadence/iOS/iOSTaskRowActionViews.swift"
    private static let sheetPath = "Cadence/iOS/iOSTaskDetailSheet.swift"

    /// A three-occurrence series: `first` spawned `second`, which spawned `third`.
    private func series(in context: ModelContext) throws -> [AppTask] {
        let seriesID = UUID()
        let tasks = (0..<3).map { index -> AppTask in
            let task = AppTask(title: "Occurrence \(index)")
            task.recurrenceRule = .daily
            task.recurrenceSeriesIDRaw = seriesID.uuidString
            task.recurrenceOccurrenceIndex = index
            task.scheduledDate = "2026-05-0\(index + 1)"
            context.insert(task)
            return task
        }
        tasks[0].recurrenceSpawnedTaskID = tasks[1].id
        tasks[1].recurrenceSpawnedTaskID = tasks[2].id
        try context.save()
        return tasks
    }

    // MARK: - Behavioural: what a refused scope edit leaves behind

    /// **The defect, stated as a store reading.** `.thisAndFuture` writes the new rule to every
    /// later occurrence; a refused commit has to put all of them back, or the dialog closes over a
    /// series that reads one way in memory and another way in the store.
    @Test func arefusedThisAndFutureRuleChangePutsEveryLaterOccurrenceBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: tasks[0],
            allTasks: tasks,
            scope: .thisAndFuture
        )
        #expect(targets.count == 3, "the edit reaches all three occurrences")

        let landed = CadenceTaskFieldEditCommit.commit(
            tasks[0],
            alsoRestoring: targets,
            in: context,
            commit: { _ in throw CommitRefused() }
        ) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                .weekly,
                to: tasks[0],
                allTasks: tasks,
                scope: .thisAndFuture
            )
        }

        #expect(landed == false, "a refused commit must not answer success")
        for task in tasks {
            #expect(task.recurrenceRule == .daily, "\(task.title) kept a rule the store never took")
        }
    }

    /// The accepted path, without which the test above passes over an edit that never happened.
    @Test func anAcceptedThisAndFutureRuleChangeReachesTheStoreForEveryOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: tasks[0],
            allTasks: tasks,
            scope: .thisAndFuture
        )
        let landed = CadenceTaskFieldEditCommit.commit(tasks[0], alsoRestoring: targets, in: context) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                .weekly,
                to: tasks[0],
                allTasks: tasks,
                scope: .thisAndFuture
            )
        }

        #expect(landed)
        #expect(!context.hasChanges, "the edit was left pending for another screen's save")
        let reader = ModelContext(container)
        let stored = try reader.fetch(FetchDescriptor<AppTask>())
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.recurrenceRule == .weekly })
    }

    /// `.thisTask` is the narrow scope, and its refusal must not leak into the siblings either —
    /// the same commit, with a one-element target list.
    @Test func arefusedThisTaskRuleChangeLeavesTheRestOfTheSeriesUntouched() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)

        let targets = CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(
            from: tasks[0],
            allTasks: [],
            scope: .thisTask
        )
        #expect(targets.map(\.id) == [tasks[0].id])

        let landed = CadenceTaskFieldEditCommit.commit(
            tasks[0],
            alsoRestoring: targets,
            in: context,
            commit: { _ in throw CommitRefused() }
        ) {
            CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule(
                .none,
                to: tasks[0],
                allTasks: [],
                scope: .thisTask
            )
        }

        #expect(landed == false)
        #expect(tasks[0].recurrenceRule == .daily)
        #expect(tasks[0].recurrenceSpawnedTaskID == tasks[1].id, "the successor pointer was cleared anyway")
    }

    // MARK: - Source shape: the row chip's dialog

    /// Neither the swallow nor the false report survives, and the alert that already existed has a
    /// path to it now.
    @Test func therowScopeDialogCommitsAndNamesArefusalInTheAlertItAlreadyOwned() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.rowPath)
        let body = try CadenceCommitSurfaceScan.declarationBody(
            named: "applyPendingRecurrenceRule",
            in: source
        )

        #expect(CadenceSourceScan.matchCount(#"try\?\s*modelContext"#, in: body) == 0)
        #expect(body.contains("CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext)"))
        #expect(body.contains("seriesUpdateFailure = CadencePendingChangePersistence.editFailureNotice"))
        #expect(body.contains("seriesUpdateFailure = CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice"))
        #expect(source.contains("@State private var seriesUpdateFailure: String?"))
        #expect(
            !source.contains("seriesLookupFailed"),
            "the old flag could only ever say the fetch failed"
        )

        // A notice nothing draws is not a report: the alert reads the state the refusal sets.
        #expect(source.contains("CadenceRecurrenceScopeCopy.taskScopeFailureTitle"))
        #expect(source.contains("presenting: seriesUpdateFailure"))

        // The stripper's own discrimination, pinned on a literal: this file is `#if os(iOS)`, so a
        // reader that had quietly blanked everything cannot pass the assertions above.
        #expect(source.contains("struct iOSTaskRowRecurrenceScopeDialogModifier: ViewModifier"))
    }

    // MARK: - Source shape: the task sheet's dialog

    /// The sheet is the second door onto the same dialog and had the same defect one frame down —
    /// `apply` swallowed, `applyPendingRecurrenceChange` closed the dialog.
    @Test func thesheetScopeDialogCommitsThroughTheSameUnitAndReportsTheSameWay() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.sheetPath)
        let apply = try CadenceCommitSurfaceScan.declarationBody(named: "apply", in: source)

        #expect(CadenceSourceScan.matchCount(#"try\?\s*modelContext"#, in: apply) == 0)
        #expect(apply.contains("CadenceTaskFieldEditCommit.commit(task, alsoRestoring: targets, in: modelContext)"))
        #expect(apply.contains("recurrenceUpdateFailure = landed ? nil : CadencePendingChangePersistence.editFailureNotice"))
        #expect(source.contains("@State private var recurrenceUpdateFailure: String?"))
        #expect(source.contains("presenting: recurrenceUpdateFailure"))

        // One title over both dialogs, from the copy holder that already owns the dialog's prose.
        #expect(source.contains("CadenceRecurrenceScopeCopy.taskScopeFailureTitle"))
        #expect(source.contains("struct iOSTaskDetailSheet: View"))
    }

    /// The two sentences are different sentences, and the lookup one is the only place "Try again"
    /// is honest: a store that refused a write is not retried by tapping the same button.
    @Test func thetwoWaysAScopeEditFailsAreNotTheSameSentence() {
        #expect(CadenceRecurrenceScopeCopy.taskScopeFailureTitle == "Couldn't Update the Series")
        #expect(CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice.contains("couldn't load"))
        #expect(CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice.hasSuffix("Try again."))
        #expect(
            CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice
                != CadencePendingChangePersistence.editFailureNotice
        )
        // Both earn "nothing was changed": the lookup fails before the write, and the commit undoes.
        #expect(CadenceRecurrenceScopeCopy.taskScopeLookupFailureNotice.contains("nothing was changed"))
        #expect(CadencePendingChangePersistence.editFailureNotice.contains("Nothing was changed"))
    }
}
