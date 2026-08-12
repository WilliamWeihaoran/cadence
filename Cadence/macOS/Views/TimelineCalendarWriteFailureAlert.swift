#if os(macOS)
import SwiftUI

/// Surfaces `CalendarManager.lastWriteFailure` on a timeline surface.
///
/// EventKit writes used to fail in silence: three early `return`s and a swallowed `catch` between
/// them meant that with no writable calendar, with the only calendar hidden in Settings →
/// Calendar, or with access revoked mid-session, drag-to-create completed, the popover dismissed,
/// the ghost cleared, and no event appeared. The failure is reported on the manager so a surface
/// can present it; this modifier is that presentation.
private struct CalendarWriteFailureAlert: ViewModifier {
    @Environment(CalendarManager.self) private var calendarManager

    func body(content: Content) -> some View {
        content.alert(
            calendarManager.lastWriteFailure?.title ?? "",
            isPresented: Binding(
                get: { calendarManager.lastWriteFailure != nil },
                set: { if !$0 { calendarManager.lastWriteFailure = nil } }
            ),
            presenting: calendarManager.lastWriteFailure
        ) { _ in
            Button("OK", role: .cancel) { calendarManager.lastWriteFailure = nil }
        } message: { failure in
            Text(failure.message)
        }
    }
}

extension View {
    func calendarWriteFailureAlert() -> some View {
        modifier(CalendarWriteFailureAlert())
    }
}
#endif
