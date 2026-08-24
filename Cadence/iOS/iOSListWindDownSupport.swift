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
    var name: String {
        let raw: String
        switch self {
        case .area(let area): raw = area.name
        case .project(let project): raw = project.name
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled \(noun)" : raw
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
    func windDownList(_ target: iOSListWindDownTarget) {
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
        try? save()
    }
}

extension View {
    /// Attaches the one list wind-down confirmation, in whichever direction its host set.
    ///
    /// Its host sets the binding only when `CadenceContainerWindDownSummary.requiresConfirmation`
    /// says the wind-down would settle something; a list with nothing open is wound down on the
    /// spot. Both the iPhone list and the iPad pane route their swipe and their context menu through
    /// that one decision, so the two cannot answer it differently.
    func iOSListWindDown(target: Binding<iOSListWindDownTarget?>) -> some View {
        modifier(iOSListWindDownModifier(target: target))
    }
}

private struct iOSListWindDownModifier: ViewModifier {
    @Binding var target: iOSListWindDownTarget?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            iOSWindDownConfirmationSheet(subject: target.windDownSubject) {
                modelContext.windDownList(target)
            }
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
                explanation: "The \(lowerNoun) moves to Archived and can be restored from there. Restoring it does not reopen the work cancelled below.",
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
