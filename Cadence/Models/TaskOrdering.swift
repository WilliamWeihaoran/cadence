import Foundation

// MARK: - Sort vocabulary
//
// These two enums used to live inside `#if os(macOS)` in `macOS/Views/TasksPanelSupport.swift`,
// which put the app's canonical task ordering out of reach of the two targets that also order
// tasks: `CadenceWidgets` and `CadenceMCPServer`. Both compile `Models/`; neither compiles
// `Shared/` or `macOS/`. So the vocabulary and the comparator live here.
//
// The raw values are persisted (`@AppStorage("allTasksSortField")`, the per-list
// `_sortField` / `_sortDir` UserDefaults keys, `TasksPanel`'s `\(prefix)SortField`). Renaming a
// case is fine; changing a raw value silently resets every saved preference.

/// What a task list is ordered *by*. Presentation-level vocabulary; the ordering itself is
/// `TaskOrdering.precedes(_:_:field:direction:)`.
nonisolated enum TaskSortField: String, CaseIterable, Identifiable, Sendable {
    case custom = "Custom"
    case date = "Date"
    case priority = "Priority"
    var id: String { rawValue }
}

/// Orthogonal to `TaskSortField`, and deliberately so: `.priority` + `.ascending` means
/// low priority first, which is a real (if rarely chosen) macOS setting.
nonisolated enum TaskSortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending = "Ascending"
    case descending = "Descending"
    var id: String { rawValue }
}

// MARK: - The comparator

/// The one task ordering. Every macOS task list, the Today widget's timeline, and any future
/// consumer sort through this type.
///
/// `nonisolated` throughout because widget timeline providers run off the main actor and this
/// module defaults to `MainActor` isolation — the same reason `TaskPriority.rank` is
/// `nonisolated`.
nonisolated enum TaskOrdering {
    /// The "sorts after every real date" key for an empty `yyyy-MM-dd` string.
    ///
    /// Deliberately *not* a parseable date: it is only ever compared, never read back, and a
    /// spelling that cannot round-trip through `DateFormatters.ymd` is a spelling nobody can
    /// mistake for data. Two spellings were in use (`"9999-99-99"` and `"9999-12-31"`) across
    /// five files. They never met inside one comparator, so they never disagreed — but
    /// `"9999-99-99" > "9999-12-31"` lexically, so the first comparator to mix them would have
    /// sorted undated work into two different places.
    static let noDateSortKey = "9999-99-99"

    /// Maps an empty date key onto `noDateSortKey`, leaving real keys untouched.
    static func dateSortKey(_ dateKey: String) -> String {
        dateKey.isEmpty ? noDateSortKey : dateKey
    }

    /// The final tie-break, and the reason it is spelled once.
    ///
    /// A comparator without a total order gives an unstable sort: two rows that compare equal can
    /// swap places between renders, between launches, and between devices, for no reason visible
    /// on screen. `order` alone is *not* enough — `order` is assigned per container
    /// (`nextTaskOrder(in:)` maxes over one list), so tasks from different lists routinely share
    /// an `order`, and every cross-list surface (Today, All Tasks, the kanban list board) mixes
    /// them. `createdAt` then `title` then `id` closes it: `id` is unique, so this is total.
    static func fallbackPrecedes(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame { return titleComparison == .orderedAscending }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Returns true if `lhs` should sort before `rhs` under the given field and direction.
    static func precedes(
        _ lhs: AppTask,
        _ rhs: AppTask,
        field: TaskSortField,
        direction: TaskSortDirection
    ) -> Bool {
        switch field {
        case .custom:
            return fallbackPrecedes(lhs, rhs)
        case .date:
            let leftDate = dateSortKey(lhs.scheduledDate)
            let rightDate = dateSortKey(rhs.scheduledDate)
            if leftDate != rightDate {
                return direction == .ascending ? leftDate < rightDate : leftDate > rightDate
            }

            // Timed work leads untimed work on the same day in *both* directions. Reversing this
            // would put "sometime today" above "9am today" when the user asked for newest-first,
            // which reads as a bug rather than as a direction.
            let lhsTimed = lhs.scheduledStartMin >= 0
            let rhsTimed = rhs.scheduledStartMin >= 0
            if lhsTimed != rhsTimed { return lhsTimed }
            if lhsTimed, lhs.scheduledStartMin != rhs.scheduledStartMin {
                return direction == .ascending
                    ? lhs.scheduledStartMin < rhs.scheduledStartMin
                    : lhs.scheduledStartMin > rhs.scheduledStartMin
            }

            return fallbackPrecedes(lhs, rhs)
        case .priority:
            let lhsRank = lhs.priority.rank
            let rhsRank = rhs.priority.rank
            if lhsRank != rhsRank {
                return direction == .ascending ? lhsRank < rhsRank : lhsRank > rhsRank
            }
            return fallbackPrecedes(lhs, rhs)
        }
    }

    /// Ordering for a completed / logbook section: most recently finished first, then the same
    /// total tie-break as every other list.
    ///
    /// The `completedAt ?? createdAt` half was written out inline at six sites — Today's
    /// completed section, All Tasks, Inbox, list detail (twice), and the shared query support —
    /// and only one of them carried a tie-break at all. Cancelled tasks and tasks completed by a
    /// migration share a timestamp often enough for that to show.
    static func completionPrecedes(_ lhs: AppTask, _ rhs: AppTask) -> Bool {
        let lhsDate = lhs.completedAt ?? lhs.createdAt
        let rhsDate = rhs.completedAt ?? rhs.createdAt
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return fallbackPrecedes(lhs, rhs)
    }
}

extension Array where Element == AppTask {
    func taskSorted(by field: TaskSortField, direction: TaskSortDirection) -> [AppTask] {
        sorted { TaskOrdering.precedes($0, $1, field: field, direction: direction) }
    }

    /// Completed / logbook ordering. See `TaskOrdering.completionPrecedes`.
    func taskCompletionSorted() -> [AppTask] {
        sorted(by: TaskOrdering.completionPrecedes)
    }
}
