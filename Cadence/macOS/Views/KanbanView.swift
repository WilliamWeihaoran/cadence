#if os(macOS)
import SwiftUI
import SwiftData

struct KanbanView: View {
    let tasks: [AppTask]
    var area: Area? = nil
    var project: Project? = nil
    @Environment(\.modelContext) private var modelContext

    private let columns: [(status: TaskStatus, label: String, color: Color)] = [
        (.todo,       "To Do",       Theme.dim),
        (.inProgress, "In Progress", Theme.blue),
        (.done,       "Done",        Theme.green),
        (.cancelled,  "Cancelled",   Theme.red),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns, id: \.status) { col in
                    KanbanColumn(
                        status: col.status,
                        label: col.label,
                        color: col.color,
                        tasks: tasks.filter { $0.status == col.status },
                        area: area,
                        project: project
                    )
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
    }
}

// MARK: - Column

private struct KanbanColumn: View {
    let status: TaskStatus
    let label: String
    let color: Color
    let tasks: [AppTask]
    var area: Area?
    var project: Project?

    @Environment(\.modelContext) private var modelContext
    @State private var isTargeted = false
    @State private var newTitle = ""
    @State private var isAdding = false
    @FocusState private var addFocused: Bool
    @Query private var allTasks: [AppTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(Theme.borderSubtle)

            // Cards
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(tasks.sorted { $0.order < $1.order }) { task in
                        KanbanCard(task: task)
                            .draggable(task.id.uuidString)
                    }

                    if isAdding {
                        TextField("Task name…", text: $newTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                            .padding(10)
                            .background(Theme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .focused($addFocused)
                            .onSubmit { addTask() }
                            .onExitCommand { isAdding = false; newTitle = "" }
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 200)

            Divider().background(Theme.borderSubtle)

            // Add button
            Button {
                isAdding = true
                addFocused = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("Add task")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? color.opacity(0.06) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isTargeted ? color.opacity(0.4) : Theme.borderSubtle)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let uuid = UUID(uuidString: uuidString),
                  let task = allTasks.first(where: { $0.id == uuid }) else { return false }
            task.status = status
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { isAdding = false; return }
        let task = AppTask(title: title)
        task.status = status
        task.area = area
        task.project = project
        task.context = area?.context ?? project?.context
        task.order = tasks.count
        modelContext.insert(task)
        newTitle = ""
        addFocused = true
    }
}

// MARK: - Card

private struct KanbanCard: View {
    @Bindable var task: AppTask
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isEditing {
                TextField("", text: $task.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { isEditing = false }
                    .onExitCommand { isEditing = false }
            } else {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isDone || task.isCancelled ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                if task.priority != .none {
                    Text(task.priority.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.priorityColor(task.priority))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.priorityColor(task.priority).opacity(0.12))
                        .clipShape(Capsule())
                }
                if !task.dueDate.isEmpty {
                    Text(task.dueDate)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(count: 2) {
            isEditing = true
            focused = true
        }
    }
}
#endif
