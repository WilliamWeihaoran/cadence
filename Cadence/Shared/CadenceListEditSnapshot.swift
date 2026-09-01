import Foundation
import SwiftData

/// Everything a list editor can write to an `Area` or a `Project` — the list's own fields, its
/// column blob, and the tasks it re-points or settles — captured before the write so a refused
/// commit can put all of it back (T-321).
///
/// **Why this exists rather than `modelContext.rollback()`, which is what the delete paths use.**
/// The reason that holds unconditionally is that this is the app's single `ModelContext`:
/// `rollback()` would discard pending work that has nothing to do with the editor.
///
/// The second reason is measured, and it is why this type was written after the first version of
/// the fix reached for a rollback by analogy with the cascades. `rollback()` un-**deletes**
/// unconditionally — `CadenceListCascadeRollbackTests` pins that, and it is why `commitDelete` is
/// right — but its undo of an *edit* is not visible on an already-materialised reference until a
/// fetch refreshes it. The store is correct the whole time; the object every SwiftUI view is
/// reading is not. An editor that rolled back and then said "Nothing was changed" would be relying
/// on a fetch nobody scheduled. See
/// `CadenceEditorSaveCommitSurfaceTests.rollbackRestoresAnEditOnlyOnceSomethingRefreshesTheObject`,
/// whose assertion order is itself load-bearing.
///
/// **Raw strings, not the computed façades.** `statusRaw` and `sectionConfigsRaw` are the stored
/// properties; `status` coerces an unrecognised value to `.active` on read and `sectionConfigs`
/// re-encodes through JSON. Snapshotting the computed side would put a *normalised* value back as
/// if the user had chosen it. Restoring the raw is a no-op when the commit lands and an exact undo
/// when it does not — same rule as `CadenceTaskFieldSnapshot`.
///
/// `tasks` is passed in rather than read from the relationship, because the two callers mean
/// different sets: the iOS editor re-points **every** task in the list, and macOS's lifecycle rows
/// settle only `TaskContainerLifecycleService.remainingActiveTasks`. Each hands over the set it is
/// about to write to, so nothing is snapshotted that was never touched and nothing touched is
/// missed.
///
/// **A task may legitimately appear twice (T-559).** macOS's edit sheets hand over two overlapping
/// sets in one save — the tasks a context change re-points, and the ones a lifecycle choice settles
/// — and concatenating them is the natural spelling at both call sites. Every snapshot in one
/// initializer is taken before any write, so two of the same task hold the same values and
/// restoring twice is exactly restoring once. De-duplicating would be code with no observable
/// effect, which is worse than the duplication.
struct CadenceListEditSnapshot {
    private let area: Area?
    private let project: Project?

    private let statusRaw: String
    private let name: String
    private let desc: String
    private let icon: String
    private let colorHex: String
    private let linkedCalendarID: String
    private let dueDate: String
    private let hideDueDateIfEmpty: Bool
    private let hideSectionDueDateIfEmpty: Bool
    private let sectionConfigsRaw: String
    private let context: Context?
    private let parentArea: Area?

    private let tasks: [AppTask]
    private let taskSnapshots: [CadenceTaskFieldSnapshot]

    init(_ area: Area, tasks: [AppTask] = []) {
        self.area = area
        project = nil
        statusRaw = area.statusRaw
        name = area.name
        desc = area.desc
        icon = area.icon
        colorHex = area.colorHex
        linkedCalendarID = area.linkedCalendarID
        // An area has no due date of its own; the field is here for the project case and is put
        // back only on a project.
        dueDate = ""
        hideDueDateIfEmpty = area.hideDueDateIfEmpty
        hideSectionDueDateIfEmpty = area.hideSectionDueDateIfEmpty
        sectionConfigsRaw = area.sectionConfigsRaw
        context = area.context
        parentArea = nil
        self.tasks = tasks
        taskSnapshots = Self.snapshots(of: tasks)
    }

    init(_ project: Project, tasks: [AppTask] = []) {
        area = nil
        self.project = project
        statusRaw = project.statusRaw
        name = project.name
        desc = project.desc
        icon = project.icon
        colorHex = project.colorHex
        linkedCalendarID = project.linkedCalendarID
        dueDate = project.dueDate
        hideDueDateIfEmpty = project.hideDueDateIfEmpty
        hideSectionDueDateIfEmpty = project.hideSectionDueDateIfEmpty
        sectionConfigsRaw = project.sectionConfigsRaw
        context = project.context
        parentArea = project.area
        self.tasks = tasks
        taskSnapshots = Self.snapshots(of: tasks)
    }

    /// A loop rather than `tasks.map(CadenceTaskFieldSnapshot.init)`: `map`'s closure parameter is
    /// nonisolated, so the function-reference spelling calls a main-actor-isolated initializer from
    /// a nonisolated context and warns. The loop runs in this initializer's own isolation.
    private static func snapshots(of tasks: [AppTask]) -> [CadenceTaskFieldSnapshot] {
        var result: [CadenceTaskFieldSnapshot] = []
        result.reserveCapacity(tasks.count)
        for task in tasks {
            result.append(CadenceTaskFieldSnapshot(task))
        }
        return result
    }

    func restore() {
        if let area {
            area.statusRaw = statusRaw
            area.name = name
            area.desc = desc
            area.icon = icon
            area.colorHex = colorHex
            area.linkedCalendarID = linkedCalendarID
            area.hideDueDateIfEmpty = hideDueDateIfEmpty
            area.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            area.sectionConfigsRaw = sectionConfigsRaw
            area.context = context
        }
        if let project {
            project.statusRaw = statusRaw
            project.name = name
            project.desc = desc
            project.icon = icon
            project.colorHex = colorHex
            project.linkedCalendarID = linkedCalendarID
            project.dueDate = dueDate
            project.hideDueDateIfEmpty = hideDueDateIfEmpty
            project.hideSectionDueDateIfEmpty = hideSectionDueDateIfEmpty
            project.sectionConfigsRaw = sectionConfigsRaw
            project.context = context
            project.area = parentArea
        }
        for (snapshot, task) in zip(taskSnapshots, tasks) {
            snapshot.restore(to: task)
        }
    }
}
