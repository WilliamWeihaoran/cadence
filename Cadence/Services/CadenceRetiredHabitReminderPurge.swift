import Foundation

/// Removes the habit reminders an **older build** left pending in the operating system.
///
/// **This file names no OS type, and `CadenceLiveNotificationPurgeCentre` lives in
/// `NotificationManager.swift` rather than here.** `CadenceAgentOperatingRuleTests` holds the app to
/// one door to the notification centre, because that door is the one that guards on
/// `isTestEnvironment` — a second one schedules real notifications to the user's Notification
/// Center under the app's bundle id (T-1386). The purge therefore states what it wants as a
/// protocol and the single guarded file supplies it.
///
/// **The problem deleting code does not solve.** A habit reminder is not stored in Cadence. It was
/// handed to the OS notification centre on some previous launch and lives in that queue, so it
/// survives the app updating, and it survives the planner that created it being deleted.
/// [[T-2081]] removed every line that could schedule one; without this pass the owner's habits
/// would have gone on firing from a build that can no longer explain them, and — because
/// [[T-2076]] removed the Goals and Habits pages — tapping the notification would open nothing.
///
/// **Why it fires forever rather than once.** `NotificationKind.habitReminder.repeatsDaily` is
/// `true`, so these are `UNCalendarNotificationTrigger`s matching on hour and minute with
/// `repeats: true`. They are not consumed when they fire and have no end date. "It will expire on
/// its own" is the intuition to discard here: left alone, it is a daily alarm with no off switch
/// inside the app.
///
/// **Why a reconcile pass is not enough, although it would work.** `NotificationReconcileDiff.make`
/// removes every *managed* pending identifier that is not in the desired set, and
/// `NotificationIdentifiers.isManaged` still claims the `habit-reminder-` prefix, so now that the
/// plan has no habit channel any reconcile does sweep these. The gap is not in what reconcile does,
/// it is in *whether reconcile runs*:
///
/// - Both root views trigger it from `.onChange(of: scenePhase)`, which does not fire for the
///   initial value — and `macOSRootView`'s additionally returns early on `.active`. So a cold
///   launch reconciles nothing.
/// - Every other caller is a task create/edit/delete or the Settings toggle.
///
/// A user who installs the update, opens the app and does not create a task or background it has
/// reconciled nothing, and gets the reminder again tomorrow. This pass closes that by depending on
/// nothing: not on a scene transition, not on a store fetch succeeding, not on `notificationsEnabled`
/// or on authorization (`reconcile` early-returns to `cancelAll()` on those, which happens to also
/// sweep — but "happens to" is the word this ticket is trying to remove).
///
/// **No `UserDefaults` "already purged" flag, deliberately.** The purge is keyed on an identifier
/// prefix nothing in the app can produce any more, so a second run finds nothing and removes
/// nothing — idempotent by construction rather than by bookkeeping. A flag would add a second thing
/// that can be wrong, and this retirement has already been bitten once by exactly that: [[T-2077]]
/// found a launch migration still minting a goal, with its `UserDefaults` flag *not* being what had
/// been stopping it. The cost of going without is one `pendingNotificationRequests()` read per cold
/// launch.
nonisolated enum CadenceRetiredHabitReminderPurge {
    /// The identifier prefix every habit reminder an older build scheduled carries.
    ///
    /// Derived from `NotificationIdentifiers.habitReminder` rather than written as a second
    /// `"habit-reminder-"` literal, so the purge cannot end up keyed on a format the scheduler no
    /// longer used. The probe UUID is thrown away; only the shape of the string matters.
    static let identifierPrefix: String = {
        let probe = UUID()
        return String(
            NotificationIdentifiers.habitReminder(habitID: probe).dropLast(probe.uuidString.count)
        )
    }()

    /// Exactly which pending identifiers this purge removes, given everything the OS holds.
    ///
    /// Pure, and the entire decision — `run(in:)` does nothing but hand the result to the
    /// notification centre. Keeping it separate is what makes the removal testable at all, since
    /// anything inside `NotificationManager` early-returns under test.
    ///
    /// **Keyed on the habit prefix, never on `NotificationIdentifiers.isManaged`.** `isManaged` is
    /// the right question for a reconcile and the wrong one here: it is true for `task-start-` and
    /// `task-due-` as well, so reusing it would turn a targeted cleanup into `cancelAll()` and take
    /// every live task reminder with it. A task reminder is for a task the user still has, and this
    /// pass has no opinion about it.
    static func identifiersToPurge(pendingIdentifiers: [String]) -> [String] {
        pendingIdentifiers.filter { $0.hasPrefix(identifierPrefix) }
    }

    /// Runs the purge against the real notification centre. The app's one production entry point.
    ///
    /// Guarded by `NotificationManager.isTestEnvironment` on the same terms as everything else in
    /// this layer, and the guard comes *before* the live centre is constructed so a unit test, a UI
    /// test or a SwiftUI preview host never reaches the live centre, which is the only thing that
    /// touches the OS.
    @MainActor
    static func run() async {
        guard !NotificationManager.isTestEnvironment else { return }
        await run(in: CadenceLiveNotificationPurgeCentre())
    }

    /// The same work against an injected centre, returning what it removed.
    ///
    /// This is the seam the tests drive: the real removal path, with a fake queue standing in for
    /// the OS, so no test ever registers or cancels a notification on the owner's machine.
    @MainActor
    @discardableResult
    static func run(in centre: some CadencePendingNotificationPurgeCentre) async -> [String] {
        let doomed = identifiersToPurge(pendingIdentifiers: await centre.pendingIdentifiers())
        // Not merely an optimisation: it keeps the pass genuinely inert on the second and every
        // later launch, so "it removed nothing" and "it did not touch the queue" are the same
        // observable state rather than two different ones a test would have to tell apart.
        guard !doomed.isEmpty else { return [] }
        centre.removePending(withIdentifiers: doomed)
        return doomed
    }
}

/// The two-call view of `UNUserNotificationCenter` the purge needs.
///
/// Narrow on purpose: a protocol that could schedule would let a future conformer — or a careless
/// test — put a habit reminder *back*. Read the pending identifiers, remove some of them, nothing
/// else.
@MainActor
protocol CadencePendingNotificationPurgeCentre {
    func pendingIdentifiers() async -> [String]
    func removePending(withIdentifiers identifiers: [String])
}
