#if os(macOS)
import SwiftUI
import SwiftData

// MARK: - Column

/// One of Cadence's **two** kanban column implementations: this one renders the *section*
/// columns of a list/project board. The other is `TaskListKanbanColumn` in
/// `KanbanListColumnView.swift`, which renders the *list* columns of the All Tasks board.
/// The two must stay visually identical — all shared chrome lives in
/// `KanbanColumnSupportViews.swift` / `KanbanBoardSupport.swift`, so change it there, not here.
struct ListSectionKanbanColumn: View {
    let section: TaskSectionConfig
    let tasks: [AppTask]
    let universeTasks: [AppTask]
    var area: Area?
    var project: Project?
    let isBeingDragged: Bool
    let isAnotherSectionBeingDragged: Bool
    let isHighlighted: Bool
    /// Answers whether the new **column** order is in the store (T-870). `Void` until then, over a
    /// blob rewrite that reached no commit — so this column reported every column drag as landed.
    let onReorderBefore: (String) -> Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredKanbanColumnManager.self) private var hoveredKanbanColumnManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager
    @Environment(HoveredSectionManager.self) private var hoveredSectionManager
    @Environment(SectionCompletionAnimationManager.self) private var sectionCompletionAnimationManager
    @State private var isTargeted = false
    @State private var isComposing = false
    @State private var dragOverTaskID: UUID? = nil
    @State private var frozenTasks: [AppTask]? = nil
    @State private var showDoneTasks = false
    @State private var showEditor = false
    @State private var editorName = ""
    @State private var editorColorHex = TaskSectionDefaults.defaultColorHex
    @State private var editorDueDate = Date()
    @State private var editorHasDueDate = false
    /// The column as it stood when the popover opened. The save diffs against this, not against
    /// the live `section`, so a rename that arrived from another device while the popover was open
    /// does not read as "the user changed the name back".
    @State private var editorBase: TaskSectionConfig?
    /// The name the column's **cards** are filed under, which is not the name its *config* carries
    /// while the rename field is being typed into (T-713). `applySectionEdits` writes the config on
    /// every keystroke and moves nothing; `moveCardsToStoredColumnName()` settles the cards at the
    /// commit point and advances this.
    ///
    /// **This is not `editorBase` and must never become it.** `editorBase` is frozen at the moment
    /// the popover opened so the merge writes only the fields the user actually changed — advancing
    /// it would let a colour press write a stale name back over a rename that arrived from another
    /// device, which is the case T-358 froze it for. This one advances, and only when cards really
    /// moved.
    @State private var editorFiledCardName: String?
    @State private var showHeaderDueDatePicker = false
    @State private var headerDueDate = Date()
    @State private var headerDueDateViewMonth = Date()
    @State private var isHovered = false
    /// Set when a column write was refused by the store, and drawn inside the editor popover. The
    /// popover staying open *is* the report of failure here — see `toggleSectionArchive()`.
    @State private var saveFailureNotice: String?
    /// Set when the store refused a **card** drop (T-869). Separate from `saveFailureNotice`, which
    /// belongs to the editor popover and gates `toggleCompletionFromEditor` — a refused drag must
    /// not hold that popover shut. Both reach the header through `columnFailureNotice`.
    @State private var reorderFailureNotice: String?
    /// Both halves come from one call, so they cannot disagree about what "over" means. See
    /// `KanbanBoardSupport.columnHalves` for why this is not `isDone` (T-381 / T-399).
    private var columnHalves: (active: [AppTask], completed: [AppTask]) {
        KanbanBoardSupport.columnHalves(from: tasks)
    }

    private var unfrozenActiveTasks: [AppTask] {
        columnHalves.active
    }

    private var activeTasks: [AppTask] {
        applyFrozenTaskOrder(unfrozenActiveTasks, frozen: frozenTasks)
    }

    private var completedTasks: [AppTask] {
        columnHalves.completed
    }

    private var columnColor: Color {
        section.isDefault ? Theme.dim : Color(hex: section.colorHex)
    }

    private var sectionHoverID: String {
        "kanban-column-\(section.id.uuidString)"
    }

    private var sectionEditHoverID: String {
        "kanban-section-edit-\(section.id.uuidString)"
    }

    private var hideColumnDueDateIfEmpty: Bool {
        if let area { return area.hideSectionDueDateIfEmpty }
        if let project { return project.hideSectionDueDateIfEmpty }
        return false
    }

    var body: some View {
        columnBody
            .background {
                KanbanFreezeObserver(
                    frozenTasks: $frozenTasks,
                    columnTaskIDs: Set(unfrozenActiveTasks.map(\.id)),
                    capturedTasks: unfrozenActiveTasks
                )
            }
    }

    private var columnBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The hairline under the header is part of `CadenceBoardColumnHeader` itself, so all three
            // boards close their header the same way without each column remembering to.
            columnHeader

            columnTaskScroll
        }
        .kanbanColumnChrome(tint: columnColor, isTargeted: isTargeted) {
            // Section columns can be "completing…" — that sweep layers on top of the shared
            // drag-over wash.
            if isPendingCompletion {
                TimelineView(.animation) { context in
                    TaskCompletionPendingOverlay(
                        progress: sectionCompletionAnimationManager.progress(for: section, now: context.date),
                        tint: Theme.green,
                        cornerRadius: kanbanColumnCornerRadius
                    )
                }
            }
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: kanbanColumnCornerRadius)
                    .strokeBorder(columnColor.opacity(0.9), lineWidth: 2)
                    .padding(-4)
                    .shadow(color: columnColor.opacity(0.28), radius: 14)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isBeingDragged ? 0.972 : 1)
        .opacity(isBeingDragged ? 0.42 : 1)
        .zIndex(isBeingDragged ? 3 : (isTargeted ? 2 : 0))
        .animation(kanbanColumnStateAnimation, value: isBeingDragged)
        .animation(kanbanColumnStateAnimation, value: isTargeted)
        .overlay(alignment: .top) {
            if isTargeted && isAnotherSectionBeingDragged {
                RoundedRectangle(cornerRadius: 3)
                    .fill(columnColor.opacity(0.9))
                    .frame(height: 3)
                    .padding(.horizontal, 4)
                    .offset(y: -8)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            if payload.hasPrefix(kanbanSectionDragPrefix) {
                let movingName = String(payload.dropFirst(kanbanSectionDragPrefix.count))
                // The board answers, not this column (T-870): the column order is a blob on the
                // list, and a refused commit puts it back before this returns.
                return onReorderBefore(movingName)
            }
            // Same payload parsing as the card-level drop and as the list board's column, so a
            // drop on empty column space accepts exactly what a drop on a card accepts.
            guard let uuid = KanbanBoardSupport.taskID(from: payload),
                  let task = universeTasks.first(where: { $0.id == uuid }) else { return false }
            return moveTask(task, before: nil)
        } isTargeted: { isTargeted = $0 }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hoveredKanbanColumnManager.beginHovering(id: sectionHoverID) {
                    isComposing = true
                }
                // Cmd+Return over a column is the third route to completion, and the only one
                // with no visible control to hide. Default does not register at all rather than
                // registering a no-op: `triggerToggleComplete()` reports whether it handled the
                // key, so a registered target would swallow Cmd+Return instead of letting it
                // through (T-268).
                if section.supportsLifecycle {
                    hoveredSectionManager.beginHovering(id: section.id) {
                        toggleSectionCompletion()
                    }
                }
            } else {
                hoveredKanbanColumnManager.endHovering(id: sectionHoverID)
                hoveredSectionManager.endHovering(id: section.id)
            }
        }
    }

    /// The `TimelineView` must stay *conditional*: an unconditional one re-renders every
    /// visible column on every display frame, forever.
    @ViewBuilder
    private var columnHeader: some View {
        if isPendingCompletion {
            TimelineView(.animation) { context in
                header(completionProgress: sectionCompletionAnimationManager.progress(for: section, now: context.date))
            }
        } else {
            header(completionProgress: 0)
        }
    }

    private func header(completionProgress: Double) -> some View {
        KanbanColumnHeader(
            section: section,
            activeTaskCount: activeTasks.count,
            columnColor: columnColor,
            hideColumnDueDateIfEmpty: hideColumnDueDateIfEmpty,
            isPendingCompletion: isPendingCompletion,
            completionProgress: completionProgress,
            failureNotice: columnFailureNotice,
            showHeaderDueDatePicker: $showHeaderDueDatePicker,
            showEditor: $showEditor,
            onToggleCompletion: toggleSectionCompletion,
            onOpenDueDatePicker: openHeaderDueDatePicker,
            onOpenEditor: openSectionEditor,
            onHoverChanged: { hovering in
                if hovering {
                    hoveredEditableManager.beginHovering(id: sectionEditHoverID) {
                        openSectionEditor()
                    }
                } else {
                    hoveredEditableManager.endHovering(id: sectionEditHoverID)
                }
            },
            dueDatePopover: {
                sectionDueDatePickerPopover
            },
            editorPopover: {
                columnEditor
            }
        )
    }

    private var columnTaskScroll: some View {
        KanbanColumnScroll(
            isColumnHovered: isHovered,
            add: .compose(.column(container: taskContainerSelection, sectionName: section.name)),
            isComposing: $isComposing
        ) {
            activeTaskCards
            completedTaskSection
        }
    }

    @ViewBuilder
    private var activeTaskCards: some View {
        ForEach(activeTasks) { task in
            KanbanDraggableCard(
                task: task,
                showsDropIndicator: dragOverTaskID == task.id,
                onDropTargetedChanged: { isOver in
                    if isOver { dragOverTaskID = task.id }
                    else if dragOverTaskID == task.id { dragOverTaskID = nil }
                },
                onDropBefore: { items in
                    handleTaskDrop(items: items, before: task)
                }
            )
        }
    }

    @ViewBuilder
    private var completedTaskSection: some View {
        if !completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                completedTasksToggle

                if showDoneTasks {
                    completedTaskCards
                }
            }
            .padding(.top, 6)
        }
    }

    private var completedTasksToggle: some View {
        KanbanCompletedTasksToggle(count: completedTasks.count, isExpanded: showDoneTasks) {
            withAnimation(.easeInOut(duration: 0.18)) {
                showDoneTasks.toggle()
            }
        }
    }

    private var completedTaskCards: some View {
        VStack(spacing: 6) {
            ForEach(completedTasks) { task in
                KanbanDraggableCard(task: task) { items in
                    handleTaskDrop(items: items, before: task)
                }
            }
        }
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                removal: .opacity
            )
        )
    }

    private func handleTaskDrop(items: [String], before target: AppTask) -> Bool {
        guard let payload = items.first,
              let droppedID = KanbanBoardSupport.taskID(from: payload),
              droppedID != target.id,
              let droppedTask = universeTasks.first(where: { $0.id == droppedID }) else { return false }
        return moveTask(droppedTask, before: target)
    }

    /// The list this board belongs to — the "where does this go" half that the column's composer
    /// seeds, alongside `section.name`.
    private var taskContainerSelection: TaskContainerSelection {
        if let area {
            return .area(area.id)
        }
        if let project {
            return .project(project.id)
        }
        return .inbox
    }

    /// File the card into this column and put it where it was dropped, as one commit.
    ///
    /// **`return true` used to sit over no commit at all (T-869).** The four field writes below and
    /// the renumber both landed in the context with nothing flushing them, so the board drew the
    /// drop and the store still held the old column and the old order.
    ///
    /// The refiling is the `assigning:` closure rather than four statements ahead of the call, so a
    /// refused drop is not left half-applied — the card filed under this column's `sectionName` at
    /// the position it had in its old one. `KanbanBoardSupport.reorder` snapshots every field
    /// either half writes, including `sectionName` and all three relationships.
    private func moveTask(_ task: AppTask, before target: AppTask?) -> Bool {
        let reordered = KanbanBoardSupport.reorder(
            tasks.sorted { $0.order < $1.order },
            moving: task,
            before: target,
            in: modelContext,
            assigning: {
                if let area {
                    task.area = area
                    task.project = nil
                    task.context = area.context
                } else if let project {
                    task.project = project
                    task.area = nil
                    task.context = project.resolvedContext
                } else {
                    task.area = nil
                    task.project = nil
                }
                task.sectionName = section.name
            }
        )
        reorderFailureNotice = reordered ? nil : CadenceOrderCommit.failureNotice
        return reordered
    }

    private func openSectionEditor() {
        // A notice belongs to the attempt that produced it. Without this, a refused archive would
        // still be showing its red line the next time the popover opened — and `toggleCompletionFromEditor`
        // reads the same flag to decide whether it may close, so a stale one would hold the popover shut.
        saveFailureNotice = nil
        editorBase = section
        editorFiledCardName = section.name
        editorName = section.name
        editorColorHex = section.colorHex
        editorDueDate = DateFormatters.date(from: section.dueDate) ?? Date()
        editorHasDueDate = !section.dueDate.isEmpty
        showEditor = true
    }

    private func openHeaderDueDatePicker() {
        let resolved = DateFormatters.date(from: section.dueDate) ?? Date()
        headerDueDate = resolved
        var comps = Calendar.current.dateComponents([.year, .month], from: resolved)
        comps.day = 1
        headerDueDateViewMonth = Calendar.current.date(from: comps) ?? resolved
        showHeaderDueDatePicker = true
    }

    @ViewBuilder
    private var sectionDueDatePickerPopover: some View {
        KanbanSectionDueDatePickerPopover(
            dueDateKey: section.dueDate,
            selection: Binding(
                get: { headerDueDate },
                set: { newDate in
                    headerDueDate = newDate
                    updateSection { config in
                        config.dueDate = DateFormatters.dateKey(from: newDate)
                    }
                }
            ),
            viewMonth: $headerDueDateViewMonth,
            isPresented: $showHeaderDueDatePicker,
            onClear: {
                updateSection { config in
                    config.dueDate = ""
                }
                showHeaderDueDatePicker = false
            }
        )
    }

    @ViewBuilder
    private var columnEditor: some View {
        KanbanSectionEditorPopover(
            section: section,
            editorColorOptions: CadenceColorPalette.offeredSectionColors(for: editorColorHex),
            editorName: $editorName,
            editorColorHex: $editorColorHex,
            editorDueDate: $editorDueDate,
            editorHasDueDate: $editorHasDueDate,
            failureNotice: saveFailureNotice,
            // **Apply on every keystroke; commit at the end of the edit (T-645).** The rename
            // writes the container's blob per character so the board's header tracks the field,
            // and a commit per character would ask the store for a transaction per character and
            // give the user a refusal notice mid-word. So `applySectionEdits` is the write and
            // `commitSectionEdits` is the point — the name field submitting or losing focus, a
            // colour chosen, a date picked. See `commitSectionEdits()` for why the rename's
            // refusal keeps the text rather than restoring it.
            onNameChanged: applySectionEdits,
            onNameCommitted: { _ = commitSectionEdits() },
            onColorSelected: { _ = commitSectionEdits() },
            onDueDateChanged: { _ = commitSectionEdits() },
            onClearDate: { _ = clearSectionDueDate() },
            onToggleCompletion: toggleCompletionFromEditor,
            onToggleArchive: toggleSectionArchive,
            onDelete: {
                deleteConfirmationManager.present(
                    title: "Delete Column?",
                    message: "This will delete the column \"\(section.name)\" and move its tasks into Default."
                ) {
                    guard deleteSection() else { return }
                    showEditor = false
                }
            }
        )
    }

    private func updateSection(_ mutate: (inout TaskSectionConfig) -> Void) {
        KanbanSectionStateSupport.updateSection(sectionID: section.id, area: area, project: project, mutate: mutate)
    }

    /// The popover snapshots name, colour and due date when it opens and writes all three on save,
    /// so it is a stale-snapshot writer even though it is only open for a few seconds: a colour
    /// change here would otherwise write the *old* name back over a rename that landed from another
    /// device in the meantime. `editorBase` is the column as the popover opened, and the merge
    /// applies only the fields that differ from it (`docs/TODO.md` T-358).
    ///
    /// **This applies and does not commit, and that is the split T-645 is about.** It runs on every
    /// keystroke of the rename field. `commitSectionEdits()` is the commit point.
    ///
    /// **And it moves no cards, which is the split T-713 is about.** It used to end by calling
    /// `moveTasks(from: base.name, to: trimmed)`, against a `base` that is deliberately frozen — so
    /// only the *first* keystroke found anything: typing `Doing` → `Doingxy` moved the cards to
    /// `Doingx`, then looked for cards still called `Doing`, found none, and left them there, filed
    /// under a name no column had. The cards move once, at the commit point, in
    /// `moveCardsToStoredColumnName()`. An intermediate name never touches a card.
    private func applySectionEdits() {
        let base = editorBase ?? section
        let trimmed = base.isDefault ? base.name : editorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let container = CadenceSectionConfigMerge.container(area: area, project: project) else { return }

        let current = container.sectionConfigs
        guard current.contains(where: { $0.uuid == base.uuid }) else { return }
        if trimmed.caseInsensitiveCompare(base.name) != .orderedSame,
           current.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return
        }

        var edited = base
        edited.name = trimmed
        edited.colorHex = editorColorHex
        edited.dueDate = editorHasDueDate ? DateFormatters.dateKey(from: editorDueDate) : ""
        container.applySectionConfigEdits(
            base: current.map { $0.uuid == base.uuid ? base : $0 },
            edited: current.map { $0.uuid == base.uuid ? edited : $0 }
        )
    }

    /// Where the column's cards are filed right now: the editor's own record while the popover is
    /// open, and the column's name otherwise.
    private var filedCardName: String {
        showEditor ? (editorFiledCardName ?? section.name) : section.name
    }

    /// **The rename's card move, taken once at the commit point (T-713).**
    ///
    /// See `KanbanSectionStateSupport.moveCardsToStoredName` for why the source is where the cards
    /// actually are rather than `editorBase.name`, and why the destination is read back out of the
    /// container rather than taken from the field.
    private func moveCardsToStoredColumnName() {
        guard let base = editorBase else { return }
        guard let filed = KanbanSectionStateSupport.moveCardsToStoredName(
            universeTasks: universeTasks,
            area: area,
            project: project,
            columnUUID: base.uuid,
            typedName: editorName.trimmingCharacters(in: .whitespacesAndNewlines),
            filedName: filedCardName
        ) else { return }
        editorFiledCardName = filed
    }

    /// The rename's **commit point** (T-645): `applySectionEdits()` and then one commit, at the end
    /// of an edit rather than in the middle of one.
    ///
    /// **`CadenceInPlaceEditFlush` rather than `commitEdit(in:undo:)`, and the difference is the
    /// caret.** The other three writes on this popover are discrete — a colour, a date, a delete —
    /// and each can be put back and reported as "Nothing was changed". A rename cannot: the field
    /// is still on screen holding what the user typed, and an undo here would delete their text in
    /// order to tell them it had not been saved. So nothing is restored, the popover stays open
    /// with the text in it, and the notice says the changes are still there. That is the decision
    /// `CadenceInPlaceEditFlush` records, arrived at for the iOS note and task editors.
    ///
    /// **What "commit point" means, and what it does not.** Every other control in this popover
    /// commits, and a commit takes the whole context — so a pending rename is carried by the very
    /// next colour, date, archive, completion or delete. The point of committing here is not to
    /// keep the rename from being lost; it is to have somewhere to *report a refusal* while the
    /// popover that would show it is still on screen.
    ///
    /// **It is also where the column's cards move (T-713)**, after the apply and before the flush,
    /// so the rename and the cards it re-points reach the store as one commit and a refusal leaves
    /// them agreeing with each other rather than stranded apart.
    private func commitSectionEdits() -> Bool {
        applySectionEdits()
        moveCardsToStoredColumnName()
        guard CadenceInPlaceEditFlush.flush(in: modelContext) else {
            saveFailureNotice = CadenceInPlaceEditFlush.failureNotice
            return false
        }
        saveFailureNotice = nil
        return true
    }

    /// The editor's "Clear date", committed (T-645). It wrote the container's blob and committed
    /// nothing, so the cleared date rode whatever unrelated save came next.
    ///
    /// Shaped like `toggleSectionArchive` rather than like `commitSectionEdits`: this is a discrete
    /// press with nothing under a caret, so a refusal genuinely can put everything back and say so.
    /// `editorHasDueDate` is restored with the blob — it is what draws the picker's Clear affordance,
    /// and a popover showing "no date" over a column that still has one is the report inverted.
    private func clearSectionDueDate() -> Bool {
        let hadDueDate = editorHasDueDate
        let undo = editSnapshot(settling: section)
        editorHasDueDate = false
        updateSection { config in
            config.dueDate = ""
        }
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: { undo?.restore() })
        } catch {
            editorHasDueDate = hadDueDate
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return false
        }
        saveFailureNotice = nil
        return true
    }

    /// The editor's "Delete Column", committed, and the popover closes only once the store has
    /// taken it (T-645).
    ///
    /// **Invisible to the `try? save()` rule, in all three of its halves.** A `TaskSectionConfig` is
    /// a struct inside the container's `sectionConfigsRaw` JSON, not a `@Model`, so no
    /// `modelContext.delete(` ever fires and half 1 and half 3 have nothing to see; and there was no
    /// `try?` for half 2 to key on, only `showEditor = false` reporting a delete that had not been
    /// committed at all.
    ///
    /// **`commitEdit` and not `commitDelete`, for the same reason.** Nothing is marked deleted in
    /// the context, so there is no row for `rollback()` to un-hide — and a rollback would discard
    /// the app's other pending work besides. The undo is the container's blob plus the `sectionName`
    /// of every card the move re-points, which is why the snapshot is taken over
    /// `KanbanSectionStateSupport.tasksMoving` — the same walk `moveTasks` performs, rather than a
    /// second one that agrees today.
    ///
    /// **It walks `filedCardName`, not `section.name` (T-713).** The rename writes the config on
    /// every keystroke and moves the cards only at the commit point, so a user who types and then
    /// presses Delete without committing has a column whose config already says `Doingxy` and whose
    /// cards still say `Doing`. Deleting on the config's name would find nothing to move and strand
    /// the whole stack under a column that no longer exists — the same damage the rename used to do,
    /// one control along.
    private func deleteSection() -> Bool {
        let undo = editSnapshotMovingTasks(outOf: filedCardName)
        moveTasks(from: filedCardName, to: TaskSectionDefaults.defaultName)
        removeSection()
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: { undo?.restore() })
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return false
        }
        saveFailureNotice = nil
        return true
    }

    private func moveTasks(from oldName: String, to newName: String) {
        KanbanSectionStateSupport.moveTasks(
            universeTasks: universeTasks,
            area: area,
            project: project,
            from: oldName,
            to: newName
        )
    }

    private func removeSection() {
        KanbanSectionStateSupport.removeSection(sectionID: section.id, area: area, project: project)
    }

    /// **The Default column has no lifecycle, and this is where every route to one converges** —
    /// the header glyph, the editor's "Mark Section Completed", and Cmd+Return over the hovered
    /// column. All three are gated at their own site so the affordance is never *offered*; this
    /// guard is what makes a fourth route safe by default rather than only the three that exist.
    ///
    /// The damage it prevents is not a no-op. `Area.normalizedSectionConfigs` /
    /// `Project.normalizedSectionConfigs` force `isCompleted` and `isArchived` false on Default on
    /// every read *and* every write, so the flag is discarded — but `saveSection` has already run
    /// `TaskContainerLifecycleService.completeRemainingActiveTasks` by then and marked every open
    /// card in the column done. The column re-renders Active with its cards gone, which is worse
    /// than either refusing or persisting: the tasks stay done and nothing on screen says so
    /// (`docs/TODO.md` T-268).
    private func toggleSectionCompletion() {
        guard section.supportsLifecycle else { return }
        sectionCompletionAnimationManager.toggleCompletion(
            for: section,
            getCurrent: currentSection,
            save: { _ = saveSection($0) }
        )
    }

    /// **Where a refused column write is reported when the popover is not there to report it
    /// (T-646).**
    ///
    /// `saveSection` has set `saveFailureNotice` since T-632, and the editor popover draws it — but
    /// two of the three routes into `toggleSectionCompletion` never open a popover at all (the
    /// header glyph and Cmd+Return over the hovered column), and the third *closes* it before the
    /// write happens. `SectionCompletionAnimationManager` writes a **reopen** synchronously and
    /// defers a **completion** behind a 2.5-second countdown on a detached `Task`, so a completion
    /// the store refuses is undone correctly — the column visibly stays active — and announced into
    /// a popover that went away two and a half seconds earlier. A notice drawn on a surface that is
    /// gone is not a report.
    ///
    /// So the column header draws the same notice while the editor is closed. **One flag and one
    /// write site, not two**: a second `@State` would need its own clearing rules and could
    /// disagree with the popover's about whether the last write landed. Reading it through
    /// `showEditor` is what keeps one refusal from being reported twice at once — while the popover
    /// is up it is the popover's, and the moment it closes the column takes it over.
    ///
    /// It clears the way the popover's does: `openSectionEditor()` clears it because a notice
    /// belongs to the attempt that produced it, and every successful column write clears it on the
    /// way out. Until then it stays up, which is correct — the column really did not save.
    private var columnFailureNotice: String? {
        if let reorderFailureNotice { return reorderFailureNotice }
        return showEditor ? nil : saveFailureNotice
    }

    private func currentSection() -> TaskSectionConfig? {
        if let area {
            return area.sectionConfigs.first(where: { $0.id == section.id })
        }
        if let project {
            return project.sectionConfigs.first(where: { $0.id == section.id })
        }
        return nil
    }

    /// Writes the column and commits it, answering `false` when the store refused (T-632).
    ///
    /// The `try? modelContext.save()` that used to end this function is the swallow both editor
    /// lifecycle buttons closed over, and it was invisible to the rule's Report half twice over:
    /// the report sits in `columnEditor`, a computed property nothing parsed, and `showEditor =
    /// false` was outside the vocabulary.
    ///
    /// **The undo is a field snapshot, never `modelContext.rollback()`** — `CadenceListEditSnapshot`
    /// carries the reason, and the leading one is that this app has a single `ModelContext`, so a
    /// rollback would discard pending work the board knows nothing about. It is the right shape
    /// here because the write is field edits only: the column lives in the container's
    /// `sectionConfigsRaw` blob, and `TaskContainerLifecycleService` settles through
    /// `CadenceTaskRecurrenceWorkflowSupport.settleWithoutAdvancingSeries`, which deliberately does
    /// **not** spawn a successor occurrence. There is nothing here to un-insert.
    @discardableResult
    private func saveSection(_ updatedSection: TaskSectionConfig) -> Bool {
        let current = currentSection()
        let undo = editSnapshot(settling: updatedSection)
        KanbanSectionStateSupport.saveSection(updatedSection: updatedSection, area: area, project: project)
        if updatedSection.isCompleted && current?.isCompleted != true {
            TaskContainerLifecycleService.completeRemainingActiveTasks(in: updatedSection, area: area, project: project, in: modelContext)
        } else if updatedSection.isArchived && !updatedSection.isCompleted && current?.isArchived != true {
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: updatedSection, area: area, project: project, in: modelContext)
        }
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: { undo?.restore() })
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return false
        }
        saveFailureNotice = nil
        return true
    }

    /// The column's container captured before a write, holding the open tasks a lifecycle settle
    /// can reach — the same set `TaskContainerLifecycleService` is about to walk, rather than a
    /// second walk that happens to agree today.
    ///
    /// `nil` only for a column belonging to neither an area nor a project, which the board does not
    /// draw; the callers spell that as "restore nothing" rather than as a refusal, because a write
    /// with no container to snapshot has no container to have changed either.
    private func editSnapshot(settling column: TaskSectionConfig) -> CadenceListEditSnapshot? {
        let settling = TaskContainerLifecycleService.remainingActiveTasks(in: column, area: area, project: project)
        if let area { return CadenceListEditSnapshot(area, tasks: settling) }
        if let project { return CadenceListEditSnapshot(project, tasks: settling) }
        return nil
    }

    /// The sibling of `editSnapshot(settling:)` for a write that **re-points** a column's cards
    /// instead of settling them (T-645). Two names rather than an overload: the repo's source scans
    /// anchor on `func <name>(`, so a second `editSnapshot(` silently changes what several existing
    /// tests read.
    ///
    /// The two differ only in which tasks they hand over, and the difference is the whole point:
    /// `settling` is `TaskContainerLifecycleService.remainingActiveTasks`, the open half a lifecycle
    /// choice reaches, while deleting a column moves its **whole** stack into Default. Snapshotting
    /// the open half of a delete would restore the cards that were still to do and leave the
    /// finished ones filed under a column that no longer exists.
    ///
    /// `nil` for a column belonging to neither an area nor a project, for the same reason as its
    /// sibling: the board does not draw one, and a write with no container to snapshot has no
    /// container to have changed.
    private func editSnapshotMovingTasks(outOf columnName: String) -> CadenceListEditSnapshot? {
        let moving = KanbanSectionStateSupport.tasksMoving(
            universeTasks: universeTasks,
            area: area,
            project: project,
            from: columnName
        )
        if let area { return CadenceListEditSnapshot(area, tasks: moving) }
        if let project { return CadenceListEditSnapshot(project, tasks: moving) }
        return nil
    }

    /// The editor's Archive / Unarchive button, and the popover now closes only once the store has
    /// taken it (T-632).
    ///
    /// It used to flip the flag, settle the column's open tasks, `try? modelContext.save()` and
    /// close — so the popover closing was the report of success, and it happened either way. On a
    /// refused commit the archive is undone, the notice appears under the buttons, and the popover
    /// stays open on the column that did not move.
    private func toggleSectionArchive() {
        let undo = editSnapshot(settling: section)
        var shouldCancelActiveTasks = false
        updateSection { config in
            let willArchive = !config.isArchived
            config.isArchived.toggle()
            shouldCancelActiveTasks = willArchive && !config.isCompleted
            if !config.isArchived {
                config.isCompleted = false
            }
        }
        if shouldCancelActiveTasks {
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: section, area: area, project: project, in: modelContext)
        }
        do {
            try CadencePendingChangePersistence.commitEdit(in: modelContext, undo: { undo?.restore() })
        } catch {
            saveFailureNotice = CadencePendingChangePersistence.editFailureNotice
            return
        }
        saveFailureNotice = nil
        showEditor = false
    }

    /// The editor's completion button, and the reason it tests a notice rather than a return value.
    ///
    /// **Reopening is synchronous; completing is not.** `SectionCompletionAnimationManager` writes
    /// a reopen immediately, straight through `saveSection`, and defers a *completion* behind a
    /// 2.5-second countdown drawn on the column itself. So a refused reopen is exactly the T-632
    /// defect — the column stayed completed with the editor gone and nothing on screen saying why —
    /// while a completion has nothing to have failed at yet by the time this returns. One flag
    /// covers both: it is set only when a commit was actually attempted and refused.
    private func toggleCompletionFromEditor() {
        toggleSectionCompletion()
        guard saveFailureNotice == nil else { return }
        showEditor = false
    }

    private var isPendingCompletion: Bool {
        sectionCompletionAnimationManager.isPending(section)
    }

    // `sectionDueDateIsOverdue` used to live here and is now
    // `CadenceBoardColumnDueDatePlan.isOverdue`, so the iOS board gets the same answer instead of
    // no answer at all (T-331).
}
#endif
