import SwiftUI

/// The two facts an event editor states that the shared `CadenceSchedulePanel` has no row for
/// ([[T-8573]], under [[T-8201]]): **that the event repeats**, and **how long it is**.
///
/// It is one owner rather than two spellings because the Mac already had both and iOS had
/// neither, and the repository has paid repeatedly for two copies of one number. The macOS
/// `CalendarEventEditPopover.header` and the iOS `iOSCalendarEventEditSheet` both draw this view,
/// so the length arithmetic, the glyph, the word "Repeats" and the capsule exist once.
///
/// **The calendar dot and name are optional and only the Mac passes them.** The panel's Calendar
/// row names the calendar on both platforms, so the name is the one part of the Mac's old strip
/// that was never drift; it stays on the Mac because the owner's decision dropped nothing from the
/// Mac, and it stays off iOS because adding it would be a second saying of the Calendar row.
struct CadenceEventEditorHeaderStrip: View {
    /// The calendar's name, or empty to draw no calendar label at all.
    var calendarName: String = ""
    /// The calendar's hue, drawn as the dot beside the name. Ignored when `calendarName` is empty.
    var calendarColor: Color?
    /// Whether this event is a member of a repeating series: what
    /// `CadenceEventNoteSupport.isRecurringSeriesMember` answers, which is the one rule both
    /// platforms already read.
    let repeatsInSeries: Bool
    /// The event's length as `CadenceEventEditorHeaderFacts.durationLabel` prints it, or `nil`
    /// for an all-day event and for a schedule that names no instant.
    let durationLabel: String?

    private var drawsCalendarLabel: Bool { !calendarName.isEmpty }

    /// Nothing to say, so the host draws nothing: an untimed one-off event on iOS keeps the sheet
    /// it had before this view existed, rather than gaining an empty band above the panel.
    var isEmpty: Bool {
        !drawsCalendarLabel && !repeatsInSeries && durationLabel == nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            leadingLabel
            Spacer(minLength: 0)
            if let durationLabel {
                Text(durationLabel)
                    .cadenceFont(.metadata, base: 11, weight: .semibold)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface)
                    .clipShape(Capsule())
                    .accessibilityLabel(CadenceEventEditorHeaderFacts.durationAccessibilityLabel(durationLabel))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated)
    }

    @ViewBuilder
    private var leadingLabel: some View {
        if drawsCalendarLabel || repeatsInSeries {
            HStack(spacing: 5) {
                if drawsCalendarLabel {
                    Circle()
                        .fill(calendarColor ?? Theme.dim)
                        .frame(width: 7, height: 7)
                    Text(calendarName)
                        .cadenceFont(.metadata, base: 11, weight: .regular)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                if repeatsInSeries {
                    Image(systemName: CadenceEventEditorHeaderFacts.repeatSymbolName)
                        .cadenceFont(.metadata, base: 9, weight: .semibold)
                        .foregroundStyle(Theme.dim)
                    Text(CadenceEventEditorHeaderFacts.repeatsLabel)
                        .cadenceFont(.metadata, base: 11, weight: .medium)
                        .foregroundStyle(Theme.dim)
                }
            }
            // The glyph and the word are one reading, and the glyph is decoration beside it.
            .accessibilityElement(children: .combine)
        }
    }
}

/// What the strip above says, as values — so a test can ask the rule rather than the view, and so
/// neither platform computes an event's length for the header a second way ([[T-8573]]).
enum CadenceEventEditorHeaderFacts {
    static let repeatsLabel = "Repeats"
    static let repeatSymbolName = "repeat"

    /// The length the header's capsule prints, read off the instants the draft would **write**, so
    /// a multi-day event reads its real length rather than the one day a block was drawn on.
    ///
    /// `nil` for an all-day event — the panel's schedule row already says "All day" — and for a
    /// schedule that names no instant. The format is the shared estimate label, with its
    /// non-breaking space, and `"–"` where the two instants coincide.
    static func durationLabel(for draft: CadenceScheduleDraft, calendar: Calendar = .current) -> String? {
        guard !draft.isAllDay, let range = draft.eventDateRange(calendar: calendar) else { return nil }
        let minutes = Int(range.end.timeIntervalSince(range.start) / 60)
        return CadenceTaskPresentationSupport.estimateLabel(minutes: minutes, emptyPlaceholder: "–")
    }

    /// The capsule is a bare duration on screen; VoiceOver hears what the duration is of.
    static func durationAccessibilityLabel(_ durationLabel: String) -> String {
        "Lasts \(durationLabel)"
    }
}
