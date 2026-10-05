import Foundation
import Testing
@testable import Cadence

/// **[[T-2081]].** The half of the habits retirement that deleting code could not do.
///
/// Every other increment removed something from the app. This one removes something from the
/// *operating system*: habit reminders a previous build handed to `UNUserNotificationCenter`,
/// which survive the update that deleted the code that scheduled them, and which
/// `NotificationKind.habitReminder.repeatsDaily` makes recur every day with no end date.
///
/// **No test here touches a real notification centre.** `CadenceRetiredHabitReminderPurge.run()` —
/// the production entry point — early-returns on `NotificationManager.isTestEnvironment` before
/// `UNUserNotificationCenter.current()` is reached, and these drive `run(in:)` against the fake
/// below instead. Nothing is ever registered or cancelled on the machine running the suite.
@MainActor
struct CadenceRetiredHabitReminderPurgeTests {
    /// A pending-notification queue that records what was asked of it.
    ///
    /// Deliberately not a mock that only counts calls: it holds identifiers and actually drops the
    /// ones it is told to, so a test can assert on the *resulting queue* rather than on the
    /// argument list. That is the difference between "the purge asked for the habit one" and "the
    /// task one is still pending afterwards", and only the second is the claim worth making.
    final class FakeCentre: CadencePendingNotificationPurgeCentre {
        private(set) var pending: [String]
        private(set) var removeCallCount = 0

        init(pending: [String]) {
            self.pending = pending
        }

        func pendingIdentifiers() async -> [String] { pending }

        func removePending(withIdentifiers identifiers: [String]) {
            removeCallCount += 1
            pending.removeAll { identifiers.contains($0) }
        }
    }

    private let habitA = UUID()
    private let habitB = UUID()
    private let task = UUID()

    private func populatedCentre() -> FakeCentre {
        FakeCentre(pending: [
            NotificationIdentifiers.habitReminder(habitID: habitA),
            NotificationIdentifiers.taskStart(taskID: task),
            NotificationIdentifiers.taskDue(taskID: task),
            NotificationIdentifiers.habitReminder(habitID: habitB),
            // Something that is not Cadence's at all. A cleanup keyed too broadly would take this
            // too, and the user would lose another app's reminder to this ticket.
            "com.example.other-app.digest"
        ])
    }

    /// **The load-bearing test: both kinds are pending, and only the habit kind goes.**
    @Test func thePurgeRemovesHabitRemindersAndLeavesTaskRemindersPending() async {
        let centre = populatedCentre()

        let removed = await CadenceRetiredHabitReminderPurge.run(in: centre)

        #expect(Set(removed) == Set([
            NotificationIdentifiers.habitReminder(habitID: habitA),
            NotificationIdentifiers.habitReminder(habitID: habitB)
        ]))
        // The task reminders are the point. They belong to a task the user still has, on a page
        // that still exists, and this pass has no opinion about them.
        #expect(centre.pending.contains(NotificationIdentifiers.taskStart(taskID: task)))
        #expect(centre.pending.contains(NotificationIdentifiers.taskDue(taskID: task)))
        #expect(centre.pending.contains("com.example.other-app.digest"))
        #expect(centre.pending.count == 3)
        #expect(centre.pending.contains { $0.hasPrefix("habit-reminder-") } == false)
    }

    /// Idempotent by construction rather than by a `UserDefaults` flag, so a second cold launch is
    /// inert — and *observably* inert: it does not reach the queue at all.
    @Test func asecondRunRemovesNothingAndDoesNotTouchTheQueue() async {
        let centre = populatedCentre()

        _ = await CadenceRetiredHabitReminderPurge.run(in: centre)
        #expect(centre.removeCallCount == 1)

        let second = await CadenceRetiredHabitReminderPurge.run(in: centre)

        #expect(second.isEmpty)
        #expect(centre.removeCallCount == 1, "the purge issued a removal with nothing to remove")
        #expect(centre.pending.count == 3)
    }

    /// A queue holding only task reminders is left exactly as found — the common case on every
    /// launch after the first, and the one where an over-broad key would be silently destructive.
    @Test func aQueueOfOnlyTaskRemindersIsNotTouched() async {
        let centre = FakeCentre(pending: [
            NotificationIdentifiers.taskStart(taskID: task),
            NotificationIdentifiers.taskDue(taskID: task)
        ])

        let removed = await CadenceRetiredHabitReminderPurge.run(in: centre)

        #expect(removed.isEmpty)
        #expect(centre.removeCallCount == 0)
        #expect(centre.pending.count == 2)
    }

    /// The prefix is derived from the identifier builder, not written out a second time, so the
    /// purge cannot end up keyed on a format the scheduler never used.
    ///
    /// Asserted against a freshly built identifier rather than against the literal
    /// `"habit-reminder-"`, which is what makes it a statement about the two staying in step.
    @Test func thePurgePrefixMatchesTheIdentifierTheSchedulerUsedToWrite() {
        let id = UUID()

        #expect(NotificationIdentifiers.habitReminder(habitID: id)
            .hasPrefix(CadenceRetiredHabitReminderPurge.identifierPrefix))
        #expect(CadenceRetiredHabitReminderPurge.identifierPrefix + id.uuidString
            == NotificationIdentifiers.habitReminder(habitID: id))
        // And it does not match a task identifier, which is the failure mode that would make the
        // test above pass with an empty prefix.
        #expect(CadenceRetiredHabitReminderPurge.identifierPrefix.isEmpty == false)
        #expect(NotificationIdentifiers.taskDue(taskID: id)
            .hasPrefix(CadenceRetiredHabitReminderPurge.identifierPrefix) == false)
    }

    /// **The other half of the cleanup, and the one a future tidy-up could silently delete.**
    ///
    /// The launch purge is the guarantee; this is the belt. Because
    /// `NotificationIdentifiers.isManaged` still claims the `habit-reminder-` prefix and
    /// `NotificationPlan` can no longer produce one, every ordinary reconcile also sweeps a stale
    /// habit reminder. Dropping the prefix from `isManaged` reads like removing dead vocabulary and
    /// would reclassify these as another app's notifications, which both `NotificationReconcileDiff`
    /// and `cancelAll` are built to preserve — turning the tidiest-looking edit in this file into a
    /// restoration of the bug.
    @Test func anOrdinaryReconcileAlsoSweepsAStaleHabitReminderAndKeepsTheTaskOne() {
        let desiredTask = CadenceNotificationRequest(
            identifier: NotificationIdentifiers.taskDue(taskID: task),
            kind: .taskDue,
            title: "Ship it",
            body: "Due today",
            fireDate: Date(timeIntervalSince1970: 1_772_000_000)
        )

        let diff = NotificationReconcileDiff.make(
            desired: [desiredTask],
            pendingIdentifiers: [
                NotificationIdentifiers.habitReminder(habitID: habitA),
                NotificationIdentifiers.taskDue(taskID: task),
                "com.example.other-app.digest"
            ]
        )

        #expect(diff.identifiersToRemove == [NotificationIdentifiers.habitReminder(habitID: habitA)])
        #expect(diff.identifiersToRemove.contains(NotificationIdentifiers.taskDue(taskID: task)) == false)
        #expect(diff.identifiersToRemove.contains("com.example.other-app.digest") == false)
        #expect(diff.requestsToAdd.map(\.identifier) == [NotificationIdentifiers.taskDue(taskID: task)])

        #expect(
            NotificationIdentifiers.isManaged(NotificationIdentifiers.habitReminder(habitID: habitA)),
            "habit reminders left the managed set, so no reconcile will ever sweep them again"
        )
    }

    /// The production entry point is wired into launch, where it runs regardless of scene phase.
    ///
    /// This is a source assertion, which is the weak form — but the thing being pinned is *that a
    /// call exists at all*, and `CadenceApp.init()` cannot be run from a test host. It is here
    /// because the whole argument for this file is that waiting for a reconcile is not enough:
    /// `.onChange(of: scenePhase)` does not fire for the initial value, so a cold launch that
    /// creates no task would otherwise purge nothing.
    @Test func theLaunchInitializerRunsThePurge() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/CadenceApp.swift")
        // `declarationBody("init(")` rather than `functionBody(named: "init")`: the latter looks
        // for `func init(`, which an initializer is not, and returns `nil` for every file.
        let initializer = try #require(CadenceSourceScan.declarationBody("init(", in: source))

        #expect(initializer.contains("CadenceRetiredHabitReminderPurge.run()"))
    }
}
