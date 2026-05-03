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

    private var filteredGoals: [Goal] {
        allGoals.filter { goal in
            guard statusFilter.matches(goal.status) else { return false }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            let summary = GoalContributionResolver.summary(for: goal)
            return goal.title.lowercased().contains(q)
                || goal.desc.lowercased().contains(q)
                || goal.rangeLabel.lowercased().contains(q)
                || (goal.context?.name.lowercased().contains(q) ?? false)
                || (goal.pursuit?.title.lowercased().contains(q) ?? false)
                || ((summary.nextActionTitle ?? "").lowercased().contains(q))
        }
    }

    private var goalGroups: [GoalMissionGroup] {
        var groups: [GoalMissionGroup] = []
        for context in allContexts {
            let goals = filteredGoals.filter { $0.context?.id == context.id }
            if !goals.isEmpty {
                groups.append(
                    GoalMissionGroup(
                        id: context.id.uuidString,
                        title: context.name,
                        icon: context.icon,
                        colorHex: context.colorHex,
                        goals: goals
                    )
                )
            }
        }
        let unfiled = filteredGoals.filter { $0.context == nil }
        if !unfiled.isEmpty {
            groups.append(
                GoalMissionGroup(
                    id: "none",
                    title: "No Context",
                    icon: "circle.dashed",
                    colorHex: "#6b7a99",
                    goals: unfiled
                )
            )
        }
        return groups
    }

    private var selectedGoal: Goal? {
        if let selectedGoalID {
            return allGoals.first { $0.id == selectedGoalID }
        }
        return filteredGoals.first ?? allGoals.first
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
                    selectedGoalID = filteredGoals.first?.id ?? allGoals.first?.id
                }
            }
            .onChange(of: filteredGoals.map(\.id)) {
                guard let selectedGoalID,
                      filteredGoals.contains(where: { $0.id == selectedGoalID }) || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    self.selectedGoalID = filteredGoals.first?.id ?? allGoals.first?.id
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goals")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Outcomes powered by lists.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 20)
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

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    TextField("Search goals", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))

                HStack(spacing: 6) {
                    ForEach(GoalStatusFilter.allCases, id: \.self) { filter in
                        CadencePillButton(
                            title: filter.label,
                            isSelected: statusFilter == filter,
                            minWidth: 48
                        ) {
                            statusFilter = filter
                        }
                    }
                }
                .padding(4)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle, lineWidth: 1))
            }
        }
        .padding(20)
        .background(Theme.surface)
    }

    private var goalList: some View {
        Group {
            if goalGroups.isEmpty {
                EmptyStateView(
                    message: searchText.isEmpty ? "No goals yet" : "No matching goals",
                    subtitle: searchText.isEmpty ? "Create a goal, then attach the lists that move it forward." : "Try a different search or status.",
                    icon: "target"
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
