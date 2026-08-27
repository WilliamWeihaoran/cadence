#if os(macOS)
import SwiftUI
import SwiftData

struct HabitsView: View {
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Query(sort: \Goal.order) private var goals: [Goal]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedHabitID: UUID? = nil
    @State private var showCreateHabit = false
    @State private var editingHabit: Habit? = nil
    @State private var searchText = ""
    @State private var filter: HabitListFilter = .today

    private var todayKey: String { DateFormatters.todayKey() }

    private var selectedHabit: Habit? {
        visibleHabits.first { $0.id == selectedHabitID } ?? habits.first { $0.id == selectedHabitID }
    }

    private var visibleHabits: [Habit] {
        habits.filter { habit in
            let matchesSearch: Bool
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                matchesSearch = habit.title.lowercased().contains(query)
                    || habit.frequencySummary.lowercased().contains(query)
                    || (habit.context?.name.lowercased().contains(query) ?? false)
                    || (habit.goal?.title.lowercased().contains(query) ?? false)
            }

            return matchesSearch && filter.matches(habit)
        }
    }

    /// Habits group under the goal they support; anything unlinked falls into a review bucket.
    private var habitGroups: [HabitGoalGroup] {
        var groups: [HabitGoalGroup] = goals.compactMap { goal in
            let linked = visibleHabits.filter { $0.goal?.id == goal.id }
            guard !linked.isEmpty else { return nil }
            return HabitGoalGroup(
                id: goal.id.uuidString,
                title: goal.title,
                subtitle: goal.context?.name ?? goal.kind.label,
                icon: goal.icon,
                colorHex: goal.colorHex,
                habits: linked
            )
        }

        let unlinked = GoalAssignmentRules.unlinkedHabits(from: visibleHabits)

        if !unlinked.isEmpty {
            // The app's one neutral grey — what an Inbox task's container chip, a list-less goal
            // link and this group all fall back to when there is no owner to take a colour from.
            // Its single spelling is `TaskSectionDefaults.defaultColorHex`, which sits in `Models/`
            // rather than in `Theme` because `CadenceMCPServer` compiles `Models/` and not
            // `Theme.swift`. Reading it here is deliberately not a claim that this group is a
            // kanban section; a second token in `Theme` holding the same hex would be the drift
            // T-166 deleted, one palette over (T-262).
            groups.append(
                HabitGoalGroup(
                    id: "unlinked",
                    title: "Unassigned",
                    subtitle: "Link these habits to a goal",
                    icon: "circle.dashed",
                    colorHex: TaskSectionDefaults.defaultColorHex,
                    habits: unlinked
                )
            )
        }

        return groups
    }

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: 300, idealWidth: 340)
                .background(Theme.surface)

            if let habit = selectedHabit {
                HabitDetailView(
                    habit: habit,
                    todayKey: todayKey,
                    onToggle: { toggleHabit(habit) },
                    onEdit: { editingHabit = habit }
                )
            } else {
                HabitsEmptyDetail()
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreateHabit) {
            CreateHabitSheet()
        }
        .sheet(item: $editingHabit) { habit in
            EditHabitSheet(habit: habit)
        }
        .onAppear {
            if selectedHabitID == nil { selectedHabitID = habits.first?.id }
        }
        .onChange(of: visibleHabits.map(\.id)) {
            if let selectedHabitID, visibleHabits.contains(where: { $0.id == selectedHabitID }) {
                return
            }
            self.selectedHabitID = visibleHabits.first?.id ?? habits.first?.id
        }
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            CommitmentPageHeader(
                title: "Habits"
            ) {
                CadenceActionButton(
                    title: "New Habit",
                    systemImage: "plus",
                    role: .primary,
                    size: .compact
                ) {
                    showCreateHabit = true
                }
            } controls: {
                HStack(spacing: 10) {
                    CommitmentSearchField(
                        placeholder: "Search habits, goals, frequency, context",
                        text: $searchText
                    )
                }

                CommitmentFilterBar(
                    items: HabitListFilter.allCases,
                    selection: $filter,
                    minWidth: 58,
                    label: \.label
                )
            }

            Divider().background(Theme.borderSubtle)

            if habitGroups.isEmpty {
                Spacer()
                EmptyStateView(
                    message: searchText.isEmpty ? "No habits yet" : "No matching habits",
                    subtitle: searchText.isEmpty ? "Create a habit, then link it to the goal it supports." : "Try a different search or filter.",
                    icon: "flame.fill"
                )
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(habitGroups) { group in
                            HabitGoalSectionView(
                                group: group,
                                todayKey: todayKey,
                                selectedHabitID: selectedHabitID,
                                onSelect: { selectedHabitID = $0.id },
                                onToggle: { toggleHabit($0) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func toggleHabit(_ habit: Habit) {
        // One writer for a habit check-in, on every surface: see `CadenceHabitCompletionStore`
        // and T-359. The swallow is deliberate — the row is already gone or present in the
        // context the list renders from, and a second tap is the retry.
        _ = try? CadenceHabitCompletionStore.toggle(habit, on: todayKey, modelContext: modelContext)
    }
}

#endif
