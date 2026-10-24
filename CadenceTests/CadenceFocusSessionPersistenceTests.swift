import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-6001.** A running iOS focus session lived only in view state: `iOSFocusView` banked on
/// `.onDisappear` alone, which does not run when iOS evicts a backgrounded app or the user swipes
/// it away, so the clock and every unlogged minute went with the process. The Mac banks on quit
/// ([[T-5305]]); the phone had no equivalent door.
///
/// The owner chose **option (a): persist `{target, startedAt, accumulated}` and resume the live
/// session on next open.** Option (b), banking a partial log on `scenePhase == .background`, was
/// declined — it would end the session every time the user glances at another app.
///
/// Nothing here writes to the SwiftData store: minutes are still banked by
/// `CadenceFocusSupport.endSession` on the exits that already called it.
@MainActor
@Suite
struct CadenceFocusSessionPersistenceTests {

    // MARK: - What is worth remembering

    @Test func anIdleClockIsNotASessionAndIsNeverPersisted() {
        let target = CadenceFocusTarget.task(UUID())
        #expect(CadenceFocusSessionPersistence.record(target: target, state: CadenceFocusTimerState()) == nil)

        // Nothing picked is nothing to resume, however the clock reads.
        var running = CadenceFocusTimerState()
        running.toggle()
        #expect(CadenceFocusSessionPersistence.record(target: nil, state: running) == nil)
    }

    @Test func aRunningSessionIsRememberedWithTheInstantItStartedOn() throws {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_000_000)
        var state = CadenceFocusTimerState()
        state.toggle(now: started)

        let record = try #require(
            CadenceFocusSessionPersistence.record(target: .task(id), state: state)
        )
        #expect(record.taskID == id)
        #expect(record.isRunning)
        #expect(record.startedAt == started)
        #expect(record.accumulatedSeconds == 0)
    }

    /// A paused session has `startedAt == nil` and seconds on the clock. It must come back paused:
    /// resuming it as running would start counting time nobody is working.
    @Test func aPausedSessionIsRememberedPausedWithItsReading() throws {
        let started = Date(timeIntervalSince1970: 2_000_000)
        var state = CadenceFocusTimerState()
        state.toggle(now: started)
        state.toggle(now: started.addingTimeInterval(90))

        let record = try #require(
            CadenceFocusSessionPersistence.record(target: .task(UUID()), state: state)
        )
        #expect(!record.isRunning)
        #expect(record.startedAt == nil)
        #expect(record.accumulatedSeconds == 90)
    }

    // MARK: - Coming back

    @Test func aRunningSessionResumesLiveSoTheMinutesAcrossTheEvictionAreStillOnTheClock() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Write the brief")
        context.insert(task)

        let started = Date(timeIntervalSince1970: 3_000_000)
        var state = CadenceFocusTimerState()
        state.toggle(now: started)
        let record = try #require(
            CadenceFocusSessionPersistence.record(target: .task(task.id), state: state)
        )

        let resumed = try #require(
            CadenceFocusSessionPersistence.resumed(from: record, tasks: [task])
        )
        #expect(resumed.target == .task(task.id))
        #expect(resumed.state.isRunning)
        // Wall-clock, as the Mac's is: ten minutes of eviction are ten minutes on the clock.
        #expect(resumed.state.elapsedSeconds(now: started.addingTimeInterval(600)) == 600)
    }

    /// `canFocus` is the picker's own predicate, asked here for T-276's reason: resuming a clock
    /// against a task finished or cancelled elsewhere banks minutes into `actualMinutes` and from
    /// there into a goal.
    @Test func aRecordNamingAMissingOrFinishedTaskResumesNothing() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Already done")
        context.insert(task)

        var state = CadenceFocusTimerState()
        state.toggle(now: Date(timeIntervalSince1970: 4_000_000))
        let record = try #require(
            CadenceFocusSessionPersistence.record(target: .task(task.id), state: state)
        )

        // The task is not in the store this screen can see.
        #expect(CadenceFocusSessionPersistence.resumed(from: record, tasks: []) == nil)

        task.status = .done
        #expect(CadenceFocusSessionPersistence.resumed(from: record, tasks: [task]) == nil)

        task.status = .cancelled
        #expect(CadenceFocusSessionPersistence.resumed(from: record, tasks: [task]) == nil)

        task.status = .todo
        #expect(CadenceFocusSessionPersistence.resumed(from: record, tasks: [task]) != nil)
        #expect(CadenceFocusSessionPersistence.resumed(from: nil, tasks: [task]) == nil)
    }

    // MARK: - The defaults round trip

    @Test func aSessionSurvivesTheRoundTripThroughTheDefaults() throws {
        try withTemporaryDefaults("cadence.tests.focusSession") { defaults in
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == nil)

            let record = CadenceFocusSessionRecord(
                taskID: UUID(),
                isRunning: true,
                startedAt: Date(timeIntervalSince1970: 5_000_000),
                accumulatedSeconds: 42
            )
            CadenceFocusSessionPersistence.write(record, to: defaults)
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == record)

            // Writing "nothing to resume" is how a session ends — the key goes, not left stale.
            CadenceFocusSessionPersistence.write(nil, to: defaults)
            #expect(defaults.string(forKey: CadencePreferenceKeys.iosFocusSession) == nil)

            CadenceFocusSessionPersistence.write(record, to: defaults)
            CadenceFocusSessionPersistence.clear(in: defaults)
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == nil)
        }
    }

    /// A key holding something else resolves to no session rather than to a guess — which is
    /// exactly the behaviour before this existed.
    @Test func anUnreadableValueResumesNothing() throws {
        try withTemporaryDefaults("cadence.tests.focusSession") { defaults in
            defaults.set("not json", forKey: CadencePreferenceKeys.iosFocusSession)
            #expect(CadenceFocusSessionPersistence.read(from: defaults) == nil)
        }
        #expect(CadenceFocusSessionPersistence.decoded(nil) == nil)
        #expect(CadenceFocusSessionPersistence.decoded("{}") == nil)
    }

    // MARK: - Source pins: the view persists on every move and clears only on a landed bank

    private static func focusView() throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
    }

    @Test func theFocusScreenRestoresOnAppearAndPersistsEveryMoveOfTheClock() throws {
        let view = try #require(
            CadenceSourceScan.declarationBody("struct iOSFocusView", in: try Self.focusView())
        )
        #expect(view.contains("restorePersistedSession()"))
        // The cold route only: a clock already standing on this screen is the live session.
        let restore = try #require(
            CadenceSourceScan.functionBody(named: "restorePersistedSession", in: view)
        )
        #expect(restore.contains("guard !timerState.isRunning, timerState.accumulatedSeconds == 0"))
        // One writer, driven by the record rather than by each mutation site.
        #expect(view.contains(".onChange(of: sessionRecord)"))
        #expect(view.contains("CadenceFocusSessionPersistence.write(record)"))
    }

    /// T-654's rule, said in this ticket's store: the record is cleared only where the commit
    /// landed, so a refused bank leaves the session there to retry.
    @Test func theRecordIsClearedInsideTheDoBlockNotTheCatch() throws {
        let view = try #require(
            CadenceSourceScan.declarationBody("struct iOSFocusView", in: try Self.focusView())
        )
        let clear = try #require(view.range(of: "CadenceFocusSessionPersistence.clear()"))
        let afterClear = view[clear.upperBound...]
        let nextCatch = try #require(afterClear.range(of: "} catch {"))
        let nextRecord = afterClear.range(of: "CadenceTaskSettleFailureCenter.shared.record()")
        // The failure record comes after the `catch` that follows the clear — i.e. the clear is
        // on the success side of it.
        #expect(nextRecord != nil && nextRecord!.lowerBound > nextCatch.lowerBound)
    }

    /// [[T-6001]] persists; it must not have grown a second banking path. `endSession` stays the
    /// only writer of minutes on this screen, and the declined option (b) must not reappear.
    @Test func theScreenStillBanksThroughEndSessionAloneAndNotOnBackground() throws {
        let view = try Self.focusView()
        #expect(view.contains("CadenceFocusSupport.endSession("))
        #expect(!view.contains("scenePhase"))
    }

}
