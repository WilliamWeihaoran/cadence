#if os(iOS)
import SwiftData
import SwiftUI

struct iPadTodayView: View {
    /// Off when the Tasks tab is hosting this as its Today segment: the tab's own header already
    /// carries the date, the greeting and the switcher that says which slice you are on, so the
    /// page heading below it would be the second title on one screen. Still on when Today is a
    /// *pushed* screen (Search results reach it that way), where the header is also the only row
    /// the back control has.
    var showsCompactHeader = true
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

    /// Every task pinned to a time today. The `.prefix(3)` this used to carry was left over from a
    /// deleted three-row schedule preview on the compact layout; its only remaining reader is the
    /// summary, which was therefore capping its own "timed" count at three.
    private var timedTodayTasks: [AppTask] {
        CadenceScheduleSupport.scheduledTasks(on: todayKey, from: allTasks, includeCompleted: false, excludeBundled: false)
            .filter { $0.scheduledStartMin >= 0 }
    }

    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(from: todayTasks, todayKey: todayKey)
    }

    private var todaySummary: CadenceTodaySummary {
        CadenceTodayPresentationSupport.summary(
            activeTasks: todayTasks,
            timedTasks: timedTodayTasks,
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
        // No `.navigationTitle("Today")`. Both layouts head themselves — the compact one with
        // "THURSDAY, AUGUST 13 / Today", the iPad one with `iPadTodayTaskHeader` — so a large nav
        // title said "Today" a second time, 60pt above the first.
        .iOSHidesCompactNavigationBar()
    }

    @ViewBuilder
    private func todayLayout(width: CGFloat) -> some View {
        // The threshold used to be a bare `width >= 1_500`, which no iPad reaches — see
        // `CadenceTodayLayoutSupport`, which derives the real floor from the panes' own minimums.
        switch CadenceTodayLayoutSupport.layout(
            prefersThreePane: layoutMode == .mac,
            isRegularWidth: isRegularWidth,
            paneWidth: width
        ) {
        case .threePane:
            threePaneTodayLayout(width: width)
        case .twoPane:
            twoPaneTodayLayout(width: width)
        case .compact:
            compactTodayLayout
        }
    }

    private func threePaneTodayLayout(width: CGFloat) -> some View {
        let notesWidth = min(max(width * 0.23, CadenceTodayLayoutSupport.notesPaneMinWidth), 340)
        let scheduleWidth = min(max(width * 0.24, CadenceTodayLayoutSupport.schedulePaneMinWidth), 360)

        return HStack(spacing: 0) {
            iOSNotesPanel(useStandardHeaderHeight: true)
                .frame(width: notesWidth)
                .layoutPriority(0.22)

            Divider().background(Theme.borderSubtle)

            todayTaskColumn(paneWidth: width)
                .frame(minWidth: CadenceTodayLayoutSupport.taskPaneMinWidth, maxWidth: .infinity)
                .layoutPriority(1)

            Divider().background(Theme.borderSubtle)

            iOSSchedulePanel()
                .frame(width: scheduleWidth)
                .layoutPriority(0.28)
        }
    }

    private func twoPaneTodayLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            todayTaskColumn(paneWidth: width)
                .frame(width: taskPaneWidth(for: width))
                .layoutPriority(0.58)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 0) {
                iPadTodayInspectorSwitcher(selection: sidePanelBinding)

                Divider().background(Theme.borderSubtle)

                inspectorPanelContent
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

    /// The two-pane inspector's body. Neither panel draws its own page title here: the switcher row
    /// directly above already has the panel's name lit up in it, and drawing it again — plus, in
    /// the timeline's case, a `SCHEDULE` eyebrow over it — was the same word three times in 120pt.
    /// `useStandardHeaderHeight` goes with it; it pins the notes header to 120pt so it lines up
    /// with the panes *beside* it, and in this layout there are none.
    @ViewBuilder
    private var inspectorPanelContent: some View {
        switch sidePanel {
        case .notes:
            iOSNotesPanel(showsTitle: false)
        case .timeline:
            iOSSchedulePanel(showsHeader: false)
        }
    }

    @ViewBuilder
    private var compactTodayLayout: some View {
        #if DEBUG
        iOSCompactTodayView(
            showsHeader: showsCompactHeader,
            todayTasks: todayTasks,
            completedTodayTasks: completedTodayTasks,
            todayTaskGroups: todayTaskGroups,
            showCompleted: $showCompleted,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSCompactTodayView(
            showsHeader: showsCompactHeader,
            todayTasks: todayTasks,
            completedTodayTasks: completedTodayTasks,
            todayTaskGroups: todayTaskGroups,
            showCompleted: $showCompleted
        )
        #endif
    }

    private func todayTaskColumn(paneWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            iPadTodayTaskHeader(
                eyebrow: DateFormatters.longDate.string(from: Date()),
                title: "Today",
                summary: todaySummary,
                layoutMode: layoutModeBinding,
                // The picker used to offer Mac at every width and do nothing below the threshold.
                // Below the floor there is genuinely no room for three columns, so the option says
                // so rather than accepting a tap and changing nothing.
                allowsThreePane: CadenceTodayLayoutSupport.supportsThreePane(paneWidth: paneWidth)
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

            iOSTaskViewOptionsBar(
                sortMode: Binding(
                    get: { sortMode },
                    set: { sortModeRaw = $0.rawValue }
                ),
                showCompleted: $showCompleted,
                completedCount: completedTodayTasks.count
            )

            // Absent on an unplanned day rather than reading "0 timed · 0 done", so the deck does
            // not reserve a band for a sentence it has nothing to put in. See
            // `CadenceTodaySummary.line`.
            iPadTodaySummaryLine(summary: todaySummary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.bg.opacity(0.36))
    }

    @ViewBuilder
    private var todayTaskSections: some View {
        if todayTasks.isEmpty && (!showCompleted || completedTodayTasks.isEmpty) {
            // The same one card the phone shows, not a deck. This was five instructional cards —
            // "Write notes", "Check timeline", "Completed", "Capture", and a "Plan" card whose text
            // read "Use the inspector to switch notes and timeline", describing the screen it was
            // drawn on. An empty day looks empty and says so once.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    iOSCompactTodayEmptyState()
                        .cadenceCard(background: Theme.surfaceElevated.opacity(0.36), cornerRadius: Theme.radiusCard)

                    #if DEBUG
                    iOSCompactSampleDataCard(
                        status: sampleDataStatus,
                        action: seedSampleData
                    )
                    #endif
                }
                .frame(maxWidth: 520, alignment: .leading)
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
