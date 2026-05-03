#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Shared scheduling mutations

enum SchedulingActions {
    private static let dayStartMin = 0
    private static let dayEndMin = 24 * 60
    private static let minimumBundleDuration = 5

    /// Create and insert a new task scheduled to a specific date/time slot.
    static func createTask(title: String, dateKey: String, startMin: Int, endMin: Int, in context: ModelContext) {
        let task = AppTask(title: title)
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        task.estimatedMinutes = max(5, endMin - startMin)
        context.insert(task)
        // No calendar sync here — task has no area/project container yet when created from timeline drag
    }

    /// Create and insert a new scheduled task bundle.
    @discardableResult
    static func createBundle(title: String, dateKey: String, startMin: Int, endMin: Int, in context: ModelContext) -> TaskBundle {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = clampedRange(startMin: startMin, endMin: endMin)
        let bundle = TaskBundle(
            title: cleanedTitle.isEmpty ? "Task Bundle" : cleanedTitle,
            dateKey: dateKey,
            startMin: range.start,
            durationMinutes: range.duration
        )
        context.insert(bundle)
        return bundle
    }

    /// Create and insert a new scheduled task in a specific list/section.
    static func createTask(
        title: String,
        dateKey: String,
        startMin: Int,
        endMin: Int,
        containerSelection: TaskContainerSelection,
        sectionName: String,
        areas: [Area],
        projects: [Project],
        in context: ModelContext
    ) {
        let task = AppTask(title: title)
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        task.estimatedMinutes = max(5, endMin - startMin)

        switch containerSelection {
        case .inbox:
            task.area = nil
            task.project = nil
            task.context = nil
            task.sectionName = TaskSectionDefaults.defaultName
        case .area(let areaID):
            if let area = areas.first(where: { $0.id == areaID }) {
                task.area = area
                task.project = nil
                task.context = area.context
                task.sectionName = normalizedSectionName(sectionName, availableSections: area.sectionNames)
            } else {
                task.sectionName = TaskSectionDefaults.defaultName
            }
        case .project(let projectID):
            if let project = projects.first(where: { $0.id == projectID }) {
                task.project = project
                task.area = nil
                task.context = project.context
                task.sectionName = normalizedSectionName(sectionName, availableSections: project.sectionNames)
            } else {
                task.sectionName = TaskSectionDefaults.defaultName
            }
        }

        context.insert(task)
    }

    /// Move an existing task to a new date/time. Assigns a 30-min default if the task has no estimate.
    static func dropTask(_ task: AppTask, to dateKey: String, startMin: Int) {
        removeTaskFromBundle(task, keepOnBundleDate: false)
        task.scheduledDate = dateKey
        task.scheduledStartMin = clampedStartMin(startMin)
        if task.estimatedMinutes <= 0 { task.estimatedMinutes = 30 }
    }

    static func dropBundle(_ bundle: TaskBundle, to dateKey: String, startMin: Int) {
        let duration = max(bundle.durationMinutes, minimumBundleDuration)
        let clampedStart = min(max(dayStartMin, startMin), max(dayStartMin, dayEndMin - duration))
        bundle.dateKey = dateKey
        bundle.startMin = clampedStart
        bundle.durationMinutes = min(duration, dayEndMin - clampedStart)
        for task in memberTasks(in: bundle) {
            task.scheduledDate = dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
        }
    }

    static func addTask(_ task: AppTask, to bundle: TaskBundle) {
        if task.bundle?.id == bundle.id {
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
            ensureTask(task, isLinkedIn: bundle)
            normalizeBundleOrder(bundle)
            return
        }

        removeTaskFromBundle(task, keepOnBundleDate: false)
        let nextOrder = (memberTasks(in: bundle).map(\.bundleOrder).max() ?? -1) + 1
        task.bundle = bundle
        task.bundleOrder = nextOrder
        task.scheduledDate = bundle.dateKey
        task.scheduledStartMin = -1
        task.calendarEventID = ""
        ensureTask(task, isLinkedIn: bundle)
        normalizeBundleOrder(bundle)
    }

    @discardableResult
    static func createBundle(from targetTask: AppTask, adding draggedTask: AppTask, in context: ModelContext) -> TaskBundle? {
        guard targetTask.id != draggedTask.id,
              !targetTask.scheduledDate.isEmpty,
              targetTask.scheduledStartMin >= 0 else { return nil }

        let bundle = TaskBundle(
            title: "Task Bundle",
            dateKey: targetTask.scheduledDate,
            startMin: targetTask.scheduledStartMin,
            durationMinutes: max(targetTask.estimatedMinutes, minimumBundleDuration)
        )
        context.insert(bundle)
        addTask(targetTask, to: bundle)
        addTask(draggedTask, to: bundle)
        return bundle
    }

    static func removeTaskFromBundle(_ task: AppTask, keepOnBundleDate: Bool = true) {
        guard let bundle = task.bundle else { return }
        if keepOnBundleDate {
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
        }
        bundle.tasks?.removeAll { $0.id == task.id }
        task.bundle = nil
        task.bundleOrder = 0
        normalizeBundleOrder(bundle)
    }

    static func moveTaskInBundle(_ task: AppTask, direction: Int) {
        guard let bundle = task.bundle, direction != 0 else { return }
        var tasks = bundle.sortedTasks
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let nextIndex = min(max(index + direction, 0), tasks.count - 1)
        guard nextIndex != index else { return }
        tasks.swapAt(index, nextIndex)
        let hiddenMembers = orderedMemberTasks(in: bundle).filter { $0.isCancelled }
        let ordered = tasks + hiddenMembers.filter { hidden in !tasks.contains(where: { $0.id == hidden.id }) }
        for (offset, member) in ordered.enumerated() {
            member.bundleOrder = offset
        }
        bundle.tasks = ordered
    }

    static func rollOverTaskToToday(_ task: AppTask, todayKey: String, in context: ModelContext) {
        if let bundle = task.bundle {
            removeTaskFromBundle(task, keepOnBundleDate: false)
            cleanupInactiveBundleIfNeeded(bundle, in: context)
        }
        if task.scheduledStartMin >= 0 {
            removeFromCalendar(task)
        }
        task.scheduledDate = todayKey
        task.scheduledStartMin = -1
        task.calendarEventID = ""
    }

    static func completeBundle(_ bundle: TaskBundle, in context: ModelContext) {
        let tasks = memberTasks(in: bundle)
        for task in tasks {
            if !task.isDone && !task.isCancelled {
                TaskWorkflowService.markDone(task, in: context)
            }
            task.bundle = nil
            task.bundleOrder = 0
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
        }
        bundle.tasks = []
        context.delete(bundle)
    }

    static func updateBundleTime(_ bundle: TaskBundle, startMin: Int, endMin: Int) {
        let range = clampedRange(startMin: startMin, endMin: endMin)
        bundle.startMin = range.start
        bundle.durationMinutes = range.duration
    }

    private static func ensureTask(_ task: AppTask, isLinkedIn bundle: TaskBundle) {
        if bundle.tasks == nil {
            bundle.tasks = []
        }
        if bundle.tasks?.contains(where: { $0.id == task.id }) != true {
            bundle.tasks?.append(task)
        }
    }

    static func normalizeBundleOrder(_ bundle: TaskBundle) {
        let ordered = orderedMemberTasks(in: bundle)
        for (offset, task) in ordered.enumerated() {
            task.bundleOrder = offset
        }
        bundle.tasks = ordered
    }

    static func deleteBundle(_ bundle: TaskBundle, in context: ModelContext) {
        for task in memberTasks(in: bundle) {
            task.bundle = nil
            task.bundleOrder = 0
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
        }
        bundle.tasks = []
        context.delete(bundle)
    }

    /// Detach any legacy calendar-event reference from a task without deleting the calendar event.
    static func removeFromCalendar(_ task: AppTask) {
        task.calendarEventID = ""
    }

    private static func cleanupInactiveBundleIfNeeded(_ bundle: TaskBundle, in context: ModelContext) {
        guard memberTasks(in: bundle).allSatisfy({ $0.isDone || $0.isCancelled }) else { return }
        for task in memberTasks(in: bundle) {
            task.bundle = nil
            task.bundleOrder = 0
            task.scheduledDate = bundle.dateKey
            task.scheduledStartMin = -1
            task.calendarEventID = ""
        }
        bundle.tasks = []
        context.delete(bundle)
    }

    private static func normalizedSectionName(_ sectionName: String, availableSections: [String]) -> String {
        let cleaned = availableSections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolved = cleaned.isEmpty ? [TaskSectionDefaults.defaultName] : cleaned
        return resolved.first(where: { $0.caseInsensitiveCompare(sectionName) == .orderedSame })
            ?? resolved.first
            ?? TaskSectionDefaults.defaultName
    }

    private static func clampedStartMin(_ startMin: Int) -> Int {
        min(max(dayStartMin, startMin), dayEndMin - minimumBundleDuration)
    }

    private static func memberTasks(in bundle: TaskBundle) -> [AppTask] {
        (bundle.tasks ?? []).filter { $0.bundle?.id == bundle.id }
    }

    private static func orderedMemberTasks(in bundle: TaskBundle) -> [AppTask] {
        memberTasks(in: bundle).sorted {
            if $0.bundleOrder != $1.bundleOrder {
                return $0.bundleOrder < $1.bundleOrder
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private static func clampedRange(startMin: Int, endMin: Int) -> (start: Int, duration: Int) {
        let orderedStart = min(startMin, endMin)
        let orderedEnd = max(startMin, endMin)
        let start = clampedStartMin(orderedStart)
        let end = min(max(start + minimumBundleDuration, orderedEnd), dayEndMin)
        return (start, max(minimumBundleDuration, end - start))
    }
}

// MARK: - Shared zoom control view

struct TimelineZoomControl: View {
    @Binding var zoomLevel: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 4) {
            Button { if zoomLevel > range.lowerBound { zoomLevel -= 1 } } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(zoomLevel > range.lowerBound ? Theme.dim : Theme.dim.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.cadencePlain)
            Text("\(zoomLevel)×")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 22)
            Button { if zoomLevel < range.upperBound { zoomLevel += 1 } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(zoomLevel < range.upperBound ? Theme.dim : Theme.dim.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.cadencePlain)
        }
    }
}
#endif
