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

    /// **T-691.** An unnamed active list's broken-link row draws a placeholder, not a blank line —
    /// the same class of defect T-577 fixed for Settings → Lists and T-557's `dormantLinks` already
    /// avoids by reading `CadenceTitleNormalization.display(_:fallback:)`. `missingLinks` passed
    /// `area.name`/`project.name` straight through with no fallback at all. The evidence gate
    /// (T-624) must be satisfied to reach the row: `cal-gone` has to be both previously observed
    /// and no longer live.
    @Test func anUnnamedActiveListsBrokenLinkRowStillHasSomethingToPutOnIt() {
        let unnamedArea = area("   ", linkedTo: "cal-gone")
        let unnamedProject = project("", linkedTo: "cal-also-gone")

        let links = CadenceCalendarLinkHealth.missingLinks(
            areas: [unnamedArea],
            projects: [unnamedProject],
            liveCalendarIDs: [],
            observedCalendarIDs: ["cal-gone", "cal-also-gone"],
            isCalendarAccessAuthorized: true
        )

        #expect(links.count == 2)
        #expect(links.map(\.name) == [
            CadenceTitleNormalization.defaultAreaName,
            CadenceTitleNormalization.defaultProjectName,
        ])
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
            #expect(code.contains("CadenceCalendarLinkHealth.removeLinkLabel"))
            #expect(
                CadenceSourceScan.matchCount("\"Remove Link\"", in: code) == 0,
                "\(path) spells the disconnect itself; four rows want those two words now"
            )
            #expect(
                CadenceSourceScan.matchCount("calendar\\.title *==", in: code) == 0,
                "\(path) compares a calendar title, which is the auto-match T-390 refused"
            )
        }
    }

    // MARK: - T-557: a link on an inactive list is dormant, not broken

    /// **An archived list keeps its link, and now something says so.**
    ///
    /// `missingLinks` narrows to active lists by the policy in its own contract — the connect menu
    /// offers active lists only, so a broken-link row for a list the menu cannot reach would be a
    /// break with no repair beside it. That policy is right and is untouched here. What it left is
    /// a stored `linkedCalendarID` surviving in a place with no reader and no control: the only way
    /// to clear an archived list's link was to un-archive the list first.
    ///
    /// `dormantLinks` is the addition, not the reversal. The same archived list is absent from one
    /// and present in the other.
    @Test func anArchivedListsCalendarLinkIsReportedDormantAndNeverMissing() {
        let shelved = area("Home", linkedTo: "cal-home", status: .archived)

        // Full evidence that this link *would* be reported broken if it were active: the identifier
        // is one this device has seen and no live calendar carries it any more.
        let missing = CadenceCalendarLinkHealth.missingLinks(
            areas: [shelved],
            projects: [],
            liveCalendarIDs: ["cal-work"],
            observedCalendarIDs: ["cal-home", "cal-work"],
            isCalendarAccessAuthorized: true
        )
        #expect(missing.isEmpty, "the active-only policy was widened")

        let dormant = CadenceCalendarLinkHealth.dormantLinks(areas: [shelved], projects: [])
        #expect(dormant.count == 1)
        #expect(dormant.first?.name == "Home")
        #expect(dormant.first?.kind == .area)
        #expect(dormant.first?.calendarID == "cal-home")
        #expect(dormant.first?.statusLabel == "Archived")
    }

    /// **The two cards can never describe the same list.**
    ///
    /// One filters `isActive`, the other its negation, so the sets are disjoint by construction —
    /// which is what stops the new card from reading as a second opinion on the first.
    @Test func aDormantLinkAndAMissingLinkAreNeverTheSameList() {
        let live = area("Work", linkedTo: "cal-gone")
        let shelved = area("Home", linkedTo: "cal-gone", status: .archived)
        let finished = project("Launch", linkedTo: "cal-gone", status: .done)

        let missing = CadenceCalendarLinkHealth.missingLinks(
            areas: [live, shelved],
            projects: [finished],
            liveCalendarIDs: [],
            observedCalendarIDs: ["cal-gone"],
            isCalendarAccessAuthorized: true
        )
        let dormant = CadenceCalendarLinkHealth.dormantLinks(areas: [live, shelved], projects: [finished])

        #expect(missing.map(\.id) == [live.id])
        #expect(dormant.map(\.id) == [shelved.id, finished.id])
        #expect(Set(missing.map(\.id)).isDisjoint(with: Set(dormant.map(\.id))))
    }

    /// **The dormant card asks EventKit nothing, which is what keeps it clear of T-624.**
    ///
    /// T-624's rule is that a device may call a link dead only for an identifier it has itself seen
    /// alive. A new surface for archived links could undo that by judging liveness on a device with
    /// no evidence. This one cannot: whether an inactive list holds a link is a fact about this
    /// app's own store, so the detector takes no live set, no observed set and no authorization
    /// state, and the four combinations of those inputs leave both answers unmoved.
    @Test func aDormantLinkIsReportedIdenticallyWhateverThisDeviceHasSeen() {
        let shelved = area("Home", linkedTo: "cal-home", status: .archived)
        let dormant = CadenceCalendarLinkHealth.dormantLinks(areas: [shelved], projects: [])
        #expect(dormant.count == 1)

        // Every combination of "is it live here" × "has this device seen it", plus the unauthorized
        // case. Four evidence states and one blind one; none may produce a broken-link row for an
        // archived list, and none changes what the dormant card holds.
        let evidence: [(live: Set<String>, observed: Set<String>, authorized: Bool)] = [
            (["cal-home"], ["cal-home"], true),
            (["cal-home"], [], true),
            ([], ["cal-home"], true),
            ([], [], true),
            ([], ["cal-home"], false),
        ]
        #expect(evidence.count == 5)
        for state in evidence {
            let missing = CadenceCalendarLinkHealth.missingLinks(
                areas: [shelved],
                projects: [],
                liveCalendarIDs: state.live,
                observedCalendarIDs: state.observed,
                isCalendarAccessAuthorized: state.authorized
            )
            #expect(missing.isEmpty, "an archived link was reported broken with evidence \(state)")
        }
        #expect(CadenceCalendarLinkHealth.dormantLinks(areas: [shelved], projects: []) == dormant)
    }

    /// An inactive list with no link at all is the common case, and `""` is in no set — the same
    /// emptiness guard `missingLinks` needs, for the same reason.
    @Test func anInactiveListWithNoCalendarLinkIsNotDormant() {
        let shelved = area("Home", linkedTo: "", status: .archived)
        let finished = project("Launch", linkedTo: "", status: .cancelled)

        #expect(CadenceCalendarLinkHealth.dormantLinks(areas: [shelved], projects: [finished]).isEmpty)
    }

    /// **The row says which kind of inactive, because there are four of them.**
    ///
    /// `AreaStatus` has three cases and `ProjectStatus` five, and the settings surface that already
    /// collapses them says `isDone ? "Completed" : "Archived"` — which labels a cancelled project
    /// "Archived". The status word is read from `CadenceListSearchLifecycle`, where this app
    /// already spells all five, so a paused project cannot be mislabelled here.
    @Test func aDormantLinkCarriesItsListsOwnStatusWord() {
        let done = area("Home", linkedTo: "cal-a", status: .done)
        let archivedProject = project("Launch", linkedTo: "cal-b", status: .archived)
        let paused = project("Rewrite", linkedTo: "cal-c", status: .paused)
        let cancelled = project("Scrapped", linkedTo: "cal-d", status: .cancelled)

        let links = CadenceCalendarLinkHealth.dormantLinks(
            areas: [done],
            projects: [archivedProject, paused, cancelled]
        )
        #expect(links.count == 4)
        #expect(links.map(\.statusLabel) == ["Completed", "Archived", "Paused", "Cancelled"])
        // Areas first, then projects, each group in the order given — the same ordering contract
        // `missingLinks` states.
        #expect(links.map(\.name) == ["Home", "Launch", "Rewrite", "Scrapped"])
    }

    /// An unnamed list draws a row with a placeholder, not a blank line (the T-577 class). Before
    /// T-691 the broken-link row still passed the raw name with no fallback at all; both rows now
    /// read `CadenceTitleNormalization.display(_:fallback:)`.
    @Test func anUnnamedInactiveListStillHasSomethingToPutOnItsDormantRow() {
        let unnamed = area("   ", linkedTo: "cal-home", status: .archived)
        let unnamedProject = project("", linkedTo: "cal-work", status: .archived)

        let links = CadenceCalendarLinkHealth.dormantLinks(areas: [unnamed], projects: [unnamedProject])
        #expect(links.count == 2)
        #expect(links.map(\.name) == [
            CadenceTitleNormalization.defaultAreaName,
            CadenceTitleNormalization.defaultProjectName,
        ])
    }

    /// **The detector's own signature is the guarantee, and this is it read back off the source.**
    ///
    /// The behavioural test above shows the answer does not move with the evidence; this shows the
    /// evidence is not even in scope, so no later edit can quietly start consulting it. A
    /// `liveCalendarIDs` in this body would be the beginning of an archived list being called
    /// broken on a device that has never seen its calendar.
    @Test func theDormantLinkDetectorNamesNoEventKitInputAtAll() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarLinkHealth.swift")
        #expect(raw.count > 1_000, "that is not the file")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code != raw, "the stripper blanked no comments in a file that has them")

        let body = try #require(
            CadenceSourceScan.functionBody(named: "dormantLinks", in: code),
            "dormantLinks(areas:projects:) is no longer declared here"
        )
        // Non-vacuity: this really is the detector's body and not an empty match. The needles are
        // things the *body* spells — `CadenceDormantCalendarLink` is in the return type, which is
        // outside it, and asserting on that is how a body assertion silently stops being one.
        #expect(body.contains("dormantLink("))
        #expect(body.contains("return areaLinks + projectLinks"))
        #expect(body.contains("!$0.isActive"))
        for input in ["liveCalendarIDs", "observedCalendarIDs", "isCalendarAccessAuthorized", "EKCalendar"] {
            #expect(
                !body.contains(input),
                "dormantLinks consults \(input); an archived link must not be judged against EventKit"
            )
        }
        // And the active-only detector beside it still consults all three.
        let missingBody = try #require(CadenceSourceScan.functionBody(named: "missingLinks", in: code))
        for input in ["liveCalendarIDs", "observedCalendarIDs", "isCalendarAccessAuthorized"] {
            #expect(missingBody.contains(input), "missingLinks stopped reading \(input)")
        }
    }

    /// **Both surfaces draw the card, neither gates it on calendar access, and neither offers a
    /// re-pick.**
    ///
    /// Source-shape, and stated as such: `Cadence/iOS/` sits inside `#if os(iOS)` and this target
    /// compiles only one of the two.
    ///
    /// The ordering assertion is the placement half. Every other card in this section asks EventKit
    /// something and waits for permission to ask it; this one asks only the app's own store, so it
    /// renders after the authorization branch closes rather than inside it. A user whose Mac has
    /// never been granted calendar access can still see and clear a link another device wrote.
    @Test func bothCalendarSettingsSurfacesDrawTheDormantLinkCardOutsideTheAccessBranch() throws {
        for (path, accessCardNeedle) in [
            ("Cadence/macOS/Views/SettingsListManagementSections.swift", "calendarAccessCard"),
            ("Cadence/iOS/iOSCalendarSettingsSection.swift", "accessCard"),
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(code != raw, "\(path) lost no comment text; the stripper did not run")

            // Read once, from the shared detector, with exactly the two arguments it takes.
            #expect(
                CadenceSourceScan.matchCount(
                    "CadenceCalendarLinkHealth\\.dormantLinks\\(areas: areas, projects: projects\\)",
                    in: code
                ) == 1,
                "\(path) does not read the shared dormant-link detector exactly once"
            )
            #expect(
                code.contains("CadenceCalendarLinkHealth.dormantLinksSectionTitle"),
                "\(path) does not read the shared section title"
            )
            #expect(
                code.contains("CadenceCalendarLinkHealth.dormantLinkSummary(for: link)"),
                "\(path) does not read the shared dormant summary"
            )

            // The one control, and only that one: the disconnect writes the empty identifier and
            // there is no `onRelink` on this row.
            #expect(
                CadenceSourceScan.matchCount("private func disconnect\\(", in: code) == 1,
                "\(path) has no single disconnect, or more than one"
            )
            let disconnect = try #require(CadenceSourceScan.functionBody(named: "disconnect", in: code))
            #expect(CadenceSourceScan.matchCount("linkedCalendarID = \"\"", in: disconnect) == 2)
            #expect(!disconnect.contains("calendarIdentifier"))

            // Placement: after the access branch, not inside it.
            let authorizationBranch = try #require(code.range(of: "if calendarManager.isAuthorized"))
            let accessCard = try #require(code.range(of: accessCardNeedle))
            let dormantCard = try #require(code.range(of: "if !dormantLinks.isEmpty"))
            #expect(authorizationBranch.lowerBound < accessCard.lowerBound)
            #expect(
                accessCard.upperBound < dormantCard.lowerBound,
                "\(path) draws the dormant card before the access branch has closed"
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
