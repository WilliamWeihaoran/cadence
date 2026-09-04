#if os(macOS)
import SwiftUI

struct ListTasksGroup: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let tasks: [AppTask]
}

enum TaskListDisplayMetrics {
    static let headerHorizontalInset: CGFloat = 24
    static let taskLeadingInset: CGFloat = 52
    static let taskTrailingInset: CGFloat = 12
}

struct ListTasksGroupSectionView: View {
    let group: ListTasksGroup
    let isCollapsed: Bool
    let overdueCount: Int?
    let regularCount: Int
    @Binding var dragOverTaskID: UUID?
    let onToggle: () -> Void
    /// Answers whether the new order is in the store (T-869). `Void` until then, over a renumber
    /// that reached no commit — so the row below reported every drop as landed.
    let onReorderTask: (UUID, UUID) -> Bool

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: group.title,
                isCollapsed: isCollapsed,
                overdueCount: overdueCount,
                regularCount: regularCount,
                accent: group.accent,
                onToggle: onToggle
            )
            .padding(.horizontal, TaskListDisplayMetrics.headerHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(.init())

            if !isCollapsed {
                ForEach(group.tasks) { task in
                    TaskListInteractiveRow(
                        task: task,
                        // A list's own Tasks tab: every row would name the page you are on.
                        showsContainer: CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail),
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
    let onToggle: () -> Void

    var body: some View {
        Group {
            TaskListGroupHeader(
                title: "Completed",
                count: tasks.count,
                isCollapsed: isCollapsed,
                accent: Theme.green,
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
                        showsContainer: CadenceTaskSurfaceOptions.showsContainerChip(on: .listDetail)
                    )
                }
            }
        }
    }
}

struct TaskListGroupHeader<LeadingContent: View>: View {
    let title: String
    let isCollapsed: Bool
    let overdueCount: Int?
    /// `nil` suppresses the "N task(s)" capsule entirely, through the same function
    /// `CadenceTaskGroupHeading` asks — `CadenceTaskGroupHeadingMetrics.showsCapsule` (T-264). A
    /// group standing for reminders Cadence has not been allowed to look at does not know its own
    /// count, and `0` states a fact it does not have. Every group that always knows its size keeps
    /// passing a plain `Int`.
    let regularCount: Int?
    var accent: Color = Theme.dim
    var isToggleEnabled: Bool = true
    let onToggle: () -> Void
    @ViewBuilder let leadingContent: () -> LeadingContent

    init(
        title: String,
        isCollapsed: Bool,
        overdueCount: Int? = nil,
        regularCount: Int?,
        accent: Color = Theme.dim,
        isToggleEnabled: Bool = true,
        onToggle: @escaping () -> Void,
        @ViewBuilder leadingContent: @escaping () -> LeadingContent
    ) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.overdueCount = overdueCount
        self.regularCount = regularCount
        self.accent = accent
        self.isToggleEnabled = isToggleEnabled
        self.onToggle = onToggle
        self.leadingContent = leadingContent
    }

    init(
        title: String,
        count: Int,
        isCollapsed: Bool,
        accent: Color,
        isToggleEnabled: Bool = true,
        onToggle: @escaping () -> Void,
        @ViewBuilder leadingContent: @escaping () -> LeadingContent
    ) {
        self.init(
            title: title,
            isCollapsed: isCollapsed,
            overdueCount: nil,
            regularCount: count,
            accent: accent,
            isToggleEnabled: isToggleEnabled,
            onToggle: onToggle,
            leadingContent: leadingContent
        )
    }

    var body: some View {
        Button(action: { if isToggleEnabled { onToggle() } }) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 22)

                if isToggleEnabled {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 16, height: 20)
                } else {
                    Color.clear.frame(width: 16, height: 20)
                }

                leadingContent()

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if let overdueCount, overdueCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(overdueCount)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.red)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(Capsule())
                }

                // Same rule as the shared heading's, asked of the same function — see
                // `CadenceTaskGroupHeadingMetrics.showsCapsule`. The `let` after it is only the
                // unwrap; do not collapse the two back into a bare `if let regularCount`.
                // (`overdueCount` above is a *different* rule on purpose: a group that knows it is
                // zero days late is stating a fact, so it hides a flag it has no reason to raise.)
                if CadenceTaskGroupHeadingMetrics.showsCapsule(for: regularCount), let regularCount {
                    HStack(spacing: 4) {
                        Text("\(regularCount)")
                            .font(.system(size: 11, weight: .bold))
                        Text(regularCount == 1 ? "task" : "tasks")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.11))
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(accent.opacity(0.2), lineWidth: 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isToggleEnabled && !isCollapsed ? Theme.surface.opacity(0.28) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.borderSubtle.opacity(0.52))
                    .frame(height: 1)
                    .padding(.leading, 34)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.cadencePlain)
    }
}

extension TaskListGroupHeader where LeadingContent == EmptyView {
    init(
        title: String,
        isCollapsed: Bool,
        overdueCount: Int? = nil,
        regularCount: Int?,
        accent: Color = Theme.dim,
        isToggleEnabled: Bool = true,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            title: title,
            isCollapsed: isCollapsed,
            overdueCount: overdueCount,
            regularCount: regularCount,
            accent: accent,
            isToggleEnabled: isToggleEnabled,
            onToggle: onToggle,
            leadingContent: { EmptyView() }
        )
    }

    init(
        title: String,
        count: Int,
        isCollapsed: Bool,
        accent: Color,
        isToggleEnabled: Bool = true,
        onToggle: @escaping () -> Void
    ) {
        self.init(
            title: title,
            count: count,
            isCollapsed: isCollapsed,
            accent: accent,
            isToggleEnabled: isToggleEnabled,
            onToggle: onToggle,
            leadingContent: { EmptyView() }
        )
    }
}

struct TaskListDisplayRow: View {
    let task: AppTask
    var style: MacTaskRowStyle = .standard
    /// Forwarded to `MacTaskRow.showsContainer`. See there: the host asks
    /// `CadenceTaskSurfaceOptions.showsContainerChip(on:)` and this carries the answer down.
    var showsContainer: Bool = true
    var contexts: [Context] = []
    var areas: [Area] = []
    var projects: [Project] = []
    var leadingInset: CGFloat = TaskListDisplayMetrics.taskLeadingInset
    var trailingInset: CGFloat = TaskListDisplayMetrics.taskTrailingInset

    var body: some View {
        MacTaskRow(task: task, style: style, showsContainer: showsContainer, contexts: contexts, areas: areas, projects: projects)
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
    var style: MacTaskRowStyle = .standard
    /// See `TaskListDisplayRow.showsContainer`.
    var showsContainer: Bool = true
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
            style: style,
            showsContainer: showsContainer,
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
                        SectionEyebrowLabel(text: "\(doneTasks.count) completed")
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(doneTasks) { task in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.green)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.dim)
                                        .strikethrough(true, color: Theme.dim)
                                    if !task.dueDate.isEmpty {
                                        Text(task.dueDate)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.dim.opacity(0.6))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
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
