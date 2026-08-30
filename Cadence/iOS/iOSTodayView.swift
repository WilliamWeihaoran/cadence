#if os(iOS)
import SwiftData
import SwiftUI

struct iOSTodayView: View {
    /// Off when the Tasks tab is hosting this as its Today segment: the tab's own header already
    /// carries the date, the greeting and the switcher that says which slice you are on, so the
    /// page heading below it would be the second title on one screen. Still on when Today is a
    /// *pushed* screen (Search results reach it that way), where the header is also the only row
    /// the back control has.
    var showsCompactHeader = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    /// For the past-due summaries only. A *column*'s due date lives in `sectionConfigsRaw` on the
    /// list, not on any task, so no query over `AppTask` can find one — see
    /// `CadenceTodayOverdueSummarySupport`.
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    /// For the *order* of Today's list groups only — `CadenceTaskQuerySupport.listGroupOrder`
    /// presents them in sidebar order, which is a context-by-context walk (T-305).
    @Query(sort: \Context.order) private var contexts: [Context]
    @AppStorage("ios.today.sortMode") private var sortModeRaw = CadenceTaskSortMode.priority.rawValue
    @AppStorage("ios.today.showCompleted") private var showCompleted = false
    @AppStorage("ios.today.sidePanel") private var sidePanelRaw = iOSTodaySidePanel.notes.rawValue
    /// The **same** `UserDefaults` key macOS's Today reads — see
    /// `CadenceTodayRolloverSupport.dismissedDateStorageKey` for why one key rather than two.
    @AppStorage(CadenceTodayRolloverSupport.dismissedDateStorageKey) private var rolloverNoticeDismissedDate = ""
    /// Written by the rollover banner's confirm, and — in DEBUG — by the sample-data seeder. It was
    /// inside the `#if DEBUG` below when the seeder was its only writer.
    @Environment(\.modelContext) private var modelContext
    /// Set by a tap on a past-due summary card, cleared when the sheet closes. See
    /// `openList(_:)` for why this is a presentation and not a navigation.
    @State private var pendingListOpen: CadenceListOpenRequest?
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
    /// withholds them — the same rows under the notice *and* in their lists' groups would be the
    /// same rows twice. Dismissing merges them straight back in; `groupedTasks` returns the array
    /// whole once the notice is down, and nothing is written to make that happen.
    ///
    /// **The withholding is what makes the roll visible now** (T-305). The offered tasks are held
    /// out of their own lists' groups, so confirming the roll does not shuffle rows between two
    /// date buckets — a list group appears, or grows, with the work that was yesterday's.
    private var todayTaskGroups: [CadenceTodayTaskGroup] {
        CadenceTaskQuerySupport.todayGroups(
            from: CadenceTodayRolloverSupport.groupedTasks(
                from: todayTasks,
                withholding: pastDoTasks,
                isNoticeVisible: isRolloverNoticeVisible
            ),
            todayKey: todayKey,
            contexts: contexts
        )
    }

    /// `nil` when there is nothing to roll or the day's notice has already been dismissed. The
    /// banner opts in whole — the tasks and the action are useless apart.
    private var rolloverNotice: iOSTodayRolloverNotice? {
        guard isRolloverNoticeVisible else { return nil }
        return iOSTodayRolloverNotice(tasks: pastDoTasks, onRollOver: rollOverPastDoTasks)
    }

    /// The day's past-due lists and columns, or `nil` when there are none — the second half of
    /// T-195, and the same "opted into whole" shape as the notice above.
    private var overdueSummaries: iOSTodayOverdueSummaries? {
        let lists = CadenceTodayOverdueSummarySupport.listSummaries(projects: projects, todayKey: todayKey)
        let sections = CadenceTodayOverdueSummarySupport.sectionSummaries(
            areas: areas,
            projects: projects,
            todayKey: todayKey
        )
        guard !lists.isEmpty || !sections.isEmpty else { return nil }
        return iOSTodayOverdueSummaries(
            listSummaries: lists,
            sectionSummaries: sections,
            onOpen: openList
        )
    }

    /// **The card presents the list; it does not navigate to it.** This is the one genuinely
    /// platform-shaped piece of T-195's second half, and it resolves differently from macOS on
    /// purpose.
    ///
    /// macOS's cards hop `ListNavigationManager`, which sets a request the sidebar and
    /// `ListDetailView` consume. That is right there because the Mac's sidebar never leaves the
    /// screen: opening a list is a change of pane and Today is one click back. Neither iOS shell
    /// can say the same thing that cheaply. On iPhone, Today is the Tasks tab's root, so a push
    /// buries the day you were triaging under a stack; on iPad it is a detail pane with **no
    /// `NavigationStack` around it at all** (`iOSRootView.detailView(for:)` wraps Notes, Lists and
    /// Search and not Today), so a `navigationDestination` here would be a control that compiles
    /// and does nothing. Routing through the shell instead would mean teaching `iOSRootView` a
    /// second router — one more thing that has to know about both shells — for a card whose whole
    /// job is a glance.
    ///
    /// A sheet says what the excursion actually is: look at the column, close it, carry on reading
    /// your day. It is also the one answer that is *identical* on both widths, which is the
    /// standing rule about iPhone and iPad sharing one style rather than one layout.
    private func openList(_ request: CadenceListOpenRequest) {
        pendingListOpen = request
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

    private var sidePanel: iOSTodaySidePanel {
        iOSTodaySidePanel(rawValue: sidePanelRaw) ?? .notes
    }

    private var sidePanelBinding: Binding<iOSTodaySidePanel> {
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
        // Unseeded, like every other `+` in the app. It used to hand in today's do date, which is
        // what the "Add a task for today…" field it replaced did implicitly — T-337 takes that
        // back: standing on Today is not a statement that the task is for today. Dropping the
        // button on one of this page's **list groups** still is, and that path seeds the day as
        // well as the list — `CadenceTaskGroupDropIdentity.todayList`. That pairing is what keeps
        // the unseeded button honest here: without it a `+` dropped on Today would produce work
        // that vanished off Today.
        .iOSFloatingCreateTaskButton()
        // No `.navigationTitle("Today")`. Both layouts head themselves — the compact one with
        // "THURSDAY, AUGUST 13 / Today", the iPad one with `iPadTodayTaskHeader` — so a large nav
        // title said "Today" a second time, 60pt above the first.
        .iOSHidesCompactNavigationBar()
        // Presented by the **page**, not by a card. The rule this looks like it is breaking —
        // "the task inspector is presented by a host, never by a row" — is about a presenter that
        // its own query can remove out from under the sheet. A card here sits in a `ForEach` over
        // summaries that a write inside the list *can* empty, which is exactly why the presenter is
        // `iOSTodayView` and not `CadenceTodayOverdueListCard`.
        .sheet(item: $pendingListOpen) { request in
            iOSTodayOverdueListSheet(request: request)
        }
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
            overdueSummaries: overdueSummaries,
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
            overdueSummaries: overdueSummaries,
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
            overdueSummaries: overdueSummaries,
            sampleDataStatus: sampleDataStatus,
            seedSampleData: seedSampleData
        )
        #else
        iOSTodayTaskSections(
            layout: .twoPane,
            taskGroups: todayTaskGroups,
            completedTasks: completedTodayTasks,
            showsCompleted: showCompleted,
            rolloverNotice: rolloverNotice,
            overdueSummaries: overdueSummaries
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
