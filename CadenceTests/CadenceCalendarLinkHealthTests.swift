import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-400 — a dead list-to-calendar link is visible.**
///
/// `Area.linkedCalendarID` and `Project.linkedCalendarID` hold an `EKCalendar.calendarIdentifier`
/// and nothing else. T-390 decided against storing a title and source beside it — that is a stored
/// property on two `@Model` types and this project has no `SchemaMigrationPlan` — and recorded that
/// a calendar Apple Calendar deleted and recreated leaves the link "visibly dead".
///
/// It was dead, but it was not visible. Both calendar surfaces in Settings iterate *live*
/// `EKCalendar`s and hang the connected lists off them, so a list whose calendar no longer exists
/// renders in no row at all; the list just stops mirroring. Detection needs none of the metadata
/// T-390 declined to store, which is what these tests pin.
struct CadenceCalendarLinkHealthTests {

    // MARK: - Detection

    private func area(_ name: String, linkedTo calendarID: String, status: AreaStatus = .active) -> Area {
        let area = Area(name: name)
        area.linkedCalendarID = calendarID
        area.status = status
        return area
    }

    private func project(_ name: String, linkedTo calendarID: String, status: ProjectStatus = .active) -> Project {
        let project = Project(name: name)
        project.linkedCalendarID = calendarID
        project.status = status
        return project
    }

    @Test func aLinkNoLiveCalendarCarriesIsReportedMissing() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-gone")],
            projects: [],
            liveCalendarIDs: ["cal-work", "cal-personal"],
            observedCalendarIDs: ["cal-gone", "cal-work", "cal-personal"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.count == 1)
        #expect(links.first?.name == "Home")
        #expect(links.first?.kind == .area)
        #expect(links.first?.calendarID == "cal-gone")
    }

    @Test func aLinkWhoseCalendarIsStillLiveIsNotReported() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-work")],
            projects: [project("Launch", linkedTo: "cal-work")],
            liveCalendarIDs: ["cal-work"],
            observedCalendarIDs: ["cal-work"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.isEmpty)
    }

    /// An unlinked list is the overwhelmingly common case. `""` is never in the live set, so a rule
    /// written as "not contained" without the emptiness guard reports every list in the app.
    @Test func aListWithNoCalendarLinkIsNeverReported() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "")],
            projects: [project("Launch", linkedTo: "")],
            liveCalendarIDs: ["cal-work"],
            observedCalendarIDs: ["cal-work"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.isEmpty)
    }

    /// The loudest possible false positive. Before authorization `allCalendars` is empty, so the
    /// plain rule reports *every* linked list at once and invites the user to overwrite links that
    /// were never broken.
    @Test func withoutCalendarAccessNothingIsReportedMissing() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-gone")],
            projects: [project("Launch", linkedTo: "cal-also-gone")],
            liveCalendarIDs: [],
            observedCalendarIDs: ["cal-gone", "cal-also-gone"],
            isCalendarAccessAuthorized: false
        )

        #expect(links.isEmpty)

        // Authorized with genuinely zero calendars is a different fact and must still report, or
        // the guard has been written as "empty set means say nothing".
        let authorized = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-gone")],
            projects: [],
            liveCalendarIDs: [],
            observedCalendarIDs: ["cal-gone"],
            isCalendarAccessAuthorized: true
        )
        #expect(authorized.count == 1)
    }

    /// The T-390 half restated as behaviour: a calendar recreated under a new identifier is a new
    /// calendar, however it is named. The report survives its arrival, and the surface offers the
    /// user a pick rather than making one.
    @Test func aCalendarRecreatedUnderANewIdentifierLeavesTheLinkReportedDead() {
        let home = area("Home", linkedTo: "cal-before")

        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [home],
            projects: [],
            liveCalendarIDs: ["cal-after"],
            observedCalendarIDs: ["cal-before", "cal-after"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.count == 1)
        #expect(links.first?.calendarID == "cal-before")
        // Detection reports; it never repairs. The stored link is untouched by asking.
        #expect(home.linkedCalendarID == "cal-before")
    }

    /// Archived and finished lists are out, matching every other calendar-link affordance in
    /// Settings — the connect menu is built from `activeAreas`/`activeProjects`, so a row here for
    /// a list that menu cannot reach would be a break with no repair beside it.
    @Test func onlyActiveListsAreReported() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Archived Home", linkedTo: "cal-gone", status: .archived)],
            projects: [project("Finished Launch", linkedTo: "cal-gone", status: .done)],
            liveCalendarIDs: ["cal-work"],
            observedCalendarIDs: ["cal-gone", "cal-work"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.isEmpty)
    }

    @Test func areasAreReportedBeforeProjects() {
        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [area("Home", linkedTo: "cal-gone")],
            projects: [project("Launch", linkedTo: "cal-gone")],
            liveCalendarIDs: [],
            observedCalendarIDs: ["cal-gone"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.map(\.kind) == [.area, .project])
        #expect(links.map(\.name) == ["Home", "Launch"])
    }

    /// The row carries what the repair needs: the list's own id, so the write-back does not have to
    /// re-derive which list it came from by name.
    @Test func theReportedLinkCarriesTheListsIdentity() {
        let home = area("Home", linkedTo: "cal-gone")
        home.icon = "house.fill"
        home.colorHex = "#4a9eff"

        let link = CadenceCalendarLinkHealth.missingLinks(
            areas: [home],
            projects: [],
            liveCalendarIDs: [],
            observedCalendarIDs: ["cal-gone"],
            isCalendarAccessAuthorized: true
        ).first

        #expect(link?.id == home.id)
        #expect(link?.icon == "house.fill")
        #expect(link?.colorHex == "#4a9eff")
    }

    // MARK: - No auto-matching

    /// The reason a recreated calendar cannot be adopted is structural, not a missing branch: the
    /// detector is never handed a title to match on. Its whole calendar input is a `Set<String>` of
    /// identifiers, so "same name, new id" is not a case it could handle if it wanted to.
    @Test func theDetectorIsNeverGivenACalendarTitleToMatchOn() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarLinkHealth.swift")
        let code = CadenceSourceScan.strippingComments(raw)

        #expect(code.contains("liveCalendarIDs: Set<String>"))
        #expect(
            CadenceSourceScan.matchCount("\\.title", in: code) == 0,
            "the detector reads a calendar title; that is the auto-match T-390 refused"
        )
        #expect(
            CadenceSourceScan.matchCount("EKCalendar", in: code) == 0,
            "the detector took an EventKit type, which is how a title gets in"
        )
        #expect(raw.contains("T-400"), "the detector does not state which decision it implements")
    }

    // MARK: - Both surfaces show it

    /// `Cadence/iOS/` is not compiled by this test target, so the iOS half is a scan. The macOS half
    /// is scanned beside it deliberately: the two claims are the same claim, and reading one from
    /// source and the other from the compiler would leave the pair unable to fail together.
    @Test func bothSettingsSurfacesRenderTheMissingLinkRow() throws {
        for path in [
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift"
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))

            #expect(code.contains("CadenceCalendarLinkHealth.missingLinks("), "\(path) never asks")
            #expect(
                code.contains("CadenceCalendarLinkHealth.missingLinkTitle"),
                "\(path) spells the row title itself instead of sharing one"
            )

            // Hidden is not missing. Both surfaces already read `calendarManager.allCalendars` into
            // `calendars`; passing the *visible* subset instead would report every switched-off
            // calendar's links dead.
            #expect(
                code.contains("liveCalendarIDs: Set(calendars.map(\\.calendarIdentifier))"),
                "\(path) does not pass the full calendar set"
            )
            #expect(code.contains("return calendarManager.allCalendars"))
            #expect(
                CadenceSourceScan.matchCount("liveCalendarIDs: [^\n]*hiddenCalendarIDs", in: code) == 0,
                "\(path) filters the live set by visibility"
            )

            // The authorization guard, which is the difference between a warning and a panic.
            #expect(
                code.contains("isCalendarAccessAuthorized: calendarManager.isAuthorized"),
                "\(path) does not pass the authorization state"
            )

            // The re-pick, and only the re-pick: the row offers the calendars that exist and an
            // unlink, and nothing preselects or reorders them by name.
            #expect(code.contains("onRelink"))
            #expect(code.contains("onUnlink"))
            #expect(code.contains("Remove Link"))
            #expect(
                CadenceSourceScan.matchCount("calendar\\.title *==", in: code) == 0,
                "\(path) compares a calendar title, which is the auto-match T-390 refused"
            )
        }
    }

    // MARK: - T-624: this device may only judge a calendar it has seen

    /// **T-624 — the evidence gate.**
    ///
    /// `linkedCalendarID` is an `EKCalendar.calendarIdentifier`, which Apple documents as local to
    /// one device, and it is stored on a **CloudKit-synced** model. So a link written on one device
    /// arrives on another as an identifier that device's EventKit has never issued. Detection read
    /// as "not in this device's live set", which cannot tell that case apart from a calendar Apple
    /// Calendar actually deleted — and the repair beside it writes straight back to the same synced
    /// field, so the second device's answer overwrites the first device's.
    ///
    /// **Whether the identifiers really do differ across this user's devices is not measured here**
    /// and cannot be without touching EventKit. This gate does not depend on it. It replaces
    /// "absent" with "was here and is gone": a device declares a link dead only for an identifier
    /// it has previously seen alive. If identifiers are shared across devices, every device
    /// observes the id and the behaviour is exactly what it was; if they are not, the device that
    /// never issued the id stays silent instead of offering a repair that would clobber a working
    /// link. Either way, **a repair on one device cannot invalidate another device's link.**
    @Test func neitherSettingsSurfaceJudgesALinkAgainstCalendarsItHasNeverSeen() throws {
        let health = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarLinkHealth.swift")
        )
        #expect(
            health.contains("observedCalendarIDs: Set<String>"),
            "the detector still judges a link from the live set alone"
        )

        for path in [
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")
            let code = CadenceSourceScan.strippingComments(raw)

            #expect(
                code.contains("observedCalendarIDs:"),
                "\(path) does not pass what this device has actually seen"
            )
            #expect(
                code.contains("CadenceCalendarLinkObservations"),
                "\(path) does not maintain the device-local observation set"
            )
        }
    }

    // MARK: - The scan itself

    /// A scan that reads nothing satisfies every `== 0` above. This proves the reader reaches real
    /// files and that the comment stripper is actually running on them.
    ///
    /// The name is suite-specific on purpose: two suites declaring the same test name make a
    /// mutation's `✔ Test name()` line unattributable.
    @Test func theCalendarLinkHealthScanReachesTheFilesItClaimsTo() throws {
        for path in [
            "Cadence/Shared/CadenceCalendarLinkHealth.swift",
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")
            #expect(raw.contains("linkedCalendarID") || raw.contains("CadenceMissingCalendarLink"))

            let stripped = CadenceSourceScan.strippingComments(raw)
            // The stripper blanks comments to spaces of equal length, so the string is never
            // shorter; `stripped.count < raw.count` is a check that can never be true.
            #expect(stripped != raw, "\(path) lost no comment text; the stripper did not run")
            #expect(stripped.count == raw.count)
        }

        // The needle self-check: the pattern used for the auto-match assertions must match the
        // thing it bans and miss the thing it must not.
        #expect(CadenceSourceScan.matchCount("calendar\\.title *==", in: "if calendar.title == other {") == 1)
        #expect(CadenceSourceScan.matchCount("calendar\\.title *==", in: "Text(calendar.title)") == 0)
    }

    // MARK: - T-598(b): one spelling of "read-only"

    /// **Two settings screens drew their own badge for a fact the app already had a word for.**
    ///
    /// `CadenceCalendarLinkExclusion.readOnly.qualifier` is `"Read-only"`, and it is what the
    /// picker one tap away puts after an excluded calendar's name;
    /// `CadenceCalendarEventEditingSupport.readOnlyNotice` says "read-only calendar" in prose. Both
    /// settings rows typed `Text("Read Only")` — a third spelling of one fact, differing from the
    /// other two by a hyphen and a capital.
    ///
    /// **This guard exists because the sweep cannot cover it.**
    /// `CadenceSharedConstantReuseSweepTests` harvests shared string constants of **twelve
    /// characters or more**; `"Read-only"` is nine, and it is a `switch` in a computed property
    /// rather than a `static let`, so it is doubly outside that harvest. A fourth surface typing
    /// the words out again is caught here or nowhere.
    @Test func neitherCalendarSettingsSurfaceSpellsItsOwnReadOnlyBadge() throws {
        // The word itself, so a rename of the qualifier fails here rather than silently
        // re-pointing both call sites at something new.
        #expect(CadenceCalendarLinkExclusion.readOnly.qualifier == "Read-only")
        #expect(CadenceCalendarLinkExclusion.hidden.qualifier == "Hidden")
        // The retired spelling and the shipped one are genuinely different strings — the whole
        // defect is the difference, so the comparison is written out.
        #expect(CadenceCalendarLinkExclusion.readOnly.qualifier != "Read Only")

        for path in [
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
            "Cadence/iOS/iOSCalendarSettingsSection.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")
            let code = CadenceSourceScan.strippingComments(raw)

            // Non-vacuity: this really is the row that decides whether to draw the badge.
            #expect(
                code.contains("!calendar.allowsContentModifications"),
                "\(path) no longer holds the row this pins"
            )
            #expect(
                CadenceSourceScan.matchCount(#""Read ?[Oo]nly""#, in: code) == 0,
                "\(path) still spells its own read-only badge"
            )
            #expect(
                code.contains("Text(CadenceCalendarLinkExclusion.readOnly.qualifier)"),
                "\(path) does not read the shared qualifier"
            )
        }

        // The prose notice is the *third* spelling and it is deliberately left alone: mid-sentence
        // lowercase is the same hyphenation, not a fourth one.
        let notice = CadenceCalendarEventEditingSupport.readOnlyNotice(calendarName: "Holidays")
        #expect(notice.contains("read-only calendar"))
        #expect(!notice.contains("Read Only"))
    }
}
