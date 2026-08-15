import Foundation
import Testing
@testable import Cadence

/// The iOS focus picker draws a play glyph on every row. It used to sit *inside* the row's own
/// button label, so it could not receive a tap of its own: pressing what looked like "start this
/// task" only re-selected the task and left the clock at 00:00. It is a real control now, and this
/// is the state machine behind it.
@MainActor
struct FocusPickerPlayControlTests {
    private let taskA = UUID()
    private let taskB = UUID()

    private var epoch: Date { Date(timeIntervalSince1970: 1_000_000) }

    @Test func tappingPlayOnTheSelectedTaskStartsTheClock() {
        let next = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskA,
            selectedTaskID: taskA,
            state: CadenceFocusTimerState(),
            now: epoch
        )

        #expect(next.isRunning)
        #expect(next.elapsedSeconds(now: epoch.addingTimeInterval(30)) == 30)
    }

    /// One row is start and pause, so a second tap has to bank the elapsed seconds rather than
    /// discard them.
    @Test func tappingPlayAgainOnTheSameTaskPausesAndKeepsTheElapsedTime() {
        let started = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskA,
            selectedTaskID: taskA,
            state: CadenceFocusTimerState(),
            now: epoch
        )
        let paused = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskA,
            selectedTaskID: taskA,
            state: started,
            now: epoch.addingTimeInterval(45)
        )

        #expect(paused.isRunning == false)
        #expect(paused.elapsedSeconds(now: epoch.addingTimeInterval(600)) == 45)
    }

    /// The load-bearing one. Seconds on the clock were measured against the task they were started
    /// on; carrying them across would log one task's minutes onto another when the session is
    /// finished, because `complete(_:elapsedSeconds:)` banks whatever the clock reads.
    @Test func tappingPlayOnADifferentTaskStartsThatTaskFromZero() {
        let running = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskA,
            selectedTaskID: taskA,
            state: CadenceFocusTimerState(),
            now: epoch
        )
        let switched = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskB,
            selectedTaskID: taskA,
            state: running,
            now: epoch.addingTimeInterval(300)
        )

        #expect(switched.isRunning)
        #expect(switched.elapsedSeconds(now: epoch.addingTimeInterval(300)) == 0)
        #expect(switched.elapsedSeconds(now: epoch.addingTimeInterval(310)) == 10)
    }

    /// A paused session on another task is discarded the same way a running one is — the reset is
    /// about which task the seconds belong to, not about whether the clock happens to be ticking.
    @Test func aPausedSessionOnAnotherTaskIsNotInherited() {
        var banked = CadenceFocusTimerState()
        banked.accumulatedSeconds = 900

        let switched = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskB,
            selectedTaskID: taskA,
            state: banked,
            now: epoch
        )

        #expect(switched.isRunning)
        #expect(switched.elapsedSeconds(now: epoch) == 0)
    }

    /// Nothing selected yet is the cold-start case: the first row tapped becomes the session.
    @Test func tappingPlayWithNothingSelectedStartsFromZero() {
        let next = CadenceFocusSupport.timerState(
            afterPlayTapOn: taskA,
            selectedTaskID: nil,
            state: CadenceFocusTimerState(),
            now: epoch
        )

        #expect(next.isRunning)
        #expect(next.elapsedSeconds(now: epoch) == 0)
    }
}
