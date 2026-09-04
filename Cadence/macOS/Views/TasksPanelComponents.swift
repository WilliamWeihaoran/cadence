#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

struct MacTaskRow: View {
    @Bindable var task: AppTask
    var style: MacTaskRowStyle = .standard
    /// Whether this row names the list its task is in — the surface's answer, not the row's.
    ///
    /// Asked of `CadenceTaskSurfaceOptions.showsContainerChip(on:)` by whichever surface is
    /// hosting the row, exactly as `iOSTaskRow.showsContainer` is. A section whose *header*
    /// already names the list (All Tasks grouped by list, and Today's by-list sections) passes
    /// `false` on top of that: the surface mixes lists, this section does not.
    var showsContainer: Bool = true
    var contexts: [Context] = []
    var areas: [Area] = []
    var projects: [Project] = []
    @Environment(\.modelContext) private var modelContext
    @Environment(CadenceDeepLinkManager.self) private var deepLinkManager
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self)    private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(FocusManager.self)          private var focusManager

    @State private var showDueDatePicker  = false
    @State private var dueDatePickerDate: Date = Date()
    @State private var dueDateViewMonth:  Date = Date()
    @State private var showDoDatePicker   = false
    @State private var doDatePickerDate: Date = Date()
    @State private var doDateViewMonth:   Date = Date()
    @State private var isHovered          = false
    @State private var showTaskInspector  = false
    @State private var isDoDateHovered    = false
    @State private var isDueDateHovered   = false

    /// **The row's figures, from the type five iOS files already read.** This row hardcoded its own
    /// 14 / 8 / 15 / 11 / 6 while `CadenceTaskRowMetrics` sat in `Shared/` with no macOS reader at
    /// all — which is how the two primary rows were free to drift a padding at a time. `.desktop`
    /// is a third tier rather than `.regular` relabelled, and the type's doc comment carries both
    /// the figures macOS keeps to itself and the ones it deliberately does not read.
    private var metrics: CadenceTaskRowMetrics { .desktop }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            TaskCompletionButton(task: task)
                .padding(.leading, metrics.horizontalPadding)
                .padding(.trailing, metrics.contentSpacing)

            if datePlan.drawsDoDateChip {
                doDatePill
                    .padding(.trailing, metrics.contentSpacing)
            }

            Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                .font(.system(size: metrics.titleFontSize))
                .foregroundStyle(task.isDone || task.isCancelled ? Theme.dim : Theme.text)
                .strikethrough(task.isDone || task.isCancelled, color: Theme.dim)
                .lineLimit(1)

            // `CadenceTaskPresentationSupport.rowTagLimit`, not a local 2. iOS showed three tags
            // on the same row of the same task; `ViewThatFits` here already drops to one chip or
            // to a bare `+N` when the column is genuinely narrow, so a fixed 2 was hiding a tag
            // the row had room for.
            CompactTagStrip(tags: task.sortedTags, limit: CadenceTaskPresentationSupport.rowTagLimit)
                .padding(.leading, task.sortedTags.isEmpty ? 0 : metrics.badgeSpacing)

            if task.isCancelled {
                // The fifth chip on this row, drawn like the other four. It set its own `10` and
                // `6/3` while the do-date pill, the due-date pill, the bundle badge and the
                // estimate chip beside it all read `metrics.secondaryFontSize` at
                // `CadenceTaskChipPadding.desktop*` — which is the drift `CadenceTaskRowMetrics.desktop`
                // exists to stop (T-597). The plate was four inline `4/2` pairs until T-617; the bundle
                // badge named there is not a fifth, because it draws no background and so has no plate.
                Text("Cancelled")
                    .font(.system(size: metrics.secondaryFontSize, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, CadenceTaskChipPadding.desktopHorizontal)
                    .padding(.vertical, CadenceTaskChipPadding.desktopVertical)
                    .background(Theme.dim.opacity(0.14))
                    .clipShape(Capsule())
                    .padding(.leading, metrics.badgeSpacing)
            }

            Spacer(minLength: 4)

            if task.estimatedMinutes > 0 {
                MacTaskRowEstimateChip(task: task)
            }

            focusButtonSlot

            if datePlan.drawsDueDateChip {
                dueDateBadgeList
            }

            if let bundle = task.bundle {
                taskBundleBadge(bundle)
            }

            if showsListContextChip {
                ContainerPickerBadge(
                    selection: taskContainerBinding,
                    contexts: contexts,
                    areas: areas,
                    projects: projects,
                    compact: true,
                    flat: true
                )
                .padding(.leading, metrics.badgeSpacing)
                .padding(.trailing, metrics.badgeSpacing)
            }
        }
        .padding(.vertical, metrics.verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { showTaskInspector = true }
        .overlay {
            RightClickActionTrigger {
                showTaskInspector = true
            }
        }
        .background(TaskRowBackground(task: task, isHovered: isHovered, hoverFill: hoverBackgroundFill))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(
                    TaskHoverVisuals.borderColor(isHovered: isHovered),
                    lineWidth: 1
                )
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderSubtle.opacity(0.22)).frame(height: 0.5)
        }
        .animation(nil, value: isHovered)
        .animation(nil, value: isDoDateHovered)
        .animation(nil, value: isDueDateHovered)
        .onHover { hovering in
            guard isHovered != hovering else { return }
            isHovered = hovering
            if hovering {
                beginHoverRegistration()
            } else {
                endHoverRegistration()
            }
        }
        .onDisappear {
            // A row can vanish out from under a still-parked pointer — completed with
            // Cmd+Return and filtered out of the section, deleted, or regrouped by a date/list
            // change — in which case `.onHover(false)` never fires. Without this teardown the
            // managers keep pointing at the gone row and hold its `onDelete` closure, so the
            // next Cmd+Delete / Cmd+Return acts on the wrong task.
            //
            // Safe against a fast pointer move from this row to the next: the replacement
            // registers first, and both managers' `endHovering` are identity-guarded, so this
            // call no-ops once the hover has moved on.
            guard isHovered else { return }
            isHovered = false
            endHoverRegistration()
        }
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
        .opacity(task.isDone || task.isCancelled ? 0.5 : 1.0)
        .onAppear(perform: handlePendingDeepLink)
        .onChange(of: deepLinkManager.pendingTaskID) { _, _ in
            handlePendingDeepLink()
        }
    }

    // MARK: - Hover registration

    /// Namespaced per surface so a task visible on two surfaces at once can't unregister
    /// the other's entry.
    private var editableID: String { "task-row-\(task.id.uuidString)" }

    /// The hovered-task shortcuts (Cmd+Delete / Cmd+Return / Cmd+E / Cmd+T / Cmd+D / Cmd+P /
    /// Cmd+S / Cmd+/) are all driven off these two managers.
    private func beginHoverRegistration() {
        hoveredTaskManager.beginHovering(task, source: .list)
        hoveredEditableManager.beginHovering(id: editableID) {
            showTaskInspector = true
        } onDelete: {
            deleteConfirmationManager.presentTaskDelete(task, in: modelContext) {
                if hoveredTaskManager.hoveredTask?.id == task.id {
                    hoveredTaskManager.hoveredTask = nil
                }
                hoveredEditableManager.endHovering(id: editableID)
            }
        }
    }

    private func endHoverRegistration() {
        hoveredTaskManager.endHovering(task)
        hoveredEditableManager.endHovering(id: editableID)
    }

    private var focusButtonSlot: some View {
        Group {
            // The shared predicate, not a second hand-written `!isDone && !isCancelled`. This row
            // was the *only* surface in the app asking the question, and the three iOS entry points
            // added since did not ask it at all (T-276).
            if CadenceFocusSupport.canFocus(task) {
                Button {
                    // T-654: `startFocus` commits a pending bank and can refuse.
                    do {
                        try focusManager.startFocus(task: task, in: modelContext)
                    } catch {
                        TaskCompletionAnimationManager.shared.recordSettleFailure()
                    }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.onColor)
                        .frame(width: 20, height: 20)
                        .background(Theme.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.cadencePlain)
                // Name *and* tooltip from one string, the shape T-472 settled on. It carried the
                // `.help` alone, so the pointer got a sentence and VoiceOver got "play.fill".
                .cadenceControlLabel(CadenceTaskControlAccessibility.startFocus)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
            } else {
                Color.clear
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 26, height: 20)
        .padding(.trailing, metrics.badgeSpacing)
    }

    private var doDatePill: some View {
        Button {
            openDoDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 10, alignment: .leading)

                ZStack {
                    Text("Tomorrow")
                        .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                        .opacity(0)

                    Text(DateFormatters.relativeDate(from: task.scheduledDate))
                        .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                        .foregroundStyle(
                            isOverdo
                                ? Theme.red
                                : (isDoToday ? Theme.amber.opacity(0.75) : Theme.dim.opacity(0.68))
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .underline(isDoDateHovered)
            .padding(.horizontal, CadenceTaskChipPadding.desktopHorizontal)
            .padding(.vertical, CadenceTaskChipPadding.desktopVertical)
            .background(isDoDateHovered ? Theme.surfaceElevated.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.cadencePlain)
        // The pill announced a bare "Tomorrow" with nothing saying which of the row's two dates it
        // set — and the due-date pill beside it announced another bare "Tomorrow" (T-594).
        .accessibilityLabel(CadenceTaskControlAccessibility.doDate)
        .accessibilityValue(DateFormatters.relativeDate(from: task.scheduledDate))
        .onHover { hovering in
            guard isDoDateHovered != hovering else { return }
            isDoDateHovered = hovering
            if hovering {
                hoveredTaskManager.beginHoveringDate(.doDate, for: task)
            } else {
                hoveredTaskManager.endHoveringDate(for: task)
            }
        }
        .popover(isPresented: $showDoDatePicker) { doDatePickerPopover }
    }

    private var dueDateBadgeList: some View {
        Button {
            openDueDatePicker()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.dim.opacity(0.68))
                Text(DateFormatters.relativeDate(from: task.dueDate))
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.dim.opacity(0.68))
            }
            .underline(isDueDateHovered)
            .padding(.horizontal, CadenceTaskChipPadding.desktopHorizontal)
            .padding(.vertical, CadenceTaskChipPadding.desktopVertical)
            .background(isDueDateHovered ? Theme.surfaceElevated.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.cadencePlain)
        .padding(.trailing, metrics.contentSpacing)
        .accessibilityLabel(CadenceTaskControlAccessibility.dueDate)
        .accessibilityValue(DateFormatters.relativeDate(from: task.dueDate))
        .onHover { hovering in
            guard isDueDateHovered != hovering else { return }
            isDueDateHovered = hovering
            if hovering {
                hoveredTaskManager.beginHoveringDate(.dueDate, for: task)
            } else {
                hoveredTaskManager.endHoveringDate(for: task)
            }
        }
        .popover(isPresented: $showDueDatePicker) { dueDatePickerPopover }
    }

    private func taskBundleBadge(_ bundle: TaskBundle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack")
                .font(.system(size: 9, weight: .semibold))
            Text(TimeFormatters.timeRange(startMin: bundle.startMin, endMin: bundle.endMin))
                .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.amber.opacity(0.85))
        .padding(.leading, metrics.badgeSpacing)
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
        let resolved = task.dueDate.isEmpty ? Date() : (DateFormatters.date(from: task.dueDate) ?? Date())
        dueDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        dueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDueDatePicker.toggle()
    }

    private func openDoDatePicker() {
        let resolved = task.scheduledDate.isEmpty ? Date() : (DateFormatters.date(from: task.scheduledDate) ?? Date())
        doDatePickerDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        doDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showDoDatePicker.toggle()
    }

    private var taskContainerBinding: Binding<TaskContainerSelection> {
        Binding(
            get: { CadenceTaskComposerSupport.container(of: task) },
            set: { newSelection in
                switch newSelection {
                case .inbox:
                    task.area = nil; task.project = nil; task.context = nil; task.sectionName = TaskSectionDefaults.defaultName
                case .area(let id):
                    if let area = areas.first(where: { $0.id == id }) {
                        task.area = area; task.project = nil; task.context = area.context; task.sectionName = area.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                case .project(let id):
                    if let project = projects.first(where: { $0.id == id }) {
                        task.project = project; task.area = nil; task.context = project.resolvedContext; task.sectionName = project.sectionNames.first ?? TaskSectionDefaults.defaultName
                    }
                }
            }
        )
    }

    /// Which date chips this row draws — **`CadenceTaskPresentationSupport.rowDatePlan`'s answer,
    /// not this row's** (T-304). A task do-dated and due on the same day stated that day twice,
    /// because the sun and the flag were each drawn from their own `isEmpty` check with nothing
    /// between them; the flag survives the merge and the type says why.
    ///
    /// `.todayGrouped` passes an empty do date rather than asking about `task.scheduledDate`: that
    /// style drops the pill by section (`MacTaskRowStyle`), and a row with no sun to draw has
    /// nothing to merge. Same answer either way for those rows — one chip — but the plan stays the
    /// only place that counts chips.
    private var datePlan: CadenceTaskRowDatePlan {
        CadenceTaskPresentationSupport.rowDatePlan(
            scheduledDate: style == .todayGrouped ? "" : task.scheduledDate,
            dueDate: task.dueDate
        )
    }

    // These three were byte-identical re-implementations of the kanban card's copies, which is how
    // the row and the card were free to answer "is this overdue" differently. One definition each.
    private var isOverdue: Bool {
        KanbanCardComputedSupport.isOverdue(task: task)
    }

    private var isOverdo: Bool {
        KanbanCardComputedSupport.isOverdo(task: task)
    }

    private var isDoToday: Bool {
        KanbanCardComputedSupport.isDoToday(task: task)
    }

    /// **The surface decides, and the row does not (T-290).** This read
    /// `style == .standard && !task.containerName.isEmpty`, which got both halves wrong at once:
    /// the style is an axis about the row, and the second clause meant an Inbox task — no area, no
    /// project, so an empty `containerName` — was the one kind of task with no chip to file it
    /// from, on the two surfaces (Today and All Tasks) where filing it is the point. The chip is
    /// the list *picker*, not a label, and `ContainerPickerBadge` already renders the real name
    /// `Inbox` for an unset container.
    private var showsListContextChip: Bool {
        showsContainer
    }

    /// Uniform neutral hover wash. Overdue / over-do state is carried by the red date text on the
    /// row (see `doDatePill` / `dueDateBadgeList`), which is persistent — it is intentionally not
    /// re-encoded as a hover-only background hue.
    private var hoverBackgroundFill: Color {
        TaskHoverVisuals.hoverFill(isHovered: isHovered)
    }

    private func handlePendingDeepLink() {
        guard deepLinkManager.pendingTaskID == task.id else { return }
        showTaskInspector = true
        deepLinkManager.clearPendingTask(task.id)
    }

}

/// The row's estimate, and the picker for it.
///
/// **macOS's task row had no estimate control and iOS's did** — `docs/CLAUDE_REFERENCE.md` records
/// that the old always-loaded guide called the absence deliberate ("the row has **no** estimate
/// control"), which is what kept the gap open through two row passes. The user's call is that the
/// iOS row wins, so it comes across: same figure from `CadenceTaskPresentationSupport.estimateLabel`,
/// same `EstimatePickerPopoverContent` the inspector chip, the kanban card and every iOS surface
/// open.
///
/// **Its own `View` struct, like `TaskCompletionButton` and `TaskRowBackground` beside it.** Not
/// for `TaskCompletionAnimationManager` — this reads nothing from it, and must not start — but for
/// the same reason those two are extracted: the popover's `@State` lives here rather than on
/// `MacTaskRow`, so opening or dismissing it invalidates a chip instead of a whole row of
/// sub-views. `NoteEditorPerformanceRegressionTests`' sibling in `CadenceTodayUnificationTests`
/// pins that this file's only `TaskCompletionAnimationManager` environments stay in those two.
private struct MacTaskRowEstimateChip: View {
    @Bindable var task: AppTask
    @Environment(\.modelContext) private var modelContext
    @State private var showPicker = false
    /// Set when the store refused an estimate change. See `EstimatePickerPopoverContent`'s
    /// committing form (T-761(b)): this used to write through a `Binding` whose setter reached
    /// `CadenceTaskMutationSupport.setEstimatedMinutes`'s swallowed `try? modelContext.save()`,
    /// while the popover's own Done/Clear/preset buttons closed unconditionally.
    @State private var estimateFailure: String?

    /// Reads `.desktop` itself rather than taking it as a prop: it is a macOS-only chip that can
    /// only ever be on a macOS row, and threading the value through would imply a caller gets to
    /// choose the tier.
    private var metrics: CadenceTaskRowMetrics { .desktop }

    /// The figure the chip draws, read once. `.accessibilityValue` states the same string, and
    /// `CadenceTodayUnificationTests` pins that this file reaches the shared label helper from
    /// exactly one place — so the chip and its announcement cannot become "45m" and "45 min".
    private var estimateLabel: String {
        CadenceTaskPresentationSupport.estimateLabel(minutes: task.estimatedMinutes)
    }

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                Text(estimateLabel)
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.dim.opacity(0.68))
            .padding(.horizontal, CadenceTaskChipPadding.desktopHorizontal)
            .padding(.vertical, CadenceTaskChipPadding.desktopVertical)
            .background(isHovered ? Theme.surfaceElevated.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.cadencePlain)
        .padding(.trailing, metrics.badgeSpacing)
        .accessibilityLabel(CadenceTaskControlAccessibility.estimate)
        .accessibilityValue(estimateLabel)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            EstimatePickerPopoverContent(
                value: task.estimatedMinutes,
                failureNotice: estimateFailure,
                onClose: { showPicker = false },
                onCommit: { minutes in
                    let landed = CadenceTaskFieldEditCommit.commit(task, in: modelContext) {
                        task.estimatedMinutes = max(0, min(minutes, 1440))
                    }
                    estimateFailure = landed ? nil : CadenceTaskFieldEditCommit.saveFailureNotice
                    return landed
                }
            )
        }
    }

    /// The same hover treatment the do/due badges beside it take: a wash at radius 4, and nothing
    /// else. One layer, one radius.
    @State private var isHovered = false
}

// MARK: - Isolated sub-views to prevent full-row re-renders on animation state changes

private struct TaskCompletionButton: View {
    @Bindable var task: AppTask
    @Environment(TaskCompletionAnimationManager.self) private var manager

    var body: some View {
        Button { handleTap() } label: {
            // Gated exactly like `TaskRowBackground` below: `TimelineView(.animation)` drives a
            // display-link redraw for as long as it is in the hierarchy, so an ungated one here
            // re-evaluated every visible row's completion glyph at screen refresh rate forever,
            // even though `pendingProgress` returns nil unless the task is mid-completion.
            if isPendingCompletion || isPendingCancel {
                TimelineView(.animation) { context in
                    TaskCompletionProgressGlyph(
                        icon: icon,
                        color: color,
                        progress: pendingProgress(now: context.date)
                    )
                }
            } else {
                TaskCompletionProgressGlyph(icon: icon, color: color, progress: nil)
            }
        }
        .buttonStyle(.cadencePlain)
        // **The primary control on every row, and it had neither a name nor a tooltip** (T-594).
        // Keyed on the glyph's own state, because what a second tap does changes with it — see
        // `CadenceTaskCompletionState.accessibilityActionLabel`, whose five branches mirror
        // `handleTap()` below.
        .accessibilityLabel(glyph.state.accessibilityActionLabel)
    }

    private var isPendingCompletion: Bool { manager.isPending(task) }
    private var isPendingCancel: Bool { manager.isPendingCancel(task) }

    /// The state→appearance decision is `CadenceTaskCompletionGlyph`'s, shared with the kanban
    /// card, the timeline block and every iOS surface. It used to be this ordered `if` chain,
    /// copied verbatim into `KanbanCardComputedSupport` and dropped to two states on iOS.
    private var glyph: CadenceTaskCompletionGlyph {
        .resolve(
            task: task,
            isPendingCompletion: isPendingCompletion,
            isPendingCancellation: isPendingCancel
        )
    }

    private var icon: String { glyph.symbolName }

    private var color: Color { glyph.tint }

    private func handleTap() {
        if isPendingCompletion {
            manager.cancelPending(for: task.id)
            manager.toggleCancellation(for: task)
        } else if isPendingCancel {
            manager.cancelCancelPending(for: task.id)
        } else {
            manager.toggleCompletion(for: task)
        }
    }

    private func pendingProgress(now: Date) -> Double? {
        if isPendingCompletion {
            return manager.progress(for: task, now: now)
        }
        if isPendingCancel {
            return manager.cancelProgress(for: task, now: now)
        }
        return nil
    }
}

private struct TaskRowBackground: View {
    let task: AppTask
    let isHovered: Bool
    let hoverFill: Color
    @Environment(TaskCompletionAnimationManager.self) private var manager

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radiusCard)
            .fill(Color.clear)
            .overlay {
                if hoverFill != .clear {
                    RoundedRectangle(cornerRadius: Theme.radiusCard).fill(hoverFill)
                }
            }
            .overlay {
                if manager.isPending(task) {
                    TimelineView(.animation) { context in
                        TaskCompletionPendingOverlay(
                            progress: manager.progress(for: task, now: context.date),
                            tint: Theme.green,
                            cornerRadius: Theme.radiusCard
                        )
                    }
                } else if manager.isPendingCancel(task) {
                    TimelineView(.animation) { context in
                        TaskCompletionPendingOverlay(
                            progress: manager.cancelProgress(for: task, now: context.date),
                            tint: Theme.dim,
                            cornerRadius: Theme.radiusCard
                        )
                    }
                }
            }
    }
}

#endif
