#if os(iOS)
import SwiftData
import SwiftUI

struct iPadTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""
    @AppStorage("ios.today.sortMode") private var sortModeRaw = iOSTaskSortMode.priority.rawValue
    @AppStorage("ios.today.showCompleted") private var showCompleted = false

    private var sortMode: iOSTaskSortMode {
        get { iOSTaskSortMode(rawValue: sortModeRaw) ?? .priority }
        set { sortModeRaw = newValue.rawValue }
    }

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var todayTasks: [AppTask] {
        allTasks
            .filter { task in
                guard !task.isDone && !task.isCancelled else { return false }
                return task.scheduledDate == todayKey ||
                    task.dueDate == todayKey ||
                    (!task.dueDate.isEmpty && task.dueDate < todayKey)
            }
            .sorted(by: sortTasks)
    }

    private var completedTodayTasks: [AppTask] {
        allTasks
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

    private var todayTaskGroups: [(title: String, color: Color, tasks: [AppTask])] {
        [
            ("Overdue", Theme.red, todayTasks.filter { !$0.dueDate.isEmpty && $0.dueDate < todayKey }),
            ("Due Today", Theme.amber, todayTasks.filter { $0.dueDate == todayKey }),
            ("Planned Today", Theme.blue, todayTasks.filter { $0.dueDate != todayKey && !(!$0.dueDate.isEmpty && $0.dueDate < todayKey) })
        ]
        .filter { !$0.tasks.isEmpty }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    todayTaskColumn
                        .frame(minWidth: 360, idealWidth: 430, maxWidth: 520)

                    Divider().background(Theme.borderSubtle)

                    iOSNotesPanel()
                        .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        todayTaskColumn
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 360, maxHeight: 520)

                        iOSNotesPanel()
                            .frame(minHeight: 430)
                    }
                    .padding(14)
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
    }

    private var todayTaskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: DateFormatters.longDate.string(from: Date()),
                title: "Today",
                count: todayTasks.count
            )

            Divider().background(Theme.borderSubtle)

            iOSTaskCaptureBar(
                placeholder: "Add a task for today...",
                title: $newTitle,
                action: captureTodayTask
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTodayTasks.count
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "checkmark.circle",
                    title: "Nothing planned for today",
                    subtitle: "Add a task above or schedule one from Inbox."
                )
            } else {
                List {
                    ForEach(todayTaskGroups, id: \.title) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                iOSTaskListRow(task: task)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: group.title, color: group.color)
                        }
                    }

                    if showCompleted && !completedTodayTasks.isEmpty {
                        Section {
                            ForEach(completedTodayTasks.prefix(12)) { task in
                                iOSTaskListRow(task: task, opacity: 0.62)
                            }
                        } header: {
                            iOSTaskSectionHeader(title: "Completed Today", color: Theme.green)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
            }
        }
        .background(Theme.surface)
    }

    private func captureTodayTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = AppTask(title: trimmed)
        task.scheduledDate = todayKey
        task.estimatedMinutes = 30
        task.order = nextTaskOrder()
        modelContext.insert(task)
        try? modelContext.save()
        newTitle = ""
    }

    private func nextTaskOrder() -> Int {
        (allTasks.map(\.order).max() ?? -1) + 1
    }

    private func rank(_ task: AppTask) -> Int {
        if !task.dueDate.isEmpty && task.dueDate < todayKey { return 0 }
        if task.dueDate == todayKey { return 1 }
        if task.scheduledDate == todayKey { return 2 }
        return 3
    }

    private func sortTasks(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let leftRank = rank(lhs)
        let rightRank = rank(rhs)
        if leftRank != rightRank { return leftRank < rightRank }

        switch sortMode {
        case .listOrder:
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

    private func priorityRank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}
#endif
