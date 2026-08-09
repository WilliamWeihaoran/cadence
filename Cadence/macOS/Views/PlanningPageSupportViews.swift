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
///
/// Chrome is the shared board chrome: `BoardColumnHeader` (same dot, label, count, hairline as
/// the kanban and Calendar boards), `KanbanCard` for every card, and `KanbanColumnAddTaskRow`
/// last in the column. Planning does *not* use `KanbanColumnScroll` because its columns are
/// flexible-width and scroll with the page as a whole rather than individually — that is a
/// layout difference, not a styling one.
struct PlanningBucketColumn: View {
    let bucket: PlanningBucket
    let tasks: [AppTask]
    let isTargeted: Bool
    let onAddTask: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BoardColumnHeader(dotColor: bucket.dotColor, title: bucket.label, count: tasks.count)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tasks) { task in
                    KanbanCard(task: task, showsContainerChip: true)
                        .draggable(TasksPanelSupport.taskDragPayload(for: task))
                }

                // Must follow the last card directly. The column's `minHeight` means a short
                // bucket has slack below it — putting the spacer *after* the row pushes that
                // slack to the bottom of the column instead of pinning the row to the page floor.
                KanbanColumnAddTaskRow(isColumnHovered: isHovered, action: onAddTask)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
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
}

#endif
