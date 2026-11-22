import Foundation

/// The New Task composer's keyboard layer, as draft edits ([[T-13792]]). Static so each chord is
/// checked against a draft rather than inferred from a view.
///
/// **Shared since [[T-18540]]**: the Mac's `CreateTaskSheet` and the iPad's capture hosts (through
/// `iOSCaptureKeyboardCommands`) bind the same chords to these same edits. They are pure edits of
/// the shared `CadenceScheduleDraft`, and a hardware keyboard is the same input on both platforms
/// ([[T-8201]]), so nothing here is a Mac's own.
///
/// The date chords are the **task's**: an event's start is a range with an end to keep after it,
/// which the card's Starts row moves; a chord that cleared it would leave an event with no day.
enum CreateTaskKeyboardCommands {
    /// Cmd+T: today as the do date, or no do date when it is already today.
    static func toggleDoToday(_ draft: inout CadenceScheduleDraft, today: String = DateFormatters.todayKey()) {
        guard draft.kind == .task else { return }
        if draft.startDateKey == today {
            draft.clearDoDate()
        } else {
            setDoDate(&draft, to: today)
        }
    }

    /// Cmd+D: today as the due date, or none when it is already today.
    static func toggleDueToday(_ draft: inout CadenceScheduleDraft, today: String = DateFormatters.todayKey()) {
        guard draft.kind == .task else { return }
        draft.dueDateKey = draft.dueDateKey == today ? "" : today
    }

    /// Cmd+Shift+= / Cmd+Shift+-: the do date a day later or earlier, starting from today when
    /// there is none.
    static func nudgeDoDate(_ draft: inout CadenceScheduleDraft, by days: Int, today: String = DateFormatters.todayKey()) {
        guard draft.kind == .task else { return }
        let base = draft.startDateKey.isEmpty ? today : draft.startDateKey
        guard let day = DateFormatters.date(from: base),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        setDoDate(&draft, to: DateFormatters.dateKey(from: moved))
    }

    /// Cmd+P: the next priority, wrapping.
    ///
    /// [[T-14041]]: it steps from the priority the card SHOWS -- a `!`/`!!`/`!!!` in the title
    /// wins over `draft.priority`, as it does at creation -- and takes the mark out of the title,
    /// as the card's own priority picker does. It stepped `draft.priority` alone, so with `Call
    /// mom !!` typed every press changed a value the chip and the created task both ignored.
    static func cyclePriority(_ draft: inout CadenceScheduleDraft) {
        guard draft.kind == .task else { return }
        let all = TaskPriority.allCases
        let current = CadenceCaptureFieldInventory.priority(for: draft)
        let index = all.firstIndex(of: current) ?? 0
        if !draft.subject.isEditing, TaskTitleSupport.priorityShortcut(in: draft.title) != nil {
            draft.title = CadenceTaskComposerSupport.titleClearingPriorityMarker(draft.title)
        }
        draft.priority = all[(index + 1) % all.count]
    }

    /// A task's one day: start and end together, as the card's own Do grid writes it. A task with
    /// no do date stays untimed (`clearDoDate` left it all-day); one with a time keeps it.
    private static func setDoDate(_ draft: inout CadenceScheduleDraft, to key: String) {
        draft.startDateKey = key
        draft.endDateKey = key
    }
}
