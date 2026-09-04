#if os(macOS)
import SwiftData
import SwiftUI

let kanbanSectionDragPrefix = "kanban-section::"
// The section swatch palette is `CadenceColorPalette.sectionColors`, in `Shared/`. It was eight
// hex literals here (T-246) — a fourth palette, in a macOS view file, for a field iOS also edits.
// The values did not change when they moved; see that declaration for why five of them are hexes
// rather than `Theme` tokens.
let kanbanColumnReorderAnimation = Animation.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.12)
let kanbanColumnStateAnimation = Animation.spring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
let kanbanColumnWidth: CGFloat = 236
// The Calendar Board's four geometry constants are `CadenceCalendarBoardLayout`, in `Shared/`
// (T-251) — the day column's width and inset, the column spacing, and the expanded rail's width.
// They were four top-level `let`s here, and this file is behind `#if os(macOS)`, so the floor that
// has to be a *sum* of them could not have been written anywhere that could read them. The values
// did not change when they moved; see that declaration for the gate they now feed. Call sites read
// the shared spelling directly rather than through an alias here, so there is one name per number.
/// Kanban columns are containerless (no fill, no border). This radius is only used for the
/// transient drop-target wash / dashed outline and the search-navigation highlight ring.
let kanbanColumnCornerRadius: CGFloat = Theme.radiusControl
/// Cards keep a container so they read as objects sitting directly on the canvas.
let kanbanCardCornerRadius: CGFloat = Theme.radiusControlCompact

// MARK: - Shared column chrome constants
//
// Both kanban column implementations (`ListSectionKanbanColumn` and `TaskListKanbanColumn`)
// render through the shared components in `KanbanColumnSupportViews.swift`, which read these
// values. Nothing should re-spell these literals inline — that is exactly how the two columns
// drifted apart before.

// The single dot of colour that survives in an otherwise containerless column header is
// `CadenceBoardColumnHeaderMetrics.dotSize`, in `Shared/`, because the iOS boards draw it too.
/// Transient drag-over wash behind a targeted column.
let kanbanColumnDropFillOpacity: Double = 0.07
/// Transient drag-over dashed outline around a targeted column.
let kanbanColumnDropStrokeOpacity: Double = 0.55
let kanbanColumnDropDash: [CGFloat] = [5, 4]
let kanbanColumnDropAnimation = Animation.easeInOut(duration: 0.14)
/// Applied when card `order` values are reassigned after a drop.
let kanbanCardReorderAnimation = Animation.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)

struct KanbanListColumnModel: Identifiable {
    let id: String
    let title: String
    let color: Color
    let tasks: [AppTask]
    let container: TaskContainerSelection
    let onAssignTask: (AppTask) -> Void
}

enum KanbanBoardSupport {
    /// The two halves a kanban column draws: the work you still intend to do, and the work that is
    /// over however it ended. One call, read twice, so the halves cannot disagree.
    ///
    /// Splitting on `isDone` alone *does* partition — and puts the wrong card in the wrong half. A
    /// cancelled task is not `isDone`, so `!$0.isDone` kept it among the work you still intend to
    /// do and `$0.isDone` kept it out of the completed half it belongs in. That is the
    /// T-147 / T-203 / T-342 shape arriving a fourth time, and
    /// `CadenceTaskQuerySupport.isFinishedTask` is the predicate that settles it.
    ///
    /// No card proves it today: the section board's only caller, `ListSectionsKanbanView`, filters
    /// cancelled work out before a column ever sees it (T-381 was right about that, and T-399 wrong
    /// to call it live). The classification has to be right without depending on a caller's shape,
    /// which is exactly what the calendar board's day columns decided under T-203.
    static func columnHalves(from tasks: [AppTask]) -> (active: [AppTask], completed: [AppTask]) {
        (
            tasks.filter { !CadenceTaskQuerySupport.isFinishedTask($0) },
            tasks.filter { CadenceTaskQuerySupport.isFinishedTask($0) }
        )
    }

    static func activeTasks(from allTasks: [AppTask]) -> [AppTask] {
        let tasksInActiveContainers = allTasks.filter(\.isInActiveContainer)
        return CadenceTaskQuerySupport.openTasks(from: tasksInActiveContainers)
    }

    static func inboxTasks(
        from activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [AppTask] {
        activeTasks
            .filter { $0.area == nil && $0.project == nil }
            .taskSorted(by: sortField, direction: sortDirection)
    }

    static func groupedTasksByAreaID(
        from activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [UUID: [AppTask]] {
        Dictionary(grouping: activeTasks.compactMap { task -> (UUID, AppTask)? in
            guard let areaID = task.area?.id else { return nil }
            return (areaID, task)
        }, by: \.0).mapValues { entries in
            entries.map(\.1).taskSorted(by: sortField, direction: sortDirection)
        }
    }

    static func groupedTasksByProjectID(
        from activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection
    ) -> [UUID: [AppTask]] {
        Dictionary(grouping: activeTasks.compactMap { task -> (UUID, AppTask)? in
            guard let projectID = task.project?.id else { return nil }
            return (projectID, task)
        }, by: \.0).mapValues { entries in
            entries.map(\.1).taskSorted(by: sortField, direction: sortDirection)
        }
    }

    /// The board's columns, one per list, Inbox first.
    ///
    /// `scope` is the Tasks page's All / Inbox switch applied to the board. Inbox is *already* one
    /// of these columns — it has been since the board shipped, which is the strongest evidence that
    /// All Tasks and Inbox were one surface all along — so the Inbox scope is this same board with
    /// the other columns dropped rather than a second board. A one-column board is the honest
    /// rendering of "the Inbox, as a board"; it is not a degenerate case to be special-cased away.
    static func listColumns(
        areas: [Area],
        projects: [Project],
        activeTasks: [AppTask],
        sortField: TaskSortField,
        sortDirection: TaskSortDirection,
        scope: CadenceTasksPageScope = .all
    ) -> [KanbanListColumnModel] {
        let groupedAreas = groupedTasksByAreaID(from: activeTasks, sortField: sortField, sortDirection: sortDirection)
        let groupedProjects = groupedTasksByProjectID(from: activeTasks, sortField: sortField, sortDirection: sortDirection)
        var columns: [KanbanListColumnModel] = [
            KanbanListColumnModel(
                id: "inbox",
                title: "Inbox",
                color: Theme.dim,
                tasks: inboxTasks(from: activeTasks, sortField: sortField, sortDirection: sortDirection),
                container: .inbox,
                onAssignTask: { task in
                    task.area = nil
                    task.project = nil
                    task.context = nil
                }
            )
        ]

        columns += areas.filter(\.isActive).map { area in
            KanbanListColumnModel(
                id: "area-\(area.id.uuidString)",
                title: area.name,
                color: Color(hex: area.colorHex),
                tasks: groupedAreas[area.id] ?? [],
                container: .area(area.id),
                onAssignTask: { task in
                    task.area = area
                    task.project = nil
                    task.context = area.context
                }
            )
        }

        columns += projects.filter(\.isActive).map { project in
            KanbanListColumnModel(
                id: "project-\(project.id.uuidString)",
                title: project.name,
                color: Color(hex: project.colorHex),
                tasks: groupedProjects[project.id] ?? [],
                container: .project(project.id),
                onAssignTask: { task in
                    task.project = project
                    task.area = nil
                    task.context = project.resolvedContext
                }
            )
        }

        return scope == .inbox ? Array(columns.prefix(1)) : columns
    }

    /// Reassigns `order` across a column after a card was dropped into it, **and commits it**.
    ///
    /// `columnTasks` is the column's current ordering *as the caller presents it* (section
    /// columns sort by `order`, list columns by the board's active sort), `task` is the card
    /// that was dropped, and `target` is the card it was dropped in front of — `nil` means
    /// "append to the end", which is what a drop on empty column space produces.
    ///
    /// **It reached no commit at all until T-869**, and both column views answered `true` over it.
    /// A rearrangement the user can see is a success report (T-614), so a card that sits where it
    /// was dropped and springs back at next launch is precisely the failure that rule is about.
    /// This one was invisible to `CadenceSaveCommitDisciplineTests` twice over: half 2 needs a
    /// *swallowed* commit in the frame to hang the rule on and there was none, and half 3 fires on
    /// insert/delete rather than on field writes.
    ///
    /// **`assigning` is inside the commit, not before it, and that is the point.** A card dropped
    /// into another column is moved *and* refiled — the list columns rewrite `area`/`project`/
    /// `context`, the section columns rewrite those and `sectionName`. Committing the renumber
    /// while the refiling sat outside it would leave a refused drop half-applied: the card in its
    /// new column at its old position. `CadenceTaskFieldEditCommit` snapshots every one of those
    /// fields on every card it is given, so the undo puts the whole drop back.
    ///
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container.
    /// - Returns: Whether the drop is in the store. `false` means every card is back where it was
    ///   and the column must show `CadenceOrderCommit.failureNotice` rather than accept the drop.
    @MainActor
    @discardableResult
    static func reorder(
        _ columnTasks: [AppTask],
        moving task: AppTask,
        before target: AppTask?,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() },
        assigning assign: () -> Void = {}
    ) -> Bool {
        var ordered = columnTasks
        ordered.removeAll { $0.id == task.id }
        if let target, let targetIndex = ordered.firstIndex(where: { $0.id == target.id }) {
            ordered.insert(task, at: targetIndex)
        } else {
            ordered.append(task)
        }
        return withAnimation(kanbanCardReorderAnimation) {
            CadenceTaskFieldEditCommit.commit(
                task,
                alsoRestoring: ordered,
                in: modelContext,
                commit: commit
            ) {
                assign()
                for (index, item) in ordered.enumerated() {
                    item.order = index
                }
            }
        }
    }

    static func nextSectionName(from sectionConfigs: [TaskSectionConfig]) -> String {
        let existingNames = Set(sectionConfigs.map { $0.name.lowercased() })
        if !existingNames.contains("new section") {
            return "New Section"
        }

        var index = 2
        while existingNames.contains("new section \(index)") {
            index += 1
        }
        return "New Section \(index)"
    }

    static func reorderedSectionConfigs(
        _ sectionConfigs: [TaskSectionConfig],
        movingName: String,
        targetName: String
    ) -> [TaskSectionConfig] {
        guard movingName.caseInsensitiveCompare(targetName) != .orderedSame else {
            return sectionConfigs
        }
        guard let fromIndex = sectionConfigs.firstIndex(where: { $0.name.caseInsensitiveCompare(movingName) == .orderedSame }),
              let toIndex = sectionConfigs.firstIndex(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame })
        else {
            return sectionConfigs
        }

        var updated = sectionConfigs
        let moved = updated.remove(at: fromIndex)
        let insertAt = fromIndex < toIndex ? toIndex - 1 : toIndex
        updated.insert(moved, at: max(0, insertAt))

        if let defaultIndex = updated.firstIndex(where: \.isDefault), defaultIndex != 0 {
            let defaultSection = updated.remove(at: defaultIndex)
            updated.insert(defaultSection, at: 0)
        }

        return updated
    }

    static func taskID(from payload: String) -> UUID? {
        TaskDragPayload.taskID(from: payload)
    }
}
#endif
