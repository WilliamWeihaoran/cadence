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
        CadenceTaskQuerySupport.activeTodayTasks(
            from: allTasks,
            todayKey: todayKey,
            sortMode: sortMode.cadenceSortMode
        )
    }

    private var completedTodayTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTodayTasks(from: allTasks, todayKey: todayKey)
    }

    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    iOSNotesPanel(useStandardHeaderHeight: true)
                        .frame(minWidth: 260, idealWidth: 340)
                        .layoutPriority(0.34)

                    Divider().background(Theme.borderSubtle)

                    todayTaskColumn
                        .frame(minWidth: 300, idealWidth: 380)
                        .layoutPriority(0.38)

                    Divider().background(Theme.borderSubtle)

                    iOSSchedulePanel()
                        .frame(minWidth: 230, idealWidth: 300)
                        .layoutPriority(0.28)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        todayTaskColumn
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 360, maxHeight: 520)

                        iOSNotesPanel()
                            .frame(minHeight: 430)

                        iOSSchedulePanel()
                            .frame(minHeight: 420)
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
                            iOSTaskSectionHeader(title: group.title, color: color(for: group.kind))
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
        guard let task = CadenceTaskQuerySupport.makeTask(
            title: newTitle,
            allTasks: allTasks,
            scheduledDate: todayKey
        ) else { return }
        modelContext.insert(task)
        try? modelContext.save()
        newTitle = ""
    }

    private func color(for groupKind: CadenceTodayTaskGroupKind) -> Color {
        switch groupKind {
        case .overdue: return Theme.red
        case .dueToday: return Theme.amber
        case .plannedToday: return Theme.blue
        }
    }
}

private struct iOSSchedulePanel: View {
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query private var allBundles: [TaskBundle]

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var scheduledTasks: [AppTask] {
        CadenceScheduleSupport.scheduledTasks(on: todayKey, from: allTasks)
    }

    private var todayBundles: [TaskBundle] {
        CadenceScheduleSupport.bundles(on: todayKey, from: allBundles, includeCompleted: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                iOSPanelHeader(eyebrow: "Schedule", title: "Timeline")
                Spacer()
            }
            .frame(height: iOSPanelHeaderHeight, alignment: .top)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(6..<23, id: \.self) { hour in
                        iOSScheduleHourRow(
                            hour: hour,
                            tasks: tasks(in: hour),
                            bundles: bundles(in: hour)
                        )
                    }
                }
                .padding(.trailing, 8)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private func tasks(in hour: Int) -> [AppTask] {
        CadenceScheduleSupport.tasks(in: hour, from: scheduledTasks)
    }

    private func bundles(in hour: Int) -> [TaskBundle] {
        CadenceScheduleSupport.bundles(in: hour, from: todayBundles)
    }
}

private struct iOSScheduleHourRow: View {
    let hour: Int
    let tasks: [AppTask]
    let bundles: [TaskBundle]

    private var hasItems: Bool {
        !tasks.isEmpty || !bundles.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(hourLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim.opacity(hour % 3 == 0 ? 0.9 : 0.45))
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 7)
                .padding(.top, -6)

            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(hour % 3 == 0 ? 0.55 : 0.25))
                    .frame(height: 1)

                if hasItems {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(bundles) { bundle in
                            iOSScheduleBlock(
                                title: bundle.displayTitle,
                                subtitle: TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin),
                                tint: Theme.purple
                            )
                        }

                        ForEach(tasks) { task in
                            iOSScheduleBlock(
                                title: task.title.isEmpty ? "Untitled Task" : task.title,
                                subtitle: TimeFormatters.timeRange(
                                    startMin: task.scheduledStartMin,
                                    endMin: task.scheduledEndMin
                                ),
                                tint: Color(hex: task.containerColor)
                            )
                        }
                    }
                    .padding(.top, 5)
                }
            }
        }
        .frame(minHeight: 48, alignment: .top)
        .padding(.leading, 4)
    }

    private var hourLabel: String {
        TimeFormatters.timeString(from: hour * 60)
    }
}

private struct iOSScheduleBlock: View {
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.18))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(tint.opacity(0.9))
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
#endif
