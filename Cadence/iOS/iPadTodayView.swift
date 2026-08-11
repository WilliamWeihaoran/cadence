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
    @AppStorage("ios.today.layoutMode") private var layoutModeRaw = iPadTodayLayoutMode.focus.rawValue
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
        CadenceScheduleSupport.scheduledTasks(on: todayKey, from: allTasks, includeCompleted: false, excludeBundled: false)
            .filter { $0.scheduledStartMin >= 0 }
            .prefix(3)
            .map { $0 }
    }

    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey)
    }

    private var todaySummary: CadenceTodaySummary {
        CadenceTodayPresentationSupport.summary(
            activeTasks: todayTasks,
            timedTasks: compactScheduleTasks,
            completedTasks: completedTodayTasks
        )
    }

    private var sidePanel: iPadTodaySidePanel {
        iPadTodaySidePanel(rawValue: sidePanelRaw) ?? .notes
    }

    private var layoutMode: iPadTodayLayoutMode {
        get { iPadTodayLayoutMode(rawValue: layoutModeRaw) ?? .focus }
        set { layoutModeRaw = newValue.rawValue }
    }

    private var sidePanelBinding: Binding<iPadTodaySidePanel> {
        Binding(
            get: { sidePanel },
            set: { sidePanelRaw = $0.rawValue }
        )
    }

    private var layoutModeBinding: Binding<iPadTodayLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutModeRaw = $0.rawValue }
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
        if isRegularWidth && layoutMode == .mac && width >= 1_500 {
            threePaneTodayLayout(width: width)
        } else if isRegularWidth {
            twoPaneTodayLayout(width: width)
        } else {
            compactTodayLayout
        }
    }

    private func threePaneTodayLayout(width: CGFloat) -> some View {
        let notesWidth = min(max(width * 0.23, 280), 340)
        let scheduleWidth = min(max(width * 0.24, 300), 360)

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
                maxWidth: 540
            )
            .layoutPriority(0.42)
        }
    }

    private func taskPaneWidth(for width: CGFloat) -> CGFloat {
        let inspectorFloor = sidePanelMinWidth(for: width)
        let maximumTaskWidth = max(420, width - inspectorFloor)
        let proposedWidth = width * 0.60
        return min(max(proposedWidth, 520), min(maximumTaskWidth, 760))
    }

    private func sidePanelMinWidth(for width: CGFloat) -> CGFloat {
        width < 900 ? 320 : 370
    }

    private func sidePanelIdealWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.40, sidePanelMinWidth(for: width)), 540)
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
            iPadTodayTaskHeader(
                eyebrow: DateFormatters.longDate.string(from: Date()),
                title: "Today",
                summary: todaySummary,
                layoutMode: layoutModeBinding
            )

            Divider().background(Theme.borderSubtle)

            todayPlanningDeck

            Divider().background(Theme.borderSubtle.opacity(0.72))

            todayTaskSections
        }
        .background(Theme.surface)
    }

    private var todayPlanningDeck: some View {
        VStack(alignment: .leading, spacing: 11) {
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    todaySummaryStrip
                        .layoutPriority(1)

                    iOSTaskViewOptionsBar(
                        sortMode: Binding(
                            get: { sortMode },
                            set: { sortModeRaw = $0.rawValue }
                        ),
                        showCompleted: $showCompleted,
                        completedCount: completedTodayTasks.count
                    )
                    .frame(width: 232)
                }

                VStack(alignment: .leading, spacing: 10) {
                    todaySummaryStrip

                    iOSTaskViewOptionsBar(
                        sortMode: Binding(
                            get: { sortMode },
                            set: { sortModeRaw = $0.rawValue }
                        ),
                        showCompleted: $showCompleted,
                        completedCount: completedTodayTasks.count
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.bg.opacity(0.36))
    }

    private var todaySummaryStrip: some View {
        iPadTodaySummaryStrip(summary: todaySummary)
    }

    @ViewBuilder
    private var todayTaskSections: some View {
        if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    #if DEBUG
                    iPadTodayEmptyReviewDeck(
                        timedCount: compactScheduleTasks.count,
                        completedCount: completedTodayTasks.count,
                        selectedPanel: sidePanelBinding,
                        sampleDataStatus: sampleDataStatus,
                        seedSampleData: seedSampleData
                    )
                    #else
                    iPadTodayEmptyReviewDeck(
                        timedCount: compactScheduleTasks.count,
                        completedCount: completedTodayTasks.count,
                        selectedPanel: sidePanelBinding
                    )
                    #endif

                    iPadTodayStarterHints()
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.surface)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(todayTaskGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            iOSTaskSectionHeader(
                                title: group.title,
                                color: CadenceTodayPresentationSupport.accent(for: group.kind)
                            )

                            ForEach(group.tasks) { task in
                                iOSTaskRow(task: task, density: todayRowDensity)
                            }
                        }
                    }

                    if showCompleted && !completedTodayTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            iOSTaskSectionHeader(title: "Completed Today", color: Theme.green)

                            ForEach(completedTodayTasks.prefix(12)) { task in
                                iOSTaskRow(task: task, density: todayRowDensity)
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

    private var todayRowDensity: iOSTaskRowDensity {
        isRegularWidth ? .regular : .compact
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

#endif
