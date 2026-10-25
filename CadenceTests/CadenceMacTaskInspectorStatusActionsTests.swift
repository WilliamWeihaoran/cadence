// macOS only: `TaskDetailActionsSection` is a macOS view.
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
        try TaskDetailActionsSection.apply(.cancelled, to: task, in: context)
        #expect(task.status == .cancelled)
        #expect(context.hasChanges == false, "the change was committed")
        try TaskDetailActionsSection.apply(.cancelled, to: task, in: context)
        #expect(task.status == .todo, "Restore is Cancel's undo")
    }

    /// A row the launch pass has not reached yet is still stored `.inprogress`. The inspector can
    /// still cancel it — the status is unwritable, not untouchable — so the task is seeded through
    /// the raw value rather than through a control that no longer exists.
    @Test func cancellingAnInProgressTaskCancelsIt() throws {
        let (context, task) = try makeTask()
        task.statusRaw = TaskStatus.inProgress.rawValue
        try TaskDetailActionsSection.apply(.cancelled, to: task, in: context)
        #expect(task.status == .cancelled)
    }

    @Test func aRefusedCommitPutsTheStatusBack() throws {
        let (context, task) = try makeTask()
        #expect(throws: (any Error).self) {
            try TaskDetailActionsSection.apply(.cancelled, to: task, in: context) { _ in
                throw CommitRefused()
            }
        }
        #expect(task.status == .todo)
    }

    /// The full inspector offers the shared set, drawn with the shared copy and glyphs.
    @Test func theInspectorHostsTheSharedStatusActionSet() throws {
        let section = try Self.actionsSection()
        #expect(section.contains("ForEach(CadenceTaskInspectorSupport.StatusAction.allCases"))
        #expect(section.contains("action.title(for: task.status)"))
        #expect(section.contains("action.systemImage(for: task.status)"))
        let host = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelComponents.swift")
        )
        #expect(host.contains("TaskDetailActionsSection(task: task, offersUnschedule: false, offersDelete: false, offersStatusActions: true)"))
    }

    /// **[[T-6231]]: Cancel/Restore is an icon button in the actions row, not a full-width row of
    /// its own.** After [[T-5015]] (b) the old status row drew one lone "Cancel" stretched across
    /// the inspector under "Mark done" — the weight this app reserves for the action a panel is
    /// for. The rule pinned here is the row's own: "Mark done" is the one control that takes the
    /// width, and the status action is drawn by the same square `iconButton` as Unschedule and
    /// Delete. A relation (one wide control, the status button routed through the square helper),
    /// never a point figure.
    @Test func theStatusActionIsASquareIconButtonBesideTheOneWidePrimary() throws {
        let section = try Self.actionsSection()
        #expect(
            CadenceSourceScan.matchCount(#"\.frame\(maxWidth: \.infinity\)"#, in: section) == 1,
            "a second control in the inspector's actions row takes the full width again (T-6231)"
        )
        let status = try #require(
            CadenceSourceScan.functionBody(named: "statusActionButton", in: section),
            "the status action no longer has its own builder this scan can scope to"
        )
        #expect(status.contains("iconButton("), "the status action is no longer drawn as the row's square icon button (T-6231)")
        let square = try #require(CadenceSourceScan.functionBody(named: "iconButton", in: section))
        #expect(square.contains(".frame(width: Self.controlHeight, height: Self.controlHeight)"))
        // The old standalone row is gone rather than left beside the new button.
        let host = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelComponents.swift")
        #expect(!host.contains("TaskInspectorStatusActionsRow("))
    }

    private static func actionsSection() throws -> String {
        let support = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        )
        return try #require(
            CadenceSourceScan.declarationBody("struct TaskDetailActionsSection: View", in: support),
            "TaskDetailActionsSection no longer reads as a declaration this scan can scope to"
        )
    }
}
#endif
