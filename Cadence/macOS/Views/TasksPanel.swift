#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Tasks Panel

struct TasksPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]
    let showsHeader: Bool
    let sortMode: CadenceTaskSortMode
    let enableControls: Bool
    let useStandardHeaderHeight: Bool
    @AppStorage(CadenceTodayRolloverSupport.dismissedDateStorageKey) private var rolloverNoticeDismissedDate = ""
    /// Set when the roll was refused, and read by the banner, which is still on screen because the
    /// dismissal above was not written. Cleared by the next roll that lands.
    @State private var rolloverFailureNotice: String?
    /// Set when the store refused a row drop (T-868). The rows have already been put back by then,
    /// so the panel and this sentence agree — which is the whole reason a reorder reports at all:
    /// without it a refused drop is a row that springs back for no stated reason and comes back
    /// wrong at next launch.
    @State private var reorderFailureNotice: String?
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var isCompletedCollapsed = true
    @State private var localSortMode: CadenceTaskSortMode = .macOSTodayDefault
    @State private var frozenTaskOrder: [AppTask]? = nil
    @State private var dragOverTaskID: UUID? = nil

    init(
        showsHeader: Bool = true,
        sortMode: CadenceTaskSortMode = .macOSTodayDefault,
        enableControls: Bool = false,
        useStandardHeaderHeight: Bool = false
    ) {
        self.showsHeader = showsHeader
        self.sortMode = sortMode
        self.enableControls = enableControls
        self.useStandardHeaderHeight = useStandardHeaderHeight
        _localSortMode = State(initialValue: Self.storedSortMode(in: .standard, fallback: sortMode))
    }

    /// Which `CadenceTaskSurface` this panel is drawing, so the chrome answers come from the
    /// shared table rather than from four inline decisions (T-290). One surface, since T-487: the
    /// `.byDoDate` mode that answered `.allTasks` here was unreachable and is gone. The All Tasks
    /// *page* is `TasksPageView`, which has never built one of these panels.
    private var surface: CadenceTaskSurface { .today }

    /// See `surface`. Read for the sort chips, the Completed section, and whether a row names its
    /// list — the three things this panel used to answer for itself.
    private var options: CadenceTaskViewOptions {
        CadenceTaskSurfaceOptions.options(for: surface)
    }

    private var activeSortMode: CadenceTaskSortMode { enableControls ? localSortMode : sortMode }

    /// Where this panel's sort preference is written. It used to be
    /// `mode == .todayOverview ? "today" : "allTasks"`; the second half went with `.byDoDate`
    /// (T-487). The `allTasks*` keys are still live — `TasksPageView` owns them.
    private static let udPrefix = "today"

    /// The key T-606 writes. New rather than reused, because the value stored under it is a
    /// different vocabulary: `todaySortField` holds `TaskSortField` raw values (`"Date"`), this
    /// holds `CadenceTaskSortMode` raw values (`"doDate"`), and one key holding both would make
    /// every read ambiguous.
    static let sortModeDefaultsKey = udPrefix + "SortMode"

    /// The pre-T-606 keys. Still read once, by `storedSortMode(in:fallback:)`, and deliberately
    /// **not** deleted: nothing is gained by destroying the only record of what the user chose,
    /// and a build rolled back to the two chips still finds its preference intact.
    static let legacySortFieldDefaultsKey = udPrefix + "SortField"
    static let legacySortDirectionDefaultsKey = udPrefix + "SortDirection"

    /// Today's stored sort mode, and the one place the retired two-chip preference is migrated.
    ///
    /// `todaySortMode` wins whenever it decodes. Otherwise the legacy `todaySortField` is mapped
    /// through `CadenceTaskSortMode.migratedFromMacOSTodaySortField`, which is where the mapping
    /// and its comparator evidence are written down. `todaySortDirection` is read by nothing: the
    /// Order chip is gone and direction folded into the named modes.
    ///
    /// **Nothing here can fail to produce a value.** A raw value neither vocabulary recognises —
    /// the hazard in removing a persisted case with no `SchemaMigrationPlan` behind it — falls
    /// through both `init(rawValue:)` calls to `fallback`, which is `.macOSTodayDefault` at every
    /// live call site.
    static func storedSortMode(in defaults: UserDefaults, fallback: CadenceTaskSortMode) -> CadenceTaskSortMode {
        if let raw = defaults.string(forKey: sortModeDefaultsKey),
           let mode = CadenceTaskSortMode(rawValue: raw) {
            return mode
        }
        guard let legacy = defaults.string(forKey: legacySortFieldDefaultsKey) else { return fallback }
        return CadenceTaskSortMode.migratedFromMacOSTodaySortField(legacy)
    }

    private var todayKey: String { DateFormatters.todayKey() }

    /// Expensive: four filters, a full sort, a `sectionConfigs` decode per active list, and a
    /// pass over every completed task ever created. Build it **once per body pass** and thread
    /// the value down (`body` does exactly that) — the eleven forwarding computed properties
    /// this replaced each rebuilt the whole thing on every access.
    private var derivedState: TasksPanelDerivedState {
        TasksPanelDerivedState(allTasks: allTasks, todayKey: todayKey)
    }

    /// `CadenceTodayRolloverSupport.isNoticeVisible`, the same predicate iOS's Today asks. This
    /// used to lead with `mode == .todayOverview &&`, guarding against the All Tasks shape of the
    /// panel; that shape was unreachable and is gone (T-487).
    private func shouldShowRolloverNotice(_ derived: TasksPanelDerivedState) -> Bool {
        CadenceTodayRolloverSupport.isNoticeVisible(
            pastDoTaskCount: derived.overdoTasks.count,
            dismissedDateKey: rolloverNoticeDismissedDate,
            todayKey: todayKey
        )
    }

    private func applyFreeze(_ sorted: [AppTask]) -> [AppTask] {
        applyFrozenTaskOrder(sorted, frozen: frozenTaskOrder)
    }

    private var dropCoordinator: TasksPanelDropCoordinator {
        TasksPanelDropCoordinator(
            allTasks: allTasks,
            taskIDFromPayload: { TasksPanelSupport.taskID(from: $0) },
            assignTask: { task, dropKey in
                TasksPanelSupport.assignTask(
                    task,
                    for: dropKey,
                    todayKey: todayKey,
                    areas: areas,
                    projects: projects,
                    modelContext: modelContext
                )
            },
            reorderTask: { droppedID, targetID, scopeTasks in
                let reordered = TasksPanelSupport.reorderTask(
                    droppedID: droppedID,
                    targetID: targetID,
                    scopeTasks: scopeTasks,
                    modelContext: modelContext
                )
                reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
                return reordered
            }
        )
    }

    var body: some View {
        let derived = derivedState
        // **Asked once per body pass, and handed to both halves.** The rows and the hover freeze
        // must agree about whether the rollover banner is up, because the banner withholds rows —
        // see `naturalTodayRows`.
        let showsRollover = shouldShowRolloverNotice(derived)

        // Split into two statements purely to keep the type checker inside its time budget —
        // one chain off a `let`-bound `derived` was enough to blow it.
        let shell = panelShell(derived: derived, showsRollover: showsRollover)
            .background(
                Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
            )
            .background(Theme.surface)
            .background { hoverFreezeObserver(derived: derived, showsRollover: showsRollover) }

        return shell
            .onAppear {
                isCompletedCollapsed = true
            }
            .onChange(of: localSortMode) { _, v in
                UserDefaults.standard.set(v.rawValue, forKey: Self.sortModeDefaultsKey)
            }
    }

    private func panelShell(derived: TasksPanelDerivedState, showsRollover: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                headerSection(derived: derived)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    todayOverviewSections(derived: derived, showsRollover: showsRollover)
                    completedSection(derived: derived)
                    emptyStateSection(derived: derived)
                }
                .padding(.top, showsHeader ? 12 : 0)
                .padding(.bottom, 16)
            }
            .cadenceSoftPageBounce()
        }
    }

    private func headerSection(derived: TasksPanelDerivedState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TasksPanelHeader(summary: todaySummary(derived: derived))
                if enableControls {
                    controlsBar
                }
            }
            .frame(height: useStandardHeaderHeight ? todayPanelHeaderHeight : nil, alignment: .top)
            Divider().background(Theme.borderSubtle)
        }
    }

    /// The panel's sections, called straight from `panelShell`. A `taskSections(derived:)`
    /// forwarder used to sit above this holding `switch mode { case .todayOverview: }`, and it went
    /// with `TasksPanelMode` itself (T-564(a)).
    @ViewBuilder
    private func todayOverviewSections(derived: TasksPanelDerivedState, showsRollover: Bool) -> some View {
        if let reorderFailureNotice {
            CadenceInlineFailureNotice(text: reorderFailureNotice)
                .padding(.horizontal, TasksPanelMetrics.horizontalInset)
                .padding(.bottom, 8)
        }
        if showsRollover {
            CadenceTodayRolloverBanner(
                tasks: derived.overdoTasks,
                style: .panelBand,
                failureNotice: rolloverFailureNotice
            ) {
                rollOverPastDoTasks()
            }
        }
        // `PAST DUE LISTS` and `PAST DUE SECTIONS` were two bands of cards here. They are gone with
        // the Overdue group, as one decision rather than two: *"remove these past due list displays
        // from today's view"*. Today was stating overdue-ness three ways — a per-task section, these
        // per-list and per-column summaries, and the red flag on the row itself — and only the last
        // says it where you can act on it. The cards also navigated *away* from the day, which is
        // the opposite of what a triage page is for.
        //
        // `CadenceTodayOverdueSummarySupport` and its two cards are untouched: **iOS's Today still
        // draws both bands**, so this is a macOS call-site removal, not a component deletion.

        todayGroupSections(derived: derived, showsRollover: showsRollover)
    }

    /// Today's groups, and the whole of them: **the day's work, by list** — one axis, no others.
    ///
    /// They come from `CadenceTaskQuerySupport.todayListGroups`, the shared function both iOS
    /// Todays call, so the page's shape is decided once for both platforms. It was four date
    /// buckets (Overdue, Past Do, Due Today, Planned Today), then one date bucket over the list
    /// groups (Overdue), and is now none: *"there shouldn't be an overdue/overdo section but all
    /// tasks should be grouped by lists"*.
    ///
    /// **Nothing is lost with the red section.** A missed deadline is stated by the row's own flag,
    /// which goes red on both platforms and is where every other surface in the app states it; the
    /// section said the same thing a second time, and paid for it by splitting a list's work across
    /// two headings, so a list could be represented twice on one page. What the date axis is still
    /// worth is *inside* a group: `compareTasksForCurrentSort` leads with `todayTaskSortRank`, so a
    /// list reads past-do, then due-today, then do-today without a heading to say so.
    ///
    /// The rollover banner still withholds the over-do tasks it is offering to roll. Those rows are
    /// missing from *their lists'* groups, which is what makes confirming the roll do something
    /// visible — and the hover freeze is fed the same withheld array, which is the other half of
    /// this change. See `naturalTodayRows`.
    @ViewBuilder
    private func todayGroupSections(derived: TasksPanelDerivedState, showsRollover: Bool) -> some View {
        let tasks = applyFreeze(naturalTodayRows(derived: derived, showsRollover: showsRollover))

        ForEach(CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: contexts)) { group in
            let dropKey = CadenceTaskDropSupport.dropKey(forGroup: group.dropIdentity)

            TasksPanelIntentSectionView(
                title: group.title,
                accent: group.accent,
                tasks: group.tasks,
                todayKey: todayKey,
                // **`false`, flatly.** This was `options.showsContainerChip &&
                // group.showsContainerChip`, and the group's half was exactly "am I Overdue".
                // Overdue was the one group drawn from every list at once, so there the chip was
                // the only thing saying where the work lived; every group left is a list, and its
                // header prints that list's name. `options.showsContainerChip` is still read — by
                // `completedSection`, which is flat and does need it.
                showsContainer: false,
                contexts: contexts,
                areas: areas,
                projects: projects,
                isCollapsed: collapsedGroupIDs.contains(group.id),
                dragOverTaskID: $dragOverTaskID,
                onToggle: { toggleGroup(group.id) },
                taskDragPayload: taskDragPayload,
                onDropOnSectionPayload: dropCoordinator.sectionDropHandler(for: dropKey),
                onDropOnTaskPayload: { payload, targetTask in
                    dropCoordinator.handleTaskDrop(
                        payload: payload,
                        targetTask: targetTask,
                        scopeTasks: group.tasks,
                        dropKey: dropKey
                    )
                }
            )
        }
    }

    /// Non-optional since T-487. It returned `CadenceTodaySummary?` and opened with
    /// `guard mode == .todayOverview else { return nil }` — the day's counts only mean anything on
    /// the day's page, and this panel is now only ever the day's page.
    private func todaySummary(derived: TasksPanelDerivedState) -> CadenceTodaySummary {
        CadenceTodayPresentationSupport.summary(
            activeTasks: derived.todayEligibleTasks,
            timedTasks: CadenceScheduleSupport.scheduledTasks(
                on: todayKey,
                from: allTasks,
                includeCompleted: false,
                excludeBundled: false
            )
            .filter { $0.scheduledStartMin >= 0 },
            completedTasks: derived.doneTasks
        )
    }

    @ViewBuilder
    private func completedSection(derived: TasksPanelDerivedState) -> some View {
        if options.showsCompletedToggle, !derived.doneTasks.isEmpty {
            TasksPanelCompletedSectionView(
                // The **desktop** tier, which `CadenceTaskSurfaceOptions` leaves uncapped — the
                // reasoning is in that file. Asked rather than assumed: the panel's own
                // `doneTasks` stays whole because `CadenceTodaySummary.completedCount` and
                // `isEmptyState` both count it, and a cap applied there would be a wrong number
                // rather than a shorter list.
                tasks: CadenceTaskSurfaceOptions.completedRows(from: derived.doneTasks, tier: .desktop),
                showsContainer: options.showsContainerChip,
                todayKey: todayKey,
                contexts: contexts,
                areas: areas,
                projects: projects,
                isCollapsed: isCompletedCollapsed,
                onToggle: { isCompletedCollapsed.toggle() },
                taskDragPayload: taskDragPayload
            )
        }
    }

    @ViewBuilder
    private func emptyStateSection(derived: TasksPanelDerivedState) -> some View {
        if derived.isEmptyState {
            // Today's copy is `CadenceTodayPresentationSupport`'s, which is what iOS's
            // `iOSCompactTodayEmptyState` draws. macOS said "Nothing for today" over
            // "Due-today and do-today tasks will appear here" — a restatement of the page's scope
            // where the shared subtitle names the next thing to do.
            //
            // The other arm read `CadenceEmptyStateCopy.allTasks*` and went with `.byDoDate`
            // (T-487). Those two constants stay live — iOS's `iOSTaskCollectionMetrics` draws the
            // All Tasks empty state from them. What is gone with the mode is a macOS empty state
            // that nothing could reach, which is why it still spelled "No tasks yet" / "Add a task
            // above to get started" for as long as it did: the first is a string T-285 retired,
            // and the second named a field that does not exist.
            EmptyStateView(
                message: CadenceTodayPresentationSupport.emptyTitle,
                subtitle: CadenceTodayPresentationSupport.emptySubtitle,
                icon: "checkmark.circle"
            )
            .padding(.top, 40)
        }
    }

    /// **The rows Today draws, in natural order — and therefore the only list the hover freeze may
    /// snapshot.**
    ///
    /// One function because there were two, and the disagreement between them was the flicker the
    /// user reported: "while i hover over different sections of tasks, some sections just glitch in
    /// and out … i think it's the tasks that are being rolled over that are appearing and
    /// disappearing".
    ///
    /// `todayGroupSections` drew `todayGroupedTaskItems`, which **withholds** the tasks the rollover
    /// banner is offering to roll. `hoverFreezeObserver` was handed `todayEligibleTasks`, which
    /// **includes** them. `applyFrozenTaskOrder` deliberately does not intersect the frozen order
    /// with the live list — a row that stops matching while you hover stays put instead of vanishing
    /// under the pointer (T-342) — so a frozen order built from the wider array put every withheld
    /// row back at the head of the page for as long as the freeze held, and took them away again
    /// when it released. `HoveredTaskManager` nils its hovered task 80ms after the pointer leaves a
    /// row, which a move between two sections comfortably exceeds, so the pair captured and released
    /// once per section boundary: rows appearing and disappearing as the pointer crossed.
    ///
    /// The freeze mechanism is fine and is unchanged. What was wrong was feeding it a different
    /// array from the one it freezes.
    private func naturalTodayRows(derived: TasksPanelDerivedState, showsRollover: Bool) -> [AppTask] {
        derived.todayGroupedTaskItems(showRolloverNotice: showsRollover)
            .sorted(by: compareTasksForCurrentSort)
    }

    private func hoverFreezeObserver(derived: TasksPanelDerivedState, showsRollover: Bool) -> some View {
        HoverFreezeObserver(
            frozenOrder: $frozenTaskOrder,
            naturalTasks: naturalTodayRows(derived: derived, showsRollover: showsRollover)
        )
    }

    /// **The dismissal is written only when the roll committed (T-635).**
    ///
    /// It used to be assigned from a `rollOver` that swallowed its save and returned today's key
    /// either way — and this one is an `@AppStorage` write, so unlike every other false success in
    /// the ledger it survived the rollback, the redraw and the relaunch: the banner stayed hidden
    /// for the rest of the day, on this Mac and on the phone, over yesterday's plans that were
    /// still exactly where they were.
    private func rollOverPastDoTasks() {
        do {
            let dismissed = try withAnimation(.easeOut(duration: 0.2)) {
                try CadenceTodayRolloverSupport.rollOver(
                    derivedState.overdoTasks,
                    todayKey: todayKey,
                    modelContext: modelContext
                )
            }
            rolloverFailureNotice = nil
            rolloverNoticeDismissedDate = dismissed
        } catch {
            rolloverFailureNotice = CadenceTodayRolloverSupport.rollFailureNotice
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 8) {
            if options.showsSort {
                CadenceEnumPickerBadge(title: "Sort", selection: $localSortMode)
            }
            Spacer()
        }
        .padding(.horizontal, TasksPanelMetrics.horizontalInset)
        .padding(.bottom, 10)
        .background(Theme.surface)
    }

    /// **Today ranks by urgency first, then by whatever the Sort chip says** — and the `!enableControls`
    /// half of this condition is gone (T-305).
    ///
    /// It used to read `mode == .todayOverview && !enableControls`, and the only `TasksPanel` that
    /// is a Today (`TodayView`) passes `enableControls: true`, so the rank never ran: macOS Today
    /// sorted purely by the Sort/Order chips. That was invisible while the page was *grouped* by
    /// the same four date states — the headings carried the urgency the sort had dropped. Grouping
    /// by list takes the headings away, and with them the only thing keeping a due-today task with
    /// no do date off the bottom of its list, where `.date` ascending files an empty
    /// `scheduledDate`.
    ///
    /// So the rank leads, exactly as iOS's `sortTodayTasks` has always had it, and the user's
    /// chosen mode orders the rows *inside* each rank. The `mode == .todayOverview` test that used
    /// to wrap the rank is gone with `.byDoDate` — All Tasks was the one shape that sorted purely
    /// by the chips, and it was unreachable (T-487).
    ///
    /// Since T-606 the second half is `CadenceTaskQuerySupport.sortTasks` — the same call iOS's
    /// Today makes — rather than `taskSortPrecedes` (deleted with its file by T-639, having lost
    /// its last caller here), so the two Todays now agree on the sort as
    /// well as on the rank. The rank stays spelled out here rather than calling the shared
    /// `sortTodayTasks`, because `macOSTodayLeadsItsSortWithTheSharedRank` pins this file's one
    /// `CadenceTaskQuerySupport.todayRank` call site and that pin is the guard against macOS
    /// growing a fourth copy of the rank.
    private func compareTasksForCurrentSort(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let leftRank = todayTaskSortRank(lhs)
        let rightRank = todayTaskSortRank(rhs)
        if leftRank != rightRank { return leftRank < rightRank }
        return CadenceTaskQuerySupport.sortTasks(lhs, rhs, sortMode: activeSortMode)
    }

    /// `CadenceTaskQuerySupport.todayRank`, not a local copy of it. The copy that used to live here
    /// tested `scheduledDate < todayKey` *before* `dueDate == todayKey`, which is the opposite of
    /// what every other Today rule does — see that function for what the disagreement cost.
    private func todayTaskSortRank(_ task: AppTask) -> Int {
        CadenceTaskQuerySupport.todayRank(task, todayKey: todayKey)
    }

    private func toggleGroup(_ id: String) {
        if collapsedGroupIDs.contains(id) {
            collapsedGroupIDs.remove(id)
        } else {
            collapsedGroupIDs.insert(id)
        }
    }

    private func taskDragPayload(for task: AppTask) -> String {
        TasksPanelSupport.taskDragPayload(for: task)
    }
}

#endif
