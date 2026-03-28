#if os(macOS)
import SwiftUI
import SwiftData

struct CreateTaskSheet: View {
    let seed: TaskCreationSeed
    let dismissAction: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \Area.order) private var areas: [Area]
    @Query(sort: \Project.order) private var projects: [Project]

    @State private var title: String
    @State private var notes: String
    @State private var selectedPriority: TaskPriority
    @State private var selectedContainer: TaskContainerSelection
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasDoDate: Bool
    @State private var doDate: Date

    init(seed: TaskCreationSeed, dismissAction: (() -> Void)? = nil) {
        self.seed = seed
        self.dismissAction = dismissAction

        let resolvedDueDate = DateFormatters.date(from: seed.dueDateKey) ?? Date()
        let resolvedDoDate = DateFormatters.date(from: seed.doDateKey) ?? Date()

        _title = State(initialValue: seed.title)
        _notes = State(initialValue: seed.notes)
        _selectedPriority = State(initialValue: seed.priority)
        _selectedContainer = State(initialValue: seed.container)
        _hasDueDate = State(initialValue: !seed.dueDateKey.isEmpty)
        _dueDate = State(initialValue: resolvedDueDate)
        _hasDoDate = State(initialValue: !seed.doDateKey.isEmpty)
        _doDate = State(initialValue: resolvedDoDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Task")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Capture it once, then decide when it is due and when you want to do it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                Text("Ctrl-Space")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.blue.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider().background(Theme.borderSubtle)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    labeledSection("Title") {
                        TextField("What needs doing?", text: $title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .padding(12)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.borderSubtle)
                            )
                    }

                    HStack(alignment: .top, spacing: 14) {
                        detailCard(title: "Due Date", icon: "calendar.badge.exclamationmark") {
                            dateToggleRow(isOn: $hasDueDate, emptyLabel: "No due date") {
                                CadenceDatePicker(selection: $dueDate)
                            }
                        }

                        detailCard(title: "Do Date", icon: "calendar") {
                            dateToggleRow(isOn: $hasDoDate, emptyLabel: "Not scheduled for a day yet") {
                                CadenceDatePicker(selection: $doDate)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 14) {
                        detailCard(title: "Priority", icon: "flag") {
                            HStack(spacing: 8) {
                                ForEach(TaskPriority.allCases, id: \.self) { priority in
                                    Button {
                                        selectedPriority = priority
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Theme.priorityColor(priority))
                                                .frame(width: 7, height: 7)
                                            Text(priority.label)
                                                .font(.system(size: 11, weight: selectedPriority == priority ? .semibold : .regular))
                                        }
                                        .foregroundStyle(selectedPriority == priority ? Theme.text : Theme.muted)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(selectedPriority == priority ? Theme.surface : Color.clear)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(4)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.borderSubtle)
                            )
                        }

                        detailCard(title: "List", icon: "tray.full") {
                            Picker("", selection: $selectedContainer) {
                                Text("Inbox").tag(TaskContainerSelection.inbox)

                                if !areas.isEmpty {
                                    Divider()
                                    ForEach(areas) { area in
                                        Text(area.name).tag(TaskContainerSelection.area(area.id))
                                    }
                                }

                                if !projects.isEmpty {
                                    Divider()
                                    ForEach(projects) { project in
                                        Text(project.name).tag(TaskContainerSelection.project(project.id))
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.borderSubtle)
                            )
                        }
                    }

                    labeledSection("Notes") {
                        TextEditor(text: $notes)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 130)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Theme.borderSubtle)
                            )
                    }
                }
                .padding(24)
            }

            Divider().background(Theme.borderSubtle)

            HStack {
                Text("Tip: use due date for deadlines and do date for when you want this to show up in planning.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Button("Create Task") {
                    createTask()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(trimmedTitle.isEmpty)
                .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
        .background(Theme.surface)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func labeledSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .kerning(0.8)
            content()
        }
    }

    @ViewBuilder
    private func detailCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.borderSubtle)
        )
    }

    @ViewBuilder
    private func dateToggleRow<Content: View>(
        isOn: Binding<Bool>,
        emptyLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.78)

            if isOn.wrappedValue {
                content()
            } else {
                Text(emptyLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func createTask() {
        let task = AppTask(title: trimmedTitle)
        task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        task.priority = selectedPriority

        if hasDueDate {
            task.dueDate = DateFormatters.dateKey(from: dueDate)
        }

        if hasDoDate {
            task.scheduledDate = DateFormatters.dateKey(from: doDate)
        }

        switch selectedContainer {
        case .inbox:
            task.area = nil
            task.project = nil
            task.context = nil
        case .area(let areaID):
            if let area = areas.first(where: { $0.id == areaID }) {
                task.area = area
                task.project = nil
                task.context = area.context
            }
        case .project(let projectID):
            if let project = projects.first(where: { $0.id == projectID }) {
                task.project = project
                task.area = nil
                task.context = project.context
            }
        }

        modelContext.insert(task)
        dismiss()
    }

    private func dismiss() {
        if let dismissAction {
            dismissAction()
        } else {
            taskCreationManager.dismiss()
        }
    }
}
#endif
