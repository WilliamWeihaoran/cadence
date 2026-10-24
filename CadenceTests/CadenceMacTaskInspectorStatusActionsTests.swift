// macOS only: `TaskInspectorStatusActionsRow` is a macOS view.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-5015]] (a): the Mac inspector renders the shared `StatusAction` set iOS renders, and each
/// button writes its action's target and commits it.
///
/// **Start/Stop was half of that set and went in (b)**, hours after (a) landed and by the owner's
/// decision — so `startThenStopRoundTripsThroughInProgress` is gone from here rather than
/// repaired. What the suite still owns is the mechanism (apply the action's target, commit, put
/// back on refusal) and the host, both of which outlived the case; `.inProgress` now appears only
/// as a status the row may be shown *over*, never one it can write.
@MainActor
struct CadenceMacTaskInspectorStatusActionsTests {
    private struct CommitRefused: Error {}

    private func makeTask() throws -> (ModelContext, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Status")
        context.insert(task)
        try context.save()
        return (context, task)
    }

    @Test func cancelThenRestoreRoundTripsThroughCancelled() throws {
        let (context, task) = try makeTask()
        try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context)
        #expect(task.status == .cancelled)
        #expect(context.hasChanges == false, "the change was committed")
        try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context)
        #expect(task.status == .todo, "Restore is Cancel's undo")
    }

    /// A row the launch pass has not reached yet is still stored `.inprogress`. The inspector can
    /// still cancel it — the status is unwritable, not untouchable — so the task is seeded through
    /// the raw value rather than through a control that no longer exists.
    @Test func cancellingAnInProgressTaskCancelsIt() throws {
        let (context, task) = try makeTask()
        task.statusRaw = TaskStatus.inProgress.rawValue
        try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context)
        #expect(task.status == .cancelled)
    }

    @Test func aRefusedCommitPutsTheStatusBack() throws {
        let (context, task) = try makeTask()
        #expect(throws: (any Error).self) {
            try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context) { _ in
                throw CommitRefused()
            }
        }
        #expect(task.status == .todo)
    }

    /// The row draws the whole shared set with the shared copy, and the full inspector hosts it.
    @Test func theInspectorHostsTheSharedStatusActionSet() throws {
        let row = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskInspectorStatusActionsRow.swift")
        #expect(row.contains("ForEach(CadenceTaskInspectorSupport.StatusAction.allCases"))
        #expect(row.contains("action.title(for: task.status)"))
        #expect(row.contains("action.systemImage(for: task.status)"))
        let host = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelComponents.swift")
        #expect(host.contains("TaskInspectorStatusActionsRow(task: task)"))
    }
}
#endif
