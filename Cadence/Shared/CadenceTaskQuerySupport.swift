import Foundation
import SwiftUI

enum CadenceTaskQuerySupport {
    // `isInActiveContainer` is a property on `AppTask` (in `Models/`, which every target compiles,
    // unlike `Shared/`). There is deliberately no free-function wrapper here: passing a
    // main-actor-isolated static method *reference* to `filter` strips its isolation and warns,
    // which is exactly what the wrapper caused at three call sites. Use `filter(\.isInActiveContainer)`.

    static func activeTodayTasks(
        from tasks: [AppTask],
        todayKey: String,
        sortMode: CadenceTaskSortMode
    ) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isDone && !task.isCancelled else { return false }
                // The four buckets macOS's `TasksPanelDerivedState` shows on Today, in the same
                // order: due today, past due, do today, and — the one this used to omit — *past
                // do*. A task planned for yesterday and never finished is still today's work; it
                // was appearing nowhere on iPad while macOS listed it under "Past Do" and offered
                // the rollover banner for it.
                return task.dueDate == todayKey ||
                    !task.dueDate.isEmpty && task.dueDate < todayKey ||
                    task.scheduledDate == todayKey ||
                    !task.scheduledDate.isEmpty && task.scheduledDate < todayKey
            }
            .sorted { sortTodayTasks($0, $1, todayKey: todayKey, sortMode: sortMode) }
    }

    /// Today's Completed section — including cancelled work. `isFinishedTask` carries the whole
    /// account of why; the three `completed*` queries below are its only callers on this surface.
    ///
    /// **The predicate is "settled inside today's calendar day", and nothing else — on both
    /// platforms.** It used to admit finished work on two further grounds, `scheduledDate ==
    /// todayKey` or `dueDate == todayKey`, tested *before* `completedAt` ever came up. So a task
    /// finished in January and do-dated today was listed under a heading reading "Completed
    /// Today" and counted into the day's "N done" summary, on a day nothing had been finished
    /// (T-229). Those two grounds are original iOS code that no decision ever chose: macOS's
    /// `TasksPanelDerivedState` has never had them, and `completedSectionTitle`'s own doc comment
    /// justified unifying the two headings on the claim that both sat "over the same predicate —
    /// `completedAt` inside today, on both", which was false when it was written.
    ///
    /// macOS calls **this** now (`TasksPanelDerivedState`, `.todayOverview`), so there is one
    /// predicate rather than two that agree by inspection.
    ///
    /// Nothing became unreachable. Every settled transition records the timestamp — `markDone`,
    /// `markCancelled`, `TaskContainerLifecycleService`, and the completion animation's
    /// context-less fallback — and `normalizeCompletionState` preserves whatever a settled status
    /// was given (T-213). Work settled on another day is still listed by `completedTasks`,
    /// `completedInboxTasks` and the list logbook, none of which test a date; what a legacy
    /// nil-stamp row loses is a place on *today's* page, which is the only place it was never
    /// entitled to.
    static func completedTodayTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        // Built once, not once per candidate: `DateFormatters.dateKey(from:)` was being called for
        // every completed task the user has ever created, on every rebuild.
        let todayRange = calendarDayRange(for: todayKey)
        return tasks
            .filter { task in
                guard isFinishedTask(task), let completedAt = task.completedAt else { return false }
                guard let todayRange else {
                    // Unreachable in practice (`todayKey` is produced by the same formatter);
                    // keep the per-task comparison as the safety net.
                    return DateFormatters.dateKey(from: completedAt) == todayKey
                }
                return todayRange.contains(completedAt)
            }
            .taskCompletionSorted()
    }

    /// The half-open span of instants belonging to the calendar day `dateKey` names, or `nil` if it
    /// does not parse. `dateKey(from:) == dateKey` is exactly `range.contains(_:)` for the calendar
    /// the key came from, so this is a form of the same test that costs one date formatting per
    /// query instead of one per task.
    ///
    /// `startOfDay` on **both** ends rather than `dayStart + 1 day`, so a DST day whose midnight
    /// does not exist still ends on tomorrow's real first instant.
    static func calendarDayRange(for dateKey: String, calendar: Calendar = .current) -> Range<Date>? {
        guard let parsed = DateFormatters.date(from: dateKey) else { return nil }
        let dayStart = calendar.startOfDay(for: parsed)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return dayStart..<calendar.startOfDay(for: nextDay)
    }

    /// The same four sections macOS's `todayDateSections` draws, in the same order. A due date
    /// outranks a do date, so a task is only ever considered for `pastDo` once both due buckets
    /// have passed on it.
    static func todayGroups(from tasks: [AppTask], todayKey: String) -> [CadenceTodayTaskGroup] {
        let overdue = tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        let dueToday = tasks.filter { $0.dueDate == todayKey }
        let claimedIDs = Set(overdue.map(\.id)).union(dueToday.map(\.id))
        let remaining = tasks.filter { !claimedIDs.contains($0.id) }

        return [
            CadenceTodayTaskGroup(kind: .overdue, tasks: overdue),
            CadenceTodayTaskGroup(
                kind: .pastDo,
                tasks: remaining.filter { !$0.scheduledDate.isEmpty && $0.scheduledDate < todayKey }
            ),
            CadenceTodayTaskGroup(kind: .dueToday, tasks: dueToday),
            CadenceTodayTaskGroup(
                kind: .plannedToday,
                tasks: remaining.filter { $0.scheduledDate.isEmpty || $0.scheduledDate >= todayKey }
            )
        ]
        .filter { !$0.tasks.isEmpty }
    }

    static func activeInboxTasks(from tasks: [AppTask], sortMode: CadenceTaskSortMode) -> [AppTask] {
        tasks
            .filter { $0.area == nil && $0.project == nil && !$0.isDone && !$0.isCancelled }
            .sorted { sortTasks($0, $1, sortMode: sortMode) }
    }

    static func completedInboxTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks
            .filter { $0.area == nil && $0.project == nil && isFinishedTask($0) }
            .taskCompletionSorted()
    }

    static func activeTasks(
        from tasks: [AppTask],
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> [AppTask] {
        tasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { sortTasks($0, $1, sortMode: sortMode, sectionNames: sectionNames) }
    }

    static func completedTasks(from tasks: [AppTask]) -> [AppTask] {
        tasks
            .filter { isFinishedTask($0) }
            .taskCompletionSorted()
    }

    static func sortedTasks(
        _ tasks: [AppTask],
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> [AppTask] {
        tasks.sorted { sortTasks($0, $1, sortMode: sortMode, sectionNames: sectionNames) }
    }

    /// A list's tasks, split into its columns.
    ///
    /// **`includingEmpty` is what makes an empty column reachable.** Dropping the empty ones is
    /// right for a surface that only *reads* — a heading over no rows says nothing — and wrong for
    /// one you can add to: `CadenceTaskDropSupport.showsWhenEmpty(_:)` says a group you can still
    /// add to does not vanish when it empties, and names an unfilled kanban column as the case it
    /// exists for. That rule could never fire on the iOS list detail, because this function had
    /// already discarded the column before the component got to apply it. The flag defaults off so
    /// the macOS grouping modes, which have no such drop, keep the shape they had.
    static func sectionGroups(
        from tasks: [AppTask],
        sectionNames: [String],
        includingEmpty: Bool = false
    ) -> [CadenceTaskDisplayGroup] {
        sectionNames.compactMap { sectionName in
            let sectionTasks = tasks.filter {
                $0.resolvedSectionName.caseInsensitiveCompare(sectionName) == .orderedSame
            }
            guard includingEmpty || !sectionTasks.isEmpty else { return nil }
            return CadenceTaskDisplayGroup(
                id: "section-\(sectionName.lowercased())",
                title: sectionName,
                accent: Theme.blue,
                tasks: sectionTasks
            )
        }
    }

    static func dateDisplayGroups(
        from tasks: [AppTask],
        todayKey: String,
        includeDueToday: Bool = true
    ) -> [CadenceTaskDisplayGroup] {
        let buckets = dateBuckets(for: tasks, todayKey: todayKey)
        let overdue = tasks.filter { buckets.overdueIDs.contains($0.id) }
        let dueToday = tasks.filter { buckets.dueTodayIDs.contains($0.id) }
        let doToday = tasks.filter { buckets.doTodayIDs.contains($0.id) }
        let scheduled = tasks.filter {
            !$0.scheduledDate.isEmpty &&
            $0.scheduledDate != todayKey &&
            !buckets.contains($0)
        }
        let unscheduled = tasks.filter {
            $0.scheduledDate.isEmpty &&
            !buckets.contains($0)
        }

        var groups = [
            CadenceTaskDisplayGroup(id: "overdue", title: "Overdue", accent: Theme.red, tasks: overdue)
        ]
        if includeDueToday {
            groups.append(CadenceTaskDisplayGroup(id: "due-today", title: "Due Today", accent: Theme.red.opacity(0.8), tasks: dueToday))
        }
        groups.append(contentsOf: [
            CadenceTaskDisplayGroup(id: "do-today", title: "Do Today", accent: Theme.blue, tasks: doToday),
            CadenceTaskDisplayGroup(id: "scheduled", title: "Scheduled", accent: Theme.dim, tasks: scheduled),
            CadenceTaskDisplayGroup(id: "unscheduled", title: "Unscheduled", accent: Theme.amber, tasks: unscheduled)
        ])

        return groups.filter { !$0.tasks.isEmpty }
    }

    // `planningDisplayGroups` used to sit here, bucketing a list's tasks into Overdue / Due Today /
    // Scheduled Today / Upcoming / Unscheduled for the iOS list-detail Planning tab. That tab is
    // gone, as macOS's was: the Calendar Board's Overdue and Unscheduled rails and its day columns
    // are where that bucketing lives now.

    static func priorityDisplayGroups(from tasks: [AppTask]) -> [CadenceTaskDisplayGroup] {
        TaskPriority.allCases.reversed().compactMap { priority in
            let priorityTasks = tasks.filter { $0.priority == priority }
            guard !priorityTasks.isEmpty else { return nil }
            return CadenceTaskDisplayGroup(
                id: "priority-\(priority.rawValue)",
                title: priority.label,
                accent: Theme.priorityColor(priority),
                tasks: priorityTasks,
                dropKey: "priority:\(priority.rawValue)"
            )
        }
    }

    static func nextTaskOrder(in tasks: [AppTask]) -> Int {
        (tasks.map(\.order).max() ?? -1) + 1
    }

    static func makeTask(
        title: String,
        allTasks: [AppTask],
        scheduledDate: String? = nil,
        estimatedMinutes: Int = 30
    ) -> AppTask? {
        var priority: TaskPriority = .none
        let trimmed = TaskTitleSupport.titleApplyingPriorityShortcut(title, priority: &priority)
        guard !trimmed.isEmpty else { return nil }

        let task = AppTask(title: trimmed)
        task.priority = priority
        task.estimatedMinutes = estimatedMinutes
        task.order = nextTaskOrder(in: allTasks)
        if let scheduledDate {
            task.scheduledDate = scheduledDate
        }
        return task
    }

    /// Free-function spelling of `TaskPriority.rank`, kept because several sort comparators here
    /// read better with it. The definition lives on the enum.
    static func priorityRank(_ priority: TaskPriority) -> Int { priority.rank }

    /// Mirrors the section order in `todayGroups` so a flat, un-grouped Today list still reads
    /// past due → past do → due today → do today.
    private static func todayRank(_ task: AppTask, todayKey: String) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if task.dueDate == todayKey { return 2 }
        if !task.scheduledDate.isEmpty && task.scheduledDate < todayKey { return 1 }
        if task.scheduledDate == todayKey { return 3 }
        return 4
    }

    private static func sortTodayTasks(
        _ lhs: AppTask,
        _ rhs: AppTask,
        todayKey: String,
        sortMode: CadenceTaskSortMode
    ) -> Bool {
        let leftRank = todayRank(lhs, todayKey: todayKey)
        let rightRank = todayRank(rhs, todayKey: todayKey)
        if leftRank != rightRank { return leftRank < rightRank }
        return sortTasks(lhs, rhs, sortMode: sortMode)
    }

    /// Every branch ends in `TaskOrdering.fallbackPrecedes`, never in a bare `order` comparison.
    ///
    /// `order` is assigned **per container** (`CadenceTaskMutationSupport.nextContainerOrder`), so
    /// on a cross-container surface — All Tasks, whose default mode is `.listOrder` — two tasks
    /// from different lists routinely share one. A comparator that stops there is a *partial*
    /// order: `sort` is free to return either arrangement, so the visible sequence is decided by
    /// whatever row order SwiftData happened to hand back, and the same list can come out
    /// differently between renders or between devices. macOS's `TaskOrdering` was given a total
    /// tie-break (`order` → `createdAt` → `title` → `id`) for exactly this reason and
    /// `TaskOrderingTests` pins it by sorting a tie-heavy set from two permutations and requiring
    /// byte-identical output. iOS spelled its own comparator and for a long time ended in a bare
    /// `order` comparison; `6277539` closed that, and `MobileTaskSortStabilityTests` pins this
    /// comparator the same way — same set, two starting permutations, identical output required.
    /// The two spellings still differ in vocabulary (`CadenceTaskSortMode` has no sort *direction*
    /// and a different case set), but not in the tie-break. This comment used to end "iOS … never
    /// got that. This is the remaining half of that consolidation", directly above five branches
    /// that already called `fallbackPrecedes` — do not pick that up as outstanding work.
    static func sortTasks(
        _ lhs: AppTask,
        _ rhs: AppTask,
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> Bool {
        switch sortMode {
        case .listOrder:
            if let sectionNames, lhs.resolvedSectionName != rhs.resolvedSectionName {
                return sectionRank(lhs.resolvedSectionName, in: sectionNames) < sectionRank(rhs.resolvedSectionName, in: sectionNames)
            }
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
        case .priority:
            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
            }
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
        case .doDate:
            let leftDate = sortDateKey(lhs.scheduledDate)
            let rightDate = sortDateKey(rhs.scheduledDate)
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            let leftTimed = lhs.scheduledStartMin >= 0
            let rightTimed = rhs.scheduledStartMin >= 0
            if leftTimed != rightTimed {
                return leftTimed
            }
            if leftTimed && lhs.scheduledStartMin != rhs.scheduledStartMin {
                return lhs.scheduledStartMin < rhs.scheduledStartMin
            }
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
        case .dueDate:
            if lhs.dueDate != rhs.dueDate {
                if lhs.dueDate.isEmpty { return false }
                if rhs.dueDate.isEmpty { return true }
                return lhs.dueDate < rhs.dueDate
            }
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
        case .newest:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return TaskOrdering.fallbackPrecedes(lhs, rhs)
        }
    }

    /// The one date-bucketing rule: due-before-today wins, then due-today, and only tasks in
    /// neither due bucket can be "do today". Internal rather than `private` so tests reach the
    /// copy production runs — a `private` spelling here is what kept a dead twin alive in
    /// `TaskSortHelpers`.
    static func dateBuckets(for tasks: [AppTask], todayKey: String) -> CadenceTaskDateBuckets {
        var overdueIDs = Set<UUID>()
        var dueTodayIDs = Set<UUID>()
        var doTodayIDs = Set<UUID>()

        for task in tasks {
            if !task.dueDate.isEmpty && task.dueDate < todayKey {
                overdueIDs.insert(task.id)
            } else if task.dueDate == todayKey {
                dueTodayIDs.insert(task.id)
            }
        }

        for task in tasks where !overdueIDs.contains(task.id) && !dueTodayIDs.contains(task.id) {
            if task.scheduledDate == todayKey {
                doTodayIDs.insert(task.id)
            }
        }

        return CadenceTaskDateBuckets(
            overdueIDs: overdueIDs,
            dueTodayIDs: dueTodayIDs,
            doTodayIDs: doTodayIDs
        )
    }

    private static func sectionRank(_ name: String, in sectionNames: [String]) -> Int {
        sectionNames.firstIndex {
            $0.caseInsensitiveCompare(name) == .orderedSame
        } ?? Int.max
    }

    private static func sortDateKey(_ dateKey: String) -> String {
        dateKey.isEmpty ? "9999-99-99" : dateKey
    }
}
