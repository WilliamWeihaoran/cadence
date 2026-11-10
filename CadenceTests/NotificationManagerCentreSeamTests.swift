import Foundation
import Testing
import SwiftData
import UserNotifications
@testable import Cadence

/// **[[T-3113]].** `NotificationManager`'s side-effecting entry points, executed.
///
/// `shared` early-returns from every one of them under `isTestEnvironment`, so until this suite no
/// test had ever run `refreshAuthorizationState`, `requestAuthorization`, `reconcile`, either
/// `cancel` or `cancelAll` — they were held only by greps of their own source text, which survive
/// an inverted authorization read or a wrong identifier set. These drive a manager built with
/// `init(centre:defaults:)` over the fake below.
///
/// **No test here touches a real notification centre.** The system centre is `private` to
/// `NotificationManager.swift`, so it cannot be handed to that initializer; `shared` is never
/// called. Nothing is registered or removed on the machine running the suite.
@MainActor
struct NotificationManagerCentreSeamTests {

    /// A pending queue that actually holds identifiers, so a test asserts on the queue left behind
    /// — "the other task's reminder is still pending" — rather than only on the argument list.
    final class FakeCentre: CadenceNotificationCentre {
        var status: UNAuthorizationStatus
        var grantsRequest: Bool
        /// What the OS reports once the prompt has been answered, when that differs from `status`.
        var statusAfterRequest: UNAuthorizationStatus?
        var refused: Set<String> = []
        private(set) var pending: [String]
        private(set) var removeCalls: [[String]] = []
        private(set) var added: [String] = []
        private(set) var statusReads = 0
        private(set) var requestedOptions: [UNAuthorizationOptions] = []
        /// What Notification Center is showing ([[T-15464]]).
        private(set) var delivered: [String]
        private(set) var removeDeliveredCalls: [[String]] = []

        init(
            status: UNAuthorizationStatus = .authorized,
            grantsRequest: Bool = false,
            pending: [String] = [],
            delivered: [String] = []
        ) {
            self.status = status
            self.grantsRequest = grantsRequest
            self.pending = pending
            self.delivered = delivered
        }

        func deliveredIdentifiers() async -> [String] { delivered }

        func removeDelivered(withIdentifiers identifiers: [String]) {
            removeDeliveredCalls.append(identifiers)
            delivered.removeAll { identifiers.contains($0) }
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            statusReads += 1
            return status
        }

        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            requestedOptions.append(options)
            if let statusAfterRequest { status = statusAfterRequest }
            return grantsRequest
        }

        func pendingIdentifiers() async -> [String] { pending }

        func removePending(withIdentifiers identifiers: [String]) {
            removeCalls.append(identifiers)
            pending.removeAll { identifiers.contains($0) }
        }

        func add(_ request: UNNotificationRequest) async throws {
            if refused.contains(request.identifier) {
                throw RefusedByFake()
            }
            // The OS replaces a pending request with the same identifier rather than duplicating it.
            added.append(request.identifier)
            pending.removeAll { $0 == request.identifier }
            pending.append(request.identifier)
        }

        var removed: Set<String> { Set(removeCalls.flatMap { $0 }) }
    }

    struct RefusedByFake: Error {}

    private let foreign = "com.example.other-app.reminder"

    private func withManager(
        _ centre: FakeCentre,
        notificationsEnabled: Bool = true,
        test: String = #function,
        _ body: (NotificationManager) async throws -> Void
    ) async throws {
        try await withTemporaryDefaults(
            "cadence.tests.notification-centre-seam",
            test: test,
            opening: { UserDefaults(suiteName: $0) }
        ) { defaults in
            defaults.set(notificationsEnabled, forKey: NotificationManager.notificationsEnabledDefaultsKey)
            try await body(NotificationManager(centre: centre, defaults: defaults))
        }
    }

    /// A task whose due reminder is in the future whatever the date the suite runs on.
    private func dueTask(_ title: String) -> AppTask {
        let task = AppTask(title: title)
        task.dueDate = "2099-06-10"
        return task
    }

    // MARK: - reconcile

    /// Re-adds exactly the planned set (an already-pending planned one too: `add` is the update
    /// path, see `NotificationReconcileDiff.make`), removes exactly the managed identifiers nothing
    /// plans, and leaves another app's request alone.
    @Test func reconcileAddsTheMissingAndRemovesOnlyTheStaleManagedIdentifiers() async throws {
        let kept = dueTask("Already pending")
        let missing = dueTask("Not yet pending")
        let staleTask = NotificationIdentifiers.taskDue(taskID: UUID())
        let staleHabit = NotificationIdentifiers.habitReminder(habitID: UUID())
        let keptID = NotificationIdentifiers.taskDue(taskID: kept.id)
        let missingID = NotificationIdentifiers.taskDue(taskID: missing.id)
        let centre = FakeCentre(pending: [keptID, staleTask, staleHabit, foreign])

        try await withManager(centre) { manager in
            await manager.reconcile(tasks: [kept, missing])

            #expect(
                centre.added.sorted() == [keptID, missingID].sorted(),
                "reconcile did not hand the OS exactly the planned requests"
            )
            #expect(
                centre.removed == [staleTask, staleHabit],
                "reconcile removed \(centre.removed) instead of exactly the stale managed identifiers"
            )
            #expect(Set(centre.pending) == [keptID, missingID, foreign])
            #expect(manager.lastReconcileRegistrationFailures.isEmpty)
        }
    }

    /// A pass with nothing stale makes no removal call at all, rather than an empty one, and still
    /// re-adds the planned request.
    @Test func reconcileWithNothingStaleMakesNoRemovalCall() async throws {
        let task = dueTask("Pending")
        let centre = FakeCentre(pending: [NotificationIdentifiers.taskDue(taskID: task.id), foreign])

        try await withManager(centre) { manager in
            await manager.reconcile(tasks: [task])
            #expect(centre.removeCalls.isEmpty)
            #expect(centre.added == [NotificationIdentifiers.taskDue(taskID: task.id)])
        }
    }

    /// **[[T-3047]], behaviourally.** The reconcile re-derives authorization before it reads it,
    /// in both directions a cached answer can be stale. This replaces the source-order grep that
    /// `CadenceNotificationsEnabledToggleTests` held while the body could not run under test.
    @Test func reconcileActsOnTheAuthorizationTheOSReportsNowNotTheCachedFlag() async throws {
        let task = dueTask("Due")
        let taskID = NotificationIdentifiers.taskDue(taskID: task.id)

        // Stale-false: never refreshed, so the cached flag says no, while the OS says yes.
        let granted = FakeCentre(status: .authorized, pending: [foreign])
        try await withManager(granted) { manager in
            #expect(!manager.isAuthorized, "precondition: the cached flag starts stale-false")
            await manager.reconcile(tasks: [task])
            #expect(granted.statusReads == 1, "reconcile did not re-read the authorization")
            #expect(manager.isAuthorized)
            #expect(granted.added == [taskID], "a just-granted permission was answered by cancelling everything")
        }

        // Stale-true: the flag was true, then the OS withdrew permission.
        let revoked = FakeCentre(status: .authorized, pending: [taskID, foreign])
        try await withManager(revoked, test: "reconcileActsOnTheAuthorizationTheOSReportsNowNotTheCachedFlag.revoked") { manager in
            await manager.refreshAuthorizationState()
            #expect(manager.isAuthorized, "precondition: the cached flag starts true")
            revoked.status = .denied
            await manager.reconcile(tasks: [task])
            #expect(!manager.isAuthorized)
            #expect(revoked.added.isEmpty, "reconcile scheduled into a withdrawn permission")
            #expect(revoked.removed == [taskID], "a withdrawn permission did not cancel the managed reminders")
            #expect(revoked.pending == [foreign])
        }
    }

    /// The preference off cancels the managed set, whatever the OS permission.
    @Test func reconcileWithTheToggleOffCancelsOnlyManagedReminders() async throws {
        let task = dueTask("Due")
        let taskID = NotificationIdentifiers.taskDue(taskID: task.id)
        let centre = FakeCentre(status: .authorized, pending: [taskID, foreign])

        try await withManager(centre, notificationsEnabled: false) { manager in
            await manager.reconcile(tasks: [task])
            #expect(centre.added.isEmpty)
            #expect(centre.pending == [foreign])
        }
    }

    /// **[[T-3049]] (2), behaviourally.** A refusal is recorded against its identifier, the pass
    /// still attempts the rest, and the cancel branch clears the previous pass's record. Replaces
    /// the grep `NotificationRegistrationFailureTests` held on the reconcile body.
    @Test func reconcileRecordsTheRefusalsOfItsOwnPassAndTheCancelBranchClearsThem() async throws {
        let refusedTask = dueTask("Refused")
        let acceptedTask = dueTask("Accepted")
        let refusedID = NotificationIdentifiers.taskDue(taskID: refusedTask.id)
        let acceptedID = NotificationIdentifiers.taskDue(taskID: acceptedTask.id)
        let centre = FakeCentre(status: .authorized)
        centre.refused = [refusedID]

        try await withManager(centre) { manager in
            await manager.reconcile(tasks: [refusedTask, acceptedTask])
            #expect(manager.lastReconcileRegistrationFailures.map(\.identifier) == [refusedID])
            #expect(centre.added == [acceptedID], "a refusal stopped the pass before the next request")

            centre.status = .denied
            await manager.reconcile(tasks: [refusedTask, acceptedTask])
            #expect(
                manager.lastReconcileRegistrationFailures.isEmpty,
                "the cancel branch kept the previous pass's refusals"
            )
        }
    }

    // MARK: - Authorization

    @Test func refreshAuthorizationStateMapsEveryStatusOntoTheTwoFlags() async throws {
        let cases: [(UNAuthorizationStatus, authorized: Bool, denied: Bool)] = [
            (.authorized, true, false),
            (.provisional, true, false),
            (.denied, false, true),
            (.notDetermined, false, false),
        ]
        let centre = FakeCentre()
        try await withManager(centre) { manager in
            for (status, authorized, denied) in cases {
                centre.status = status
                await manager.refreshAuthorizationState()
                #expect(manager.isAuthorized == authorized, "isAuthorized wrong for status \(status.rawValue)")
                #expect(manager.isDenied == denied, "isDenied wrong for status \(status.rawValue)")
            }
            #expect(centre.statusReads == cases.count)
        }
    }

    /// The request asks for alert and sound once, returns the OS's answer, and re-derives the flags
    /// from the status the OS reports afterwards.
    @Test func requestAuthorizationAsksOnceAndRefreshesTheFlags() async throws {
        let centre = FakeCentre(status: .authorized, grantsRequest: true)
        try await withManager(centre) { manager in
            let granted = await manager.requestAuthorization()
            #expect(granted)
            #expect(centre.requestedOptions == [[.alert, .sound]])
            #expect(centre.statusReads == 1)
            #expect(manager.isAuthorized)
        }

        let declining = FakeCentre(status: .denied, grantsRequest: false)
        try await withManager(declining, test: "requestAuthorizationAsksOnceAndRefreshesTheFlags.declined") { manager in
            let granted = await manager.requestAuthorization()
            #expect(!granted)
            #expect(!manager.isAuthorized)
            #expect(manager.isDenied)
        }
    }

    /// **[[T-6000]].** On a fresh install the stored switch is absent, and a granted answer to the
    /// "Enable Notifications" request turns it on — so the next reconcile schedules rather than
    /// cancelling everything. A refusal leaves it absent: nobody who said no is opted in.
    @Test func aGrantedRequestTurnsRemindersOnAndADeclinedOneDoesNot() async throws {
        let key = NotificationManager.notificationsEnabledDefaultsKey
        let task = dueTask("Due after granting")
        let dueID = NotificationIdentifiers.taskDue(taskID: task.id)

        let granting = FakeCentre(status: .authorized, grantsRequest: true)
        try await withTemporaryDefaults(
            "cadence.tests.notification-centre-seam",
            test: "aGrantedRequestTurnsRemindersOnAndADeclinedOneDoesNot.granted",
            opening: { UserDefaults(suiteName: $0) }
        ) { defaults in
            #expect(defaults.object(forKey: key) == nil, "non-vacuity: the suite starts as a fresh install")
            let manager = NotificationManager(centre: granting, defaults: defaults)
            #expect(await manager.requestAuthorization())
            #expect(defaults.object(forKey: key) as? Bool == true, "a granted request left reminders off")

            await manager.reconcile(tasks: [task])
            #expect(granting.added.contains(dueID), "reminders were turned on but nothing was scheduled")
        }

        let declining = FakeCentre(status: .denied, grantsRequest: false)
        try await withTemporaryDefaults(
            "cadence.tests.notification-centre-seam",
            test: "aGrantedRequestTurnsRemindersOnAndADeclinedOneDoesNot.declined",
            opening: { UserDefaults(suiteName: $0) }
        ) { defaults in
            let manager = NotificationManager(centre: declining, defaults: defaults)
            #expect(await manager.requestAuthorization() == false)
            #expect(defaults.object(forKey: key) == nil, "a declined request wrote the reminders switch")
        }
    }

    /// **[[T-6000]].** The "Enable Notifications" button opens system Settings only when access was
    /// ALREADY denied before the tap. A "Don't Allow" given to the prompt the tap itself raised is
    /// an answer, and must not send the user to Settings unasked; a refusal from before the tap
    /// cannot be re-asked, so Settings is where it goes — without a pointless second request.
    @Test func settingsOpensOnlyWhenAccessWasDeniedBeforeTheTap() async throws {
        // Never asked, then "Don't Allow": the OS reports .denied only AFTER the request.
        let askedNow = FakeCentre(status: .notDetermined, grantsRequest: false)
        askedNow.statusAfterRequest = .denied
        try await withManager(askedNow, test: "settingsOpensOnlyWhenAccessWasDeniedBeforeTheTap.declinedNow") { manager in
            let opens = await manager.requestAuthorizationOrOpenSettings()
            #expect(askedNow.requestedOptions == [[.alert, .sound]], "non-vacuity: the tap did not ask the OS")
            #expect(manager.isDenied, "non-vacuity: the fake did not report the refusal afterwards")
            #expect(!opens, "a \"Don't Allow\" given just now sent the user to system Settings unasked")
        }

        // Never asked, then "Allow".
        let granting = FakeCentre(status: .notDetermined, grantsRequest: true)
        granting.statusAfterRequest = .authorized
        try await withManager(granting, test: "settingsOpensOnlyWhenAccessWasDeniedBeforeTheTap.grantedNow") { manager in
            #expect(await manager.requestAuthorizationOrOpenSettings() == false, "a granted request opened Settings")
            #expect(granting.requestedOptions.count == 1)
        }

        // Already refused before the tap: the system will not prompt again.
        let alreadyDenied = FakeCentre(status: .denied, grantsRequest: false)
        try await withManager(alreadyDenied, test: "settingsOpensOnlyWhenAccessWasDeniedBeforeTheTap.deniedBefore") { manager in
            #expect(!manager.isDenied, "non-vacuity: the cached flag starts stale, so the status must be re-read")
            #expect(await manager.requestAuthorizationOrOpenSettings(), "an earlier refusal did not route to Settings")
            #expect(alreadyDenied.requestedOptions.isEmpty, "a refusal the OS will not re-prompt was asked again")
        }
    }

    // MARK: - [[T-15464]]: reminders that already fired

    /// A fired reminder is no longer pending, so only the delivered list can withdraw it. A pass
    /// takes down exactly the shown reminders of the tasks it holds as done or cancelled, and
    /// leaves an open task's, an absent task's, a habit's and another app's on screen.
    @Test func reconcileWithdrawsTheDeliveredRemindersOfSettledTasksOnly() async throws {
        let done = dueTask("Finished at 09:05")
        done.status = .done
        let cancelled = dueTask("Called off")
        cancelled.status = .cancelled
        let open = dueTask("Still open")
        let absent = UUID()
        let doneShown = [NotificationIdentifiers.taskStart(taskID: done.id), NotificationIdentifiers.taskDue(taskID: done.id)]
        let cancelledShown = NotificationIdentifiers.taskDue(taskID: cancelled.id)
        let kept = [
            NotificationIdentifiers.taskDue(taskID: open.id),
            NotificationIdentifiers.taskDue(taskID: absent),
            NotificationIdentifiers.habitReminder(habitID: done.id),
            foreign,
        ]
        let centre = FakeCentre(delivered: doneShown + [cancelledShown] + kept)

        try await withManager(centre) { manager in
            await manager.reconcile(tasks: [done, cancelled, open])

            #expect(centre.removeDeliveredCalls.count == 1)
            #expect(
                Set(centre.removeDeliveredCalls.flatMap { $0 }) == Set(doneShown + [cancelledShown]),
                "reconcile withdrew \(centre.removeDeliveredCalls) instead of exactly the settled tasks' shown reminders"
            )
            #expect(Set(centre.delivered) == Set(kept))

            // Nothing settled left on screen: no empty call reaches the centre.
            await manager.reconcile(tasks: [done, cancelled, open])
            #expect(centre.removeDeliveredCalls.count == 1, "a pass with nothing to withdraw still reached the centre")
        }
    }

    // MARK: - [[T-15486]]: a fired reminder whose task was deleted where no cancel ran

    private func shown(_ id: UUID) -> [String] {
        [NotificationIdentifiers.taskStart(taskID: id), NotificationIdentifiers.taskDue(taskID: id)]
    }

    /// A delete that reaches the store without `cancel(taskIDs:)` -- one CloudKit imported from
    /// another device -- is proved by two complete reads of the same store: the task was in the
    /// first and is gone from the second. Its shown reminders go; a kept task's, a never-seen
    /// task's, and another app's stay.
    @Test func reconcileWithdrawsTheDeliveredRemindersOfATaskTwoCompleteReadsProveDeleted() async throws {
        let container = try CadenceTestStore.container()
        let writer = ModelContext(container)
        let kept = AppTask(title: "Kept")
        let deleted = AppTask(title: "Deleted on another device")
        writer.insert(kept)
        writer.insert(deleted)
        try writer.save()
        let (keptID, deletedID, neverSeen) = (kept.id, deleted.id, UUID())
        let centre = FakeCentre(delivered: shown(keptID) + shown(deletedID) + shown(neverSeen) + [foreign])

        try await withManager(centre) { manager in
            let first = try CadenceForegroundNotificationSnapshot(container: container)
            #expect(first.completeStore != nil, "non-vacuity: the default fetch must prove completeness")
            await manager.reconcile(tasks: first.tasks, completeStore: first.completeStore)
            #expect(centre.removeDeliveredCalls.isEmpty, "a first complete read proved a deletion it never saw")

            writer.delete(deleted)
            try writer.save()
            // A partial pass in between proves nothing and must not erase the first read.
            await manager.reconcile(tasks: [])
            #expect(centre.removeDeliveredCalls.isEmpty, "a pass with no complete read withdrew a reminder")
            let second = try CadenceForegroundNotificationSnapshot(container: container)
            #expect(second.tasks.map(\.id) == [keptID])
            await manager.reconcile(tasks: second.tasks, completeStore: second.completeStore)

            #expect(centre.removeDeliveredCalls.count == 1)
            #expect(Set(centre.removeDeliveredCalls.flatMap { $0 }) == Set(shown(deletedID)))
            #expect(Set(centre.delivered) == Set(shown(keptID) + shown(neverSeen) + [foreign]))
        }
    }

    /// Absence without proof withdraws nothing: a pass handed no complete read (a partial list),
    /// a complete read of a DIFFERENT store (the empty recovery store, a restore), and a partial
    /// pass in between does not erase the last complete read.
    @Test func aMissingTaskIsNeverWithdrawnWithoutTwoCompleteReadsOfOneStore() async throws {
        let container = try CadenceTestStore.container()
        let writer = ModelContext(container)
        let task = AppTask(title: "Merely not loaded")
        writer.insert(task)
        try writer.save()
        let taskID = task.id
        let centre = FakeCentre(delivered: shown(taskID))

        try await withManager(centre) { manager in
            let first = try CadenceForegroundNotificationSnapshot(container: container)
            await manager.reconcile(tasks: first.tasks, completeStore: first.completeStore)

            // A partial pass that lacks the task proves nothing.
            await manager.reconcile(tasks: [])
            #expect(centre.removeDeliveredCalls.isEmpty, "a pass with no complete read withdrew a missing task's reminder")

            // A complete read of another store proves nothing either.
            let other = try CadenceForegroundNotificationSnapshot(container: try CadenceTestStore.container())
            #expect(other.tasks.isEmpty)
            await manager.reconcile(tasks: other.tasks, completeStore: other.completeStore)
            #expect(centre.removeDeliveredCalls.isEmpty, "a different store's read proved a deletion")
            #expect(Set(centre.delivered) == Set(shown(taskID)))
        }
    }

    /// The pure rule: present-then-absent in one store, nothing across stores or without a read.
    @Test func provenDeletedTaskIDsNeedsTwoReadsOfTheSameStore() throws {
        let (a, b) = (try CadenceTestStore.container(), try CadenceTestStore.container())
        let (x, y) = (UUID(), UUID())
        let read = { (c: AnyObject, ids: Set<UUID>) in
            NotificationCompleteStoreRead(storeIdentity: ObjectIdentifier(c), taskIDs: ids)
        }
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: read(a, [x, y]), current: read(a, [x])) == [y])
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: read(a, [x, y]), current: read(b, [])).isEmpty)
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: nil, current: read(a, [])).isEmpty)
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: read(a, [x]), current: nil).isEmpty)
        withExtendedLifetime((a, b)) {}
    }

    // MARK: - [[T-15516]]: a delete imported while the app was not running

    /// A store FILE in this test's own temp directory -- never the app's store -- opened as a
    /// fresh container each call, which is what a relaunch is to `ObjectIdentifier`.
    private func fileStore(_ url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: [ModelConfiguration(schema: CadenceSchema.schema, url: url, cloudKitDatabase: .none)]
        )
    }

    private func withTemporaryStoreDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotificationManagerCentreSeamTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// The resolver `shared` uses, minus its "is this the app's container" check: each test
    /// container's own store file.
    private func fileIdentity(of containers: [ModelContainer]) -> @MainActor (ObjectIdentifier) -> String? {
        { identity in
            containers.first { ObjectIdentifier($0) == identity }.flatMap(NotificationStoreFileIdentity.of)
        }
    }

    /// The first complete read of a launch is compared with the one the previous launch stored:
    /// a task in that read and gone from this one -- deleted on another device while the app was
    /// not running -- has its fired reminders withdrawn; a kept task's and another app's stay.
    @Test func aDeleteImportedBeforeTheNextLaunchIsProvedByTheStoredReadOfTheSameFile() async throws {
        try await withTemporaryStoreDirectory { directory in
            let url = directory.appendingPathComponent("relaunch.store")
            let firstLaunch = try fileStore(url)
            let writer = ModelContext(firstLaunch)
            let kept = AppTask(title: "Kept")
            let deleted = AppTask(title: "Deleted on another device")
            writer.insert(kept)
            writer.insert(deleted)
            try writer.save()
            let (keptID, deletedID) = (kept.id, deleted.id)
            let centre = FakeCentre(delivered: shown(keptID) + shown(deletedID) + [foreign])

            try await withTemporaryDefaults(
                "cadence.tests.notification-centre-seam",
                opening: { UserDefaults(suiteName: $0) }
            ) { defaults in
                defaults.set(true, forKey: NotificationManager.notificationsEnabledDefaultsKey)
                let before = try CadenceForegroundNotificationSnapshot(container: firstLaunch)
                await NotificationManager(centre: centre, defaults: defaults, durableStoreIdentity: fileIdentity(of: [firstLaunch]))
                    .reconcile(tasks: before.tasks, completeStore: before.completeStore)
                #expect(NotificationManager.storedCompleteStoreRead(defaults: defaults)?.taskIDs == [keptID, deletedID],
                        "non-vacuity: the first launch stored its complete read")
                #expect(centre.removeDeliveredCalls.isEmpty)

                // The next launch: a new container over the same file, the import already applied.
                let nextLaunch = try fileStore(url)
                let importer = ModelContext(nextLaunch)
                let gone = try importer.fetch(FetchDescriptor<AppTask>()).filter { $0.id == deletedID }
                #expect(gone.count == 1)
                gone.forEach(importer.delete)
                try importer.save()
                let after = try CadenceForegroundNotificationSnapshot(container: nextLaunch)
                #expect(after.completeStore?.storeIdentity != before.completeStore?.storeIdentity,
                        "the in-memory identity must differ, or this is T-15486's case again")
                await NotificationManager(centre: centre, defaults: defaults, durableStoreIdentity: fileIdentity(of: [nextLaunch]))
                    .reconcile(tasks: after.tasks, completeStore: after.completeStore)

                #expect(Set(centre.removeDeliveredCalls.flatMap { $0 }) == Set(shown(deletedID)))
                #expect(Set(centre.delivered) == Set(shown(keptID) + [foreign]))
                #expect(NotificationManager.storedCompleteStoreRead(defaults: defaults)?.taskIDs == [keptID],
                        "the next launch's read replaces the stored one")
            }
        }
    }

    /// A stored read of ANOTHER file proves nothing: the next launch opening the empty recovery
    /// store, or a store with no file at all (the in-memory fallback), withdraws no reminder.
    @Test func aStoredReadOfAnotherStoreFileProvesNothing() async throws {
        try await withTemporaryStoreDirectory { directory in
            let primary = try fileStore(directory.appendingPathComponent("default.store"))
            let writer = ModelContext(primary)
            let task = AppTask(title: "Still in the primary store")
            writer.insert(task)
            try writer.save()
            let taskID = task.id
            let centre = FakeCentre(delivered: shown(taskID))

            try await withTemporaryDefaults(
                "cadence.tests.notification-centre-seam",
                opening: { UserDefaults(suiteName: $0) }
            ) { defaults in
                defaults.set(true, forKey: NotificationManager.notificationsEnabledDefaultsKey)
                let first = try CadenceForegroundNotificationSnapshot(container: primary)
                await NotificationManager(centre: centre, defaults: defaults, durableStoreIdentity: fileIdentity(of: [primary]))
                    .reconcile(tasks: first.tasks, completeStore: first.completeStore)
                let stored = try #require(NotificationManager.storedCompleteStoreRead(defaults: defaults))
                #expect(stored.taskIDs == [taskID])

                let recovery = try fileStore(directory.appendingPathComponent("recovery.store"))
                let empty = try CadenceForegroundNotificationSnapshot(container: recovery)
                #expect(empty.tasks.isEmpty)
                await NotificationManager(centre: centre, defaults: defaults, durableStoreIdentity: fileIdentity(of: [recovery]))
                    .reconcile(tasks: empty.tasks, completeStore: empty.completeStore)
                #expect(centre.removeDeliveredCalls.isEmpty, "the recovery store's empty read proved a deletion")

                let inMemory = try CadenceTestStore.container()
                let none = try CadenceForegroundNotificationSnapshot(container: inMemory)
                await NotificationManager(centre: centre, defaults: defaults, durableStoreIdentity: fileIdentity(of: [inMemory]))
                    .reconcile(tasks: none.tasks, completeStore: none.completeStore)
                #expect(centre.removeDeliveredCalls.isEmpty, "an in-memory store's read proved a deletion")
                #expect(Set(centre.delivered) == Set(shown(taskID)))
            }
        }
    }

    /// The identity is the FILE, not the path: re-read unchanged, and unchanged by a write in
    /// place; different once a copy is moved over it, which is what a restore does
    /// (`StoreBackupManager.performPendingRestoreIfNeeded`). An in-memory store has none.
    @Test func theStoreFileIdentityFollowsTheFileAcrossWritesAndChangesOnARestoreShapedSwap() async throws {
        try await withTemporaryStoreDirectory { directory in
            let url = directory.appendingPathComponent("default.store")
            try Data("original".utf8).write(to: url)
            let original = try #require(NotificationStoreFileIdentity.of(storeURL: url))
            #expect(NotificationStoreFileIdentity.of(storeURL: url) == original)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(" plus a row".utf8))
            try handle.close()
            #expect(NotificationStoreFileIdentity.of(storeURL: url) == original, "a write in place changed the identity")

            let staged = directory.appendingPathComponent("staged.store")
            try FileManager.default.copyItem(at: url, to: staged)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: staged, to: url)
            let restored = try #require(NotificationStoreFileIdentity.of(storeURL: url))
            #expect(restored != original, "a restored copy at the same path matched the original file")

            #expect(NotificationStoreFileIdentity.of(storeURL: directory.appendingPathComponent("absent.store")) == nil)
            #expect(NotificationStoreFileIdentity.of(storeURL: directory) == nil,
                    "a directory has a file number and a creation date, but it is not a store file")
            #expect(NotificationStoreFileIdentity.of(try CadenceTestStore.container()) == nil,
                    "an in-memory store has no file to survive a launch")
            let fileBacked = try fileStore(directory.appendingPathComponent("open.store"))
            #expect(NotificationStoreFileIdentity.of(fileBacked) != nil, "non-vacuity: a store file has an identity")
        }
    }

    /// The durable rule, and its encoding: same file proves, another file or no read does not; the
    /// record round-trips and a damaged one reads as nothing.
    @Test func durableProvenDeletedTaskIDsNeedsTheSameStoreFile() throws {
        let (x, y) = (UUID(), UUID())
        let read = { (file: String, ids: Set<UUID>) in
            NotificationDurableCompleteStoreRead(storeFileIdentity: file, taskIDs: ids)
        }
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: read("a", [x, y]), current: read("a", [x])) == [y])
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: read("a", [x, y]), current: read("b", [])).isEmpty)
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: nil, current: read("a", [])).isEmpty)
        #expect(NotificationReconcileDiff.provenDeletedTaskIDs(previous: read("a", [x]), current: nil).isEmpty)

        let record = read("/store|42|1.5", [x, y])
        let data = try #require(record.encoded)
        #expect(NotificationDurableCompleteStoreRead(encoded: data) == record)
        #expect(read("s", [y, x]).encoded == read("s", [x, y]).encoded, "an unchanged read must encode to the same bytes")
        #expect(NotificationDurableCompleteStoreRead(encoded: Data("not a record".utf8)) == nil)
    }

    /// A delete withdraws the shown copies of the deleted tasks' two reminders as well as the
    /// pending ones, and nothing of any other task's.
    @Test func cancelTaskIDsAlsoWithdrawsTheDeliveredRemindersOfTheGivenTasks() async throws {
        let (a, b) = (UUID(), UUID())
        let ids = { (id: UUID) in [NotificationIdentifiers.taskStart(taskID: id), NotificationIdentifiers.taskDue(taskID: id)] }
        let centre = FakeCentre(delivered: ids(a) + ids(b) + [foreign])

        try await withManager(centre) { manager in
            await manager.cancel(taskIDs: [a])
            #expect(Set(centre.removeDeliveredCalls.flatMap { $0 }) == Set(ids(a)))
            #expect(Set(centre.delivered) == Set(ids(b) + [foreign]))
        }
    }

    // MARK: - cancel / cancelAll

    @Test func cancelTaskIDsRemovesExactlyBothRemindersOfTheGivenTasks() async throws {
        let (a, b, c) = (UUID(), UUID(), UUID())
        let ids = { (id: UUID) in [NotificationIdentifiers.taskStart(taskID: id), NotificationIdentifiers.taskDue(taskID: id)] }
        let centre = FakeCentre(pending: ids(a) + ids(b) + ids(c) + [foreign])

        try await withManager(centre) { manager in
            await manager.cancel(taskIDs: [a, b])
            #expect(centre.removeCalls.count == 1)
            #expect(centre.removed == Set(ids(a) + ids(b)))
            #expect(Set(centre.pending) == Set(ids(c) + [foreign]))

            await manager.cancel(taskIDs: [])
            #expect(centre.removeCalls.count == 1, "an empty cancel reached the centre")
        }
    }

    @Test func cancelHabitIDsRemovesExactlyTheGivenHabitReminders() async throws {
        let (a, b) = (UUID(), UUID())
        let taskID = NotificationIdentifiers.taskDue(taskID: a)
        let centre = FakeCentre(pending: [
            NotificationIdentifiers.habitReminder(habitID: a),
            NotificationIdentifiers.habitReminder(habitID: b),
            taskID,
        ])

        try await withManager(centre) { manager in
            await manager.cancel(habitIDs: [a])
            #expect(centre.removed == [NotificationIdentifiers.habitReminder(habitID: a)])
            #expect(Set(centre.pending) == [NotificationIdentifiers.habitReminder(habitID: b), taskID])

            await manager.cancel(habitIDs: [])
            #expect(centre.removeCalls.count == 1, "an empty cancel reached the centre")
        }
    }

    @Test func cancelAllRemovesEveryManagedIdentifierAndNothingElse() async throws {
        let managed = [
            NotificationIdentifiers.taskStart(taskID: UUID()),
            NotificationIdentifiers.taskDue(taskID: UUID()),
            NotificationIdentifiers.habitReminder(habitID: UUID()),
        ]
        let centre = FakeCentre(pending: managed + [foreign])

        try await withManager(centre) { manager in
            await manager.cancelAll()
            #expect(centre.removed == Set(managed))
            #expect(centre.pending == [foreign])

            await manager.cancelAll()
            #expect(centre.removeCalls.count == 1, "cancelAll with nothing managed still reached the centre")
        }
    }
}
