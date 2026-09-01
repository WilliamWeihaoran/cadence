import Foundation

/// One list whose `linkedCalendarID` names a calendar EventKit no longer has.
///
/// A value, not a model reference: the row that renders it needs a name, an icon and a colour, and
/// the write-back needs the list's `id`. Keeping the model out of the value means the detection
/// rule can be tested without a `ModelContext`.
nonisolated struct CadenceMissingCalendarLink: Identifiable, Hashable, Sendable {
    enum ListKind: String, Sendable {
        case area
        case project
    }

    /// The `Area.id` or `Project.id`, which is what the re-pick writes back through.
    let id: UUID
    let kind: ListKind
    let name: String
    let icon: String
    let colorHex: String
    /// The dead identifier, kept so the row can say which link is broken when a list is renamed
    /// between the break and the repair.
    let calendarID: String
}

/// **T-400.** Whether a list's calendar link still points at a calendar that exists.
///
/// `Area.linkedCalendarID` and `Project.linkedCalendarID` store an `EKCalendar.calendarIdentifier`
/// and nothing else — see the T-390 contract on `Area.linkedCalendarID` for why no title or source
/// sits beside it, and why a calendar that Apple Calendar deleted and recreated must *not* be
/// re-adopted on a name match. That decision left the link dead but said nothing about it being
/// visible, and it was not: every calendar surface in Settings is a list of *live* `EKCalendar`s
/// with the connected lists hanging off them, so a link whose calendar is gone renders nowhere at
/// all. The list simply stopped mirroring, silently.
///
/// Detection needs none of the metadata T-390 declined to store. A non-empty identifier that no
/// live calendar carries is already the whole test, and it is exact in both directions: EventKit
/// identifiers are opaque, so "not in this set" cannot be a near miss.
///
/// **Still no auto-matching.** This type reports the break and hands back the list; it never
/// proposes a replacement, and it deliberately does not look at a calendar's name. The re-pick is
/// the user's, from the same menu they linked with in the first place.
///
/// **T-624 — "not in this device's live set" was too weak a rule to act on.** The identifier is an
/// `EKCalendar.calendarIdentifier`, which Apple documents as local to one device, stored on a
/// **CloudKit-synced** `@Model`. So a link written on one device arrives on the others as an
/// identifier they never issued, and this detector could not tell that apart from a deletion. The
/// only control it offers writes back to the same synced property, so the second device's re-pick
/// overwrites the first device's link — a false alarm that repeats and repairs itself into the
/// other direction each time.
///
/// The rule is now "was here and is gone": a link is dead when this device has **previously seen
/// that identifier alive** and no longer does. `CadenceCalendarLinkObservations` keeps that record,
/// device-locally in `UserDefaults`, which is where it belongs — what one device has seen is not a
/// fact about the list, and it needs no stored property, so T-390's `SchemaMigrationPlan` block and
/// `CadenceEventKitPlatformParityTests`' guard against a second `linkedCalendar*` property both
/// stand untouched.
///
/// **Whether the identifiers actually differ across a user's devices is not measured** — that would
/// take an EventKit call, and Apple's documentation is not a measurement. This rule does not need
/// it. Under one shared identifier space every device observes every linked calendar and the report
/// is unchanged; under device-local ones the device with no evidence stays quiet. Either way a
/// repair on one device cannot invalidate another device's link, and the residual failure is
/// **under**-reporting a break this device cannot vouch for — the safe direction for a report whose
/// only action is destructive.
nonisolated enum CadenceCalendarLinkHealth {

    /// The row title. One spelling, so the two platform surfaces cannot drift.
    static let missingLinkTitle = "Linked calendar is missing"

    /// The eyebrow above the card, drawn only when `missingLinks` is non-empty — so it is a
    /// heading the reader sees exactly when there is something under it.
    ///
    /// Here rather than beside the rest of the Settings copy ([[T-524]]) because it belongs to
    /// this surface: the section exists only to hold the rows this type detects, and a rename that
    /// left the two out of step would be a heading over a card describing something else.
    static let brokenLinksSectionTitle = "Broken Calendar Links"

    /// The re-pick menu with nothing to re-pick. Reachable in one situation only — a link is dead
    /// *and* EventKit has no calendar at all — so it says the library is empty rather than telling
    /// the reader to make one, which is not something Cadence can do for them.
    static let noRelinkTargetsLabel = "No Apple calendars available"

    /// Every active list whose calendar link is dead, areas first, each group in the order given.
    ///
    /// - Parameter liveCalendarIDs: identifiers of **every** calendar EventKit has, including the
    ///   ones hidden from Cadence by `CalendarVisibilityPreferences`. Hidden is not missing: pass
    ///   the visible subset and every hidden calendar's links are reported dead, which is a false
    ///   alarm inviting the user to overwrite a link that was fine.
    /// - Parameter observedCalendarIDs: identifiers this device has itself seen EventKit carry
    ///   (T-624). A link is dead only if its identifier is in here and *not* in `liveCalendarIDs`;
    ///   an identifier this device has never seen is one it has no evidence about, most likely
    ///   because another device wrote it, and it is reported as nothing at all. Pass the live set
    ///   here and the gate is a no-op, which is the mistake it exists to prevent.
    /// - Parameter isCalendarAccessAuthorized: the guard against the loudest false positive there
    ///   is. Without authorization `allCalendars` is empty, so *every* link in the app looks dead
    ///   at once. It is a parameter rather than a call-site `if` because both platform surfaces
    ///   have to honour it and only one of them is compiled by the test target.
    ///
    /// Archived and finished lists are excluded, matching every other calendar-link affordance in
    /// Settings: the connect menu offers active lists only, so a row here for a list the menu
    /// cannot reach would be a break with no repair beside it.
    static func missingLinks(
        areas: [Area],
        projects: [Project],
        liveCalendarIDs: Set<String>,
        observedCalendarIDs: Set<String>,
        isCalendarAccessAuthorized: Bool
    ) -> [CadenceMissingCalendarLink] {
        guard isCalendarAccessAuthorized else { return [] }

        let areaLinks = areas.filter(\.isActive).compactMap { area in
            missingLink(
                id: area.id,
                kind: .area,
                name: area.name,
                icon: area.icon,
                colorHex: area.colorHex,
                linkedCalendarID: area.linkedCalendarID,
                liveCalendarIDs: liveCalendarIDs,
                observedCalendarIDs: observedCalendarIDs
            )
        }
        let projectLinks = projects.filter(\.isActive).compactMap { project in
            missingLink(
                id: project.id,
                kind: .project,
                name: project.name,
                icon: project.icon,
                colorHex: project.colorHex,
                linkedCalendarID: project.linkedCalendarID,
                liveCalendarIDs: liveCalendarIDs,
                observedCalendarIDs: observedCalendarIDs
            )
        }
        return areaLinks + projectLinks
    }

    /// What the row says under the list's name.
    ///
    /// Names the calendar as gone and the consequence, and stops there. It does not name a
    /// candidate replacement, because proposing one is the auto-match T-390 refused wearing a
    /// question mark.
    static func missingLinkSummary(for link: CadenceMissingCalendarLink) -> String {
        switch link.kind {
        case .area:
            "This area's Apple calendar no longer exists. Pick a calendar to link it again, or remove the link."
        case .project:
            "This project's Apple calendar no longer exists. Pick a calendar to link it again, or remove the link."
        }
    }

    private static func missingLink(
        id: UUID,
        kind: CadenceMissingCalendarLink.ListKind,
        name: String,
        icon: String,
        colorHex: String,
        linkedCalendarID: String,
        liveCalendarIDs: Set<String>,
        observedCalendarIDs: Set<String>
    ) -> CadenceMissingCalendarLink? {
        guard !linkedCalendarID.isEmpty,
              observedCalendarIDs.contains(linkedCalendarID),
              !liveCalendarIDs.contains(linkedCalendarID) else {
            return nil
        }
        return CadenceMissingCalendarLink(
            id: id,
            kind: kind,
            name: name,
            icon: icon,
            colorHex: colorHex,
            calendarID: linkedCalendarID
        )
    }
}
