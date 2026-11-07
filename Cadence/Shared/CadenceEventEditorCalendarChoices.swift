import EventKit
import SwiftUI

/// The Calendar row of an existing event's editor, on both platforms.
///
/// **[[T-12753]].** The Mac editor built its rows through `CadenceCalendarLink` ([[T-467]]), so a
/// read-only event's row read "Holidays (Read-only)"; the iOS sheet returned the bare calendar name
/// for a read-only event and `writableCalendars` titles otherwise, so the same event read "Holidays".
/// No hardware constraint separates them ([[T-8201]]). Both editors now call `choices` here.
///
/// The offer is `availableCalendars` (what the timeline can show) filtered to the writable ones plus
/// the event's own calendar, which is why `.readOnly` is always the true word for the one calendar
/// the link adds back. A read-only event's panel is inert, so on such an event only the row's label
/// is ever read.
enum CadenceEventEditorCalendarChoices {

    /// The event's calendar link, as the editor's Calendar row reads it.
    static func link(
        selectedID: String,
        availableCalendars: [CadenceCalendarChoice],
        writableCalendarIDs: Set<String>
    ) -> CadenceCalendarLink {
        CadenceCalendarLink(
            linkedCalendarID: selectedID,
            allCalendars: availableCalendars,
            visibleCalendarIDs: writableCalendarIDs,
            exclusion: .readOnly
        )
    }

    /// The panel's calendar rows: the link's offer, each worded by the link — so a read-only one
    /// reads "Holidays (Read-only)" in the row and the menu alike. When the selected calendar is in
    /// neither (an event with no calendar, or one the fetch no longer lists) the row still names what
    /// the link calls it rather than falling back to the panel's "Choose Calendar", which would read
    /// as a choice still to make.
    static func choices(
        link: CadenceCalendarLink,
        selectedID: String,
        color: (String) -> Color
    ) -> [CadenceSchedulePanelChoice] {
        var choices = link.pickableCalendars.map {
            CadenceSchedulePanelChoice(
                id: $0.id,
                name: link.pickerLabel(
                    title: CadenceTitleNormalization.display(
                        $0.title,
                        fallback: CadenceAppleCalendarNaming.unnamedCalendarTitle
                    ),
                    calendarID: $0.id
                ),
                color: color($0.id),
                systemImage: "calendar"
            )
        }
        if !choices.contains(where: { $0.id == selectedID }) {
            choices.append(
                CadenceSchedulePanelChoice(id: selectedID, name: link.rowState.valueText, color: Theme.dim)
            )
        }
        return choices
    }

    /// The EventKit-shaped call both editors make.
    static func choices(
        selectedID: String,
        availableCalendars: [EKCalendar],
        writableCalendars: [EKCalendar]
    ) -> [CadenceSchedulePanelChoice] {
        let link = link(
            selectedID: selectedID,
            availableCalendars: availableCalendars.map {
                CadenceCalendarChoice(id: $0.calendarIdentifier, title: $0.title)
            },
            writableCalendarIDs: Set(writableCalendars.map(\.calendarIdentifier))
        )
        let colors = Dictionary(
            availableCalendars.map { ($0.calendarIdentifier, $0.cgColor) },
            uniquingKeysWith: { first, _ in first }
        )
        return choices(link: link, selectedID: selectedID) { id in
            // `cgColor` is implicitly unwrapped and nil on a calendar EventKit has not coloured
            // yet; read as the orphan row's dim rather than trapping.
            colors[id].flatMap { $0 }.map { Color(cgColor: $0) } ?? Theme.dim
        }
    }
}
