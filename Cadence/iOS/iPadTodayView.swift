#if os(iOS)
import SwiftData
import SwiftUI

struct iPadTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @State private var newTitle = ""
    @State private var saveError: String?
    @AppStorage("ios.today.sortMode") private var sortModeRaw = CadenceTaskSortMode.priority.rawValue
    @AppStorage("ios.today.showCompleted") private var showCompleted = false
    @AppStorage("ios.today.sidePanel") private var sidePanelRaw = iPadTodaySidePanel.notes.rawValue
    #if DEBUG
    @State private var sampleDataStatus: String?
    #endif

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

    private var compactScheduleTasks: [AppTask] {
        CadenceScheduleSupport.scheduledTasks(on: todayKey, from: allTasks)
            .filter { $0.scheduledStartMin >= 0 }
            .prefix(3)
            .map { $0 }
    }

    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey)
    }

    private var sidePanel: iPadTodaySidePanel {
        iPadTodaySidePanel(rawValue: sidePanelRaw) ?? .notes
    }

    private var sidePanelBinding: Binding<iPadTodaySidePanel> {
        Binding(
            get: { sidePanel },
            set: { sidePanelRaw = $0.rawValue }
        )
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
        if isRegularWidth && width >= 1_100 {
            threePaneTodayLayout(width: width)
        } else if isRegularWidth {
            twoPaneTodayLayout(width: width)
        } else {
            compactTodayLayout
        }
    }

    private func threePaneTodayLayout(width: CGFloat) -> some View {
        let notesWidth = min(max(width * 0.25, 260), 330)
        let scheduleWidth = min(max(width * 0.25, 280), 360)

        return HStack(spacing: 0) {
            iOSNotesPanel(useStandardHeaderHeight: true)
                .frame(width: notesWidth)
                .layoutPriority(0.22)

            Divider().background(Theme.borderSubtle)

            todayTaskColumn
                .frame(minWidth: 440, maxWidth: .infinity)
                .layoutPriority(1)

            Divider().background(Theme.borderSubtle)

            iOSSchedulePanel()
                .frame(width: scheduleWidth)
                .layoutPriority(0.28)
        }
    }

    private func twoPaneTodayLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            todayTaskColumn
                .frame(width: taskPaneWidth(for: width))
                .layoutPriority(0.58)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 0) {
                iPadTodayInspectorSwitcher(selection: sidePanelBinding)

                Divider().background(Theme.borderSubtle)

                sidePanelContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(
                minWidth: sidePanelMinWidth(for: width),
                idealWidth: sidePanelIdealWidth(for: width),
                maxWidth: 520
            )
            .layoutPriority(0.42)
        }
    }

    private func taskPaneWidth(for width: CGFloat) -> CGFloat {
        let inspectorFloor = sidePanelMinWidth(for: width)
        let maximumTaskWidth = max(420, width - inspectorFloor)
        let proposedWidth = width * 0.58
        return min(max(proposedWidth, 520), min(maximumTaskWidth, 740))
    }

    private func sidePanelMinWidth(for width: CGFloat) -> CGFloat {
        width < 900 ? 300 : 380
    }

    private func sidePanelIdealWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.42, sidePanelMinWidth(for: width)), 620)
    }

    @ViewBuilder
    private var sidePanelContent: some View {
        switch sidePanel {
        case .notes:
            iOSNotesPanel(useStandardHeaderHeight: true)
        case .timeline:
            iOSSchedulePanel()
        }
    }

    @ViewBuilder
    private var compactTodayLayout: some View {
        #if DEBUG
        iOSCompactTodayView(
            todayTasks: todayTasks,
            completedTodayTasks: completedTodayTasks,
            compactScheduleTasks: compactScheduleTasks,
            todayTaskGroups: todayTaskGroups,
            sortMode: Binding(
                get: { sortMode },
                set: { sortModeRaw = $0.rawValue }
            ),
            showCompleted: $showCompleted,
            newTitle: $newTitle,
            saveError: $saveError,
            captureTodayTask: captureTodayTask,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSCompactTodayView(
            todayTasks: todayTasks,
            completedTodayTasks: completedTodayTasks,
            compactScheduleTasks: compactScheduleTasks,
            todayTaskGroups: todayTaskGroups,
            sortMode: Binding(
                get: { sortMode },
                set: { sortModeRaw = $0.rawValue }
            ),
            showCompleted: $showCompleted,
            newTitle: $newTitle,
            saveError: $saveError,
            captureTodayTask: captureTodayTask
        )
        #endif
    }

    private var todayTaskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSPanelHeader(
                eyebrow: DateFormatters.longDate.string(from: Date()),
                title: "Today",
                count: todayTasks.count
            )

            Divider().background(Theme.borderSubtle)

            todayPlanningDeck

            Divider().background(Theme.borderSubtle.opacity(0.72))

            todayTaskSections
        }
        .background(Theme.surface)
    }

    private var todayPlanningDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            iPadTodaySummaryStrip(
                activeCount: todayTasks.count,
                timedCount: compactScheduleTasks.count,
                completedCount: completedTodayTasks.count
            )

            iOSTaskCaptureBar(
                placeholder: "Add a task for today...",
                title: $newTitle,
                action: captureTodayTask
            )

            if let saveError {
                iOSInlineErrorBanner(message: saveError) {
                    self.saveError = nil
                }
            }

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTodayTasks.count
            )
        }
        .padding(14)
        .background(Theme.bg.opacity(0.42))
    }

    @ViewBuilder
    private var todayTaskSections: some View {
        if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    iPadTodayEmptyStateCard(
                        sampleDataStatus: sampleDataStatus,
                        seedSampleData: seedSampleData
                    )
                    #else
                    iPadTodayEmptyStateCard()
                    #endif

                    iPadTodayStarterHints()
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.surface)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(todayTaskGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            iOSTaskSectionHeader(title: group.title, color: color(for: group.kind))

                            ForEach(group.tasks) { task in
                                iOSTaskRow(task: task, density: .compact)
                            }
                        }
                    }

                    if showCompleted && !completedTodayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            iOSTaskSectionHeader(title: "Completed Today", color: Theme.green)

                            ForEach(completedTodayTasks.prefix(12)) { task in
                                iOSTaskRow(task: task, density: .compact)
                                    .opacity(0.62)
                            }
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.surface)
        }
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

    #if DEBUG
    private func seedSampleData() {
        do {
            let inserted = try iOSSampleDataSupport.seedReviewTasks(
                allTasks: allTasks,
                modelContext: modelContext
            )
            sampleDataStatus = inserted == 0 ? "Sample review data already exists." : "Added \(inserted) sample review items."
        } catch {
            sampleDataStatus = "Could not add sample tasks."
        }
    }
    #endif
}

private struct iPadTodayInspectorSwitcher: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(selection.subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            iPadTodaySidePanelPicker(selection: $selection)
                .frame(width: 192)
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
        .background(Theme.bg)
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

    var subtitle: String {
        switch self {
        case .notes: return "Today, week, and notepad"
        case .timeline: return "Timed tasks and schedule"
        }
    }

    var compactTitle: String {
        switch self {
        case .notes: return "Notes"
        case .timeline: return "Timeline"
        }
    }
}

private struct iPadTodaySidePanelPicker: View {
    @Binding var selection: iPadTodaySidePanel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(iPadTodaySidePanel.allCases) { panel in
                Button {
                    selection = panel
                } label: {
                    Label(panel.compactTitle, systemImage: panel.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == panel ? Theme.text : Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(selection == panel ? Color.white.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(panel.title)
            }
        }
        .padding(3)
        .background(Theme.surfaceElevated.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct iPadTodaySummaryStrip: View {
    let activeCount: Int
    let timedCount: Int
    let completedCount: Int

    var body: some View {
        HStack(spacing: 8) {
            iPadTodaySummaryChip(
                value: activeCount,
                label: "Active",
                systemImage: "checklist",
                tint: Theme.blue
            )
            iPadTodaySummaryChip(
                value: timedCount,
                label: "Timed",
                systemImage: "clock.fill",
                tint: Theme.purple
            )
            iPadTodaySummaryChip(
                value: completedCount,
                label: "Done",
                systemImage: "checkmark.circle.fill",
                tint: Theme.green
            )
        }
    }
}

private struct iPadTodaySummaryChip: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Theme.surfaceElevated.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.46), lineWidth: 1)
        }
    }
}

private struct iPadTodayEmptyStateCard: View {
    #if DEBUG
    let sampleDataStatus: String?
    let seedSampleData: () -> Void

    init(sampleDataStatus: String? = nil, seedSampleData: @escaping () -> Void = {}) {
        self.sampleDataStatus = sampleDataStatus
        self.seedSampleData = seedSampleData
    }
    #else
    init() {}
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.blue.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing planned for today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text("Add a task above, schedule one from Inbox, or seed review tasks to check the layout.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                #if DEBUG
                Button(action: seedSampleData) {
                    Label("Samples", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Theme.blue.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Theme.blue.opacity(0.24), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seed sample tasks")
                #endif
            }

            #if DEBUG
            if let sampleDataStatus {
                Text(sampleDataStatus)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.leading, 50)
            }
            #endif
        }
        .padding(14)
        .background(Theme.surfaceElevated.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.48), lineWidth: 1)
        }
    }
}

private struct iPadTodayStarterHints: View {
    var body: some View {
        HStack(spacing: 10) {
            iPadTodayHint(
                title: "Capture",
                detail: "Quick-add a task and it lands on today.",
                systemImage: "plus"
            )
            iPadTodayHint(
                title: "Plan",
                detail: "Use the inspector to switch notes and timeline.",
                systemImage: "sidebar.right"
            )
        }
    }
}

private struct iPadTodayHint: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .frame(width: 24, height: 24)
                .background(Theme.surfaceElevated.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Theme.surfaceElevated.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.borderSubtle.opacity(0.38), lineWidth: 1)
        }
    }
}

#endif
