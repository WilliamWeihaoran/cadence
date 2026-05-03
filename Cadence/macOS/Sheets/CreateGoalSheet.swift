#if os(macOS)
import SwiftUI
import SwiftData

struct CreateGoalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Pursuit.order) private var allPursuits: [Pursuit]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private let editingGoal: Goal?

    @State private var title = ""
    @State private var desc = ""
    @State private var selectedContextID: UUID? = nil
    @State private var selectedPursuitID: UUID? = nil
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var initialListTag = "none"
    @State private var selectedColor = "#4a9eff"
    @State private var selectedStatus: GoalStatus = .active

    init(goal: Goal? = nil) {
        editingGoal = goal
        let initialStart = goal.flatMap { DateFormatters.ymd.date(from: $0.startDate) } ?? Date()
        let proposedEnd = goal.flatMap { DateFormatters.ymd.date(from: $0.endDate) }
            ?? Calendar.current.date(byAdding: .month, value: 1, to: initialStart)
            ?? initialStart
        let initialEnd = proposedEnd < initialStart ? initialStart : proposedEnd

        _title = State(initialValue: goal?.title ?? "")
        _desc = State(initialValue: goal?.desc ?? "")
        _selectedContextID = State(initialValue: goal?.context?.id)
        _selectedPursuitID = State(initialValue: goal?.pursuit?.id)
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: initialEnd)
        _selectedColor = State(initialValue: goal?.colorHex ?? "#4a9eff")
        _selectedStatus = State(initialValue: goal?.status ?? .active)
    }

    private var isEditing: Bool {
        editingGoal != nil
    }

    private var pursuitChoices: [Pursuit] {
        var choices = allPursuits.filter { $0.status == .active }
        if let current = editingGoal?.pursuit,
           !choices.contains(where: { $0.id == current.id }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Goal" : "New Goal")
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
                    TextField("e.g. Ship Cadence goals, Finish ASA", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text)
                        .padding(10)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    // Outcome / desc
                    fieldLabel("Outcome")
                    TextField("What does done look like?", text: $desc)
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

                    if !pursuitChoices.isEmpty {
                        fieldLabel("Pursuit")
                        CadencePursuitPickerButton(
                            pursuits: pursuitChoices,
                            selectedID: $selectedPursuitID
                        )
                    }

                    if isEditing {
                        fieldLabel("Status")
                        GoalStatusSection(selection: $selectedStatus)
                    } else {
                        fieldLabel("Initial Linked List")
                        Picker("", selection: $initialListTag) {
                            Text("None").tag("none")
                            ForEach(allContexts) { ctx in
                                Section(ctx.name) {
                                    ForEach(areas.filter { $0.context?.id == ctx.id }) { area in
                                        Label(area.name, systemImage: area.icon).tag("area:\(area.id.uuidString)")
                                    }
                                    ForEach(projects.filter { $0.context?.id == ctx.id }) { project in
                                        Label(project.name, systemImage: project.icon).tag("project:\(project.id.uuidString)")
                                    }
                                }
                            }
                            let looseAreas = areas.filter { $0.context == nil }
                            let looseProjects = projects.filter { $0.context == nil }
                            if !looseAreas.isEmpty || !looseProjects.isEmpty {
                                Section("No Context") {
                                    ForEach(looseAreas) { area in
                                        Label(area.name, systemImage: area.icon).tag("area:\(area.id.uuidString)")
                                    }
                                    ForEach(looseProjects) { project in
                                        Label(project.name, systemImage: project.icon).tag("project:\(project.id.uuidString)")
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundStyle(Theme.text)
                        .padding(8)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Start Date")
                            CadenceDatePicker(selection: $startDate)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("End Date")
                            CadenceDatePicker(selection: $endDate)
                        }
                    }

                    // Color
                    fieldLabel("Color")
                    ColorGrid(selected: $selectedColor)
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
                    title: isEditing ? "Save" : "Create",
                    role: .primary,
                    size: .compact,
                    isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    save()
                }
            }
            .padding(16)
        }
        .frame(width: 420, height: 620)
        .background(Theme.surface)
        .onChange(of: startDate) {
            if endDate < startDate {
                endDate = startDate
            }
        }
        .onChange(of: endDate) {
            if endDate < startDate {
                endDate = startDate
            }
        }
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .kerning(0.8)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let editingGoal {
            applyFields(to: editingGoal, title: trimmed)
        } else {
            let goal = Goal(title: trimmed)
            goal.progressType = .subtasks
            goal.targetHours = 0
            goal.order = allGoals.count
            applyFields(to: goal, title: trimmed)
            modelContext.insert(goal)
            attachInitialList(to: goal)
        }

        dismiss()
    }

    private func applyFields(to goal: Goal, title: String) {
        goal.title = title
        goal.desc = desc.trimmingCharacters(in: .whitespaces)
        goal.startDate = DateFormatters.dateKey(from: startDate)
        goal.endDate = DateFormatters.dateKey(from: max(endDate, startDate))
        goal.colorHex = selectedColor
        goal.status = selectedStatus
        let selectedPursuit = selectedPursuitID.flatMap { id in allPursuits.first { $0.id == id } }
        goal.pursuit = selectedPursuit
        if let selectedContextID {
            goal.context = allContexts.first { $0.id == selectedContextID }
        } else {
            goal.context = selectedPursuit?.context
        }
    }

    private func attachInitialList(to goal: Goal) {
        if initialListTag.hasPrefix("area:"),
           let id = UUID(uuidString: String(initialListTag.dropFirst(5))),
           let area = areas.first(where: { $0.id == id }) {
            modelContext.insert(GoalListLink(goal: goal, area: area))
        } else if initialListTag.hasPrefix("project:"),
                  let id = UUID(uuidString: String(initialListTag.dropFirst(8))),
                  let project = projects.first(where: { $0.id == id }) {
            modelContext.insert(GoalListLink(goal: goal, project: project))
        }
    }
}

private struct GoalStatusSection: View {
    @Binding var selection: GoalStatus

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GoalStatus.allCases, id: \.self) { status in
                statusButton(status)
            }
        }
    }

    private func statusButton(_ status: GoalStatus) -> some View {
        let isSelected = selection == status
        let tint = color(for: status)

        return Button {
            selection = status
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: status))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : tint)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? tint : tint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: status))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                        .lineLimit(1)

                    Text(subtitle(for: status))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isSelected ? tint.opacity(0.12) : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? tint.opacity(0.45) : Theme.borderSubtle, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.cadencePlain)
    }

    private func title(for status: GoalStatus) -> String {
        switch status {
        case .active: return "Active"
        case .paused: return "Paused"
        case .done: return "Done"
        }
    }

    private func subtitle(for status: GoalStatus) -> String {
        switch status {
        case .active: return "In motion"
        case .paused: return "Parked"
        case .done: return "Complete"
        }
    }

    private func icon(for status: GoalStatus) -> String {
        switch status {
        case .active: return "play.fill"
        case .paused: return "pause.fill"
        case .done: return "checkmark"
        }
    }

    private func color(for status: GoalStatus) -> Color {
        switch status {
        case .active: return Theme.blue
        case .paused: return Theme.amber
        case .done: return Theme.green
        }
    }
}
#endif
