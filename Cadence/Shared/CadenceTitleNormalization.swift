import Foundation

/// The one trim rule for every user-entered title or name, on both platforms.
///
/// macOS and iOS spelled the same intent two ways: several macOS forms trimmed `.whitespaces`
/// only (or saved the raw string), while their iOS siblings trimmed `.whitespacesAndNewlines`
/// (T-332). `"Name\n"` therefore round-tripped as `"Name\n"` on the Mac and `"Name"` on the
/// phone — a difference a paste can produce and no form can see. Route new name/title fields
/// here rather than picking whichever spelling the neighbouring file happens to use.
///
/// `.whitespacesAndNewlines` wins because it is the strictly stronger rule: a title is a
/// single-line value, so a trailing newline is never content, and the weaker spelling can only
/// ever let one through.
nonisolated enum CadenceTitleNormalization {
    /// The stored form of a user-entered title: trimmed at both ends, newlines included.
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the value carries no content. `" "` and `"\n"` are blank; this is the guard to
    /// write, not `raw.isEmpty`, which passes a whitespace-only string straight through.
    static func isBlank(_ raw: String) -> Bool {
        normalized(raw).isEmpty
    }

    /// The normalized title, or `fallback` when it is blank. Note that this returns the
    /// *trimmed* title, so a caller cannot accidentally store the untrimmed original after
    /// testing the trimmed one for emptiness.
    static func display(_ raw: String, fallback: String) -> String {
        let trimmed = normalized(raw)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

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
