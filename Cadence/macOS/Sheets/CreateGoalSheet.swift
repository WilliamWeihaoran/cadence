#if os(macOS)
import SwiftUI
import SwiftData

struct CreateGoalSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.order) private var allGoals: [Goal]
    @Query(sort: \Context.order) private var allContexts: [Context]
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    private let editingGoal: Goal?

    @State private var title = ""
    @State private var desc = ""
    @State private var selectedContextID: UUID? = nil
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
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: initialEnd)
        _selectedColor = State(initialValue: goal?.colorHex ?? "#4a9eff")
        _selectedStatus = State(initialValue: goal?.status ?? .active)
    }

    private var isEditing: Bool {
        editingGoal != nil
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

                    // Context
                    fieldLabel("Context")
                    Picker("", selection: $selectedContextID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(allContexts) { ctx in
                            Label(ctx.name, systemImage: ctx.icon).tag(Optional(ctx.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .foregroundStyle(Theme.text)
                    .padding(8)
                    .background(Theme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderSubtle))

                    if isEditing {
                        fieldLabel("Status")
                        Picker("", selection: $selectedStatus) {
                            ForEach(GoalStatus.allCases, id: \.self) { status in
                                Text(statusLabel(status)).tag(status)
                            }
                        }
                        .pickerStyle(.segmented)
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

                    // Dates
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("Start Date")
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .foregroundStyle(Theme.text)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("End Date")
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .foregroundStyle(Theme.text)
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
        goal.context = selectedContextID.flatMap { id in allContexts.first { $0.id == id } }
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

    private func statusLabel(_ status: GoalStatus) -> String {
        switch status {
        case .active: return "Active"
        case .paused: return "Paused"
        case .done: return "Done"
        }
    }
}
#endif
