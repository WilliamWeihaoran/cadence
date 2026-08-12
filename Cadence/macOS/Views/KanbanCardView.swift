#if os(macOS)
import SwiftUI
import SwiftData

/// The **one** task card used by every board surface: the list/section kanban boards, and the
/// Calendar Board's day columns and pinned rails. Density is fixed and identical everywhere —
/// completion circle, title, estimate, do/due chips, tags, subtasks — so the boards cannot drift
/// apart again.
///
/// The only per-board knob is `showsContainerChip`, and it exists because the information is
/// genuinely redundant on some boards: a section column already sits inside one list, and an
/// All Tasks list column *is* a list, so repeating the name on every card there is noise.
/// The Calendar Board is cross-list, so it shows it on both its day columns and its rails.
struct KanbanCard: View {
    @Bindable var task: AppTask
    var showsContainerChip: Bool = false

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
    @State private var showContainerPicker = false
    @State private var showTagPicker = false
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
                        duration: estimateLabel,
                        onDurationTap: openDurationPicker,
                        isDurationFocused: showDurationPicker,
                        onDurationHoverChanged: setAttributeFocused
                    )
                }

                cardHeader

                KanbanCardTagStrip(
                    task: task,
                    isPresented: $showTagPicker,
                    onOpen: openTagPicker,
                    onHoverChanged: setAttributeFocused
                )

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
                    Theme.borderSubtle,
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
        .onDisappear {
            // A card can vanish out from under a still-parked pointer — dragged to another
            // column, completed with Cmd+Return and filtered out, or deleted — in which case
            // `.onHover(false)` never fires. Without this teardown the managers keep pointing
            // at the gone card and hold its `onDelete` closure, so the next Cmd+Delete /
            // Cmd+Return acts on the wrong task.
            //
            // Safe against a fast pointer move to the next card: the replacement registers
            // first, and both managers' `endHovering` are identity-guarded, so this call
            // no-ops once the hover has moved on.
            guard isHovered else { return }
            isPointerOverCard = false
            isHovered = false
            KanbanCardStateSupport.endHoverRegistration(
                task: task,
                hoveredTaskManager: hoveredTaskManager,
                hoveredEditableManager: hoveredEditableManager
            )
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
            // The same roller the inspector uses. A card and an inspector editing one field
            // through two different controls is how the two drifted apart in the first place.
            TaskInspectorEstimateRollerPopover(value: durationBinding, title: "ESTIMATE") {
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

    /// One layout for every board. Row 1 is the date pair, row 2 the list chip when the board
    /// isn't already scoped to a single list.
    private var metadataRows: [[KanbanMetaItem]] {
        var rows: [[KanbanMetaItem]] = []

        var dateRow: [KanbanMetaItem] = []
        if let doDateMetaItem { dateRow.append(doDateMetaItem) }
        if let dueDateMetaItem { dateRow.append(dueDateMetaItem) }
        if !dateRow.isEmpty { rows.append(dateRow) }

        if showsContainerChip { rows.append([contextMetaItem]) }

        return rows
    }

    private var doDateMetaItem: KanbanMetaItem? {
        guard !task.scheduledDate.isEmpty else { return nil }
        // Amber is semantic here — it means "do date", not "this task's list".
        let tint = task.scheduledDate.isEmpty ? Theme.dim : Theme.amber
        return KanbanMetaItem(
            id: "do-date",
            icon: "sun.max.fill",
            text: task.scheduledDate.isEmpty ? "Do" : DateFormatters.relativeDate(from: task.scheduledDate),
            tint: tint,
            textColor: task.scheduledDate.isEmpty ? Theme.dim : (isOverdo ? Theme.red : (isDoToday ? Theme.amber : Theme.dim)),
            hoverStyle: .semantic(tint),
            action: .doDate
        )
    }

    private var dueDateMetaItem: KanbanMetaItem? {
        guard task.shouldShowDueDateField else { return nil }
        // Red is semantic here — it means "due date".
        let tint = task.dueDate.isEmpty ? Theme.dim : Theme.red
        return KanbanMetaItem(
            id: "due-date",
            icon: "flag.fill",
            text: task.dueDate.isEmpty ? "Due" : DateFormatters.relativeDate(from: task.dueDate),
            tint: tint,
            textColor: task.dueDate.isEmpty ? Theme.dim : (isOverdue ? Theme.red : Theme.dim),
            hoverStyle: .semantic(tint),
            action: .dueDate
        )
    }

    private var contextMetaItem: KanbanMetaItem {
        KanbanMetaItem(
            id: "list",
            icon: task.project?.icon ?? task.area?.icon ?? "tray.fill",
            text: task.containerName.isEmpty ? "Inbox" : task.containerName,
            // The container color stays on the icon — that is the list's identity. It must not
            // become the hover color, or the chip hovers in whatever hue this list happens to be,
            // which is the container-color bleed already removed from the row hover.
            tint: Color(hex: task.containerColor),
            textColor: Theme.dim,
            hoverStyle: .neutral,
            action: .container
        )
    }

    private var hasScheduleTopRow: Bool {
        scheduleStartLabel != nil
    }

    private var headerDurationBadge: String? {
        scheduleStartLabel == nil ? estimateLabel : nil
    }

    private var scheduleStartLabel: String? {
        guard task.scheduledStartMin >= 0 else { return nil }
        return TimeFormatters.timeString(from: task.scheduledStartMin).lowercased()
    }

    /// Always rendered, even with no estimate set — the badge *is* the estimate picker, so
    /// hiding it when the value is empty would leave the field unreachable from the card.
    /// Uses the app-wide duration vocabulary. This used to format `"H:MM"` — 90 minutes as
    /// `"1:30"` — which is a sixth format for a field every other surface renders as `1h 30m`,
    /// and worse, `KanbanCardScheduleTopRow` draws this badge immediately beside a real clock
    /// time like `9am`. A duration written `1:30` next to `9am` reads as a time of day. The badge
    /// has no width constraint (a `Spacer(minLength: 8)` pushes it to the trailing edge), so the
    /// longer string fits.
    private var estimateLabel: String {
        CadenceTaskPresentationSupport.estimateLabel(minutes: task.estimatedMinutes, emptyPlaceholder: "—")
    }

    @ViewBuilder
    private func metaChip(_ item: KanbanMetaItem) -> some View {
        switch item.action {
        case .container:
            KanbanContainerMetaButton(
                item: item,
                task: task,
                isPresented: $showContainerPicker,
                onOpen: openContainerPicker,
                onHoverChanged: setAttributeFocused
            )
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

    private func openContainerPicker() {
        showContainerPicker = true
        setAttributeFocused(true)
        syncInteractiveHoverState()
    }

    private func openTagPicker() {
        showTagPicker = true
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
        showDueDatePicker || showDoDatePicker || showDurationPicker || showContainerPicker || showTagPicker
    }

    /// Merely hovering a chip no longer cancels the card's own hover — the two coexist, so the
    /// card keeps its neutral gray raise while the chip adds its own. (Chips cover most of the
    /// card, so gating on `isAttributeFocused` here meant the common case was "card hover off,
    /// colored chip hover on", which is why hover still read as colored.)
    ///
    /// An *open* inline popover still suppresses the card hover: that is deliberate, since the
    /// pointer has left the card for the picker.
    private var isCardVisuallyFocused: Bool {
        isHovered && !isPresentingInlinePopover
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
                completionProgress: 0,
                cancelProgress: 0
            )
        }
    }
}
#endif
