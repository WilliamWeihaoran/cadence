import Foundation

/// **T-624.** Which linked calendar identifiers *this* device has seen EventKit actually carry.
///
/// `Area.linkedCalendarID` / `Project.linkedCalendarID` hold an `EKCalendar.calendarIdentifier`,
/// which Apple documents as local to one device, and those two properties live on **CloudKit-synced**
/// `@Model` types. So an identifier written on one device arrives on the others, and a device that
/// never issued it cannot look it up.
///
/// `CadenceCalendarLinkHealth` used to read that as "the calendar is gone", because absence from
/// this device's live set was the whole rule. The repair beside the report writes straight back to
/// the same synced property, so the second device's answer overwrites the first device's — a
/// repair on one device invalidating a link that was fine on the other.
///
/// **What is measured and what is not.** That the identifier is device-local is Apple's
/// documentation, not a measurement taken here; confirming it would mean touching EventKit on the
/// user's own machine. **This type does not depend on it.** It replaces "absent" with "was here and
/// is gone", which is the honest form of the claim either way:
///
/// - If identifiers *are* shared across devices, every device sees every linked calendar alive,
///   observes its identifier, and reports a deletion exactly as before. Nothing changes.
/// - If they are **not**, the device that never issued the identifier has no evidence of a
///   deletion, stays silent, and never offers the repair that would clobber the other device's
///   working link.
///
/// Either way a repair on one device cannot invalidate another device's link, and the failure mode
/// is under-reporting — a break this device cannot vouch for — never a false alarm inviting the
/// user to overwrite something that was fine.
///
/// Device-local **by construction**: `UserDefaults`, not a stored property. T-390 blocked companion
/// metadata on the two models because this project has no `SchemaMigrationPlan`, and
/// `CadenceEventKitPlatformParityTests` fails if a second `linkedCalendar*` property appears. This
/// needs neither: what one device has seen is not a fact about the list, and syncing it would
/// re-create the exact problem it exists to remove.
nonisolated enum CadenceCalendarLinkObservations {

    /// Newline-separated identifiers, matching `CalendarVisibilityPreferences`' encoding so the two
    /// device-local calendar preferences read the same way.
    static let observedCalendarIDsKey = "calendar.observedLinkedCalendarIDs.v1"

    static func observedCalendarIDs(from rawValue: String) -> Set<String> {
        Set(rawValue.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    static func rawObservedCalendarIDs(from ids: Set<String>) -> String {
        ids.sorted().joined(separator: "\n")
    }

    /// Every identifier any list currently links to, archived and finished lists included.
    ///
    /// Deliberately *not* the active subset that `missingLinks` reports on: an archived list's
    /// observation has to survive the archiving, or un-archiving it would produce a link this
    /// device has "never seen" and can no longer vouch for.
    static func linkedCalendarIDs(areas: [Area], projects: [Project]) -> Set<String> {
        var ids: Set<String> = []
        for area in areas where !area.linkedCalendarID.isEmpty {
            ids.insert(area.linkedCalendarID)
        }
        for project in projects where !project.linkedCalendarID.isEmpty {
            ids.insert(project.linkedCalendarID)
        }
        return ids
    }

    /// The set this device should hold after looking at what it can currently see.
    ///
    /// Learns an identifier only when it is **both linked and live here** — seeing a calendar this
    /// app is not linked to proves nothing about any link — and forgets one only when no list links
    /// it any more, which is what keeps the set bounded by the number of lists rather than growing
    /// with every calendar the user has ever had. One `intersection` does both: the linked-and-live
    /// half is `(O ∪ (L ∩ V)) ∩ L`, which is `(O ∪ V) ∩ L`, so writing the first form would leave a
    /// term no test could ever fail on.
    ///
    /// - Parameter isCalendarAccessAuthorized: without it `allCalendars` is empty, so this is the
    ///   guard against a blind device concluding it has seen nothing. It returns the set unchanged:
    ///   an unauthorized device must neither learn nor forget.
    ///
    /// Never forgets an identifier that is merely *not live right now*. That case is the whole
    /// point of the set — a dead link stays reported until the user resolves it, and a calendar
    /// account that has not finished loading must not erase the evidence in the meantime.
    static func observing(
        linkedCalendarIDs: Set<String>,
        liveCalendarIDs: Set<String>,
        isCalendarAccessAuthorized: Bool,
        observed: Set<String>
    ) -> Set<String> {
        guard isCalendarAccessAuthorized else { return observed }
        return observed.union(liveCalendarIDs).intersection(linkedCalendarIDs)
    }

    /// Records a calendar the user has just picked for a list, from anywhere in the app.
    ///
    /// A pick comes from a menu built out of live `EKCalendar`s, so a **changed** identifier is one
    /// this device can see by construction. This exists because `observing(...)` only runs while the
    /// calendar settings surface is on screen, and the list editor can link a calendar without ever
    /// going there — an unrecorded link would then be one this device could never report as broken.
    ///
    /// `replacing:` is the whole guard, and it is not a micro-optimisation. A save that leaves the
    /// calendar alone still passes the *stored* identifier, which may be one another device wrote;
    /// recording that would manufacture evidence this device does not have and revive exactly the
    /// false alarm the gate exists to remove — a list would need only a rename to start reporting
    /// its own good link as broken. So an identifier is recorded only when the save changed it.
    static func recordPick(
        _ calendarID: String,
        replacing storedCalendarID: String,
        defaults: UserDefaults = .standard
    ) {
        guard !calendarID.isEmpty, calendarID != storedCalendarID else { return }
        let raw = defaults.string(forKey: observedCalendarIDsKey) ?? ""
        var ids = observedCalendarIDs(from: raw)
        guard ids.insert(calendarID).inserted else { return }
        defaults.set(rawObservedCalendarIDs(from: ids), forKey: observedCalendarIDsKey)
    }
}
