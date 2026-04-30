#if os(macOS)
import SwiftUI
import SwiftData

struct GoalsView: View {
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @Environment(\.modelContext) private var modelContext
    @State private var selectedGoalID: UUID?
    @State private var showCreateGoal = false
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

    private var activeGoalsCount: Int { allGoals.filter { $0.status == .active }.count }
    private var linkedListsCount: Int { allGoals.reduce(0) { $0 + (($1.listLinks ?? []).count) } }
    private var contributingTasksCount: Int {
        allGoals.reduce(0) { $0 + GoalContributionResolver.summary(for: $1).totalTasks }
    }

    var body: some View {
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
                    onAttachWork: { showAttachWork = true },
                    onDetachList: detachList
                )
                .frame(minWidth: 360, idealWidth: 430)
            } else {
                GoalsEmptyDetail()
                    .frame(minWidth: 360, idealWidth: 430)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreateGoal) {
            CreateGoalSheet()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goals")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Outcomes powered by the lists and tasks already moving.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 20)
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
                GoalHeaderMetric(title: "Active", value: "\(activeGoalsCount)", icon: "target", color: Theme.green)
                GoalHeaderMetric(title: "Linked Lists", value: "\(linkedListsCount)", icon: "folder.badge.gearshape", color: Theme.blue)
                GoalHeaderMetric(title: "Contributors", value: "\(contributingTasksCount)", icon: "checklist", color: Theme.amber)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                    TextField("Search goals, outcomes, next actions", text: $searchText)
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
                            minWidth: 54
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
                    subtitle: searchText.isEmpty ? "Create a goal, then attach the lists or tasks that move it forward." : "Try a different search or status.",
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
}

#endif
