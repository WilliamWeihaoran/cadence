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

extension CalendarManager {
    /// Reports one write outcome on a surface that is **holding the user's draft** (T-658).
    ///
    /// The alert above is the backstop for surfaces with nothing on screen to write under — a
    /// drag-move, a resize, an all-day chip dropped on the timeline. An event editor is not one of
    /// those: it has a title, notes, a chosen calendar and a time range in it, so a refusal belongs
    /// beside the button that was pressed and the editor has to stay open to hold them.
    ///
    /// Clearing `lastWriteFailure` is part of reporting, not a tidy-up. Two reports of one refusal
    /// is one too many, and on macOS an alert raised over a popover dismisses that popover — which
    /// is exactly the draft loss this exists to stop.
    ///
    /// `onCommitted` defaults to doing nothing so a caller that refused *before* reaching EventKit
    /// — an unformable date range — can report `.refused` without inventing a success branch.
    func report(
        _ outcome: CadenceCalendarWriteOutcome,
        into notice: Binding<String?>,
        onCommitted: () -> Void = {}
    ) {
        notice.wrappedValue = outcome.failureNotice
        if outcome.closesEditor {
            onCommitted()
        } else {
            lastWriteFailure = nil
        }
    }
}
#endif
