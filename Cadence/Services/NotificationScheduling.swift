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
    static func startNotification(for task: AppTask, now: Date) -> CadenceNotificationRequest? {
        guard !task.isDone, !task.isCancelled else { return nil }
        guard !task.scheduledDate.isEmpty, task.scheduledStartMin >= 0 else { return nil }
        guard let baseDate = DateFormatters.date(from: task.scheduledDate) else { return nil }
        guard let fireDate = Calendar.current.date(byAdding: .minute, value: task.scheduledStartMin, to: baseDate) else {
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
    static func dueNotification(
        for task: AppTask,
        now: Date,
        reminderHour: Int,
        reminderMinute: Int
    ) -> CadenceNotificationRequest? {
        guard !task.isDone, !task.isCancelled else { return nil }
        guard !task.dueDate.isEmpty else { return nil }
        guard let baseDate = DateFormatters.date(from: task.dueDate) else { return nil }
        guard let fireDate = Calendar.current.date(
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
