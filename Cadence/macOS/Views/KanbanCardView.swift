#if os(macOS)
import SwiftUI
import SwiftData

struct KanbanCard: View {
    @Bindable var task: AppTask
    var presentation: KanbanCardPresentation = .listBoard

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager
    @State private var showDueDatePicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth: Date = Date()
    @State private var showDoDatePicker = false
    @State private var doDatePickerDate: Date = Date()
    @State private var doDateViewMonth: Date = Date()
    @State private var showDurationPicker = false
    @State private var isHovered = false
    @State private var isPointerOverCard = false
    @State private var isAttributeFocused = false
    @State private var showTaskInspector = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: hasScheduleTopRow ? 7 : 10) {
                if hasScheduleTopRow {
                    KanbanCardScheduleTopRow(
                        startTime: scheduleStartLabel,
                        duration: scheduleDurationLabel,
                        onDurationTap: openDurationPicker,
                        isDurationFocused: showDurationPicker,
                        onDurationHoverChanged: setAttributeFocused
                    )
                }

                cardHeader

                CompactTagStrip(tags: task.sortedTags, limit: 3)

                if !metadataRows.isEmpty {
                    KanbanMetadataRows(
                        rows: metadataRows,
                        chipContent: { item in AnyView(metaChip(item)) }
                    )
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
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous)
                .strokeBorder(
                    isCardVisuallyFocused
                        ? TaskHoverVisuals.borderColor(for: task, isHovered: isCardVisuallyFocused, opacity: 0.56)
                        : Theme.borderSubtle,
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: kanbanCardCornerRadius, style: .continuous))
        .animation(nil, value: isHovered)
        .onTapGesture {
            openTaskInspectorFromCardTap()
        }
        .overlay {
            RightClickActionTrigger {
                showTaskInspector = true
            }
        }
        .onHover { hovering in
            isPointerOverCard = hovering
            syncInteractiveHoverState()
        }
        .onChange(of: isPresentingInlinePopover) { _, isPresented in
            if !isPresented {
                setAttributeFocused(false)
            }
            if isPresented {
                syncInteractiveHoverState()
            } else {
                syncInteractiveHoverState()
            }
        }
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
        .popover(isPresented: $showDurationPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            EstimatePickerPopoverContent(value: durationBinding) {
                showDurationPicker = false
            }
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { task.estimatedMinutes },
            set: { newValue in
                task.estimatedMinutes = max(0, min(newValue, 1440))
                try? modelContext.save()
            }
        )
    }

    private var metadataRows: [[KanbanMetaItem]] {
        switch presentation {
        case .listBoard:
            listBoardMetadataRows
        case .calendarBoard:
            calendarBoardMetadataRows
        }
    }

    private var doDateMetaItem: KanbanMetaItem? {
        guard !task.scheduledDate.isEmpty else { return nil }
        return KanbanMetaItem(
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

    private var listBoardMetadataRows: [[KanbanMetaItem]] {
        var row: [KanbanMetaItem] = []
        if let doDateMetaItem {
            row.append(doDateMetaItem)
        }
        if let dueDateMetaItem {
            row.append(dueDateMetaItem)
        }
        return row.isEmpty ? [] : [row]
    }

    private var calendarBoardMetadataRows: [[KanbanMetaItem]] {
        var primary: [KanbanMetaItem] = []

        if let dueDateItem = concreteDueDateMetaItem {
            primary.append(dueDateItem)
        }

        if primary.count >= 2 {
            return [primary, [contextMetaItem]]
        }
        primary.append(contextMetaItem)
        return [primary]
    }

    private var contextMetaItem: KanbanMetaItem {
        KanbanMetaItem(
            id: "list",
            icon: task.project?.icon ?? task.area?.icon ?? "tray.fill",
            text: task.containerName.isEmpty ? "Inbox" : task.containerName,
            tint: Color(hex: task.containerColor),
            textColor: Theme.dim,
            action: .none
        )
    }

    private var concreteDueDateMetaItem: KanbanMetaItem? {
        guard !task.dueDate.isEmpty else { return nil }
        return KanbanMetaItem(
            id: "due-date",
            icon: "flag.fill",
            text: DateFormatters.relativeDate(from: task.dueDate),
            tint: Theme.red,
            textColor: isOverdue ? Theme.red : Theme.dim,
            action: .dueDate
        )
    }

    private var hasScheduleTopRow: Bool {
        scheduleStartLabel != nil
    }

    private var headerDurationBadge: String? {
        scheduleStartLabel == nil ? scheduleDurationLabel : nil
    }

    private var scheduleStartLabel: String? {
        guard task.scheduledStartMin >= 0 else { return nil }
        return TimeFormatters.timeString(from: task.scheduledStartMin).lowercased()
    }

    private var scheduleDurationLabel: String? {
        guard task.estimatedMinutes > 0 else { return nil }
        return KanbanCardStateSupport.compactDurationLabel(task.estimatedMinutes)
    }

    @ViewBuilder
    private func metaChip(_ item: KanbanMetaItem) -> some View {
        switch item.action {
        case .none:
            KanbanMetaChip(item: item, onHoverChanged: setAttributeFocused)
        case .doDate:
            KanbanDateMetaButton(
                item: item,
                isPresented: $showDoDatePicker,
                onOpen: openDoDatePicker,
                onHoverChanged: { hovering in
                    setAttributeFocused(hovering)
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
                    setAttributeFocused(hovering)
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
        setAttributeFocused(true)
        KanbanCardStateSupport.openDatePicker(
            dateKey: task.dueDate,
            setSelection: { dueDatePickerDate = $0 },
            setViewMonth: { dueDateViewMonth = $0 },
            setPresented: { showDueDatePicker = $0 }
        )
        syncInteractiveHoverState()
    }

    private func openDoDatePicker() {
        setAttributeFocused(true)
        KanbanCardStateSupport.openDatePicker(
            dateKey: task.scheduledDate,
            setSelection: { doDatePickerDate = $0 },
            setViewMonth: { doDateViewMonth = $0 },
            setPresented: { showDoDatePicker = $0 }
        )
        syncInteractiveHoverState()
    }

    private func openDurationPicker() {
        showDurationPicker = true
        setAttributeFocused(true)
        syncInteractiveHoverState()
    }

    private func openTaskInspectorFromCardTap() {
        guard !isAttributeFocused && !isPresentingInlinePopover else { return }
        showTaskInspector = true
    }

    private func setAttributeFocused(_ focused: Bool) {
        isAttributeFocused = focused
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

    private func pendingCompletionProgress(now: Date) -> Double? {
        if isPendingCompletion {
            return taskCompletionAnimationManager.progress(for: task, now: now)
        }
        if isPendingCancel {
            return taskCompletionAnimationManager.cancelProgress(for: task, now: now)
        }
        return nil
    }

    private var isPresentingInlinePopover: Bool {
        showDueDatePicker || showDoDatePicker || showDurationPicker
    }

    private var isCardVisuallyFocused: Bool {
        isHovered && !isAttributeFocused && !isPresentingInlinePopover
    }

    private var urgencyBackgroundTint: Color {
        KanbanCardComputedSupport.urgencyBackgroundTint(task: task, isHovered: isCardVisuallyFocused)
    }

    @ViewBuilder
    private var cardHeader: some View {
        if isPendingCompletion || isPendingCancel {
            TimelineView(.animation) { context in
                KanbanCardHeader(
                    title: task.title,
                    titleColor: task.isDone || task.isCancelled ? Theme.dim : Theme.text,
                    isStruckThrough: task.isDone || isPendingCancel,
                    durationBadge: headerDurationBadge,
                    onDurationTap: openDurationPicker,
                    isDurationFocused: showDurationPicker,
                    onDurationHoverChanged: setAttributeFocused,
                    completionButtonIcon: completionButtonIcon,
                    completionButtonColor: completionButtonColor,
                    completionProgress: pendingCompletionProgress(now: context.date),
                    onCompletionTap: handleCompletionTap
                )
            }
        } else {
            KanbanCardHeader(
                title: task.title,
                titleColor: task.isDone || task.isCancelled ? Theme.dim : Theme.text,
                isStruckThrough: task.isDone || isPendingCancel,
                durationBadge: headerDurationBadge,
                onDurationTap: openDurationPicker,
                isDurationFocused: showDurationPicker,
                onDurationHoverChanged: setAttributeFocused,
                completionButtonIcon: completionButtonIcon,
                completionButtonColor: completionButtonColor,
                completionProgress: nil,
                onCompletionTap: handleCompletionTap
            )
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isPendingCompletion || isPendingCancel {
            TimelineView(.animation) { context in
                KanbanCardBackground(
                    isHovered: isCardVisuallyFocused,
                    isDone: task.isDone,
                    isPendingCompletion: isPendingCompletion,
                    isPendingCancel: isPendingCancel,
                    urgencyBackgroundTint: urgencyBackgroundTint,
                    completionProgress: taskCompletionAnimationManager.progress(for: task, now: context.date),
                    cancelProgress: taskCompletionAnimationManager.cancelProgress(for: task, now: context.date)
                )
            }
        } else {
            KanbanCardBackground(
                isHovered: isCardVisuallyFocused,
                isDone: task.isDone,
                isPendingCompletion: false,
                isPendingCancel: false,
                urgencyBackgroundTint: urgencyBackgroundTint,
                completionProgress: 0,
                cancelProgress: 0
            )
        }
    }
}
#endif
