#if os(macOS)
import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaskCreationManager.self) private var taskCreationManager
    @Query(sort: \AppTask.order) private var allTasks: [AppTask]

    @State private var newTitle = ""
    @FocusState private var captureFocused: Bool

    private var inboxTasks: [AppTask] {
        allTasks.filter { $0.area == nil && $0.project == nil && !$0.isCancelled }
    }
    private var activeTasks: [AppTask] { inboxTasks.filter { !$0.isDone } }
    private var doneTasks:   [AppTask] { inboxTasks.filter {  $0.isDone } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.borderSubtle)
            captureBar
            Divider().background(Theme.borderSubtle)

            if activeTasks.isEmpty && doneTasks.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(activeTasks) { task in
                        MacTaskRow(task: task, style: .standard)
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .draggable("listTask:\(task.id.uuidString)")
                            .dropDestination(for: String.self) { items, _ in
                                guard let payload = items.first,
                                      payload.hasPrefix("listTask:"),
                                      let droppedID = UUID(uuidString: String(payload.dropFirst(9))),
                                      droppedID != task.id else { return false }
                                reorderTask(droppedID: droppedID, targetID: task.id)
                                return true
                            }
                    }

                    if !doneTasks.isEmpty {
                        Text("DONE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.green)
                            .kerning(0.8)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(.init())
                        ForEach(doneTasks) { task in
                            MacTaskRow(task: task, style: .standard)
                                .listRowInsets(.init())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
            }
        }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture { clearAppEditingFocus() }
        )
        .background(Theme.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TASKS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .kerning(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Inbox")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.text)
                    if !activeTasks.isEmpty {
                        Text("\(activeTasks.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Button {
                taskCreationManager.present()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("New Task").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.cadencePlain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Theme.surface)
    }

    // MARK: - Capture Bar

    private var captureBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(captureFocused ? Theme.blue : Theme.dim)
                .animation(.easeInOut(duration: 0.15), value: captureFocused)

            TextField("Capture a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($captureFocused)
                .onSubmit { captureTask() }

            if !newTitle.isEmpty {
                Button(action: captureTask) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.cadencePlain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Theme.surfaceElevated)
        .animation(.easeInOut(duration: 0.15), value: newTitle.isEmpty)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.blue.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "tray")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.blue.opacity(0.6))
                }
                VStack(spacing: 6) {
                    Text("Inbox is empty")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Tasks without a list land here.\nCapture something to get started.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
                Button {
                    captureFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Capture a task")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func captureTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let task = AppTask(title: t)
        task.order = activeTasks.count
        modelContext.insert(task)
        newTitle = ""
    }

    private func reorderTask(droppedID: UUID, targetID: UUID) {
        var sorted = activeTasks
        guard let fromIndex = sorted.firstIndex(where: { $0.id == droppedID }),
              let toIndex = sorted.firstIndex(where: { $0.id == targetID }) else { return }
        let element = sorted.remove(at: fromIndex)
        sorted.insert(element, at: toIndex > fromIndex ? toIndex - 1 : toIndex)
        for (i, t) in sorted.enumerated() { t.order = i }
    }
}
#endif
