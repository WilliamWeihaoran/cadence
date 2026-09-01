import Foundation
import Testing
@testable import Cadence

/// **T-624 — a device-local EventKit identifier is stored in CloudKit.**
///
/// `Area.linkedCalendarID` / `Project.linkedCalendarID` are `EKCalendar.calendarIdentifier`s on
/// CloudKit-synced `@Model` types. Detection asked "is this identifier in *this device's* live
/// calendar set", and the repair beside it writes back to the same synced property — so if the
/// identifiers differ across devices, each device reports the other's good link as broken and each
/// repair invalidates the other. Nothing is lost; it is a repeating false alarm that costs the user
/// a re-pick every time they switch machines.
///
/// **The premise is not measured here and these tests do not assume it.** Whether one iCloud
/// calendar carries different identifiers on this user's Mac and iPhone would take an EventKit call
/// on the user's own machine to establish, and Apple's documentation that the identifier is local
/// is documentary evidence rather than a measurement. So the fix is written to be right either way:
/// a device declares a link dead only for an identifier it has itself seen alive.
///
/// - Identifiers shared across devices: every device observes every linked calendar, and the T-400
///   report is exactly what it was.
/// - Identifiers device-local: the device that never issued the identifier has no evidence of a
///   deletion, says nothing, and never offers a repair that would overwrite a working link.
///
/// The invariant that holds under both, and is the reason this lands on its own: **a repair on one
/// device cannot invalidate another device's link.** The residual cost is under-reporting — a break
/// this device genuinely cannot vouch for — which is the safe direction for a control whose only
/// action is destructive.
struct CadenceCalendarLinkObservationsTests {

    private func area(_ name: String, linkedTo calendarID: String) -> Area {
        let area = Area(name: name)
        area.linkedCalendarID = calendarID
        return area
    }

    private func project(_ name: String, linkedTo calendarID: String) -> Project {
        let project = Project(name: name)
        project.linkedCalendarID = calendarID
        return project
    }

    // MARK: - The gate

    /// The finding, as behaviour. The Mac wrote `cal-mac`; the iPhone syncs the property, has never
    /// issued that identifier, and must not conclude the calendar was deleted.
    @Test func aLinkNamingAnIdentifierThisDeviceHasNeverSeenIsNotReportedMissing() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-mac")],
            projects: [],
            liveCalendarIDs: ["cal-iphone"],
            observedCalendarIDs: ["cal-iphone"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.isEmpty)
    }

    /// The other half, and the one that keeps T-400 alive: an identifier this device *did* see and
    /// no longer sees is a deletion, and is still reported.
    @Test func aLinkThisDeviceOnceSawAliveAndNoLongerDoesIsStillReportedMissing() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-gone")],
            projects: [project("Launch", linkedTo: "cal-gone")],
            liveCalendarIDs: ["cal-work"],
            observedCalendarIDs: ["cal-gone", "cal-work"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.map(\.name) == ["Home", "Launch"])
        #expect(links.allSatisfy { $0.calendarID == "cal-gone" })
    }

    /// Both devices, in order, with the identifiers differing — the premise the ticket could not
    /// measure. The point is that the repair on the Mac leaves the iPhone's stored link alone
    /// because the iPhone never offered one.
    @Test func aRepairOnOneDeviceCannotInvalidateTheOtherDevicesLink() {
        let home = area("Home", linkedTo: "cal-mac")

        // The Mac: it issued `cal-mac`, Apple Calendar has since deleted it, so it reports.
        let onTheMac = CadenceCalendarLinkHealth.missingLinks(
            areas: [home],
            projects: [],
            liveCalendarIDs: ["cal-mac-2"],
            observedCalendarIDs: ["cal-mac", "cal-mac-2"],
            isCalendarAccessAuthorized: true
        )
        #expect(onTheMac.count == 1)

        // The iPhone, same synced value, its own identifier space: no evidence, no report, so no
        // re-pick and no write back to the synced property.
        let onThePhone = CadenceCalendarLinkHealth.missingLinks(
            areas: [home],
            projects: [],
            liveCalendarIDs: ["cal-iphone"],
            observedCalendarIDs: ["cal-iphone"],
            isCalendarAccessAuthorized: true
        )
        #expect(onThePhone.isEmpty)

        // And if the premise is false — one identifier space — the phone has observed it too, and
        // the deletion is real on both. Nothing about this gate depends on which world we are in.
        let sharedIdentifierSpace = CadenceCalendarLinkHealth.missingLinks(
            areas: [home],
            projects: [],
            liveCalendarIDs: ["cal-mac-2"],
            observedCalendarIDs: ["cal-mac", "cal-mac-2"],
            isCalendarAccessAuthorized: true
        )
        #expect(sharedIdentifierSpace.count == 1)
    }

    /// The gate narrows; it must not widen. An unlinked list stays out, and so does the
    /// unauthorized device, whichever way the observation set falls.
    @Test func theEvidenceGateDoesNotReviveTheOlderFalsePositives() {
        #expect(
            CadenceCalendarLinkHealth.missingLinks(
                areas: [area("Home", linkedTo: "")],
                projects: [],
                liveCalendarIDs: ["cal-work"],
                observedCalendarIDs: ["", "cal-work"],
                isCalendarAccessAuthorized: true
            ).isEmpty
        )
        #expect(
            CadenceCalendarLinkHealth.missingLinks(
                areas: [area("Home", linkedTo: "cal-gone")],
                projects: [],
                liveCalendarIDs: [],
                observedCalendarIDs: ["cal-gone"],
                isCalendarAccessAuthorized: false
            ).isEmpty
        )
    }

    // MARK: - Maintaining the set

    /// Learns what is linked *and* live. A calendar the user has but no list links proves nothing
    /// about any link, and letting it in would make the set grow with the calendar library.
    @Test func theObservationSetLearnsOnlyIdentifiersThatAreBothLinkedAndLiveHere() {
        let updated = CadenceCalendarLinkObservations.observing(
            linkedCalendarIDs: ["cal-work", "cal-mac"],
            liveCalendarIDs: ["cal-work", "cal-unlinked"],
            isCalendarAccessAuthorized: true,
            observed: []
        )

        #expect(updated == ["cal-work"])
    }

    /// A dead link must stay reported. "Not live right now" is precisely the state the set exists
    /// to describe, so it can never be a reason to forget.
    @Test func anIdentifierThatIsMerelyAbsentKeepsItsObservation() {
        let updated = CadenceCalendarLinkObservations.observing(
            linkedCalendarIDs: ["cal-gone"],
            liveCalendarIDs: [],
            isCalendarAccessAuthorized: true,
            observed: ["cal-gone"]
        )

        #expect(updated == ["cal-gone"])
    }

    /// Unlinking is the one thing that forgets, which is what bounds the set by the number of lists
    /// rather than by the user's calendar history.
    @Test func anIdentifierNoListLinksAnyMoreIsForgotten() {
        let updated = CadenceCalendarLinkObservations.observing(
            linkedCalendarIDs: ["cal-work"],
            liveCalendarIDs: ["cal-work", "cal-old"],
            isCalendarAccessAuthorized: true,
            observed: ["cal-work", "cal-old"]
        )

        #expect(updated == ["cal-work"])
    }

    /// Without authorization `allCalendars` is empty, so a device that learns or forgets here would
    /// erase every observation it has and then be unable to report anything at all.
    @Test func anUnauthorizedDeviceNeitherLearnsNorForgets() {
        let observed: Set<String> = ["cal-work", "cal-old"]
        let updated = CadenceCalendarLinkObservations.observing(
            linkedCalendarIDs: ["cal-work"],
            liveCalendarIDs: [],
            isCalendarAccessAuthorized: false,
            observed: observed
        )

        #expect(updated == observed)
    }

    /// Archived and finished lists are outside `missingLinks`, but their identifiers must stay in
    /// the set — un-archiving a list must not produce a link this device can no longer vouch for.
    @Test func anArchivedListsIdentifierIsStillCountedAsLinked() {
        let archived = area("Home", linkedTo: "cal-home")
        archived.status = .archived
        let finished = project("Launch", linkedTo: "cal-launch")
        finished.status = .done

        #expect(
            CadenceCalendarLinkObservations.linkedCalendarIDs(
                areas: [archived, area("Unlinked", linkedTo: "")],
                projects: [finished]
            ) == ["cal-home", "cal-launch"]
        )
    }

    // MARK: - Storage

    @Test func theObservationSetRoundTripsThroughItsRawEncoding() {
        let ids: Set<String> = ["cal-b", "cal-a"]
        let raw = CadenceCalendarLinkObservations.rawObservedCalendarIDs(from: ids)

        #expect(raw == "cal-a\ncal-b")
        #expect(CadenceCalendarLinkObservations.observedCalendarIDs(from: raw) == ids)
        #expect(CadenceCalendarLinkObservations.observedCalendarIDs(from: "").isEmpty)
        #expect(CadenceCalendarLinkObservations.observedCalendarIDs(from: "\n\ncal-a\n") == ["cal-a"])
    }

    /// A pick comes from a menu of live calendars, so making one is itself an observation. Without
    /// this, a calendar linked from the list editor by someone who never opens the calendar settings
    /// screen would be a link this device could never report as broken.
    @Test func recordingAPickAddsTheIdentifierAndIgnoresTheUnlinkSentinel() throws {
        let suiteName = "com.haoranwei.Cadence.tests.linkObservations.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CadenceCalendarLinkObservations.recordPick("", replacing: "cal-work", defaults: defaults)
        #expect(defaults.string(forKey: CadenceCalendarLinkObservations.observedCalendarIDsKey) == nil)

        CadenceCalendarLinkObservations.recordPick("cal-work", replacing: "", defaults: defaults)
        CadenceCalendarLinkObservations.recordPick("cal-home", replacing: "cal-work", defaults: defaults)
        CadenceCalendarLinkObservations.recordPick("cal-work", replacing: "cal-home", defaults: defaults)

        let raw = defaults.string(forKey: CadenceCalendarLinkObservations.observedCalendarIDsKey) ?? ""
        #expect(CadenceCalendarLinkObservations.observedCalendarIDs(from: raw) == ["cal-home", "cal-work"])
    }

    /// **The hole in the first cut of this fix, found before it shipped and pinned here.**
    ///
    /// `EditAreaSheet` seeds its picker from the *stored* `linkedCalendarID`, so every save passes
    /// an identifier back — including a save that only renamed the list. If recording were
    /// unconditional, a rename would enter another device's identifier into this device's evidence,
    /// and the very next render would report that device's perfectly good link as broken. That is
    /// the false alarm the gate exists to remove, re-created by the thing meant to feed it.
    ///
    /// Only a **changed** selection is an observation, because only a changed selection came off a
    /// menu of live calendars.
    @Test func aSaveThatDidNotChangeTheCalendarRecordsNothing() throws {
        let suiteName = "com.haoranwei.Cadence.tests.linkObservations.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // The list editor, opened on a list another device linked, saved after a rename.
        CadenceCalendarLinkObservations.recordPick(
            "cal-from-another-device",
            replacing: "cal-from-another-device",
            defaults: defaults
        )
        #expect(defaults.string(forKey: CadenceCalendarLinkObservations.observedCalendarIDsKey) == nil)

        // And the whole point: with no observation, that link is not reported as broken here.
        let home = area("Home", linkedTo: "cal-from-another-device")
        #expect(
            CadenceCalendarLinkHealth.missingLinks(
                areas: [home],
                projects: [],
                liveCalendarIDs: ["cal-this-device"],
                observedCalendarIDs: CadenceCalendarLinkObservations.observedCalendarIDs(
                    from: defaults.string(forKey: CadenceCalendarLinkObservations.observedCalendarIDsKey) ?? ""
                ),
                isCalendarAccessAuthorized: true
            ).isEmpty
        )
    }

    /// The key is a preference, so renaming it silently drops every observation the installed build
    /// has made — every existing link then reads as unvouched-for until the settings screen is
    /// opened again. Pinned beside `CalendarVisibilityPreferences`' key, which it deliberately
    /// mirrors in shape.
    @Test func theObservationPreferenceKeyIsStableAndDistinct() {
        #expect(CadenceCalendarLinkObservations.observedCalendarIDsKey == "calendar.observedLinkedCalendarIDs.v1")
        #expect(CadenceCalendarLinkObservations.observedCalendarIDsKey != CalendarVisibilityPreferences.hiddenCalendarIDsKey)
    }

    // MARK: - The surfaces maintain it

    /// The gate is only as good as the set behind it, and the set is maintained in the views, which
    /// the test target does not compile for iOS. Both surfaces must refresh it and must record a
    /// pick made in the list editor, or the gate silences reports it should be making.
    @Test func bothCalendarSettingsSurfacesMaintainTheObservationSet() throws {
        for path in [
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")
            let code = CadenceSourceScan.strippingComments(raw)

            #expect(
                code.contains("@AppStorage(CadenceCalendarLinkObservations.observedCalendarIDsKey)"),
                "\(path) does not hold the device-local observation set"
            )
            #expect(
                code.contains("CadenceCalendarLinkObservations.observing("),
                "\(path) never refreshes what this device has seen"
            )
            #expect(
                code.contains("observedCalendarIDs: CadenceCalendarLinkObservations.observedCalendarIDs(from: observedCalendarIDsRaw)"),
                "\(path) does not pass its observation set to the detector"
            )
            // Refreshed on appear *and* when the store changes: a calendar list that arrives after
            // the screen is already up is the ordinary case on a cold launch. And after every link
            // write, because a calendar linked here is by definition one this device can see.
            //
            // **Exact, not `>=`.** This assertion was written `>= 3` against four real occurrences
            // — the declaration plus three call sites — so deleting the post-write refresh left
            // three and the guard passed. A mutation that dropped it survived, which is how the
            // hole was found; `== 4` is what makes each of the three call sites load-bearing.
            #expect(code.contains("refreshCalendarObservations()"), "\(path) has no refresh")
            #expect(
                CadenceSourceScan.matchCount("refreshCalendarObservations\\(\\)", in: code) == 4,
                "\(path) does not declare the refresh and call it on appear, on store change, and after a link write"
            )
            for site in [".onAppear", ".onChange(of: calendarManager.storeVersion)"] {
                #expect(code.contains(site), "\(path) lost the \(site) hook the refresh hangs off")
            }
            // The third call site by name rather than by count: it is the one a mutation deleted
            // and got away with, and it is the one that matters most — the link the user just made
            // is the link this device most needs to be able to vouch for.
            let saver = try #require(code.range(of: "private func saveCalendarLinks()"))
            let saverBody = code[saver.upperBound...].prefix(400)
            #expect(
                saverBody.contains("refreshCalendarObservations()"),
                "\(path) commits a link write without recording that this device saw the calendar"
            )
        }

        // The list editor links calendars without going near the settings screen.
        let editor = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/EditListSheet.swift")
        )
        #expect(
            CadenceSourceScan.matchCount(
                "CadenceCalendarLinkObservations\\.recordPick\\([^\n]*replacing:",
                in: editor
            ) == 2,
            "the list editor does not record both an area's and a project's calendar pick, against the stored value"
        )
        // Before the assignment, or `replacing:` is handed the value it is supposed to differ from
        // and the guard is dead in both sheets at once.
        for stored in ["area.linkedCalendarID", "project.linkedCalendarID"] {
            let recordIndex = editor.range(of: "recordPick(selectedCalendarID, replacing: \(stored))")
            let assignIndex = editor.range(of: "\(stored) = selectedCalendarID")
            #expect(recordIndex != nil && assignIndex != nil)
            if let recordIndex, let assignIndex {
                #expect(recordIndex.lowerBound < assignIndex.lowerBound, "\(stored) is written before it is read")
            }
        }
    }

    /// A scan that reads nothing satisfies every assertion above, and the needle self-check keeps
    /// the pattern honest in both directions.
    @Test func theCalendarLinkObservationScanReachesTheFilesItClaimsTo() throws {
        for path in [
            "Cadence/Shared/CadenceCalendarLinkObservations.swift",
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift",
            "Cadence/macOS/Sheets/EditListSheet.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path) lost no comment text; the stripper did not run")
            #expect(stripped.count == raw.count)
        }

        #expect(CadenceSourceScan.matchCount("refreshCalendarObservations\\(\\)", in: "  refreshCalendarObservations()") == 1)
        #expect(CadenceSourceScan.matchCount("refreshCalendarObservations\\(\\)", in: "func refreshCalendarObservations(now: Bool)") == 0)

        // T-624 is stated where a future edit to the detector will meet it, not merely true.
        let health = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarLinkHealth.swift")
        #expect(health.contains("T-624"), "the detector does not say why it needs prior evidence")
    }
}
