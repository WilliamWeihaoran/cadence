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
        pursuits.filter { $0.status == .active }
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
            guard let pursuit = habit.pursuit else { return true }
            return pursuit.status != .active
        }

        if !unlinked.isEmpty {
            groups.append(
                HabitGoalGroup(
                    id: "unlinked",
                    title: "No Pursuit",
                    subtitle: "Attach to a pursuit when the habit supports a direction",
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
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]

    @State private var title = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "#4a9eff"
    @State private var frequencyType: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var monthlyDay = 1
    @State private var selectedContextID: UUID? = nil
    @State private var selectedPursuitID: UUID? = nil

    private var pursuitChoices: [Pursuit] {
        allPursuits.filter { $0.status == .active }
    }

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
                HabitFormFields(
                    title: $title,
                    selectedIcon: $selectedIcon,
                    selectedColor: $selectedColor,
                    frequencyType: $frequencyType,
                    selectedDays: $selectedDays,
                    timesPerWeek: $timesPerWeek,
                    monthlyDay: $monthlyDay,
                    selectedContextID: $selectedContextID,
                    selectedPursuitID: $selectedPursuitID,
                    contexts: allContexts,
                    pursuits: pursuitChoices
                )
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

        let selectedPursuit = selectedPursuitID.flatMap { id in
            allPursuits.first { $0.id == id }
        }

        if let selectedContextID,
           let context = allContexts.first(where: { $0.id == selectedContextID }) {
            habit.context = context
        } else if let selectedPursuit {
            habit.context = selectedPursuit.context
        }

        habit.pursuit = selectedPursuit

        modelContext.insert(habit)
        dismiss()
    }
}

// MARK: - EditHabitSheet

struct EditHabitSheet: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]

    @State private var title: String
    @State private var selectedIcon: String
    @State private var selectedColor: String
    @State private var frequencyType: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var monthlyDay: Int
    @State private var selectedContextID: UUID?
    @State private var selectedPursuitID: UUID?

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
        _selectedPursuitID = State(initialValue: habit.pursuit?.id)
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = habit.pursuit,
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
                HabitFormFields(
                    title: $title,
                    selectedIcon: $selectedIcon,
                    selectedColor: $selectedColor,
                    frequencyType: $frequencyType,
                    selectedDays: $selectedDays,
                    timesPerWeek: $timesPerWeek,
                    monthlyDay: $monthlyDay,
                    selectedContextID: $selectedContextID,
                    selectedPursuitID: $selectedPursuitID,
                    contexts: allContexts,
                    pursuits: pursuitChoices
                )
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

        let selectedPursuit = selectedPursuitID.flatMap { id in
            allPursuits.first { $0.id == id }
        }

        if let selectedContextID,
           let context = allContexts.first(where: { $0.id == selectedContextID }) {
            habit.context = context
        } else if let selectedPursuit {
            habit.context = selectedPursuit.context
        } else {
            habit.context = nil
        }

        habit.pursuit = selectedPursuit
        dismiss()
    }
}

private struct HabitFormFields: View {
    @Binding var title: String
    @Binding var selectedIcon: String
    @Binding var selectedColor: String
    @Binding var frequencyType: HabitFrequency
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerWeek: Int
    @Binding var monthlyDay: Int
    @Binding var selectedContextID: UUID?
    @Binding var selectedPursuitID: UUID?

    let contexts: [Context]
    let pursuits: [Pursuit]

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HabitFormLabel("Title")
            TextField("e.g. Morning Run, Read 30 min", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(10)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

            if !contexts.isEmpty {
                HabitFormLabel("Context")
                CadenceContextPickerButton(
                    contexts: contexts,
                    selectedID: $selectedContextID
                )
            }

            if !pursuits.isEmpty {
                HabitFormLabel("Pursuit")
                CadencePursuitPickerButton(
                    pursuits: pursuits,
                    selectedID: $selectedPursuitID
                )
            }

            HabitFormLabel("Icon")
            IconGrid(selected: $selectedIcon)

            HabitFormLabel("Color")
            ColorGrid(selected: $selectedColor)

            HabitFormLabel("Frequency")
            HabitFrequencyPicker(selection: $frequencyType, tintHex: selectedColor)

            frequencyDetails
        }
    }

    @ViewBuilder
    private var frequencyDetails: some View {
        switch frequencyType {
        case .daysOfWeek:
            HabitWeekdayPicker(
                selectedDays: $selectedDays,
                dayNames: dayNames,
                tintHex: selectedColor
            )
        case .timesPerWeek:
            HabitNumberStepper(
                title: "Weekly target",
                detail: "check-ins per week",
                value: $timesPerWeek,
                range: 1...7,
                tintHex: selectedColor
            )
        case .monthly:
            HabitNumberStepper(
                title: "Monthly day",
                detail: "day of month",
                value: $monthlyDay,
                range: 1...31,
                tintHex: selectedColor
            )
        case .daily:
            HabitFrequencyNote(
                icon: "sun.max.fill",
                title: "Every day",
                detail: "This habit is expected daily.",
                tintHex: selectedColor
            )
        }
    }
}

private struct HabitFormLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }
}

private struct HabitFrequencyPicker: View {
    @Binding var selection: HabitFrequency
    let tintHex: String

    private var options: [HabitFrequencyOption] {
        [
            HabitFrequencyOption(type: .daily, title: "Daily", detail: "Every day", icon: "sun.max.fill"),
            HabitFrequencyOption(type: .daysOfWeek, title: "Days", detail: "Specific weekdays", icon: "calendar"),
            HabitFrequencyOption(type: .timesPerWeek, title: "Weekly", detail: "Target count", icon: "number"),
            HabitFrequencyOption(type: .monthly, title: "Monthly", detail: "One day each month", icon: "calendar.badge.clock"),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(options) { option in
                frequencyButton(option)
            }
        }
    }

    private func frequencyButton(_ option: HabitFrequencyOption) -> some View {
        let isSelected = selection == option.type
        let tint = Color(hex: tintHex)

        return Button {
            selection = option.type
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.dim)
                    .frame(width: 28, height: 28)
                    .background((isSelected ? tint : Theme.dim).opacity(isSelected ? 0.14 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                    Text(option.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minHeight: 54)
            .background(isSelected ? tint.opacity(0.10) : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? tint.opacity(0.42) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.cadencePlain)
    }
}

private struct HabitFrequencyOption: Identifiable {
    let type: HabitFrequency
    let title: String
    let detail: String
    let icon: String

    var id: String { type.rawValue }
}

private struct HabitWeekdayPicker: View {
    @Binding var selectedDays: Set<Int>
    let dayNames: [String]
    let tintHex: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let dayValue = index + 1
                let isSelected = selectedDays.contains(dayValue)
                Button {
                    if isSelected {
                        selectedDays.remove(dayValue)
                    } else {
                        selectedDays.insert(dayValue)
                    }
                } label: {
                    Text(dayNames[index])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(isSelected ? Color(hex: tintHex) : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.clear : Theme.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.cadencePlain)
            }
        }
    }
}

private struct HabitNumberStepper: View {
    let title: String
    let detail: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let tintHex: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()

            stepButton(systemImage: "minus", isDisabled: value <= range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }

            Text("\(value)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.text)
                .frame(width: 42, height: 32)
                .background(Color(hex: tintHex).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: tintHex).opacity(0.24), lineWidth: 1)
                )

            stepButton(systemImage: "plus", isDisabled: value >= range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    private func stepButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? Theme.dim.opacity(0.45) : Color(hex: tintHex))
                .frame(width: 30, height: 30)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.cadencePlain)
        .disabled(isDisabled)
    }
}

private struct HabitFrequencyNote: View {
    let icon: String
    let title: String
    let detail: String
    let tintHex: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: tintHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: tintHex).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }

            Spacer()
        }
        .padding(12)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}
#endif
