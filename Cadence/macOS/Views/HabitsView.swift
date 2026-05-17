#if os(macOS)
import SwiftUI
import SwiftData

struct HabitsView: View {
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
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
                    || (habit.pursuit?.title.lowercased().contains(query) ?? false)
                    || (habit.goal?.title.lowercased().contains(query) ?? false)
            }

            return matchesSearch && filter.matches(habit)
        }
    }

    private var activePursuits: [Pursuit] {
        pursuits
    }

    private var dueHabitsToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    private var openHabitsToday: [Habit] {
        dueHabitsToday.filter { !$0.isDone(on: todayKey) }
    }

    private var pursuitLinkedHabitCount: Int {
        habits.filter { $0.pursuit != nil }.count
    }

    private var pursuitCoverageLabel: String {
        guard !habits.isEmpty else { return "No habits yet" }
        return "\(pursuitLinkedHabitCount)/\(habits.count) in pursuits"
    }

    private var nextOpenHabit: Habit? {
        openHabitsToday.sorted { lhs, rhs in
            if lhs.pursuit != nil && rhs.pursuit == nil { return true }
            if lhs.pursuit == nil && rhs.pursuit != nil { return false }
            if lhs.currentStreak != rhs.currentStreak { return lhs.currentStreak > rhs.currentStreak }
            return lhs.order < rhs.order
        }.first
    }

    private var habitGroups: [HabitGoalGroup] {
        var groups: [HabitGoalGroup] = activePursuits.compactMap { pursuit in
            let linked = visibleHabits.filter { $0.pursuit?.id == pursuit.id }
            guard !linked.isEmpty else { return nil }
            return HabitGoalGroup(
                id: pursuit.id.uuidString,
                title: pursuit.title,
                subtitle: pursuit.context?.name ?? "Pursuit",
                icon: pursuit.icon,
                colorHex: pursuit.colorHex,
                habits: linked
            )
        }

        let unlinked = visibleHabits.filter { habit in
            habit.pursuit == nil
        }

        if !unlinked.isEmpty {
            groups.append(
                HabitGoalGroup(
                    id: "unlinked",
                    title: "Unassigned",
                    subtitle: "Assign these habits to a pursuit",
                    icon: "circle.dashed",
                    colorHex: "#6b7a99",
                    habits: unlinked
                )
            )
        }

        return groups
    }

    private var doneTodayCount: Int {
        habits.filter { $0.isDone(on: todayKey) }.count
    }

    private var dueTodayCount: Int {
        habits.filter(\.isDueToday).count
    }

    private var activeStreakCount: Int {
        habits.filter { $0.currentStreak > 0 }.count
    }

    private var averageLast30Completion: Int {
        guard !habits.isEmpty else { return 0 }
        let avg = habits.reduce(0.0) { $0 + Double($1.last30DayCompletionRate) }
            / Double(habits.count)
        return Int(avg.rounded())
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Habits")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text("Rhythms across pursuits.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 16)

                    CadenceActionButton(
                        title: "New Habit",
                        systemImage: "plus",
                        role: .primary,
                        size: .compact
                    ) {
                        showCreateHabit = true
                    }
                }

                HStack(spacing: 10) {
                    CommitmentSearchField(
                        placeholder: "Search habits, pursuits, frequency, context",
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(Theme.surface)

            Divider().background(Theme.borderSubtle)

            if habitGroups.isEmpty {
                Spacer()
                EmptyStateView(
                    message: searchText.isEmpty ? "No habits yet" : "No matching habits",
                    subtitle: searchText.isEmpty ? "Create a Pursuit first, then add a habit inside it." : "Try a different search or filter.",
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
        let existing = (habit.completions ?? []).filter { $0.date == todayKey }
        if !existing.isEmpty {
            for completion in existing {
                modelContext.delete(completion)
            }
        } else {
            let c = HabitCompletion(date: todayKey, habit: habit)
            modelContext.insert(c)
        }
    }
}

#endif
