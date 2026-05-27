#if os(iOS)
import SwiftData
import SwiftUI

struct iPadTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""
    @State private var saveError: String?
    @State private var sidePanel: iPadTodaySidePanel = .notes
    @AppStorage("ios.today.sortMode") private var sortModeRaw = CadenceTaskSortMode.priority.rawValue
    @AppStorage("ios.today.showCompleted") private var showCompleted = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var sortMode: CadenceTaskSortMode {
        get { CadenceTaskSortMode(rawValue: sortModeRaw) ?? .priority }
        set { sortModeRaw = newValue.rawValue }
    }

    private var todayKey: String {
        DateFormatters.todayKey()
    }

    private var todayTasks: [AppTask] {
        CadenceTaskQuerySupport.activeTodayTasks(
            from: allTasks,
            todayKey: todayKey,
            sortMode: sortMode
        )
    }

    private var completedTodayTasks: [AppTask] {
        CadenceTaskQuerySupport.completedTodayTasks(from: allTasks, todayKey: todayKey)
    }

    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey)
    }

    var body: some View {
        GeometryReader { proxy in
            todayLayout(width: proxy.size.width)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func todayLayout(width: CGFloat) -> some View {
        if isRegularWidth && width >= 1_080 {
            threePaneTodayLayout
        } else if isRegularWidth {
            twoPaneTodayLayout
        } else {
            compactTodayLayout
        }
    }

    private var threePaneTodayLayout: some View {
        HStack(spacing: 0) {
            iOSNotesPanel(useStandardHeaderHeight: true)
                .frame(minWidth: 360, idealWidth: 430)
                .layoutPriority(0.34)

            Divider().background(Theme.borderSubtle)

            todayTaskColumn
                .frame(minWidth: 400, idealWidth: 470)
                .layoutPriority(0.43)

            Divider().background(Theme.borderSubtle)

            iOSSchedulePanel()
                .frame(minWidth: 310, idealWidth: 350)
                .layoutPriority(0.23)
        }
    }

    private var twoPaneTodayLayout: some View {
        HStack(spacing: 0) {
            todayTaskColumn
                .frame(minWidth: 420)
                .layoutPriority(0.62)

            Divider().background(Theme.borderSubtle)

            VStack(alignment: .leading, spacing: 0) {
                iPadTodaySidePanelPicker(selection: $sidePanel)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider().background(Theme.borderSubtle)

                switch sidePanel {
                case .notes:
                    iOSNotesPanel(useStandardHeaderHeight: true)
                case .timeline:
                    iOSSchedulePanel()
                }
            }
            .frame(minWidth: 320, idealWidth: 380)
            .layoutPriority(0.38)
        }
    }

    private var compactTodayLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactTodayHeader

            Divider().background(Theme.borderSubtle)

            iOSTaskCaptureBar(
                placeholder: "Add a task...",
                title: $newTitle,
                action: captureTodayTask
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

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
            .padding(.bottom, 10)

            if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
                iOSEmptyPanel(
                    systemImage: "checkmark.circle",
                    title: "Nothing planned",
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.ignoresSafeArea())
    }

    private var compactTodayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 38, height: 38)
                .background(Theme.amber.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.amber.opacity(0.22), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormatters.longDate.string(from: Date()))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text("Today")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(todayTasks.count)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.blue.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
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

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

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
        let pendingTitle = newTitle
        do {
            _ = try CadenceTaskMutationSupport.insertTask(
                title: newTitle,
                allTasks: allTasks,
                modelContext: modelContext,
                scheduledDate: todayKey
            )
            saveError = nil
            newTitle = ""
        } catch {
            newTitle = pendingTitle
            saveError = "Couldn't save this task. Try again in a moment."
        }
    }

    private func color(for groupKind: CadenceTodayTaskGroupKind) -> Color {
        switch groupKind {
        case .overdue: return Theme.red
        case .dueToday: return Theme.amber
        case .plannedToday: return Theme.blue
        }
    }
}

private enum iPadTodaySidePanel: String, CaseIterable, Identifiable {
    case notes
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .timeline: return "Timeline"
        }
    }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .timeline: return "clock"
        }
    }
}

private struct iPadTodaySidePanelPicker: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(iPadTodaySidePanel.allCases) { panel in
                Label(panel.title, systemImage: panel.icon)
                    .tag(panel)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(Theme.blue)
    }
}

private struct iOSSchedulePanel: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                            bundles: bundles(in: hour),
                            rowHeight: horizontalSizeClass == .regular ? 58 : 48
                        )
                    }
                }
                .padding(.trailing, horizontalSizeClass == .regular ? 12 : 8)
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
    let rowHeight: CGFloat

    private var hasItems: Bool {
        !tasks.isEmpty || !bundles.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(hourLabel)
                .font(.system(size: rowHeight > 50 ? 11 : 10, weight: .medium))
                .foregroundStyle(Theme.dim.opacity(hour % 3 == 0 ? 0.9 : 0.45))
                .frame(width: rowHeight > 50 ? 50 : 42, alignment: .trailing)
                .padding(.trailing, rowHeight > 50 ? 9 : 7)
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
        .frame(minHeight: rowHeight, alignment: .top)
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
