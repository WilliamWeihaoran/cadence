#if os(macOS)
import SwiftUI
import SwiftData

/// The **one** task card used by every board surface: the list/section kanban boards, and the
/// Calendar Board's day columns and pinned rails. Density is fixed and identical everywhere —
/// completion circle, title, estimate, do/due chips, tags, subtasks — so the boards cannot drift
/// apart again.
///
/// The per-board knobs are both suppressions, and both exist because the information is genuinely
/// redundant on some boards rather than because the boards want to look different:
/// `showsContainerChip`, since a section column already sits inside one list and an All Tasks list
/// column *is* a list; and `dayAlreadyStatedBySurface`, since a day column has named its day in its
/// own header. The Calendar Board is cross-list, so it shows the list chip on both its day columns
/// and its rails, and passes its date key on the day columns only — a rail is a bucket, not a day.
struct KanbanCard: View {
    @Bindable var task: AppTask
    var showsContainerChip: Bool = false
    /// The day this card's surface has already stated, if it states one. See
    /// `CadenceBoardCardMetadata.repeatsSurfaceDay`.
    var dayAlreadyStatedBySurface: String? = nil

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

                subtaskRows
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

    /// The unfinished subtasks, capped, with a line saying how many are left over.
    ///
    /// **This card used to list every subtask it had, done ones included, with no cap** — so a task
    /// with twelve of them made its card taller than the column and the rest of the day went below
    /// the fold. That question was already settled for the app's task rows and measured on a phone:
    /// `CadenceTaskPresentationSupport.rowSubtaskLimit`, unfinished only, and *name* what is left
    /// rather than counting it. A `3/5` chip is the spelling that rule rejects — it states a number
    /// of things to do without stating one of them, so the checklist is only readable by opening the
    /// task. The card is the one surface that had never adopted it; there is no third answer here.
    ///
    /// The overflow line is deliberately not a control. Clicking anywhere on this card already
    /// opens the inspector, which is where the rest of the list is, and a second hover layer inside
    /// a card that has one is the pattern this repo keeps having to unpick.
    @ViewBuilder
    private var subtaskRows: some View {
        let subtasks = CadenceTaskPresentationSupport.listedSubtasks(for: task)
        if !subtasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subtasks) { subtask in
                    SubtaskRow(subtask: subtask)
                }

                if let hidden = CadenceTaskPresentationSupport.unlistedSubtaskCount(for: task) {
                    Text("+\(hidden) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.dim)
                        .padding(.vertical, 3)
                }
            }
            .padding(.leading, 10)
            .padding(.top, 2)
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
    ///
    /// **What is in the strip is `CadenceBoardCardMetadata`'s decision, not this file's.** The
    /// arrangement below — two rows, dates then list — stays here, and so does everything that
    /// makes each chip a picker. The iOS card builds its grid from the same three descriptors; it
    /// used to build its own list and had quietly dropped the do date from it.
    private var metadataRows: [[KanbanMetaItem]] {
        var rows: [[KanbanMetaItem]] = []
        let chips = CadenceBoardCardMetadata.chips(
            for: task,
            showsContainer: showsContainerChip,
            dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
        )

        var dateRow: [KanbanMetaItem] = chips
            .filter { $0.kind != .list }
            .map(dateMetaItem)
        // The empty-due affordance, and only macOS has one: this chip *is* the due-date picker, so
        // a card in a list that does not hide empty due dates keeps a `Due` chip with no date on
        // it. An empty chip states nothing, which is why the shared descriptor does not produce it.
        if !chips.contains(where: { $0.kind == .dueDate }), task.shouldShowDueDateField {
            dateRow.append(emptyDueDateMetaItem)
        }
        if !dateRow.isEmpty { rows.append(dateRow) }

        if let listChip = chips.first(where: { $0.kind == .list }) {
            rows.append([listMetaItem(listChip)])
        }

        return rows
    }

    private func dateMetaItem(_ chip: CadenceBoardCardChip) -> KanbanMetaItem {
        // Amber and red are semantic here — they mean "do date" and "due date", not "this task's
        // list". The identity tint never varies with urgency; only the label's colour does.
        let tint = chip.identityColor
        return KanbanMetaItem(
            id: chip.kind == .doDate ? "do-date" : "due-date",
            icon: chip.icon,
            text: chip.text,
            tint: tint,
            textColor: chip.labelColor,
            hoverStyle: .semantic(tint),
            action: chip.kind == .doDate ? .doDate : .dueDate
        )
    }

    private var emptyDueDateMetaItem: KanbanMetaItem {
        KanbanMetaItem(
            id: "due-date",
            icon: CadenceBoardCardMetadata.dueDateIcon,
            text: "Due",
            tint: Theme.dim,
            textColor: Theme.dim,
            hoverStyle: .semantic(Theme.dim),
            action: .dueDate
        )
    }

    private func listMetaItem(_ chip: CadenceBoardCardChip) -> KanbanMetaItem {
        KanbanMetaItem(
            id: "list",
            icon: chip.icon,
            text: chip.text,
            // The container color stays on the icon — that is the list's identity. It must not
            // become the hover color, or the chip hovers in whatever hue this list happens to be,
            // which is the container-color bleed already removed from the row hover.
            tint: chip.identityColor,
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
                    CadenceTaskDateEditing.setDueDate(
                        DateFormatters.dateKey(from: $0),
                        for: task,
                        in: modelContext
                    )
                }
            ),
            viewMonth: $dueDateViewMonth,
            isOpen: $showDueDatePicker,
            showsClear: true,
            onClear: {
                CadenceTaskDateEditing.clearDueDate(task, in: modelContext)
            }
        )
    }

    private var doDatePickerPopover: some View {
        CadenceQuickDatePopover(
            selection: Binding(
                get: { doDatePickerDate },
                set: {
                    doDatePickerDate = $0
                    CadenceTaskDateEditing.setScheduledDate(
                        DateFormatters.dateKey(from: $0),
                        for: task,
                        in: modelContext
                    )
                }
            ),
            viewMonth: $doDateViewMonth,
            isOpen: $showDoDatePicker,
            showsClear: true,
            onClear: {
                CadenceTaskDateEditing.clearScheduledDate(task, in: modelContext)
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

    // `isOverdue` / `isOverdo` / `isDoToday` are gone from this card. They were the three-way
    // urgency choice behind the do and due chips' label colour, and that choice is now
    // `CadenceBoardCardChip.Emphasis`, made once for both platforms. `KanbanCardComputedSupport`
    // still declares them for its other callers.

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
