#if os(macOS)
import SwiftUI
import SwiftData

struct GoalsView: View {
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @Environment(\.modelContext) private var modelContext
    @AppStorage("goalsViewMode") private var goalsViewModeRaw = GoalsViewMode.mission.rawValue
    @AppStorage("goalsTimelineScale") private var timelineScaleRaw = TimeScale.quarter.rawValue
    @State private var selectedGoalID: UUID?
    @State private var showCreateGoal = false
    @State private var showEditGoal = false
    @State private var showAttachWork = false
    /// The narrow-width route to the inspector. See `GoalInspectorSheet`.
    @State private var showGoalDetail = false
    @State private var searchText = ""
    @State private var statusFilter: GoalStatusFilter = .active

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesFilters(_ goal: Goal) -> Bool {
        guard statusFilter.matches(goal.status) else { return false }
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        let summary = GoalContributionResolver.summary(for: goal)
        return goal.title.lowercased().contains(q)
            || goal.desc.lowercased().contains(q)
            || goal.rangeLabel.lowercased().contains(q)
            || goal.kind.label.lowercased().contains(q)
            || (goal.context?.name.lowercased().contains(q) ?? false)
            || (goal.parentGoal?.title.lowercased().contains(q) ?? false)
            || ((summary.nextActionTitle ?? "").lowercased().contains(q))
    }

    private var goalGroups: [GoalMissionGroup] {
        GoalMissionGrouping.groups(from: allGoals, matches: matchesFilters)
    }

    private var visibleGoals: [Goal] {
        Self.visibleGoals(in: goalGroups)
    }

    private static func visibleGoals(in groups: [GoalMissionGroup]) -> [Goal] {
        groups.flatMap { group in
            (group.parentGoal.map { [$0] } ?? []) + group.goals
        }
    }

    /// T-346. **Which goal to hold, once "deleted" and "filtered out" stop being one question.**
    ///
    /// This used to read
    /// `visibleGoals.contains(where: { $0.id == selectedGoalID }) || trimmedQuery.isEmpty`, and that
    /// `||` is the whole bug. It answers "does this goal still exist?" and "is it hidden by the
    /// search I typed?" with a single condition, and the condition's escape hatch — an empty search
    /// box — is the state the page is in almost all the time. So the guard retargeted correctly
    /// while you were searching and left a *deleted* goal selected the moment you cleared the box,
    /// which is the one case it was there for.
    ///
    /// Split, per `CadenceSelectionNormalization`: missing from `allGoalIDs` always retargets,
    /// whatever the search box says; hidden-by-search keeps the previous product behaviour and only
    /// retargets while a search is actually active.
    ///
    /// Static and non-private so the rule can be measured against a real store rather than argued
    /// about — the view itself cannot be instantiated in a test.
    static func normalizedSelection(
        selectedGoalID: UUID?,
        allGoalIDs: [UUID],
        visibleGoalIDs: [UUID],
        searchIsActive: Bool
    ) -> UUID? {
        let fallback = visibleGoalIDs.first ?? allGoalIDs.first
        guard selectedGoalID != nil else { return fallback }
        return CadenceSelectionNormalization.normalized(
            selectedGoalID,
            existingIDs: Set(allGoalIDs),
            visibleIDs: Set(visibleGoalIDs),
            filterIsActive: searchIsActive,
            fallback: fallback
        )
    }

    private func normalizeSelection(visible: [Goal]) {
        selectedGoalID = Self.normalizedSelection(
            selectedGoalID: selectedGoalID,
            allGoalIDs: allGoals.map(\.id),
            visibleGoalIDs: visible.map(\.id),
            searchIsActive: !trimmedQuery.isEmpty
        )
    }

    private var selectedGoal: Goal? {
        if let selectedGoalID {
            return allGoals.first { $0.id == selectedGoalID }
        }
        return visibleGoals.first ?? allGoals.first
    }

    var body: some View {
        // `goalGroups` re-runs `matchesFilters` over every goal — and with a non-empty search
        // box that means a full `GoalContributionResolver.summary` walk per goal. Build the
        // grouping once per pass and hand it to the body-time readers.
        let groups = goalGroups

        return content(groups: groups)
            .background(Theme.bg)
            .sheet(isPresented: $showCreateGoal) {
                CreateGoalSheet()
            }
            .sheet(isPresented: $showEditGoal) {
                if let goal = selectedGoal {
                    CreateGoalSheet(goal: goal)
                }
            }
            .sheet(isPresented: $showAttachWork) {
                if let goal = selectedGoal {
                    AttachWorkSheet(
                        goal: goal,
                        contexts: allContexts,
                        areas: areas,
                        projects: projects
                    )
                }
            }
            .sheet(isPresented: $showGoalDetail) {
                if let goal = selectedGoal {
                    GoalInspectorSheet(
                        goal: goal,
                        contexts: allContexts,
                        areas: areas,
                        projects: projects,
                        onDetachList: detachList
                    )
                }
            }
            .onAppear {
                if selectedGoalID == nil {
                    selectedGoalID = visibleGoals.first?.id ?? allGoals.first?.id
                }
            }
            // Two triggers, because the two questions below have two different causes. A search
            // narrowing changes the visible set; a *delete* changes `allGoals` and need not change
            // the visible set at all — a goal filtered out by `statusFilter` and then deleted moves
            // neither list, and the selection would sit on it forever.
            .onChange(of: Self.visibleGoals(in: groups).map(\.id)) {
                normalizeSelection(visible: visibleGoals)
            }
            .onChange(of: allGoals.map(\.id)) {
                normalizeSelection(visible: visibleGoals)
            }
    }

    /// **Timeline mode hands `select` a literal `false` because the roadmap has no inspector
    /// column at any width.** It is a fixed left rail plus a horizontally scrolling Gantt; there is
    /// nothing for a wide window to put a column beside, so the sheet T-271 gave narrow mission
    /// mode is not a fallback here but the only route. Spending the same `select` rather than
    /// setting `showGoalDetail` a second time keeps one place that decides what opening a goal
    /// means — the mission branch's own rule, that two answers cannot disagree if there is one.
    ///
    /// This replaced `onEditGoal`, which is the whole of T-272: the roadmap offered **Edit** from
    /// both its rows and every bar and **Attach List** from nowhere, at every width, since before
    /// T-250 — the timeline never had an inspector to lose. Edit is a button inside
    /// `GoalInspectorView`, so opening the inspector is a superset of what the double-click did,
    /// not a trade; Attach List and `GoalLinkedListRow`'s per-list detach come with it.
    @ViewBuilder
    private func content(groups: [GoalMissionGroup]) -> some View {
        if goalsViewMode == .timeline {
            GoalTimelineView(
                groups: groups,
                selectedGoalID: $selectedGoalID,
                viewMode: goalsViewModeBinding,
                scale: timelineScaleBinding,
                searchText: $searchText,
                statusFilter: $statusFilter,
                onCreateGoal: { showCreateGoal = true },
                onOpenGoal: { select($0, showsInspector: false) }
            )
        } else {
            missionContent(groups: groups)
        }
    }

    /// The mission column is not the side that yields: the page header, the search field, the
    /// status filter and the only New Goal button are all inside it, and `goalListPaneMinWidth` is
    /// their floor. Below `goalsSplitMinimumWidth` the inspector goes instead — it is nine points
    /// wide at the app's minimum window with the sidebar out, which is not a narrow inspector but
    /// an invisible one. See `CadenceDesktopSplitLayout`.
    ///
    /// `showsInspector` is also what a card's tap *means*, which is the T-271 half: with a column
    /// beside it a card selects and the column re-subjects itself, and without one the card opens
    /// `GoalInspectorSheet`. One gate, read once, answering both — a second `goalsShowsInspector`
    /// call for the sheet would be a second place for the two answers to disagree.
    private func missionContent(groups: [GoalMissionGroup]) -> some View {
        GeometryReader { proxy in
            let showsInspector = CadenceDesktopSplitLayout.goalsShowsInspector(
                paneWidth: proxy.size.width
            )

            HSplitView {
                VStack(spacing: 0) {
                    header
                    Divider().background(Theme.borderSubtle)
                    goalList(groups: groups, showsInspector: showsInspector)
                }
                .frame(minWidth: CadenceDesktopSplitLayout.goalListPaneMinWidth, idealWidth: 760)
                .background(Theme.bg)

                if showsInspector {
                    if let goal = selectedGoal {
                        GoalInspectorView(
                            goal: goal,
                            onEdit: { showEditGoal = true },
                            onAttachWork: { showAttachWork = true },
                            onDetachList: detachList
                        )
                        .frame(
                            minWidth: CadenceDesktopSplitLayout.goalInspectorPaneMinWidth,
                            idealWidth: 400
                        )
                    } else {
                        GoalsEmptyDetail()
                            .frame(
                                minWidth: CadenceDesktopSplitLayout.goalInspectorPaneMinWidth,
                                idealWidth: 400
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        CommitmentPageHeader(
            title: "Goals"
        ) {
            HStack(spacing: 10) {
                GoalsViewModeToggle(selection: goalsViewModeBinding)
                CadenceActionButton(
                    title: "New Goal",
                    systemImage: "plus",
                    role: .primary,
                    size: .regular
                ) {
                    showCreateGoal = true
                }
            }
        } controls: {
            HStack(spacing: 12) {
                CommitmentSearchField(
                    placeholder: "Search goals",
                    text: $searchText
                )

                CommitmentFilterBar(
                    items: GoalStatusFilter.allCases,
                    selection: $statusFilter,
                    minWidth: 48,
                    label: \.label
                )
            }
        }
    }

    /// Whether the page is empty because the search field or the status bar is narrowing it.
    private var isNarrowedToEmpty: Bool {
        CadenceEmptyStateCopy.isNarrowedToEmpty(
            searchText: searchText,
            filterNarrows: statusFilter.narrowsResults
        )
    }

    private func goalList(groups: [GoalMissionGroup], showsInspector: Bool) -> some View {
        Group {
            if groups.isEmpty {
                EmptyStateView(
                    // Not `searchText.isEmpty`: `statusFilter` defaults to `.active` and hides
                    // paused and finished goals, so an empty page under it is a filter miss and
                    // not a first run. See `CadenceEmptyStateCopy.isNarrowedToEmpty`.
                    message: isNarrowedToEmpty ? "No matching goals" : "No goals yet",
                    subtitle: isNarrowedToEmpty
                        ? "Try a different search or status."
                        : "Create a goal for an ongoing direction, then nest milestones inside it.",
                    icon: "flag.fill"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups) { group in
                            GoalMissionGroupView(
                                group: group,
                                selectedGoalID: selectedGoalID,
                                onSelect: { select($0, showsInspector: showsInspector) }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    /// Selecting a goal, at both widths. The selection is written either way — it is what the
    /// inspector is *about*, so re-widening the window has to find the same goal under the column —
    /// and only the second half is width-dependent: with no column to re-subject, the card has to
    /// open the inspector itself or the tap does nothing a user can see.
    ///
    /// Both cards go through here. `GoalDirectionHeaderCard` is selectable and editable exactly as
    /// `GoalMissionCard` is, so a route hung on one of the two would leave every top-level direction
    /// without one — which is what a `contextMenu` per card would have cost, in two copies.
    private func select(_ goal: Goal, showsInspector: Bool) {
        selectedGoalID = goal.id
        if !showsInspector {
            showGoalDetail = true
        }
    }

    /// `ModelContext.detachGoalListLink` rather than a bare `delete`: the shared helper severs the
    /// link's own references first and saves, and it is the same call iOS's goal detail makes.
    private func detachList(_ link: GoalListLink) {
        modelContext.detachGoalListLink(link)
    }

    private var goalsViewMode: GoalsViewMode {
        get { GoalsViewMode(rawValue: goalsViewModeRaw) ?? .mission }
        nonmutating set { goalsViewModeRaw = newValue.rawValue }
    }

    private var timelineScale: TimeScale {
        get {
            let restored = TimeScale(rawValue: timelineScaleRaw) ?? .quarter
            return GoalTimelineDateMath.roadmapScales.contains(restored) ? restored : .quarter
        }
        nonmutating set { timelineScaleRaw = newValue.rawValue }
    }

    private var goalsViewModeBinding: Binding<GoalsViewMode> {
        Binding(
            get: { goalsViewMode },
            set: { goalsViewMode = $0 }
        )
    }

    private var timelineScaleBinding: Binding<TimeScale> {
        Binding(
            get: { timelineScale },
            set: { timelineScale = $0 }
        )
    }
}

#endif
