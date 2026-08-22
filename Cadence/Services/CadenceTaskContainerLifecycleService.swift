import Foundation
import SwiftData

/// Winding a whole container down: an area, a project, or one kanban column, settling whatever is
/// still open inside it.
///
/// **Cross-platform, and always could have been.** This lived inside `TaskWorkflowService.swift`'s
/// `#if os(macOS)` until T-215 while importing nothing platform-specific — SwiftData models, a
/// `ModelContext`, a `Foundation.Date` and `CadenceTaskRecurrenceWorkflowSupport`, all of which iOS
/// compiles. The guard is what produced the divergence the ticket names: macOS's archive cancelled
/// a list's remaining active tasks and iOS's archive only flipped `status`, so the same list wound
/// down to two different sets of open work depending on which device the swipe happened on. Same
/// shape as `RemindersManager`, `PrivacyDataResetService` and `ListDeleteHelpers`, whose tombstones
/// are in `Cadence/macOS/Services/`; the file name carries the `Cadence` prefix and the type does
/// not, for the same `.stringsdata` reason those three do.
///
/// The prefixed file lives in `Services/` rather than `Shared/` because it is a persistence
/// mutation, not presentation — and because `Shared/CadenceTaskRecurrenceWorkflowSupport.swift`,
/// which it calls, compiles into `CadenceWidgets` and `CadenceMCPServer` as well, and a bulk
/// container wind-down has no business in either.
enum TaskContainerLifecycleService {

    // MARK: - What a wind-down would settle

    /// The tasks a wind-down of `area` would settle — deduped, and filtered by the same predicate
    /// the settle itself uses.
    ///
    /// Public because a confirmation has to count them *before the fact*, and counting them any
    /// other way is exactly how a confirmation comes to over-promise: this is the same array the
    /// two `…RemainingActiveTasks` entry points hand to the settle, not a second walk that happens
    /// to agree today. `CadenceListDeletionSummary`'s doc comment makes the same argument about the
    /// delete cascade.
    static func remainingActiveTasks(in area: Area, includingChildProjects: Bool) -> [AppTask] {
        unsettled(tasks(in: area, includingChildProjects: includingChildProjects))
    }

    static func remainingActiveTasks(in project: Project) -> [AppTask] {
        unsettled(project.tasks ?? [])
    }

    static func remainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?) -> [AppTask] {
        unsettled(tasks(in: section, area: area, project: project))
    }

    // MARK: - Winding down

    static func completeRemainingActiveTasks(in area: Area, includingChildProjects: Bool, in context: ModelContext) {
        settle(remainingActiveTasks(in: area, includingChildProjects: includingChildProjects), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in area: Area, includingChildProjects: Bool, in context: ModelContext) {
        settle(remainingActiveTasks(in: area, includingChildProjects: includingChildProjects), as: .cancelled, in: context)
    }

    static func completeRemainingActiveTasks(in project: Project, in context: ModelContext) {
        settle(remainingActiveTasks(in: project), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in project: Project, in context: ModelContext) {
        settle(remainingActiveTasks(in: project), as: .cancelled, in: context)
    }

    static func completeRemainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?, in context: ModelContext) {
        settle(remainingActiveTasks(in: section, area: area, project: project), as: .done, in: context)
    }

    static func cancelRemainingActiveTasks(in section: TaskSectionConfig, area: Area?, project: Project?, in context: ModelContext) {
        settle(remainingActiveTasks(in: section, area: area, project: project), as: .cancelled, in: context)
    }

    /// Settling a whole container is **not** the single-task transition, and must not become it.
    /// `markDone` / `markCancelled` spawn the next recurrence occurrence into the same area,
    /// project and section, so routing this through either would refill the list or column that
    /// was just completed or archived (`docs/TODO.md` T-213, T-214). It routes through
    /// `settleWithoutAdvancingSeries` instead, which is that decision written down once.
    ///
    /// What was actually wrong here was the timestamp: `.cancelled` hand-wrote
    /// `completedAt = nil`, so archiving a list or a kanban column produced untimestamped
    /// cancellations after T-202 had made a cancellation a timestamped event everywhere else —
    /// and `completedAt` is the only ground Today's Completed section has for settled work whose
    /// dates are empty or past, the *only* one on macOS. One `Date()` for the batch, because a
    /// single click settling twelve tasks settled them all at once.
    private static func settle(_ tasks: [AppTask], as status: TaskStatus, in context: ModelContext) {
        let now = Date()
        for task in tasks {
            CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: status, now: now)
        }
    }

    /// Reads **status alone**, which is the spelling that stayed correct once a cancelled task
    /// began carrying a `completedAt`: a guard that also asked `completedAt == nil` would re-stamp
    /// last week's cancellation to today and drag it into Today's Completed section.
    private static func unsettled(_ tasks: [AppTask]) -> [AppTask] {
        unique(tasks).filter { !$0.isDone && !$0.isCancelled }
    }

    private static func tasks(in area: Area, includingChildProjects: Bool) -> [AppTask] {
        var result = area.tasks ?? []
        if includingChildProjects {
            for project in area.projects ?? [] {
                result.append(contentsOf: project.tasks ?? [])
            }
        }
        return result
    }

    private static func tasks(in section: TaskSectionConfig, area: Area?, project: Project?) -> [AppTask] {
        let sourceTasks = area?.tasks ?? project?.tasks ?? []
        return sourceTasks.filter {
            $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
        }
    }

    private static func unique(_ tasks: [AppTask]) -> [AppTask] {
        var seen = Set<UUID>()
        return tasks.filter { seen.insert($0.id).inserted }
    }
}

/// What archiving a list is about to settle, counted before the fact.
///
/// **Why a count at all.** Archiving is advertised as reversible — an archived list sits in the
/// Archived section one tap from Restore — and the cancellation it performs is *not*: restoring the
/// list leaves every task it cancelled cancelled. That asymmetry is the whole reason this type
/// exists. On macOS the action is buried in the edit sheet's footer, which is deliberate enough on
/// its own; on iOS it is a row swipe and a context-menu item, so the number has to be shown before
/// the swipe is honoured.
///
/// **The count is the settle's own array**, via `TaskContainerLifecycleService.remainingActiveTasks`
/// — including the two things a naive count gets wrong: an area rolls up its child projects,
/// because that is what `cancelRemainingActiveTasks(in:includingChildProjects:)` walks, and a task
/// filed under both an area and one of its projects is counted once.
///
/// It lives beside the service rather than in `Shared/CadenceListDeletionSummary.swift` because
/// that file is about a cascade that removes rows; this is about work that stays and changes
/// status. It lives *outside* `Cadence/iOS/` because that folder is inside `#if os(iOS)` and
/// invisible to the macOS-built `CadenceTests` — the same reason `CadenceCompactTab` and
/// `CadenceDetailPanelPresentation` are where they are.
struct CadenceListArchiveSummary: Equatable, Sendable {
    var openTasks = 0

    var isEmpty: Bool {
        openTasks == 0
    }

    /// Archiving a list with nothing open in it flips one flag and is one tap from Restore, so it
    /// asks nothing — friction on a no-op is friction people learn to dismiss without reading, the
    /// same argument `iOSListDeleteConfirmationSheet` makes against a typed phrase. Archiving a
    /// list with open work in it cancels that work irreversibly, so it asks.
    var requiresConfirmation: Bool {
        !isEmpty
    }

    /// `nil` when there is nothing to say, rather than "0 open tasks will be cancelled" — the same
    /// rule `CadenceListDeletionSummary.lostItemLines` follows about zeroes.
    var settledLine: String? {
        guard openTasks > 0 else { return nil }
        return "\(openTasks) open \(openTasks == 1 ? "task" : "tasks") will be cancelled"
    }

    static func forArea(_ area: Area) -> Self {
        Self(openTasks: TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true).count)
    }

    static func forProject(_ project: Project) -> Self {
        Self(openTasks: TaskContainerLifecycleService.remainingActiveTasks(in: project).count)
    }
}
