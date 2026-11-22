import Foundation
import UserNotifications

// **[[T-18527]].** The notification-centre door the widget target can compile.
//
// `NotificationManager.swift` is the app's guarded door to `UNUserNotificationCenter`, but it
// cannot be compiled into `CadenceWidgets` (it needs `PersistenceController`, `CadenceDefaults`,
// the planner and the app delegate's world). `CompleteTaskIntent` is compiled into both targets
// and may run in either process, and after it marks a task done it has to withdraw that task's
// two reminders or the OS keeps firing them until the app is next opened. So this file is the one
// other place allowed to name the centre -- `CadenceAgentOperatingRuleTests` lists exactly these
// two files -- and it can do exactly one thing: remove a task's `task-start-` / `task-due-`
// requests, pending and delivered. It schedules nothing and reads no setting: cancelling a done
// task's reminders is right whatever `notificationsEnabled` says, which is why [[T-312]]'s rule
// (the extension cannot see that setting, so it must not *reconcile*) does not forbid it.
//
// `NotificationIdentifiers` lives here rather than in `NotificationScheduling.swift` so the
// scheduler and this canceller spell the identifiers from one place in both targets.

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

extension NotificationIdentifiers {
    /// The task a task reminder's identifier names, or `nil` for any other identifier.
    ///
    /// **[[T-3049]] (1).** The identifier has always carried the task's UUID, so it is the one
    /// field a reminder registered by an *older* build — before `userInfo` carried a link — still
    /// has. `NotificationTapRoute` falls back to it for exactly those. A `habit-reminder-` id names
    /// a habit, not a task, and answers `nil`.
    nonisolated static func taskID(fromIdentifier identifier: String) -> UUID? {
        for prefix in ["task-start-", "task-due-"] where identifier.hasPrefix(prefix) {
            return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
        }
        return nil
    }
}

extension NotificationIdentifiers {
    /// **[[T-18527]].** Both reminders each task can hold, in task order: what every task-scoped
    /// cancel removes, so `NotificationManager.withdrawRemindersNow` and the widget's door name
    /// the same set.
    nonisolated static func taskReminders(taskIDs: [UUID]) -> [String] {
        taskIDs.flatMap { [taskStart(taskID: $0), taskDue(taskID: $0)] }
    }
}

/// **[[T-18527]].** Whether this process may reach the OS notification centre at all: not a test
/// host (either XCTest variable), not Xcode's SwiftUI preview host (`current()` crashes there for
/// want of a normal bundle identity), and not a UI-test-mode launch. `NotificationManager`'s
/// `isTestEnvironment` is this answer's negation, so the app's door and the widget's door cannot
/// disagree about which processes are off-limits.
nonisolated enum CadenceNotificationProcessGate {
    static func mayReachTheCentre(in environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return false }
        if environment["XCTestSessionIdentifier"] != nil { return false }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return false }
        if CadenceUITestModeGate.isOn(in: environment) { return false }
        return true
    }
}

/// **[[T-18527]].** Withdraws tasks' reminders. The seam `CompleteTaskIntent` cancels through, so a
/// test can hand it a recorder and assert what a completion removes.
nonisolated protocol CadenceTaskReminderWithdrawing: Sendable {
    func withdrawReminders(taskIDs: [UUID])
}

/// The real withdrawal: both identifiers per task, pending and delivered, from this process's
/// notification centre.
///
/// **Unverified on a device (see T-18527's sighting entry):** whether the widget extension's
/// `UNUserNotificationCenter.current()` reaches the requests the app registered. When the intent
/// runs in the app's process it certainly does.
///
/// `current()` is read inside the call, never stored, and only after the process gate -- so
/// constructing this touches nothing and no test host, preview or UI-test launch reaches the OS.
nonisolated struct CadenceSystemTaskReminderWithdrawal: CadenceTaskReminderWithdrawing {
    func withdrawReminders(taskIDs: [UUID]) {
        guard !taskIDs.isEmpty,
              CadenceNotificationProcessGate.mayReachTheCentre(in: ProcessInfo.processInfo.environment)
        else { return }
        let identifiers = NotificationIdentifiers.taskReminders(taskIDs: taskIDs)
        let centre = UNUserNotificationCenter.current()
        centre.removePendingNotificationRequests(withIdentifiers: identifiers)
        centre.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
