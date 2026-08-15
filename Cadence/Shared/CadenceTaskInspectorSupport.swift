import Foundation

/// The rules the task inspector runs on, shared by macOS's `TaskDetailPlacementBreadcrumb` and the
/// iOS task detail sheet.
///
/// Both platforms draw the same inspector — title row, tags, `List › Section` breadcrumb, schedule,
/// subtasks, notes, actions — and the decisions that shape it are arithmetic, not layout: whether a
/// section segment is worth a chevron, what a section with no name is called, whether there is any
/// logged time to report, and which status a button moves the task to. Every one of those was
/// previously spelled out inline in a view, on one platform only.
///
/// It lives here rather than in `Cadence/iOS/` because everything under that folder is inside
/// `#if os(iOS)` and therefore invisible to `CadenceTests`, which builds for macOS.
///
/// Main-actor isolated, like the `TaskSectionDefaults` and `CadenceTaskPresentationSupport` values
/// it reads; the callers are all views.
enum CadenceTaskInspectorSupport {

    // MARK: - Placement breadcrumb

    /// Whether the breadcrumb's `› Section` segment is worth drawing.
    ///
    /// A task in the Inbox has nowhere to be sectioned, so `Inbox › Default` would be a chevron
    /// pointing at a non-choice. The segment appears as soon as there is a section worth naming:
    /// more than one to pick from, or a single one the user actually named.
    static func showsSectionSegment(availableSections: [String]) -> Bool {
        let sections = availableSections
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sections.count > 1 { return true }
        guard let only = sections.first else { return false }
        return only.caseInsensitiveCompare(TaskSectionDefaults.defaultName) != .orderedSame
    }

    /// What the section segment says. An unset section reads as the real name of where the task
    /// actually is — `Default` — rather than "None": dimmer styling is what conveys "unset", so the
    /// segment and the picker it opens never disagree about the task's section.
    static func sectionSegmentTitle(_ sectionName: String) -> String {
        let trimmed = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? TaskSectionDefaults.defaultName : trimmed
    }

    /// What the container segment says when the task is in no list at all.
    static let inboxSegmentTitle = "Inbox"

    // MARK: - Logged time

    /// Logged time as text, or `nil` when there is none to report.
    ///
    /// Logged time is **measured**, not typed: the focus timer writes `AppTask.actualMinutes`, so
    /// the inspector reports it and offers no editor for it. macOS removed its "Actual" row for the
    /// same reason; iOS was still showing a minutes picker, which invited a user to overwrite a
    /// measurement by hand.
    static func loggedLabel(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        return CadenceTaskPresentationSupport.estimateLabel(minutes: minutes)
    }

    // MARK: - Status actions

    /// The two status transitions that are not completion.
    ///
    /// Completion is the header control's job — one tap, exactly as every task row's circle. These
    /// two cover the statuses a checkbox cannot express, and each one owns its value outright: no
    /// other control in the inspector can set `.inProgress` or `.cancelled`, and neither of these
    /// can set `.done`.
    enum StatusAction: CaseIterable {
        case inProgress
        case cancelled

        var status: TaskStatus {
            switch self {
            case .inProgress: .inProgress
            case .cancelled: .cancelled
            }
        }

        func isActive(_ current: TaskStatus) -> Bool {
            current == status
        }

        /// Tapping an active action returns the task to `.todo`, so each button is its own undo.
        func target(from current: TaskStatus) -> TaskStatus {
            isActive(current) ? .todo : status
        }

        /// The button says what the tap will *do*, not what the task currently is.
        func title(for current: TaskStatus) -> String {
            switch self {
            case .inProgress: isActive(current) ? "Stop" : "Start"
            case .cancelled: isActive(current) ? "Restore" : "Cancel"
            }
        }

        func systemImage(for current: TaskStatus) -> String {
            switch self {
            case .inProgress: isActive(current) ? "pause.circle" : "play.circle"
            case .cancelled: isActive(current) ? "arrow.uturn.backward.circle" : "xmark.circle"
            }
        }
    }
}
