#if os(macOS)
import SwiftUI
import SwiftData

struct HabitsView: View {
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedHabitID: UUID? = nil
    @State private var showCreateHabit = false

    private var selectedHabit: Habit? {
        habits.first { $0.id == selectedHabitID }
    }

    private var todayKey: String { DateFormatters.todayKey() }

    var body: some View {
        HSplitView {
            // Left: habit list
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Habits")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button {
                        showCreateHabit = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider().background(Theme.borderSubtle)

                if habits.isEmpty {
                    Spacer()
                    EmptyStateView(
                        message: "No habits yet",
                        subtitle: "Tap + to create one",
                        icon: "flame.fill"
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(habits) { habit in
                                HabitListRow(
                                    habit: habit,
                                    todayKey: todayKey,
                                    isSelected: selectedHabitID == habit.id,
                                    onSelect: { selectedHabitID = habit.id },
                                    onToggle: { toggleHabit(habit) }
                                )
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 280)
            .background(Theme.surface)

            // Right: detail / heatmap
            if let habit = selectedHabit {
                HabitDetailView(habit: habit)
            } else {
                ZStack {
                    Theme.bg
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.dim)
                        Text("Select a habit")
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreateHabit) {
            CreateHabitSheet()
        }
        .onAppear {
            if selectedHabitID == nil { selectedHabitID = habits.first?.id }
        }
    }

    private func toggleHabit(_ habit: Habit) {
        let completions = habit.completions ?? []
        if let existing = completions.first(where: { $0.date == todayKey }) {
            modelContext.delete(existing)
        } else {
            let c = HabitCompletion(date: todayKey, habit: habit)
            modelContext.insert(c)
        }
    }
}

// MARK: - Habit List Row

private struct HabitListRow: View {
    let habit: Habit
    let todayKey: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void

    private var isDoneToday: Bool {
        (habit.completions ?? []).contains { $0.date == todayKey }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: habit.colorHex).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: habit.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: habit.colorHex))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.amber)
                    Text("\(habit.currentStreak) day streak")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            // Check-in button
            Button(action: onToggle) {
                Image(systemName: isDoneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isDoneToday ? Color(hex: habit.colorHex) : Theme.borderSubtle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.blue.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Habit Detail View

private struct HabitDetailView: View {
    let habit: Habit

    private var totalCompletions: Int {
        (habit.completions ?? []).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: habit.colorHex).opacity(0.15))
                            .frame(width: 48, height: 48)
                        Image(systemName: habit.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(Color(hex: habit.colorHex))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Text(frequencyDescription)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                }

                // Stats row
                HStack(spacing: 20) {
                    StatPill(value: "\(habit.currentStreak)", label: "Current Streak", icon: "flame.fill", color: Theme.amber)
                    StatPill(value: "\(totalCompletions)", label: "Total Check-ins", icon: "checkmark.circle.fill", color: Color(hex: habit.colorHex))
                    StatPill(value: bestStreakString, label: "Best Streak", icon: "trophy.fill", color: Theme.purple)
                }

                // Heatmap
                VStack(alignment: .leading, spacing: 8) {
                    Text("Activity")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .kerning(0.8)

                    HabitHeatmap(habit: habit)
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
    }

    private var frequencyDescription: String {
        switch habit.frequencyType {
        case "daily": return "Every day"
        case "daysOfWeek":
            let days = habit.frequencyDays
            let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            let selected = days.sorted().compactMap { i in names.indices.contains(i) ? names[i] : nil }
            return selected.isEmpty ? "Custom days" : selected.joined(separator: ", ")
        case "timesPerWeek":
            return "\(habit.targetCount)x per week"
        case "monthly":
            return "Monthly"
        default: return habit.frequencyType
        }
    }

    private var bestStreakString: String {
        let dates = Set((habit.completions ?? []).map { $0.date })
        let cal = Calendar.current
        var best = 0
        var current = 0
        let today = cal.startOfDay(for: Date())
        for i in stride(from: 365, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            if dates.contains(DateFormatters.dateKey(from: date)) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return "\(best)"
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Habit Heatmap

private struct HabitHeatmap: View {
    let habit: Habit

    private let cellSize: CGFloat = 12
    private let gap: CGFloat = 2
    private let weeks = 52

    private var completionDates: Set<String> {
        Set((habit.completions ?? []).map { $0.date })
    }

    private var cal: Calendar { Calendar.current }

    // Start date = 52 weeks ago, aligned to Sunday
    private var startDate: Date {
        let today = cal.startOfDay(for: Date())
        let daysBack = weeks * 7
        let rawStart = cal.date(byAdding: .day, value: -daysBack, to: today) ?? today
        // align to Sunday (weekday 1)
        let weekday = cal.component(.weekday, from: rawStart)
        let offset = weekday - 1
        return cal.date(byAdding: .day, value: -offset, to: rawStart) ?? rawStart
    }

    private var months: [(label: String, weekCol: Int)] {
        var result: [(String, Int)] = []
        var seenMonths = Set<Int>()
        for weekIdx in 0..<weeks {
            guard let weekStart = cal.date(byAdding: .day, value: weekIdx * 7, to: startDate) else { continue }
            let month = cal.component(.month, from: weekStart)
            if !seenMonths.contains(month) {
                seenMonths.insert(month)
                result.append((DateFormatters.monthAbbrev.string(from: weekStart), weekIdx))
            }
        }
        return result
    }

    var body: some View {
        let fmt = DateFormatters.ymd
        VStack(alignment: .leading, spacing: 4) {
            // Month labels
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 16)
                ForEach(months, id: \.weekCol) { m in
                    Text(m.label)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)
                        .offset(x: CGFloat(m.weekCol) * (cellSize + gap))
                }
            }

            // Grid
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { weekIdx in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { dayOfWeek in
                            let dayOffset = weekIdx * 7 + dayOfWeek
                            let date = cal.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
                            let key = fmt.string(from: date)
                            let isDone = completionDates.contains(key)
                            let isFuture = date > Date()

                            RoundedRectangle(cornerRadius: 2)
                                .fill(isFuture ? Color.clear : (isDone ? Color(hex: habit.colorHex) : Theme.borderSubtle))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CreateHabitSheet

struct CreateHabitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Habit.order) private var habits: [Habit]
    @Query(sort: \Context.order) private var allContexts: [Context]

    @State private var title = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "#4a9eff"
    @State private var frequencyType = "daily"
    @State private var selectedDays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var monthlyDay = 1
    @State private var selectedContextID: UUID? = nil

    private let freqTypes = ["daily", "daysOfWeek", "timesPerWeek", "monthly"]
    private let freqLabels = ["Daily", "Days of Week", "Times per Week", "Monthly"]
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
                    // Title
                    fieldLabel("Title")
                    TextField("e.g. Morning Run, Read 30 min", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    // Context
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

                    // Icon
                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    // Color
                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)

                    // Frequency type
                    fieldLabel("Frequency")
                    Picker("", selection: $frequencyType) {
                        ForEach(0..<freqTypes.count, id: \.self) { i in
                            Text(freqLabels[i]).tag(freqTypes[i])
                        }
                    }
                    .pickerStyle(.segmented)

                    // Frequency details
                    switch frequencyType {
                    case "daysOfWeek":
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                let dayVal = i + 1 // Mon=1..Sun=7
                                Button(dayNames[i]) {
                                    if selectedDays.contains(dayVal) {
                                        selectedDays.remove(dayVal)
                                    } else {
                                        selectedDays.insert(dayVal)
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(selectedDays.contains(dayVal) ? .white : Theme.dim)
                                .frame(width: 36, height: 28)
                                .background(selectedDays.contains(dayVal) ? Color(hex: selectedColor) : Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                    case "timesPerWeek":
                        HStack {
                            Text("Times per week:")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Stepper("\(timesPerWeek)", value: $timesPerWeek, in: 1...7)
                                .foregroundStyle(Theme.text)
                        }

                    case "monthly":
                        HStack {
                            Text("Day of month:")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                            Stepper("\(monthlyDay)", value: $monthlyDay, in: 1...31)
                                .foregroundStyle(Theme.text)
                        }

                    default:
                        EmptyView()
                    }
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                Button("Create") { create() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
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
        case "daysOfWeek":
            habit.frequencyDays = Array(selectedDays).sorted()
        case "timesPerWeek":
            habit.frequencyDays = [timesPerWeek]
        case "monthly":
            habit.frequencyDays = [monthlyDay]
        default:
            habit.frequencyDays = []
        }

        if let ctxID = selectedContextID,
           let ctx = try? modelContext.fetch(FetchDescriptor<Context>()).first(where: { $0.id == ctxID }) {
            habit.context = ctx
        }

        modelContext.insert(habit)
        dismiss()
    }
}
#endif
