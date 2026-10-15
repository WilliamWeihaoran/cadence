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
    ///
    /// **Re-pointed by [[T-3171]].** The sheet is the shared schedule panel now and its series is a
    /// field of the draft, so the dialog is asked once, at Save, and both of its scopes reach the
    /// one draft save — which commits through the same unit with the same `alsoRestoring:` walk.
    /// The refusal is named in the panel's notice slot rather than a second alert, the one-notice-
    /// per-surface rule (T-646), with the sentence that the undo makes true.
    @Test func thesheetScopeDialogCommitsThroughTheSameUnitAndReportsTheSameWay() throws {
        let source = try CadenceCommitSurfaceScan.scanned(Self.sheetPath)
        #expect(source.contains("struct iOSTaskDetailSheet: View"))
        #expect(source.contains("CadenceRecurrenceScopeCopy.taskScopeTitle"))
        #expect(CadenceSourceScan.matchCount(#"applySave\(scope: \.(thisTask|thisAndFuture)\)"#, in: source) == 3,
                "the dialog's two scopes and the direct save do not all reach the one save")
        let apply = try CadenceCommitSurfaceScan.declarationBody(named: "applySave", in: source)
        #expect(CadenceSourceScan.matchCount(#"try\?\s*modelContext"#, in: apply) == 0)
        #expect(apply.contains("saveFailureNotice = CadencePendingChangePersistence.editFailureNotice"))
        #expect(source.contains("failureNotice: saveFailureNotice"))

        let writer = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/CadenceScheduleDraftTaskEditing.swift")
        let save = try CadenceCommitSurfaceScan.declarationBody(named: "save", in: writer)
        #expect(save.contains("CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets(from: task, allTasks: allTasks, scope: scope)"))
        #expect(save.contains("alsoRestoring: targets,"))
        #expect(CadenceSourceScan.matchCount(#"try\?"#, in: save) == 0)
    }

    /// The behavioural half for the sheet's door: a refused this-and-future end edit through the
    /// draft save puts every occurrence it reached back.
    @Test func arefusedDraftSeriesEditRestoresEveryLaterOccurrence() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let tasks = try series(in: context)
        let opened = CadenceScheduleDraft(editing: tasks[0])
        var draft = opened
        draft.repeatRule = .weekly
        draft.seriesEndMode = .afterCount
        draft.seriesEndCount = 7

        let landed = CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: tasks[0], area: nil, project: nil,
            allTasks: tasks, scope: .thisAndFuture, in: context, reconciler: .inert,
            commit: { _ in throw CommitRefused() }
        )
        #expect(!landed)
        #expect(tasks.map(\.recurrenceRule) == [.daily, .daily, .daily], "a refused series edit left a new rule behind")
        #expect(tasks.map(\.recurrenceEndCount) == [0, 0, 0], "a refused series edit left a new bound behind")

        #expect(CadenceTaskEditDraftCommit.save(
            draft, opened: opened, to: tasks[0], area: nil, project: nil,
            allTasks: tasks, scope: .thisAndFuture, in: context, reconciler: .inert
        ))
        #expect(tasks.map(\.recurrenceRule) == [.weekly, .weekly, .weekly], "this-and-future did not reach the series")
        #expect(tasks.map(\.recurrenceEndCount) == [7, 7, 7])
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
