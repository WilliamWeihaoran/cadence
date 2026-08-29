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
        case .hidden(let title): Self.hiddenTitle(title)
        case .missing: CadenceCalendarLinkHealth.missingLinkTitle
        }
    }

    /// "This calendar exists, and Cadence is not showing it", spelled once.
    ///
    /// **T-464.** The row and the picker both have to say this now — the row as its value, the
    /// picker as the label on the one hidden calendar it offers — and two surfaces wording the same
    /// state separately is how the pair drifts. `CadenceCalendarLinkHealth.missingLinkTitle` pins
    /// the *missing* wording for the same reason; this is the hidden half of it.
    ///
    /// **T-467.** The word itself now lives on `CadenceCalendarLinkExclusion`, because a second
    /// surface excludes calendars for a second reason and needs a second word for the same shape.
    static func hiddenTitle(_ title: String) -> String {
        CadenceCalendarLinkExclusion.hidden.title(title)
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

/// Why a calendar can be *stored* on a link and still sit outside the set a picker offers.
///
/// **T-467.** [[T-441]] and [[T-464]] built this machinery for one exclusion — the user has
/// unticked the calendar in Cadence's calendar settings — and spelled that word into the label.
/// The timeline's event editor excludes calendars for a different reason: it offers
/// `CalendarManager.writableCalendars`, while the timeline's events are fetched from
/// `availableCalendars`, which filters by visibility alone. So an event on an active **read-only**
/// subscribed calendar reached a picker its own calendar was not in, and the row under a card that
/// had just printed "Holidays" said "No calendar".
///
/// The two exclusions are the same shape and different words, so the shape is shared and the word
/// is a parameter. Calling a read-only calendar "(Hidden)" would be this family of tickets' own
/// collapse, one word further down.
nonisolated enum CadenceCalendarLinkExclusion: Equatable, Sendable, CaseIterable {
    /// The offer is what Cadence is showing; what it leaves out, the user hid in calendar settings.
    case hidden
    /// The offer is what the user can write to; what it leaves out is read-only or subscribed.
    case readOnly

    /// The parenthetical a surface puts after an excluded calendar's name.
    var qualifier: String {
        switch self {
        case .hidden: "Hidden"
        case .readOnly: "Read-only"
        }
    }

    /// An excluded calendar's name, spelled the one way every surface spells it.
    func title(_ title: String) -> String { "\(title) (\(qualifier))" }
}

/// One list's calendar link as the row *and* the picker see it, from one set of inputs.
///
/// **T-464.** [[T-441]] taught the row to tell `.hidden` from `.missing`, and left the picker
/// offering the visible subset alone — deliberately, on the reasoning that linking to a calendar
/// Cadence is not showing should be a decision made in calendar settings rather than fallen into
/// from a list editor. That reasoning is still right for calendars the user has *never* linked. It
/// is wrong for the one already stored: the row says "Team (Hidden)", and the picker it opens has
/// no Team in it. The user can read the state and cannot act on it — cannot re-pick the same
/// calendar, cannot even confirm it, and the only exit is "None", which is the silent overwrite
/// T-441 exists to prevent, now performed by hand.
///
/// So the offer is *visible, plus the linked one*. Exactly one hidden calendar can ever appear, and
/// only because it is already stored — no new hidden link can be made from here, which keeps the
/// T-441 decision intact where it applies.
///
/// The type exists so the two surfaces cannot disagree about which calendars are hidden. Before
/// this, hiddenness was the row's private subtraction of two arrays and the picker knew nothing
/// about it; now both read `rowState` and `pickableCalendars` off the same three stored values, and
/// the picker is *told* which ids are hidden rather than deciding again.
nonisolated struct CadenceCalendarLink: Equatable, Sendable {
    /// What the list stores. Empty means never linked.
    let linkedCalendarID: String
    /// Every calendar EventKit has, **including** the ones hidden from Cadence.
    let allCalendars: [CadenceCalendarChoice]
    /// The calendars Cadence is currently showing.
    let visibleCalendarIDs: Set<String>
    /// **T-467.** Why a calendar can be outside `visibleCalendarIDs` — the word for the one
    /// excluded calendar this link still offers. `.hidden` for the list editor, whose offer is
    /// visibility; `.readOnly` for the event editor, whose offer is writability. The default is
    /// `.hidden` because that is the offer every caller before T-467 had.
    let exclusion: CadenceCalendarLinkExclusion

    init(
        linkedCalendarID: String,
        allCalendars: [CadenceCalendarChoice],
        visibleCalendarIDs: Set<String>,
        exclusion: CadenceCalendarLinkExclusion = .hidden
    ) {
        self.linkedCalendarID = linkedCalendarID
        self.allCalendars = allCalendars
        self.visibleCalendarIDs = visibleCalendarIDs
        self.exclusion = exclusion
    }

    /// The EventKit-shaped call, for the row. Same reason the row state has one: an `EKCalendar`'s
    /// `calendarIdentifier` is read-only, so the decision is untestable in its EventKit shape.
    init(
        linkedCalendarID: String,
        allCalendars: [EKCalendar],
        visibleCalendars: [EKCalendar],
        exclusion: CadenceCalendarLinkExclusion = .hidden
    ) {
        self.init(
            linkedCalendarID: linkedCalendarID,
            allCalendars: allCalendars.map {
                CadenceCalendarChoice(id: $0.calendarIdentifier, title: $0.title)
            },
            visibleCalendarIDs: Set(visibleCalendars.map(\.calendarIdentifier)),
            exclusion: exclusion
        )
    }

    /// What the field row shows.
    var rowState: CadenceCalendarLinkRowState {
        CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: linkedCalendarID,
            allCalendars: allCalendars,
            visibleCalendarIDs: visibleCalendarIDs
        )
    }

    /// Whether this identifier names a calendar Cadence is not showing.
    ///
    /// The single question both surfaces ask. A `.missing` identifier answers `true` here too and
    /// that is harmless: it names no calendar, so it reaches no picker row and no label.
    func isExcluded(_ calendarID: String) -> Bool { !visibleCalendarIDs.contains(calendarID) }

    /// The same question under the name it had when visibility was the only offer.
    func isHidden(_ calendarID: String) -> Bool { isExcluded(calendarID) }

    /// The calendars the picker offers, in `allCalendars` order: everything visible, plus the
    /// linked one when it is hidden.
    ///
    /// Nothing is appended for a `.missing` link — there is no calendar to offer — so a dead link
    /// is still repaired by picking a live calendar, which is what T-400 wanted.
    var pickableCalendars: [CadenceCalendarChoice] {
        allCalendars.filter { choice in
            visibleCalendarIDs.contains(choice.id)
                || (!linkedCalendarID.isEmpty && choice.id == linkedCalendarID)
        }
    }

    /// The same offer as `[EKCalendar]`, which is what the picker draws: it needs each calendar's
    /// source for grouping and its `cgColor` for the dot, and neither survives the value type.
    func pickableCalendars(from calendars: [EKCalendar]) -> [EKCalendar] {
        let offered = Set(pickableCalendars.map(\.id))
        return calendars.filter { offered.contains($0.calendarIdentifier) }
    }

    /// The identifiers the picker has to label as hidden — at most one, by construction.
    var hiddenPickableCalendarIDs: Set<String> {
        Set(pickableCalendars.map(\.id).filter(isHidden))
    }

    /// What a picker row is called. Reads the row's own spelling rather than a second one.
    func pickerLabel(title: String, calendarID: String) -> String {
        isExcluded(calendarID) ? exclusion.title(title) : title
    }
}
