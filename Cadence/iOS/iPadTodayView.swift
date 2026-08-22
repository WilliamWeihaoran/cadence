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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @AppStorage("ios.today.sortMode") private var sortModeRaw = CadenceTaskSortMode.priority.rawValue
    @AppStorage("ios.today.showCompleted") private var showCompleted = false
    @AppStorage("ios.today.sidePanel") private var sidePanelRaw = iPadTodaySidePanel.notes.rawValue
    /// The **same** `UserDefaults` key macOS's Today reads — see
    /// `CadenceTodayRolloverSupport.dismissedDateStorageKey` for why one key rather than two.
    @AppStorage(CadenceTodayRolloverSupport.dismissedDateStorageKey) private var rolloverNoticeDismissedDate = ""
    /// Written by the rollover banner's confirm, and — in DEBUG — by the sample-data seeder. It was
    /// inside the `#if DEBUG` below when the seeder was its only writer.
    @Environment(\.modelContext) private var modelContext
    #if DEBUG
    @State private var sampleDataStatus: String?
    #endif

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// Read-only: `sortModeBinding` below is the write path. The setter this used to carry was
    /// uncallable — a `View`'s `body` cannot mutate `self`.
    private var sortMode: CadenceTaskSortMode {
        CadenceTaskSortMode(rawValue: sortModeRaw) ?? .priority
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

    /// Yesterday's unfinished plans, as the rollover banner offers them. Shared with macOS's Today
    /// (T-195), predicate and all.
    private var pastDoTasks: [AppTask] {
        CadenceTodayRolloverSupport.pastDoTasks(from: allTasks, todayKey: todayKey)
    }

    private var isRolloverNoticeVisible: Bool {
        CadenceTodayRolloverSupport.isNoticeVisible(
            pastDoTaskCount: pastDoTasks.count,
            dismissedDateKey: rolloverNoticeDismissedDate,
            todayKey: todayKey
        )
    }

    /// The banner is already listing the tasks it is offering to roll, so the grouped list below it
    /// withholds them — a Past Do section under the notice would be the same rows twice. Dismissing
    /// merges them straight back in; `groupedTasks` returns the array whole once the notice is
    /// down, and nothing is written to make that happen.
    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(
            from: CadenceTodayRolloverSupport.groupedTasks(
                from: todayTasks,
                withholding: pastDoTasks,
                isNoticeVisible: isRolloverNoticeVisible
            ),
            todayKey: todayKey
        )
    }

    /// `nil` when there is nothing to roll or the day's notice has already been dismissed. The
    /// banner opts in whole — the tasks and the action are useless apart.
    private var rolloverNotice: iOSTodayRolloverNotice? {
        guard isRolloverNoticeVisible else { return nil }
        return iOSTodayRolloverNotice(tasks: pastDoTasks, onRollOver: rollOverPastDoTasks)
    }

    private func rollOverPastDoTasks() {
        withAnimation(.easeOut(duration: 0.2)) {
            rolloverNoticeDismissedDate = CadenceTodayRolloverSupport.rollOver(
                pastDoTasks,
                todayKey: todayKey,
                modelContext: modelContext
            )
        }
    }

    private var todaySummary: CadenceTodaySummary {
        CadenceTodayPresentationSupport.summary(
            activeTasks: todayTasks,
            timedTasks: timedTodayTasks,
            completedTasks: completedTodayTasks
        )
    }

    /// One binding, handed to whichever layout is on screen. Both widths carry the same sort and
    /// completed controls — see `CadenceTaskSurfaceOptions`.
    private var sortModeBinding: Binding<CadenceTaskSortMode> {
        Binding(
            get: { sortMode },
            set: { sortModeRaw = $0.rawValue }
        )
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
        // Seeded with today's do date, which is what the "Add a task for today…" field it replaced
        // did implicitly and silently. The button says nothing about the date; the sheet's chip
        // strip shows it, so the assumption is visible before the task is created.
        .iOSFloatingCreateTaskButton(seed: CadenceTaskComposerSeed(doDateKey: todayKey))
        // No `.navigationTitle("Today")`. Both layouts head themselves — the compact one with
        // "THURSDAY, AUGUST 13 / Today", the iPad one with `iPadTodayTaskHeader` — so a large nav
        // title said "Today" a second time, 60pt above the first.
        .iOSHidesCompactNavigationBar()
    }

    @ViewBuilder
    private func todayLayout(width: CGFloat) -> some View {
        // Two panes or one; there is no third layout and no stored preference feeding this. See
        // `CadenceTodayLayoutSupport`, which derives the two-pane floor from the panes' own
        // minimums.
        switch CadenceTodayLayoutSupport.layout(isRegularWidth: isRegularWidth, paneWidth: width) {
        case .twoPane:
            twoPaneTodayLayout(width: width)
        case .compact:
            compactTodayLayout
        }
    }

    /// Every width here comes from `CadenceTodayLayoutSupport`, which also owns the floor that
    /// decides whether this layout renders at all. It used to own the floor while this view owned
    /// the widths, and the two disagreed about whether the `Divider()` below existed — see
    /// `taskPaneWidth(forPaneWidth:)`.
    private func twoPaneTodayLayout(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            todayTaskColumn
                .frame(width: CadenceTodayLayoutSupport.taskPaneWidth(forPaneWidth: width))
                .layoutPriority(0.58)

            Divider().background(Theme.borderSubtle)

            VStack(spacing: 0) {
                iPadTodayInspectorSwitcher(selection: sidePanelBinding)

                Divider().background(Theme.borderSubtle)

                inspectorPanelContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // No maximum. The 540 that used to sit here needed a 1350pt pane; the widest this view
            // can be handed on a target device is 1210 — an 11" Pro in landscape with the shell
            // sidebar folded — where the ideal is 484.
            .frame(
                minWidth: CadenceTodayLayoutSupport.inspectorPaneFloor(forPaneWidth: width),
                idealWidth: CadenceTodayLayoutSupport.inspectorPaneIdealWidth(forPaneWidth: width)
            )
            .layoutPriority(0.42)
        }
    }

    /// The two-pane inspector's body. Neither panel draws its own page title here: the switcher row
    /// directly above already has the panel's name lit up in it, and drawing it again — plus, in
    /// the timeline's case, a `SCHEDULE` eyebrow over it — was the same word three times in 120pt.
    @ViewBuilder
    private var inspectorPanelContent: some View {
        switch sidePanel {
        case .notes:
            iOSNotesView(showsTitle: false)
        case .timeline:
            iOSSchedulePanel()
        }
    }

    @ViewBuilder
    private var compactTodayLayout: some View {
        #if DEBUG
        iOSCompactTodayView(
            showsHeader: showsCompactHeader,
            completedTodayTasks: completedTodayTasks,
            todayTaskGroups: todayTaskGroups,
            rolloverNotice: rolloverNotice,
            summary: todaySummary,
            sortMode: sortModeBinding,
            showCompleted: $showCompleted,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSCompactTodayView(
            showsHeader: showsCompactHeader,
            completedTodayTasks: completedTodayTasks,
            todayTaskGroups: todayTaskGroups,
            rolloverNotice: rolloverNotice,
            summary: todaySummary,
            sortMode: sortModeBinding,
            showCompleted: $showCompleted
        )
        #endif
    }

    /// Header, then tasks. There is no band between them any more: the "planning deck" that used to
    /// sit there held the sort/completed bar and the summary line, both of which now ride on the
    /// header row itself — see `iPadTodayTaskHeader`. It cost ~70pt of a column whose whole job is
    /// showing tasks, and it was the last chrome band left after the capture field ("Add a task for
    /// today…", replaced by the corner composer button) and the layout picker were removed from it.
    private var todayTaskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            iPadTodayTaskHeader(
                eyebrow: DateFormatters.longDate.string(from: Date()),
                title: "Today",
                summary: todaySummary,
                sortMode: sortModeBinding,
                showCompleted: $showCompleted
            )

            Divider().background(Theme.borderSubtle)

            todayTaskSections
        }
        .background(Theme.surface)
    }

    /// `iOSTodayTaskSections`, which is also what the phone's Today draws — one list, one empty
    /// state, one group spacing. This was a second copy of both halves: 15pt between groups against
    /// the phone's 14, an empty state padded 18 against the phone's 14, and the branch between them
    /// spelled out again from `todayTasks` rather than from the groups.
    ///
    /// The scroll container and its gutters stay here, because they are the *column's* and not the
    /// list's — the header above sits outside this scroll view so a two-pane column keeps its title
    /// while the rows move.
    private var todayTaskSections: some View {
        ScrollView {
            todaySections
                .frame(
                    maxWidth: iOSTodayTaskSections.contentMaxWidth(layout: .twoPane),
                    alignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface)
    }

    private var todaySections: some View {
        #if DEBUG
        iOSTodayTaskSections(
            layout: .twoPane,
            taskGroups: todayTaskGroups,
            completedTasks: completedTodayTasks,
            showsCompleted: showCompleted,
            rolloverNotice: rolloverNotice,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSTodayTaskSections(
            layout: .twoPane,
            taskGroups: todayTaskGroups,
            completedTasks: completedTodayTasks,
            showsCompleted: showCompleted,
            rolloverNotice: rolloverNotice
        )
        #endif
    }

    // `todayRowDensity` is gone with `iOSTaskRowDensity` — and it was already dead in the direction
    // it named: this column only renders inside `twoPaneTodayLayout`, which
    // `CadenceTodayLayoutSupport.layout` reaches only at regular width, so its `.compact` branch
    // could not be taken. The row reads `horizontalSizeClass` itself now.

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
