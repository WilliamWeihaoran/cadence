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

    // MARK: - Subtask commit copy (T-634)

    /// The sentence the inspector's subtask field shows when its insert was refused.
    ///
    /// It stops at "Couldn't add this subtask." and does **not** promise "nothing was changed",
    /// which is the second sentence `CadencePendingChangePersistence.editFailureNotice` and
    /// `CadenceTaskMutationSupport.deleteFailureNotice` both carry. That promise is only ever true
    /// because an undo ran first; here the undo is the caller's own two lines — `commitInsert`
    /// deletes the row, and the surface puts `task.subtasks` back — so the shorter sentence is the
    /// one that stays honest if either half is ever dropped. Same reason
    /// `TaskCreationService.saveFailureNotice` is one clause long.
    static let subtaskAddFailureNotice = "Couldn't add this subtask."

    /// The delete-side sentence, and it *does* carry the second clause: `commitDelete` rolls the
    /// delete back and the surface restores the parent's array, so by the time this is read the
    /// subtask really is still there. Word for word `CadenceTaskMutationSupport.deleteFailureNotice`
    /// with the noun changed, because the two are the same event one level apart.
    static let subtaskDeleteFailureNotice = "Couldn't delete this subtask. Nothing was removed."

    // MARK: - Status actions

    /// The status transition that is not completion.
    ///
    /// Completion is the header control's job — one tap, exactly as every task row's circle. This
    /// covers the one status a checkbox cannot express, and it owns its value outright: no other
    /// control in the inspector can set `.cancelled`, and this one cannot set `.done`.
    ///
    /// **`.inProgress` was the second case and is gone ([[T-5015]] (b), owner decision 2026-10-24).**
    /// Removing it here is what retires In Progress as a *writable* status on both platforms in one
    /// edit: all three writers rendered this set — `iOSTaskStatusActionsSection`, the macOS
    /// inspector's `TaskDetailActionsSection` (an icon button there since [[T-6231]]) and the macOS
    /// note-embed `TaskEmbedFieldEditorPopover` —
    /// so none of them has a Start/Stop button any more and none of them had to be told separately.
    /// `TaskStatus.inProgress` itself stays: it is a persisted raw value and old rows must keep
    /// decoding. `CadenceInProgressStatusRetirement` is the launch pass that moves those rows to
    /// `.todo`, which is why dropping the writers strands nobody.
    ///
    /// A one-case enum rather than a plain function on purpose: the type is the shared *vocabulary*
    /// — copy, glyph, active state and undo target, written once and read by three surfaces — and
    /// that is as worth having for one action as it was for two.
    enum StatusAction: CaseIterable {
        case cancelled

        var status: TaskStatus {
            switch self {
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
            case .cancelled: isActive(current) ? "Restore" : "Cancel"
            }
        }

        func systemImage(for current: TaskStatus) -> String {
            switch self {
            case .cancelled: isActive(current) ? "arrow.uturn.backward.circle" : "xmark.circle"
            }
        }
    }
}
