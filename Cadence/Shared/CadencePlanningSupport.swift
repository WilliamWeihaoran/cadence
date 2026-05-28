import Foundation
import SwiftData
import SwiftUI

enum CadenceTaskSortMode: String, CaseIterable, Hashable, Identifiable {
    case listOrder
    case priority
    case dueDate
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listOrder: return "List Order"
        case .priority: return "Priority"
        case .dueDate: return "Due Date"
        case .newest: return "Newest"
        }
    }
}

enum CadenceCoreNoteTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case notepad = "Notepad"

    var id: Self { self }

    var compactTitle: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .notepad: return "Notepad"
        }
    }

    var subtitle: String {
        switch self {
        case .today:
            guard let today = DateFormatters.date(from: DateFormatters.todayKey()) else {
                return "Today"
            }
            return DateFormatters.longDate.string(from: today)
        case .week:
            return DateFormatters.weekLabel(from: DateFormatters.currentWeekKey())
        case .notepad:
            return "Permanent notes"
        }
    }
}

struct CadenceCoreNoteState {
    var today: Note?
    var week: Note?
    var notepad: Note?

    func note(for tab: CadenceCoreNoteTab) -> Note? {
        switch tab {
        case .today: return today
        case .week: return week
        case .notepad: return notepad
        }
    }
}

enum CadenceCoreNoteSupport {
    static func loadOrCreateCoreNotes(in modelContext: ModelContext) -> CadenceCoreNoteState {
        CadenceCoreNoteState(
            today: try? NoteMigrationService.dailyNote(for: DateFormatters.todayKey(), in: modelContext),
            week: try? NoteMigrationService.weeklyNote(for: DateFormatters.currentWeekKey(), in: modelContext),
            notepad: try? NoteMigrationService.permanentNote(in: modelContext)
        )
    }

    static func note(for tab: CadenceCoreNoteTab, in modelContext: ModelContext) throws -> Note {
        switch tab {
        case .today:
            return try NoteMigrationService.dailyNote(for: DateFormatters.todayKey(), in: modelContext)
        case .week:
            return try NoteMigrationService.weeklyNote(for: DateFormatters.currentWeekKey(), in: modelContext)
        case .notepad:
            return try NoteMigrationService.permanentNote(in: modelContext)
        }
    }

    static func update(_ note: Note, content: String, in modelContext: ModelContext, syncTags: Bool = true) {
        note.content = content
        note.updatedAt = Date()
        if syncTags {
            TagSupport.syncNoteTagsFromMarkdown(note, in: modelContext)
        }
        try? modelContext.save()
    }
}

enum CadenceListNoteSupport {
    static func notes(for area: Area?, project: Project?, in notes: [Note]) -> [Note] {
        if let area {
            return notes.filter { $0.kind == .list && $0.area?.id == area.id }
        }
        if let project {
            return notes.filter { $0.kind == .list && $0.project?.id == project.id }
        }
        return []
    }

    static func firstOrCreateNote(for area: Area?, project: Project?, in modelContext: ModelContext) -> Note? {
        let descriptor = FetchDescriptor<Note>()
        let fetchedNotes = (try? modelContext.fetch(descriptor)) ?? []
        if let existing = notes(for: area, project: project, in: fetchedNotes).first {
            return existing
        }

        guard area != nil || project != nil else { return nil }
        let created = Note(kind: .list, title: defaultTitle(for: area, project: project))
        attach(created, to: area, project: project)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    static func attach(_ note: Note, to area: Area?, project: Project?) {
        note.area = area
        note.project = project
    }

    static func defaultTitle(for area: Area?, project: Project?) -> String {
        area?.name ?? project?.name ?? "Untitled Note"
    }
}

enum CadenceTodayTaskGroupKind: String, CaseIterable, Hashable {
    case overdue
    case dueToday
    case plannedToday

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueToday: return "Due Today"
        case .plannedToday: return "Planned Today"
        }
    }
}

enum CadenceCalendarViewMode: String, CaseIterable, Hashable {
    case week = "Week"
    case twoWeeks = "2 Weeks"
    case month = "Month"

    var daysCount: Int {
        switch self {
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 1
        }
    }
}

enum CadenceCalendarPresentation: String, CaseIterable, Hashable {
    case timeline = "Timeline"
    case board = "Board"
}

enum CadenceCalendarBoardMarkerKind: Hashable {
    case task
    case event
}

struct CadenceCalendarBoardMarker: Identifiable {
    let id: String
    let kind: CadenceCalendarBoardMarkerKind
    let color: Color
    let isCompleted: Bool
    let count: Int
}

struct CadenceCalendarBoardDaySummary: Identifiable {
    let dateKey: String
    let taskMarkers: [CadenceCalendarBoardMarker]
    let eventMarkers: [CadenceCalendarBoardMarker]
    let bundleCount: Int
    let overflowCount: Int

    var id: String { dateKey }

    var totalCount: Int {
        taskMarkers.reduce(0) { $0 + $1.count } + eventMarkers.count + bundleCount + overflowCount
    }
}

enum CadenceCalendarBoardSupport {
    static func monthSummaries(
        monthDate: Date,
        tasksByDate: [String: [AppTask]],
        bundlesByDate: [String: [TaskBundle]],
        calendar: Calendar = .current,
        eventMarkers: (Date, String) -> [CadenceCalendarBoardMarker] = { _, _ in [] }
    ) -> [String: CadenceCalendarBoardDaySummary] {
        var summaries: [String: CadenceCalendarBoardDaySummary] = [:]
        summaries.reserveCapacity(42)

        for date in CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar) {
            let key = DateFormatters.dateKey(from: date)
            summaries[key] = daySummary(
                dateKey: key,
                tasks: CadenceScheduleSupport.items(on: key, in: tasksByDate),
                bundles: CadenceScheduleSupport.items(on: key, in: bundlesByDate),
                eventMarkers: eventMarkers(date, key)
            )
        }

        return summaries
    }

    static func daySummary(
        dateKey: String,
        tasks: [AppTask],
        bundles: [TaskBundle],
        eventMarkers: [CadenceCalendarBoardMarker] = [],
        maxTaskMarkers: Int = 4,
        maxEventMarkers: Int = 5,
        maxBundleMarkers: Int = 1
    ) -> CadenceCalendarBoardDaySummary {
        let sortedTasks = CadenceTaskQuerySupport.sortedTasks(
            tasks.filter { !$0.isCancelled },
            sortMode: .priority
        )
        let taskGroups = taskGroupMarkers(from: sortedTasks)
        let visibleTaskGroups = Array(taskGroups.prefix(max(0, maxTaskMarkers)))
        let visibleEvents = Array(eventMarkers.prefix(max(0, maxEventMarkers)))
        let visibleBundleCount = min(max(0, maxBundleMarkers), bundles.count)
        let hiddenTaskCount = taskGroups.dropFirst(visibleTaskGroups.count).reduce(0) { $0 + $1.count }
        let hiddenEventCount = max(0, eventMarkers.count - visibleEvents.count)
        let hiddenBundleCount = max(0, bundles.count - visibleBundleCount)

        return CadenceCalendarBoardDaySummary(
            dateKey: dateKey,
            taskMarkers: visibleTaskGroups,
            eventMarkers: visibleEvents,
            bundleCount: visibleBundleCount,
            overflowCount: hiddenTaskCount + hiddenEventCount + hiddenBundleCount
        )
    }

    private static func taskGroupMarkers(from tasks: [AppTask]) -> [CadenceCalendarBoardMarker] {
        var groupOrder: [String] = []
        var groupedMarkers: [String: (color: Color, isCompleted: Bool, count: Int)] = [:]

        for task in tasks {
            let key = taskGroupKey(for: task)
            if groupedMarkers[key] == nil {
                groupOrder.append(key)
                groupedMarkers[key] = (Color(hex: task.containerColor), true, 0)
            }
            guard var marker = groupedMarkers[key] else { continue }
            marker.count += 1
            marker.isCompleted = marker.isCompleted && task.isDone
            groupedMarkers[key] = marker
        }

        return groupOrder.compactMap { key in
            guard let marker = groupedMarkers[key] else { return nil }
            return CadenceCalendarBoardMarker(
                id: key,
                kind: .task,
                color: marker.color,
                isCompleted: marker.isCompleted,
                count: marker.count
            )
        }
    }

    private static func taskGroupKey(for task: AppTask) -> String {
        if let area = task.area { return "area-\(area.id.uuidString)" }
        if let project = task.project { return "project-\(project.id.uuidString)" }
        return "inbox"
    }
}

struct CadenceTodayTaskGroup: Identifiable {
    let kind: CadenceTodayTaskGroupKind
    let tasks: [AppTask]

    var id: CadenceTodayTaskGroupKind { kind }
    var title: String { kind.title }
}

struct CadenceTaskDisplayGroup: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let tasks: [AppTask]
    let dropKey: String?

    init(
        id: String,
        title: String,
        accent: Color,
        tasks: [AppTask],
        dropKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.accent = accent
        self.tasks = tasks
        self.dropKey = dropKey
    }
}

struct CadenceTaskDateBuckets {
    let overdueIDs: Set<UUID>
    let dueTodayIDs: Set<UUID>
    let doTodayIDs: Set<UUID>

    func contains(_ task: AppTask) -> Bool {
        overdueIDs.contains(task.id) || dueTodayIDs.contains(task.id) || doTodayIDs.contains(task.id)
    }
}

enum CadenceTaskQuerySupport {
    static func activeTodayTasks(
        from tasks: [AppTask],
        todayKey: String,
        sortMode: CadenceTaskSortMode
    ) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isDone && !task.isCancelled else { return false }
                return task.scheduledDate == todayKey ||
                    task.dueDate == todayKey ||
                    (!task.dueDate.isEmpty && task.dueDate < todayKey)
            }
            .sorted { sortTodayTasks($0, $1, todayKey: todayKey, sortMode: sortMode) }
    }

    static func completedTodayTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks
            .filter { task in
                guard task.isDone && !task.isCancelled else { return false }
                if task.scheduledDate == todayKey || task.dueDate == todayKey { return true }
                if let completedAt = task.completedAt {
                    return DateFormatters.dateKey(from: completedAt) == todayKey
                }
                return false
            }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    static func todayGroups(from tasks: [AppTask], todayKey: String) -> [CadenceTodayTaskGroup] {
        [
            CadenceTodayTaskGroup(
                kind: .overdue,
                tasks: tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
            ),
            CadenceTodayTaskGroup(
                kind: .dueToday,
                tasks: tasks.filter { $0.dueDate == todayKey }
            ),
            CadenceTodayTaskGroup(
                kind: .plannedToday,
                tasks: tasks.filter { $0.dueDate != todayKey && !(!$0.dueDate.isEmpty && $0.dueDate < todayKey) }
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
            .filter { $0.area == nil && $0.project == nil && $0.isDone && !$0.isCancelled }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
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
            .filter { $0.isDone && !$0.isCancelled }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    static func sortedTasks(
        _ tasks: [AppTask],
        sortMode: CadenceTaskSortMode,
        sectionNames: [String]? = nil
    ) -> [AppTask] {
        tasks.sorted { sortTasks($0, $1, sortMode: sortMode, sectionNames: sectionNames) }
    }

    static func sectionGroups(from tasks: [AppTask], sectionNames: [String]) -> [CadenceTaskDisplayGroup] {
        sectionNames.compactMap { sectionName in
            let sectionTasks = tasks.filter {
                $0.resolvedSectionName.caseInsensitiveCompare(sectionName) == .orderedSame
            }
            guard !sectionTasks.isEmpty else { return nil }
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

    static func planningDisplayGroups(from tasks: [AppTask], todayKey: String) -> [CadenceTaskDisplayGroup] {
        let overdue = tasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }
        let dueToday = tasks.filter { $0.dueDate == todayKey }
        let scheduledToday = tasks.filter { $0.scheduledDate == todayKey && $0.dueDate != todayKey }
        let upcoming = tasks
            .filter { task in
                let dueFuture = !task.dueDate.isEmpty && task.dueDate > todayKey
                let scheduledFuture = !task.scheduledDate.isEmpty && task.scheduledDate > todayKey
                return dueFuture || scheduledFuture
            }
            .sorted { planningKey(for: $0) < planningKey(for: $1) }
        let unscheduled = tasks.filter { $0.dueDate.isEmpty && $0.scheduledDate.isEmpty }

        return [
            CadenceTaskDisplayGroup(id: "overdue", title: "Overdue", accent: Theme.red, tasks: overdue),
            CadenceTaskDisplayGroup(id: "due-today", title: "Due Today", accent: Theme.amber, tasks: dueToday),
            CadenceTaskDisplayGroup(id: "scheduled-today", title: "Scheduled Today", accent: Theme.blue, tasks: scheduledToday),
            CadenceTaskDisplayGroup(id: "upcoming", title: "Upcoming", accent: Theme.purple, tasks: upcoming),
            CadenceTaskDisplayGroup(id: "unscheduled", title: "Unscheduled", accent: Theme.dim, tasks: unscheduled)
        ]
        .filter { !$0.tasks.isEmpty }
    }

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

    static func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }

    private static func todayRank(_ task: AppTask, todayKey: String) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if task.dueDate == todayKey { return 1 }
        if task.scheduledDate == todayKey { return 2 }
        return 3
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

    private static func sortTasks(
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
            return lhs.order < rhs.order
        case .priority:
            if lhs.priority != rhs.priority {
                return priorityRank(lhs.priority) > priorityRank(rhs.priority)
            }
            return lhs.order < rhs.order
        case .dueDate:
            if lhs.dueDate != rhs.dueDate {
                if lhs.dueDate.isEmpty { return false }
                if rhs.dueDate.isEmpty { return true }
                return lhs.dueDate < rhs.dueDate
            }
            return lhs.order < rhs.order
        case .newest:
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func dateBuckets(for tasks: [AppTask], todayKey: String) -> CadenceTaskDateBuckets {
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

    private static func planningKey(for task: AppTask) -> String {
        [task.dueDate, task.scheduledDate]
            .filter { !$0.isEmpty }
            .min() ?? "9999-99-99"
    }

    private static func sectionRank(_ name: String, in sectionNames: [String]) -> Int {
        sectionNames.firstIndex {
            $0.caseInsensitiveCompare(name) == .orderedSame
        } ?? Int.max
    }
}

enum CadenceTaskMutationSupport {
    static func toggleCompletion(_ task: AppTask, modelContext: ModelContext) {
        if task.isDone {
            task.status = .todo
            task.completedAt = nil
        } else {
            task.status = .done
            task.completedAt = Date()
        }
        try? modelContext.save()
    }

    static func scheduleToday(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    static func scheduleTomorrow(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    static func clearScheduledDate(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = ""
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func delete(_ task: AppTask, modelContext: ModelContext) {
        let subtasks = task.subtasks ?? []
        task.subtasks = []
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }

        for subtask in subtasks {
            modelContext.delete(subtask)
        }

        modelContext.delete(task)
        try? modelContext.save()
    }

    static func insertTask(
        title: String,
        allTasks: [AppTask],
        modelContext: ModelContext,
        scheduledDate: String? = nil,
        configure: (AppTask) -> Void = { _ in }
    ) throws -> AppTask? {
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: title,
            allTasks: allTasks,
            scheduledDate: scheduledDate
        ) else { return nil }

        configure(task)
        modelContext.insert(task)
        do {
            try modelContext.save()
            return task
        } catch {
            modelContext.delete(task)
            throw error
        }
    }
}

enum CadenceScheduleSupport {
    static let calendarStartHour = 6
    static let calendarEndHour = 23

    static func tasks(on dateKey: String, from tasks: [AppTask], includeCompleted: Bool = true) -> [AppTask] {
        tasks
            .filter { task in
                guard !task.isCancelled else { return false }
                guard includeCompleted || !task.isDone else { return false }
                return task.scheduledDate == dateKey || task.dueDate == dateKey
            }
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func scheduledTasks(
        on dateKey: String,
        from tasks: [AppTask],
        includeCompleted: Bool = false,
        excludeBundled: Bool = false
    ) -> [AppTask] {
        tasks
            .filter {
                !$0.isCancelled &&
                (includeCompleted || !$0.isDone) &&
                (!excludeBundled || $0.bundle == nil) &&
                $0.scheduledDate == dateKey &&
                $0.scheduledStartMin >= 0
            }
            .sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
    }

    static func bundles(on dateKey: String, from bundles: [TaskBundle], includeCompleted: Bool = true) -> [TaskBundle] {
        bundles
            .filter { $0.dateKey == dateKey && (includeCompleted || !$0.isCompleted) }
            .sorted { $0.startMin < $1.startMin }
    }

    static func tasks(in hour: Int, from tasks: [AppTask]) -> [AppTask] {
        tasks.filter { $0.scheduledStartMin / 60 == hour }
    }

    static func bundles(in hour: Int, from bundles: [TaskBundle]) -> [TaskBundle] {
        bundles.filter { $0.startMin / 60 == hour }
    }

    static func itemCount(on dateKey: String, tasks: [AppTask], bundles: [TaskBundle]) -> Int {
        let taskCount = tasks.filter { !$0.isCancelled && ($0.scheduledDate == dateKey || $0.dueDate == dateKey) }.count
        let bundleCount = bundles.filter { $0.dateKey == dateKey }.count
        return taskCount + bundleCount
    }

    static func startOfWeek(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func dates(containing anchorDate: Date, mode: CadenceCalendarViewMode, calendar: Calendar = .current) -> [Date] {
        let start: Date
        switch mode {
        case .week, .twoWeeks:
            start = startOfWeek(containing: anchorDate, calendar: calendar)
        case .month:
            start = calendar.startOfDay(for: anchorDate)
        }

        return (0..<mode.daysCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    static func shiftedDate(_ date: Date, mode: CadenceCalendarViewMode, by value: Int, calendar: Calendar = .current) -> Date {
        switch mode {
        case .week:
            return calendar.date(byAdding: .day, value: value * 7, to: date) ?? date
        case .twoWeeks:
            return calendar.date(byAdding: .day, value: value * 14, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date) ?? date
        }
    }

    static func monthGridDays(for monthDate: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)?.start,
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let gridEnd = calendar.dateInterval(of: .weekOfMonth, for: lastDay)?.end
        else { return [] }

        var result: [Date] = []
        var cursor = gridStart
        while cursor < gridEnd {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }
        return result
    }

    static func calendarTitle(for anchorDate: Date, mode: CadenceCalendarViewMode, calendar: Calendar = .current) -> String {
        switch mode {
        case .month:
            return DateFormatters.monthYear.string(from: anchorDate)
        case .week, .twoWeeks:
            let days = dates(containing: anchorDate, mode: mode, calendar: calendar)
            guard let first = days.first, let last = days.last else {
                return DateFormatters.monthYear.string(from: anchorDate)
            }
            if calendar.isDate(first, equalTo: last, toGranularity: .month) {
                return "\(DateFormatters.monthAbbrev.string(from: first)) \(DateFormatters.dayNumber.string(from: first))-\(DateFormatters.dayNumber.string(from: last))"
            }
            return "\(DateFormatters.monthAbbrev.string(from: first)) \(DateFormatters.dayNumber.string(from: first)) - \(DateFormatters.monthAbbrev.string(from: last)) \(DateFormatters.dayNumber.string(from: last))"
        }
    }

    static func tasksByScheduledDate(_ tasks: [AppTask], includeCompleted: Bool = false) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil &&
            task.scheduledStartMin >= 0 &&
            !task.scheduledDate.isEmpty &&
            !task.isCancelled &&
            (includeCompleted || !task.isDone) {
            result[task.scheduledDate, default: []].append(task)
        }
        return result.mapValues { tasks in
            tasks.sorted {
                if $0.scheduledStartMin != $1.scheduledStartMin {
                    return $0.scheduledStartMin < $1.scheduledStartMin
                }
                return $0.order < $1.order
            }
        }
    }

    static func unscheduledTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil &&
            task.scheduledStartMin == -1 &&
            !task.scheduledDate.isEmpty &&
            !task.isCancelled &&
            !task.isDone {
            result[task.scheduledDate, default: []].append(task)
        }
        return result.mapValues { CadenceTaskQuerySupport.sortedTasks($0, sortMode: .priority) }
    }

    static func monthTasksByDate(_ tasks: [AppTask]) -> [String: [AppTask]] {
        var result: [String: [AppTask]] = [:]
        for task in tasks where task.bundle == nil && !task.isCancelled {
            if !task.scheduledDate.isEmpty {
                result[task.scheduledDate, default: []].append(task)
            } else if !task.dueDate.isEmpty {
                result[task.dueDate, default: []].append(task)
            }
        }
        return result.mapValues { CadenceTaskQuerySupport.sortedTasks($0, sortMode: .priority) }
    }

    static func bundlesByDate(_ bundles: [TaskBundle], includeCompleted: Bool = false) -> [String: [TaskBundle]] {
        var result: [String: [TaskBundle]] = [:]
        for bundle in bundles where includeCompleted || !bundle.isCompleted {
            result[bundle.dateKey, default: []].append(bundle)
        }
        return result.mapValues { $0.sorted { $0.startMin < $1.startMin } }
    }

    static func items<T>(on dateKey: String, in itemsByDate: [String: [T]]) -> [T] {
        itemsByDate[dateKey] ?? []
    }

    static func dueOnlyTasks(on dateKey: String, from tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.sortedTasks(
            tasks.filter {
                !$0.isCancelled &&
                !$0.isDone &&
                $0.dueDate == dateKey &&
                $0.scheduledDate != dateKey
            },
            sortMode: .priority
        )
    }

    static func calendarDayTasks(on dateKey: String, from tasks: [AppTask]) -> [AppTask] {
        CadenceTaskQuerySupport.sortedTasks(
            tasks.filter {
                !$0.isCancelled &&
                ($0.scheduledDate == dateKey || $0.dueDate == dateKey)
            },
            sortMode: .priority
        )
    }

    static func blockRange(startMinute: Int, fallbackDuration: Int) -> (start: Int, end: Int) {
        let start = max(calendarStartHour * 60, startMinute)
        let duration = max(15, fallbackDuration)
        let end = min(calendarEndHour * 60, start + duration)
        return (start, max(start + 15, end))
    }

    static func timeRangeLabel(startMinute: Int, endMinute: Int) -> String {
        TimeFormatters.timeRange(startMin: startMinute, endMin: endMinute)
    }
}

struct CadenceFocusTimerState: Hashable {
    var isRunning = false
    var startedAt: Date?
    var accumulatedSeconds = 0

    func elapsedSeconds(now: Date = Date()) -> Int {
        accumulatedSeconds + (isRunning ? Int(now.timeIntervalSince(startedAt ?? now)) : 0)
    }

    mutating func toggle(now: Date = Date()) {
        if isRunning {
            accumulatedSeconds = elapsedSeconds(now: now)
            startedAt = nil
            isRunning = false
        } else {
            startedAt = now
            isRunning = true
        }
    }

    mutating func reset() {
        isRunning = false
        startedAt = nil
        accumulatedSeconds = 0
    }
}

enum CadenceFocusSupport {
    static func readyTasks(from tasks: [AppTask], todayKey: String) -> [AppTask] {
        tasks
            .filter { !$0.isDone && !$0.isCancelled }
            .sorted { lhs, rhs in
                let lhsScore = focusScore(for: lhs, todayKey: todayKey)
                let rhsScore = focusScore(for: rhs, todayKey: todayKey)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    static func sidebarDetail(for task: AppTask, todayKey: String, fallback: String = "Ready") -> String {
        if task.scheduledDate == todayKey { return "Scheduled today" }
        if task.dueDate == todayKey { return "Due today" }
        if !task.containerName.isEmpty { return task.containerName }
        return fallback
    }

    static func clockDisplay(elapsedSeconds: Int) -> String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        let seconds = elapsedSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func logElapsedSeconds(_ seconds: Int, to task: AppTask) {
        let minutes = max(0, Int((Double(seconds) / 60.0).rounded()))
        guard minutes > 0 else { return }

        task.actualMinutes += minutes
        if let project = task.project {
            project.loggedMinutes += minutes
        } else if let area = task.area {
            area.loggedMinutes += minutes
        }
    }

    static func complete(_ task: AppTask, elapsedSeconds: Int, modelContext: ModelContext) {
        logElapsedSeconds(elapsedSeconds, to: task)
        task.status = .done
        task.completedAt = Date()
        try? modelContext.save()
    }

    private static func focusScore(for task: AppTask, todayKey: String) -> Int {
        var score = 0
        if task.scheduledDate == todayKey { score += 4 }
        if task.dueDate == todayKey { score += 3 }
        if !task.dueDate.isEmpty && task.dueDate < todayKey { score += 5 }
        score += CadenceTaskQuerySupport.priorityRank(task.priority)
        if task.actualMinutes == 0 { score += 1 }
        return score
    }
}

struct CadencePursuitSummary {
    let goals: [Goal]
    let habits: [Habit]

    var activeGoalCount: Int {
        goals.filter { $0.status == .active }.count
    }

    var activeHabitCount: Int {
        habits.count
    }

    var nextActionTitle: String? {
        goals.compactMap { GoalContributionResolver.summary(for: $0).nextActionTitle }.first
    }

    var dueHabitCount: Int {
        habits.filter(\.isDueToday).count
    }

    var doneHabitCount: Int {
        let todayKey = DateFormatters.todayKey()
        return habits.filter { $0.isDone(on: todayKey) }.count
    }
}

enum CadencePursuitSupport {
    static func goals(for pursuit: Pursuit) -> [Goal] {
        (pursuit.goals ?? []).sorted { $0.order < $1.order }
    }

    static func habits(for pursuit: Pursuit) -> [Habit] {
        (pursuit.habits ?? []).sorted { $0.order < $1.order }
    }

    static func summary(for pursuit: Pursuit) -> CadencePursuitSummary {
        CadencePursuitSummary(goals: goals(for: pursuit), habits: habits(for: pursuit))
    }
}

enum CadenceHabitSupport {
    static func toggle(_ habit: Habit, on dateKey: String, modelContext: ModelContext) {
        let existing = (habit.completions ?? []).filter { $0.date == dateKey }
        if existing.isEmpty {
            let completion = HabitCompletion(date: dateKey, habit: habit)
            modelContext.insert(completion)
            habit.completions = (habit.completions ?? []) + [completion]
        } else {
            for completion in existing {
                habit.completions = (habit.completions ?? []).filter { $0.id != completion.id }
                modelContext.delete(completion)
            }
        }
        try? modelContext.save()
    }
}
