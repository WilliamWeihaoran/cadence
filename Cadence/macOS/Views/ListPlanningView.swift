#if os(macOS)
import Foundation
import SwiftUI
import SwiftData

struct ListPlanningView: View {
    let tasks: [AppTask]
    let area: Area?
    let project: Project?

    @Environment(\.modelContext) private var modelContext
    @State private var window: PlanningWindow = .twoWeeks
    @State private var targetedDateKey: String?
    @State private var isBacklogTargeted = false

    private var listName: String {
        area?.name ?? project?.name ?? "List"
    }

    private var activeTasks: [AppTask] {
        CadenceTaskQuerySupport.openTasks(from: tasks)
    }

    private var dates: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return (0..<window.dayCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var dateKeys: Set<String> {
        Set(dates.map { DateFormatters.dateKey(from: $0) })
    }

    private var plannedTasks: [AppTask] {
        activeTasks.filter { !$0.scheduledDate.isEmpty }
    }

    private var unscheduledTasks: [AppTask] {
        activeTasks
            .filter { $0.scheduledDate.isEmpty && ($0.dueDate.isEmpty || !dateKeys.contains($0.dueDate)) }
            .sorted(by: planningTaskSort)
    }

    private var visibleDatedTaskCount: Int {
        activeTasks.filter { task in
            dateKeys.contains(task.scheduledDate) || (task.scheduledDate.isEmpty && dateKeys.contains(task.dueDate))
        }.count
    }

    private var dueSoonCount: Int {
        activeTasks.filter { !$0.dueDate.isEmpty && dateKeys.contains($0.dueDate) }.count
    }

    private var plannedMinutes: Int {
        plannedTasks.reduce(0) { $0 + max($1.estimatedMinutes, 0) }
    }

    private var windowLabel: String {
        guard let first = dates.first, let last = dates.last else { return "" }
        return "\(DateFormatters.shortDate.string(from: first)) - \(DateFormatters.shortDate.string(from: last))"
    }

    var body: some View {
        VStack(spacing: 0) {
            planningHeader

            Divider().background(Theme.borderSubtle)

            if activeTasks.isEmpty {
                EmptyStateView(message: "No active tasks", subtitle: "Open tasks will appear here", icon: "calendar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        timelineSection
                        backlogSection
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .cadenceSoftPageBounce()
            }
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
        .background(Theme.bg)
    }

    private var planningHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                planningTitleBlock
                Spacer(minLength: 12)
                planningMetricStrip
                PlanningWindowControl(selection: $window)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    planningTitleBlock
                    Spacer(minLength: 8)
                    PlanningWindowControl(selection: $window)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    planningMetricStrip
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.72))
    }

    private var planningTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Planning")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("\(listName) - \(windowLabel)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
    }

    private var planningMetricStrip: some View {
        HStack(spacing: 8) {
            PlanningMetricPill(title: "Open", value: "\(activeTasks.count)", tint: Theme.blue)
            PlanningMetricPill(title: "Planned", value: "\(plannedTasks.count)", tint: Theme.green)
            PlanningMetricPill(title: "Due", value: "\(dueSoonCount)", tint: Theme.red)
            PlanningMetricPill(title: "Estimate", value: planningDurationLabel(plannedMinutes), tint: Theme.amber)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanningSectionHeader(
                icon: "calendar",
                title: "Upcoming",
                count: visibleDatedTaskCount,
                tint: Theme.blue
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(dates, id: \.self) { date in
                        let dateKey = DateFormatters.dateKey(from: date)
                        PlanningDayColumn(
                            date: date,
                            dateKey: dateKey,
                            tasks: tasksForDate(dateKey),
                            isTargeted: targetedDateKey == dateKey,
                            onClearSchedule: clearSchedule
                        )
                        .frame(width: window.dayWidth)
                        .dropDestination(for: String.self) { items, _ in
                            scheduleDroppedTask(items: items, on: dateKey)
                        } isTargeted: { isTargeted in
                            if isTargeted {
                                targetedDateKey = dateKey
                            } else if targetedDateKey == dateKey {
                                targetedDateKey = nil
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }

    private var backlogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlanningSectionHeader(
                icon: "tray",
                title: "Backlog",
                count: unscheduledTasks.count,
                tint: Theme.amber
            )

            PlanningBacklogPanel(
                tasks: unscheduledTasks,
                isTargeted: isBacklogTargeted,
                onClearSchedule: clearSchedule
            )
            .dropDestination(for: String.self) { items, _ in
                clearDroppedTask(items: items)
            } isTargeted: { isTargeted in
                isBacklogTargeted = isTargeted
            }
        }
    }

    private func tasksForDate(_ dateKey: String) -> [AppTask] {
        activeTasks
            .filter { task in
                task.scheduledDate == dateKey || (task.scheduledDate.isEmpty && task.dueDate == dateKey)
            }
            .sorted(by: planningTaskSort)
    }

    private func scheduleDroppedTask(items: [String], on dateKey: String) -> Bool {
        guard let task = task(from: items) else { return false }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            task.scheduledDate = dateKey
        }
        try? modelContext.save()
        return true
    }

    private func clearDroppedTask(items: [String]) -> Bool {
        guard let task = task(from: items) else { return false }
        clearSchedule(for: task)
        return true
    }

    private func clearSchedule(for task: AppTask) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
            task.scheduledDate = ""
            task.scheduledStartMin = -1
        }
        try? modelContext.save()
    }

    private func task(from items: [String]) -> AppTask? {
        guard let payload = items.first,
              let taskID = TasksPanelSupport.taskID(from: payload) else {
            return nil
        }
        return activeTasks.first { $0.id == taskID }
    }

    private func planningTaskSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsKey = planningAnchorKey(for: lhs)
        let rhsKey = planningAnchorKey(for: rhs)
        if lhsKey != rhsKey { return lhsKey < rhsKey }

        if lhs.scheduledStartMin != rhs.scheduledStartMin {
            if lhs.scheduledStartMin < 0 { return false }
            if rhs.scheduledStartMin < 0 { return true }
            return lhs.scheduledStartMin < rhs.scheduledStartMin
        }

        let lhsPriority = taskPriorityRank(lhs.priority)
        let rhsPriority = taskPriorityRank(rhs.priority)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }

        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func planningAnchorKey(for task: AppTask) -> String {
        if !task.scheduledDate.isEmpty { return task.scheduledDate }
        if !task.dueDate.isEmpty { return task.dueDate }
        return "9999-99-99"
    }
}
#endif
