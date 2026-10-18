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
    /// The day this row's surface has already named, if it names one — `CadenceBoardCardMetadata`'s
    /// knob, under its own name, asked of its own function. Today passes `todayKey`, and the sun
    /// pill it would otherwise draw on **every** row of a page called Today goes away: *"since this
    /// is in today's view, no tasks appearing here need the 'today' chip in the front"*. It is the
    /// standing page-header rule one level further down, and the same one that already keeps a
    /// calendar day column's cards from repeating their column's date.
    ///
    /// **An equality, not a surface flag**, which is what makes it safe here: a task do-dated
    /// *yesterday* on the Today page does not match, so it keeps its pill and keeps it red. That
    /// row's lateness is the only thing stating it once the Overdue section is gone, so a blunter
    /// "Today hides the sun" — which is what `MacTaskRowStyle.todayGrouped` would have given — would
    /// have hidden it. See `CadenceBoardCardMetadata.repeatsSurfaceDay`, which argues the same point
    /// for the boards.
    var dayAlreadyStatedBySurface: String? = nil
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
    /// The context menu's two after-the-click states — see `MacTaskRowMenuOutcomeModifier`.
    @State private var pendingMenuRecurrenceRule: TaskRecurrenceRule?
    @State private var menuFailure: MacTaskRowMenuFailure?

    /// **The row's figures, from the type five iOS files already read.** This row hardcoded its own
    /// 14 / 8 / 15 / 11 / 6 while `CadenceTaskRowMetrics` sat in `Shared/` with no macOS reader at
    /// all — which is how the two primary rows were free to drift a padding at a time. `.desktop`
    /// is a third tier rather than `.regular` relabelled, and the type's doc comment carries both
    /// the figures macOS keeps to itself and the ones it deliberately does not read.
    private var metrics: CadenceTaskRowMetrics { .desktop }

    /// The note / checklist / tag glyphs this row draws after its title — the shared answer, asked
    /// once so the strip and the padding beside it cannot disagree about whether there is anything
    /// to pad. `iOSTaskRow` asks the same function.
    private var rowIndicators: [CadenceTaskRowIndicator] {
        CadenceTaskRowIndicatorSupport.indicators(for: task)
    }

    var body: some View {
        // **Two tiers since [[T-1467]]: the title line, then what the task holds.** The row was one
        // `HStack` and said nothing about a task's notes or child work beyond two glyphs, while the
        // iOS row printed a notes excerpt and listed the open subtasks with checkboxes — the same
        // task told the desktop less (parity findings PA-01 and PA-02). The owner chose the full
        // match: excerpt *and* checkboxes.
        //
        // The completion circle stays in its own leading column and is centred on the **title
        // line**, not on the whole row, through `.macTaskRowTitleLine`: centred on the row it would
        // drift down beside a task with three subtasks and stop reading as that title's control.
        // A row with no notes and no open subtasks lays out exactly as before — the detail tier
        // contributes no children, so the `VStack` holds one and adds no spacing.
        HStack(alignment: .macTaskRowTitleLine, spacing: 0) {
            TaskCompletionButton(task: task)
                .padding(.leading, metrics.horizontalPadding)
                .padding(.trailing, metrics.contentSpacing)

            VStack(alignment: .leading, spacing: metrics.summarySpacing) {
                titleLine
                    .alignmentGuide(.macTaskRowTitleLine) { $0[VerticalAlignment.center] }

                inlineDetail
            }
        }
        .padding(.vertical, metrics.verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { showTaskInspector = true }
        // **Right-click is a menu, not a second tap ([[T-1479]]).** It used to be a
        // `RightClickActionTrigger` overlay running the same `showTaskInspector = true` as the
        // line above, which spent the gesture macOS reserves for a menu on a duplicate. Tap keeps
        // the inspector; right-click gains iOS's long-press actions. See `MacTaskRowContextMenu`.
        .contextMenu {
            MacTaskRowContextMenu(
                task: task,
                openDetail: { showTaskInspector = true },
                startFocus: startFocus,
                requestDelete: presentDelete,
                pendingRecurrenceRule: $pendingMenuRecurrenceRule,
                failure: $menuFailure
            )
        }
        .modifier(MacTaskRowMenuOutcomeModifier(
            task: task,
            pendingRecurrenceRule: $pendingMenuRecurrenceRule,
            failure: $menuFailure
        ))
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

    /// The row's first line — do-date pill, title, glyphs, the Cancelled chip, then the trailing
    /// metadata and list chip — exactly the single `HStack` the whole row used to be. It moved
    /// into its own property unchanged when [[T-1467]] put a detail tier beneath it, so the
    /// T-1432 layout argument below still holds line for line.
    private var titleLine: some View {
        HStack(alignment: .center, spacing: 0) {
            if datePlan.drawsDoDateChip {
                doDatePill
                    .padding(.trailing, metrics.contentSpacing)
            }

            // **`.layoutPriority(1)`, and it is the whole of T-1432(3).** Every flexible child of
            // this `HStack` used to sit at the same priority, so the stack split the row between
            // the title and each metadata `Text` in roughly equal shares — the owner photographed a
            // row whose title had collapsed to `check fo…` while a due chip beside it wrapped onto
            // three lines. The title is the only part of a row that identifies its task; the chips
            // are decoration over information the row states again elsewhere. So the title is laid
            // out first, and takes whatever it can use up to its full width; `metadataStrip`
            // divides what is left and sheds chips rather than crushing it.
            Text(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))
                .font(.system(size: metrics.titleFontSize))
                .foregroundStyle(task.isDone || task.isCancelled ? Theme.dim : Theme.text)
                .strikethrough(task.isDone || task.isCancelled, color: Theme.dim)
                .lineLimit(1)
                .layoutPriority(1)
                // Addressable by identifier because it is not addressable by its text: the defect
                // above *is* a truncated title, and a lookup by label would stop resolving at the
                // moment it appeared. `CadenceTodayRowCrushUITests` reads this element's width.
                .accessibilityIdentifier(CadenceAccessibilityIdentifiers.taskRowTitle(title: task.title))

            // **The tag chips are gone from here and a glyph stands in for them (T-2058).** The
            // owner asked for note / checklist / tag icons after the title on all three platforms
            // and, asked directly whether the icon should replace the named chips, chose replace:
            // you no longer see *which* tags without opening the task. The side benefit is the one
            // this row needed most — `CompactTagStrip` shed chips through `ViewThatFits` as the
            // pane narrowed, so what the row said about a task changed with the window; three
            // glyphs are the same 48pt at every width.
            //
            // It attaches **here**, with the title, rather than in `metadataStrip` below, for the
            // same reason: that strip is where things go to be shed.
            CadenceTaskRowIndicatorStrip(indicators: rowIndicators)
                .padding(.leading, rowIndicators.isEmpty ? 0 : metrics.badgeSpacing)

            if task.isCancelled {
                // The last chip on this row, drawn like the others. It set its own `10` and
                // `6/3` while the do-date pill and the due-date pill beside it both read
                // `metrics.secondaryFontSize` at
                // `CadenceTaskChipPadding.desktop*` — which is the drift `CadenceTaskRowMetrics.desktop`
                // exists to stop (T-597). The plate was four inline `4/2` pairs until T-617. Two of
                // those four readers have since gone: the block badge with the Block feature
                // ([[T-3170]]), and the estimate chip with [[T-3196]].
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

            metadataStrip

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
    }

    /// The notes excerpt, then the open subtasks — [[T-1467]], parity findings PA-01 and PA-02.
    ///
    /// **Both answers are the shared ones iOS's row reads**: the excerpt is
    /// `CadenceTaskPresentationSupport.plainPreviewText` at this tier's `notesPreviewLimit`, one
    /// line (`secondaryLineLimit`), and the subtasks are `listedSubtasks(for:)` with
    /// `unlistedSubtaskCount(for:)` — unfinished only, capped at three, none under a finished task.
    /// The figures are `.desktop`'s, which stated them at `.compact`'s answers for exactly this
    /// day: a macOS task column is a narrow pane.
    ///
    /// The note / checklist glyphs on the title line **stay** for now. [[T-3196]] decided they
    /// come off both platforms once both rows show what they stand for; this is the macOS half of
    /// that precondition, and the glyph removal itself is [[T-3196]]'s (its iOS half is
    /// lease-blocked), so taking them off here alone would make the two rows disagree again.
    @ViewBuilder
    private var inlineDetail: some View {
        if let notesPreview {
            Text(notesPreview)
                .font(.system(size: metrics.secondaryFontSize))
                .foregroundStyle(Theme.dim)
                .lineLimit(metrics.secondaryLineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, metrics.horizontalPadding)
        }

        let subtasks = CadenceTaskPresentationSupport.listedSubtasks(for: task)
        if !subtasks.isEmpty {
            MacTaskSubtaskPreviewList(
                subtasks: subtasks,
                hiddenCount: CadenceTaskPresentationSupport.unlistedSubtaskCount(for: task),
                overflowFontSize: metrics.secondaryFontSize
            )
            .padding(.trailing, metrics.horizontalPadding)
        }
    }

    /// `nil` rather than an empty string, so a task whose notes are only markup or whitespace
    /// draws no line at all — the same test iOS's `secondaryLine` makes.
    private var notesPreview: String? {
        let preview = CadenceTaskPresentationSupport.plainPreviewText(
            from: task.notes,
            limit: metrics.notesPreviewLimit
        )
        return preview.isEmpty ? nil : preview
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
            presentDelete()
        }
    }

    /// The row's one delete: Cmd+Delete over the hovered row and the context menu's Delete Task
    /// both arrive here, so they share one confirmation and one hover teardown.
    private func presentDelete() {
        deleteConfirmationManager.presentTaskDelete(task, in: modelContext) {
            if hoveredTaskManager.hoveredTask?.id == task.id {
                hoveredTaskManager.hoveredTask = nil
            }
            hoveredEditableManager.endHovering(id: editableID)
        }
    }

    /// The row's one focus start: the hover ▶ and the context menu's Focus. T-654: `startFocus`
    /// commits a pending bank and can refuse.
    private func startFocus() {
        do {
            try focusManager.startFocus(task: task, in: modelContext)
        } catch {
            TaskCompletionAnimationManager.shared.recordSettleFailure()
        }
    }

    private func endHoverRegistration() {
        hoveredTaskManager.endHovering(task)
        hoveredEditableManager.endHovering(id: editableID)
    }

    /// The trailing decoration — the focus control and the due date — as **one child** of the row's
    /// `HStack`, which is what lets it yield to the title (T-1432).
    ///
    /// **There is no `ViewThatFits` ladder here any more, because nothing is left to shed
    /// ([[T-3196]]).** The owner called the estimate noise — *"for all devices when seeing tasks in
    /// a view like this, remove the estimated time chip on the right of the task cuz it just looks
    /// noisy"* — and the estimate was the only thing that distinguished the last reading from the
    /// first. Two readings that draw the same views are one reading, so the ladder is gone rather
    /// than left as a `ViewThatFits` with one child, which renders that child unconditionally and
    /// says nothing. The replacement is exactly equivalent: before this change `metadataRow` was
    /// called with and without the estimate, and with the chip deleted both calls built the same
    /// `HStack`.
    ///
    /// **The due date is what stands in the vacated slot, and it needed no move to get there.**
    /// The owner asked that *"where the estimated time chip was, now in that same place we should
    /// put down the due date if any of that task. if there is no due date, leave it empty and use
    /// that space."* On macOS the due chip already sat immediately after the estimate in this
    /// strip, so deleting the estimate slides it to the trailing edge; a task with no due date
    /// draws nothing and the width goes to the title, which is the "leave it empty and use that
    /// space" half. iOS has further to go — its due date is a chip in the wrapping badge strip
    /// under the title — and that half of [[T-3196]] is not this file's.
    ///
    /// **The ladder was three readings until [[T-3170]] and two until this.** The widest led with
    /// the block's time range, which shed first — it was the widest of the three and the one the
    /// row stated least usefully in a fragment, `6:10 AM…` naming nothing. The Block feature is
    /// gone, which retired the surviving half of this row's parity finding, PA-04 in
    /// `docs/PLATFORM_PARITY_AUDIT.md`. PA-04's other half was the estimate, and this closes it:
    /// the Mac row sheds no metadata that iOS keeps, because this strip sheds nothing at all.
    ///
    /// `.fixedSize(horizontal: true, vertical: false)` **stays, and is still load-bearing without
    /// the ladder.** It was put here so each variant reported the width it actually needed rather
    /// than "fitting" any width by truncating its own text; with one reading left it is what makes
    /// the strip state a real minimum, and that minimum is all the row reserves before the title,
    /// at `.layoutPriority(1)`, is offered the rest. Dropping it would let the due chip squeeze and
    /// wrap, which is the defect T-1432 was filed from.
    ///
    /// The focus control is inside the strip rather than beside it only because it sits before the
    /// due chip in the row's reading order; it is a fixed 26pt slot.
    private var metadataStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            focusButtonSlot

            if datePlan.drawsDueDateChip {
                dueDateBadgeList
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var focusButtonSlot: some View {
        Group {
            // The shared predicate, not a second hand-written `!isDone && !isCancelled`. This row
            // was the *only* surface in the app asking the question, and the three iOS entry points
            // added since did not ask it at all (T-276).
            if CadenceFocusSupport.canFocus(task) {
                Button(action: startFocus) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.onColor(for: Theme.blue))
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
                // `.lineLimit(1)`. The do-date pill beside it has never needed one — it reserves
                // its width with a hidden `Text("Tomorrow")` and pins it with `.fixedSize` — and
                // this chip had neither, so `51 days ago` wrapped onto three lines (`51` / `days` /
                // `ago`) and took three lines of row height with it.
                Text(DateFormatters.relativeDate(from: task.dueDate))
                    .font(.system(size: metrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(isOverdue ? Theme.red : Theme.dim.opacity(0.68))
                    .lineLimit(1)
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
        // The chip's *box*, so a UI test can read the height the wrap took. The label above names
        // the control and the value reads the date; neither says how tall it came out.
        .accessibilityIdentifier(CadenceAccessibilityIdentifiers.taskRowDueChip(title: task.title))
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

    // [[T-3170]] removed taskBundleBadge(_:) — a `square.stack` glyph and the block's time range,
    // drawn on any row whose task was a block member. Nothing replaces it: the row says nothing
    // about block membership because there are no blocks to belong to.

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
    /// Both suppressions go in as an **empty do date** rather than as a branch after the plan: a row
    /// with no sun to draw has nothing to merge, and the plan stays the only place that counts
    /// chips. `.todayGrouped` drops the pill by section (`MacTaskRowStyle`);
    /// `dayAlreadyStatedBySurface` drops it only when it would repeat the day the surface has
    /// already named.
    private var datePlan: CadenceTaskRowDatePlan {
        CadenceTaskPresentationSupport.rowDatePlan(
            scheduledDate: statedDoDate,
            dueDate: task.dueDate
        )
    }

    /// The do date this row still has something to say about — `""` when it does not.
    private var statedDoDate: String {
        guard style != .todayGrouped else { return "" }
        guard !CadenceBoardCardMetadata.repeatsSurfaceDay(
            task.scheduledDate,
            dayAlreadyStatedBySurface: dayAlreadyStatedBySurface
        ) else { return "" }
        return task.scheduledDate
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

// [[T-3196]] removed MacTaskRowEstimateChip — a clock glyph and the task's estimate, drawn at the
// head of the row's trailing strip and opening the shared EstimatePickerPopoverContent. The owner
// asked for it off every platform's list row because a column of capsules reads before any task
// title does. Nothing replaces it: the due date slid into the slot, and the estimate itself is
// untouched everywhere else it is edited or read — AppTask.estimatedMinutes, the capture card's
// overflow, the task inspector, the kanban card, the markdown embed and Focus all still have it.
// It is the LIST ROW that stopped saying it, on purpose.

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

/// The vertical line `MacTaskRow` centres its completion circle on: the middle of the **title
/// line**, not of the whole row, once [[T-1467]] let the row grow a notes excerpt and subtasks
/// beneath that line. Only the title line sets it, so there is one answer to take.
private extension VerticalAlignment {
    enum MacTaskRowTitleLine: AlignmentID {
        nonisolated static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let macTaskRowTitleLine = VerticalAlignment(MacTaskRowTitleLine.self)
}

#endif
