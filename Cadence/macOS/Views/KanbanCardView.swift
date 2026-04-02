#if os(macOS)
import SwiftUI
import SwiftData

struct KanbanCard: View {
    private enum MetaAction: Hashable {
        case none
        case priority
        case doDate
        case dueDate
    }

    private struct MetaItem: Identifiable {
        let id: String
        let icon: String
        let text: String
        let tint: Color
        let textColor: Color
        let action: MetaAction
    }

    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager
    @State private var showPriorityPicker = false
    @State private var showDueDatePicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth: Date = Date()
    @State private var showDoDatePicker = false
    @State private var doDatePickerDate: Date = Date()
    @State private var doDateViewMonth: Date = Date()
    @State private var isHovered = false
    @State private var isPointerOverCard = false
    @State private var showTaskInspector = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(priorityBarColor)
                .frame(width: 3.5)
                .padding(.leading, 10)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        taskCompletionAnimationManager.toggleCompletion(for: task)
                    } label: {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : (isPendingCompletion ? "circle.inset.filled" : "circle"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(task.isDone || isPendingCompletion ? Theme.green : Theme.dim)
                    }
                    .buttonStyle(.cadencePlain)

                    Text(task.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(task.isDone || task.isCancelled ? Theme.dim : Theme.text)
                        .strikethrough(task.isDone, color: Theme.dim)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(metadataRows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 6) {
                            ForEach(metadataRows[rowIndex]) { item in
                                metaChip(item)
                            }
                        }
                    }
                }

                let sortedSubtasks = (task.subtasks ?? []).sorted { $0.order < $1.order }
                if !sortedSubtasks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(sortedSubtasks) { subtask in
                            SubtaskRow(subtask: subtask)
                        }
                    }
                    .padding(.leading, 10)
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
        }
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Theme.blue.opacity(0.56) : .white.opacity(0.06), lineWidth: isHovered ? 1.35 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(nil, value: isHovered)
        .onTapGesture {
            showTaskInspector = true
        }
        .onHover { hovering in
            isPointerOverCard = hovering
            syncInteractiveHoverState()
        }
        .onChange(of: isPresentingInlinePopover) { _, isPresented in
            if isPresented {
                syncInteractiveHoverState()
            } else {
                syncInteractiveHoverState()
            }
        }
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
    }

    private var metadataRows: [[MetaItem]] {
        if let dueDateMetaItem {
            return [[doDateMetaItem, dueDateMetaItem]]
        }
        return [[doDateMetaItem]]
    }

    private var doDateMetaItem: MetaItem {
        MetaItem(
            id: "do-date",
            icon: "sun.max.fill",
            text: task.scheduledDate.isEmpty ? "Do" : DateFormatters.relativeDate(from: task.scheduledDate),
            tint: task.scheduledDate.isEmpty ? Theme.dim : Theme.amber,
            textColor: task.scheduledDate.isEmpty ? Theme.dim : (isOverdo ? Theme.red : (isDoToday ? Theme.amber : Theme.dim)),
            action: .doDate
        )
    }

    private var dueDateMetaItem: MetaItem? {
        guard task.shouldShowDueDateField else { return nil }
        return MetaItem(
            id: "due-date",
            icon: "flag.fill",
            text: task.dueDate.isEmpty ? "Due" : DateFormatters.relativeDate(from: task.dueDate),
            tint: task.dueDate.isEmpty ? Theme.dim : Theme.red,
            textColor: task.dueDate.isEmpty ? Theme.dim : (isOverdue ? Theme.red : Theme.dim),
            action: .dueDate
        )
    }

    @ViewBuilder
    private func metaChip(_ item: MetaItem) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 10)
            Text(item.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 6))

        switch item.action {
        case .none:
            EmptyView()
        case .priority:
            Button {
                showPriorityPicker = true
                syncInteractiveHoverState()
            } label: {
                label
            }
            .buttonStyle(.cadencePlain)
            .popover(isPresented: $showPriorityPicker) { priorityPickerPopover }
        case .doDate:
            Button {
                openDoDatePicker()
            } label: {
                label
            }
            .buttonStyle(.cadencePlain)
            .onHover { hovering in
                if hovering {
                    hoveredTaskManager.beginHoveringDate(.doDate, for: task)
                } else {
                    hoveredTaskManager.endHoveringDate(for: task)
                }
            }
            .popover(isPresented: $showDoDatePicker) { doDatePickerPopover }
        case .dueDate:
            Button {
                openDueDatePicker()
            } label: {
                label
            }
            .buttonStyle(.cadencePlain)
            .onHover { hovering in
                if hovering {
                    hoveredTaskManager.beginHoveringDate(.dueDate, for: task)
                } else {
                    hoveredTaskManager.endHoveringDate(for: task)
                }
            }
            .popover(isPresented: $showDueDatePicker) { dueDatePickerPopover }
        }
    }

    private var priorityPickerPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TaskPriority.allCases, id: \.self) { p in
                Button {
                    task.priority = p
                    showPriorityPicker = false
                } label: {
                    HStack(spacing: 8) {
                        if p == .none {
                            Text("—").font(.system(size: 13)).foregroundStyle(Theme.dim).frame(width: 7)
                        } else {
                            Circle().fill(Theme.priorityColor(p)).frame(width: 7, height: 7)
                        }
                        Text(p.label).font(.system(size: 13)).foregroundStyle(Theme.text)
                        Spacer()
                        if task.priority == p {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.blue)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.cadencePlain)
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 150)
        .background(Theme.surfaceElevated)
    }

    private var dueDatePickerPopover: some View {
        CadenceQuickDatePopover(
            selection: Binding(
                get: { dueDatePickerDate },
                set: {
                    dueDatePickerDate = $0
                    task.dueDate = DateFormatters.dateKey(from: $0)
                }
            ),
            viewMonth: $dueDateViewMonth,
            isOpen: $showDueDatePicker,
            showsClear: true,
            onClear: {
                task.dueDate = ""
            }
        )
    }

    private var doDatePickerPopover: some View {
        CadenceQuickDatePopover(
            selection: Binding(
                get: { doDatePickerDate },
                set: {
                    doDatePickerDate = $0
                    task.scheduledDate = DateFormatters.dateKey(from: $0)
                }
            ),
            viewMonth: $doDateViewMonth,
            isOpen: $showDoDatePicker,
            showsClear: true,
            onClear: {
                task.scheduledDate = ""
            }
        )
    }

    private func openDueDatePicker() {
        let resolved = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
        dueDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        dueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDueDatePicker = true
        syncInteractiveHoverState()
    }

    private func openDoDatePicker() {
        let resolved = task.scheduledDate.isEmpty ? Date() : (DateFormatters.date(from: task.scheduledDate) ?? Date())
        doDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        doDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDoDatePicker = true
        syncInteractiveHoverState()
    }

    private func syncInteractiveHoverState() {
        let isActive = isPointerOverCard || isPresentingInlinePopover
        isHovered = isActive
        if isActive {
            hoveredTaskManager.beginHovering(task, source: .kanban)
            hoveredEditableManager.beginHovering(id: "kanban-task-\(task.id.uuidString)") {
                showTaskInspector = true
            } onDelete: {
                deleteConfirmationManager.present(
                    title: "Delete Task?",
                    message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
                ) {
                    if hoveredTaskManager.hoveredTask?.id == task.id {
                        hoveredTaskManager.hoveredTask = nil
                    }
                    modelContext.delete(task)
                }
            }
        } else {
            hoveredTaskManager.endHovering(task)
            hoveredEditableManager.endHovering(id: "kanban-task-\(task.id.uuidString)")
        }
    }

    private var isOverdue: Bool {
        guard !task.dueDate.isEmpty, !task.isDone else { return false }
        return task.dueDate < DateFormatters.todayKey()
    }

    private var isOverdo: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return (DateFormatters.dayOffset(from: task.scheduledDate) ?? 0) < 0
    }

    private var isDoToday: Bool {
        guard !task.scheduledDate.isEmpty, !task.isDone else { return false }
        return task.scheduledDate == DateFormatters.todayKey()
    }

    private var priorityBarColor: Color {
        task.isDone ? Theme.dim.opacity(0.4) : Theme.priorityColor(task.priority)
    }

    private var isPendingCompletion: Bool {
        taskCompletionAnimationManager.isPending(task)
    }

    private var isPresentingInlinePopover: Bool {
        showPriorityPicker || showDueDatePicker || showDoDatePicker
    }

    private var urgencyBackgroundTint: Color {
        guard !task.isDone else { return isHovered ? Theme.blue.opacity(0.075) : .clear }
        if isOverdue {
            return Theme.red.opacity(isHovered ? 0.22 : 0.16)
        }
        if isOverdo {
            return Theme.amber.opacity(isHovered ? 0.26 : 0.2)
        }
        return isHovered ? Theme.blue.opacity(0.075) : .clear
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isHovered ? Theme.surfaceElevated.opacity(1.0) : Theme.surfaceElevated)
            .overlay {
                if urgencyBackgroundTint != .clear {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(urgencyBackgroundTint)
                }
            }
            .overlay {
                if isPendingCompletion {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.green.opacity(0.24))
                                .frame(
                                    width: proxy.size.width * taskCompletionAnimationManager.progress(for: task, now: context.date),
                                    alignment: .leading
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .overlay {
                if task.isDone {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.surface.opacity(0.18))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.04))
            }
    }
}
#endif
