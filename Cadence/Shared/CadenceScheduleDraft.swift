import Foundation

/// The two things the shared schedule panel can be editing.
///
/// **Deliberately two cases, not three.** `iOSCalendarQuickCreateKind` carries a `.bundle` arm as
/// well; a Block is formed from tasks that already exist
/// (`CadenceTaskMutationSupport.insertBundle(from:adding:)` takes two of them), so an empty slot has
/// nothing to make one out of, and sibling work is retiring the feature in any case.
@MainActor
enum CadenceScheduleDraftKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case task
    case event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: return "Task"
        case .event: return "Event"
        }
    }

    var titlePlaceholder: String {
        switch self {
        case .task: return "Task title"
        case .event: return "Event title"
        }
    }

    /// What a draft block prints before it has been named. A draft is visible on the canvas
    /// *before* it is titled — that is the point of drawing it in place — so it needs a word, and
    /// an empty block would read as a rendering fault rather than as an unnamed one.
    var untitledLabel: String {
        switch self {
        case .task: return "New Task"
        case .event: return "New Event"
        }
    }
}

/// Everything the one panel edits, for either kind, in either mode — the model half of [[T-3171]].
///
/// **Creating and editing are the same panel.** They differ by exactly two things, and both are
/// here rather than in the view: `subject`, which says whether a record already exists and which
/// one, and the Delete control the view shows only when it does. Nothing else about the form
/// changes, which is the whole claim of that ticket — eight surfaces, 4,576 lines, spelling the
/// same four fields four different ways.
///
/// **It holds no `Color`, no `EKEvent` and no `AppTask`.** Every member is a `String`, an `Int`, a
/// `Bool` or an app enum, so the whole of "what is being made, when, and how long for" is testable
/// from the macOS-built `CadenceTests` and usable from both platforms' views. The host resolves
/// paint, calendars and lists at draw time and performs the writes; the panel moves this struct.
///
/// ## One schedule, read by both kinds
///
/// `startDateKey` / `startMin` / `endMin` / `isAllDay` serve a task **and** an event, rather than
/// each kind carrying its own pair. That is what lets the Task/Event switch repaint a draft block
/// without moving it: the block is in the same place on the canvas before and after the switch, and
/// a second schedule would have to be copied across — which is how two fields that must agree come
/// to disagree.
///
/// The translation to storage is stated once, in `scheduledStartMin`: an **all-day task is an
/// untimed task**, `AppTask.scheduledStartMin == -1`, which is the app's existing spelling of
/// "planned for this day, at no particular time" and what `iOSCalendarQuickCreateSheet`'s "Set
/// time" toggle already writes. The alternative — a task pinned 00:00–24:00 — would put a block
/// across the whole canvas for something every other surface draws in the untimed column.
///
/// ## Due is a date, by construction
///
/// `AppTask.dueDate` is a `yyyy-MM-dd` string and there is **no due-time field anywhere in the
/// models**. So Due here is a bare date key with no minute beside it, and the panel's expanded Due
/// section is a calendar grid and nothing else. This is the UI being made to match what the storage
/// already believes rather than a field being added to suit a form.
@MainActor
struct CadenceScheduleDraft: Equatable {

    /// Whether a record exists, and which one.
    ///
    /// The identifiers are carried rather than the objects: an `AppTask` is a SwiftData model and
    /// an `EKEvent` is a reference type EventKit can `reset()` under you, and neither belongs in a
    /// value the panel copies on every keystroke. The host resolves them when it commits.
    enum Subject: Equatable {
        case creating
        case editingTask(UUID)
        case editingEvent(String)

        var isEditing: Bool {
            switch self {
            case .creating: return false
            case .editingTask, .editingEvent: return true
            }
        }
    }

    /// An hour. Apple Calendar's own default for a press-and-hold, and longer than the 30 minutes
    /// the docked quick-create bar hard-coded: that bar could only ever make one length, so its
    /// figure was a contract; this one is a starting point with two drag handles on it.
    static let defaultDurationMinutes = 60

    /// The shortest block a drag can produce. One snap step, so an edge handle can never cross its
    /// opposite edge and invert the block.
    static let minimumDurationMinutes = CadenceScheduleSupport.touchTimeGridMinutes

    var subject: Subject
    var kind: CadenceScheduleDraftKind
    var title: String
    var notes: String
    var repeatRule: TaskRecurrenceRule

    // MARK: The one schedule

    /// `yyyy-MM-dd`, the app's one persisted date spelling. For a task this is the **Do** date.
    var startDateKey: String
    /// The day the block ends on. Equal to `startDateKey` for everything that fits in a day; only
    /// an event can move it, because an `AppTask` has one `scheduledDate` and there is no second
    /// day for the control to write to.
    var endDateKey: String
    var startMin: Int
    var endMin: Int
    /// All-day for an event; "no time" for a task. See the type note.
    var isAllDay: Bool

    // MARK: Task only

    var dueDateKey: String
    var priority: TaskPriority
    /// `CadenceTaskComposerSupport`'s container token — "inbox", or a prefixed area/project id.
    var listToken: String
    var sectionName: String
    var estimateIsExplicit: Bool

    // MARK: Event only

    var location: String
    /// `EKCalendar.calendarIdentifier`, or `""` before one has been resolved.
    var calendarID: String

    // MARK: Creating

    /// A draft at a pressed minute: what a press-and-hold on a timed canvas leaves behind.
    init(
        dateKey: String,
        startMin: Int,
        kind: CadenceScheduleDraftKind = .task,
        /// `nil` means `defaultDurationMinutes`. Spelled as an optional rather than as a default
        /// *expression*, because a default argument is evaluated in the caller's isolation and this
        /// type's constants are main-actor like `CadenceScheduleSupport`'s.
        durationMinutes: Int? = nil
    ) {
        let snappedStart = Self.snapped(startMin)
        let length = durationMinutes ?? Self.defaultDurationMinutes
        self.subject = .creating
        self.kind = kind
        self.title = ""
        self.notes = ""
        self.repeatRule = .none
        self.startDateKey = dateKey
        self.endDateKey = dateKey
        self.startMin = snappedStart
        self.endMin = min(
            CadenceScheduleSupport.calendarEndHour * 60,
            snappedStart + max(Self.minimumDurationMinutes, length)
        )
        self.isAllDay = false
        self.dueDateKey = ""
        self.priority = .none
        // Through the shared mapping, not a re-typed `"inbox"` — that encoding was hand-spelled in
        // four iOS files before `token(for:)` existed.
        self.listToken = CadenceTaskComposerSupport.token(for: .inbox)
        self.sectionName = TaskSectionDefaults.defaultName
        self.estimateIsExplicit = false
        self.location = ""
        self.calendarID = ""
    }

    // MARK: Geometry

    /// Minutes from midnight, snapped to the touch grid and held inside the drawn day.
    ///
    /// The grid is `touchTimeGridMinutes`, which is what a tap, a dropped `+` and
    /// `CadenceCaptureDropSlotRule` all already land on — so a block dragged to a minute is a
    /// minute the rest of the canvas can express.
    static func snapped(_ minute: Int) -> Int {
        let snap = max(1, CadenceScheduleSupport.touchTimeGridMinutes)
        let floor = CadenceScheduleSupport.calendarStartHour * 60
        let ceiling = CadenceScheduleSupport.calendarEndHour * 60
        return max(floor, min(ceiling, (max(floor, min(ceiling, minute)) / snap) * snap))
    }

    var durationMinutes: Int {
        max(Self.minimumDurationMinutes, endMin - startMin)
    }

    var spansMultipleDays: Bool {
        endDateKey > startDateKey
    }

    /// What `AppTask.scheduledStartMin` is written with. See the type note on all-day tasks.
    var scheduledStartMin: Int {
        isAllDay ? -1 : startMin
    }

    /// The top handle. Pushing it past the bottom edge would invert the block, so it stops one snap
    /// short — the block gets shorter, never negative, and never swaps its own ends under the
    /// finger.
    mutating func moveStartEdge(toMinute minute: Int) {
        guard !spansMultipleDays else { return }
        startMin = max(
            CadenceScheduleSupport.calendarStartHour * 60,
            min(Self.snapped(minute), endMin - Self.minimumDurationMinutes)
        )
    }

    /// The bottom handle, with the same non-inversion rule read the other way.
    mutating func moveEndEdge(toMinute minute: Int) {
        guard !spansMultipleDays else { return }
        endMin = min(
            CadenceScheduleSupport.calendarEndHour * 60,
            max(Self.snapped(minute), startMin + Self.minimumDurationMinutes)
        )
    }

    /// Moving the start carries the block's length with it, rather than stretching it against a
    /// pinned end — which is what a user dragging a *start* time means by it.
    mutating func moveStart(toMinute minute: Int) {
        let length = durationMinutes
        startMin = Self.snapped(minute)
        guard !spansMultipleDays else { return }
        endMin = min(CadenceScheduleSupport.calendarEndHour * 60, startMin + length)
    }

    // MARK: Labels

    /// What the collapsed date-and-time row reads for an **event**, and what a draft block prints
    /// under its title.
    ///
    /// Three shapes, because the thing being described has three: a timed block inside one day
    /// (`Oct 16 · 4:00 – 6:00 PM`), an all-day one (`Oct 16 · All day`), and one that crosses a
    /// midnight (`Oct 16, 4:00 PM → Oct 17, 6:00 PM`). The multi-day form names both days, because
    /// a range printing one day and two clock times would state the wrong thing rather than less.
    var scheduleLabel: String {
        let startDay = Self.dayLabel(startDateKey)
        if isAllDay {
            guard spansMultipleDays else { return "\(startDay) · All day" }
            return "\(startDay) → \(Self.dayLabel(endDateKey)) · All day"
        }
        guard spansMultipleDays else {
            return "\(startDay) · \(TimeFormatters.timeRange(startMin: startMin, endMin: endMin))"
        }
        return "\(startDay), \(TimeFormatters.timeString(from: startMin))"
            + " → \(Self.dayLabel(endDateKey)), \(TimeFormatters.timeString(from: endMin))"
    }

    /// The collapsed **Do** row. A date and nothing else: expanding Do opens the calendar, because
    /// the date is what matters for a task and the time is a secondary row revealed under it.
    var doRowLabel: String {
        startDateKey.isEmpty ? "No date" : Self.dayLabel(startDateKey)
    }

    /// The quiet Time row inside the expanded Do section. `"Add time"` while there is none, and the
    /// time plus the length once there is — so the row says what it holds rather than only that it
    /// could hold something.
    var doTimeLabel: String {
        guard !isAllDay else { return "Add time" }
        return "\(TimeFormatters.timeString(from: startMin)) · "
            + CadenceTaskPresentationSupport.estimateLabel(minutes: durationMinutes)
    }

    var dueRowLabel: String {
        dueDateKey.isEmpty ? "No due date" : Self.dayLabel(dueDateKey)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.untitledLabel : trimmed
    }

    /// A thing being created or saved needs a name, whichever kind it is — the rule T-567 settled
    /// for `iOSCalendarQuickCreateSheet`'s three arms, restated for these two.
    var hasCommittableTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Do after Due

    /// Said, in amber, when the task is planned for after its own deadline — and **only** said.
    ///
    /// **Warn, never block.** Planning to do something after it is due is a legitimate thing to
    /// record: it is late, and the user knows. Clamping the date would silently discard what they
    /// chose, and disabling Save would make the panel refuse a state the store is perfectly able to
    /// hold. So Save stays enabled, nothing is rewritten, and the sentence retires itself the
    /// moment either date moves — which is why it is computed rather than latched.
    ///
    /// The gap is **computed**, not generic: "3 days after it's due" is the whole value of the
    /// notice, and "this is scheduled after its due date" would be a sentence the user could have
    /// worked out from the two rows above it.
    var doAfterDueNotice: String? {
        guard kind == .task,
              !startDateKey.isEmpty,
              !dueDateKey.isEmpty,
              startDateKey > dueDateKey,
              let dueDate = DateFormatters.date(from: dueDateKey),
              let days = DateFormatters.dayOffset(from: startDateKey, relativeTo: dueDate),
              days > 0 else { return nil }
        let unit = days == 1 ? "day" : "days"
        return "You're planning to do this \(days) \(unit) after it's due."
    }

    // MARK: Switching kind

    /// Switching kind must not silently carry a field the other kind cannot store.
    ///
    /// `location` and the chosen calendar are EventKit's and a task has neither; `dueDate`,
    /// `priority` and the list are Cadence's and an `EKEvent` has none of them. A draft that kept a
    /// typed location through a switch to Task would be holding text with nowhere to go — the shape
    /// of a field that looks saved and is not.
    ///
    /// The **schedule** survives the switch deliberately: the draft block is in the same place on
    /// the canvas before and after, and moving it would make the switch look like it had done
    /// something to the time.
    mutating func normalizeForKind() {
        if kind == .task {
            location = ""
            endDateKey = startDateKey
        } else {
            dueDateKey = ""
            priority = .none
        }
    }

    private static func dayLabel(_ key: String) -> String {
        DateFormatters.shortDateString(from: key)
    }
}
