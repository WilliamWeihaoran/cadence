import Foundation
import SwiftData
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

/// T-186: iOS discarded the focus timer whenever the session moved to another task.
///
/// macOS has always committed first — `FocusManager.startFocus(task:)` and `startFocus(bundle:)`
/// both call `commitElapsed()` before switching. iOS reset the clock instead, on **both** of its
/// switch paths, so the only way measured minutes ever reached `actualMinutes` was finishing the
/// task. The visible symptom was that a goal with `progressType == "hours"` could only be advanced
/// from a Mac, because the list `loggedMinutes` behind it moves through this helper alone.
///
/// **Two kinds of test, and the second kind is the point.** `logElapsedSeconds` was already
/// correct and already covered; T-161 is the standing example of a fix that was revertible with a
/// green suite because the tests pinned a helper and nothing observed the call sites. So the switch
/// decision is asserted behaviorally *and* the two iOS call sites are read out of the source file —
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so source text
/// is the only handle on it.
@MainActor
struct FocusSessionSwitchCommitTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private var epoch: Date { Date(timeIntervalSince1970: 1_000_000) }

    private func runningClock(from seconds: Int) -> CadenceFocusTimerState {
        var state = CadenceFocusTimerState()
        state.accumulatedSeconds = seconds
        return state
    }

    /// The load-bearing one: 25 minutes measured on one task, then the user picks another. The
    /// minutes land on the task *and* on the list an hours-mode goal reads.
    @Test func leavingATaskBanksItsMinutesOnTheTaskAndOnItsList() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "Website")
        let outgoing = AppTask(title: "Write copy")
        outgoing.project = project
        let incoming = AppTask(title: "Review copy")
        context.insert(project)
        context.insert(outgoing)
        context.insert(incoming)

        let next = CadenceFocusSupport.commitElapsed(
            leaving: outgoing,
            switchingTo: incoming.id,
            state: runningClock(from: 25 * 60),
            modelContext: context,
            now: epoch
        )

        #expect(outgoing.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
        // The incoming task starts from zero — the seconds were measured against the other one.
        #expect(incoming.actualMinutes == 0)
        #expect(next.elapsedSeconds(now: epoch) == 0)
        #expect(next.isRunning == false)
    }

    /// A clock still ticking has to be read at the moment of the switch, not from
    /// `accumulatedSeconds`: the picker's play control leaves it running.
    @Test func aRunningClockIsReadAtTheMomentOfTheSwitch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let area = Area(name: "Life")
        let outgoing = AppTask(title: "Errand")
        outgoing.area = area
        context.insert(area)
        context.insert(outgoing)

        var running = CadenceFocusTimerState()
        running.toggle(now: epoch)

        _ = CadenceFocusSupport.commitElapsed(
            leaving: outgoing,
            switchingTo: UUID(),
            state: running,
            modelContext: context,
            now: epoch.addingTimeInterval(10 * 60)
        )

        #expect(outgoing.actualMinutes == 10)
        #expect(area.loggedMinutes == 10)
    }

    /// Tapping the row you are already focused on is not leaving a session. It used to reset the
    /// clock — the same discard, one tap earlier.
    @Test func reSelectingTheFocusedTaskLeavesTheClockAlone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Write copy")
        context.insert(task)

        let next = CadenceFocusSupport.commitElapsed(
            leaving: task,
            switchingTo: task.id,
            state: runningClock(from: 12 * 60),
            modelContext: context,
            now: epoch
        )

        #expect(next.elapsedSeconds(now: epoch) == 12 * 60)
        #expect(task.actualMinutes == 0)
    }

    /// Under a whole minute writes nothing at all. `minutes(fromElapsedSeconds:)` rounds to the
    /// nearest minute, so 20 seconds is a zero, and a zero is not a record.
    ///
    /// The field that must not move is `actualMinutes`, which starts at 0. `estimatedMinutes` is
    /// **not** part of this: it defaults to 30, so asserting "nothing was written" against it
    /// would be asserting the default rather than the behaviour.
    @Test func aClockUnderOneMinuteWritesNothing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "Website")
        let outgoing = AppTask(title: "Write copy")
        outgoing.project = project
        context.insert(project)
        context.insert(outgoing)

        let next = CadenceFocusSupport.commitElapsed(
            leaving: outgoing,
            switchingTo: UUID(),
            state: runningClock(from: 20),
            modelContext: context,
            now: epoch
        )

        #expect(outgoing.actualMinutes == 0)
        #expect(project.loggedMinutes == 0)
        #expect(outgoing.estimatedMinutes == 30)
        #expect(next.elapsedSeconds(now: epoch) == 0)
    }

    /// Switching with no session loaded has nothing to bank and must not crash on the way through.
    @Test func switchingWithNothingFocusedBanksNothing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let next = CadenceFocusSupport.commitElapsed(
            leaving: nil,
            switchingTo: UUID(),
            state: runningClock(from: 25 * 60),
            modelContext: context,
            now: epoch
        )

        #expect(next.elapsedSeconds(now: epoch) == 0)
    }

    // MARK: - The call sites

    /// **Both** switch paths, counted exactly. The reset rule has two entry points — the picker
    /// row's `select(_:)` and its play control's `toggleSession(for:)` — and fixing one leaves the
    /// bug half-present, which a "contains" assertion would not notice.
    @Test func bothIOSSwitchPathsCommitTheOutgoingTasksTime() throws {
        let code = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(code.components(separatedBy: "CadenceFocusSupport.commitElapsed(").count - 1 == 2)
        // And the old spelling is gone from them. Three live `resetTimer()` occurrences remain:
        // its own declaration, `complete(_:)`, and — since T-242 — `logBundleSession(_:)`, which
        // hands a block's minutes to its ticked members and then clears the clock, the same shape
        // `complete(_:)` has for a single task. The reset *button* passes `resetTimer` unapplied.
        #expect(code.components(separatedBy: "resetTimer()").count - 1 == 3)
    }

    /// The scan is worthless if it reads nothing, and a scan that returns an empty string passes
    /// every count above by accident. This is the non-vacuity check.
    ///
    /// The two signatures took a `CadenceFocusPickItem` in T-242 rather than an `AppTask`, because
    /// the row being picked can now be a block. Pinning the *new* spelling is the point: a scan
    /// that still named the old one would go quietly vacuous the moment it stopped matching.
    @Test func theScanActuallyReachesTheIOSFocusView() throws {
        let code = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(code.contains("struct iOSFocusView: View"))
        #expect(code.contains("private func select(_ item: CadenceFocusPickItem)"))
        #expect(code.contains("private func toggleSession(for item: CadenceFocusPickItem)"))
        #expect(code.count > 8_000, "read \(code.count) characters of iOSFocusView and cannot be doing its job")
    }

    /// **T-242 fired this tripwire, and it is replaced rather than deleted.** It used to read
    /// `code.contains("TaskBundle") == false` with the note "if that changes, this fails and the
    /// commit has to be added there" — which is exactly what happened: `iOSFocusView` now loads a
    /// `TaskBundle`, so the assertion has to become the positive one it was standing in for.
    ///
    /// What must hold is that **both** switch paths hand `commitElapsed` a `CadenceFocusSubject`,
    /// not a task. A subject carries the block's ticked members with it, and that is the only thing
    /// that knows where a block session's minutes go; passing `selectedItem` or a bare id would
    /// either credit every member or none, unrecoverably, once the clock is reset.
    @Test func theIOSBundleFocusPathCommitsThroughTheSubjectShapedRule() throws {
        let code = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(code.contains("TaskBundle"))
        #expect(code.contains("private var selectedSubject: CadenceFocusSubject?"))
        #expect(code.components(separatedBy: "leaving: selectedSubject").count - 1 == 2)
        // And the task-shaped overload is gone from this screen: leaving a block through it is
        // unspellable, which is the whole reason the subject type exists.
        #expect(code.components(separatedBy: "leaving: selectedTask,").count - 1 == 0)
    }
}

// MARK: - Source-reading helpers

private func focusRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func focusSourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: focusRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` and `/* */` comments so the counts above read code rather than the prose that
/// describes it — this file's own doc comments name `commitElapsed` and `resetTimer` repeatedly.
private func focusStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
