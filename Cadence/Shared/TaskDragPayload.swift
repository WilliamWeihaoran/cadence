import Foundation

/// Prefixed string payloads for task and bundle drags.
///
/// This existed as two files — `Shared/iOSTaskDragPayload.swift` under `#if os(iOS)` and
/// `macOS/Services/TaskDragPayload.swift` under `#if os(macOS)` — declaring the *same type name*
/// with byte-identical bodies and no compiler relationship between them. Since these strings are
/// the wire format between a drag source and a drop target, a change to one file would have
/// produced a platform whose drags silently stopped matching, with nothing to catch it. One
/// declaration, no fence.
///
/// The prefixes are load-bearing: each drag context uses its own so a drop target cannot accept a
/// payload from an unrelated context. See "Drag-to-Reorder Payload Prefixes" in `CLAUDE.md`.
///
/// `nonisolated` for the same reason `CadenceEmptyStateCopy` is: the project defaults value types
/// to the main actor, and the drop delegates that read these payloads run in `@Sendable` closures.
/// Parsing a prefix off a string is not main-actor work.
nonisolated enum TaskDragPayload {
    private static let listTaskPrefix = "listTask:"
    private static let bundlePrefix = "taskBundle:"

    static func string(for id: UUID) -> String {
        "\(listTaskPrefix)\(id.uuidString)"
    }

    static func bundleString(for id: UUID) -> String {
        "\(bundlePrefix)\(id.uuidString)"
    }

    /// A bare UUID is accepted because tasks dragged from `TasksPanel` onto the timeline carry no
    /// prefix. A bundle payload deliberately returns `nil` rather than its own id — asking for a
    /// task id and getting a bundle id back would be worse than getting nothing.
    static func taskID(from payload: String) -> UUID? {
        if payload.hasPrefix(listTaskPrefix) {
            return UUID(uuidString: String(payload.dropFirst(listTaskPrefix.count)))
        }
        if payload.hasPrefix(bundlePrefix) {
            return nil
        }
        return UUID(uuidString: payload)
    }

    /// The strict `listTask:` decode. `ListDetailView`'s rows are the remaining caller: it cannot
    /// use `taskID(from:)`, because that one accepts a **bare UUID** by
    /// design, and two surfaces really do emit one — the kanban card
    /// (`KanbanColumnSupportViews.swift:371`) and the month-grid task chip
    /// (`CalendarPageMonthSupportViews.swift:482`), both `.draggable(task.id.uuidString)`. A strict
    /// decode is what stops those reading as a reorder.
    ///
    /// Not `TasksPanel`, which an earlier draft of this comment named: its rows go through
    /// `TasksPanelSupport.taskDragPayload(for:)`, which calls `string(for:)` and is therefore
    /// prefixed. That error came out of `CLAUDE.md`'s drag-prefix table, which is stale on this
    /// point — a wrong doc propagating into source, which is the whole argument for checking a
    /// claim against the code before repeating it.
    ///
    /// The other caller was `InboxView`, which is gone: All Tasks and Inbox are one page
    /// (`TasksListView`) and it takes the lenient decode, because it then looks the id up in its
    /// own task universe — a stronger check than the prefix, since a foreign task fails the lookup.
    ///
    /// Both call sites hand-spelled the prefix and `dropFirst(9)` instead — the prefix's length as
    /// a literal, which is precisely the silent break this type exists to prevent.
    static func listTaskID(from payload: String) -> UUID? {
        guard payload.hasPrefix(listTaskPrefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(listTaskPrefix.count)))
    }

    static func bundleID(from payload: String) -> UUID? {
        guard payload.hasPrefix(bundlePrefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(bundlePrefix.count)))
    }
}
