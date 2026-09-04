import EventKit
import Foundation

/// One list's calendar link, as four different answers rather than one word.
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
/// **No auto-matching here either.** This reports which of the cases holds and stops. It never
/// proposes a replacement calendar and never rewrites the stored identifier — a broken link is left
/// broken, and visible, until the user re-picks. Clearing it here would be the silent overwrite the
/// ticket is about, wearing a repair's clothes.
///
/// **T-624 — there is a fourth case, and it used to be read as the third.** `.missing` was reached
/// from "no calendar *this device* has carries this identifier", which is the rule
/// `CadenceCalendarLinkHealth` stopped using: `Area.linkedCalendarID` / `Project.linkedCalendarID`
/// hold an `EKCalendar.calendarIdentifier`, which Apple documents as local to one device, on a
/// **CloudKit-synced** `@Model`. A link made on the iPhone therefore arrives on the Mac as an
/// identifier the Mac never issued, and the Mac cannot tell that apart from a deletion.
///
/// The Settings sweep was taught the difference and this row was not, so the false alarm simply
/// moved: the broken-links card stayed silent while the list editor's calendar row printed
/// *"Linked calendar is missing"* over a picker whose every option overwrites the other device's
/// working link. `.unverified` is that case named — stored, unseen here, and **not** claimed
/// broken.
///
/// Same reasoning as `CadenceCalendarLinkObservations`, and it does not depend on the unmeasured
/// fact either: under one shared identifier space every device has seen every linked calendar, so
/// `.unverified` is unreachable and this row says exactly what it said before; under device-local
/// ones the device with no evidence declines to call the link dead. The residual failure is
/// under-reporting a break this device cannot vouch for, which is the safe direction for a verdict
/// whose repair is destructive.
nonisolated enum CadenceCalendarLinkRowState: Equatable, Sendable {
    /// `linkedCalendarID` is empty: no link has ever been made.
    case unlinked
    /// Linked to a calendar that exists and that Cadence is showing.
    case linked(title: String)
    /// Linked to a calendar that exists and that the user has hidden from Cadence. The mirroring is
    /// intact; only this app's view of the calendar is switched off.
    case hidden(title: String)
    /// Linked to an identifier no calendar carries **and that this device has seen alive before**.
    /// `CadenceCalendarLinkHealth.missingLinks` is the same verdict reached over every list at once,
    /// off the same evidence.
    case missing
    /// Linked to an identifier no calendar carries and that this device has **never** seen — most
    /// likely one another device issued. Not a break: this device has no evidence either way, so it
    /// reports what it knows and offers no repair. See T-624 on the type above.
    case unverified

    /// What the field row shows as its value.
    var valueText: String {
        switch self {
        case .unlinked: Self.unlinkedText
        case .linked(let title): title
        case .hidden(let title): Self.hiddenTitle(title)
        case .missing: CadenceCalendarLinkHealth.missingLinkTitle
        case .unverified: Self.unverifiedText
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
    /// `.unverified` is set for the same reason and a stronger one: an identifier this device
    /// cannot resolve is still an identifier the other device is mirroring against.
    var isSet: Bool { self != .unlinked }

    /// The word for "no calendar", pinned here so the row and its tests cannot disagree about it.
    static let unlinkedText = "None"

    /// **T-624.** The word for a stored link this device cannot see and will not call broken.
    ///
    /// Deliberately not "Linked on another device", which claims more than is known: the same state
    /// is reached by a link this device made *before* it kept an observation record, which is the
    /// accepted under-report T-624 recorded rather than a peer's link. What is true in both is that
    /// the calendar is not on this device, so that is all it says.
    ///
    /// Deliberately not `CadenceCalendarLinkHealth.missingLinkTitle` either. That sentence is a
    /// verdict with a repair beside it; this one is an absence of evidence, and wording them the
    /// same collapses the distinction the case exists to draw — the T-441 mistake, one state along.
    static let unverifiedText = "Linked calendar is not on this device"

    /// - Parameter allCalendars: every calendar EventKit has, **including** the ones hidden from
    ///   Cadence. Passing the visible subset is the bug: `.hidden` becomes unreachable and every
    ///   hidden link reports `.missing`.
    /// - Parameter visibleCalendarIDs: identifiers of the calendars Cadence is currently showing —
    ///   the same subset the picker offers.
    /// - Parameter evidence: where the identifier came from, which is what decides whether "no
    ///   calendar here carries it" means `.missing` or `.unverified`. See
    ///   `CadenceCalendarLinkEvidence`; `.deviceLocal` is the default because it is the truthful
    ///   answer for every identifier read off a live EventKit object, and a link read out of a
    ///   **synced** `linkedCalendarID` has to say `.synced` instead.
    static func forLink(
        linkedCalendarID: String,
        allCalendars: [CadenceCalendarChoice],
        visibleCalendarIDs: Set<String>,
        evidence: CadenceCalendarLinkEvidence = .deviceLocal
    ) -> CadenceCalendarLinkRowState {
        guard !linkedCalendarID.isEmpty else { return .unlinked }
        guard let match = allCalendars.first(where: { $0.id == linkedCalendarID }) else {
            return evidence.vouchesFor(linkedCalendarID) ? .missing : .unverified
        }
        return visibleCalendarIDs.contains(match.id) ? .linked(title: match.title) : .hidden(title: match.title)
    }

    /// The EventKit-shaped call, for the row. Separate from the value-shaped one above so the
    /// decision can be tested without an `EKCalendar`, whose `calendarIdentifier` is read-only and
    /// therefore not a thing a test can arrange.
    static func forLink(
        linkedCalendarID: String,
        allCalendars: [EKCalendar],
        visibleCalendars: [EKCalendar],
        evidence: CadenceCalendarLinkEvidence = .deviceLocal
    ) -> CadenceCalendarLinkRowState {
        forLink(
            linkedCalendarID: linkedCalendarID,
            allCalendars: allCalendars.map {
                CadenceCalendarChoice(id: $0.calendarIdentifier, title: $0.title)
            },
            visibleCalendarIDs: Set(visibleCalendars.map(\.calendarIdentifier)),
            evidence: evidence
        )
    }
}

/// **T-624.** Whether this device can vouch for a linked calendar identifier it cannot currently
/// resolve — which is the difference between "the calendar was deleted" and "I have never seen it".
///
/// The two callers of `CadenceCalendarLink` hold identifiers of genuinely different provenance, and
/// before this they were treated alike:
///
/// - The timeline's event editor reads its identifier off an `EKEvent` **this device just fetched**.
///   An identifier that arrived through EventKit is one EventKit has, so "no match" there really is
///   a deletion and nothing is gated.
/// - The list editor reads `Area.linkedCalendarID` / `Project.linkedCalendarID`, which CloudKit
///   syncs between devices while `EKCalendar.calendarIdentifier` is documented as local to one. A
///   Mac holding an identifier its iPhone minted cannot resolve it and has learned nothing by
///   failing to.
///
/// So the parameter is provenance, not a set of ids — a caller cannot satisfy it by handing over
/// the live calendars, which would make the gate a no-op while looking like it was being honoured.
/// That is the mistake `CadenceCalendarLinkHealth.missingLinks` warns about in prose for its own
/// `observedCalendarIDs`, spelled here as something the type system refuses.
nonisolated enum CadenceCalendarLinkEvidence: Equatable, Sendable {
    /// The identifier came off a live EventKit object on this device, so this device has seen it by
    /// construction and an unresolvable one is genuinely gone.
    case deviceLocal
    /// The identifier came out of a CloudKit-synced `linkedCalendarID`. Carries the identifiers this
    /// device has itself seen EventKit carry — `CadenceCalendarLinkObservations`, the same record
    /// `CadenceCalendarLinkHealth.missingLinks` reads.
    case synced(observedCalendarIDs: Set<String>)

    /// Whether this device has any standing to call the identifier's calendar deleted.
    func vouchesFor(_ calendarID: String) -> Bool {
        switch self {
        case .deviceLocal: true
        case .synced(let observedCalendarIDs): observedCalendarIDs.contains(calendarID)
        }
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

    /// The parenthetical a surface puts after an excluded calendar's name — and, since T-598, the
    /// word on the badge beside it.
    ///
    /// **T-598(b).** Both calendar settings screens drew their own `Text("Read Only")` pill next to
    /// a calendar the user cannot write to, while this enum was already spelling the same fact
    /// `"Read-only"` in the picker one tap away and
    /// `CadenceCalendarEventEditingSupport.readOnlyNotice` was saying "read-only calendar" in prose.
    /// Three spellings of one fact, on one feature, two of them a hyphen apart.
    ///
    /// The hyphenated form wins because it is the compound adjective English actually has, and
    /// because the prose was already using it; the badges now read it rather than re-typing it.
    /// Note that `"Read-only"` is nine characters, under
    /// `CadenceSharedConstantReuseSweepTests`' twelve-character floor, so that sweep will never
    /// catch a fourth surface typing it out again — `CadenceCalendarLinkHealthTests` carries the
    /// guard instead.
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
    /// **T-624.** Where `linkedCalendarID` came from, which decides whether an identifier this
    /// device cannot resolve is `.missing` or `.unverified`. `.deviceLocal` by default: it is the
    /// truthful answer for an identifier read off a live `EKEvent`, and the one caller reading a
    /// **CloudKit-synced** `linkedCalendarID` — `ListEditorCalendarRow` — passes `.synced`.
    let evidence: CadenceCalendarLinkEvidence

    init(
        linkedCalendarID: String,
        allCalendars: [CadenceCalendarChoice],
        visibleCalendarIDs: Set<String>,
        exclusion: CadenceCalendarLinkExclusion = .hidden,
        evidence: CadenceCalendarLinkEvidence = .deviceLocal
    ) {
        self.linkedCalendarID = linkedCalendarID
        self.allCalendars = allCalendars
        self.visibleCalendarIDs = visibleCalendarIDs
        self.exclusion = exclusion
        self.evidence = evidence
    }

    /// The EventKit-shaped call, for the row. Same reason the row state has one: an `EKCalendar`'s
    /// `calendarIdentifier` is read-only, so the decision is untestable in its EventKit shape.
    init(
        linkedCalendarID: String,
        allCalendars: [EKCalendar],
        visibleCalendars: [EKCalendar],
        exclusion: CadenceCalendarLinkExclusion = .hidden,
        evidence: CadenceCalendarLinkEvidence = .deviceLocal
    ) {
        self.init(
            linkedCalendarID: linkedCalendarID,
            allCalendars: allCalendars.map {
                CadenceCalendarChoice(id: $0.calendarIdentifier, title: $0.title)
            },
            visibleCalendarIDs: Set(visibleCalendars.map(\.calendarIdentifier)),
            exclusion: exclusion,
            evidence: evidence
        )
    }

    /// What the field row shows.
    var rowState: CadenceCalendarLinkRowState {
        CadenceCalendarLinkRowState.forLink(
            linkedCalendarID: linkedCalendarID,
            allCalendars: allCalendars,
            visibleCalendarIDs: visibleCalendarIDs,
            evidence: evidence
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
    /// is still repaired by picking a live calendar, which is what T-400 wanted. Nor for an
    /// `.unverified` one, for the same reason and with a different consequence: the offer is the
    /// ordinary connect menu, unchanged, so the user can still deliberately link this device's list
    /// to a calendar. What T-624 removed is the app *telling* them the link is broken first.
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
