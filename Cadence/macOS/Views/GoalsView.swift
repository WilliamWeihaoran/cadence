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

    private var filteredGoals: [Goal] {
        allGoals.filter(matchesFilters)
    }

    /// Top-level goals become groups; everything nested beneath one is shown as its milestones.
    /// Descendants are flattened depth-first so a deeper chain can never hide a goal entirely.
    private var goalGroups: [GoalMissionGroup] {
        GoalAssignmentRules
            .topLevelGoals(from: allGoals)
            .compactMap { parent in
                let milestones = nestedGoals(under: parent).filter(matchesFilters)
                guard matchesFilters(parent) || !milestones.isEmpty else { return nil }
                return GoalMissionGroup(
                    id: parent.id.uuidString,
                    title: parent.title,
                    icon: parent.icon,
                    colorHex: parent.colorHex,
                    parentGoal: parent,
                    goals: milestones
                )
            }
    }

    private func nestedGoals(under goal: Goal) -> [Goal] {
        var visited: Set<UUID> = [goal.id]
        var result: [Goal] = []

        func walk(_ parent: Goal) {
            for child in GoalAssignmentRules.milestones(of: parent) where !visited.contains(child.id) {
                visited.insert(child.id)
                result.append(child)
                walk(child)
            }
        }

        walk(goal)
        return result
    }

    private var visibleGoals: [Goal] {
        goalGroups.flatMap { group in
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
        content
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
            .onChange(of: visibleGoals.map(\.id)) {
                guard let selectedGoalID,
                      visibleGoals.contains(where: { $0.id == selectedGoalID }) || trimmedQuery.isEmpty
                else {
                    self.selectedGoalID = visibleGoals.first?.id ?? allGoals.first?.id
                    return
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if goalsViewMode == .timeline {
            GoalTimelineView(
                groups: goalGroups,
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
            missionContent
        }
    }

    private var missionContent: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider().background(Theme.borderSubtle)
                goalList
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

    private var goalList: some View {
        Group {
            if goalGroups.isEmpty {
                EmptyStateView(
                    message: searchText.isEmpty ? "No goals yet" : "No matching goals",
                    subtitle: searchText.isEmpty ? "Create a goal for an ongoing direction, then nest milestones inside it." : "Try a different search or status.",
                    icon: "flag.fill"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(goalGroups) { group in
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

    private func detachList(_ link: GoalListLink) {
        modelContext.delete(link)
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
