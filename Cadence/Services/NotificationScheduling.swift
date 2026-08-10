import Foundation

// This file contains ONLY pure planning logic — no `import UserNotifications`, no OS notification
// stack, no side effects. It is fully unit-testable without touching the real notification center.
// `NotificationManager.swift` is the thin adapter that turns a `NotificationPlan` into real
// `UNNotificationRequest`s and reconciles them against `UNUserNotificationCenter`.

enum NotificationKind: String, Codable {
    case taskStart
    case taskDue
    case habitReminder
}

struct CadenceNotificationRequest: Equatable {
    let identifier: String
    let kind: NotificationKind
    let title: String
    let body: String
    let fireDate: Date
}

/// Centralizes deterministic notification identifier formats so the scheduler (add) and the
/// canceller (remove) can never drift apart on ID format.
enum NotificationIdentifiers {
    static func taskStart(taskID: UUID) -> String {
        "task-start-\(taskID.uuidString)"
    }

    static func taskDue(taskID: UUID) -> String {
        "task-due-\(taskID.uuidString)"
    }

    static func habitReminder(habitID: UUID) -> String {
        "habit-reminder-\(habitID.uuidString)"
    }

    /// Whether an identifier belongs to Cadence's reconciled set. Anything else pending in the
    /// notification centre is somebody else's and must survive a reconcile untouched.
    nonisolated static func isManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix("task-start-") || identifier.hasPrefix("task-due-") || identifier.hasPrefix("habit-reminder-")
    }
}

/// The add/remove work a single reconcile pass must perform. Split out of `NotificationManager`
/// so the diffing rules are a pure, testable function — the manager's own `reconcile` early-returns
/// under test, so anything left inside it is effectively unverifiable.
struct NotificationReconcileDiff: Equatable {
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

enum TaskNotificationPlanner {
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

enum HabitNotificationPlanner {
    /// Returns the next daily reminder occurrence for a habit, or nil if no reminder time is set.
    ///
    /// MVP simplification: this fires every day the reminder is enabled, regardless of the
    /// habit's `frequencyType`/`frequencyDays` (e.g. a "3x/week" habit still gets a daily nudge
    /// on days it isn't due). That's a deliberate scope decision for a general daily reminder,
    /// not a bug — per-frequency-aware scheduling was explicitly out of scope for this pass.
    static func reminder(for habit: Habit, now: Date) -> CadenceNotificationRequest? {
        guard let minuteOfDay = habit.reminderMinuteOfDay else { return nil }
        let calendar = Calendar.current
        let todayAtReminderTime = calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: now
        ) ?? now

        let fireDate: Date
        if todayAtReminderTime > now {
            fireDate = todayAtReminderTime
        } else {
            fireDate = calendar.date(byAdding: .day, value: 1, to: todayAtReminderTime) ?? todayAtReminderTime
        }

        return CadenceNotificationRequest(
            identifier: NotificationIdentifiers.habitReminder(habitID: habit.id),
            kind: .habitReminder,
            title: habit.title,
            body: "Time for your daily check-in",
            fireDate: fireDate
        )
    }
}

struct NotificationPlan {
    let taskStarts: [CadenceNotificationRequest]
    let taskDues: [CadenceNotificationRequest]
    let habitReminders: [CadenceNotificationRequest]

    var all: [CadenceNotificationRequest] {
        taskStarts + taskDues + habitReminders
    }

    /// The single pure entry point both the real `NotificationManager` adapter and unit tests
    /// call. Never call `Date()` directly inside any planner function above — `now` is always
    /// injected here so the whole plan is deterministic and testable.
    static func build(
        tasks: [AppTask],
        habits: [Habit],
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
            },
            habitReminders: habits.compactMap { HabitNotificationPlanner.reminder(for: $0, now: now) }
        )
    }
}
