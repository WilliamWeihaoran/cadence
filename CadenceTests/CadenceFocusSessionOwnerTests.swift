import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-15548]].** On iOS, backing out of Focus or picking another iPad sidebar destination ended
/// the session — clock back to 00:00, minutes logged — because the session was `iOSFocusView`'s own
/// `@State` and its `.onDisappear` banked and cleared it. The Mac's session is the app-wide
/// `FocusManager.shared` and survives leaving the Focus page ([[T-1103]]). `CadenceFocusSessionOwner`
/// is the iOS session held for the app; these drive it through a screen's appear and disappear.
@MainActor
@Suite
struct CadenceFocusSessionOwnerTests {
    private let epoch = Date(timeIntervalSince1970: 9_000_000)
    private struct CommitRefused: Error {}

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func withSuite<T>(
        test: String = #function,
        _ body: (UserDefaults) async throws -> T
    ) async throws -> T {
        try await withTemporaryDefaults(
            "cadence.tests.focusSessionOwner",
            test: test,
            opening: { UserDefaults(suiteName: $0) },
            body
        )
    }

    private func makeTask(_ title: String) throws -> (AppTask, Project, ModelContext) {
        let context = ModelContext(try CadenceTestStore.container())
        let project = Project(name: "Ledger")
        context.insert(project)
        let task = AppTask(title: title)
        task.project = project
        context.insert(task)
        try context.save()
        return (task, project, context)
    }

    /// A session started on the screen, as the screen's own writer leaves it on disk.
    private func startSession(
        on task: AppTask,
        owner: CadenceFocusSessionOwner,
        clock: Clock,
        defaults: UserDefaults
    ) {
        owner.screenDidAppear()
        owner.selectedTarget = .task(task.id)
        owner.timerState.toggle(now: clock.now)
        CadenceFocusSessionPersistence.write(
            CadenceFocusSessionPersistence.record(target: owner.selectedTarget, state: owner.timerState),
            to: defaults
        )
    }

    /// The ticket's steps: start, leave Focus, come back. The clock is still running against the
    /// same task with the time away on it, nothing was logged, and the record is still there for
    /// an eviction to resume.
    @Test func leavingTheFocusScreenKeepsTheSessionRunningAndLogsNothing() async throws {
        try await withSuite { defaults in
            let (task, project, _) = try makeTask("Write the brief")
            let clock = Clock(epoch)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            startSession(on: task, owner: owner, clock: clock, defaults: defaults)

            clock.now = epoch.addingTimeInterval(25 * 60)
            owner.screenDidDisappear(leaving: .task(task))
            clock.now = epoch.addingTimeInterval(40 * 60)
            owner.screenDidAppear()

            #expect(owner.selectedTarget == .task(task.id))
            #expect(owner.timerState.isRunning)
            #expect(owner.timerState.elapsedSeconds(now: clock.now) == 40 * 60)
            #expect(task.actualMinutes == 0)
            #expect(project.loggedMinutes == 0)
            #expect(CadenceFocusSessionPersistence.read(from: defaults)?.taskID == task.id)
        }
    }

    /// With the screen gone it can no longer see its subject being finished, so the owner does:
    /// ticking the task elsewhere banks the minutes it had earned **when it was ticked** and ends
    /// the session, the Mac's `releaseIfActiveTaskSettled`. Nothing here calls the owner after the
    /// tick — the watch is the code under test.
    @Test func aTaskFinishedWhileTheScreenIsGoneIsBankedAtTheTickAndTheSessionEnds() async throws {
        try await withSuite { defaults in
            let (task, project, _) = try makeTask("Reconcile invoices")
            let clock = Clock(epoch)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            startSession(on: task, owner: owner, clock: clock, defaults: defaults)
            owner.screenDidDisappear(leaving: .task(task))

            clock.now = epoch.addingTimeInterval(30 * 60)
            task.status = .done

            let deadline = Date().addingTimeInterval(10)
            while owner.timerState.isRunning, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(!owner.timerState.isRunning, "the finished task is still under a running clock")
            #expect(owner.timerState.elapsedSeconds(now: clock.now) == 0)
            #expect(owner.selectedTarget == nil)
            #expect(task.actualMinutes == 30)
            #expect(project.loggedMinutes == 30)
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == nil)
        }
    }

    /// While a screen stands, its own `.onChange(of: selectedSubjectIsSettled)` releases the
    /// subject; the owner standing down is what keeps the minutes from being banked twice.
    @Test func withAScreenStandingTheOwnerLeavesTheReleaseToIt() async throws {
        try await withSuite { defaults in
            let (task, _, _) = try makeTask("Reconcile invoices")
            let clock = Clock(epoch)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            startSession(on: task, owner: owner, clock: clock, defaults: defaults)
            owner.screenDidDisappear(leaving: .task(task))
            owner.screenDidAppear()

            clock.now = epoch.addingTimeInterval(30 * 60)
            task.status = .done
            for _ in 0..<20 { try await Task.sleep(nanoseconds: 10_000_000) }

            #expect(owner.timerState.isRunning)
            #expect(task.actualMinutes == 0)
        }
    }

    /// [[T-6223]] with the screen gone: a backgrounding still reaches the record, so an eviction
    /// overnight comes back paused at the sighting rather than crediting the night.
    @Test func aBackgroundingWithTheScreenGoneStillStampsTheRecord() async throws {
        try await withSuite { defaults in
            let (task, _, _) = try makeTask("Late session")
            let clock = Clock(epoch)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            startSession(on: task, owner: owner, clock: clock, defaults: defaults)
            owner.screenDidDisappear(leaving: .task(task))

            let sighting = epoch.addingTimeInterval(1_800)
            clock.now = sighting
            owner.leaveForeground()

            let record = try #require(CadenceFocusSessionPersistence.read(from: defaults))
            #expect(record.lastSeenAt == sighting)
            let morning = sighting.addingTimeInterval(11 * 60 * 60)
            let resumed = try #require(
                CadenceFocusSessionPersistence.resumed(from: record, tasks: [task], now: morning)
            )
            #expect(!resumed.state.isRunning)
            #expect(resumed.state.accumulatedSeconds == 1_800)

            // And a suspended-not-evicted return applies the same rule in memory.
            clock.now = morning
            owner.returnToForeground()
            #expect(!owner.timerState.isRunning)
            #expect(owner.timerState.accumulatedSeconds == 1_800)
            #expect(owner.lastSeenAt == nil)
        }
    }

    /// A cold launch that has not visited Focus has an empty clock in memory and the session on
    /// disk. Leaving the foreground then must not write the empty clock over it.
    @Test func anEmptyClockInMemoryNeverClearsTheRecordOnDisk() async throws {
        try await withSuite { defaults in
            let record = CadenceFocusSessionRecord(
                taskID: UUID(), isRunning: true, startedAt: epoch, accumulatedSeconds: 0
            )
            CadenceFocusSessionPersistence.write(record, to: defaults)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { self.epoch })

            owner.leaveForeground()
            owner.returnToForeground()

            #expect(CadenceFocusSessionPersistence.read(from: defaults) == record)
        }
    }

    // MARK: - [[T-15572]]: the session header's close

    /// The Mac's ✕ (`FocusManager.endSession(in:)`) on iOS: one tap banks the elapsed minutes
    /// against the subject — rounded, through the shared `CadenceFocusSupport.endSession` — and
    /// ends the session: clock at zero and stopped, subject released, the record on disk gone.
    @Test func closingTheSessionBanksTheElapsedMinutesAndEndsIt() async throws {
        try await withSuite { defaults in
            let (task, project, context) = try makeTask("Draft the memo")
            let clock = Clock(epoch)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            startSession(on: task, owner: owner, clock: clock, defaults: defaults)
            #expect(owner.hasLiveSession)

            clock.now = epoch.addingTimeInterval(25 * 60 + 20)
            try owner.endSession(leaving: .task(task), in: context)

            #expect(task.actualMinutes == 25)
            #expect(project.loggedMinutes == 25)
            #expect(!owner.timerState.isRunning)
            #expect(owner.timerState.elapsedSeconds(now: clock.now) == 0)
            #expect(!owner.hasLiveSession, "the close control is still drawn after the session ended")
            #expect(owner.selectedTarget == nil)
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == nil)
        }
    }

    /// A refused bank ends nothing (T-654, the Mac's rule): the clock is still running against the
    /// same subject with its reading, and the record is still there, so the close can be retried.
    @Test func aRefusedCloseLeavesTheSessionRunningToRetry() async throws {
        try await withSuite { defaults in
            let (task, _, context) = try makeTask("Draft the memo")
            let clock = Clock(epoch)
            let owner = CadenceFocusSessionOwner(defaults: defaults, clock: { clock.now })
            startSession(on: task, owner: owner, clock: clock, defaults: defaults)

            clock.now = epoch.addingTimeInterval(10 * 60)
            #expect(throws: CommitRefused.self) {
                try owner.endSession(leaving: .task(task), in: context, commit: { _ in throw CommitRefused() })
            }

            #expect(task.actualMinutes == 0)
            #expect(owner.timerState.isRunning)
            #expect(owner.timerState.elapsedSeconds(now: clock.now) == 10 * 60)
            #expect(owner.selectedTarget == .task(task.id))
            #expect(CadenceFocusSessionPersistence.read(from: defaults)?.taskID == task.id)
        }
    }

    /// The control itself, read out of both platforms' sources: iOS's session header draws a close
    /// under the Mac's label, and it calls the owner's `endSession` with the screen's subject, the
    /// way the Mac header's `onClose` calls `focusManager.endSession(in:)`.
    @Test func bothSessionHeadersCarryTheCloseUnderOneLabel() throws {
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let header = try #require(CadenceSourceScan.declarationBody("private func sessionHeader<", in: ios))
        #expect(header.contains("accessibilityLabel: CadenceFocusSupport.closeSessionControlLabel"))
        #expect(header.contains("action: endSession"))
        let close = try #require(CadenceSourceScan.declarationBody("private func endSession()", in: ios))
        #expect(close.contains("try session.endSession(leaving: selectedSubject, in: modelContext)"))
        #expect(close.contains("CadenceTaskSettleFailureCenter.shared.record()"))

        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusChromeSupportViews.swift")
        )
        #expect(mac.contains(".cadenceControlLabel(CadenceFocusSupport.closeSessionControlLabel)"))
        let macView = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusView.swift")
        #expect(macView.contains("onClose: { reportingFocusFailure { try focusManager.endSession(in: modelContext) } }"))
    }
}
