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
            .onAppear {
                if selectedGoalID == nil {
                    selectedGoalID = visibleGoals.first?.id ?? allGoals.first?.id
                }
            }
            .onChange(of: Self.visibleGoals(in: groups).map(\.id)) {
                guard let selectedGoalID,
                      visibleGoals.contains(where: { $0.id == selectedGoalID }) || trimmedQuery.isEmpty
                else {
                    self.selectedGoalID = visibleGoals.first?.id ?? allGoals.first?.id
                    return
                }
            }
    }

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
                onEditGoal: { goal in
                    selectedGoalID = goal.id
                    showEditGoal = true
                }
            )
        } else {
            missionContent(groups: groups)
        }
    }

    private func missionContent(groups: [GoalMissionGroup]) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider().background(Theme.borderSubtle)
                goalList(groups: groups)
            }
            .frame(minWidth: 560, idealWidth: 760)
            .background(Theme.bg)

            if let goal = selectedGoal {
                GoalInspectorView(
                    goal: goal,
                    onEdit: { showEditGoal = true },
                    onAttachWork: { showAttachWork = true },
                    onDetachList: detachList
                )
                .frame(minWidth: 340, idealWidth: 400)
            } else {
                GoalsEmptyDetail()
                    .frame(minWidth: 340, idealWidth: 400)
            }
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

    private func goalList(groups: [GoalMissionGroup]) -> some View {
        Group {
            if groups.isEmpty {
                EmptyStateView(
                    message: searchText.isEmpty ? "No goals yet" : "No matching goals",
                    subtitle: searchText.isEmpty ? "Create a goal for an ongoing direction, then nest milestones inside it." : "Try a different search or status.",
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
                                onSelect: { selectedGoalID = $0.id }
                            )
                        }
                    }
                    .padding(20)
                }
            }
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
