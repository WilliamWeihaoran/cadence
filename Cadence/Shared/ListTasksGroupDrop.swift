import Foundation
import SwiftData

// **A list's Tasks tab re-files a row dropped on a heading, on both platforms ([[T-16682]]).**
//
// `ListTasksGroupDrop` was `#if os(macOS)` in `ListDetailSupportViews.swift` and typed on the
// Mac-only `ListTasksGroup`, so on the iPhone and iPad a list's Tasks tab headings took only the
// new-task `+` while the Mac's re-filed a row dragged onto the same heading. No hardware constraint
// answered that split -- a touch row drag is a system drag carrying the same `TaskDragPayload`
// string, which [[T-16654]] already let All Tasks and Inbox read -- so it was drift ([[T-8201]]),
// and the enum moved here verbatim rather than being re-spelled for iOS. It reads a group through
// `ListTasksDropGroup`, which the Mac's `ListTasksGroup` and the shared `CadenceTaskDisplayGroup`
// (iOS's group) both are; its two Mac-only lookups are the shared ones they already forwarded to
// (`CadenceTaskHeaderDrop.dateDropKey`, `CadenceTaskHeaderDrop.assignTask`).

/// What `ListTasksGroupDrop` reads of a heading: its id (which says what kind of group it is), its
/// title (a section's configured spelling) and its rows.
protocol ListTasksDropGroup {
    var id: String { get }
    var title: String { get }
    var tasks: [AppTask] { get }
}

extension CadenceTaskDisplayGroup: ListTasksDropGroup {}

/// **[[T-5358]] — a row dropped into ANOTHER group on a list's Tasks tab joins that group.**
///
/// The tab's row drop only renumbered, so a task dragged from "Documents" onto a row under "Later"
/// took a new `order` and sprang straight back under Documents, with nothing said. All Tasks and
/// the section board both refile on the same gesture (`TasksPanelDropCoordinator.handleTaskDrop`
/// assigns its group's key, then reorders; `KanbanSectionColumnView.moveTask` files the card under
/// its column). This is that first half for this tab: what the target group means, written as one
/// commit before the reorder that `ListTasksView.reorderTask` already makes.
///
/// - By section: the group's section name — the configured spelling, which is the group's title.
/// - By priority: the target row's priority, the `priority:` key All Tasks reads.
/// - By date: `CadenceTaskHeaderDrop.dateDropKey(forGroupID:)`, so Do Today / Scheduled / Unscheduled move
///   a task exactly as they do on All Tasks, and Overdue / Due Today — a day already gone, with no
///   assignment that makes a task late — reorder only, as they do there.
enum ListTasksGroupDrop {
    enum Refiling: Equatable {
        case section(String)
        case dropKey(String)
    }

    /// `nil` when the drop stays inside its own group, or the group names nothing a task can be
    /// moved into — the drop is then the plain reorder it always was.
    static func refiling(
        dropping dropped: AppTask,
        onto target: AppTask,
        in group: some ListTasksDropGroup,
        groupingMode: TaskGroupingMode
    ) -> Refiling? {
        guard !group.tasks.contains(where: { $0.id == dropped.id }) else { return nil }
        switch groupingMode {
        case .none:
            return nil
        case .byList:
            return .section(group.title)
        case .byPriority:
            return target.priority == dropped.priority ? nil : .dropKey("priority:\(target.priority.rawValue)")
        case .byDate:
            return CadenceTaskHeaderDrop.dateDropKey(forGroupID: group.id).map(Refiling.dropKey)
        }
    }

    /// **[[T-5840]] — a drop on a group's HEADER joins that group, at its top.** The header had no
    /// drop destination, so a task let go over "Later" itself, with no row under the pointer, was
    /// not taken at all. A header drop is answered as a drop on the group's first row: the same
    /// refiling as a row drop (`refiling(dropping:onto:in:groupingMode:)` reads that row's priority,
    /// which is the group's, since every row of a priority group shares it), then the renumber puts
    /// the task first in the group — the place a drop just under a heading means. Going through the
    /// row path keeps one commit order and one failure notice for both drop sites.
    ///
    /// `nil` — the header refuses the drop — when the task is already in this group, or the group
    /// names nothing a task can be moved into (the ungrouped "Tasks" group; Overdue / Due Today by
    /// date). A header that only renumbered would answer a drop the user aimed at a group by leaving
    /// the task out of it, which is the silent accept T-591 removed from All Tasks' headers.
    ///
    /// **Asked of the group's id, not of a grouping mode**, because the id already says which kind
    /// of group this is — `CadenceTaskQuerySupport` spells section groups `section-…`, priority
    /// groups `priority-…` and the date buckets by name — and the header view is handed the group,
    /// not the page's grouping. `ListTasksGroupDropTests` builds its groups with those same
    /// functions, so a renamed id reddens there rather than turning every header off.
    /// **[[T-15821]] — an EMPTY section's header files the dropped task under that section.**
    /// Grouped by section, the tab draws every configured section, empty ones included, and an
    /// empty section has no rows — so its header is its only drop site, and `headerDropTarget`
    /// (which answers through the group's first row) is `nil` for exactly the section the user is
    /// trying to fill. This is the refiling half of the row path without the renumber: there is no
    /// row to land beside, so the task keeps its `order`.
    ///
    /// Section groups only (`section-…`, the id `CadenceTaskQuerySupport.sectionGroups` spells):
    /// they are the only groups this tab draws empty. A non-empty group answers through
    /// `headerDropTarget` instead, so the two never both claim one drop.
    static func emptySectionRefiling(in group: some ListTasksDropGroup) -> Refiling? {
        guard group.tasks.isEmpty, group.id.hasPrefix("section-") else { return nil }
        return .section(group.title)
    }

    static func headerDropTarget(droppedID: UUID, in group: some ListTasksDropGroup) -> UUID? {
        guard let first = group.tasks.first,
              !group.tasks.contains(where: { $0.id == droppedID }) else { return nil }
        return refilesInto(groupID: group.id) ? first.id : nil
    }

    /// **Whether a heading takes a dropped row at all** -- asked before any drag, so a surface
    /// registers a row destination only on a heading that can file one ([[T-16682]]; T-591: a
    /// heading that accepted a row and filed it nowhere is a silent accept). The same two answers
    /// `dropOnHeader` gives: a group with rows refiles when its id names a placement; an empty one
    /// only when it is a section.
    static func takesDroppedRow(_ group: some ListTasksDropGroup) -> Bool {
        group.tasks.isEmpty ? emptySectionRefiling(in: group) != nil : refilesInto(groupID: group.id)
    }

    private static func refilesInto(groupID id: String) -> Bool {
        id.hasPrefix("section-")
            || id.hasPrefix("priority-")
            || CadenceTaskHeaderDrop.dateDropKey(forGroupID: id) != nil
    }

    /// What a heading drop did, for the surface to draw: the notice is the sentence to show, the
    /// same two the Mac's `ListTasksView` sets (`CadenceReorderVisibility`'s off-screen landing on
    /// a drop the store took; `editFailureNotice` or `CadenceOrderCommit.failureNotice` on one it
    /// refused). `.resolvedNothing` says nothing -- the row springing back is the whole report.
    enum HeaderDropOutcome: Equatable {
        case applied(notice: String?)
        case refused(notice: String)
        case resolvedNothing
    }

    /// **A row let go over a heading of a list's Tasks tab -- the Mac header's whole drop, in one
    /// place iOS can call ([[T-16682]]).** The same three steps, in the same order, as
    /// `ListTasksGroupSectionView`'s header and `ListTasksView.dropTask`: a group with rows takes
    /// the drop as one on its first row (`headerDropTarget`) -- refile, then renumber to the top of
    /// the group through `CadenceTaskRowReorder.reorderTask` over the list's open rows, spanning the
    /// whole list ([[T-1175]]); an empty section files it with no renumber
    /// (`emptySectionRefiling`, [[T-15821]]); anything else refuses. A refused refile stops before
    /// the renumber, because the store still files the task where it was.
    ///
    /// `listTasks` is the list's own tasks, open and finished -- the page's universe: a payload
    /// naming a task the list does not hold resolves to nothing and writes nothing.
    static func dropOnHeader(
        payload: String,
        onto group: some ListTasksDropGroup,
        groupingMode: TaskGroupingMode,
        listTasks: [AppTask],
        todayKey: String,
        modelContext: ModelContext,
        sortKeyOrder: (AppTask, AppTask) -> TaskSortKeyOrder,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> HeaderDropOutcome {
        guard let droppedID = TaskDragPayload.listTaskID(from: payload),
              let dropped = listTasks.first(where: { $0.id == droppedID }) else { return .resolvedNothing }
        guard let targetID = headerDropTarget(droppedID: droppedID, in: group) else {
            guard let refiling = emptySectionRefiling(in: group) else { return .resolvedNothing }
            return refile(dropped, refiling, todayKey: todayKey, modelContext: modelContext, commit: commit)
                ? .applied(notice: nil)
                : .refused(notice: CadencePendingChangePersistence.editFailureNotice)
        }
        guard let target = listTasks.first(where: { $0.id == targetID }) else { return .resolvedNothing }
        if let refiling = refiling(dropping: dropped, onto: target, in: group, groupingMode: groupingMode) {
            guard refile(dropped, refiling, todayKey: todayKey, modelContext: modelContext, commit: commit) else {
                return .refused(notice: CadencePendingChangePersistence.editFailureNotice)
            }
        }
        let openTasks = CadenceTaskQuerySupport.openTasks(from: listTasks)
        // Asked before the renumber and reported after it, as the Mac's tab does (T-1119).
        let landing = CadenceReorderVisibility.notice(
            droppedID: droppedID,
            targetID: targetID,
            in: openTasks,
            sortKeyOrder: sortKeyOrder
        )
        let reordered = CadenceTaskRowReorder.reorderTask(
            droppedID: droppedID,
            targetID: targetID,
            scopeTasks: openTasks,
            spanTasks: listTasks,
            modelContext: modelContext,
            commit: commit
        )
        return reordered ? .applied(notice: landing) : .refused(notice: CadenceOrderCommit.failureNotice)
    }

    /// Writes the refiling as one commit. `false` means the store refused it and every field is
    /// back as it was (`CadenceTaskFieldEditCommit` / `CadenceTaskHeaderDrop.assignTask` undo it), so
    /// the caller must not go on to reorder a row the store still files in its old group.
    static func refile(
        _ task: AppTask,
        _ refiling: Refiling,
        todayKey: String,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        switch refiling {
        case .section(let name):
            return CadenceTaskFieldEditCommit.commit(task, in: modelContext, commit: commit) {
                task.sectionName = name
            }
        case .dropKey(let key):
            return CadenceTaskHeaderDrop.assignTask(
                task,
                for: key,
                todayKey: todayKey,
                areas: [],
                projects: [],
                modelContext: modelContext,
                commit: commit
            ) == .applied
        }
    }
}
