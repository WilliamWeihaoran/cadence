#if os(macOS)
import SwiftUI

@Observable
final class FocusManager {
    static let shared = FocusManager()

    var activeTask: AppTask? = nil
    var isRunning: Bool = false
    var elapsed: Int = 0            // seconds in current session
    var wantsNavToFocus: Bool = false

    private init() {}

    /// Begin focusing on a task, navigating to the focus view.
    /// If switching to a different task, commits any accumulated elapsed time first.
    func startFocus(task: AppTask) {
        if activeTask?.id != task.id {
            commitElapsed()
        }
        activeTask = task
        isRunning = true        // start immediately
        wantsNavToFocus = true
    }

    /// Commits elapsed seconds (rounded UP to nearest minute) into the task's actualMinutes.
    /// Pauses and resets the stopwatch so the next session starts fresh.
    func commitElapsed() {
        guard let task = activeTask, elapsed > 0 else { return }
        task.actualMinutes += (elapsed + 59) / 60   // ceiling division
        isRunning = false
        elapsed = 0
    }

    func reset() {
        isRunning = false
        elapsed = 0
    }
}
#endif
