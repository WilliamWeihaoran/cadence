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
        selectedBundleTaskIDs = Set(bundle.sortedTasks.map(\.id))
        isRunning = true
        wantsNavToFocus = true
    }

    /// Commits elapsed seconds (rounded UP to nearest minute) into the task's actualMinutes.
    /// Pauses and resets the stopwatch so the next session starts fresh.
    func commitElapsed() {
        guard elapsed > 0 else { return }
        let minutes = (elapsed + 59) / 60
        switch activeSession {
        case .task(let task):
            task.actualMinutes += minutes
        case .bundle(let bundle):
            FocusSessionSupport.distributeBundleMinutes(
                minutes,
                across: bundle.sortedTasks.filter { selectedBundleTaskIDs.contains($0.id) }
            )
        case nil:
            break
        }
        isRunning = false
        elapsed = 0
    }

    func reset() {
        isRunning = false
        elapsed = 0
    }
}
#endif
