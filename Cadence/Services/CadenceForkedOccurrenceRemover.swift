import Foundation
import SwiftData

/// The app's half of T-622's forked-occurrence collapse: the removal, and only the removal.
///
/// **Why this is a separate file rather than four lines inside the repair pass.**
/// `DataIntegrityRepairService.swift` is a member of `CadenceMCPServer`'s explicit Sources phase,
/// and `CadenceTaskMutationSupport` and `NotificationManager` are not. A reference from there to
/// either leaves `-scheme Cadence` green — the app target reaches `Cadence/` by folder membership
/// and compiles everything under it — while `-scheme CadenceMCPServer`, which no scheme here
/// builds, stops compiling. That is `aaa0064` exactly, it shipped once and stayed broken for four
/// commits, and `CadenceTargetSourceMembershipTests` exists to catch it. This file lives under
/// `Cadence/` so the app compiles it and the MCP target's explicit list does not name it.
///
/// It is deliberately the *only* thing here. The rule — which row survives a fork, and which of
/// the others may go — is `CadenceTaskRecurrenceWorkflowSupport`'s, beside the spawn that writes
/// the occurrence slot; the decision to run at all, and the report counter, are
/// `DataIntegrityRepairService`'s. Nothing about the collapse is decided in this file.
nonisolated enum CadenceForkedOccurrenceRemover {

    /// Deletes the rows the collapse chose, and cancels the reminders they carried.
    ///
    /// Severing goes through `CadenceTaskMutationSupport.detachRelationships`, and the copied
    /// subtasks through `deleteSubtask`, rather than a second spelling of either: a spawned
    /// successor inherits `area`, `project`, `context`, `goal` and `tags` from its predecessor, and
    /// leaving a deleted row in those inverse arrays is the T-296 window where a surface
    /// re-rendering before the next flush draws a gone object.
    ///
    /// Bundles are deliberately untouched: a removable row has `bundle == nil` by
    /// `isUntouchedClone`, so no bundle is left holding a stale member.
    ///
    /// Deliberately does **not** save. `DataIntegrityRepairService.repairIfNeeded` commits once,
    /// after every pass, when anything changed — so the whole repair is one pending change rather
    /// than a partial one this could commit on its own.
    ///
    /// One cancel for the whole batch rather than one per row, the shape
    /// `ModelContext.deleteContext` uses for the habits a context cascade takes. Without it a
    /// scheduled-start reminder fires for a task that no longer exists, because reconciliation only
    /// converges at the next `scenePhase` transition.
    static let removeAndCancelReminders: CadenceForkedOccurrenceRemoval = { tasks, modelContext in
        var removedIDs: [UUID] = []
        for task in tasks {
            for subtask in task.subtasks ?? [] {
                CadenceTaskMutationSupport.deleteSubtask(subtask, parent: task, modelContext: modelContext)
            }
            CadenceTaskMutationSupport.detachRelationships(for: task)
            removedIDs.append(task.id)
            modelContext.delete(task)
        }
        guard !removedIDs.isEmpty else { return [] }
        let cancelled = removedIDs
        Task { await NotificationManager.shared.cancel(taskIDs: cancelled) }
        return removedIDs
    }
}
