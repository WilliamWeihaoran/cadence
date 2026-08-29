import EventKit
import Foundation

/// One list's calendar link, as three different answers rather than one word.
///
/// **T-441.** `ListEditorCalendarRow` rendered `selectedTitle ?? "None"`, and it looked that title
/// up in `CalendarManager.availableCalendars` — the *visible* subset, with everything the user has
/// unticked in Cadence's calendar settings already filtered out. So three unrelated situations
/// arrived at the row as the same string:
///
/// - the list was never linked to a calendar;
/// - it is linked to a live calendar the user has merely **hidden** from Cadence;
/// - it is linked to a calendar Apple Calendar has **deleted**.
///
/// They need three different things from the user — nothing, a visibility tick, and a re-pick — and
/// the row offered one reading for all of them. The second is the damaging one: a link that is
/// perfectly intact reads as absent, so a user "setting" the calendar they believe is missing
/// overwrites a link that was working.
///
/// `CadenceCalendarLinkHealth` already draws this line and names the exact trap in its
/// `liveCalendarIDs` contract — *"Hidden is not missing: pass the visible subset and every hidden
/// calendar's links are reported dead, which is a false alarm inviting the user to overwrite a link
/// that was fine."* That is the row's bug stated a file away. This type asks the same question one
/// link at a time, for a field row rather than for a Settings-wide sweep over models, and it takes
/// **both** lists so the distinction is spellable at all rather than collapsing at the call site.
///
/// The dead-link wording is read from `CadenceCalendarLinkHealth.missingLinkTitle`, not re-typed:
/// two surfaces report the same break, and that type keeps the one spelling for exactly this
/// reason.
///
/// **No auto-matching here either.** This reports which of the three cases holds and stops. It
/// never proposes a replacement calendar and never rewrites the stored identifier — a broken link
/// is left broken, and visible, until the user re-picks. Clearing it here would be the silent
/// overwrite the ticket is about, wearing a repair's clothes.
nonisolated enum CadenceCalendarLinkRowState: Equatable, Sendable {
    /// `linkedCalendarID` is empty: no link has ever been made.
    case unlinked
    /// Linked to a calendar that exists and that Cadence is showing.
    case linked(title: String)
    /// Linked to a calendar that exists and that the user has hidden from Cadence. The mirroring is
    /// intact; only this app's view of the calendar is switched off.
    case hidden(title: String)
    /// Linked to an identifier no calendar carries. `CadenceCalendarLinkHealth.missingLinks` is the
    /// same verdict reached over every list at once.
    case missing

    /// What the field row shows as its value.
    var valueText: String {
        switch self {
        case .unlinked: Self.unlinkedText
        case .linked(let title): title
        case .hidden(let title): "\(title) (Hidden)"
        case .missing: CadenceCalendarLinkHealth.missingLinkTitle
        }
    }

    /// Whether the row draws its value as a set field.
    ///
    /// `.missing` is **set**. Something is stored, and the row's job is to say that it is stored and
    /// broken; dimming it back to the unset treatment is the collapse this type exists to undo.
    var isSet: Bool { self != .unlinked }

    /// The word for "no calendar", pinned here so the row and its tests cannot disagree about it.
    static let unlinkedText = "None"

    /// - Parameter allCalendars: every calendar EventKit has, **including** the ones hidden from
    ///   Cadence. Passing the visible subset is the bug: `.hidden` becomes unreachable and every
    ///   hidden link reports `.missing`.
    /// - Parameter visibleCalendarIDs: identifiers of the calendars Cadence is currently showing —
    ///   the same subset the picker offers.
    static func forLink(
        linkedCalendarID: String,
        allCalendars: [CadenceCalendarChoice],
        visibleCalendarIDs: Set<String>
    ) -> CadenceCalendarLinkRowState {
        guard !linkedCalendarID.isEmpty else { return .unlinked }
        guard let match = allCalendars.first(where: { $0.id == linkedCalendarID }) else {
            return .missing
        }
        return visibleCalendarIDs.contains(match.id) ? .linked(title: match.title) : .hidden(title: match.title)
    }

    /// The EventKit-shaped call, for the row. Separate from the value-shaped one above so the
    /// decision can be tested without an `EKCalendar`, whose `calendarIdentifier` is read-only and
    /// therefore not a thing a test can arrange.
    static func forLink(
        linkedCalendarID: String,
        allCalendars: [EKCalendar],
        visibleCalendars: [EKCalendar]
    ) -> CadenceCalendarLinkRowState {
        forLink(
            linkedCalendarID: linkedCalendarID,
            allCalendars: allCalendars.map {
                CadenceCalendarChoice(id: $0.calendarIdentifier, title: $0.title)
            },
            visibleCalendarIDs: Set(visibleCalendars.map(\.calendarIdentifier))
        )
    }
}

/// An identifier and a title — the whole of what the decision above reads off a calendar.
///
/// A value rather than an `EKCalendar` so the rule can be tested: `EKCalendar.calendarIdentifier`
/// is read-only and minted by EventKit, so a test cannot arrange the "linked to a calendar that is
/// hidden" case out of real ones.
nonisolated struct CadenceCalendarChoice: Equatable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
