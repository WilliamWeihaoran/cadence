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
            // The four buckets macOS's `TasksPanelDerivedState` shows on Today, in the same order:
            // due today, past due, do today, and — the one this used to omit — *past do*. A task
            // planned for yesterday and never finished is still today's work; it was appearing
            // nowhere on iPad while macOS listed it under "Past Do" and offered the rollover
            // banner for it.
            //
            // Those four conditions were spelled out here. They are `AppTask.isTodayWork` now, in
            // `Models/`, because the widget target compiles `Models/` and **not** `Shared/`: it
            // could not call this, so it kept a second and narrower copy, which is T-353. Do not
            // re-inline the predicate.
            .filter { $0.isTodayWork(todayKey: todayKey) }
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

    /// Today's groups, on both platforms: **Overdue, and then the day's work by list** (T-305).
    ///
    /// This replaced a four-way split by date intent — Overdue, Past Do, Due Today, Planned Today.
    /// Three things were wrong with it, and the user named all three:
    ///
    /// 1. "Planned Today" restates the page. On the Today view everything is today, so the heading
    ///    carried no information — the standing rule that a page header does not describe the page
    ///    you are already on, applied one level down.
    /// 2. Today was the only task surface grouped by *when*; every other one groups by list, and
    ///    the `PAST DUE LISTS` cards directly above these groups are list-shaped too. One page,
    ///    two grouping axes.
    /// 3. A rolled-over task moved from one date bucket to another, which looked like nothing had
    ///    happened. It now leaves the red section and joins its list, which is what makes the roll
    ///    visible.
    ///
    /// **Overdue stays at the top and stays date-shaped**, deliberately: a missed deadline is a
    /// fact about the day that outranks where the work lives, and it is the one thing on Today
    /// worth pulling out of its list. Everything else — due today, do today, and yesterday's plans
    /// once they have been rolled — falls into its list's group.
    ///
    /// **The order inside a group is the caller's sort, untouched.** This partitions and never
    /// re-sorts: both hosts hand in an array already ordered by `activeTodayTasks` (iOS) or
    /// `compareTasksForCurrentSort` (macOS), and both of those lead with a today-rank, so a list
    /// group reads due-today before merely-do-today without needing a heading to say so. That rank
    /// is where the deleted axis went; it is a sort now instead of four headings.
    ///
    /// `contexts` is only for the order of the list groups — see `listGroupOrder(contexts:)`.
    static func todayGroups(
        from tasks: [AppTask],
        todayKey: String,
        contexts: [Context]
    ) -> [CadenceTodayTaskGroup] {
        let overdue = tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        let overdueIDs = Set(overdue.map(\.id))

        var groups: [CadenceTodayTaskGroup] = []
        if !overdue.isEmpty {
            groups.append(
                CadenceTodayTaskGroup(
                    identity: .overdue,
                    title: CadenceTodayPresentationSupport.overdueSectionTitle,
                    accent: CadenceTodayPresentationSupport.overdueSectionAccent,
                    listIcon: nil,
                    contextIcon: nil,
                    contextColor: nil,
                    tasks: overdue
                )
            )
        }

        groups.append(
            contentsOf: todayListGroups(
                from: tasks.filter { !overdueIDs.contains($0.id) },
                contexts: contexts
            )
        )
        return groups
    }

    /// The day's remaining work, one group per list, in the sidebar's order.
    ///
    /// **A task with no list gets the Inbox group, and the Inbox group sits first.** That is not a
    /// new answer invented for Today: `TasksPanelSupport.listGroups`, the Kanban board's first
    /// column, `CadenceBoardCardMetadata.inboxLabel` and the sidebar's top row all already call an
    /// unfiled task's home "Inbox", with `tray.fill` and a neutral tint, and `listGroupOrder`
    /// leads with it. The alternative considered was a nameless bucket at the foot of the page —
    /// which is "Planned Today" again in everything but the label, a group defined by what it is
    /// *not*, on the page whose whole complaint was a heading that carried no information. Inbox is
    /// also a real destination, so this group can accept a dropped `+`; a tail bucket could not.
    static func todayListGroups(
        from tasks: [AppTask],
        contexts: [Context]
    ) -> [CadenceTodayTaskGroup] {
        var tasksByKey: [String: [AppTask]] = [:]
        var firstTaskByKey: [String: AppTask] = [:]
        for task in tasks {
            let key = listGroupKey(for: task)
            tasksByKey[key, default: []].append(task)
            if firstTaskByKey[key] == nil { firstTaskByKey[key] = task }
        }

        let shells = firstTaskByKey.mapValues { listGroupShell(for: $0) }
        let ordered = listGroupOrder(contexts: contexts).filter { tasksByKey[$0] != nil }
        let orderedSet = Set(ordered)
        // A list whose context was archived, or which arrived from CloudKit before its context
        // did, is reachable from a task and not from `contexts`. Sorted by the name the header
        // will actually print, then by key, so the tail is stable rather than in `Dictionary`
        // order.
        let leftovers = tasksByKey.keys
            .filter { !orderedSet.contains($0) }
            .sorted { lhs, rhs in
                let lhsTitle = shells[lhs]?.title ?? ""
                let rhsTitle = shells[rhs]?.title ?? ""
                if lhsTitle != rhsTitle {
                    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                }
                return lhs < rhs
            }

        return (ordered + leftovers).compactMap { key in
            guard let shell = shells[key], let groupTasks = tasksByKey[key] else { return nil }
            return CadenceTodayTaskGroup(
                identity: shell.identity,
                title: shell.title,
                accent: shell.accent,
                listIcon: shell.listIcon,
                contextIcon: shell.contextIcon,
                contextColor: shell.contextColor,
                tasks: groupTasks
            )
        }
    }

    /// Which list a task is grouped under, in the one spelling this app has for that string.
    ///
    /// **Project before area**, which is `CadenceTaskDropSupport.listKey(for:)`'s rule and its
    /// reason: `TaskCreationService` leaves a project task's `area` nil, so a row holding both has
    /// been repaired into that state and the more specific container is where the UI already shows
    /// it. The key itself comes from `CadenceTaskDropSupport.containerKey(for:)` rather than being
    /// re-spelled, so a group's id and the drop key its header offers cannot drift apart.
    static func listGroupKey(for task: AppTask) -> String {
        if let project = task.project {
            return CadenceTaskDropSupport.containerKey(for: .project(project.id))
        }
        if let area = task.area {
            return CadenceTaskDropSupport.containerKey(for: .area(area.id))
        }
        return CadenceTaskDropSupport.containerKey(for: .inbox)
    }

    /// Every list key in sidebar order, Inbox first — the order any by-list grouping presents its
    /// groups in. `TasksPanelSupport.listGroups` reads this one too, so All Tasks' by-list mode and
    /// Today's groups cannot come out in different orders.
    static func listGroupOrder(contexts: [Context]) -> [String] {
        var order: [String] = [CadenceTaskDropSupport.containerKey(for: .inbox)]
        for context in contexts.sorted(by: { $0.order < $1.order }) {
            let sortedAreas = (context.areas ?? []).sorted { $0.order < $1.order }
            let sortedProjects = (context.projects ?? []).sorted { $0.order < $1.order }
            order.append(contentsOf: sortedAreas.map { CadenceTaskDropSupport.containerKey(for: .area($0.id)) })
            order.append(contentsOf: sortedProjects.map { CadenceTaskDropSupport.containerKey(for: .project($0.id)) })
        }
        return order
    }

    /// A list group with no tasks in it yet: everything the header draws, read off one member.
    private static func listGroupShell(for task: AppTask) -> CadenceTodayTaskGroup {
        if let project = task.project {
            return CadenceTodayTaskGroup(
                identity: .list(key: CadenceTaskDropSupport.containerKey(for: .project(project.id))),
                title: project.name,
                accent: Color(hex: project.colorHex),
                listIcon: project.icon,
                contextIcon: project.context?.icon,
                contextColor: project.context.map { Color(hex: $0.colorHex) },
                tasks: []
            )
        }
        if let area = task.area {
            return CadenceTodayTaskGroup(
                identity: .list(key: CadenceTaskDropSupport.containerKey(for: .area(area.id))),
                title: area.name,
                accent: Color(hex: area.colorHex),
                listIcon: area.icon,
                contextIcon: area.context?.icon,
                contextColor: area.context.map { Color(hex: $0.colorHex) },
                tasks: []
            )
        }
        return CadenceTodayTaskGroup(
            identity: .list(key: CadenceTaskDropSupport.containerKey(for: .inbox)),
            title: CadenceBoardCardMetadata.inboxLabel,
            accent: Theme.dim,
            listIcon: "tray.fill",
            contextIcon: nil,
            contextColor: nil,
            tasks: []
        )
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

    /// How urgent a task is *today*: past due, then past do, then due today, then do today.
    ///
    /// **Since T-305 this is the only thing that says so.** Today used to head those four states as
    /// four sections; it groups by list now, so the day's shape survives as the leading term of the
    /// sort inside each list rather than as headings above it.
    ///
    /// A due date outranks a do date, exactly as `todayGroups` and `dateBuckets` have it: `dueDate
    /// == todayKey` is tested *before* `scheduledDate < todayKey`, so a task due today and planned
    /// for yesterday reads as due-today.
    ///
    /// Internal rather than `private` for two reasons, and the second is the load-bearing one: so
    /// tests reach the copy production runs (the rule `dateBuckets` records), and so macOS's
    /// `TasksPanel.todayTaskSortRank` can *call* it. That method used to be a fourth spelling of
    /// this rank which disagreed with this one — it tested `scheduledDate < todayKey` before
    /// `dueDate == todayKey`, so the two platforms ordered a task due today and do-dated yesterday
    /// differently, on the same day, from the same data.
    ///
    /// The four branches themselves moved to `AppTask.todayStanding(todayKey:)` under T-353, for
    /// the reason given there: `Shared/` is not compiled into `CadenceWidgets`, so the widget's
    /// rank could not call this one and was a *fifth* spelling, missing the past-do branch
    /// outright. This is the same rank it always was; it is no longer the only copy of it because
    /// it is no longer a copy.
    static func todayRank(_ task: AppTask, todayKey: String) -> Int {
        task.todayRank(todayKey: todayKey)
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
            let leftDate = TaskOrdering.dateSortKey(lhs.scheduledDate)
            let rightDate = TaskOrdering.dateSortKey(rhs.scheduledDate)
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
    /// `TaskSortHelpers`, and what kept this type's own `sortDateKey` twin of
    /// `TaskOrdering.dateSortKey` out of the five-file sweep that consolidated the rest (T-640).
    /// That file is gone (T-639) and so is the twin.
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
}
