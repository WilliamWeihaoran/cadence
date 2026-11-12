#if os(macOS)
import SwiftUI
import SwiftData

// `TasksPanelMode` was declared here and is gone (T-564(a)). `.byDoDate` — this panel's All Tasks
// shape — had already gone in T-487, being unreachable: `TodayView` builds the only `TasksPanel` in
// the repository and took the `.todayOverview` default, so nothing but a test ever constructed the
// other one. That left a one-case enum, kept for one stated reason: `switch mode`, written out in
// `TasksPanelDerivedState.init`, `isEmptyState` and `TasksPanel.taskSections`, forced a future
// second mode to be *answered* rather than to fall through silently.
//
// **The decision, made deliberately and late.** A one-case enum is a dead abstraction three files
// and every reader have to carry, and the forcing function it buys only pays out for a mode that
// arrives in exactly this shape. Whoever reintroduces the Today / All Tasks distinction will design
// it against the surfaces that exist then — `TasksPageView` is the All Tasks page now, and it has
// never built one of these panels — rather than filling in a `case` this file left open for them.
// So the enum is collapsed and the three `switch`es are gone with it.

// `TaskSortField` and `TaskSortDirection` live in `Cadence/Models/TaskOrdering.swift`, next to
// the comparator that reads them, so `CadenceWidgets` and `CadenceMCPServer` can reach both.
//
// `TaskGroupingMode` was declared here, under a comment saying grouping was "a macOS list-surface
// concern with no comparator behind it, and no other target has a grouped task list". The second
// half stopped being true with [[T-8731]]: the owner chose the Mac's Sort + Order + Group model
// for the iPhone and iPad too, and `Cadence/iOS/` cannot see this file. It lives in
// `Shared/CadenceTaskPlanningSupport.swift` now, beside the other shared task-presentation
// vocabulary, and `CadenceTaskQuerySupport.displayGroups(from:mode:todayKey:contexts:)` is the one
// place a mode is turned into groups.

// `TodayOverdueListSummary` and `TodayOverdueSectionSummary` were declared here, and derived in
// `TasksPanelDerivedState.init`, until T-195 moved them to `Shared/`. Today no longer draws
// past-due cards on either platform (T-3076), so the shared derivation and this panel's two
// `openOverdue…Summary` hops onto `ListNavigationManager` are gone too (T-3078).

// `MacTaskRowStyle` was declared here. `.list` went in T-290 (the list chip became the surface's
// `showsContainer` answer), and `.todayGrouped` — "drop the do-date pill, the section is the day" —
// went in T-7984: its last caller was All Tasks' Group: By List, whose sections are lists, not
// days, so every row there lost its do date. Today had already stopped using it for the same
// reason, and a one-case enum is a parameter that draws nothing. What a row withholds about its
// do date is now only `MacTaskRow.dayAlreadyStatedBySurface`, an equality with the named day.

/// Shared, pure index math for the inline "picker badge" style controls
/// (`ContainerPickerBadge`, `TaskSectionPickerBadge`, the CreateTaskSheet tilde
/// list/section pickers). Kept separate from any specific view so the
/// highlight-index arithmetic can be unit tested without SwiftUI.
enum TaskPickerHighlightSupport {
    /// Clamps `index` into the valid `0..<count` range. Returns 0 when `count <= 0`
    /// (an empty filtered list), which callers should additionally treat as "no
    /// selection" rather than a real highlighted row.
    static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    /// Moves `index` by `offset` and clamps at the ends (arrow key navigation stops
    /// at the first/last row). Used by `ContainerPickerBadge` / `TaskSectionPickerBadge`.
    ///
    /// The starting `index` is clamped into range *before* the offset is applied.
    /// This matters when a fast-typed search query has just shrunk the filtered
    /// list out from under a stale `highlightIdx`: without pre-clamping, the very
    /// next arrow press could land on the same edge row twice before recovering.
    static func clampedMovedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
        clampedIndex(clampedIndex(index, count: count) + offset, count: count)
    }

    /// Moves `index` by `offset`, wrapping around at the ends (cycling navigation).
    /// Used by the CreateTaskSheet tilde (`~`) inline list/section pickers.
    static func wrappedMovedIndex(_ index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (clampedIndex(index, count: count) + offset + count) % count
    }
}

// `TasksPanelDropAssignment`, `TasksPanelDropOutcome` and the resolved assignment were declared
// here; [[T-16654]] moved them, with the assign half below, to `Shared/CadenceTaskHeaderDrop.swift`.

enum TasksPanelSupport {
    // sidebarListOrder, listGroups and their two private helpers were here: All Tasks' By List
    // arm, built into a macOS-only TodayTaskGroup for the context glyph its header drew.
    // [[T-12193]] removed the glyph and [[T-12212]] moved that arm onto
    // `CadenceTaskQuerySupport.displayGroups`, which buckets and orders through the same
    // `CadenceTaskQuerySupport.listGroupKey` / `CadenceTaskQuerySupport.listGroupOrder` pair, so
    // all four went with their last reader.

    /// **How many rows the group has**, which is what its capsule says: "N tasks".
    ///
    /// This was `regularCount`, and it **subtracted** `overdueCount` from the not-done total. The
    /// user caught what that reads like on screen: a header saying `0 tasks` over three visible
    /// rows. The subtraction made the neutral capsule the *remainder* after the red flag, while its
    /// own label — "tasks" — claimed to be the total, so the two numbers had to be added to learn
    /// the group's size and a group whose open work was entirely late reported none.
    ///
    /// The flag and the capsule now answer two independent questions about the same rows — "how
    /// many, and how many of those are late" — so both are true on their own and neither has to be
    /// read through the other. `todayKey` went with the subtraction: a group's size does not depend
    /// on what day it is.
    ///
    /// **This is read by all four macOS group headers** — Today, All Tasks, the Inbox panel and a
    /// list's own detail — so the same `0 tasks` was reachable on every one of them, not just on
    /// the section the user was looking at.
    static func openCount(in tasks: [AppTask]) -> Int {
        tasks.filter { !$0.isDone }.count
    }

    static func taskDragPayload(for task: AppTask) -> String {
        TaskDragPayload.string(for: task.id)
    }

    static func taskID(from payload: String) -> UUID? {
        TaskDragPayload.taskID(from: payload)
    }

    /// Today's and All Tasks'/Inbox's row drop — both panels reach this one function.
    ///
    /// **It ended in `try? modelContext.save()` until T-868.** T-583 had recorded that spelling as
    /// deliberate here for the reason it is deliberate on an archive toggle: `order` is a field on
    /// rows the store already holds, and nothing after the save calls a `dismiss`. T-614 settled
    /// that a *visible rearrangement* is itself the report — a row that stays where you dropped it
    /// claims more than a sheet that closed, and a refused drop reverts at next launch with nothing
    /// to retry — so this left that list along with `SettingsView.moveContext`.
    ///
    /// **What a drag under a non-`order` sort rewrites, decided (T-884).**
    ///
    /// This sorts `scopeTasks` by `order` and renumbers *that*. `ListTasksView.reorderTask` used to
    /// renumber the **displayed** order instead — the tab's active sort plus its hover freeze — so
    /// one gesture meant two different things depending on which screen it was made on. Both
    /// spellings were preserved exactly as found when T-869 gave them commits; T-884 is the ticket
    /// that had to choose. Four sites now agree on this one, and here is why it is this one:
    ///
    /// - **`order` is the *custom* arrangement, and it is the only sequence in this app a user
    ///   authors.** `TaskOrdering.precedes` sorts by it outright under `.custom` and uses it only
    ///   as a tie-break under `.date` and `.priority`. So a drag made while the screen is sorted by
    ///   date is not a statement about the sequence on screen: that sequence comes from dates,
    ///   which the drag does not touch.
    /// - **Renumbering the display writes a derived sequence over an authored one.** One drag under
    ///   a date sort would replace the user's whole hand-made arrangement with the date order —
    ///   silently, and invisibly, because the screen is not showing `order` at the time. They find
    ///   out the next time they switch back to Custom, with nothing to undo. That is the same class
    ///   of defect as T-870 and T-885, not a smaller one.
    /// - **The cost of choosing this way is real and is smaller.** Under a date sort the dragged
    ///   row lands somewhere the user cannot see, so the gesture looks like it did nothing. But the
    ///   row springs back on screen under *either* rule — the list re-sorts by date the moment the
    ///   drop lands — so the visible outcome is identical, and only the other rule also destroys
    ///   something. And this one is exactly recoverable: drag again under Custom.
    /// - **The repo had already decided the freeze half.** `TaskListKanbanColumn.moveTask` states
    ///   that "the hover freeze is a display-only concern and must never be what gets written back
    ///   into `order`". The active sort is the same kind of thing — a view over the tasks, not an
    ///   arrangement anybody made.
    ///
    /// **Whether the drag should be *offered* at all under a non-custom sort was left open here and
    /// is settled (T-1054): it is offered, under every sort.** The refusal that ticket proposed
    /// rests on the premise that the dragged row always springs back, and T-1077 measured that
    /// false — inside a tie band the displayed sequence *is* the `order` sequence. What each
    /// surface does instead is ask `CadenceReorderVisibility` per drop and name the minority case.
    ///
    /// **`scopeTasks` is a slice and `spanTasks` is not, which is [[T-1175]].**
    /// `CadenceOrderCommit.commit` says a renumber must span the whole sequence, and every row
    /// surface used to hand it a group or a tab: T-1055 measured what that cost in
    /// `CadenceRowReorderSliceSpanTests` — rows of **one list** left holding the same `order`, and
    /// a drag made on Today moving rows on that list's Tasks tab the user never touched. The two
    /// arrays are two different questions and neither can be dropped. `scopeTasks` is what the user
    /// was looking at, so it is what "put this row above that one" means; `spanTasks` is where the
    /// numbers are allowed to go, so it is what gets written. `CadenceRowReorderSpan.wholeSequence`
    /// puts them together, and the rows `scopeTasks` does not hold keep their places inside it.
    ///
    /// **What *is* decided is how much of that sequence a drop writes ([[T-1119]]), and it is why
    /// this renumbers `CadenceRowReorderSpan.ownListSiblings` rather than the whole group.** On All
    /// Tasks and Inbox a section is drawn from several lists, and a drop used to renumber all of
    /// them from 0 — rewriting the arrangement of lists the user was not dragging in. Asked what a
    /// cross-list drag should do, the repository owner answered, verbatim: *"Reorder within its own
    /// list only."* Rows of every other list now come out of the drop holding exactly the `order`
    /// they went in with; the rule, and the reason `nil` is success rather than a refusal, are on
    /// that type.
    ///
    /// **It costs nothing on the surfaces that never cross a list.** Today's groups, a list's Tasks
    /// tab and both kanban columns are one container each, so the filter is the identity there —
    /// which is what lets this be one rule at one site rather than a cross-list special case bolted
    /// onto the one panel that has one.
    ///
    /// - Parameter spanTasks: the widest set of rows the surface knows about — the page's whole
    ///   `@Query`, or a list detail's own `tasks`. It is filtered to the dragged row's list here, so
    ///   a caller does not have to work out which container it is dropping into, and it is **not**
    ///   defaulted: a surface that passed its slice twice would silently reinstate the defect, and
    ///   a defaulted argument is exactly the kind of check that stops matching its population
    ///   without failing.
    /// - Parameter commit: How to commit. Defaults to `ModelContext.save()`; it is a parameter
    ///   because a `save()` that throws cannot be provoked out of an in-memory container.
    /// - Returns: Whether the new order is in the store. `false` means every row is back where it
    ///   was, and the panel must show `CadenceOrderCommit.failureNotice`. A drop with nothing to
    ///   write answers `true`, because nothing failed.
    ///
    /// **The body is `CadenceTaskRowReorder.reorderTask`'s since [[T-16682]]**, in `Shared/`, so
    /// iOS's list Tasks tab renumbers a row dropped on a heading through this same rule.
    static func reorderTask(
        droppedID: UUID,
        targetID: UUID,
        scopeTasks: [AppTask],
        spanTasks: [AppTask],
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        CadenceTaskRowReorder.reorderTask(
            droppedID: droppedID,
            targetID: targetID,
            scopeTasks: scopeTasks,
            spanTasks: spanTasks,
            modelContext: modelContext,
            commit: commit
        )
    }

    // **The assign half lives in `Shared/` now ([[T-16654]])**, on `CadenceTaskHeaderDrop`, so the
    // iPhone and iPad headings re-file a dragged row through the same parse, resolve and one commit
    // the Mac's do. These three keep the names every Mac caller and test already spells.

    /// See `CadenceTaskHeaderDrop.assignTask`.
    @discardableResult
    static func assignTask(
        _ task: AppTask,
        for dropKey: String,
        todayKey: String,
        areas: [Area],
        projects: [Project],
        modelContext: ModelContext,
        reconciler: CadenceWindDownReconciler? = nil,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> TasksPanelDropOutcome {
        CadenceTaskHeaderDrop.assignTask(
            task,
            for: dropKey,
            todayKey: todayKey,
            areas: areas,
            projects: projects,
            modelContext: modelContext,
            reconciler: reconciler,
            commit: commit
        )
    }

    /// See `CadenceTaskHeaderDrop.dropAssignments(forDropKey:)`.
    static func dropAssignments(forDropKey dropKey: String) -> [TasksPanelDropAssignment] {
        CadenceTaskHeaderDrop.dropAssignments(forDropKey: dropKey)
    }

    /// See `CadenceTaskHeaderDrop.pushedToScheduledDateKey(from:todayKey:calendar:)`.
    static func pushedToScheduledDateKey(
        from scheduledDate: String,
        todayKey: String,
        calendar: Calendar = .current
    ) -> String? {
        CadenceTaskHeaderDrop.pushedToScheduledDateKey(from: scheduledDate, todayKey: todayKey, calendar: calendar)
    }
}
#endif
