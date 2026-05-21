#if os(iOS)
import SwiftData
import SwiftUI

enum iOSTaskSortMode: String, CaseIterable, Identifiable {
    case listOrder = "listOrder"
    case priority = "priority"
    case dueDate = "dueDate"
    case newest = "newest"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listOrder: return "List Order"
        case .priority: return "Priority"
        case .dueDate: return "Due Date"
        case .newest: return "Newest"
        }
    }
}

extension iOSTaskSortMode {
    var cadenceSortMode: CadenceTaskSortMode {
        switch self {
        case .listOrder: return .listOrder
        case .priority: return .priority
        case .dueDate: return .dueDate
        case .newest: return .newest
        }
    }
}

struct iOSTaskRow: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @State private var showDetail = false
    @State private var showDeleteConfirmation = false

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .top, spacing: isRegularWidth ? 12 : 9) {
            Button {
                toggleCompletion()
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: isRegularWidth ? 19 : 16, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.green : Theme.dim.opacity(0.68))
                    .frame(width: isRegularWidth ? 24 : 20, height: isRegularWidth ? 24 : 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark task todo" : "Complete task")

            VStack(alignment: .leading, spacing: isRegularWidth ? 8 : 6) {
                Text(task.title.isEmpty ? "Untitled" : task.title)
                    .font(.system(size: isRegularWidth ? 15 : 13, weight: .semibold))
                    .foregroundStyle(task.isDone ? Theme.dim : Theme.text)
                    .strikethrough(task.isDone, color: Theme.dim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    priorityBadge

                    if !task.scheduledDate.isEmpty {
                        taskBadge(
                            systemImage: "sun.max.fill",
                            text: DateFormatters.relativeDate(from: task.scheduledDate),
                            color: task.scheduledDate == DateFormatters.todayKey() ? Theme.amber : Theme.dim
                        )
                    }

                    if !task.dueDate.isEmpty {
                        taskBadge(
                            systemImage: "flag.fill",
                            text: DateFormatters.relativeDate(from: task.dueDate),
                            color: isOverdue ? Theme.red : Theme.dim
                        )
                    }

                    if task.estimatedMinutes > 0 {
                        taskBadge(
                            systemImage: "clock",
                            text: estimateLabel,
                            color: Theme.dim
                        )
                    }
                }

                if !task.sortedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(task.sortedTags.prefix(4)) { tag in
                                iOSTagChip(tag: tag)
                            }

                            if task.sortedTags.count > 4 {
                                Text("+\(task.sortedTags.count - 4)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.dim)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Theme.surfaceElevated)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: isRegularWidth ? 12 : 10, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.65))
                .padding(.top, 4)
        }
        .padding(.horizontal, isRegularWidth ? 14 : 11)
        .padding(.vertical, isRegularWidth ? 12 : 9)
        .background(Theme.surfaceElevated.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous)
                .stroke(Theme.borderSubtle.opacity(0.55), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
        .onTapGesture {
            showDetail = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens task details")
        .sheet(isPresented: $showDetail) {
            iOSTaskDetailSheet(task: task)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleCompletion()
            } label: {
                Label(task.isDone ? "Todo" : "Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
            }
            .tint(task.isDone ? Theme.blue : Theme.green)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                scheduleToday()
            } label: {
                Label("Today", systemImage: "sun.max.fill")
            }
            .tint(Theme.amber)

            Button {
                scheduleTomorrow()
            } label: {
                Label("Tomorrow", systemImage: "calendar")
            }
            .tint(Theme.blue)

            if !task.scheduledDate.isEmpty {
                Button {
                    clearScheduledDate()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .tint(Theme.dim)
            }
        }
        .contextMenu {
            Button {
                showDetail = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }

            Button {
                toggleCompletion()
            } label: {
                Label(task.isDone ? "Mark Todo" : "Mark Done",
                      systemImage: task.isDone ? "circle" : "checkmark.circle.fill")
            }

            Button {
                scheduleToday()
            } label: {
                Label("Schedule Today", systemImage: "sun.max.fill")
            }

            Button {
                scheduleTomorrow()
            } label: {
                Label("Schedule Tomorrow", systemImage: "calendar")
            }

            if !task.scheduledDate.isEmpty {
                Button {
                    clearScheduledDate()
                } label: {
                    Label("Clear Do Date", systemImage: "xmark.circle")
                }
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
        .alert("Delete Task?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteTask)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the task and its subtasks.")
        }
        .onAppear(perform: handlePendingDeepLink)
        .onChange(of: deepLinkManager.pendingTaskID) { _, _ in
            handlePendingDeepLink()
        }
    }

    private var priorityBadge: some View {
        taskBadge(
            systemImage: "circle.fill",
            text: task.priority.label,
            color: Theme.priorityColor(task.priority)
        )
    }

    private var isOverdue: Bool {
        !task.dueDate.isEmpty && task.dueDate < DateFormatters.todayKey()
    }

    private var estimateLabel: String {
        if task.estimatedMinutes < 60 { return "\(task.estimatedMinutes)m" }
        if task.estimatedMinutes % 60 == 0 { return "\(task.estimatedMinutes / 60)h" }
        return String(format: "%.1fh", Double(task.estimatedMinutes) / 60.0)
    }

    private func taskBadge(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.11))
        .clipShape(Capsule())
    }

    private func toggleCompletion() {
        if task.isDone {
            task.status = .todo
            task.completedAt = nil
        } else {
            task.status = .done
            task.completedAt = Date()
        }
        try? modelContext.save()
    }

    private func scheduleToday() {
        task.scheduledDate = DateFormatters.todayKey()
        try? modelContext.save()
    }

    private func scheduleTomorrow() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        task.scheduledDate = DateFormatters.dateKey(from: tomorrow)
        try? modelContext.save()
    }

    private func clearScheduledDate() {
        task.scheduledDate = ""
        task.scheduledStartMin = -1
        try? modelContext.save()
    }

    private func deleteTask() {
        modelContext.deleteTaskForiOS(task)
    }

    private func handlePendingDeepLink() {
        guard deepLinkManager.pendingTaskID == task.id else { return }
        showDetail = true
        deepLinkManager.clearPendingTask(task.id)
    }
}

struct iOSTaskListRow: View {
    @Bindable var task: AppTask
    var opacity: Double = 1

    var body: some View {
        iOSTaskRow(task: task)
            .opacity(opacity)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct iOSTaskSectionHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .kerning(0.8)
            .textCase(.uppercase)
            .padding(.top, 6)
    }
}

struct iOSTaskViewOptionsBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var sortMode: iOSTaskSortMode
    @Binding var showCompleted: Bool
    var completedCount: Int

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: $sortMode) {
                    ForEach(iOSTaskSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 11 : 9)
                    .padding(.vertical, isRegularWidth ? 7 : 5)
                    .background(Theme.blue.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous)
                            .strokeBorder(Theme.blue.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showCompleted.toggle()
            } label: {
                Text(completedCount > 0 ? "Completed \(completedCount)" : "Completed")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .semibold))
                    .foregroundStyle(showCompleted ? Theme.text : Theme.dim)
                    .padding(.horizontal, isRegularWidth ? 11 : 9)
                    .padding(.vertical, isRegularWidth ? 7 : 5)
                    .background(showCompleted ? Theme.surfaceElevated.opacity(0.72) : Theme.surfaceElevated.opacity(0.36))
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: isRegularWidth ? 9 : 7, style: .continuous)
                            .strokeBorder(Theme.borderSubtle.opacity(showCompleted ? 0.54 : 0.28), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(completedCount == 0)
            .opacity(completedCount == 0 ? 0.45 : 1)
        }
        .tint(Theme.blue)
    }
}

struct iOSTaskCaptureBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let placeholder: String
    @Binding var title: String
    let action: () -> Void

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: isRegularWidth ? 15 : 13))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(action)
                .padding(.horizontal, isRegularWidth ? 13 : 10)
                .frame(minHeight: isRegularWidth ? 44 : 34)
                .background(Theme.surfaceElevated.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous)
                        .stroke(Theme.borderSubtle.opacity(0.7), lineWidth: 1)
                }

            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: isRegularWidth ? 16 : 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isRegularWidth ? 44 : 34, height: isRegularWidth ? 44 : 34)
                    .background(Theme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: isRegularWidth ? 10 : 7, style: .continuous))
            }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
    }
}

let iOSPanelHeaderHeight: CGFloat = 92

struct iOSPanelHeader: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let eyebrow: String
    let title: String
    var count: Int? = nil

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: isRegularWidth ? 10 : 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Text(title)
                    .font(.system(size: isRegularWidth ? 21 : 17, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(size: isRegularWidth ? 13 : 12, weight: .bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, isRegularWidth ? 10 : 8)
                    .padding(.vertical, isRegularWidth ? 6 : 4)
                    .background(Theme.blue.opacity(0.11))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, isRegularWidth ? 20 : 16)
        .padding(.top, isRegularWidth ? 16 : 13)
        .padding(.bottom, isRegularWidth ? 11 : 7)
    }
}

struct iOSEmptyPanel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.dim)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension ModelContext {
    func deleteTaskForiOS(_ task: AppTask) {
        let subtasks = task.subtasks ?? []
        task.subtasks = []
        task.bundle?.tasks = (task.bundle?.tasks ?? []).filter { $0.id != task.id }

        for subtask in subtasks {
            delete(subtask)
        }

        delete(task)
        try? save()
    }
}
#endif
