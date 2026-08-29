import Foundation

/// Titles for EventKit events, on both platforms.
///
/// Two defects lived here (T-380). macOS wrote `title.isEmpty ? "New Event" : title` in
/// `CalendarManager.createStandaloneEvent` and again in `TimelineDayCanvas`, so a
/// whitespace-only title was *not* empty, passed the guard, and became a real event titled
/// `" "`. And the placeholder itself disagreed: macOS said `"New Event"` where iOS said
/// `"Untitled Event"`.
///
/// `"Untitled Event"` is the surviving label. It matches the placeholder family the rest of the
/// app already uses (`"Untitled Task"`, `"Untitled Column"`, `"Untitled <list noun>"`), and
/// unlike `"New Event"` it does not go stale — an event created last year is not new, but it is
/// still untitled.
nonisolated enum CadenceEventTitleSupport {
    static let defaultDisplayTitle = "Untitled Event"

    static func normalized(_ raw: String) -> String {
        CadenceTitleNormalization.normalized(raw)
    }

    static func isBlank(_ raw: String) -> Bool {
        CadenceTitleNormalization.isBlank(raw)
    }

    /// What to write to `EKEvent.title` for a user-entered string. Never blank, never untrimmed.
    static func storedTitle(_ raw: String) -> String {
        CadenceTitleNormalization.display(raw, fallback: defaultDisplayTitle)
    }

    /// What to draw for an event already in the store, whose title may be `nil`, blank, or
    /// untrimmed because something other than Cadence wrote it.
    static func displayTitle(_ raw: String?) -> String {
        CadenceTitleNormalization.display(raw ?? "", fallback: defaultDisplayTitle)
    }
}
