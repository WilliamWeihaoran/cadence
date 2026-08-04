import Foundation
import SwiftData
import SwiftUI

enum CadenceTaskSortMode: String, CaseIterable, Hashable, Identifiable {
    case listOrder
    case priority
    case doDate
    case dueDate
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listOrder: return "List Order"
        case .priority: return "Priority"
        case .doDate: return "Do Date"
        case .dueDate: return "Due Date"
        case .newest: return "Newest"
        }
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

    private static func sortDateKey(_ dateKey: String) -> String {
        dateKey.isEmpty ? "9999-99-99" : dateKey
    }
}

enum CadenceTaskMutationSupport {
    static func toggleCompletion(_ task: AppTask, modelContext: ModelContext) {
        if task.isDone {
            CadenceTaskRecurrenceWorkflowSupport.markTodo(task)
        } else {
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        }
        try? modelContext.save()
    }

    static func setStatus(_ status: TaskStatus, for task: AppTask, modelContext: ModelContext) {
        applyStatusCompletion(status, to: task, modelContext: modelContext)
        try? modelContext.save()
    }

    static func applyStatusCompletion(_ status: TaskStatus, to task: AppTask, modelContext: ModelContext) {
        switch status {
        case .done:
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        case .cancelled:
            CadenceTaskRecurrenceWorkflowSupport.markCancelled(task, in: modelContext)
        case .todo, .inProgress:
            task.status = status
            task.completedAt = nil
        }
    }

    static func normalizeCompletionState(for task: AppTask, modelContext: ModelContext) {
        if task.status == .done {
            CadenceTaskRecurrenceWorkflowSupport.markDone(task, in: modelContext)
        } else {
            task.completedAt = nil
        }
        try? modelContext.save()
    }

    static func setPriority(_ priority: TaskPriority, for task: AppTask, modelContext: ModelContext) {
        task.priority = priority
        try? modelContext.save()
    }

    static func setGoal(_ goal: Goal?, for task: AppTask, modelContext: ModelContext) {
        task.goal = goal
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

    static func scheduleNextWeek(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: nextWeek)
        try? modelContext.save()
    }

    static func setScheduledDate(_ dateKey: String, for task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = dateKey
        try? modelContext.save()
    }

    static func moveTaskToDate(_ task: AppTask, dateKey: String, modelContext: ModelContext) {
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = dateKey
        if task.estimatedMinutes <= 0 {
            task.estimatedMinutes = 30
        }
        try? modelContext.save()
    }

    static func setScheduledTime(_ startMin: Int, for task: AppTask, modelContext: ModelContext) {
        task.scheduledStartMin = min(max(0, startMin), 1425)
        try? modelContext.save()
    }

    static func clearScheduledDate(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledDate = ""
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func clearScheduledTime(_ task: AppTask, modelContext: ModelContext) {
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func dueToday(_ task: AppTask, modelContext: ModelContext) {
        task.dueDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    static func dueTomorrow(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.dueDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    static func dueNextWeek(_ task: AppTask, modelContext: ModelContext, calendar: Calendar = .current) {
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        task.dueDate = DateFormatters.dateKey(from: nextWeek)
        try? modelContext.save()
    }

    static func setDueDate(_ dateKey: String, for task: AppTask, modelContext: ModelContext) {
        task.dueDate = dateKey
        try? modelContext.save()
    }

    static func clearDueDate(_ task: AppTask, modelContext: ModelContext) {
        task.dueDate = ""
        try? modelContext.save()
    }

    static func setPlanningDates(
        scheduledDate: String?,
        dueDate: String?,
        for task: AppTask,
        modelContext: ModelContext
    ) {
        let scheduleKey = scheduledDate ?? ""
        task.scheduledDate = scheduleKey
        if scheduleKey.isEmpty {
            task.scheduledStartMin = -1
        }
        task.dueDate = dueDate ?? ""
        try? modelContext.save()
    }

    static func moveToSection(_ sectionName: String, task: AppTask, modelContext: ModelContext) {
        task.sectionName = sectionName
        try? modelContext.save()
    }

    static func sectionNames(forArea area: Area?, project: Project?) -> [String] {
        if let area {
            return area.sectionNames
        }
        if let project {
            return project.sectionNames
        }
        return [TaskSectionDefaults.defaultName]
    }

    static func normalizedSectionName(_ sectionName: String, area: Area?, project: Project?) -> String {
        let names = sectionNames(forArea: area, project: project)
        if let matched = names.first(where: { $0.caseInsensitiveCompare(sectionName) == .orderedSame }) {
            return matched
        }
        return names.first ?? TaskSectionDefaults.defaultName
    }

    static func assignContainer(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        sectionName: String = TaskSectionDefaults.defaultName,
        allTasks: [AppTask],
        updateOrder: Bool = true
    ) {
        let normalizedSectionName = normalizedSectionName(sectionName, area: area, project: project)

        if let area {
            task.area = area
            task.project = nil
            task.context = area.context
        } else if let project {
            task.project = project
            task.area = nil
            task.context = project.context ?? project.area?.context
        } else {
            task.area = nil
            task.project = nil
            task.context = nil
        }

        task.sectionName = normalizedSectionName
        if updateOrder {
            task.order = nextContainerOrder(excluding: task, in: allTasks, area: area, project: project)
        }
    }

    static func moveToContainer(
        _ task: AppTask,
        area: Area?,
        project: Project?,
        sectionName: String = TaskSectionDefaults.defaultName,
        allTasks: [AppTask],
        modelContext: ModelContext
    ) {
        assignContainer(
            task,
            area: area,
            project: project,
            sectionName: sectionName,
            allTasks: allTasks
        )
        try? modelContext.save()
    }

    static func moveToInbox(_ task: AppTask, allTasks: [AppTask], modelContext: ModelContext) {
        assignContainer(
            task,
            area: nil,
            project: nil,
            sectionName: TaskSectionDefaults.defaultName,
            allTasks: allTasks
        )
        try? modelContext.save()
    }

    static func duplicate(_ task: AppTask, allTasks: [AppTask], modelContext: ModelContext) throws -> AppTask {
        let duplicate = AppTask(title: task.title)
        duplicate.notes = task.notes
        duplicate.priority = task.priority
        duplicate.status = .todo
        duplicate.recurrenceRule = task.recurrenceRule
        duplicate.dueDate = task.dueDate
        duplicate.scheduledDate = task.scheduledDate
        duplicate.scheduledStartMin = task.scheduledStartMin
        duplicate.estimatedMinutes = task.estimatedMinutes
        duplicate.actualMinutes = 0
        duplicate.sectionName = task.resolvedSectionName
        duplicate.order = nextOrderForSibling(of: task, in: allTasks)
        duplicate.area = task.area
        duplicate.project = task.project
        duplicate.goal = task.goal
        duplicate.context = task.context
        duplicate.tags = task.tags

        modelContext.insert(duplicate)
        do {
            try modelContext.save()
            return duplicate
        } catch {
            modelContext.delete(duplicate)
            throw error
        }
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

    static func insertScheduledTask(
        title: String,
        allTasks: [AppTask],
        modelContext: ModelContext,
        scheduledDate: String,
        scheduledStartMin: Int,
        estimatedMinutes: Int,
        configure: (AppTask) -> Void = { _ in }
    ) throws -> AppTask? {
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: title,
            allTasks: allTasks,
            scheduledDate: scheduledDate,
            estimatedMinutes: max(5, estimatedMinutes)
        ) else { return nil }

        task.scheduledStartMin = scheduledStartMin
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

    @discardableResult
    static func insertBundle(
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext
    ) throws -> TaskBundle {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedStart = min(max(0, startMin), (24 * 60) - 5)
        let duration = min(max(5, durationMinutes), (24 * 60) - clampedStart)
        let bundle = TaskBundle(
            title: trimmed.isEmpty ? "Task Bundle" : trimmed,
            dateKey: dateKey,
            startMin: clampedStart,
            durationMinutes: duration
        )

        modelContext.insert(bundle)
        do {
            try modelContext.save()
            return bundle
        } catch {
            modelContext.delete(bundle)
            throw error
        }
    }

    static func updateBundle(
        _ bundle: TaskBundle,
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedStart = min(max(0, startMin), (24 * 60) - 5)
        let duration = min(max(5, durationMinutes), (24 * 60) - clampedStart)

        bundle.title = trimmed
        bundle.dateKey = dateKey
        bundle.startMin = clampedStart
        bundle.durationMinutes = duration

        for task in bundle.tasks ?? [] {
            task.scheduledDate = dateKey
            task.scheduledStartMin = -1
        }

        try? modelContext.save()
    }

    static func moveBundle(_ bundle: TaskBundle, to dateKey: String, modelContext: ModelContext) {
        updateBundle(
            bundle,
            title: bundle.title,
            dateKey: dateKey,
            startMin: bundle.startMin,
            durationMinutes: bundle.durationMinutes,
            modelContext: modelContext
        )
    }

    static func addTask(_ task: AppTask, to bundle: TaskBundle, modelContext: ModelContext) {
        let nextOrder = ((bundle.tasks ?? []).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        if !(bundle.tasks ?? []).contains(where: { $0.id == task.id }) {
            bundle.tasks = (bundle.tasks ?? []) + [task]
        }
        try? modelContext.save()
    }

    static func removeTaskFromBundle(_ task: AppTask, modelContext: ModelContext) {
        let bundleDateKey = task.bundle?.dateKey ?? task.scheduledDate
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }
        task.bundle = nil
        task.bundleOrder = 0
        task.scheduledDate = bundleDateKey
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    static func deleteBundle(_ bundle: TaskBundle, modelContext: ModelContext) {
        for task in bundle.tasks ?? [] {
            task.bundle = nil
            task.bundleOrder = 0
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
        }

        bundle.tasks = []
        modelContext.delete(bundle)
        try? modelContext.save()
    }

    private static func nextContainerOrder(
        excluding task: AppTask,
        in allTasks: [AppTask],
        area: Area?,
        project: Project?
    ) -> Int {
        let siblings = allTasks.filter { candidate in
            guard candidate.id != task.id else { return false }
            if let area {
                return candidate.area?.id == area.id
            }
            if let project {
                return candidate.project?.id == project.id
            }
            return candidate.area == nil && candidate.project == nil
        }
        return CadenceTaskQuerySupport.nextTaskOrder(in: siblings)
    }

    private static func nextOrderForSibling(of task: AppTask, in allTasks: [AppTask]) -> Int {
        nextContainerOrder(excluding: task, in: allTasks, area: task.area, project: task.project)
    }
}

enum CadenceTaskRecurrenceEditScope: String, CaseIterable, Hashable {
    case thisTask
    case thisAndFuture

    var label: String {
        switch self {
        case .thisTask: return "Only This Task"
        case .thisAndFuture: return "This And Future Tasks"
        }
    }
}

enum CadenceTaskRecurrenceWorkflowSupport {
    static func markDone(_ task: AppTask, in context: ModelContext, now: Date = Date()) {
        task.completedAt = now
        task.status = .done
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    /// Cancelling a single occurrence skips it, but the recurring series must keep going —
    /// otherwise the whole future series silently dies the first time anyone cancels instead of completes.
    static func markCancelled(_ task: AppTask, in context: ModelContext, now: Date = Date()) {
        task.completedAt = nil
        task.status = .cancelled
        spawnNextOccurrenceIfNeeded(from: task, in: context, now: now)
    }

    static func markTodo(_ task: AppTask) {
        task.completedAt = nil
        task.status = .todo
    }

    private static func spawnNextOccurrenceIfNeeded(from task: AppTask, in context: ModelContext, now: Date) {
        guard task.isRecurring, task.recurrenceSpawnedTaskID == nil else { return }
        ensureRecurrenceSeriesMetadata(for: task)
        let nextTask = makeNextRecurringTask(from: task, now: now)
        context.insert(nextTask)
        task.recurrenceSpawnedTaskID = nextTask.id
    }

    static func ensureRecurrenceSeriesMetadata(for task: AppTask) {
        if task.recurrenceSeriesIDRaw.isEmpty {
            task.recurrenceSeriesIDRaw = task.id.uuidString
        }
    }

    static func applyRecurrenceRule(
        _ rule: TaskRecurrenceRule,
        to task: AppTask,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope
    ) {
        ensureRecurrenceSeriesMetadata(for: task)
        let targetTasks = recurrenceTargets(from: task, allTasks: allTasks, scope: scope)
        for target in targetTasks {
            ensureRecurrenceSeriesMetadata(for: target)
            target.recurrenceRule = rule
            if rule == .none {
                target.recurrenceSpawnedTaskID = nil
            }
        }
    }

    static func recurrenceTargets(
        from task: AppTask,
        allTasks: [AppTask],
        scope: CadenceTaskRecurrenceEditScope
    ) -> [AppTask] {
        guard scope == .thisAndFuture else { return [task] }

        var targets = [task]
        var seen = Set([task.id])
        var current = task

        while let nextID = current.recurrenceSpawnedTaskID,
              let next = allTasks.first(where: { $0.id == nextID }),
              seen.insert(next.id).inserted {
            targets.append(next)
            current = next
        }

        let currentDate = recurrenceSortDateKey(for: task)
        let seriesID = task.recurrenceSeriesID
        for candidate in allTasks where !seen.contains(candidate.id) {
            guard candidate.recurrenceSeriesID == seriesID else { continue }
            if let currentDate,
               let candidateDate = recurrenceSortDateKey(for: candidate),
               candidateDate < currentDate {
                continue
            }
            targets.append(candidate)
            seen.insert(candidate.id)
        }

        return targets.sorted { lhs, rhs in
            recurrenceSortKey(for: lhs) < recurrenceSortKey(for: rhs)
        }
    }

    private static func makeNextRecurringTask(from task: AppTask, now: Date) -> AppTask {
        let nextTask = AppTask(title: task.title)
        nextTask.notes = task.notes
        nextTask.priority = task.priority
        nextTask.recurrenceRule = task.recurrenceRule
        nextTask.estimatedMinutes = max(task.estimatedMinutes, 30)
        nextTask.sectionName = task.sectionName
        nextTask.area = task.area
        nextTask.project = task.project
        nextTask.context = task.context
        nextTask.goal = task.goal
        nextTask.recurrenceSeriesIDRaw = task.recurrenceSeriesID.uuidString
        nextTask.recurrenceSourceTaskID = task.id
        nextTask.recurrenceOccurrenceIndex = task.recurrenceOccurrenceIndex + 1

        let todayKey = DateFormatters.dateKey(from: now)
        if !task.dueDate.isEmpty {
            nextTask.dueDate = nextRecurrenceDateKey(from: task.dueDate, todayKey: todayKey, recurrence: task.recurrenceRule) ?? task.dueDate
        }
        if !task.scheduledDate.isEmpty {
            nextTask.scheduledDate = nextRecurrenceDateKey(from: task.scheduledDate, todayKey: todayKey, recurrence: task.recurrenceRule) ?? task.scheduledDate
            nextTask.scheduledStartMin = task.scheduledStartMin
        }

        if let subtasks = task.subtasks {
            nextTask.subtasks = subtasks
                .sorted { $0.order < $1.order }
                .map { source in
                    let copy = Subtask(title: source.title)
                    copy.order = source.order
                    return copy
                }
        }

        return nextTask
    }

    private static func recurrenceSortDateKey(for task: AppTask) -> String? {
        if !task.scheduledDate.isEmpty { return task.scheduledDate }
        if !task.dueDate.isEmpty { return task.dueDate }
        return nil
    }

    private static func recurrenceSortKey(for task: AppTask) -> String {
        [
            recurrenceSortDateKey(for: task) ?? "9999-12-31",
            String(format: "%04d", max(0, task.scheduledStartMin)),
            String(format: "%08d", task.recurrenceOccurrenceIndex),
            task.createdAt.ISO8601Format(),
            task.id.uuidString
        ].joined(separator: "|")
    }

    /// Shifts one recurrence period forward from whichever is later: the occurrence's own date or today.
    /// A daily/weekly/etc. task completed long after it was last due (e.g. a week-stale daily task)
    /// should catch up to today rather than advancing by one period from its stale date, which would
    /// just produce another still-overdue occurrence.
    private static func nextRecurrenceDateKey(from key: String, todayKey: String, recurrence: TaskRecurrenceRule) -> String? {
        guard recurrence != .none else { return nil }
        let anchorKey = max(key, todayKey)
        return shiftedDateKey(anchorKey, recurrence: recurrence)
    }

    private static func shiftedDateKey(_ key: String, recurrence: TaskRecurrenceRule) -> String? {
        guard recurrence != .none, let date = DateFormatters.date(from: key) else { return nil }
        let calendar = Calendar.current
        let component: Calendar.Component
        let value: Int

        switch recurrence {
        case .none:
            return key
        case .daily:
            component = .day
            value = 1
        case .weekly:
            component = .weekOfYear
            value = 1
        case .monthly:
            component = .month
            value = 1
        case .yearly:
            component = .year
            value = 1
        }

        guard let next = calendar.date(byAdding: component, value: value, to: date) else { return nil }
        return DateFormatters.dateKey(from: next)
    }
}
