#if os(macOS)
import SwiftUI
import SwiftData

struct PursuitsView: View {
    @Query(sort: \Pursuit.order) private var pursuits: [Pursuit]
    @Query(sort: \Context.order) private var contexts: [Context]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPursuitID: UUID?
    @State private var showCreatePursuit = false
    @State private var editingPursuit: Pursuit?
    @State private var searchText = ""

    private var filteredPursuits: [Pursuit] {
        pursuits.filter { pursuit in
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return pursuit.title.lowercased().contains(query)
                || pursuit.desc.lowercased().contains(query)
                || (pursuit.context?.name.lowercased().contains(query) ?? false)
        }
    }

    private var pursuitGroups: [PursuitContextGroup] {
        var groups: [PursuitContextGroup] = contexts.compactMap { context in
            let items = filteredPursuits.filter { $0.context?.id == context.id }
            guard !items.isEmpty else { return nil }
            return PursuitContextGroup(
                id: context.id.uuidString,
                title: context.name,
                icon: context.icon,
                colorHex: context.colorHex,
                pursuits: items
            )
        }

        let loose = filteredPursuits.filter { $0.context == nil }
        if !loose.isEmpty {
            groups.append(
                PursuitContextGroup(
                    id: "none",
                    title: "No Context",
                    icon: "circle.dashed",
                    colorHex: "#6b7a99",
                    pursuits: loose
                )
            )
        }
        return groups
    }

    private var selectedPursuit: Pursuit? {
        if let selectedPursuitID {
            return pursuits.first { $0.id == selectedPursuitID }
        }
        return filteredPursuits.first ?? pursuits.first
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                header
                Divider().background(Theme.borderSubtle)
                pursuitList
            }
            .frame(minWidth: 360, idealWidth: 440)
            .background(Theme.surface)

            if let pursuit = selectedPursuit {
                PursuitDetailView(
                    pursuit: pursuit,
                    onEdit: { editingPursuit = pursuit }
                )
                .frame(minWidth: 560, idealWidth: 720)
            } else {
                EmptyStateView(
                    message: "No pursuits yet",
                    subtitle: "Create a pursuit for ongoing directions like learning, strength, or craft.",
                    icon: "sparkles"
                )
                .frame(minWidth: 560, idealWidth: 720)
                .background(Theme.bg)
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showCreatePursuit) {
            CreatePursuitSheet()
        }
        .sheet(item: $editingPursuit) { pursuit in
            CreatePursuitSheet(pursuit: pursuit)
        }
        .onAppear {
            if selectedPursuitID == nil {
                selectedPursuitID = filteredPursuits.first?.id ?? pursuits.first?.id
            }
        }
        .onChange(of: filteredPursuits.map(\.id)) {
            guard let selectedPursuitID,
                  filteredPursuits.contains(where: { $0.id == selectedPursuitID }) || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                self.selectedPursuitID = filteredPursuits.first?.id ?? pursuits.first?.id
                return
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pursuits")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Directions powered by goals and habits.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                CadenceActionButton(
                    title: "New Pursuit",
                    systemImage: "plus",
                    role: .primary,
                    size: .compact
                ) {
                    showCreatePursuit = true
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                TextField("Search pursuits", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
        }
        .padding(20)
        .background(Theme.surface)
    }

    @ViewBuilder
    private var pursuitList: some View {
        if pursuitGroups.isEmpty {
            Spacer()
            EmptyStateView(
                message: searchText.isEmpty ? "No pursuits yet" : "No matching pursuits",
                subtitle: searchText.isEmpty ? "Use pursuits for ongoing directions, then add goals and habits inside them." : "Try a different search.",
                icon: "sparkles"
            )
            Spacer()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(pursuitGroups) { group in
                        PursuitContextGroupView(
                            group: group,
                            selectedPursuitID: selectedPursuitID,
                            onSelect: { selectedPursuitID = $0.id }
                        )
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct PursuitContextGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let pursuits: [Pursuit]
}

private struct PursuitContextGroupView: View {
    let group: PursuitContextGroup
    let selectedPursuitID: UUID?
    let onSelect: (Pursuit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: group.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: group.colorHex))
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Spacer()
            }

            VStack(spacing: 9) {
                ForEach(group.pursuits) { pursuit in
                    PursuitListCard(
                        pursuit: pursuit,
                        isSelected: selectedPursuitID == pursuit.id,
                        onSelect: { onSelect(pursuit) }
                    )
                }
            }
        }
    }
}

private struct PursuitListCard: View {
    let pursuit: Pursuit
    let isSelected: Bool
    let onSelect: () -> Void

    private var activeGoals: [Goal] {
        (pursuit.goals ?? []).filter { $0.status == .active }
    }

    private var habits: [Habit] {
        pursuit.habits ?? []
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: pursuit.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: pursuit.colorHex))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: pursuit.colorHex).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 5) {
                    Text(pursuit.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Text("\(activeGoals.count) goals")
                        Text("\(habits.count) habits")
                        Text(pursuit.status.label)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)
                }

                Spacer()
            }
            .padding(12)
            .background(isSelected ? Theme.surfaceElevated : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: pursuit.colorHex).opacity(0.65) : Theme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PursuitDetailView: View {
    let pursuit: Pursuit
    let onEdit: () -> Void

    private var goals: [Goal] {
        (pursuit.goals ?? []).sorted { $0.order < $1.order }
    }

    private var habits: [Habit] {
        (pursuit.habits ?? []).sorted { $0.order < $1.order }
    }

    private var activeGoalCount: Int {
        goals.filter { $0.status == .active }.count
    }

    private var dueHabitsToday: [Habit] {
        habits.filter(\.isDueToday)
    }

    private var doneHabitsToday: Int {
        dueHabitsToday.filter { $0.isDone(on: DateFormatters.todayKey()) }.count
    }

    private var nextActionTitle: String? {
        goals.compactMap { GoalContributionResolver.summary(for: $0).nextActionTitle }.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                hero
                signalRow
                goalsSection
                habitsSection
            }
            .padding(24)
        }
        .background(Theme.bg)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: pursuit.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(hex: pursuit.colorHex))
                    .frame(width: 54, height: 54)
                    .background(Color(hex: pursuit.colorHex).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(pursuit.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        PursuitStatusBadge(status: pursuit.status)
                    }
                    Text(pursuit.desc.isEmpty ? "No direction yet" : pursuit.desc)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let context = pursuit.context {
                        Text(context.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: context.colorHex))
                    }
                }

                Spacer()

                CadenceActionButton(
                    title: "Edit",
                    systemImage: "pencil",
                    role: .secondary,
                    size: .compact,
                    tint: Color(hex: pursuit.colorHex),
                    action: onEdit
                )
            }
        }
        .padding(18)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: pursuit.colorHex).opacity(0.24), lineWidth: 1))
    }

    private var signalRow: some View {
        HStack(spacing: 12) {
            PursuitSignalTile(title: "Active Goals", value: "\(activeGoalCount)", icon: "target", color: Theme.green)
            PursuitSignalTile(title: "Habits Today", value: dueHabitsToday.isEmpty ? "None due" : "\(doneHabitsToday)/\(dueHabitsToday.count)", icon: "flame.fill", color: Theme.amber)
            PursuitSignalTile(title: "Next Action", value: nextActionTitle ?? "None", icon: "checklist", color: Theme.blue)
        }
    }

    @ViewBuilder
    private var goalsSection: some View {
        PursuitSection(title: "Goals", count: goals.count) {
            if goals.isEmpty {
                PursuitEmptySectionText("No goals in this pursuit yet.")
            } else {
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        PursuitGoalRow(goal: goal)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var habitsSection: some View {
        PursuitSection(title: "Habits", count: habits.count) {
            if habits.isEmpty {
                PursuitEmptySectionText("No habits in this pursuit yet.")
            } else {
                VStack(spacing: 8) {
                    ForEach(habits) { habit in
                        PursuitHabitRow(habit: habit)
                    }
                }
            }
        }
    }
}

private struct PursuitSignalTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

private struct PursuitSection<Content: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.text.opacity(0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.surfaceElevated)
                    .clipShape(Capsule())
                Spacer()
            }
            content
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.borderSubtle, lineWidth: 1))
    }
}

private struct PursuitGoalRow: View {
    let goal: Goal

    private var summary: GoalContributionSummary {
        GoalContributionResolver.summary(for: goal)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: goal.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: goal.colorHex).opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(goal.desc.isEmpty ? "No outcome yet" : goal.desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
            Spacer()
            Text(summary.percentLabel)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PursuitHabitRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: habit.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: habit.colorHex))
                .frame(width: 28, height: 28)
                .background(Color(hex: habit.colorHex).opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(habit.frequencySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Text(habit.currentStreak > 0 ? "\(habit.currentStreak)d" : "No streak")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(habit.currentStreak > 0 ? Theme.amber : Theme.dim)
        }
        .padding(10)
        .background(Theme.surfaceElevated.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PursuitEmptySectionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surfaceElevated.opacity(0.36))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PursuitStatusBadge: View {
    let status: PursuitStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .active: return Theme.green
        case .paused: return Theme.amber
        case .done: return Theme.blue
        }
    }
}

private struct CreatePursuitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var allContexts: [Context]

    private let editingPursuit: Pursuit?

    @State private var title = ""
    @State private var desc = ""
    @State private var selectedIcon = "sparkles"
    @State private var selectedColor = "#a78bfa"
    @State private var selectedContextID: UUID?
    @State private var selectedStatus: PursuitStatus = .active
    @Environment(\.modelContext) private var modelContext

    init(pursuit: Pursuit? = nil) {
        editingPursuit = pursuit
        _title = State(initialValue: pursuit?.title ?? "")
        _desc = State(initialValue: pursuit?.desc ?? "")
        _selectedIcon = State(initialValue: pursuit?.icon ?? "sparkles")
        _selectedColor = State(initialValue: pursuit?.colorHex ?? "#a78bfa")
        _selectedContextID = State(initialValue: pursuit?.context?.id)
        _selectedStatus = State(initialValue: pursuit?.status ?? .active)
    }

    private var isEditing: Bool {
        editingPursuit != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Pursuit" : "New Pursuit")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    fieldLabel("Title")
                    TextField("e.g. Become more knowledgeable", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Direction")
                    TextField("What are you trying to cultivate?", text: $desc)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    fieldLabel("Context")
                    CadenceContextPickerButton(
                        contexts: allContexts,
                        selectedID: $selectedContextID
                    )

                    if isEditing {
                        fieldLabel("Status")
                        PursuitStatusSection(selection: $selectedStatus)
                    }

                    fieldLabel("Icon")
                    IconGrid(selected: $selectedIcon)

                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Spacer()
                CadenceActionButton(title: "Cancel", role: .ghost, size: .compact) {
                    dismiss()
                }
                CadenceActionButton(
                    title: isEditing ? "Save" : "Create",
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

        let pursuit = editingPursuit ?? Pursuit(title: trimmed)
        pursuit.title = trimmed
        pursuit.desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        pursuit.icon = selectedIcon
        pursuit.colorHex = selectedColor
        pursuit.status = selectedStatus
        pursuit.context = selectedContextID.flatMap { id in allContexts.first { $0.id == id } }

        if editingPursuit == nil {
            pursuit.order = allPursuits.count
            modelContext.insert(pursuit)
        }

        dismiss()
    }
}

private struct PursuitStatusSection: View {
    @Binding var selection: PursuitStatus

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PursuitStatus.allCases, id: \.self) { status in
                CadencePillButton(
                    title: status.label,
                    isSelected: selection == status,
                    minWidth: 70,
                    tint: tint(for: status)
                ) {
                    selection = status
                }
            }
        }
        .padding(4)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderSubtle, lineWidth: 1))
    }

    private func tint(for status: PursuitStatus) -> Color {
        switch status {
        case .active: return Theme.green
        case .paused: return Theme.amber
        case .done: return Theme.blue
        }
    }
}
#endif
