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

/// One **inactive** list — archived, completed, paused or cancelled — that still holds a calendar
/// link.
///
/// **T-557.** The same shape as `CadenceMissingCalendarLink` and deliberately not the same type:
/// nothing here is broken. The link is intact and dormant, and saying so is the whole point.
nonisolated struct CadenceDormantCalendarLink: Identifiable, Hashable, Sendable {
    /// The `Area.id` or `Project.id`, which is what the disconnect writes back through.
    let id: UUID
    let kind: CadenceMissingCalendarLink.ListKind
    let name: String
    let icon: String
    let colorHex: String
    /// The stored identifier. Kept for parity with the missing-link row and **never resolved
    /// against EventKit here** — see `CadenceCalendarLinkHealth.dormantLinks(areas:projects:)`.
    let calendarID: String
    /// The list's own status word — "Archived", "Completed", "Paused", "Cancelled" — read from
    /// `CadenceListSearchLifecycle`, which is where this app already spells them. The section
    /// heading says "dormant"; the row says which kind of dormant, because `Area` has three
    /// inactive states and `Project` four and collapsing them is how a cancelled project comes to
    /// be labelled archived.
    let statusLabel: String
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

    // MARK: - T-557: a link on an inactive list

    /// The eyebrow above the dormant-link card, drawn only when `dormantLinks` is non-empty.
    /// Deliberately parallel to `brokenLinksSectionTitle`, and deliberately not the same word:
    /// these links are not broken.
    static let dormantLinksSectionTitle = "Dormant Calendar Links"

    /// The one spelling of the disconnect, read by both the broken row and the dormant row on both
    /// platforms — four call sites that had begun as two copies of the same two words.
    static let removeLinkLabel = "Remove Link"

    /// Every **inactive** list that still holds a calendar link, areas first, each group in the
    /// order given.
    ///
    /// **T-557.** Archiving a list keeps its `linkedCalendarID`, so un-archiving restores the
    /// connection intact — that is the decision, not an oversight. What was missing is any way to
    /// *see* it: `missingLinks` above narrows to active lists by the policy stated in its own
    /// contract, the connect menu offers active lists only, and the per-calendar summary in
    /// Settings lists active connections only. So the stored identifier survived in a place with
    /// no reader and no control, and the only way to clear it was to un-archive the list first.
    ///
    /// **This is an addition to that active-only policy, not a reversal of it.** `missingLinks` is
    /// untouched and still reports active lists only: an archived list's link is not *missing*, it
    /// is dormant, and the two want opposite things from the user — a re-pick and nothing at all.
    ///
    /// **It asks EventKit nothing, and that is load-bearing (T-624).** There is no
    /// `liveCalendarIDs`, no `observedCalendarIDs` and no authorization flag in this signature,
    /// because whether an inactive list holds a link is a fact about this app's own store and not
    /// about any calendar. So this cannot call a link dead on a device that has never seen its
    /// calendar — it never calls a link dead at all — and it cannot weaken the evidence gate
    /// `CadenceCalendarLinkObservations` exists to hold. The row it feeds offers a disconnect and
    /// no re-pick for the same reason: a re-pick writes a fresh identifier into a CloudKit-synced
    /// property, which is exactly the clobber T-624 removed.
    ///
    /// Disjoint from `missingLinks` by construction: that one filters `isActive`, this one filters
    /// its negation, so no list can appear in both cards.
    static func dormantLinks(areas: [Area], projects: [Project]) -> [CadenceDormantCalendarLink] {
        let areaLinks = areas.filter { !$0.isActive }.compactMap { area in
            dormantLink(
                id: area.id,
                kind: .area,
                name: CadenceTitleNormalization.display(
                    area.name,
                    fallback: CadenceTitleNormalization.defaultAreaName
                ),
                icon: area.icon,
                colorHex: area.colorHex,
                linkedCalendarID: area.linkedCalendarID,
                statusLabel: CadenceListSearchSupport.lifecycle(of: area).statusLabel
            )
        }
        let projectLinks = projects.filter { !$0.isActive }.compactMap { project in
            dormantLink(
                id: project.id,
                kind: .project,
                name: CadenceTitleNormalization.display(
                    project.name,
                    fallback: CadenceTitleNormalization.defaultProjectName
                ),
                icon: project.icon,
                colorHex: project.colorHex,
                linkedCalendarID: project.linkedCalendarID,
                statusLabel: CadenceListSearchSupport.lifecycle(of: project).statusLabel
            )
        }
        return areaLinks + projectLinks
    }

    /// What the dormant row says under the list's name.
    ///
    /// Says the link is **kept**, because that is the behaviour and because the alternative
    /// reading — "this is broken, fix it" — is the one the row must not invite. It names no
    /// calendar: the stored identifier may well be one another device issued, and resolving it
    /// against this device's EventKit is the question T-624 stopped asking.
    static func dormantLinkSummary(for link: CadenceDormantCalendarLink) -> String {
        switch link.kind {
        case .area:
            "This area is not active, so Cadence has stopped mirroring it. The Apple calendar link is kept and resumes if the area becomes active again."
        case .project:
            "This project is not active, so Cadence has stopped mirroring it. The Apple calendar link is kept and resumes if the project becomes active again."
        }
    }

    private static func dormantLink(
        id: UUID,
        kind: CadenceMissingCalendarLink.ListKind,
        name: String,
        icon: String,
        colorHex: String,
        linkedCalendarID: String,
        statusLabel: String
    ) -> CadenceDormantCalendarLink? {
        guard !linkedCalendarID.isEmpty else { return nil }
        return CadenceDormantCalendarLink(
            id: id,
            kind: kind,
            name: name,
            icon: icon,
            colorHex: colorHex,
            calendarID: linkedCalendarID,
            statusLabel: statusLabel
        )
    }
}
