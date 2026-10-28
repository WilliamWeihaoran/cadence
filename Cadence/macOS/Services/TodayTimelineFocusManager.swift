#if os(macOS)
import SwiftUI

@Observable
final class TodayTimelineFocusManager {
    static let shared = TodayTimelineFocusManager()

    var focusRequestID: Int = 0

    /// **Whether Today's own Timeline pane is mounted** ([[T-7986]]). `TodayView` writes it from
    /// the layout it picked: false in `CadenceDesktopTodayLayout.tasksOnly`, where `SchedulePanel`
    /// is not built and a focus request is heard by nothing. Cmd+\ reads it to choose between
    /// focusing that pane and toggling the timeline overlay. Ignored by observation: no view draws
    /// from it, and a write on every resize must not invalidate the panel that observes
    /// `focusRequestID`.
    @ObservationIgnored var isTodayTimelinePaneMounted = false

    private init() {}

    func requestFocus() {
        focusRequestID &+= 1
    }
}
#endif
