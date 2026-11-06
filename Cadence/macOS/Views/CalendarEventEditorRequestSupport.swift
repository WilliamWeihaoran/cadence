#if os(macOS)
import SwiftUI

extension EnvironmentValues {
    /// Whether event blocks and chips below this point answer
    /// `CalendarNavigationManager.eventEditorRequest` ([[T-11196]] (1)). Only the Calendar page sets
    /// it: Cmd+K selects that page, and the same `TimelineEventBlock` also draws in Today's
    /// schedule pane and the timeline overlay, which must not take the request and open a popover
    /// somewhere the reader is not looking.
    @Entry var honoursCalendarEventEditorRequests: Bool = false
}

/// The block's half of "open this event's editor once its day is drawn" ([[T-11196]] (1)).
///
/// Checked when the block appears -- the usual case, since the jump is what draws the day -- and
/// when a request arrives while it is already on screen. The open is deferred a beat so the page's
/// jump has scrolled the block into place before a popover anchors on it.
private struct CalendarEventEditorRequestHonour: ViewModifier {
    let eventID: String
    let open: () -> Void

    @Environment(\.honoursCalendarEventEditorRequests) private var honours
    @Environment(CalendarNavigationManager.self) private var navigation: CalendarNavigationManager?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: honourIfAsked)
            .onChange(of: navigation?.eventEditorRequest?.token) { _, _ in honourIfAsked() }
    }

    private func honourIfAsked() {
        guard honours, navigation?.takeEventEditorRequest(for: eventID) == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + CalendarEventEditorRequestTiming.settleDelay) {
            open()
        }
    }
}

enum CalendarEventEditorRequestTiming {
    /// Long enough for the page's jump to have scrolled the day into place.
    static let settleDelay: TimeInterval = 0.25
}

extension View {
    /// Opens this event's editor when Cmd+K asked for it ([[T-11196]] (1)).
    func honoursCalendarEventEditorRequest(eventID: String, open: @escaping () -> Void) -> some View {
        modifier(CalendarEventEditorRequestHonour(eventID: eventID, open: open))
    }
}
#endif
