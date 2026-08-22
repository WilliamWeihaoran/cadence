#if os(macOS)
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
    func startFocus(task: AppTask) {
        if activeTask?.id != task.id || activeBundle != nil {
            commitElapsed()
        }
        activeSession = .task(task)
        selectedBundleTaskIDs.removeAll()
        isRunning = true        // start immediately
        wantsNavToFocus = true
    }

    func startFocus(bundle: TaskBundle) {
        if activeBundle?.id != bundle.id || activeTask != nil {
            commitElapsed()
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
    func commitElapsed() {
        guard elapsed > 0 else { return }
        switch activeSession {
        case .task(let task):
            CadenceFocusSupport.logElapsedSeconds(elapsed, to: task)
        case .bundle(let bundle):
            CadenceFocusSupport.logElapsedSeconds(
                elapsed,
                across: CadenceFocusSupport.selectedTasks(in: bundle, selectedTaskIDs: selectedBundleTaskIDs)
            )
        case nil:
            break
        }
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
    func endSession() {
        commitElapsed()
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
