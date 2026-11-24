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

    /// **The writable calendars an existing event's editor offers** -- the manager's, plus on a
    /// fixture launch the served fixture calendars that accept writes.
    ///
    /// [[T-12942]]: a fixture launch is EventKit-disarmed, so the managers' lists arrive empty and
    /// an opened fixture event's row would read as a missing calendar. The fixture's own calendars
    /// stand in, read-only ones left out by EventKit's own question. `[]` is added on every launch
    /// outside the fixture gate, which leaves the list exactly as passed.
    ///
    /// [[T-19924]]: one answer for the menu AND the notice. The notice used to ask the manager's
    /// bare `writableCalendars`, which is empty on a fixture launch, so a writable fixture event's
    /// editor said "No writable calendars are available." above a menu that offered `Work`.
    static func offeredWritableCalendars(
        _ writableCalendars: [EKCalendar],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [EKCalendar] {
        writableCalendars
            + CadenceCalendarFixtureEvents.servedCalendars(in: environment).filter(\.allowsContentModifications)
    }

    /// What an existing event's editor says in place of its Calendar row when there is nothing it
    /// could move the event to: `nil` on a read-only event (its panel is inert, and its row names
    /// its own calendar), and otherwise asked of `offeredWritableCalendars`, the list the menu
    /// draws from. Both editors call this, so the sentence and the menu cannot disagree.
    static func unavailableNotice(
        isEditable: Bool,
        writableCalendars: [EKCalendar],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard isEditable,
              offeredWritableCalendars(writableCalendars, environment: environment).isEmpty
        else { return nil }
        return noWritableCalendarSentence
    }

    static let noWritableCalendarSentence = "No writable calendars are available."

    /// The EventKit-shaped call both editors make.
    static func choices(
        selectedID: String,
        availableCalendars: [EKCalendar],
        writableCalendars: [EKCalendar],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [CadenceSchedulePanelChoice] {
        let fixtureCalendars = CadenceCalendarFixtureEvents.servedCalendars(in: environment)
        let availableCalendars = availableCalendars + fixtureCalendars
        let writableCalendars = offeredWritableCalendars(writableCalendars, environment: environment)
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
