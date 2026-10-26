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
    /// [[T-6223]] gave the screen a `scenePhase` handler, so the pin is now said about that
    /// handler: it notes an instant and applies the absence rule, and banks nothing.
    @Test func theScreenStillBanksThroughEndSessionAloneAndNotOnBackground() throws {
        let view = try Self.focusView()
        #expect(view.contains("CadenceFocusSupport.endSession("))
        #expect(view.components(separatedBy: "CadenceFocusSupport.endSession(").count == 2)
        let phase = try #require(view.range(of: ".onChange(of: scenePhase)"))
        let handler = String(view[phase.lowerBound...].prefix(700))
        #expect(!handler.contains("endSession"))
        #expect(!handler.contains("commitElapsed"))
        #expect(!handler.contains("modelContext"))
    }

    // MARK: - [[T-6223]]: a gap past the threshold comes back paused

    private static let threshold = CadenceFocusAbsenceRule.unobservedGapThreshold

    private static func runningRecord(
        for task: AppTask,
        startedAt: Date,
        lastSeenAt: Date?
    ) throws -> CadenceFocusSessionRecord {
        var state = CadenceFocusTimerState()
        state.toggle(now: startedAt)
        return try #require(
            CadenceFocusSessionPersistence.record(target: .task(task.id), state: state, lastSeenAt: lastSeenAt)
        )
    }

    /// The owner's case: started at night, half an hour of work, force-quit, opened at eleven. The
    /// session comes back PAUSED holding the half hour it was seen for, not the night.
    @Test func aRunningSessionUnseenPastTheThresholdComesBackPausedAtItsLastSighting() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Late session")
        context.insert(task)

        let started = Date(timeIntervalSince1970: 6_000_000)
        let lastSeen = started.addingTimeInterval(1_800)
        let record = try Self.runningRecord(for: task, startedAt: started, lastSeenAt: lastSeen)
        let morning = lastSeen.addingTimeInterval(11 * 60 * 60)

        let resumed = try #require(
            CadenceFocusSessionPersistence.resumed(from: record, tasks: [task], now: morning)
        )
        #expect(resumed.target == .task(task.id))
        #expect(!resumed.state.isRunning)
        #expect(resumed.state.startedAt == nil)
        #expect(resumed.state.accumulatedSeconds == 1_800)
        // Paused means it stays put: an hour later it still reads the half hour.
        #expect(resumed.state.elapsedSeconds(now: morning.addingTimeInterval(3_600)) == 1_800)
    }

    /// The other side of the line: a gap up to the threshold is a glance and resumes live, exactly
    /// as [[T-6001]] decided. One second past it is not.
    @Test func aGapUpToTheThresholdResumesLiveAndOneSecondPastItDoesNot() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Glance")
        context.insert(task)

        let started = Date(timeIntervalSince1970: 7_000_000)
        let lastSeen = started.addingTimeInterval(600)
        let record = try Self.runningRecord(for: task, startedAt: started, lastSeenAt: lastSeen)

        let atTheLine = lastSeen.addingTimeInterval(Self.threshold)
        let live = try #require(
            CadenceFocusSessionPersistence.resumed(from: record, tasks: [task], now: atTheLine)
        )
        #expect(live.state.isRunning)
        #expect(live.state.elapsedSeconds(now: atTheLine) == 600 + Int(Self.threshold))

        let past = try #require(
            CadenceFocusSessionPersistence.resumed(from: record, tasks: [task], now: atTheLine.addingTimeInterval(1))
        )
        #expect(!past.state.isRunning)
        #expect(past.state.accumulatedSeconds == 600)
    }

    /// A paused session is already holding its reading; a long gap changes nothing about it. And a
    /// record with no sighting — written before this rule, or by a process that died in front —
    /// is no evidence of a gap and resumes as [[T-6001]] always did.
    @Test func aPausedSessionAndARecordWithNoSightingAreLeftAsTheyWere() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)
        let task = AppTask(title: "Held")
        context.insert(task)

        let paused = CadenceFocusSessionRecord(
            taskID: task.id,
            isRunning: false,
            startedAt: nil,
            accumulatedSeconds: 420,
            lastSeenAt: Date(timeIntervalSince1970: 8_000_000)
        )
        let later = Date(timeIntervalSince1970: 8_000_000 + 86_400)
        let resumedPaused = try #require(
            CadenceFocusSessionPersistence.resumed(from: paused, tasks: [task], now: later)
        )
        #expect(!resumedPaused.state.isRunning)
        #expect(resumedPaused.state.accumulatedSeconds == 420)

        let started = Date(timeIntervalSince1970: 8_000_000)
        let unsighted = try Self.runningRecord(for: task, startedAt: started, lastSeenAt: nil)
        let resumedLive = try #require(
            CadenceFocusSessionPersistence.resumed(from: unsighted, tasks: [task], now: later)
        )
        #expect(resumedLive.state.isRunning)
    }

    /// The sighting has to survive the trip to disk, and a record from the build before it must
    /// still decode rather than resolve to no session.
    @Test func theSightingRoundTripsAndARecordWrittenBeforeItStillDecodes() throws {
        try withTemporaryDefaults("cadence.tests.focusSession.sighting") { defaults in
            let record = CadenceFocusSessionRecord(
                taskID: UUID(),
                isRunning: true,
                startedAt: Date(timeIntervalSince1970: 9_000_000),
                accumulatedSeconds: 5,
                lastSeenAt: Date(timeIntervalSince1970: 9_000_600)
            )
            CadenceFocusSessionPersistence.write(record, to: defaults)
            #expect(CadenceFocusSessionPersistence.read(from: defaults)?.lastSeenAt == record.lastSeenAt)
        }
        let id = UUID()
        let legacy = #"{"taskID":"\#(id.uuidString)","isRunning":true,"startedAt":"1970-04-16T17:46:40Z","accumulatedSeconds":3}"#
        let decoded = try #require(CadenceFocusSessionPersistence.decoded(legacy))
        #expect(decoded.taskID == id)
        #expect(decoded.isRunning)
        #expect(decoded.lastSeenAt == nil)
    }

    /// The freeze is one function both platforms call. It holds the reading at the instant, leaves
    /// a stopped clock alone, and never reads less than what was already on the clock.
    @Test func theFreezeHoldsTheReadingAtTheInstantAndNeverTakesTimeOff() {
        let started = Date(timeIntervalSince1970: 10_000_000)
        var state = CadenceFocusTimerState()
        state.accumulatedSeconds = 60
        state.toggle(now: started)

        let frozen = CadenceFocusAbsenceRule.frozen(state, at: started.addingTimeInterval(300))
        #expect(!frozen.isRunning)
        #expect(frozen.startedAt == nil)
        #expect(frozen.accumulatedSeconds == 360)
        #expect(CadenceFocusAbsenceRule.frozen(frozen, at: started.addingTimeInterval(9_999)) == frozen)

        // A clock set back before the start cannot take the banked minute away.
        let setBack = CadenceFocusAbsenceRule.frozen(state, at: started.addingTimeInterval(-500))
        #expect(setBack.accumulatedSeconds == 60)
    }

    /// One rule, not two: the Mac's sleep freeze calls the shared function, and the iOS screen
    /// applies the same absence rule on return to the foreground as on a cold resume.
    @Test func theMacSleepAndTheIOSReturnBothGoThroughTheSharedRule() throws {
        let manager = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Services/FocusManager.swift")
        )
        let sleep = try #require(CadenceSourceScan.functionBody(named: "handleSystemWillSleep", in: manager))
        #expect(sleep.contains("CadenceFocusAbsenceRule.frozen(timerState, at: clock())"))

        let view = try Self.focusView()
        let phase = try #require(view.range(of: ".onChange(of: scenePhase)"))
        let handler = String(view[phase.lowerBound...].prefix(700))
        #expect(handler.contains("lastSeenAt = Date()"))
        #expect(handler.contains("CadenceFocusAbsenceRule.afterAbsence("))
        #expect(view.contains("lastSeenAt: lastSeenAt"))
    }

}
