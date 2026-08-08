#if os(macOS)
import Foundation
import SwiftData
import SwiftUI

// MARK: - Buckets

/// The mutation a Planning drop performs. Every accepted drop changes the task's **do date**,
/// which is the one field the page buckets on — so every drop visibly moves the card.
enum PlanningDropAction: Equatable {
    case setDoDate(String)
    case clearDoDate
}

/// The five date buckets the global Planning page splits open work into.
enum PlanningBucket: String, CaseIterable, Identifiable {
    case overdue
    case today
    case thisWeek
    case later
    case unscheduled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue:     return "OVERDUE"
        case .today:       return "TODAY"
        case .thisWeek:    return "THIS WEEK"
        case .later:       return "LATER"
        case .unscheduled: return "UNSCHEDULED"
        }
    }

    var dotColor: Color {
        switch self {
        case .overdue:     return Theme.red
        case .today:       return Theme.amber
        case .thisWeek:    return Theme.blue
        case .later:       return Theme.purple
        case .unscheduled: return Theme.dim
        }
    }

    /// Overdue is derived from a do date already in the past, and backdating a task is never
    /// what a drag means — so the column refuses drops rather than accepting one and no-oping.
    /// Must stay in agreement with `dropAction(todayKey:)` returning `nil`.
    var acceptsDrops: Bool {
        self != .overdue
    }

    /// What dropping a card into this bucket writes to the task. `nil` means the bucket
    /// refuses drops outright — the drop destination is never installed for it.
    func dropAction(todayKey: String) -> PlanningDropAction? {
        switch self {
        case .overdue:
            return nil
        case .today:
            return .setDoDate(todayKey)
        case .thisWeek:
            return .setDoDate(PlanningBucket.dateKey(offsetDays: 1, from: todayKey))
        case .later:
            return .setDoDate(PlanningBucket.dateKey(offsetDays: 8, from: todayKey))
        case .unscheduled:
            return .clearDoDate
        }
    }

    /// Do date to seed the task creation sheet with from this column's add affordance.
    func seedDoDateKey(todayKey: String) -> String {
        switch self {
        case .unscheduled:
            return ""
        case .overdue, .today:
            return todayKey
        case .thisWeek:
            return PlanningBucket.dateKey(offsetDays: 1, from: todayKey)
        case .later:
            return PlanningBucket.dateKey(offsetDays: 8, from: todayKey)
        }
    }

    // MARK: Bucketing

    /// The earliest date this task is anchored to (do date or due date), if any.
    /// Used for *ordering* cards and for the "late" badge — never for bucketing.
    static func anchorKey(for task: AppTask) -> String? {
        [task.scheduledDate, task.dueDate]
            .filter { !$0.isEmpty }
            .min()
    }

    /// Buckets **strictly by do date**. Planning answers "when will I work on this", so the
    /// due date must not influence which column a card lands in — otherwise dropping a card
    /// writes a new do date and the due date silently pulls it back to its old column.
    /// A task that is late by its *due* date still shows the red "Nd late" badge wherever it sits.
    ///
    /// The cases are mutually exclusive and exhaustive over `doDate`:
    /// empty → unscheduled; `< today` → overdue; `== today` → today;
    /// `today+1 ... today+7` (`<= weekEndKey`) → thisWeek; `> today+7` → later.
    static func bucket(for task: AppTask, todayKey: String, weekEndKey: String) -> PlanningBucket {
        let doDate = task.scheduledDate

        guard !doDate.isEmpty else { return .unscheduled }
        if doDate < todayKey { return .overdue }
        if doDate == todayKey { return .today }
        return doDate <= weekEndKey ? .thisWeek : .later
    }

    static func weekEndKey(from todayKey: String) -> String {
        dateKey(offsetDays: 7, from: todayKey)
    }

    /// Whole days a task is past its earliest date, or `nil` if it is not late.
    static func daysLate(for task: AppTask, todayKey: String) -> Int? {
        guard let anchor = anchorKey(for: task), anchor < todayKey,
              let anchorDate = DateFormatters.date(from: anchor),
              let today = DateFormatters.date(from: todayKey) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: anchorDate, to: today).day ?? 0
        return days > 0 ? days : nil
    }

    private static func dateKey(offsetDays: Int, from todayKey: String) -> String {
        guard let today = DateFormatters.date(from: todayKey),
              let shifted = Calendar.current.date(byAdding: .day, value: offsetDays, to: today) else {
            return todayKey
        }
        return DateFormatters.dateKey(from: shifted)
    }
}

// MARK: - Column

/// A single planning column. Deliberately has no background and no border — cards sit
/// straight on the canvas and columns are separated by whitespace alone.
struct PlanningBucketColumn: View {
    let bucket: PlanningBucket
    let tasks: [AppTask]
    let todayKey: String
    let isTargeted: Bool
    let onAddTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            columnHeader

            ForEach(tasks) { task in
                PlanningCardView(task: task, todayKey: todayKey)
            }

            // Must follow the last card directly. The column's `minHeight` means a short
            // bucket has slack below it — putting the spacer *after* the button pushes that
            // slack to the bottom of the column instead of pinning the button to the page floor.
            PlanningAddTaskButton(action: onAddTask)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        bucket.dotColor.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                    .padding(-6)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(bucket.dotColor)
                .frame(width: 6, height: 6)

            Text(bucket.label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("\(tasks.count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Card

struct PlanningCardView: View {
    @Bindable var task: AppTask
    let todayKey: String

    @Environment(\.modelContext) private var modelContext
    @Environment(DeleteConfirmationManager.self) private var deleteConfirmationManager
    @Environment(HoveredTaskManager.self) private var hoveredTaskManager
    @Environment(HoveredEditableManager.self) private var hoveredEditableManager

    @State private var isHovered = false
    @State private var showTaskInspector = false

    /// Namespaced the same way `MacTaskRow` / `KanbanCardView` namespace theirs, so a card
    /// visible on two surfaces at once can't unregister the other's hover entry.
    private var editableID: String { "planning-task-\(task.id.uuidString)" }

    var body: some View {
        Button {
            showTaskInspector = true
        } label: {
            HStack(alignment: .top, spacing: 7) {
                PlanningCompletionCircle(task: task)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    metadataRow
                }

                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Same neutral hover as `MacTaskRow` / `KanbanCardView`: a plain raise to
            // `Theme.surfaceElevated` with a `Theme.borderSubtle` hairline — no list, priority,
            // or urgency hue in the wash.
            .background(TaskHoverVisuals.cardFill(isHovered: isHovered))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            }
        }
        .buttonStyle(.cadencePlain)
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
            // A card can be dragged into another bucket (or completed away) while the pointer
            // is still over it, so `.onHover(false)` never fires. Without this the managers keep
            // pointing at a row that no longer exists and the shortcuts act on a stale task.
            guard isHovered else { return }
            isHovered = false
            endHoverRegistration()
        }
        .overlay {
            RightClickActionTrigger {
                showTaskInspector = true
            }
        }
        .draggable(TasksPanelSupport.taskDragPayload(for: task))
        .popover(isPresented: $showTaskInspector, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
        }
    }

    // MARK: - Hover registration

    /// The hovered-task shortcuts (Cmd+Delete / Cmd+Return / Cmd+E / Cmd+T / Cmd+D / Cmd+P /
    /// Cmd+S / Cmd+/) are all driven off these two managers — a surface that never registers
    /// is a surface where every one of them silently no-ops.
    private func beginHoverRegistration() {
        hoveredTaskManager.beginHovering(task, source: .list)
        hoveredEditableManager.beginHovering(id: editableID) {
            showTaskInspector = true
        } onDelete: {
            deleteConfirmationManager.present(
                title: "Delete Task?",
                message: "This will permanently delete \"\(task.title.isEmpty ? "Untitled" : task.title)\"."
            ) {
                if hoveredTaskManager.hoveredTask?.id == task.id {
                    hoveredTaskManager.hoveredTask = nil
                }
                hoveredEditableManager.endHovering(id: editableID)
                modelContext.deleteTask(task)
            }
        }
    }

    private func endHoverRegistration() {
        hoveredTaskManager.endHovering(task)
        hoveredEditableManager.endHovering(id: editableID)
    }

    @ViewBuilder
    private var metadataRow: some View {
        // Computed for every column, not just OVERDUE: now that bucketing ignores the due
        // date, a past-due task can sit in TODAY / THIS WEEK / UNSCHEDULED and must keep its alarm.
        let daysLate = PlanningBucket.daysLate(for: task, todayKey: todayKey)

        HStack(spacing: 5) {
            Image(systemName: containerIcon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(containerTint)

            if !task.containerName.isEmpty {
                Text(task.containerName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            // App-wide rule: a task that *has* a due date always shows it, on every surface.
            // The "Nd late" badge is not a substitute — it says the task is late, not when it
            // was due, and it never appears at all for a task due today or in the future.
            if !task.dueDate.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8, weight: .semibold))
                    Text(DateFormatters.relativeDate(from: task.dueDate))
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(dueDateTint)
                .lineLimit(1)
                .fixedSize()
            }

            if let daysLate {
                Text("\(daysLate)d late")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.red)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// Same urgency convention as `MacTaskRow` and the kanban card: overdue reads red,
    /// due today reads amber, everything else stays quiet.
    private var dueDateTint: Color {
        guard !task.isDone, !task.isCancelled else { return Theme.dim }
        if task.dueDate < todayKey { return Theme.red }
        if task.dueDate == todayKey { return Theme.amber }
        return Theme.dim
    }

    private var containerIcon: String {
        task.area?.icon ?? task.project?.icon ?? "tray"
    }

    private var containerTint: Color {
        task.containerName.isEmpty ? Theme.dim : Color(hex: task.containerColor)
    }
}

/// App-wide rule: the completion circle's outline encodes task priority.
/// Kept as its own view so only this fragment re-renders on completion animation ticks.
private struct PlanningCompletionCircle: View {
    @Bindable var task: AppTask
    @Environment(TaskCompletionAnimationManager.self) private var manager

    var body: some View {
        Button {
            manager.toggleCompletion(for: task)
        } label: {
            TimelineView(.animation) { context in
                TaskCompletionProgressGlyph(
                    icon: icon,
                    color: color,
                    progress: manager.isPending(task) ? manager.progress(for: task, now: context.date) : nil,
                    size: 12,
                    lineWidth: 1.5
                )
            }
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
    }

    private var icon: String {
        if task.isDone { return "checkmark.circle.fill" }
        return "circle"
    }

    private var color: Color {
        if task.isDone || manager.isPending(task) { return Theme.green }
        return Theme.priorityColor(task.priority)
    }
}

// MARK: - Add affordance

/// Quiet at rest, full strength on hover.
struct PlanningAddTaskButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add task")
                    .font(.system(size: 10, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.dim)
            .opacity(isHovered ? 1 : 0.45)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cadencePlain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
#endif
