import Foundation
import SwiftData

/// **The launch pass that takes In Progress out of the store without stranding the rows that are
/// in it ([[T-5015]] (b), owner decision 2026-10-24).**
///
/// The owner removed In Progress everywhere — every writer and every render site. The hazard in
/// doing that is not the controls; it is the **rows**. `TaskEmbedFieldEditorPopover`'s own comment
/// said so before anything was written: its Start button was the last macOS writer of
/// `.inProgress`, and "dropping it would strand every task already in that state" — a task no
/// control can leave, on no surface that will admit it is there. That sentence is the reason the
/// question went to the owner rather than being settled by an agent, and **this pass is the
/// answer to it**: the writers go, and the rows they wrote come back to `.todo`.
///
/// **`TaskStatus.inProgress` stays in the enum, and this pass is why it must.** `"inprogress"` is a
/// *persisted raw value*. A store written by any shipped build can hold it, and so can a record
/// arriving from CloudKit or an archive; removing the case would make those rows fail to decode,
/// which is a data-loss bug dressed as a cleanup. The case therefore stays legal to read forever,
/// and is simply never written and never drawn. Nothing here deletes a row or touches a column.
///
/// **What it promises, and what `CadenceInProgressStatusRetirementTests` asserts:**
///
/// - every `.inProgress` task ends `.todo`;
/// - **no other status is touched** — `.todo`, `.done` and `.cancelled` all survive unchanged,
///   which is the half that matters most, because the honest failure mode of a status sweep is
///   over-reach rather than under-reach;
/// - `completedAt` is cleared on exactly the rows it rewrites, and on no others. `.inProgress` is
///   an *open* status, so a row in it should already carry no timestamp; this writes through
///   `CadenceTaskRecurrenceWorkflowSupport.markTodo`, the one helper that states the
///   open-status-carries-no-timestamp invariant, rather than assigning `status` raw — a raw
///   assignment would leave a stray `completedAt` on any row an older build had stamped, and
///   `normalizeCompletionState` would then have two passes disagreeing about it.
/// - nothing else on the task moves. Not the do date, not the estimate, not the recurrence rule.
///
/// **Where it runs, and why there: a startup maintenance pass, not a schema migration and not a
/// latched one-shot.**
///
/// - *Not a schema migration.* This project has no `SchemaMigrationPlan` — `CadenceStoreSupport`,
///   `CadenceDataExportService` and `Note` all say so in terms — and there is nothing here for one
///   to do: no entity, property or raw value changes. This is a **data rewrite inside an unchanged
///   schema**, which is the shape `PursuitToGoalMigration` and `TaskBundleRetirement` already have.
/// - *Not latched on a `UserDefaults` flag,* and this is the load-bearing decision rather than a
///   convenience. A flag would make the pass run once per *device* when the requirement is once per
///   **store state**, and `.inprogress` rows can arrive long after the first launch: from CloudKit
///   (another device still on a build that writes them), from an imported archive, or from a
///   pending restore that `PersistenceController.init` applies *before* this ever runs.
///   `TaskBundleRetirement` records the same argument for the same reason. A latched pass would
///   strand exactly the rows this exists to rescue — the original hazard, reintroduced by the
///   mechanism meant to fix it.
/// - *Idempotent and self-guarding instead.* The guard is the fetch: a `#Predicate` on the raw
///   value, which after the first pass matches nothing, so the pass is a no-op read on every later
///   launch and **the store is written once per arrival, never twice for the same row**. That is
///   what "do not run it more than once per store" asks for, and a guard delivers it where a flag
///   only claims it.
///
/// **It fetches on the raw string, not on `.inProgress`.** SwiftData compiles the `#Predicate` down
/// to a store query over the persisted column, so the comparison has to be the persisted
/// representation; and writing it this way means the pass keeps working if the Swift case is ever
/// renamed, since `"inprogress"` is the thing on disk and the thing that must be found.
nonisolated enum CadenceInProgressStatusRetirement {

    /// The persisted raw value this pass hunts, spelled once. `TaskStatus.inProgress.rawValue`
    /// rather than a literal so a rename of the case cannot silently stop the fetch matching.
    static let retiredRawValue = TaskStatus.inProgress.rawValue

    /// Whether a status still earns a drawn mark of its own on a surface that renders one.
    ///
    /// `.todo` never did and `.inProgress` no longer does, so they answer alike. It lives here
    /// rather than in the one view that asks it because the retirement and the predicate are the
    /// same decision: the drawing rule and the store rule must not be able to drift apart, and a
    /// surface that reads a *snapshot* of `statusRaw` (the markdown task embed does) can be handed
    /// "inprogress" after the store itself no longer holds any.
    static func drawsStatusChip(_ status: TaskStatus) -> Bool {
        switch status {
        case .todo, .inProgress: return false
        case .done, .cancelled: return true
        }
    }

    /// Every task still stored as In Progress. Separate from the walk so a caller — and a test —
    /// can ask what the pass would touch without touching it.
    static func retiredTasks(in context: ModelContext) throws -> [AppTask] {
        let raw = retiredRawValue
        return try context.fetch(
            FetchDescriptor<AppTask>(predicate: #Predicate<AppTask> { $0.statusRaw == raw })
        )
    }

    /// The walk: every stored In Progress task to `.todo`. Returns how many it rewrote.
    ///
    /// `nonisolated` and commit-free, so the `CadenceMCPServer` side of the module and a test can
    /// both call it directly; `runIfNeeded` below is the launch pass that wraps it in a save.
    ///
    /// `capturing` is handed each row **before** it is rewritten, which is how `runIfNeeded` builds
    /// the undo a refused save needs. Same shape as `TaskBundleRetirement.retireAllBundles`, and
    /// for the same reason recorded there: this pass rewrites fields on rows that *survive*, and
    /// `rollback()`'s reach onto an already-materialised reference is the clause this repository's
    /// two Xcode majors answer differently, so the restore is explicit rather than the framework's.
    @discardableResult
    static func retireAll(
        in context: ModelContext,
        capturing capture: (AppTask) -> Void = { _ in }
    ) throws -> Int {
        let stranded = try retiredTasks(in: context)
        for task in stranded {
            capture(task)
            CadenceTaskRecurrenceWorkflowSupport.markTodo(task)
        }
        return stranded.count
    }

    /// The launch pass. `nothingToDo` on a store holding none, which after the first pass is every
    /// launch; `couldNotRead` for a fetch or a save that refused, kept apart from `nothingToDo` for
    /// the reason [[T-1402]] drew the distinction — a launch that *could not* retire the rows must
    /// not read like a launch with no rows to retire.
    static func runIfNeeded(
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> CadenceMaintenancePassOutcome {
        // The two fields `markTodo` writes, per row, so a refused save puts back exactly what this
        // pass changed and nothing else.
        var restore: [(task: AppTask, status: TaskStatus, completedAt: Date?)] = []
        let retired: Int
        do {
            retired = try retireAll(in: modelContext) { task in
                restore.append((task, task.status, task.completedAt))
            }
        } catch {
            return .couldNotRead
        }
        guard retired > 0 else { return .nothingToDo }

        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, commit: commit) {
                for row in restore {
                    row.task.status = row.status
                    row.task.completedAt = row.completedAt
                }
            }
        } catch {
            return .couldNotRead
        }
        return .changed
    }
}
