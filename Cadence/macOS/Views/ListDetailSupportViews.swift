#if os(macOS)
import SwiftUI
import SwiftData

struct ListTasksGroup: Identifiable {
    let id: String
    let title: String
    let tasks: [AppTask]
    /// The heading's colour, handed to `CadenceTaskGroupHeading` ([[T-11214]]). `ListTasksView`
    /// passes it for every group it draws; `Theme.dim` is the answer for a group nobody coloured,
    /// the same fallback `CadenceTaskQuerySupport.sectionAccent(named:configs:)` gives a name no
    /// section config carries.
    var tint: Color = Theme.dim
}

/// **[[T-5358]] — a row dropped into ANOTHER group on a list's Tasks tab joins that group.**
///
/// The tab's row drop only renumbered, so a task dragged from "Documents" onto a row under "Later"
/// took a new `order` and sprang straight back under Documents, with nothing said. All Tasks and
/// the section board both refile on the same gesture (`TasksPanelDropCoordinator.handleTaskDrop`
/// assigns its group's key, then reorders; `KanbanSectionColumnView.moveTask` files the card under
/// its column). This is that first half for this tab: what the target group means, written as one
/// commit before the reorder that `ListTasksView.reorderTask` already makes.
///
/// - By section: the group's section name — the configured spelling, which is the group's title.
/// - By priority: the target row's priority, the `priority:` key All Tasks reads.
/// - By date: `TasksListView.dateDropKey(forGroupID:)`, so Do Today / Scheduled / Unscheduled move
///   a task exactly as they do on All Tasks, and Overdue / Due Today — a day already gone, with no
///   assignment that makes a task late — reorder only, as they do there.
enum ListTasksGroupDrop {
    enum Refiling: Equatable {
        case section(String)
        case dropKey(String)
    }

    /// `nil` when the drop stays inside its own group, or the group names nothing a task can be
    /// moved into — the drop is then the plain reorder it always was.
    static func refiling(
        dropping dropped: AppTask,
        onto target: AppTask,
        in group: ListTasksGroup,
        groupingMode: TaskGroupingMode
    ) -> Refiling? {
        guard !group.tasks.contains(where: { $0.id == dropped.id }) else { return nil }
        switch groupingMode {
        case .none:
            return nil
        case .byList:
            return .section(group.title)
        case .byPriority:
            return target.priority == dropped.priority ? nil : .dropKey("priority:\(target.priority.rawValue)")
        case .byDate:
            return TasksListView.dateDropKey(forGroupID: group.id).map(Refiling.dropKey)
        }
    }

    /// **[[T-5840]] — a drop on a group's HEADER joins that group, at its top.** The header had no
    /// drop destination, so a task let go over "Later" itself, with no row under the pointer, was
    /// not taken at all. A header drop is answered as a drop on the group's first row: the same
    /// refiling as a row drop (`refiling(dropping:onto:in:groupingMode:)` reads that row's priority,
    /// which is the group's, since every row of a priority group shares it), then the renumber puts
    /// the task first in the group — the place a drop just under a heading means. Going through the
    /// row path keeps one commit order and one failure notice for both drop sites.
    ///
    /// `nil` — the header refuses the drop — when the task is already in this group, or the group
    /// names nothing a task can be moved into (the ungrouped "Tasks" group; Overdue / Due Today by
    /// date). A header that only renumbered would answer a drop the user aimed at a group by leaving
    /// the task out of it, which is the silent accept T-591 removed from All Tasks' headers.
    ///
    /// **Asked of the group's id, not of a grouping mode**, because the id already says which kind
    /// of group this is — `CadenceTaskQuerySupport` spells section groups `section-…`, priority
    /// groups `priority-…` and the date buckets by name — and the header view is handed the group,
    /// not the page's grouping. `ListTasksGroupDropTests` builds its groups with those same
    /// functions, so a renamed id reddens there rather than turning every header off.
    static func headerDropTarget(droppedID: UUID, in group: ListTasksGroup) -> UUID? {
        guard let first = group.tasks.first,
              !group.tasks.contains(where: { $0.id == droppedID }) else { return nil }
        let refiles = group.id.hasPrefix("section-")
            || group.id.hasPrefix("priority-")
            || TasksListView.dateDropKey(forGroupID: group.id) != nil
        return refiles ? first.id : nil
    }

    /// Writes the refiling as one commit. `false` means the store refused it and every field is
    /// back as it was (`CadenceTaskFieldEditCommit` / `TasksPanelSupport.assignTask` undo it), so
    /// the caller must not go on to reorder a row the store still files in its old group.
    static func refile(
        _ task: AppTask,
        _ refiling: Refiling,
        todayKey: String,
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> Bool {
        switch refiling {
        case .section(let name):
            return CadenceTaskFieldEditCommit.commit(task, in: modelContext, commit: commit) {
                task.sectionName = name
            }
        case .dropKey(let key):
            return TasksPanelSupport.assignTask(
                task,
                for: key,
                todayKey: todayKey,
                areas: [],
                projects: [],
                modelContext: modelContext,
                commit: commit
            ) == .applied
        }
    }
}

enum TaskListDisplayMetrics {
    static let headerHorizontalInset: CGFloat = 24
    static let taskLeadingInset: CGFloat = 52
    static let taskTrailingInset: CGFloat = 12
}

struct ListTasksGroupSectionView: View {
    let group: ListTasksGroup
    let isCollapsed: Bool
    /// `ListTasksView`'s observed day, for the rows' lateness ([[T-5012]]).
    let todayKey: String
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    /// Answers whether the new order is in the store (T-869). `Void` until then, over a renumber
    /// that reached no commit — so the row below reported every drop as landed.
    let onReorderTask: (UUID, UUID) -> Bool

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: group.title,
                tint: group.tint,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            // [[T-5840]]: a task let go over the header joins the group, as on All Tasks.
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first,
                      let droppedID = TaskDragPayload.listTaskID(from: payload),
                      let targetID = ListTasksGroupDrop.headerDropTarget(droppedID: droppedID, in: group)
                else { return false }
                return onReorderTask(droppedID, targetID)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(group.tasks) { task in
                    TaskListInteractiveRow(
                        task: task,
                        // A list's own Tasks tab: every row would name the page you are on.
                        showsContainer: CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail),
                        todayKey: todayKey,
                        dragOverTaskID: $dragOverTaskID,
                        taskDragPayload: { TaskDragPayload.string(for: $0.id) },
                        onDropOnTaskPayload: { payload, targetTask in
                            guard let droppedID = TaskDragPayload.listTaskID(from: payload),
                                  droppedID != targetTask.id else { return false }
                            return onReorderTask(droppedID, targetTask.id)
                        }
                    )
                }
            }
        }
    }
}

struct ListTasksCompletedSectionView: View {
    let tasks: [AppTask]
    let isCollapsed: Bool
    /// See `ListTasksGroupSectionView.todayKey`.
    let todayKey: String
    let onToggle: () -> Void

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: "Completed",
                // iOS's list Tasks tab heads the same section in the same green.
                tint: Theme.green,
                isCollapsed: isCollapsed,
                onToggle: onToggle
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(tasks) { task in
                    TaskListDisplayRow(
                        task: task,
                        showsContainer: CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail),
                        todayKey: todayKey
                    )
                }
            }
        }
    }
}

/// macOS's task-group header: the disclosure chevron and the group's name.
///
/// **The name is the shared `CadenceTaskGroupHeading` (T-11214).** It was a 14pt bold
/// `Theme.text` title of its own, so the Mac headed every task group — Today, All Tasks, Inbox and
/// a list's Tasks tab — in a different vocabulary from the iOS pages beside it, which draw the
/// shared eyebrow tinted per group: "Tasks" blue, "Apple Reminders" purple, "Completed" green, a
/// list or section in its own colour. No input or screen constraint separated the two (T-8201),
/// and T-605's reason for keeping Today on this header — one desktop app, one heading — still
/// holds, because every desktop group heading moved together. What stays here is the Mac's
/// furniture around the shared row: the chevron and the click that folds the group (every group
/// folds, decided for both platforms on T-11214; iOS's half is T-12191). The tint colours the
/// heading's text, never a bar, which is the line T-2084 drew.
///
/// **The accent bar is gone, and the space it held is reclaimed (T-2084).** Every section on this
/// page, on All Tasks and on Inbox opened with a 3×22pt rounded rectangle in the group's colour,
/// and the owner's reading of the page was that *"these colors make the page very distracting"* —
/// the same sentence that took the sidebar's list bars. Nothing replaces it: not a grey bar, not a
/// dot. Unlike the sidebar's, this bar was a real `HStack` child with 10pt of spacing after it, so
/// its removal pulls the rest of the header **13pt leftward**, which is the reclaimed space the
/// owner asked for. The `accent` parameter went with the drawing rather than being left inert —
/// the colour is still the list's, still chosen in the list editor, and since T-11214 it tints the
/// heading's text.
///
/// **It does not say how many rows are under it any more (T-2056).** The capsule read "2 tasks",
/// in the group's accent inside a bordered pill, and the owner asked for the per-section count
/// gone on iOS and iPadOS and then on macOS too, so that the two platforms keep saying the same
/// thing about the same group. The `taskCount` parameter went with the drawing rather than being
/// left inert, and so did the shared `showsCapsule` rule it asked — T-264's answer to when a count
/// may be drawn at all, which a heading that draws none cannot break. macOS's own
/// Today had already stopped passing a count (`TasksPanelIntentSectionView`); this is the rest of
/// the desktop catching up with it.
///
/// **The Mac-only furniture is gone too ([[T-12193]]).** After T-11214 shared the title, the header
/// still drew four things iOS's does not: a red overdue flag capsule, a leading slot's list and
/// context glyphs on All Tasks By List, a `Theme.surface` fill while expanded, and a hairline
/// under every heading. None answers a pointer, hover, keyboard or width constraint (T-8201), so
/// each unified -- toward iOS, because iOS is the side the owner's own words point at: T-1495 took
/// "these pills" (the overdue flag among them) off Today's headings, T-2056 took the remaining
/// count off every heading on every platform, and T-2084 took the colour bars, leaving a heading
/// that is a chevron and a tinted name. Lateness is not lost: every late row still draws its own
/// red due pill. The glyphs restated what the tinted list name already says; the fill was a second
/// state layer the chevron already states; the hairline was a separator iOS's 22pt group gap does
/// without. `TasksPanelSupport`'s overdue counter and the capsule's VoiceOver label went with the
/// drawing rather than being left inert.
struct TaskListGroupHeader: View {
    let title: String
    /// The group's colour, which `CadenceTaskGroupHeading` draws the title in. Required, so every
    /// call site says which colour its group is rather than inheriting a default.
    let tint: Color
    let isCollapsed: Bool
    var isToggleEnabled: Bool = true
    let onToggle: () -> Void

    /// **What VoiceOver hears (T-7008).** A collapsible group is a button that states its own
    /// state, the value iOS's completed-section header already gives. A group that cannot collapse
    /// (the Inbox's "Apple Reminders" heading) is no longer a `Button` whose action does nothing:
    /// it is plain text carrying the header trait, so VoiceOver offers a heading, not a dead control.
    @ViewBuilder
    var body: some View {
        if isToggleEnabled {
            Button(action: onToggle) { headerContent }
                .buttonStyle(.cadencePlain)
                .accessibilityValue(TaskListGroupHeaderAccessibility.value(isCollapsed: isCollapsed))
        } else {
            headerContent
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var headerContent: some View {
        HStack(spacing: 10) {
            if isToggleEnabled {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 16, height: 20)
            } else {
                Color.clear.frame(width: 16, height: 20)
            }

            CadenceTaskGroupHeading(title: title, tint: tint)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The words `TaskListGroupHeader` speaks to VoiceOver (T-7008), outside the view so a test can
/// read them without building one.
enum TaskListGroupHeaderAccessibility {
    /// "Expanded" / "Collapsed", the same words iOS's `iOSTaskGroupDisclosure` states.
    static func value(isCollapsed: Bool) -> String {
        isCollapsed ? "Collapsed" : "Expanded"
    }
}

struct TaskListDisplayRow: View {
    let task: AppTask
    /// Forwarded to `MacTaskRow.showsContainer`. See there: the host asks
    /// `CadenceTaskSurfaceOptions.showsContainerChip(on:)` and this carries the answer down.
    var showsContainer: Bool = true
    /// Forwarded to `MacTaskRow.dayAlreadyStatedBySurface`. See there.
    var dayAlreadyStatedBySurface: String? = nil
    /// Forwarded to `MacTaskRow.todayKey`: the host's observed day ([[T-5012]]).
    let todayKey: String
    var contexts: [Context] = []
    var areas: [Area] = []
    var projects: [Project] = []
    var leadingInset: CGFloat = TaskListDisplayMetrics.taskLeadingInset
    var trailingInset: CGFloat = TaskListDisplayMetrics.taskTrailingInset

    var body: some View {
        MacTaskRow(
            task: task,
            showsContainer: showsContainer,
            dayAlreadyStatedBySurface: dayAlreadyStatedBySurface,
            todayKey: todayKey,
            contexts: contexts,
            areas: areas,
            projects: projects
        )
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .transition(.asymmetric(
                insertion: .opacity,
                removal: .opacity.combined(with: .move(edge: .top))
            ))
    }
}

/// The primary macOS task row wherever a task can be dragged, dropped onto, or reordered: list
/// detail, All Tasks, and — since T-608 — Today, which used to re-implement this whole chain around
/// its own `MacTaskRow`.
///
/// **The overlay goes over the *padded* row, and that ordering is the reason Today's copy was worth
/// removing rather than keeping.** `TaskListDisplayRow` applies the insets; the indicator is padded
/// by the same two figures on top of that, so it spans exactly the row's content. Pad again out
/// here and the indicator is inset twice — which is what Today drew, 16pt in from the row it was
/// pointing at, on both sides. Pinned by
/// `CadenceTodayUnificationTests.todaysRowsAreTheSharedInteractiveRowAtThePanelsOwnInsets`.
///
/// The insets are parameters because the two surfaces genuinely disagree: 52 clears a list detail's
/// leading furniture, and Today's rows sit directly under a 16pt panel heading. The default is the
/// list detail's, so a caller that needs the other one has to say so.
struct TaskListInteractiveRow: View {
    let task: AppTask
    /// See `TaskListDisplayRow.showsContainer`.
    var showsContainer: Bool = true
    /// See `MacTaskRow.dayAlreadyStatedBySurface`.
    var dayAlreadyStatedBySurface: String? = nil
    /// See `MacTaskRow.todayKey`.
    let todayKey: String
    var contexts: [Context] = []
    var areas: [Area] = []
    var projects: [Project] = []
    var leadingInset: CGFloat = TaskListDisplayMetrics.taskLeadingInset
    var trailingInset: CGFloat = TaskListDisplayMetrics.taskTrailingInset
    @Binding var dragOverTaskID: UUID?
    let taskDragPayload: (AppTask) -> String
    let onDropOnTaskPayload: (String, AppTask) -> Bool

    var body: some View {
        TaskListDisplayRow(
            task: task,
            showsContainer: showsContainer,
            dayAlreadyStatedBySurface: dayAlreadyStatedBySurface,
            todayKey: todayKey,
            contexts: contexts,
            areas: areas,
            projects: projects,
            leadingInset: leadingInset,
            trailingInset: trailingInset
        )
        .overlay(alignment: .top) {
            if dragOverTaskID == task.id {
                Rectangle()
                    .fill(Theme.blue)
                    .frame(height: 2)
                    .padding(.leading, leadingInset)
                    .padding(.trailing, trailingInset)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: dragOverTaskID)
        .draggable(taskDragPayload(task))
        .dropDestination(for: String.self) { items, _ in
            guard let payload = items.first else { return false }
            return onDropOnTaskPayload(payload, task)
        } isTargeted: { isOver in
            if isOver {
                dragOverTaskID = task.id
            } else if dragOverTaskID == task.id {
                dragOverTaskID = nil
            }
        }
    }
}

/// **[[T-6995]] — what one row of a list's Completed tab says.**
///
/// The tab used to hand-roll its row: a green `checkmark.circle.fill` for every task in it,
/// cancelled ones included; `task.title` raw, so a title of spaces drew a struck-through blank
/// line; and `task.dueDate` raw, so the line under the title read `2026-10-19` with nothing to
/// say it was the deadline. Every other Mac task surface already answers each of those through
/// the shared helpers, so this reads them too rather than spelling a fourth answer.
enum ListLogRowPresentation {
    static func title(for task: AppTask) -> String {
        TaskTitleSupport.displayTitle(task.title)
    }

    /// The same symbol and tint the task row's completion control settles on.
    static func glyph(for task: AppTask) -> CadenceTaskCompletionGlyph {
        CadenceTaskCompletionGlyph.resolve(task: task)
    }

    /// What the glyph says to VoiceOver ([[T-7084]]): the eyebrow's own two words. The green tick
    /// and the grey cross were the only thing telling a finished task from a canceled one, and
    /// VoiceOver read neither.
    static func statusLabel(for task: AppTask) -> String {
        task.isCancelled ? "Canceled" : "Completed"
    }

    /// `"Due Tomorrow"`, `"Due Oct 19"` — the spelling Cmd+K and Focus already use — or nil.
    static func dueLine(for task: AppTask) -> String? {
        guard !task.dueDate.isEmpty else { return nil }
        return "Due \(CadenceTaskPresentationSupport.dueDateLabel(for: task))"
    }

    /// The eyebrow over the rows. It counted cancelled tasks as "completed"; it now names both
    /// when both are there.
    static func countLabel(for tasks: [AppTask]) -> String {
        let cancelled = tasks.filter(\.isCancelled).count
        let completed = tasks.count - cancelled
        switch (completed, cancelled) {
        case (_, 0): return "\(completed) completed"
        case (0, _): return "\(cancelled) canceled"
        default: return "\(completed) completed, \(cancelled) canceled"
        }
    }
}

struct ListLogView: View {
    let tasks: [AppTask]

    private var doneTasks: [AppTask] {
        tasks.filter { $0.isDone || $0.isCancelled }.taskCompletionSorted()
    }

    var body: some View {
        ZStack {
            Theme.bg

            if doneTasks.isEmpty {
                EmptyStateView(
                    message: CadenceEmptyStateCopy.completedTasksTitle,
                    subtitle: CadenceEmptyStateCopy.completedTasksSubtitle,
                    icon: "checkmark.circle"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionEyebrowLabel(text: ListLogRowPresentation.countLabel(for: doneTasks))
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(doneTasks) { task in
                            let glyph = ListLogRowPresentation.glyph(for: task)
                            HStack(spacing: 10) {
                                // [[T-8411]]: the drawn circle every completion control uses,
                                // not an SF Symbol stamp of the same state.
                                CadenceTaskCompletionCircle(glyph: glyph, diameter: 14)
                                    .accessibilityLabel(ListLogRowPresentation.statusLabel(for: task))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ListLogRowPresentation.title(for: task))
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.dim)
                                        .strikethrough(true, color: Theme.dim)
                                        .lineLimit(2)
                                    if let dueLine = ListLogRowPresentation.dueLine(for: task) {
                                        Text(dueLine)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.dim.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Theme.borderSubtle.opacity(0.4)).frame(height: 0.5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearAppEditingFocus()
                }
        )
    }
}

#endif
