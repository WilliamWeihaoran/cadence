import Foundation

// This file contains ONLY pure planning logic — no `import UserNotifications`, no OS notification
// stack, no side effects. It is fully unit-testable without touching the real notification center.
// `NotificationManager.swift` is the thin adapter that turns a `NotificationPlan` into real
// `UNNotificationRequest`s and reconciles them against `UNUserNotificationCenter`.

nonisolated enum NotificationKind: String, Codable {
    case taskStart
    case taskDue
    /// **Retired as something the app schedules ([[T-2081]]); kept as something it can recognise.**
    ///
    /// Nothing builds a request of this kind any more — the habit planner function is gone and
    /// `NotificationPlan` has no habit channel. The case stays because `repeatsDaily` below is
    /// the *reason* the retirement needed an explicit cleanup pass: a habit reminder scheduled by
    /// an older build is a repeating time-of-day trigger, so it is not consumed when it fires and
    /// does not expire on its own. See `CadenceRetiredHabitReminderPurge`.
    case habitReminder

    /// Whether this reminder recurs at the same time every day, or fires once at one instant.
    ///
    /// A task's start and due reminders are about a specific dated task, so they are one-shot.
    /// A habit reminder is a standing "every day at 09:00" — it has no meaningful single date,
    /// and the planner only ever names the *next* occurrence. Building both as one-shot triggers
    /// meant a habit reminder fired once and then never again: the pending request was consumed,
    /// and only a reconcile could re-add it. Reconcile runs on `scenePhase` changes, so leaving
    /// the app open on a Mac (or simply not reopening it on iPhone) silently ended the reminder.
    var repeatsDaily: Bool {
        switch self {
        case .taskStart, .taskDue: return false
        case .habitReminder: return true
        }
    }

    /// The date components a trigger for this kind should match. A repeating daily reminder must
    /// match on time-of-day *only* — including `.year`/`.month`/`.day` pins it to one calendar
    /// date, which is what made `repeats` meaningless.
    var triggerComponents: Set<Calendar.Component> {
        repeatsDaily ? [.hour, .minute] : [.year, .month, .day, .hour, .minute, .second]
    }
}

nonisolated struct CadenceNotificationRequest: Equatable {
    let identifier: String
    let kind: NotificationKind
    let title: String
    let body: String
    let fireDate: Date

    /// Exactly what `NotificationManager` hands `UNCalendarNotificationTrigger`, as a pure value.
    ///
    /// The manager used to build these two inline, so nothing connected `NotificationKind`'s
    /// repeat rules to the trigger actually scheduled: reverting the adapter to a hardcoded
    /// one-shot left the whole suite green while the enum kept confidently reporting otherwise.
    /// `reconcile` early-returns under test by design, so this is the only seam where the two can
    /// be checked against each other.
    func triggerSpec(calendar: Calendar = .current) -> (components: DateComponents, repeats: Bool) {
        (calendar.dateComponents(kind.triggerComponents, from: fireDate), kind.repeatsDaily)
    }
}

/// Centralizes deterministic notification identifier formats so the scheduler (add) and the
/// canceller (remove) can never drift apart on ID format.
nonisolated enum NotificationIdentifiers {
    static func taskStart(taskID: UUID) -> String {
        "task-start-\(taskID.uuidString)"
    }

    static func taskDue(taskID: UUID) -> String {
        "task-due-\(taskID.uuidString)"
    }

    /// **Kept after [[T-2081]] retired habit reminders, and load-bearing rather than vestigial.**
    ///
    /// Nothing *schedules* one any more, but the owner's device still holds the ones an older
    /// build registered. This is the only spelling of the identifier they carry, so it is what
    /// `CadenceRetiredHabitReminderPurge` keys its removal on. Deleting it would leave those
    /// pending requests with no name the app can say.
    static func habitReminder(habitID: UUID) -> String {
        "habit-reminder-\(habitID.uuidString)"
    }

    /// Whether an identifier belongs to Cadence's reconciled set. Anything else pending in the
    /// notification centre is somebody else's and must survive a reconcile untouched.
    ///
    /// **`habit-reminder-` must stay in this list ([[T-2081]]).** It reads like dead vocabulary now
    /// that no habit reminder is ever planned, and dropping it is the one "tidy-up" that would make
    /// the retirement worse instead of better: `NotificationReconcileDiff.make` removes managed
    /// pending identifiers that are not desired, and `cancelAll` removes managed ones outright, so
    /// while the prefix is managed *every* reconcile sweeps the stale reminders an older build
    /// left. Unmanaging it reclassifies them as "somebody else's", and both sweeps would then
    /// deliberately preserve the thing this ticket exists to remove.
    nonisolated static func isManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix("task-start-") || identifier.hasPrefix("task-due-") || identifier.hasPrefix("habit-reminder-")
    }
}

/// The add/remove work a single reconcile pass must perform. Split out of `NotificationManager`
/// so the diffing rules are a pure, testable function — the manager's own `reconcile` early-returns
/// under test, so anything left inside it is effectively unverifiable.
nonisolated struct NotificationReconcileDiff: Equatable {
    let identifiersToRemove: [String]
    let requestsToAdd: [CadenceNotificationRequest]

    /// The platform keeps at most this many pending local notifications per app and silently drops
    /// the rest, so the desired set is trimmed here rather than left to the OS to truncate however
    /// it likes.
    static let pendingRequestLimit = 64

    /// Every desired request is re-added, including ones whose identifier is already pending.
    /// The identifier encodes only the task/habit UUID — the fire date and title live in the
    /// pending request itself — so "already pending" says nothing about whether the pending copy
    /// is still correct. Skipping those meant rescheduling a task to a new time, or renaming it,
    /// never reached the OS. `UNUserNotificationCenter.add` replaces a pending request with the
    /// same identifier, so re-adding is an update, not a duplicate.
    ///
    /// The desired set is *not* inherently small — one request per future-scheduled task, per
    /// future due date, and per reminding habit, so roughly forty dated tasks already pass the
    /// limit. It is therefore capped at the soonest `pendingRequestLimit` fire dates: whatever
    /// falls off is weeks out and will be picked up by a later reconcile long before it fires,
    /// whereas letting the OS choose loses an arbitrary subset of *today's* reminders. The
    /// overflow is also removed from pending rather than left behind, so the pending set converges
    /// on exactly the window this computed rather than on a stale union with previous passes.
    static func make(
        desired: [CadenceNotificationRequest],
        pendingIdentifiers: [String]
    ) -> NotificationReconcileDiff {
        let scheduled = desired
            .sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }
            .prefix(pendingRequestLimit)
        let desiredIdentifiers = Set(scheduled.map(\.identifier))
        let managedPending = Set(pendingIdentifiers.filter(NotificationIdentifiers.isManaged))

        return NotificationReconcileDiff(
            identifiersToRemove: managedPending.subtracting(desiredIdentifiers).sorted(),
            requestsToAdd: scheduled.sorted { $0.identifier < $1.identifier }
        )
    }
}

nonisolated enum TaskNotificationPlanner {
    /// Returns the "starting now" notification for a task's scheduled start time, or nil if the
    /// task isn't scheduled, is done/cancelled, or its fire time has already passed.
    ///
    /// **`scheduledStartMin` is a wall-clock time of day, so the fire date is *set*, never added**
    /// ([[T-3048]]). `date(byAdding: .minute, value:, to: midnight)` is **elapsed** time — `.hour`,
    /// `.minute` and `.second` are not calendrical units — so on a day that is 23 or 25 hours long
    /// it lands on a different clock reading than the one every timeline, row and chip renders for
    /// the same field. Measured in `America/New_York` with `scheduledStartMin = 540`: adding 540
    /// minutes to midnight gives **10:00** on 2026-03-08 and **08:00** on 2026-11-01, while
    /// `date(bySettingHour:minute:second:of:)` gives 09:00 on both and on an ordinary day. The
    /// error is not absorbed downstream: `CadenceNotificationRequest.triggerSpec` extracts
    /// `.hour`/`.minute` from this instant and `NotificationManager.makeTrigger` hands them to
    /// `UNCalendarNotificationTrigger`, so the wrong hour is the hour the OS fires at. The due leg
    /// below has always set its hour; this is the start leg agreeing with it.
    ///
    /// **The three times that need a decision rather than a default**, all measured on this
    /// toolchain in `America/New_York`:
    ///
    /// - **`0` (00:00)** and **`1439` (23:59)** are ordinary: both resolve on all three days, and
    ///   23:59 stays on the task's own day rather than rolling into the next one.
    /// - **A time the day does not have.** 02:30 on 2026-03-08 never occurs — the clocks jump from
    ///   01:59:59 EST to 03:00:00 EDT. Foundation answers **03:00 EDT**, the first instant at or
    ///   after the missing reading, and that is the behaviour this function wants: a reminder for a
    ///   start time inside the gap fires the moment that gap closes instead of being skipped or
    ///   silently moved to the next day. Spelled out because it is a decision — adding 150 minutes
    ///   to midnight instead answers 03:30, an hour past a start the user never asked for.
    /// - **An ambiguous time.** 01:30 on 2026-11-01 happens twice. Foundation answers the **first**
    ///   (01:30 EDT), which is the earlier of the two and the only one that cannot arrive late.
    ///
    /// A `scheduledStartMin` of `1440` or more names no time on the day at all, and
    /// `bySettingHour:` returns `nil` for it, so no reminder is planned. That is deliberate: every
    /// writer already holds the field to `0...1439` (`CadenceWriteService`, `AIActionService`), and
    /// the old arithmetic instead rolled such a value quietly onto a *different calendar day* than
    /// the one the task is filed under. The existing guards are unchanged — this leg still returns
    /// `nil` for an unscheduled, done, cancelled or already-past task, and for a negative minute.
    ///
    /// - Parameter calendar: The calendar whose time zone the day key is resolved in and the start
    ///   time is set in. Defaults to `.current`, which is every production call. A test passes an
    ///   explicit DST-observing zone because the scheme pins the test host to `TZ=UTC` ([[T-1116]]),
    ///   which has no DST and in which this whole distinction is invisible.
    static func startNotification(
        for task: AppTask,
        now: Date,
        calendar: Calendar = .current
    ) -> CadenceNotificationRequest? {
        guard !task.isDone, !task.isCancelled else { return nil }
        guard !task.scheduledDate.isEmpty, task.scheduledStartMin >= 0 else { return nil }
        guard let baseDate = DateFormatters.date(from: task.scheduledDate, in: calendar) else { return nil }
        guard let fireDate = calendar.date(
            bySettingHour: task.scheduledStartMin / 60,
            minute: task.scheduledStartMin % 60,
            second: 0,
            of: baseDate
        ) else {
            return nil
        }
        guard fireDate > now else { return nil }

        return CadenceNotificationRequest(
            identifier: NotificationIdentifiers.taskStart(taskID: task.id),
            kind: .taskStart,
            title: task.title,
            body: "Starting now",
            fireDate: fireDate
        )
    }

    /// Returns the due-date reminder for a task, fired at a fixed time-of-day on the due date,
    /// or nil if the task has no due date, is done/cancelled, or the fire time has already passed.
    ///
    /// This leg was already DST-safe and is the shape the start leg above was corrected to match
    /// ([[T-3048]]). The `calendar:` parameter exists so a test can assert that in as many words,
    /// in a zone that actually has DST; it changes nothing in production, where it is `.current`.
    static func dueNotification(
        for task: AppTask,
        now: Date,
        reminderHour: Int,
        reminderMinute: Int,
        calendar: Calendar = .current
    ) -> CadenceNotificationRequest? {
        guard !task.isDone, !task.isCancelled else { return nil }
        guard !task.dueDate.isEmpty else { return nil }
        guard let baseDate = DateFormatters.date(from: task.dueDate, in: calendar) else { return nil }
        guard let fireDate = calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: baseDate
        ) else { return nil }
        guard fireDate > now else { return nil }

        return CadenceNotificationRequest(
            identifier: NotificationIdentifiers.taskDue(taskID: task.id),
            kind: .taskDue,
            title: task.title,
            body: "Due today",
            fireDate: fireDate
        )
    }
}

/// What a habit's reminder *time* is allowed to be. No longer a scheduler.
///
/// **[[T-2081]].** The one function that turned a `Habit` into a pending OS notification is gone
/// with the rest of the habits surface, along with `NotificationPlan`'s habit channel. The minute range stays because it is still the app's one answer to "is this
/// stored value a real time of day", which `CadenceHabitReminderEditing` and the integrity tests
/// still ask of rows the schema deliberately keeps. It validates; it does not schedule.
nonisolated enum HabitNotificationPlanner {
    /// The minutes-from-midnight a reminder time can name: `0` (00:00) through `1439` (23:59).
    ///
    /// One spelling, in `Models/Habit.swift`, because `DataIntegrityRepairService` asks the same
    /// question and this file is not in the `CadenceMCPServer` target while `Models/` is — see
    /// `HabitReminderTime`.
    static let reminderMinuteRange = HabitReminderTime.minuteRange
}

nonisolated struct NotificationPlan {
    let taskStarts: [CadenceNotificationRequest]
    let taskDues: [CadenceNotificationRequest]

    var all: [CadenceNotificationRequest] {
        taskStarts + taskDues
    }

    /// The single pure entry point both the real `NotificationManager` adapter and unit tests
    /// call. Never call `Date()` directly inside any planner function above — `now` is always
    /// injected here so the whole plan is deterministic and testable.
    ///
    /// **There is deliberately no `habits:` parameter ([[T-2081]]).** The cheap retirement was to
    /// keep the parameter and have every caller pass `[]`, and that is the shape to refuse: a
    /// parameter that must always be empty carries no signal that filling it is forbidden, so the
    /// next caller to hold a `[Habit]` has every reason to pass it and would silently restore
    /// scheduling. Removing it makes "a habit cannot be scheduled" a fact the compiler keeps.
    static func build(
        tasks: [AppTask],
        now: Date,
        dueReminderHour: Int,
        dueReminderMinute: Int
    ) -> NotificationPlan {
        NotificationPlan(
            taskStarts: tasks.compactMap { TaskNotificationPlanner.startNotification(for: $0, now: now) },
            taskDues: tasks.compactMap {
                TaskNotificationPlanner.dueNotification(
                    for: $0,
                    now: now,
                    reminderHour: dueReminderHour,
                    reminderMinute: dueReminderMinute
                )
            }
        )
    }
}
