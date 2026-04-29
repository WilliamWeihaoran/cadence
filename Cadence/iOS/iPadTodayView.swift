#if os(iOS)
import SwiftData
import SwiftUI

struct iPadTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""

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
            .sorted { lhs, rhs in
                let leftRank = rank(lhs)
                let rightRank = rank(rhs)
                if leftRank != rightRank { return leftRank < rightRank }
                if lhs.priority != rhs.priority {
                    return priorityRank(lhs.priority) > priorityRank(rhs.priority)
                }
                return lhs.order < rhs.order
            }
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
            .padding(16)

            if todayTasks.isEmpty {
                iOSEmptyPanel(
                    systemImage: "checkmark.circle",
                    title: "Nothing planned for today",
                    subtitle: "Add a task above or schedule one from Inbox."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(todayTasks) { task in
                            iOSTaskRow(task: task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
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
