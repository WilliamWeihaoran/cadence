#if os(macOS)
import SwiftUI
import SwiftData

/// A heading on a list's Tasks tab. `ListTasksDropGroup` is what the shared drop reads of it
/// ([[T-16682]]), so this tab and iOS's ask `ListTasksGroupDrop` the same questions.
struct ListTasksGroup: Identifiable, ListTasksDropGroup {
    let id: String
    let title: String
    let tasks: [AppTask]
    /// The heading's colour, handed to `CadenceTaskGroupHeading` ([[T-11214]]). `ListTasksView`
    /// passes it for every group it draws; `Theme.dim` is the answer for a group nobody coloured,
    /// the same fallback `CadenceTaskQuerySupport.sectionAccent(named:configs:)` gives a name no
    /// section config carries.
    var tint: Color = Theme.dim
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
    /// Files a task dropped on an EMPTY section's header under it, answering whether the store
    /// took it ([[T-15821]]).
    let onRefileTask: (UUID, ListTasksGroupDrop.Refiling) -> Bool

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
                      let droppedID = TaskDragPayload.listTaskID(from: payload)
                else { return false }
                if let targetID = ListTasksGroupDrop.headerDropTarget(droppedID: droppedID, in: group) {
                    return onReorderTask(droppedID, targetID)
                }
                // [[T-15821]]: an empty section has no first row to aim at.
                guard let refiling = ListTasksGroupDrop.emptySectionRefiling(in: group) else { return false }
                return onRefileTask(droppedID, refiling)
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

// `ListLogRowPresentation`, the eyebrow over this tab, lives in
// `Cadence/Shared/ListLogRowPresentation.swift` so iOS's Completed tab draws it too ([[T-14292]]).

/// A list's Completed tab.
///
/// **[[T-12791]]: its rows are the task row every other Mac task surface draws.** They were a
/// hand-rolled circle, struck title and due line with no action of any kind: no click opened the
/// task, the circle reopened nothing, and a right-click offered no menu. iOS's Completed tab
/// (`iOSListCompletedPanel`) draws `iOSTaskListRow`, the full row -- tap opens the task, the circle
/// reopens it, long-press brings the row's menu -- and so do the Mac's own folded Completed
/// sections one tab over (`ListTasksCompletedSectionView`) and on All Tasks. No pointer or screen
/// reason separated the tab from those (T-8201), so it reads `TaskListDisplayRow` too.
struct ListLogView: View {
    let tasks: [AppTask]
    /// The rows' lateness day ([[T-5012]]): `MacTaskRow` takes it with no default, and this tab's
    /// host hands it none.
    @State private var observedDay = CadenceObservedDay()

    private var todayKey: String { observedDay.todayKey }

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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Over the rows' completion circles: the row's own leading inset plus the
                        // row's own content padding.
                        SectionEyebrowLabel(text: ListLogRowPresentation.countLabel(for: doneTasks))
                            .padding(.horizontal, ListLogMetrics.rowInset + CadenceTaskRowMetrics.desktop.horizontalPadding)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(doneTasks) { task in
                            TaskListDisplayRow(
                                task: task,
                                // A list's own tab: every row would name the page you are on.
                                showsContainer: CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail),
                                todayKey: todayKey,
                                leadingInset: ListLogMetrics.rowInset,
                                trailingInset: ListLogMetrics.rowInset
                            )
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
        .cadenceTracksDayChanges($observedDay)
    }
}

/// The Completed tab's row inset. `TaskListDisplayMetrics.taskLeadingInset`'s 52 clears a group
/// header's disclosure chevron; this tab has no group and no chevron, so its rows take the
/// trailing inset on both sides.
enum ListLogMetrics {
    static let rowInset: CGFloat = TaskListDisplayMetrics.taskTrailingInset
}

#endif
