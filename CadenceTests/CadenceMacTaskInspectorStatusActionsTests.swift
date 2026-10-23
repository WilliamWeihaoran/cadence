// macOS only: `TaskInspectorStatusActionsRow` is a macOS view.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-5015]] (a): the Mac inspector renders the shared `StatusAction` set iOS renders, and each
/// button writes its action's target and commits it.
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

    @Test func startThenStopRoundTripsThroughInProgress() throws {
        let (context, task) = try makeTask()
        try TaskInspectorStatusActionsRow.apply(.inProgress, to: task, in: context)
        #expect(task.status == .inProgress)
        #expect(context.hasChanges == false, "the change was committed")
        try TaskInspectorStatusActionsRow.apply(.inProgress, to: task, in: context)
        #expect(task.status == .todo, "Stop is Start's undo")
    }

    @Test func cancelThenRestoreRoundTripsThroughCancelled() throws {
        let (context, task) = try makeTask()
        try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context)
        #expect(task.status == .cancelled)
        #expect(context.hasChanges == false, "the change was committed")
        try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context)
        #expect(task.status == .todo, "Restore is Cancel's undo")
    }

    @Test func cancellingAnInProgressTaskCancelsIt() throws {
        let (context, task) = try makeTask()
        try TaskInspectorStatusActionsRow.apply(.inProgress, to: task, in: context)
        try TaskInspectorStatusActionsRow.apply(.cancelled, to: task, in: context)
        #expect(task.status == .cancelled)
    }

    @Test func aRefusedCommitPutsTheStatusBack() throws {
        let (context, task) = try makeTask()
        #expect(throws: (any Error).self) {
            try TaskInspectorStatusActionsRow.apply(.inProgress, to: task, in: context) { _ in
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
