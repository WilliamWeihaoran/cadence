#if os(macOS)
import SwiftUI

@Observable
final class FocusManager {
    static let shared = FocusManager()

    var activeTask: AppTask? = nil
    var timerSeconds: Int = 25 * 60
    var isRunning: Bool = false
    var mode: TimerMode = .pomodoro
    var customMinutes: Int = 25

    enum TimerMode: String, CaseIterable {
        case pomodoro = "25 min"
        case fiftyTwo = "52 min"
        case custom   = "Custom"
        case stopwatch = "Stopwatch"

        var defaultSeconds: Int {
            switch self {
            case .pomodoro:  return 25 * 60
            case .fiftyTwo:  return 52 * 60
            case .custom:    return 25 * 60
            case .stopwatch: return 0
            }
        }
    }

    private init() {}

    func reset() {
        isRunning = false
        if mode == .stopwatch {
            timerSeconds = 0
        } else if mode == .custom {
            timerSeconds = customMinutes * 60
        } else {
            timerSeconds = mode.defaultSeconds
        }
    }
}
#endif
