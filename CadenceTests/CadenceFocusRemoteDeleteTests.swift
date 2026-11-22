import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-19093]].** A focused task deleted on ANOTHER device arrives by CloudKit import -- a delete
/// saved in a different context -- so the in-app delete core, which ends the session on both
/// platforms ([[T-18514]], `deferFocusTeardown`), never runs, and the held instance goes on reading
/// `isDeleted == false` with its context set ([[T-7561]]). The Mac kept timing and banking against
/// the row; iOS dropped to "No session selected" under a clock still reading "Session running".
///
/// The fixture is an on-disk store in this test's own temp directory with two containers on it:
/// the app's, and the "other device" that deletes the row and saves -- the shape an import takes.
@MainActor
@Suite
struct CadenceFocusRemoteDeleteTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private struct Fixture {
        let directory: URL
        let storeURL: URL
        let appContainer: ModelContainer
        let appContext: ModelContext
        let task: AppTask
        let project: Project

        func openStore() throws -> ModelContainer {
            try ModelContainer(
                for: CadenceSchema.schema,
                configurations: ModelConfiguration(
                    "T19093Fixture", schema: CadenceSchema.schema,
                    url: storeURL, cloudKitDatabase: .none
                )
            )
        }

        /// The other device's delete, saved through its own container on the same file.
        func deleteOnAnotherDevice() throws {
            let otherContext = ModelContext(try openStore())
            let id = task.id
            let copy = try #require(
                try otherContext.fetch(FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })).first
            )
            otherContext.delete(copy)
            try otherContext.save()
        }

        /// What the store holds, read through a context that has never seen the task.
        func storedSessionLogCount() throws -> Int {
            try ModelContext(openStore()).fetchCount(FetchDescriptor<FocusSessionLog>())
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T19093-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Cadence.store")
        let appContainer = try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(
                "T19093Fixture", schema: CadenceSchema.schema,
                url: storeURL, cloudKitDatabase: .none
            )
        )
        let appContext = ModelContext(appContainer)
        let project = Project(name: "Ledger")
        appContext.insert(project)
        let task = AppTask(title: "Reconcile invoices")
        task.project = project
        appContext.insert(task)
        try appContext.save()
        return Fixture(
            directory: directory, storeURL: storeURL, appContainer: appContainer,
            appContext: appContext, task: task, project: project
        )
    }

    // MARK: - Shared: iOS's owner

    @Test func theOwnerEndsASessionWhoseSubjectAnotherDeviceDeletedAndBanksNothing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try withTemporaryDefaults("cadence.tests.focusRemoteDelete") { defaults in
            let clock = Clock()
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            owner.selectedTarget = .task(fixture.task.id)
            owner.timerState.toggle(now: clock.now)
            CadenceFocusSessionPersistence.write(
                CadenceFocusSessionPersistence.record(target: owner.selectedTarget, state: owner.timerState),
                to: defaults
            )
            clock.now = clock.now.addingTimeInterval(30 * 60)

            try fixture.deleteOnAnotherDevice()
            #expect(fixture.task.isDeleted == false, "premise: the held instance never hears of the import's delete")

            #expect(owner.endSessionIfSubjectGone(in: fixture.appContext))
            #expect(owner.selectedTarget == nil)
            #expect(owner.timerState.isRunning == false)
            #expect(owner.timerState.elapsedSeconds(now: clock.now) == 0)
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == nil, "an eviction would resume a session against nothing")
            #expect(try fixture.storedSessionLogCount() == 0)
        }
    }

    /// The control: a subject still in the store keeps its session, so the end above is the
    /// store's answer and not an unconditional one.
    @Test func theOwnerKeepsASessionWhoseSubjectIsStillInTheStore() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try withTemporaryDefaults("cadence.tests.focusRemoteDelete") { defaults in
            let clock = Clock()
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            owner.selectedTarget = .task(fixture.task.id)
            owner.timerState.toggle(now: clock.now)
            clock.now = clock.now.addingTimeInterval(30 * 60)

            #expect(owner.endSessionIfSubjectGone(in: fixture.appContext) == false)
            #expect(owner.selectedTarget == .task(fixture.task.id))
            #expect(owner.timerState.elapsedSeconds(now: clock.now) == 30 * 60)
        }
    }

    #if os(macOS)
    // MARK: - Mac: FocusManager

    private func startedManager(on fixture: Fixture, clock: Clock) throws -> FocusManager {
        let manager = FocusManager(sessionDefaults: nil)
        manager.clock = { clock.now }
        try manager.startFocus(task: fixture.task, in: fixture.appContext)
        clock.now = clock.now.addingTimeInterval(30 * 60)
        #expect(manager.elapsed == 30 * 60)
        return manager
    }

    /// The ticket's Mac half: ✕ on the Focus page banked the half hour against a row the store no
    /// longer has. It now ends the session unbanked.
    @Test func closingAMacSessionWhoseTaskAnotherDeviceDeletedBanksNothing() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = Clock()
        let manager = try startedManager(on: fixture, clock: clock)

        try fixture.deleteOnAnotherDevice()
        #expect(fixture.task.isDeleted == false, "premise: the held instance never hears of the import's delete")

        try manager.endSession(in: fixture.appContext)
        #expect(manager.activeSession == nil)
        #expect(manager.elapsed == 0)
        #expect(manager.isRunning == false)
        #expect(try fixture.storedSessionLogCount() == 0, "minutes were banked against a deleted row")
    }

    @Test func theFocusPageEndsAMacSessionWhoseTaskAnotherDeviceDeleted() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = Clock()
        let manager = try startedManager(on: fixture, clock: clock)

        #expect(manager.endSessionIfActiveTaskGone() == false, "a live task's session was ended")
        #expect(manager.activeTask?.id == fixture.task.id)
        #expect(manager.elapsed == 30 * 60)

        try fixture.deleteOnAnotherDevice()

        #expect(manager.endSessionIfActiveTaskGone())
        #expect(manager.activeSession == nil)
        #expect(manager.elapsed == 0)
        #expect(try fixture.storedSessionLogCount() == 0)
    }

    /// `refreshAppData()`'s swap could not re-resolve the deleted row and kept the old object
    /// ([[T-3098]]); it now gives that session the delete's teardown.
    @Test func theContextSwapEndsAMacSessionWhoseTaskAnotherDeviceDeleted() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let clock = Clock()
        let manager = try startedManager(on: fixture, clock: clock)

        try fixture.deleteOnAnotherDevice()

        let live = CadenceModelContextRefresh.replacement(for: fixture.appContext)
        macOSRootDataRefreshSupport.adoptReplacementContext(
            live,
            focusManager: manager,
            hoveredTaskManager: HoveredTaskManager.shared
        )
        #expect(manager.activeSession == nil, "the swap kept a session on a task the store no longer has")
        #expect(manager.elapsed == 0)
        #expect(try fixture.storedSessionLogCount() == 0)
    }
    #endif
}
