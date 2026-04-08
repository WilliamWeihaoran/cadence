#if os(macOS)
import SwiftUI
import SwiftData

struct KanbanCard: View {
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
                KanbanCardHeader(
                    title: task.title,
                    titleColor: task.isDone || task.isCancelled ? Theme.dim : Theme.text,
                    isStruckThrough: task.isDone || isPendingCancel,
                    completionButtonIcon: completionButtonIcon,
                    completionButtonColor: completionButtonColor,
                    onCompletionTap: handleCompletionTap
                )

                KanbanMetadataRows(
                    rows: metadataRows,
                    chipContent: { item in AnyView(metaChip(item)) }
                )

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

    private var metadataRows: [[KanbanMetaItem]] {
        KanbanCardStateSupport.metadataRows(
            for: task,
            doDateMetaItem: doDateMetaItem,
            dueDateMetaItem: dueDateMetaItem
        )
    }

    private var doDateMetaItem: KanbanMetaItem {
        KanbanMetaItem(
            id: "do-date",
            icon: "sun.max.fill",
            text: task.scheduledDate.isEmpty ? "Do" : DateFormatters.relativeDate(from: task.scheduledDate),
            tint: task.scheduledDate.isEmpty ? Theme.dim : Theme.amber,
            textColor: task.scheduledDate.isEmpty ? Theme.dim : (isOverdo ? Theme.red : (isDoToday ? Theme.amber : Theme.dim)),
            action: .doDate
        )
    }

    private var dueDateMetaItem: KanbanMetaItem? {
        guard task.shouldShowDueDateField else { return nil }
        return KanbanMetaItem(
            id: "due-date",
            icon: "flag.fill",
            text: task.dueDate.isEmpty ? "Due" : DateFormatters.relativeDate(from: task.dueDate),
            tint: task.dueDate.isEmpty ? Theme.dim : Theme.red,
            textColor: task.dueDate.isEmpty ? Theme.dim : (isOverdue ? Theme.red : Theme.dim),
            action: .dueDate
        )
    }

    @ViewBuilder
    private func metaChip(_ item: KanbanMetaItem) -> some View {
        switch item.action {
        case .none:
            EmptyView()
        case .priority:
            KanbanPriorityMetaButton(
                item: item,
                priority: $task.priority,
                isPresented: $showPriorityPicker,
                onOpen: {
                    showPriorityPicker = true
                    syncInteractiveHoverState()
                }
            )
        case .doDate:
            KanbanDateMetaButton(
                item: item,
                isPresented: $showDoDatePicker,
                onOpen: openDoDatePicker,
                onHoverChanged: { hovering in
                    if hovering {
                        hoveredTaskManager.beginHoveringDate(.doDate, for: task)
                    } else {
                        hoveredTaskManager.endHoveringDate(for: task)
                    }
                }
            ) {
                doDatePickerPopover
            }
        case .dueDate:
            KanbanDateMetaButton(
                item: item,
                isPresented: $showDueDatePicker,
                onOpen: openDueDatePicker,
                onHoverChanged: { hovering in
                    if hovering {
                        hoveredTaskManager.beginHoveringDate(.dueDate, for: task)
                    } else {
                        hoveredTaskManager.endHoveringDate(for: task)
                    }
                }
            ) {
                dueDatePickerPopover
            }
        }
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
        KanbanCardStateSupport.openDatePicker(
            dateKey: task.dueDate,
            setSelection: { dueDatePickerDate = $0 },
            setViewMonth: { dueDateViewMonth = $0 },
            setPresented: { showDueDatePicker = $0 }
        )
        syncInteractiveHoverState()
    }

    private func openDoDatePicker() {
        KanbanCardStateSupport.openDatePicker(
            dateKey: task.scheduledDate,
            setSelection: { doDatePickerDate = $0 },
            setViewMonth: { doDateViewMonth = $0 },
            setPresented: { showDoDatePicker = $0 }
        )
        syncInteractiveHoverState()
    }

    private func syncInteractiveHoverState() {
        KanbanCardStateSupport.syncInteractiveHoverState(
            task: task,
            isPointerOverCard: isPointerOverCard,
            isPresentingInlinePopover: isPresentingInlinePopover,
            setHovered: { isHovered = $0 },
            hoveredTaskManager: hoveredTaskManager,
            hoveredEditableManager: hoveredEditableManager,
            deleteConfirmationManager: deleteConfirmationManager,
            modelContext: modelContext,
            showTaskInspector: $showTaskInspector
        )
    }

    private var isOverdue: Bool {
        KanbanCardComputedSupport.isOverdue(task: task)
    }

    private var isOverdo: Bool {
        KanbanCardComputedSupport.isOverdo(task: task)
    }

    private var isDoToday: Bool {
        KanbanCardComputedSupport.isDoToday(task: task)
    }

    private var priorityBarColor: Color {
        KanbanCardComputedSupport.priorityBarColor(task: task)
    }

    private var isPendingCompletion: Bool {
        taskCompletionAnimationManager.isPending(task)
    }

    private var isPendingCancel: Bool {
        taskCompletionAnimationManager.isPendingCancel(task)
    }

    private var completionButtonIcon: String {
        KanbanCardComputedSupport.completionButtonIcon(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancel: isPendingCancel
        )
    }

    private var completionButtonColor: Color {
        KanbanCardComputedSupport.completionButtonColor(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancel: isPendingCancel
        )
    }

    private func handleCompletionTap() {
        KanbanCardComputedSupport.handleCompletionTap(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancel: isPendingCancel,
            manager: taskCompletionAnimationManager
        )
    }

    private var isPresentingInlinePopover: Bool {
        showPriorityPicker || showDueDatePicker || showDoDatePicker
    }

    private var urgencyBackgroundTint: Color {
        KanbanCardComputedSupport.urgencyBackgroundTint(task: task, isHovered: isHovered)
    }

    @ViewBuilder
    private var cardBackground: some View {
        TimelineView(.animation) { context in
            KanbanCardBackground(
                isHovered: isHovered,
                isDone: task.isDone,
                isPendingCompletion: isPendingCompletion,
                isPendingCancel: isPendingCancel,
                urgencyBackgroundTint: urgencyBackgroundTint,
                completionProgress: taskCompletionAnimationManager.progress(for: task, now: context.date),
                cancelProgress: taskCompletionAnimationManager.cancelProgress(for: task, now: context.date)
            )
        }
    }
}
#endif
