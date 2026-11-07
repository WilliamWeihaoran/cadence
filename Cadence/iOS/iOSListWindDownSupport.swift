#if os(iOS)
import SwiftData
import SwiftUI

/// The two ways a list is wound down, both of which settle the work still open inside it.
///
/// Only the *entering* transitions are here, for the same reason `iOSColumnWindDownAction` has only
/// two cases: restoring an archived list and reopening a completed one settle nothing — they write
/// `status = .active` and stop — so they are plain calls rather than targets this enum could name.
///
/// This file was `iOSListArchiveSupport.swift` and this enum did not exist, because archive was the
/// only wind-down iOS offered (T-215). T-214 is the other half, and it is the *same* machinery with
/// the outcome flipped, which is exactly the extension `CadenceWindDownOutcome` was added for when
/// the kanban column needed both directions (T-247).
enum iOSListWindDownAction {
    case archive
    case complete

    /// Which way the settle goes. Archiving abandons what is left; completing asserts it happened.
    var outcome: CadenceWindDownOutcome {
        switch self {
        case .archive: return .cancelled
        case .complete: return .done
        }
    }

    var verb: String {
        switch self {
        case .archive: return "Archive"
        case .complete: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .archive: return "archivebox"
        case .complete: return "checkmark.circle"
        }
    }

    var filledIcon: String {
        switch self {
        case .archive: return "archivebox.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

/// The one kind of list an iOS wind-down can be about.
///
/// Areas and projects only — a context is not archivable or completable from any iOS surface, and a
/// kanban column is its own target (`iOSColumnWindDownTarget`) because a column is a
/// `TaskSectionConfig` value inside one of these two rather than a model of its own. It carries the
/// model object for the same reason `iOSListDeletionTarget` does: the confirmation has to identify
/// *which* list is going quiet, and the settle itself takes the object.
enum iOSListWindDownList {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id)"
        case .project(let project): return "project-\(project.id)"
        }
    }

    /// Title-cased, because every use is a button title or a sheet title. Deliberately not read off
    /// `CadenceListDeletionKind` — that enum is the delete cascade's vocabulary and its third case
    /// (`context`) is not a thing this action can be about.
    var noun: String {
        switch self {
        case .area: return "Area"
        case .project: return "Project"
        }
    }

    /// The real name, or the same "Untitled …" fallback the delete confirmation uses — a
    /// confirmation with a blank name in it does not say what is about to be wound down.
    ///
    /// **T-512.** The fallback is read off `CadenceTitleNormalization`, not built as
    /// `"Untitled \(noun)"`. Interpolating it produced exactly `defaultAreaName` /
    /// `defaultProjectName` at runtime while being invisible to the shared-constant sweep, whose
    /// harvest drops interpolated literals by construction — so the claim this comment makes about
    /// matching the delete confirmation was true and nothing held it true. It is one switch rather
    /// than a second `untitledName` property beside `noun`, so there is no parallel list of cases
    /// to keep in step.
    var name: String {
        let raw: String
        let untitled: String
        switch self {
        case .area(let area):
            raw = area.name
            untitled = CadenceTitleNormalization.defaultAreaName
        case .project(let project):
            raw = project.name
            untitled = CadenceTitleNormalization.defaultProjectName
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? untitled : raw
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        }
    }

    var colorHex: String {
        switch self {
        case .area(let area): return area.colorHex
        case .project(let project): return project.colorHex
        }
    }

    /// The settle's own array, counted before the fact, in the direction it is about to go — see
    /// `CadenceContainerWindDownSummary`. The `outcome` is a parameter rather than a constant
    /// because the count is the same walk either way and only the sentence over it changes; that is
    /// the whole reason `forArea` / `forProject` gained the argument instead of a second pair of
    /// factories appearing beside them.
    func summary(outcome: CadenceWindDownOutcome) -> CadenceContainerWindDownSummary {
        switch self {
        case .area(let area): return .forArea(area, outcome: outcome)
        case .project(let project): return .forProject(project, outcome: outcome)
        }
    }
}

/// One list about to be wound down, in one direction.
///
/// The same shape as `iOSColumnWindDownTarget`: subject plus action, `Identifiable` on both, so the
/// sheet re-presents when the *direction* changes and not only when the list does.
struct iOSListWindDownTarget: Identifiable {
    let list: iOSListWindDownList
    let action: iOSListWindDownAction

    var id: String {
        "\(list.id)-\(action)"
    }

    var summary: CadenceContainerWindDownSummary {
        list.summary(outcome: action.outcome)
    }

    /// The tasks the settle writes, and so the set a snapshot taken before it must hold: every
    /// task still open in the list, and for an area those of its child projects too
    /// (`includingChildProjects: true`, the walk `settleListWindDown` makes).
    var settledTasks: [AppTask] {
        switch list {
        case .area(let area):
            TaskContainerLifecycleService.remainingActiveTasks(in: area, includingChildProjects: true)
        case .project(let project):
            TaskContainerLifecycleService.remainingActiveTasks(in: project)
        }
    }

    static func area(_ area: Area, _ action: iOSListWindDownAction) -> Self {
        Self(list: .area(area), action: action)
    }

    static func project(_ project: Project, _ action: iOSListWindDownAction) -> Self {
        Self(list: .project(project), action: action)
    }
}

extension ModelContext {
    /// The one place iOS archives or completes a list, and the reason T-215 and T-214 exist.
    ///
    /// Winding a list down is a **settle**, not a status flip: macOS has cancelled a list's
    /// remaining active tasks on archive and marked them done on completion since long before this
    /// file, through exactly this service, while iOS wrote `status = .archived` and nothing else and
    /// offered no completion at all — so the same list wound down to two different sets of open work
    /// depending on which device the gesture happened on, and the Mac's All Tasks kept surfacing
    /// tasks the phone had "archived".
    ///
    /// `includingChildProjects: true` matches `EditAreaSheet.apply(_:)` on both branches. An area's
    /// child projects keep their own `status`, so their tasks are still reachable from All Tasks
    /// after the parent is filed away — which is precisely why the wind-down has to reach them.
    ///
    /// Neither branch may be rerouted through `markDone` / `markCancelled` /
    /// `applyStatusCompletion`: those advance the recurrence series, and the successor inherits
    /// `area`, `project` and `sectionName`, so a completed list would immediately refill itself with
    /// fresh open work. `TaskContainerLifecycleService` settles through
    /// `settleWithoutAdvancingSeries` instead — that is the invariant T-212 and T-213 record and the
    /// one thing a new wind-down surface is most likely to get wrong.
    ///
    /// **Committed through the spine and reported, as macOS's `EditAreaSheet` / `EditProjectSheet`
    /// lifecycle rows are ([[T-11614]] group (1)).** Every write it reaches is an in-place field
    /// edit — a `status`, and `settleWithoutAdvancingSeries`'s `status`/`completedAt` pair, so no
    /// successor is inserted — which is why this used to be a `try? save()` the rule allowed
    /// ([[T-1301]]). But the confirmation sheet closing and the list leaving the page *are* the
    /// report, and a swallowed refusal left the whole settle pending for the next unrelated
    /// `rollback()` to revert: a list the owner archived coming back with all its tasks open.
    ///
    /// The undo is a `CadenceListEditSnapshot` of the list and the tasks about to be settled
    /// (`iOSListWindDownTarget.settledTasks`), taken before the first write. For an area that is
    /// `includingChildProjects: true`, the set the settle walks.
    func windDownList(
        _ target: iOSListWindDownTarget,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        let undo: CadenceListEditSnapshot
        switch target.list {
        case .area(let area):
            undo = CadenceListEditSnapshot(area, tasks: target.settledTasks)
        case .project(let project):
            undo = CadenceListEditSnapshot(project, tasks: target.settledTasks)
        }
        settleListWindDown(target)
        try CadencePendingChangePersistence.commitEdit(in: self, commit: commit, undo: undo.restore)
    }

    /// The settle's writes alone -- the list's `status` and its remaining open tasks -- for a
    /// caller that commits them inside a commit of its own.
    ///
    /// **[[T-12020]]: the list editor's Complete / Archive rows.** Its `save()` used to commit the
    /// field edits and only then call `windDownList`, so a refused wind-down reported
    /// `CadencePendingChangePersistence.editFailureNotice` -- "Nothing was changed" -- over a
    /// rename that was already in the store. macOS's `EditAreaSheet` / `EditProjectSheet`
    /// `apply(_:)` writes the edits and the settle under one snapshot and one commit (no hardware
    /// reason for the difference, T-8201), so the editor now does the same: it hands
    /// `settledTasks` to its own snapshot, calls this before its commit, and a refusal undoes the
    /// edits and the settle together, which is what the sentence says.
    ///
    /// Not a door around the rule above: every write is still made here, and the caller's commit
    /// must go through `CadencePendingChangePersistence.commitEdit` with a snapshot that holds
    /// `settledTasks`.
    func settleListWindDown(_ target: iOSListWindDownTarget) {
        switch (target.list, target.action) {
        case (.area(let area), .archive):
            area.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                in: self
            )
        case (.area(let area), .complete):
            area.status = .done
            TaskContainerLifecycleService.completeRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                in: self
            )
        case (.project(let project), .archive):
            project.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: project, in: self)
        case (.project(let project), .complete):
            project.status = .done
            TaskContainerLifecycleService.completeRemainingActiveTasks(in: project, in: self)
        }
    }

    /// **The one conditional-confirmation decision for a list's context-menu wind-down** — the
    /// Lists page (`iOSListsView`, which the iPad pane calls up into) and the sidebar lists region
    /// (`iOSSidebarListsRegion`, [[T-11753]]) both ask it, so the menus cannot answer it
    /// differently. Winds `target` down at once and returns `nil` when nothing would be settled;
    /// otherwise returns `target` for the host to hand to `iOSListWindDown(target:)`, untouched.
    /// The list editor keeps its own copy because its immediate path settles inside its field
    /// edits' commit ([[T-8562]], [[T-12020]]).
    ///
    /// Throws when the immediate wind-down was refused; a menu has closed by then, so the host
    /// names it with `iOSListWindDownFailureAlert`.
    func windDownListUnlessConfirmationIsNeeded(
        _ target: iOSListWindDownTarget,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> iOSListWindDownTarget? {
        guard target.summary.requiresConfirmation else {
            try windDownList(target, commit: commit)
            return nil
        }
        return target
    }
}

extension iOSListWindDownTarget {
    /// Title-case, because it is an alert title; `CadencePendingChangePersistence.editFailureNotice`
    /// is the sentence under it, as on the Mac's edit sheets.
    ///
    /// **[[T-12532]]: it names the kind.** It was `"Couldn't \(verb) List"` on the action alone,
    /// under a control that read "Archive Project" or "Complete Area" and a confirmation titled
    /// "Archive \(noun)" -- and "list" is not a thing the app calls anything, which is why
    /// `CadenceListDeletionKind.deleteFailureNotice` already names the kind. So a refusal keeps the
    /// whole target, not just its action.
    var failureAlertTitle: String {
        "Couldn't \(action.verb) \(list.noun)"
    }
}

extension View {
    /// Attaches the one list wind-down confirmation, in whichever direction its host set.
    ///
    /// Its host sets the binding only when `CadenceContainerWindDownSummary.requiresConfirmation`
    /// says the wind-down would settle something; a list with nothing open is wound down on the
    /// spot. Both the iPhone list and the iPad pane route their swipe and their context menu through
    /// that one decision, so the two cannot answer it differently.
    ///
    /// `perform` is `nil` on the Lists page, which winds the list down and nothing else. The list
    /// editor ([[T-8562]]) hands its own, because a confirmed wind-down there also writes the
    /// editor's pending field edits first and closes the editor -- the same `perform` it runs on
    /// the immediate path, as `iOSColumnWindDown` does for a column.
    ///
    /// `perform` throws when the write was refused, and the confirmation then stays up and says so
    /// rather than closing over a settle the store never took ([[T-11614]] group (1)).
    func iOSListWindDown(
        target: Binding<iOSListWindDownTarget?>,
        perform: ((iOSListWindDownTarget) throws -> Void)? = nil
    ) -> some View {
        modifier(iOSListWindDownModifier(target: target, perform: perform))
    }

    /// The refusal of a wind-down made **without** a confirmation — a context-menu or swipe item on
    /// a list with nothing open. The menu has closed on the tap, so there is no surface of its own
    /// left to say it, for the reason `iOSTaskMoveFailureAlertModifier` gives. `nil` hides it.
    func iOSListWindDownFailureAlert(refused target: Binding<iOSListWindDownTarget?>) -> some View {
        alert(
            target.wrappedValue?.failureAlertTitle ?? "",
            isPresented: Binding(
                get: { target.wrappedValue != nil },
                set: { if !$0 { target.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CadencePendingChangePersistence.editFailureNotice)
        }
    }
}

private struct iOSListWindDownModifier: ViewModifier {
    @Binding var target: iOSListWindDownTarget?
    let perform: ((iOSListWindDownTarget) throws -> Void)?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            iOSWindDownConfirmationSheet(subject: target.windDownSubject) {
                if let perform {
                    try perform(target)
                } else {
                    try modelContext.windDownList(target)
                }
            }
            .cadenceFixedTypography()
        }
    }
}

/// Everything the confirmation needs from a list, in the vocabulary the sheet speaks.
///
/// Built here rather than in the sheet because the sheet is shared with the kanban column
/// (`iOSColumnWindDownSupport`), and the containers agree on nothing except that a wind-down settles
/// work irreversibly. See `iOSWindDownSubject`.
///
/// **The two directions ask the same question and make different claims, and the copy has to carry
/// that.** The *ceremony* is identical — same sheet, same conditional rule, no typed phrase either
/// way — because what makes a wind-down worth confirming is that the settle cannot be undone, and
/// that is equally true of both. What differs is what the settle *asserts*. A cancellation records
/// that work was abandoned; a completion records that it happened, and Cadence reads that record:
/// `GoalContributionSummary` computes a subtasks-goal's progress as `completedTasks / totalTasks`
/// over `filter(\.isDone)`, so bulk-completing a list can move a goal's bar — where bulk-cancelling
/// the same list moves nothing, since a cancelled task stays in the denominator and out of the
/// numerator. The completion copy says so; the archive copy has nothing to say there.
///
/// The other real difference is **where the list goes**, and it is not symmetrical on iOS: an
/// archived list stays on this page under "Archived", one tap from Restore, while a completed list
/// leaves the page entirely and is reopened from Settings › Lists. A confirmation that did not name
/// the destination would make completion look like a deletion.
extension iOSListWindDownTarget {
    var windDownSubject: iOSWindDownSubject {
        let noun = list.noun
        let lowerNoun = noun.lowercased()

        switch action {
        case .archive:
            return iOSWindDownSubject(
                title: "Archive \(noun)",
                actionIcon: action.filledIcon,
                headline: "Archiving settles what is left",
                explanation: "The \(lowerNoun) moves to Archived and can be unarchived from there. Unarchiving it does not reopen the work canceled below.",
                name: list.name,
                icon: list.icon,
                colorHex: list.colorHex,
                emptyNote: "Nothing is still open in this \(lowerNoun) — archiving it cancels no work.",
                summary: summary
            )
        case .complete:
            return iOSWindDownSubject(
                title: "Complete \(noun)",
                actionIcon: action.filledIcon,
                headline: "Completing settles what is left",
                explanation: "The \(lowerNoun) moves to Completed in Settings › Lists and can be reopened from there. Reopening it does not reopen the work below, and work marked done counts as finished wherever Cadence measures progress.",
                name: list.name,
                icon: list.icon,
                colorHex: list.colorHex,
                emptyNote: "Nothing is still open in this \(lowerNoun) — completing it marks no work done.",
                summary: summary
            )
        }
    }
}
#endif
