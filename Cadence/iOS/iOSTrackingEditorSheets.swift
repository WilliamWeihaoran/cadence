#if os(iOS)
import SwiftData
import SwiftUI

enum iOSPursuitEditorMode: Identifiable {
    case new
    case edit(Pursuit)

    var id: String {
        switch self {
        case .new: return "new-pursuit"
        case .edit(let pursuit): return "edit-pursuit-\(pursuit.id.uuidString)"
        }
    }
}

enum iOSGoalEditorMode: Identifiable {
    case new(Pursuit?)
    case edit(Goal)

    var id: String {
        switch self {
        case .new(let pursuit): return "new-goal-\(pursuit?.id.uuidString ?? "none")"
        case .edit(let goal): return "edit-goal-\(goal.id.uuidString)"
        }
    }
}

enum iOSHabitEditorMode: Identifiable {
    case new(Pursuit?)
    case edit(Habit)

    var id: String {
        switch self {
        case .new(let pursuit): return "new-habit-\(pursuit?.id.uuidString ?? "none")"
        case .edit(let habit): return "edit-habit-\(habit.id.uuidString)"
        }
    }
}

struct iOSPursuitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSPursuitEditorMode
    let onSave: (Pursuit) -> Void

    @State private var title: String
    @State private var desc: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var kind: PursuitKind
    @State private var status: PursuitStatus
    @State private var contextID: UUID?

    init(mode: iOSPursuitEditorMode, onSave: @escaping (Pursuit) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave

        if case .edit(let pursuit) = mode {
            _title = State(initialValue: pursuit.title)
            _desc = State(initialValue: pursuit.desc)
            _icon = State(initialValue: pursuit.icon)
            _colorHex = State(initialValue: pursuit.colorHex)
            _kind = State(initialValue: pursuit.kind)
            _status = State(initialValue: pursuit.status)
            _contextID = State(initialValue: pursuit.context?.id)
        } else {
            _title = State(initialValue: "")
            _desc = State(initialValue: "")
            _icon = State(initialValue: "sparkles")
            _colorHex = State(initialValue: "#a78bfa")
            _kind = State(initialValue: .ongoing)
            _status = State(initialValue: .active)
            _contextID = State(initialValue: nil)
        }
    }

    private var editingPursuit: Pursuit? {
        if case .edit(let pursuit) = mode { return pursuit }
        return nil
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingPursuit == nil ? "New Pursuit" : "Edit Pursuit",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Become more knowledgeable", text: $title)
            iOSTrackingTextField(title: "Direction", placeholder: "What are you trying to cultivate?", text: $desc, axis: .vertical)

            iOSTrackingPickerSection(title: "Context") {
                Picker("Context", selection: $contextID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(contexts) { context in
                        Label(context.name, systemImage: context.icon).tag(Optional(context.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Kind") {
                Picker("Kind", selection: $kind) {
                    ForEach(PursuitKind.allCases, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            iOSTrackingPickerSection(title: "Status") {
                Picker("Status", selection: $status) {
                    ForEach(PursuitStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }

            iOSTrackingPickerSection(title: "Icon") {
                iOSTrackingIconGrid(selection: $icon)
            }

            iOSTrackingPickerSection(title: "Color") {
                iOSTrackingColorGrid(selection: $colorHex)
            }
        }
    }

    private func save() {
        guard let pursuit = CadenceTrackingMutationSupport.savePursuit(
            editingPursuit,
            title: title,
            desc: desc,
            icon: icon,
            colorHex: colorHex,
            kind: kind,
            status: status,
            context: selectedContext,
            allPursuits: allPursuits,
            modelContext: modelContext
        ) else { return }
        onSave(pursuit)
        dismiss()
    }
}

struct iOSGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSGoalEditorMode
    let onSave: (Goal) -> Void

    @State private var title: String
    @State private var desc: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var progressType: GoalProgressType
    @State private var targetHours: Double
    @State private var colorHex: String
    @State private var status: GoalStatus
    @State private var contextID: UUID?
    @State private var pursuitID: UUID?

    init(mode: iOSGoalEditorMode, onSave: @escaping (Goal) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .edit(let goal):
            _title = State(initialValue: goal.title)
            _desc = State(initialValue: goal.desc)
            _startDate = State(initialValue: DateFormatters.date(from: goal.startDate) ?? Date())
            _endDate = State(initialValue: DateFormatters.date(from: goal.endDate) ?? Date())
            _progressType = State(initialValue: goal.progressType)
            _targetHours = State(initialValue: goal.targetHours)
            _colorHex = State(initialValue: goal.colorHex)
            _status = State(initialValue: goal.status)
            _contextID = State(initialValue: goal.context?.id)
            _pursuitID = State(initialValue: goal.pursuit?.id)
        case .new(let pursuit):
            let start = Date()
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            _title = State(initialValue: "")
            _desc = State(initialValue: "")
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: end)
            _progressType = State(initialValue: .subtasks)
            _targetHours = State(initialValue: 0)
            _colorHex = State(initialValue: pursuit?.colorHex ?? "#4a9eff")
            _status = State(initialValue: .active)
            _contextID = State(initialValue: pursuit?.context?.id)
            _pursuitID = State(initialValue: pursuit?.id)
        }
    }

    private var editingGoal: Goal? {
        if case .edit(let goal) = mode { return goal }
        return nil
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = editingGoal?.pursuit,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var selectedPursuit: Pursuit? {
        pursuitID.flatMap { id in allPursuits.first { $0.id == id } }
    }

    private var canSave: Bool {
        PursuitAssignmentRules.canSaveMilestone(title: title, pursuitID: pursuitID)
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingGoal == nil ? "New Milestone" : "Edit Milestone",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Pass Exam P", text: $title)
            iOSTrackingTextField(title: "Definition of Done", placeholder: "What does done look like?", text: $desc, axis: .vertical)

            iOSTrackingPickerSection(title: "Pursuit") {
                Picker("Pursuit", selection: $pursuitID) {
                    Text("Choose Pursuit").tag(Optional<UUID>.none)
                    ForEach(pursuitChoices) { pursuit in
                        Label(pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title, systemImage: pursuit.icon)
                            .tag(Optional(pursuit.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Context") {
                Picker("Context", selection: $contextID) {
                    Text("Use Pursuit Context").tag(Optional<UUID>.none)
                    ForEach(contexts) { context in
                        Label(context.name, systemImage: context.icon).tag(Optional(context.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingDateRangeSection(startDate: $startDate, endDate: $endDate)

            iOSTrackingPickerSection(title: "Progress") {
                Picker("Progress", selection: $progressType) {
                    ForEach(GoalProgressType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                if progressType == .hours {
                    Stepper(value: $targetHours, in: 0...10_000, step: 1) {
                        HStack {
                            Text("Target Hours")
                            Spacer()
                            Text("\(Int(targetHours))h")
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            iOSTrackingPickerSection(title: "Status") {
                Picker("Status", selection: $status) {
                    ForEach(GoalStatus.allCases, id: \.self) { status in
                        Text(status.trackingLabel).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }

            iOSTrackingPickerSection(title: "Color") {
                iOSTrackingColorGrid(selection: $colorHex)
            }
        }
    }

    private func save() {
        guard let selectedPursuit else { return }
        guard let goal = CadenceTrackingMutationSupport.saveGoal(
            editingGoal,
            title: title,
            desc: desc,
            startDate: DateFormatters.dateKey(from: startDate),
            endDate: DateFormatters.dateKey(from: max(startDate, endDate)),
            progressType: progressType,
            targetHours: targetHours,
            colorHex: colorHex,
            status: status,
            context: selectedContext,
            pursuit: selectedPursuit,
            allGoals: allGoals,
            modelContext: modelContext
        ) else { return }
        onSave(goal)
        dismiss()
    }
}

struct iOSHabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.order) private var allHabits: [Habit]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var contexts: [Context]

    let mode: iOSHabitEditorMode
    let onSave: (Habit) -> Void

    @State private var title: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var frequencyType: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var monthlyDay: Int
    @State private var contextID: UUID?
    @State private var pursuitID: UUID?
    @State private var goalID: UUID?

    init(mode: iOSHabitEditorMode, onSave: @escaping (Habit) -> Void = { _ in }) {
        self.mode = mode
        self.onSave = onSave

        switch mode {
        case .edit(let habit):
            let storedDays = habit.frequencyDays
            _title = State(initialValue: habit.title)
            _icon = State(initialValue: habit.icon)
            _colorHex = State(initialValue: habit.colorHex)
            _frequencyType = State(initialValue: habit.frequencyType)
            _selectedDays = State(initialValue: habit.frequencyType == .daysOfWeek ? Set(storedDays) : [])
            _timesPerWeek = State(initialValue: habit.frequencyType == .timesPerWeek ? max(1, habit.targetCount) : 3)
            _monthlyDay = State(initialValue: habit.frequencyType == .monthly ? min(max(storedDays.first ?? 1, 1), 31) : 1)
            _contextID = State(initialValue: habit.context?.id)
            _pursuitID = State(initialValue: habit.pursuit?.id)
            _goalID = State(initialValue: habit.goal?.id)
        case .new(let pursuit):
            _title = State(initialValue: "")
            _icon = State(initialValue: "star.fill")
            _colorHex = State(initialValue: pursuit?.colorHex ?? "#4a9eff")
            _frequencyType = State(initialValue: .daily)
            _selectedDays = State(initialValue: [])
            _timesPerWeek = State(initialValue: 3)
            _monthlyDay = State(initialValue: 1)
            _contextID = State(initialValue: pursuit?.context?.id)
            _pursuitID = State(initialValue: pursuit?.id)
            _goalID = State(initialValue: nil)
        }
    }

    private var editingHabit: Habit? {
        if case .edit(let habit) = mode { return habit }
        return nil
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = editingHabit?.pursuit,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    private var goalChoices: [Goal] {
        allGoals.filter { goal in
            goal.status == .active && (pursuitID == nil || goal.pursuit?.id == pursuitID)
        }
    }

    private var selectedContext: Context? {
        contextID.flatMap { id in contexts.first { $0.id == id } }
    }

    private var selectedPursuit: Pursuit? {
        pursuitID.flatMap { id in allPursuits.first { $0.id == id } }
    }

    private var selectedGoal: Goal? {
        goalID.flatMap { id in allGoals.first { $0.id == id } }
    }

    private var canSave: Bool {
        PursuitAssignmentRules.canSaveHabit(title: title, pursuitID: pursuitID)
    }

    var body: some View {
        iOSTrackingEditorShell(
            title: editingHabit == nil ? "New Habit" : "Edit Habit",
            canSave: canSave,
            tint: Color(hex: colorHex),
            save: save
        ) {
            iOSTrackingTextField(title: "Title", placeholder: "e.g. Read for 20 minutes", text: $title)

            iOSTrackingPickerSection(title: "Pursuit") {
                Picker("Pursuit", selection: $pursuitID) {
                    Text("Choose Pursuit").tag(Optional<UUID>.none)
                    ForEach(pursuitChoices) { pursuit in
                        Label(pursuit.title.isEmpty ? "Untitled Pursuit" : pursuit.title, systemImage: pursuit.icon)
                            .tag(Optional(pursuit.id))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: pursuitID) { _, _ in
                    if let goalID, !goalChoices.contains(where: { $0.id == goalID }) {
                        self.goalID = nil
                    }
                }
            }

            iOSTrackingPickerSection(title: "Goal") {
                Picker("Goal", selection: $goalID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(goalChoices) { goal in
                        Label(goal.title.isEmpty ? "Untitled Milestone" : goal.title, systemImage: "flag.fill")
                            .tag(Optional(goal.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Context") {
                Picker("Context", selection: $contextID) {
                    Text("Use Pursuit Context").tag(Optional<UUID>.none)
                    ForEach(contexts) { context in
                        Label(context.name, systemImage: context.icon).tag(Optional(context.id))
                    }
                }
                .pickerStyle(.menu)
            }

            iOSTrackingPickerSection(title: "Frequency") {
                Picker("Frequency", selection: $frequencyType) {
                    ForEach(HabitFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.label).tag(frequency)
                    }
                }
                .pickerStyle(.segmented)

                iOSHabitFrequencyEditor(
                    frequencyType: frequencyType,
                    selectedDays: $selectedDays,
                    timesPerWeek: $timesPerWeek,
                    monthlyDay: $monthlyDay
                )
                .padding(.top, 10)
            }

            iOSTrackingPickerSection(title: "Icon") {
                iOSTrackingIconGrid(selection: $icon)
            }

            iOSTrackingPickerSection(title: "Color") {
                iOSTrackingColorGrid(selection: $colorHex)
            }
        }
    }

    private func save() {
        guard let selectedPursuit else { return }
        let frequency = resolvedFrequency()
        guard let habit = CadenceTrackingMutationSupport.saveHabit(
            editingHabit,
            title: title,
            icon: icon,
            colorHex: colorHex,
            frequencyType: frequencyType,
            frequencyDays: frequency.days,
            targetCount: frequency.targetCount,
            context: selectedContext,
            pursuit: selectedPursuit,
            goal: selectedGoal,
            allHabits: allHabits,
            modelContext: modelContext
        ) else { return }
        onSave(habit)
        dismiss()
    }

    private func resolvedFrequency() -> (days: [Int], targetCount: Int) {
        switch frequencyType {
        case .daily:
            return ([], 1)
        case .daysOfWeek:
            let days = selectedDays.isEmpty ? [Habit.weekdayIndex(for: Date())] : selectedDays.sorted()
            return (days, days.count)
        case .timesPerWeek:
            return ([timesPerWeek], timesPerWeek)
        case .monthly:
            return ([monthlyDay], 1)
        }
    }
}

private struct iOSTrackingEditorShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let canSave: Bool
    let tint: Color
    let save: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .tint(tint)
        }
    }
}

private struct iOSTrackingTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        iOSTrackingPickerSection(title: title) {
            field
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceElevated.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var field: some View {
        if axis == .vertical {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(3...6)
        } else {
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(1)
        }
    }
}

private struct iOSTrackingPickerSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.dim)
                .textCase(.uppercase)
                .kerning(0.8)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
            }
        }
    }
}

private struct iOSTrackingDateRangeSection: View {
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        iOSTrackingPickerSection(title: "Dates") {
            DatePicker("Start", selection: $startDate, displayedComponents: .date)
                .tint(Theme.blue)
            Divider().background(Theme.borderSubtle.opacity(0.55)).padding(.vertical, 8)
            DatePicker("End", selection: $endDate, displayedComponents: .date)
                .tint(Theme.blue)
                .onChange(of: endDate) { _, newValue in
                    if newValue < startDate {
                        endDate = startDate
                    }
                }
        }
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue {
                endDate = newValue
            }
        }
    }
}

private struct iOSHabitFrequencyEditor: View {
    let frequencyType: HabitFrequency
    @Binding var selectedDays: Set<Int>
    @Binding var timesPerWeek: Int
    @Binding var monthlyDay: Int

    private let weekdays = [
        (1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")
    ]

    var body: some View {
        switch frequencyType {
        case .daily:
            Text("Every day")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
        case .daysOfWeek:
            HStack(spacing: 7) {
                ForEach(weekdays, id: \.0) { day, label in
                    Button {
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(selectedDays.contains(day) ? Theme.text : Theme.dim)
                            .frame(width: 34, height: 34)
                            .background(selectedDays.contains(day) ? Theme.blue.opacity(0.22) : Theme.surfaceElevated)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .timesPerWeek:
            Stepper(value: $timesPerWeek, in: 1...14) {
                HStack {
                    Text("Times per week")
                    Spacer()
                    Text("\(timesPerWeek)")
                        .foregroundStyle(Theme.dim)
                }
            }
        case .monthly:
            Stepper(value: $monthlyDay, in: 1...31) {
                HStack {
                    Text("Day of month")
                    Spacer()
                    Text("\(monthlyDay)")
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

private struct iOSTrackingIconGrid: View {
    @Binding var selection: String
    private let icons = ["sparkles", "star.fill", "flag.fill", "flame.fill", "book.fill", "figure.run", "heart.fill", "brain.head.profile", "paintbrush.fill", "briefcase.fill", "leaf.fill", "music.note"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selection = icon
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selection == icon ? Theme.text : Theme.dim)
                        .frame(height: 36)
                        .frame(maxWidth: .infinity)
                        .background(selection == icon ? Theme.blue.opacity(0.22) : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct iOSTrackingColorGrid: View {
    @Binding var selection: String
    private let colors = ["#4a9eff", "#a78bfa", "#4ecb71", "#ffb84d", "#ff6b6b", "#38d5c7", "#f472b6", "#94a3b8"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(colors, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .strokeBorder(selection == color ? Theme.text : Color.clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension GoalStatus {
    var trackingLabel: String {
        switch self {
        case .active: return "Active"
        case .done: return "Done"
        case .paused: return "Paused"
        }
    }
}
#endif
