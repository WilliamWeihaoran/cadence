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
        // Three since T-266, and the third is a different act rather than a third switch path:
        // `.onDisappear` ends the session outright through `endSession(leaving:…)`, which the two
        // switch paths reach only via `commitElapsed`'s identity guard. The count is still exact —
        // a fourth `leaving: selectedSubject` means a commit was added somewhere unaccounted for.
        #expect(code.components(separatedBy: "leaving: selectedSubject").count - 1 == 3)
        #expect(code.components(separatedBy: "CadenceFocusSupport.endSession(").count - 1 == 1)
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


/// T-266: iOS could only enter a focus session from the Focus screen. macOS reaches one from four
/// other places, all through `FocusManager.startFocus(…)` — a singleton that is macOS-only on
/// purpose, because iOS's clock lives in `iOSFocusView`'s own `CadenceFocusTimerState` and a second
/// authority would have nothing incrementing it. What iOS was missing is the *message*, and these
/// are the two decisions the message forced: how a handoff starts the clock, and what happens to
/// the session already on it.
@MainActor
struct FocusHandoffTests {
    private let taskA = CadenceFocusTarget.task(UUID())
    private let taskB = CadenceFocusTarget.task(UUID())

    private var epoch: Date { Date(timeIntervalSince1970: 1_000_000) }

    private func runningClock(from seconds: Int, at start: Date) -> CadenceFocusTimerState {
        var state = CadenceFocusTimerState()
        state.accumulatedSeconds = seconds
        state.toggle(now: start)
        return state
    }

    // MARK: - Starting

    /// **The load-bearing one.** A handoff is not a play tap: routing it through
    /// `timerState(afterPlayTapOn:)` would *pause* the running session whenever the subject asked
    /// for is the subject already running — "Focus this" on the task you are already focusing would
    /// stop the clock. It has to leave a running session running.
    @Test func askingToFocusTheRunningSubjectLeavesItsClockAlone() {
        let running = runningClock(from: 0, at: epoch)

        let next = CadenceFocusSupport.timerState(
            startRequestFor: taskA,
            selectedTarget: taskA,
            state: running,
            now: epoch.addingTimeInterval(300)
        )

        #expect(next.isRunning)
        // Still counting from where it started, not restarted at zero.
        #expect(next.elapsedSeconds(now: epoch.addingTimeInterval(300)) == 300)
    }

    /// The same subject, paused: the handoff resumes it rather than discarding the banked seconds.
    @Test func askingToFocusThePausedSelectedSubjectResumesIt() {
        var banked = CadenceFocusTimerState()
        banked.accumulatedSeconds = 420

        let next = CadenceFocusSupport.timerState(
            startRequestFor: taskA,
            selectedTarget: taskA,
            state: banked,
            now: epoch
        )

        #expect(next.isRunning)
        #expect(next.elapsedSeconds(now: epoch) == 420)
    }

    /// A *different* subject starts from zero, for the reason the play control does: the seconds on
    /// the clock were earned by what they were started on. Banking them is `commitElapsed`'s job,
    /// which the caller runs first.
    @Test func askingToFocusADifferentSubjectStartsFromZero() {
        let running = runningClock(from: 0, at: epoch)

        let next = CadenceFocusSupport.timerState(
            startRequestFor: taskB,
            selectedTarget: taskA,
            state: running,
            now: epoch.addingTimeInterval(300)
        )

        #expect(next.isRunning)
        #expect(next.elapsedSeconds(now: epoch.addingTimeInterval(300)) == 0)
        #expect(next.elapsedSeconds(now: epoch.addingTimeInterval(310)) == 10)
    }

    /// Cold start: the screen has never been opened, so nothing is selected.
    @Test func askingToFocusWithNothingSelectedStartsRunningFromZero() {
        let next = CadenceFocusSupport.timerState(
            startRequestFor: taskA,
            selectedTarget: nil,
            state: CadenceFocusTimerState(),
            now: epoch
        )

        #expect(next.isRunning)
        #expect(next.elapsedSeconds(now: epoch) == 0)
    }

    /// A bundle and one of its members carry equal-looking ids in every other vocabulary; the
    /// target type is what keeps them apart, and the reset rule has to read it that way.
    @Test func aBundleAndItsMemberAreDifferentSubjectsEvenWithTheSameID() {
        let shared = UUID()
        let running = runningClock(from: 0, at: epoch)

        let next = CadenceFocusSupport.timerState(
            startRequestFor: .bundle(shared),
            selectedTarget: .task(shared),
            state: running,
            now: epoch.addingTimeInterval(300)
        )

        #expect(next.elapsedSeconds(now: epoch.addingTimeInterval(300)) == 0)
    }

    // MARK: - Leaving

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CadenceSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Walking away from the Focus screen banks what the session earned. Before T-266 the screen's
    /// clock was `@State` with nothing reading it on the way out, so a pop threw the minutes away —
    /// and a route *into* Focus from a task row makes backing straight out of it routine.
    @Test func endingASessionBanksItsMinutesOnTheTaskAndItsList() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(name: "Website")
        let task = AppTask(title: "Write copy")
        task.project = project
        context.insert(project)
        context.insert(task)

        var running = CadenceFocusTimerState()
        running.toggle(now: epoch)

        let next = CadenceFocusSupport.endSession(
            leaving: .task(task),
            state: running,
            modelContext: context,
            now: epoch.addingTimeInterval(18 * 60)
        )

        #expect(task.actualMinutes == 18)
        #expect(project.loggedMinutes == 18)
        #expect(next.isRunning == false)
        #expect(next.elapsedSeconds(now: epoch.addingTimeInterval(18 * 60)) == 0)
    }

    /// A block's minutes go to the members that were ticked while it ran, and to no one else — the
    /// whole reason the subject carries the selection rather than the bundle alone.
    @Test func endingABundleSessionCreditsOnlyTheTickedMembers() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let bundle = TaskBundle(title: "Morning", dateKey: "2026-08-24", startMin: 540, durationMinutes: 60)
        let included = AppTask(title: "Draft")
        let excluded = AppTask(title: "Email")
        included.bundle = bundle
        excluded.bundle = bundle
        // Assigned explicitly: the inverse is not back-populated before a save, and `sortedTasks`
        // reads `bundle.tasks`.
        bundle.tasks = [included, excluded]
        context.insert(bundle)
        context.insert(included)
        context.insert(excluded)

        var banked = CadenceFocusTimerState()
        banked.accumulatedSeconds = 30 * 60

        _ = CadenceFocusSupport.endSession(
            leaving: .bundle(bundle, selectedTaskIDs: [included.id]),
            state: banked,
            modelContext: context,
            now: epoch
        )

        #expect(included.actualMinutes == 30)
        #expect(excluded.actualMinutes == 0)
    }

    /// Under a whole minute writes nothing: `minutes(fromElapsedSeconds:)` rounds to the nearest
    /// minute and a zero is not a record. `actualMinutes` is the field to assert on —
    /// `estimatedMinutes` defaults to 30, so it would be asserting the default.
    @Test func endingASessionUnderOneMinuteWritesNothing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Write copy")
        context.insert(task)

        var banked = CadenceFocusTimerState()
        banked.accumulatedSeconds = 20

        _ = CadenceFocusSupport.endSession(
            leaving: .task(task),
            state: banked,
            modelContext: context,
            now: epoch
        )

        #expect(task.actualMinutes == 0)
    }

    /// Leaving with nothing loaded banks nothing and must not crash on the way through — the
    /// `onDisappear` that calls this fires on every exit, including one from an empty screen.
    @Test func endingWithNoSubjectBanksNothing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        var banked = CadenceFocusTimerState()
        banked.accumulatedSeconds = 25 * 60

        let next = CadenceFocusSupport.endSession(
            leaving: nil,
            state: banked,
            modelContext: context,
            now: epoch
        )

        #expect(next.elapsedSeconds(now: epoch) == 0)
    }

    /// The switching form still forwards through here, so re-selecting what is already focused is
    /// still not "leaving" — the identity guard lives above the bank, not inside it.
    @Test func reSelectingTheFocusedSubjectStillBanksNothing() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Write copy")
        context.insert(task)

        var banked = CadenceFocusTimerState()
        banked.accumulatedSeconds = 12 * 60

        let next = CadenceFocusSupport.commitElapsed(
            leaving: .task(task),
            switchingTo: .task(task.id),
            state: banked,
            modelContext: context,
            now: epoch
        )

        #expect(task.actualMinutes == 0)
        #expect(next.elapsedSeconds(now: epoch) == 12 * 60)
    }

    // MARK: - The inbox

    /// Two taps on the same task are two events. Without the token they would be `Equatable`-equal
    /// to the request already sitting in the inbox, so the `onChange` that drives navigation would
    /// not fire and the second tap would do nothing.
    @Test func twoRequestsForTheSameSubjectAreDistinctEvents() {
        let center = CadenceFocusHandoffCenter()
        let id = UUID()

        center.request(.task(id))
        let first = center.pending
        center.request(.task(id))
        let second = center.pending

        #expect(first?.target == .task(id))
        #expect(second?.target == .task(id))
        #expect(first?.id != second?.id)
    }

    /// Consuming is by token, so a request made while an older one was being adopted is not
    /// swallowed by the adopter of the older one.
    @Test func consumingClearsOnlyTheMatchingHandoff() {
        let center = CadenceFocusHandoffCenter()
        center.request(.task(UUID()))
        let stale = center.pending

        center.request(.bundle(UUID()))
        let current = center.pending

        center.consume(stale!)
        #expect(center.pending?.id == current?.id)

        center.consume(current!)
        #expect(center.pending == nil)
    }

    /// The handoff navigates through the shared routing table rather than a hand-spelled tab, so
    /// "which tab owns Focus" has one answer. On the compact shell that is More, *pushed* — Focus
    /// is not a tab root, and a route that cleared the stack instead would land on the More menu.
    @Test func aHandoffRoutesToTheTabThatOwnsFocus() {
        let route = CadenceFocusHandoff.destination.compactRoute

        #expect(CadenceFocusHandoff.destination == .focus)
        #expect(route.tab == .more)
        #expect(route.pushedDestination == .focus)
        #expect(route.tasksSection == nil)
    }
}

/// The iOS wiring, read out of the source. `Cadence/iOS/` is inside `#if os(iOS)` and invisible to
/// this macOS-built target, so source text is the only handle on it — and the lesson from T-161 is
/// that pinning a helper while nothing observes its call sites is how a fix becomes revertible with
/// a green suite.
@MainActor
struct FocusHandoffCallSiteTests {

    /// The Focus screen adopts a handoff, and adopts it through the *start* rule rather than the
    /// play control's toggle.
    @Test func theFocusScreenAdoptsAHandoffThroughTheStartRule() throws {
        let code = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSFocusView.swift"))

        #expect(code.contains("private func accept(_ handoff: CadenceFocusHandoff)"))
        #expect(code.components(separatedBy: "startRequestFor: handoff.target").count - 1 == 1)
        // And not through the toggle, which would pause the session it was asked to start.
        #expect(code.components(separatedBy: "afterPlayTapOn: handoff").count - 1 == 0)
        // Both arrival routes: cold (the screen is built by the navigation) and warm (it was
        // already standing behind another tab). Dropping either makes the affordance work only
        // sometimes, which is worse than not working.
        #expect(code.contains(".onAppear"))
        #expect(code.components(separatedBy: "focusHandoffCenter.pending").count - 1 >= 3)
        #expect(code.count > 8_000, "read \(code.count) characters of iOSFocusView and cannot be doing its job")
    }

    /// The shell navigates and the screen adopts — two pieces of knowledge, two places. A root view
    /// that also decided what happens to the running clock would be the second timer authority
    /// T-242 rejected, one level up.
    @Test func theShellRoutesToFocusWithoutTouchingTheSession() throws {
        let code = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSRootView.swift"))

        #expect(code.contains("func routeToFocus()"))
        #expect(code.contains("CadenceFocusHandoff.destination.compactRoute"))
        #expect(code.contains("focusHandoffCenter.pending?.id"))
        // No session vocabulary here at all.
        #expect(code.contains("CadenceFocusTimerState") == false)
        #expect(code.contains("commitElapsed") == false)
        #expect(code.count > 4_000, "read \(code.count) characters of iOSRootView and cannot be doing its job")
    }

    /// Every affordance, and both halves of `CadenceFocusTarget`. Shipping only the task half would
    /// leave the block half — the thing T-242 had just built — reachable from nowhere but Focus.
    ///
    /// It read `bothAffordancesRequestAHandoff` while there were two; the third (T-273) is the task
    /// inspector, which is what gives a task met on the Calendar Board or a day timeline a route —
    /// `iOSTaskRowContextMenu` hangs off `iOSTaskRow` and off nothing else.
    @Test func everyAffordanceRequestsAHandoff() throws {
        let rowCode = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSTaskRowActionViews.swift"))
        let blockCode = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSCalendarBundleDetailSheet.swift"))
        let sheetCode = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSTaskDetailSheet.swift"))

        #expect(rowCode.contains("struct iOSTaskRowContextMenu: View"))
        #expect(rowCode.contains("CadenceFocusHandoffCenter.shared.request(.task(task.id))"))

        #expect(blockCode.contains("struct iOSCalendarBundleDetailSheet: View"))
        #expect(blockCode.contains("CadenceFocusHandoffCenter.shared.request(.bundle(bundle.id))"))

        #expect(sheetCode.contains("struct iOSTaskDetailSheet: View"))
        #expect(sheetCode.contains("CadenceFocusHandoffCenter.shared.request(.task(task.id))"))
        // Non-vacuity: three needles that also match a doc comment would make this unfailable, so
        // the comment-stripped text has to be real code of a plausible size.
        #expect(sheetCode.count > 8_000, "read \(sheetCode.count) characters of iOSTaskDetailSheet and cannot be doing its job")
    }

    /// The inspector's entry is drawn *and* rendered — a `focusSection` that no `body` composes is
    /// a request no finger can make, and the source scan above cannot tell the difference.
    @Test func theInspectorRendersItsFocusEntry() throws {
        let sheetCode = try focusStrippingComments(focusSourceFile("Cadence/iOS/iOSTaskDetailSheet.swift"))

        #expect(sheetCode.components(separatedBy: "focusSection").count - 1 == 2)
        #expect(sheetCode.contains("private var focusSection: some View"))
    }

    /// The request is posted before the sheet dismisses, in that order.
    ///
    /// Reversed, the tap would be asking a view that is already being torn down to post it. The
    /// block sheet established the order; the inspector has the same two lines and there is no
    /// second place for them to disagree.
    @Test func theInspectorRequestsBeforeItDismisses() throws {
        for path in [
            "Cadence/iOS/iOSTaskDetailSheet.swift",
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift"
        ] {
            let code = try focusStrippingComments(focusSourceFile(path))
            let request = try #require(code.range(of: "CadenceFocusHandoffCenter.shared.request("))
            let dismissAfter = try #require(code.range(of: "dismiss()", range: request.upperBound ..< code.endIndex))
            // …and nothing else between them but whitespace and the closing paren of the request.
            let between = code[request.upperBound ..< dismissAfter.lowerBound]
            #expect(
                between.filter { !$0.isWhitespace }.count < 40,
                "\(path): dismiss() is no longer the next statement after the handoff request"
            )
        }
    }

    /// Both Focus entries name the Focus destination's own tint and glyph rather than spelling a
    /// palette decision twice. The block sheet shipped `Theme.amber` — the token
    /// `CadenceFeatureDestination.defaultColorHex` gives Today and Habits — and a second button
    /// naming one screen in a second colour is what that property's doc comment calls the drift.
    @Test func bothFocusEntriesReadTheDestinationsOwnTint() throws {
        for path in [
            "Cadence/iOS/iOSTaskDetailSheet.swift",
            "Cadence/iOS/iOSCalendarBundleDetailSheet.swift"
        ] {
            let code = try focusStrippingComments(focusSourceFile(path))
            #expect(code.contains("tint: CadenceFeatureDestination.focus.tint"), "\(path)")
            #expect(code.contains("systemImage: CadenceFeatureDestination.focus.systemImage"), "\(path)")
            // The exact retired spelling, not a bare `Theme.amber`: the block sheet legitimately
            // draws an amber overdue glyph, and a needle that fails on that is a needle that
            // forces the next agent to re-tint something unrelated.
            #expect(code.contains("tint: Theme.amber") == false, "\(path)")
        }
        #expect(CadenceFeatureDestination.focus.defaultColorHex == Theme.tealHex)
    }
}
