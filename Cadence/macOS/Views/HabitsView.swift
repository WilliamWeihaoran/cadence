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

    private var activeGoals: [Goal] {
        goals.filter { $0.status == .active }
    }

    private var dueHabitsToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    private var openHabitsToday: [Habit] {
        dueHabitsToday.filter { !$0.isDone(on: todayKey) }
    }

    private var goalLinkedHabitCount: Int {
        habits.filter { $0.goal != nil }.count
    }

    private var goalCoverageLabel: String {
        guard !habits.isEmpty else { return "No habits yet" }
        return "\(goalLinkedHabitCount)/\(habits.count) linked"
    }

    private var nextOpenHabit: Habit? {
        openHabitsToday.sorted { lhs, rhs in
            if lhs.goal != nil && rhs.goal == nil { return true }
            if lhs.goal == nil && rhs.goal != nil { return false }
            if lhs.currentStreak != rhs.currentStreak { return lhs.currentStreak > rhs.currentStreak }
            return lhs.order < rhs.order
        }.first
    }

    private var habitGroups: [HabitGoalGroup] {
        var groups: [HabitGoalGroup] = activeGoals.compactMap { goal in
            let linked = visibleHabits.filter { $0.goal?.id == goal.id }
            guard !linked.isEmpty else { return nil }
            return HabitGoalGroup(
                id: goal.id.uuidString,
                title: goal.title,
                subtitle: GoalHabitMomentumResolver.summary(for: goal).dueTodayLabel,
                icon: "target",
                colorHex: goal.colorHex,
                habits: linked
            )
        }

        let unlinked = visibleHabits.filter { habit in
            guard let goal = habit.goal else { return true }
            return goal.status != .active
        }

        if !unlinked.isEmpty {
            groups.append(
                HabitGoalGroup(
                    id: "unlinked",
                    title: "Unlinked Habits",
                    subtitle: "Attach to goals when the habit supports an outcome",
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
                        Text("Daily systems tied to real outcomes.")
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
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                        TextField("Search habits, goals, frequency, context", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.borderSubtle, lineWidth: 1)
                    )
                }

                HStack(spacing: 8) {
                    ForEach(HabitListFilter.allCases, id: \.self) { item in
                        CadencePillButton(
                            title: item.label,
                            isSelected: filter == item,
                            minWidth: 58
                        ) {
                            filter = item
                        }
                    }
                }
                .padding(4)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.borderSubtle, lineWidth: 1)
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
                    subtitle: searchText.isEmpty ? "Create a habit to start building momentum." : "Try a different search or filter.",
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

// MARK: - CreateHabitSheet

struct CreateHabitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Goal.order) private var allGoals: [Goal]

    @State private var title = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "#4a9eff"
    @State private var frequencyType: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var monthlyDay = 1
    @State private var selectedContextID: UUID? = nil
    @State private var selectedGoalID: UUID? = nil
    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Habit")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Title")
                    TextField("e.g. Morning Run, Read 30 min", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    if !allContexts.isEmpty {
                        fieldLabel("Context")
                        Picker("", selection: $selectedContextID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(allContexts) { ctx in
                                Text(ctx.name).tag(Optional(ctx.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(Theme.text)
                    }

                    if !allGoals.isEmpty {
                        fieldLabel("Goal")
                        Picker("", selection: $selectedGoalID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(allGoals.filter { $0.status == .active }) { goal in
                                Text(goal.title).tag(Optional(goal.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(Theme.text)
                    }

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    fieldLabel("Frequency")
                    Picker("", selection: $frequencyType) {
                        ForEach(HabitFrequency.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch frequencyType {
                    case .daysOfWeek:
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                let dayVal = i + 1
                                Button(dayNames[i]) {
                                    if selectedDays.contains(dayVal) {
                                        selectedDays.remove(dayVal)
                                    } else {
                                        selectedDays.insert(dayVal)
                                    }
                                }
                                .buttonStyle(.cadencePlain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedDays.contains(dayVal) ? .white : Theme.dim)
                                .frame(width: 36, height: 28)
                                .background(selectedDays.contains(dayVal) ? Color(hex: selectedColor) : Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                    case .timesPerWeek:
                        HStack {
                            Text("Times per week:")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Stepper("\(timesPerWeek)", value: $timesPerWeek, in: 1...7)
                                .foregroundStyle(Theme.text)
                        }

                    case .monthly:
                        HStack {
                            Text("Day of month:")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Stepper("\(monthlyDay)", value: $monthlyDay, in: 1...31)
                                .foregroundStyle(Theme.text)
                        }

                    case .daily:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    dismiss()
                }
                CadenceActionButton(
                    title: "Create",
                    role: .primary,
                    size: .compact,
                    isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    create()
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 640)
        .background(Theme.surface)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let habit = Habit(title: trimmed)
        habit.icon = selectedIcon
        habit.colorHex = selectedColor
        habit.frequencyType = frequencyType
        habit.order = habits.count

        switch frequencyType {
        case .daily:
            habit.frequencyDays = []
            habit.targetCount = 1
        case .daysOfWeek:
            let resolvedDays = selectedDays.isEmpty ? [Habit.weekdayIndex(for: Date())] : selectedDays.sorted()
            habit.frequencyDays = resolvedDays
            habit.targetCount = resolvedDays.count
        case .timesPerWeek:
            habit.frequencyDays = [timesPerWeek]
            habit.targetCount = timesPerWeek
        case .monthly:
            habit.frequencyDays = [monthlyDay]
            habit.targetCount = 1
        }

        let selectedGoal = selectedGoalID.flatMap { id in
            allGoals.first { $0.id == id }
        }

        if let selectedContextID,
           let context = allContexts.first(where: { $0.id == selectedContextID }) {
            habit.context = context
        } else if let selectedGoal {
            habit.context = selectedGoal.context
        }

        habit.goal = selectedGoal

        modelContext.insert(habit)
        dismiss()
    }
}

// MARK: - EditHabitSheet

struct EditHabitSheet: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Goal.order) private var allGoals: [Goal]

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var frequencyType: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var monthlyDay: Int
    @State private var selectedContextID: UUID?
    @State private var selectedGoalID: UUID?

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(habit: Habit) {
        self.habit = habit
        let frequency = habit.frequencyType
        let storedDays = habit.frequencyDays

        _title = State(initialValue: habit.title)
        _selectedIcon = State(initialValue: habit.icon)
        _selectedColor = State(initialValue: habit.colorHex)
        _frequencyType = State(initialValue: frequency)
        _selectedDays = State(initialValue: frequency == .daysOfWeek ? Set(storedDays) : [])
        _timesPerWeek = State(initialValue: frequency == .timesPerWeek ? max(1, habit.targetCount) : 3)
        _monthlyDay = State(initialValue: frequency == .monthly ? min(max(storedDays.first ?? 1, 1), 31) : 1)
        _selectedContextID = State(initialValue: habit.context?.id)
        _selectedGoalID = State(initialValue: habit.goal?.id)
    }

    private var goalChoices: [Goal] {
        var choices = allGoals.filter { $0.status == .active }
        if let current = habit.goal,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Habit")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Title")
                    TextField("e.g. Morning Run, Read 30 min", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    if !allContexts.isEmpty {
                        fieldLabel("Context")
                        Picker("", selection: $selectedContextID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(allContexts) { ctx in
                                Text(ctx.name).tag(Optional(ctx.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(Theme.text)
                    }

                    if !goalChoices.isEmpty {
                        fieldLabel("Goal")
                        Picker("", selection: $selectedGoalID) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(goalChoices) { goal in
                                Text(goal.title).tag(Optional(goal.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(Theme.text)
                    }

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    fieldLabel("Frequency")
                    Picker("", selection: $frequencyType) {
                        ForEach(HabitFrequency.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch frequencyType {
                    case .daysOfWeek:
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                let dayVal = i + 1
                                Button(dayNames[i]) {
                                    if selectedDays.contains(dayVal) {
                                        selectedDays.remove(dayVal)
                                    } else {
                                        selectedDays.insert(dayVal)
                                    }
                                }
                                .buttonStyle(.cadencePlain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedDays.contains(dayVal) ? .white : Theme.dim)
                                .frame(width: 36, height: 28)
                                .background(selectedDays.contains(dayVal) ? Color(hex: selectedColor) : Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                    case .timesPerWeek:
                        HStack {
                            Text("Times per week:")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Stepper("\(timesPerWeek)", value: $timesPerWeek, in: 1...7)
                                .foregroundStyle(Theme.text)
                        }

                    case .monthly:
                        HStack {
                            Text("Day of month:")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Stepper("\(monthlyDay)", value: $monthlyDay, in: 1...31)
                                .foregroundStyle(Theme.text)
                        }

                    case .daily:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(
                    title: "Cancel",
                    role: .ghost,
                    size: .compact
                ) {
                    dismiss()
                }
                CadenceActionButton(
                    title: "Save",
                    role: .primary,
                    size: .compact,
                    tint: Color(hex: selectedColor),
                    isDisabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    save()
                }
            }
            .padding(16)
        }
        .frame(width: 460, height: 640)
        .background(Theme.surface)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        habit.title = trimmed
        habit.icon = selectedIcon
        habit.colorHex = selectedColor
        habit.frequencyType = frequencyType

        switch frequencyType {
        case .daily:
            habit.frequencyDays = []
            habit.targetCount = 1
        case .daysOfWeek:
            let resolvedDays = selectedDays.isEmpty ? [Habit.weekdayIndex(for: Date())] : selectedDays.sorted()
            habit.frequencyDays = resolvedDays
            habit.targetCount = resolvedDays.count
        case .timesPerWeek:
            habit.frequencyDays = [timesPerWeek]
            habit.targetCount = timesPerWeek
        case .monthly:
            habit.frequencyDays = [monthlyDay]
            habit.targetCount = 1
        }

        let selectedGoal = selectedGoalID.flatMap { id in
            allGoals.first { $0.id == id }
        }

        if let selectedContextID,
           let context = allContexts.first(where: { $0.id == selectedContextID }) {
            habit.context = context
        } else if let selectedGoal {
            habit.context = selectedGoal.context
        } else {
            habit.context = nil
        }

        habit.goal = selectedGoal
        dismiss()
    }
}
#endif
