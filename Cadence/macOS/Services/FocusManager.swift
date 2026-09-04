#if os(macOS)
import SwiftData
import SwiftUI

@Observable
final class FocusManager {
    static let shared = FocusManager()

    enum ActiveSession {
        case task(AppTask)
        case bundle(TaskBundle)
    }

    var activeSession: ActiveSession? = nil
    var selectedBundleTaskIDs: Set<UUID> = []
    var isRunning: Bool = false
    var elapsed: Int = 0            // seconds in current session
    var wantsNavToFocus: Bool = false

    private init() {}

    var activeTask: AppTask? {
        get {
            guard case .task(let task) = activeSession else { return nil }
            return task
        }
        set {
            activeSession = newValue.map { .task($0) }
            if newValue == nil {
                selectedBundleTaskIDs.removeAll()
            }
        }
    }

    var activeBundle: TaskBundle? {
        guard case .bundle(let bundle) = activeSession else { return nil }
        return bundle
    }

    /// Begin focusing on a task, navigating to the focus view.
    /// If switching to a different task, commits any accumulated elapsed time first.
    ///
    /// **Throws on a refused switch, and does not switch over one (T-654).** `commitElapsed` now
    /// actually commits (it used to write the pending bank and never call `save()` at all — the
    /// worst of the three shapes this ticket found, since not even a swallowed `try?` sat between
    /// the write and the caller). Starting the new task anyway would show its clock at zero while
    /// the outgoing one's session — still running, un-banked — had nothing left pointing at it.
    func startFocus(
        task: AppTask,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        if activeTask?.id != task.id || activeBundle != nil {
            try commitElapsed(in: modelContext, commit: commit)
        }
        activeSession = .task(task)
        selectedBundleTaskIDs.removeAll()
        isRunning = true        // start immediately
        wantsNavToFocus = true
    }

    func startFocus(
        bundle: TaskBundle,
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        if activeBundle?.id != bundle.id || activeTask != nil {
            try commitElapsed(in: modelContext, commit: commit)
        }
        activeSession = .bundle(bundle)
        selectedBundleTaskIDs = CadenceFocusSupport.defaultSelectedTaskIDs(for: bundle)
        isRunning = true
        wantsNavToFocus = true
    }

    /// Commits elapsed seconds into the task's `actualMinutes` **and its list's `loggedMinutes`**.
    /// Pauses and resets the stopwatch so the next session starts fresh.
    ///
    /// This used to add to `actualMinutes` only, so running the timer never moved
    /// `project.loggedMinutes` — which an hours-mode goal reads. Two things made that hard to
    /// notice: macOS's *manual* "log session" sheet does roll up, so typing 25 minutes and
    /// running the timer for 25 minutes produced different totals on the same Mac; and the
    /// bundle branch below rolls up too, so a bundle timer credited the list and a single-task
    /// timer did not. It now goes through the same shared helper iOS uses.
    ///
    /// **It takes a `ModelContext` because banking now inserts.** Since T-621 each increment is a
    /// `FocusSessionLog` row, so this is a pending change and the rule that governs one
    /// (`AGENTS.md`, "The `try? save()` rule") requires the caller to own the commit rather than
    /// this helper to reach for an ambient store. That is why `startFocus` and `endSession` take
    /// one too: they are the frames that bank on the user's behalf.
    ///
    /// **Throws and takes `commit:` now (T-654).** It used to write the bank and stop — no `save()`
    /// of any kind, swallowed or otherwise, which is why `FocusView.timerControls`/
    /// `bundleTimerControls` were held in `CadenceSaveCommitRule.commitReachExemptions` rather than
    /// `existenceExemptions`: there was no commit for half 1/2 to find. Routes through the same
    /// `CadenceFocusSupport.logElapsedSeconds(_:across:in:commit:)` iOS uses — a single active task
    /// is a one-element credit list — so both platforms share one commit-and-undo shape. `isRunning`
    /// and `elapsed` are only cleared once that commit actually lands.
    func commitElapsed(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard elapsed > 0 else { return }
        let creditedTasks: [AppTask]
        switch activeSession {
        case .task(let task):
            creditedTasks = [task]
        case .bundle(let bundle):
            creditedTasks = CadenceFocusSupport.selectedTasks(in: bundle, selectedTaskIDs: selectedBundleTaskIDs)
        case nil:
            return
        }
        try CadenceFocusSupport.logElapsedSeconds(elapsed, across: creditedTasks, in: modelContext, commit: commit)
        isRunning = false
        elapsed = 0
    }

    /// Leave the current session the way switching to another one leaves it: bank the elapsed
    /// time against the task (or bundle) that earned it, then clear the session.
    ///
    /// Clearing `activeSession` directly is what the close buttons used to do, and it stranded the
    /// stopwatch: `isRunning` stayed `true`, so `FocusView`'s one-second timer kept incrementing
    /// `elapsed` with no session attached — the idle "Pick a task" card showed a clock still
    /// counting up. Picking the next task then called `startFocus`, whose `commitElapsed()` hit the
    /// `case nil` branch and zeroed `elapsed`, so a 25-minute session closed rather than switched
    /// away from logged nothing at all. `startFocus` already commits on a switch; closing is the
    /// same act of leaving a session, so it commits too.
    ///
    /// **Throws, and does not clear the session over a refusal (T-654).** The close button's own
    /// `onClose` names the refusal; leaving `activeSession` alone means the timer is still there,
    /// still running, if the user tries again rather than closing over lost minutes.
    func endSession(
        in modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try commitElapsed(in: modelContext, commit: commit)
        activeSession = nil
        selectedBundleTaskIDs.removeAll()
        reset()
    }

    func reset() {
        isRunning = false
        elapsed = 0
    }
}
#endif
