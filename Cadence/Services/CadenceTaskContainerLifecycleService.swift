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

    // `reconciler` is an Optional defaulting to `nil` rather than `= .default`, and the reason is a
    // compiler rule rather than a preference: a default argument *expression* is evaluated in a
    // `nonisolated` context even when the enclosing declaration is main-actor isolated — including
    // when the function carries an explicit `@MainActor`, which was tried — so spelling it
    // `= .default` fails with "main actor-isolated static property 'default' can not be referenced
    // from a nonisolated context", once per entry point. `nil` is the isolation-free way to say
    // "whatever the app would normally do"; `settle` resolves it.

    static func completeRemainingActiveTasks(
        in area: Area,
        includingChildProjects: Bool,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        settle(
            remainingActiveTasks(in: area, includingChildProjects: includingChildProjects),
            as: .done,
            in: context,
            reconciler: reconciler
        )
    }

    static func cancelRemainingActiveTasks(
        in area: Area,
        includingChildProjects: Bool,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        settle(
            remainingActiveTasks(in: area, includingChildProjects: includingChildProjects),
            as: .cancelled,
            in: context,
            reconciler: reconciler
        )
    }

    static func completeRemainingActiveTasks(
        in project: Project,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        settle(remainingActiveTasks(in: project), as: .done, in: context, reconciler: reconciler)
    }

    static func cancelRemainingActiveTasks(
        in project: Project,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        settle(remainingActiveTasks(in: project), as: .cancelled, in: context, reconciler: reconciler)
    }

    static func completeRemainingActiveTasks(
        in section: TaskSectionConfig,
        area: Area?,
        project: Project?,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        settle(
            remainingActiveTasks(in: section, area: area, project: project),
            as: .done,
            in: context,
            reconciler: reconciler
        )
    }

    static func cancelRemainingActiveTasks(
        in section: TaskSectionConfig,
        area: Area?,
        project: Project?,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        settle(
            remainingActiveTasks(in: section, area: area, project: project),
            as: .cancelled,
            in: context,
            reconciler: reconciler
        )
    }

    // MARK: Winding down by outcome

    // The pair above says *which* settle by which function is called, so a call site that picks the
    // wrong one is a decision made in a view body and pinned by nothing. These two take the
    // decision as a value instead, so "archiving cancels, completing marks done" is an assertion a
    // test can make about `CadenceWindDownOutcome` rather than a branch a source scan has to go
    // looking for. `docs/TODO.md` T-161.

    static func settleRemainingActiveTasks(
        in area: Area,
        includingChildProjects: Bool,
        outcome: CadenceWindDownOutcome,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        switch outcome {
        case .done:
            completeRemainingActiveTasks(
                in: area,
                includingChildProjects: includingChildProjects,
                in: context,
                reconciler: reconciler
            )
        case .cancelled:
            cancelRemainingActiveTasks(
                in: area,
                includingChildProjects: includingChildProjects,
                in: context,
                reconciler: reconciler
            )
        }
    }

    static func settleRemainingActiveTasks(
        in project: Project,
        outcome: CadenceWindDownOutcome,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil
    ) {
        switch outcome {
        case .done:
            completeRemainingActiveTasks(in: project, in: context, reconciler: reconciler)
        case .cancelled:
            cancelRemainingActiveTasks(in: project, in: context, reconciler: reconciler)
        }
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
    ///
    /// **The `context` is finally load-bearing (T-241).** Every entry point took one and none of
    /// them read it, because `settleWithoutAdvancingSeries` mutates the models in place. T-212 left
    /// the parameters in anyway, on the grounds that the missing notification reconcile would want
    /// them back — this is that. A settled task's pending "starting now" / "due today" nudges are
    /// cleared the same way `TaskWorkflowService.markDone` clears a single task's, so completing or
    /// archiving a list stops leaving live notifications for work nobody is going to do until the
    /// next `scenePhase` checkpoint happens to sweep them.
    ///
    /// Nothing settled means nothing to reconcile: the reconcile is a diff against a desired set
    /// derived from the store, so an unchanged store diffs to a no-op, and archiving an
    /// already-empty list should not cost two full-store fetches to discover that.
    private static func settle(
        _ tasks: [AppTask],
        as status: TaskStatus,
        in context: ModelContext,
        reconciler: CadenceWindDownReconciler?
    ) {
        let now = Date()
        for task in tasks {
            CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries(task, as: status, now: now)
        }
        guard !tasks.isEmpty else { return }
        (reconciler ?? .default).run(in: context)
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

/// Which way a wind-down settles the work it finds.
///
/// One dimension, because the service already has both spellings: archiving a container cancels
/// what is left in it, completing one marks it done. The distinction is only *said* here — the
/// settle itself is `completeRemainingActiveTasks` / `cancelRemainingActiveTasks`, and this exists
/// so a confirmation can name the outcome without a second copy of the counting.
enum CadenceWindDownOutcome: String, Sendable, CaseIterable {
    case cancelled
    case done

    /// Reads after "N open tasks will be …".
    var settledPhrase: String {
        switch self {
        case .cancelled: return "cancelled"
        case .done: return "marked done"
        }
    }
}

/// The one thing a bulk wind-down does outside SwiftData, made injectable so a test can watch it
/// without a notification subsystem being involved.
///
/// **Why a seam at all, for a one-line call.** `HabitNotificationReconcileSupport.scheduleReconcile`
/// spawns an unstructured `Task` that fetches the whole store twice and calls into
/// `NotificationManager.shared`. Calling it unconditionally from `settle` would have handed the
/// eighteen existing wind-down unit tests a stray async fetch apiece, running after the test body
/// returned, against a `ModelContext` the test had finished with — and `NotificationManager` is a
/// `@MainActor` singleton, so the tests would be reaching into the notification layer to be told
/// "not under test" rather than never reaching it at all. That is why T-212 and T-215 both declined
/// to add the line.
///
/// The alternatives, and why not:
/// - *A global `onDidSettle` hook the app installs at launch.* Correctness would depend on remote
///   wiring invisible from here, which is precisely the defect T-241 describes; and a mutable
///   static shared by a parallel test suite is a race.
/// - *An optional closure every call site passes explicitly.* Same failure: the next wind-down
///   surface that forgets it silently reintroduces the bug. The default has to be the live
///   behaviour.
/// - *Making `scheduleReconcile` itself inert under `XCTestConfigurationFilePath`.* It would work
///   and it changes no behaviour today, but it leaves the wiring provable only by a source-text
///   scan — the weak form this repo warns about — because with the call inert there is nothing a
///   behavioural test can observe. Injection makes "the settle reconciles" an assertion about a
///   value the test supplied.
///
/// So: the default is live in the app and inert in a test host, and a test that cares injects its
/// own. The environment predicate is `NotificationManager.isTestEnvironment` rather than a third
/// hand-rolled copy of the question. `PersistenceController.isRunningTests` asks it too and is the
/// established spelling, but it is `private` and cannot be reused; `NotificationManager`'s is the
/// same two XCTest keys plus the SwiftUI Preview host and `CadenceUITestSupport.isEnabled`, and it
/// is already the predicate the notification layer itself obeys — which is the point, since a
/// reconcile that would early-return anyway is exactly the work worth not queuing.
@MainActor
struct CadenceWindDownReconciler {
    /// `false` for a reconciler that deliberately does nothing.
    ///
    /// Exposed only so `default` can be pinned: without it, "simplify" this back to an
    /// unconditional `.live` and every wind-down test starts spawning store fetches into the
    /// notification layer again, with nothing red to say so.
    let isLive: Bool

    private let body: (ModelContext) -> Void

    init(isLive: Bool = true, _ body: @escaping (ModelContext) -> Void) {
        self.isLive = isLive
        self.body = body
    }

    func run(in context: ModelContext) {
        body(context)
    }

    /// The same fast-path reconcile `TaskWorkflowService.markDone` / `markCancelled` / `markTodo`
    /// run after a single-task transition.
    static let live = Self { context in
        HabitNotificationReconcileSupport.scheduleReconcile(in: context)
    }

    /// Settles the tasks and stops there.
    static let inert = Self(isLive: false) { _ in }

    /// What the six wind-down entry points fall back to when handed `nil`.
    static var `default`: Self {
        NotificationManager.isTestEnvironment ? .inert : .live
    }
}

/// What winding a container down is about to settle, counted before the fact.
///
/// **Why a count at all.** Archiving is advertised as reversible — an archived list sits in the
/// Archived section one tap from Restore, an archived kanban column comes back from the list
/// editor — and the settle it performs is *not*: restoring the container leaves every task it
/// cancelled cancelled, and reopening a completed column leaves every task it finished finished.
/// That asymmetry is the whole reason this type exists. On macOS the actions are buried in an edit
/// sheet's footer or a column popover you had to open; on iOS they sit on a row swipe, a
/// context-menu item and a list-editor row, so the number has to be shown before the gesture is
/// honoured.
///
/// **The count is the settle's own array**, via `TaskContainerLifecycleService.remainingActiveTasks`
/// — including the things a naive count gets wrong: an area rolls up its child projects, because
/// that is what `cancelRemainingActiveTasks(in:includingChildProjects:)` walks; a task filed under
/// both an area and one of its projects is counted once; and a column's members are matched on
/// `resolvedSectionName`, so the tasks that never named a section are in the Default column's
/// number rather than in nobody's.
///
/// It lives beside the service rather than in `Shared/CadenceListDeletionSummary.swift` because
/// that file is about a cascade that removes rows; this is about work that stays and changes
/// status. It lives *outside* `Cadence/iOS/` because that folder is inside `#if os(iOS)` and
/// invisible to the macOS-built `CadenceTests` — the same reason `CadenceCompactTab` and
/// `CadenceDetailPanelPresentation` are where they are.
///
/// It was `CadenceListArchiveSummary` until T-247, when a kanban column needed exactly it with one
/// word changed. A second struct would have been a near-copy of four members; the outcome is the
/// dimension that was implicit in the name.
struct CadenceContainerWindDownSummary: Equatable, Sendable {
    var openTasks = 0
    var outcome: CadenceWindDownOutcome = .cancelled

    var isEmpty: Bool {
        openTasks == 0
    }

    /// Winding down a container with nothing open in it flips one flag and is one tap from
    /// reversing, so it asks nothing — friction on a no-op is friction people learn to dismiss
    /// without reading, the same argument `iOSListDeleteConfirmationSheet` makes against a typed
    /// phrase. Winding down a container with open work in it settles that work irreversibly, so it
    /// asks.
    var requiresConfirmation: Bool {
        !isEmpty
    }

    /// `nil` when there is nothing to say, rather than "0 open tasks will be cancelled" — the same
    /// rule `CadenceListDeletionSummary.lostItemLines` follows about zeroes.
    var settledLine: String? {
        guard openTasks > 0 else { return nil }
        return "\(openTasks) open \(openTasks == 1 ? "task" : "tasks") will be \(outcome.settledPhrase)"
    }

    /// An area, in whichever direction it is being wound down.
    ///
    /// The `outcome` is a required argument rather than a defaulted `.cancelled`, and the reason is
    /// the one the column factory already had: the walk is identical in both directions and only
    /// the sentence over it changes, so a default would let a completion quietly promise
    /// "cancelled" — the failure mode this whole type exists to prevent, wearing the right number.
    /// It was `.cancelled` unconditionally until T-214, when iOS gained the Complete action macOS
    /// has had all along.
    static func forArea(_ area: Area, outcome: CadenceWindDownOutcome) -> Self {
        Self(
            openTasks: TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true).count,
            outcome: outcome
        )
    }

    static func forProject(_ project: Project, outcome: CadenceWindDownOutcome) -> Self {
        Self(
            openTasks: TaskContainerLifecycleService.remainingActiveTasks(in: project).count,
            outcome: outcome
        )
    }

    /// A kanban column, in whichever direction it is being wound down.
    ///
    /// The `section` handed in must be the one **on the model**, not a draft of it: the walk
    /// matches `AppTask.resolvedSectionName` against `section.name`, so counting against a name the
    /// user has typed but not saved would count a column that no task points at yet.
    static func forColumn(
        _ section: TaskSectionConfig,
        area: Area?,
        project: Project?,
        outcome: CadenceWindDownOutcome
    ) -> Self {
        Self(
            openTasks: TaskContainerLifecycleService.remainingActiveTasks(
                in: section,
                area: area,
                project: project
            ).count,
            outcome: outcome
        )
    }
}
