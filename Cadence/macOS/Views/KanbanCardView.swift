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
    /// The day the do and due chips measure lateness against — the board host's observed day
    /// ([[T-5012]]). No default: the chips defaulted to the clock, read in a body whose inputs do
    /// not change at midnight, so a board left open overnight kept yesterday's red and amber.
    let todayKey: String

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(TaskCompletionAnimationManager.self) private var taskCompletionAnimationManager
    /// Read by `completionRing`: under Reduce Motion the ring draws the pending state still, as
    /// iOS's board card does ([[T-8412]]).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(FocusManager.self) private var focusManager
    @State private var showDueDatePicker = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth: Date = Date()
    @State private var showDoDatePicker = false
    @State private var doDatePickerDate: Date = Date()
    @State private var doDateViewMonth: Date = Date()
    @State private var showDurationPicker = false
    @State private var showStartTimePicker = false
    @State private var showContainerPicker = false
    @State private var showTagPicker = false
    @State private var isHovered = false
    @State private var isPointerOverCard = false
    @State private var isAttributeFocused = false
    @State private var showTaskInspector = false
    /// The context menu's after-the-click states, settled by `MacTaskRowMenuOutcomeModifier`
    /// exactly as on `MacTaskRow` ([[T-8062]]).
    @State private var pendingRecurrenceRule: TaskRecurrenceRule?
    @State private var menuFailure: MacTaskRowMenuFailure?

    var body: some View {
        CadenceLedgerCard(
            title: TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle),
            isSettled: isSettled,
            isStruckThrough: task.isDone || isPendingCancel,
            listColor: listColor,
            priority: task.priority,
            isRecurring: task.isRecurring,
            tokens: tokens,
            isHovered: isCardVisuallyFocused,
            ring: { completionRing },
            tokenView: { token in tokenControl(token) },
            subtasks: { subtaskRows },
            settlingOverlay: { settlingOverlay }
        )
        .animation(nil, value: isHovered)
        .onTapGesture {
            openTaskInspectorFromCardTap()
        }
        // **Right-click is the task menu, not a second tap ([[T-8062]]).** It was a
        // `RightClickActionTrigger` overlay running `openTaskInspector`, the click's own path —
        // the defect [[T-1479]] removed from `MacTaskRow` and left on the board card, so the same
        // task offered its actions on the Tasks tab and the inspector on every board. The card now
        // presents the row's menu with the row's outcome handling; click keeps the inspector.
        .contextMenu {
            MacTaskRowContextMenu(
                task: task,
                openDetail: openTaskInspector,
                startFocus: startFocus,
                requestDelete: presentDelete,
                pendingRecurrenceRule: $pendingRecurrenceRule,
                failure: $menuFailure
            )
        }
        .modifier(MacTaskRowMenuOutcomeModifier(
            task: task,
            pendingRecurrenceRule: $pendingRecurrenceRule,
            failure: $menuFailure
        ))
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
            syncInteractiveHoverState()
        }
        // **`.contain`, so the card becomes one element without swallowing its tokens.** T-1740
        // measures where the popovers below land, and they are anchored to `.rect(.bounds)` — the
        // card's own box — so a test needs that box as an element and not merely a point inside it.
        // `.combine` would take the run's tokens with it, and the list token is a popover anchor of
        // its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(CadenceAccessibilityIdentifiers.boardCard(title: task.title))
        // [[T-7092]]: click and right-click were the card's only ways to its detail, and neither is
        // an accessibility action, so VoiceOver could reach the chips and never the task. The
        // action runs `openTaskInspector` unconditionally, since no chip is under a pointer.
        .accessibilityAction(named: CadenceTaskControlAccessibility.openTaskActionName, openTaskInspector)
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
        // **The tag picker is presented here, from the card, and not from the token that opens it**
        // (T-1740). Measured on this Mac at Xcode 27.0: presented from the old 57pt tag strip at the
        // leading end of the card, the picker opened at x in [636, 902] against card content of
        // [578, 830] and covered 194pt of the card. It went to the side its `arrowEdge: .trailing`
        // asked for; the side was never the problem. An anchor that **spans** the content is, as
        // T-1722 established for the inspector, the only shape whose placement does not depend on
        // a choice this repository does not make: when both of an anchor's ends are the content's
        // ends, either end the platform picks is clear of it. A Ledger token is far smaller than
        // that strip was, so the argument only got stronger.
        //
        // **Three chained `.popover` modifiers on one view, and all three present.** That is worth
        // stating, because T-1722 measured the opposite on the inspector's title row: two chained
        // there and only the first ever opened, which is why its two header panels were folded
        // into one `.popover(item:)`. Measured here 2026-09-30, in one run, from one card: the
        // inspector at (846, 33, 362, 523), this picker at (846, 209, 266, 111) and the roller at
        // (846, 121, 286, 286) — three distinct frames, each opened by its own control. Whatever
        // the inspector ran into, it is not a flat rule about chaining, and this card is evidence
        // against reading it as one.
        .popover(isPresented: $showTagPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            KanbanTagPickerPopover(task: task)
        }
        .popover(isPresented: $showDurationPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            // The same roller the inspector uses. A card and an inspector editing one field
            // through two different controls is how the two drifted apart in the first place.
            TaskInspectorEstimateRollerPopover(value: durationBinding, title: "ESTIMATE") {
                showDurationPicker = false
            }
        }
    }

    // MARK: - The Ledger run

    /// The card's metadata run, built by the shared `CadenceLedgerCardSupport` from the shared
    /// `CadenceBoardCardMetadata` descriptor.
    ///
    /// `placeholders: true` is the macOS half of the one difference the two cards keep here, and it
    /// is forced by input rather than chosen: every token on this card is a **picker**, so a field
    /// with no value still needs something under the pointer to click. A touch card reaches the same
    /// fields by tapping the card, so an empty token there would say nothing and do nothing.
    private var tokens: [CadenceLedgerToken] {
        CadenceLedgerCardSupport.tokens(
            startMinute: task.scheduledStartMin,
            estimatedMinutes: task.estimatedMinutes,
            chips: CadenceBoardCardMetadata.chips(
                for: task,
                showsContainer: showsContainerChip,
                dayAlreadyStatedBySurface: dayAlreadyStatedBySurface,
                todayKey: todayKey
            ),
            tagNames: tagTokenNames,
            placeholders: true,
            showsEmptyDueDate: task.shouldShowDueDateField
        )
    }

    /// `CadenceTaskPresentationSupport.rowTagLimit`, the same cap the task rows and the iOS card
    /// use, so no surface decides for itself how much of a task fits.
    private var tagTokenNames: [String] {
        CadenceLedgerTagTokens.names(for: task)
    }

    /// Which tag token carries the card's `Tags` accessibility identifier. See `tokenControl`.
    private var firstTagTokenID: String? {
        tokens.first { $0.kind == .tag }?.id
    }

    /// One token, as a control.
    ///
    /// **Which tokens are pickers is what the pills could edit, not a new inventory.** The do, due
    /// and list chips and the estimate badge were `Button`s opening popovers, and the tag strip
    /// opened the tag editor; all five keep working, now as hover-underlined text. The slot was the
    /// one token a card could not edit, and [[T-8185]] gave it the inspector's own start-time
    /// roller rather than a control of its own, so every token in the run is now a hit target.
    @ViewBuilder
    private func tokenControl(_ token: CadenceLedgerToken) -> some View {
        switch token.kind {
        case .time:
            KanbanLedgerTokenButton(
                token: token,
                isActive: showStartTimePicker,
                accessibilityLabel: CadenceStartTimeFieldRow.label,
                help: "Set start time",
                onHoverChanged: setAttributeFocused,
                action: openStartTimePicker
            )
            // Anchored on the token, as do, due and list are: a fourth chained `.popover` on the
            // card's own box is a configuration nobody has measured presenting (see the note on
            // the tag picker above), and a token anchor is one this card already proves works.
            .popover(isPresented: $showStartTimePicker, arrowEdge: .trailing) {
                KanbanStartTimePickerPopover(task: task, isPresented: $showStartTimePicker)
            }
        case .duration:
            KanbanLedgerTokenButton(
                token: token,
                isActive: showDurationPicker,
                accessibilityLabel: CadenceTaskControlAccessibility.estimate,
                accessibilityIdentifier: CadenceAccessibilityIdentifiers.boardCardControl(
                    title: task.title,
                    field: CadenceTaskControlAccessibility.estimate
                ),
                help: "Set duration",
                onHoverChanged: setAttributeFocused,
                action: openDurationPicker
            )
        case .doDay:
            KanbanLedgerTokenButton(
                token: token,
                isActive: showDoDatePicker,
                accessibilityLabel: CadenceTaskControlAccessibility.doDate,
                help: "Set do date",
                onHoverChanged: { hovering in
                    setAttributeFocused(hovering)
                    if hovering {
                        hoveredTaskManager.beginHoveringDate(.doDate, for: task)
                    } else {
                        hoveredTaskManager.endHoveringDate(for: task)
                    }
                },
                action: openDoDatePicker
            )
            .popover(isPresented: $showDoDatePicker, arrowEdge: .trailing) {
                doDatePickerPopover
            }
        case .dueDay:
            KanbanLedgerTokenButton(
                token: token,
                isActive: showDueDatePicker,
                accessibilityLabel: CadenceTaskControlAccessibility.dueDate,
                help: "Set due date",
                onHoverChanged: { hovering in
                    setAttributeFocused(hovering)
                    if hovering {
                        hoveredTaskManager.beginHoveringDate(.dueDate, for: task)
                    } else {
                        hoveredTaskManager.endHoveringDate(for: task)
                    }
                },
                action: openDueDatePicker
            )
            .popover(isPresented: $showDueDatePicker, arrowEdge: .trailing) {
                dueDatePickerPopover
            }
        case .list:
            KanbanLedgerTokenButton(
                token: token,
                isActive: showContainerPicker,
                accessibilityLabel: CadenceTaskControlAccessibility.list,
                accessibilityIdentifier: CadenceAccessibilityIdentifiers.boardCardControl(
                    title: task.title,
                    field: CadenceTaskControlAccessibility.list
                ),
                help: "Move to another list",
                onHoverChanged: setAttributeFocused,
                action: openContainerPicker
            )
            // The picker's `@Query`s live in the popover *content*: a board can have a hundred
            // cards alive at once, and a query per card would mean a hundred fetches for a picker
            // almost none of them will ever open.
            .popover(isPresented: $showContainerPicker, arrowEdge: .trailing) {
                KanbanContainerPickerPopover(task: task, isPresented: $showContainerPicker)
            }
        case .tag:
            KanbanLedgerTokenButton(
                token: token,
                isActive: showTagPicker,
                accessibilityLabel: "Edit tags",
                // **The FIRST tag token only.** A card states up to `rowTagLimit` tags and each one
                // opens the same editor, so giving them all the identifier would publish the same
                // address two or three times — and an identifier that matches several elements is
                // not an address. The old tag STRIP was one control and carried it once; the run
                // has to say which token stands in for it.
                accessibilityIdentifier: token.id == firstTagTokenID
                    ? CadenceAccessibilityIdentifiers.boardCardControl(title: task.title, field: "Tags")
                    : nil,
                help: "Edit tags",
                onHoverChanged: setAttributeFocused,
                action: openTagPicker
            )
        }
    }

    /// The gutter's completion control. macOS's is a `Button` over a hold-to-settle progress arc,
    /// which is the one thing about this card a fingertip cannot do on a 13pt target.
    @ViewBuilder
    private var completionRing: some View {
        if !reduceMotion && (isPendingCompletion || isPendingCancel) {
            TimelineView(.animation) { context in
                KanbanCompletionButton(
                    icon: completionButtonIcon,
                    color: completionButtonColor,
                    progress: pendingCompletionProgress(now: context.date),
                    accessibilityLabel: completionAccessibilityLabel,
                    action: handleCompletionTap
                )
            }
        } else {
            KanbanCompletionButton(
                icon: completionButtonIcon,
                color: completionButtonColor,
                progress: nil,
                accessibilityLabel: completionAccessibilityLabel,
                action: handleCompletionTap
            )
        }
    }

    /// The press-and-hold settle wash. It exists only where there is a press-and-hold to be
    /// pending about.
    ///
    /// The shared host iOS's board card lays ([[T-8412]]), so it reads the shared decision and
    /// draws nothing under Reduce Motion, where the ring already says "pending" still.
    private var settlingOverlay: some View {
        TaskCompletionPendingSweep(task: task, cornerRadius: CadenceLedgerCardMetrics.cornerRadius)
    }

    private var isSettled: Bool {
        CadenceTaskCompletionState.resolve(task: task).isSettled
    }

    private var listColor: Color {
        Color(hex: task.containerColor)
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
    ///
    /// **The list itself is `MacTaskSubtaskPreviewList`, the macOS task row's own view** ([[T-3221]]),
    /// so the card and the row cannot drift apart. Only the overflow font size (11, the card's
    /// metadata size) and the card's leading inset are the card's own.
    @ViewBuilder
    private var subtaskRows: some View {
        let subtasks = CadenceTaskPresentationSupport.listedSubtasks(for: task)
        if !subtasks.isEmpty {
            MacTaskSubtaskPreviewList(
                subtasks: subtasks,
                hiddenCount: CadenceTaskPresentationSupport.unlistedSubtaskCount(for: task),
                overflowFontSize: 11
            )
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

    private func openStartTimePicker() {
        showStartTimePicker = true
        setAttributeFocused(true)
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
        openTaskInspector()
    }

    /// The one way into this card's detail: the tap (past its chip guard), the context menu's
    /// Edit, and the "Open task" accessibility action ([[T-7092]]).
    private func openTaskInspector() {
        showTaskInspector = true
    }

    /// The context menu's Focus — `MacTaskRow.startFocus`'s path. T-654: `startFocus` commits a
    /// pending bank and can refuse.
    private func startFocus() {
        do {
            try focusManager.startFocus(task: task, in: modelContext)
        } catch {
            taskCompletionAnimationManager.recordSettleFailure()
        }
    }

    /// The context menu's Delete Task — the same refusable overlay as the card's Cmd+Delete
    /// (`KanbanCardStateSupport.syncInteractiveHoverState`), with the same hover teardown.
    private func presentDelete() {
        deleteConfirmationManager.presentTaskDelete(task, in: modelContext) {
            if hoveredTaskManager.hoveredTask?.id == task.id {
                hoveredTaskManager.hoveredTask = nil
            }
            hoveredEditableManager.endHovering(id: KanbanCardStateSupport.editableID(for: task))
        }
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

    private var completionAccessibilityLabel: String {
        KanbanCardComputedSupport.completionGlyph(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancel: isPendingCancel
        ).state.accessibilityActionLabel
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
        showDueDatePicker || showDoDatePicker || showStartTimePicker || showDurationPicker
            || showContainerPicker || showTagPicker
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
}
#endif
