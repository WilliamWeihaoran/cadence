import Foundation
import Testing
#if os(macOS)
import EventKit
#endif
@testable import Cadence

// Covers the pure authorization-state -> UI-state mapping behind the Settings > Reminders
// category (Cadence/macOS/Views/SettingsRemindersSection.swift). The mapping is the whole
// decision that surface makes, and it is the one place a mistake is expensive: report access
// the app does not have and the page lies, treat a working grant as missing and the user is
// locked out of a working integration. None of this touches EventKit or needs a real grant.
#if os(macOS)
@Suite
@MainActor
struct RemindersConnectionStateTests {

    // MARK: - The three states

    @Test func notDeterminedOffersAConnectAffordance() {
        let state = RemindersConnectionState.resolve(isAuthorized: false, isDenied: false)

        #expect(state == .notDetermined)
        #expect(state.isConnected == false)
        #expect(state.badgeTitle == "Not connected")
        #expect(state.accessAction == .requestAccess)
        #expect(state.accessAction?.title == "Allow Access")
    }

    /// **T-846.** The first visit to this screen used to say "Reminders access required" — a
    /// demand before anyone had been asked anything, the same defect T-694/T-777 already fixed on
    /// Calendar and Notifications by splitting a neutral pre-prompt offer ("Connect Apple
    /// Calendar" / "Connect Notifications") from the post-denial fault report. `.notDetermined`
    /// reads as the equivalent offer now, and is a different sentence from `.denied`'s — which is
    /// the state that is actually a fault the reader has to go and fix, and keeps its own wording.
    @Test func notDeterminedTitleIsAnOfferRatherThanADemand() {
        let state = RemindersConnectionState.resolve(isAuthorized: false, isDenied: false)

        #expect(state.accessTitle == "Connect Apple Reminders")
        #expect(!state.accessTitle.localizedCaseInsensitiveContains("required"))
        #expect(state.accessTitle != RemindersConnectionState.denied.accessTitle)
        #expect(RemindersConnectionState.denied.accessTitle == "Reminders access denied")
    }

    @Test func authorizedReadsAsConnectedAndAsksForNothing() {
        let state = RemindersConnectionState.resolve(isAuthorized: true, isDenied: false)

        #expect(state == .connected)
        #expect(state.isConnected)
        #expect(state.badgeTitle == "Connected")
        // No access button at all when connected — the card offers a refresh instead.
        #expect(state.accessAction == nil)
    }

    @Test func deniedPointsAtSystemSettingsAndNeverAtADeadRequestButton() {
        let state = RemindersConnectionState.resolve(isAuthorized: false, isDenied: true)

        #expect(state == .denied)
        #expect(state.isConnected == false)
        #expect(state.badgeTitle == "Access denied")
        // macOS will not re-prompt once denied, so a request button here would do nothing.
        #expect(state.accessAction == .openSystemSettings)
        #expect(state.accessAction != .requestAccess)
        #expect(state.accessMessage.contains("System Settings"))
    }

    /// `isAuthorized` is a stored snapshot on `RemindersManager`; `isDenied` is evaluated live.
    /// Revoking access in System Settings mid-session produces exactly this contradiction, and
    /// the live signal has to win or the page keeps claiming a connection that is gone.
    @Test func liveDenialOverridesAStaleAuthorizedSnapshot() {
        #expect(RemindersConnectionState.resolve(isAuthorized: true, isDenied: true) == .denied)
    }

    // MARK: - T-256: a restriction is not a denial the user can undo

    /// **The whole ticket.** A restricted device (Screen Time, an MDM profile) offered the exact
    /// same "Reminders access denied" / "Open Reminders Settings" pair a plain denial gets, and
    /// that pane will not let a restricted user grant anything — an affordance offered in a state
    /// where it cannot work, the same class of bug as the pre-T-21 dead **Allow Access** button.
    @Test func restrictedOffersNoActionAndNamesTheRestrictionRatherThanADenial() {
        let state = RemindersConnectionState.resolve(isAuthorized: false, isDenied: false, isRestricted: true)

        #expect(state == .restricted)
        #expect(state != .denied)
        #expect(state.isConnected == false)
        #expect(state.badgeTitle == "Restricted")
        #expect(state.badgeTitle != "Access denied")
        // No settings trip: there is no pane that lifts a restriction for this user.
        #expect(state.accessAction == nil)
        #expect(state.accessTitle != RemindersConnectionState.denied.accessTitle)
        #expect(state.accessMessage != RemindersConnectionState.denied.accessMessage)
        // The copy says the restriction is not Cadence's (or the user's) to lift, and does not
        // send anyone to a settings pane the way the denied copy does.
        #expect(state.accessMessage.localizedCaseInsensitiveContains("restrict"))
        #expect(state.accessMessage.localizedCaseInsensitiveContains("Settings") == false)
    }

    /// `isRestricted` wins over `isDenied` when both are `true` — which is exactly what
    /// `RemindersManager.isDenied` hands the resolver, since it folds `.restricted` into its own
    /// answer too (see its doc comment). If restricted did not win here, its presentation would
    /// be unreachable through the manager's real flags.
    @Test func restrictedOutranksADenialThatAlsoReadsTrueForTheSameStatus() {
        #expect(RemindersConnectionState.resolve(isAuthorized: false, isDenied: true, isRestricted: true) == .restricted)
    }

    /// `isRestricted` defaults to `false`, so every call written before T-256 — including every
    /// test above this section — keeps resolving exactly as it did.
    @Test func omittingIsRestrictedPreservesThePreT256Behavior() {
        #expect(RemindersConnectionState.resolve(isAuthorized: false, isDenied: false) == .notDetermined)
        #expect(RemindersConnectionState.resolve(isAuthorized: false, isDenied: true) == .denied)
        #expect(RemindersConnectionState.resolve(isAuthorized: true, isDenied: false) == .connected)
    }

    // MARK: - EventKit status mapping

    /// **`.restricted` cannot be produced with `simctl privacy` or any other host-side toggle** —
    /// there is no "restrict this app" lever to flip, only real MDM/Screen Time configuration this
    /// suite has no business touching. This pure mapping is therefore the only place the state can
    /// be pinned; it is not simulator-verified, and no report of this ticket should claim otherwise.
    @Test func fullAccessIsTheOnlyStatusThatCountsAsConnected() {
        #expect(RemindersConnectionState.resolve(status: .fullAccess) == .connected)
        #expect(RemindersConnectionState.resolve(status: .denied) == .denied)
        // **T-256.** This used to fold into `.denied`; `.restricted` is its own state now,
        // because the two need different second halves — see the tests above.
        #expect(RemindersConnectionState.resolve(status: .restricted) == .restricted)
        #expect(RemindersConnectionState.resolve(status: .notDetermined) == .notDetermined)
    }

    /// `RemindersManager.refreshAuthorizationState()` used to test `status == .fullAccess ||
    /// status == .authorized`, which built with a deprecation warning. Dropping the second
    /// disjunct is safe only because the deprecated `.authorized` is not a separate state: it
    /// is declared as `EKAuthorizationStatusAuthorized = EKAuthorizationStatusFullAccess`, raw
    /// value 3. This pins that equivalence without naming the deprecated symbol, so if a future
    /// SDK ever split them apart the check would fail here rather than silently locking the
    /// user out of (or falsely claiming) Reminders access.
    @Test func theDeprecatedAuthorizedRawValueStillResolvesToFullAccess() throws {
        let legacyAuthorized = try #require(EKAuthorizationStatus(rawValue: 3))

        #expect(legacyAuthorized == .fullAccess)
        #expect(RemindersConnectionState.resolve(status: legacyAuthorized) == .connected)
    }

    /// Write-only access is documented as an events-only status and is never returned for
    /// reminders, but if it ever were, read access is exactly what Cadence needs, so it must
    /// not read as connected. It also has to agree with `resolve(isAuthorized:isDenied:)`,
    /// which is what the view actually calls: write-only leaves `isAuthorized` false and
    /// `isDenied` false, i.e. `.notDetermined`.
    @Test func writeOnlyIsNotConnectedAndAgreesWithTheFlagBasedResolver() throws {
        let writeOnly = try #require(EKAuthorizationStatus(rawValue: 4))

        #expect(writeOnly == .writeOnly)
        #expect(RemindersConnectionState.resolve(status: writeOnly) == .notDetermined)
        #expect(RemindersConnectionState.resolve(isAuthorized: false, isDenied: false) == .notDetermined)
    }

    // MARK: - The in-app "Don't Allow", which the cached status cannot see

    /// **T-21, measured on the iOS 26 simulator.** `EKEventStore.authorizationStatus` is cached per
    /// process in *both* directions. The grant direction was already known and worked around; the
    /// denial direction was not, and its consequence is worse: after the user taps **Don't Allow**
    /// on the in-app prompt the status still reads `.notDetermined`, so Settings > Reminders and
    /// the Inbox strip both stayed on "Reminders access required" with a live **Allow Access**
    /// button — which iOS will never answer again, because the app has had its one prompt.
    ///
    /// Reproduced with the simulator's own TCC row already reading denied (`auth_value 0`) while
    /// the running app showed the not-determined card, and the *same build relaunched* against the
    /// *same* TCC row rendering "Reminders access denied" correctly. The process was the only
    /// variable, which is what makes it the cache and not a missing `.onAppear`.
    @Test func aRefusedInAppPromptIsDeniedEvenWhileTheCachedStatusStillSaysNotDetermined() {
        #expect(RemindersConnectionState.isDenied(status: .notDetermined, deniedInThisSession: true))

        // And it has to reach the state the views actually render, not just the flag.
        let state = RemindersConnectionState.resolve(
            isAuthorized: false,
            isDenied: RemindersConnectionState.isDenied(status: .notDetermined, deniedInThisSession: true)
        )
        #expect(state == .denied)
        #expect(state.accessAction == .openSystemSettings)
        #expect(state.accessAction != .requestAccess, "the dead Allow Access button is back")
    }

    /// The record only ever *adds* a denial the cached status has not caught up with. Without a
    /// refusal in this launch the answer is exactly the old one, so a fresh launch against a
    /// `.notDetermined` store still offers to ask.
    @Test func withoutARefusalTheAnswerIsStillEventKitsOwn() {
        #expect(RemindersConnectionState.isDenied(status: .notDetermined, deniedInThisSession: false) == false)
        #expect(RemindersConnectionState.isDenied(status: .denied, deniedInThisSession: false))
        #expect(RemindersConnectionState.isDenied(status: .restricted, deniedInThisSession: false))
        #expect(RemindersConnectionState.isDenied(status: .fullAccess, deniedInThisSession: false) == false)
    }

    /// A refusal must not outlive the grant that overturns it — otherwise a user who denies, then
    /// allows from System Settings, is locked out of a working integration for the rest of the
    /// launch. `RemindersManager` clears the record whenever a real grant lands; this pins the
    /// pure half, and `theManagerDerivesDenialThroughTheSharedRuleRatherThanRespellingIt` pins
    /// that the manager is the thing asking.
    @Test func agrantOverturnsARefusalRatherThanBeingOutlivedByIt() {
        // The clearing is the manager's job, so the pure function is asked the question it will
        // actually be asked after a grant: status full, record cleared.
        #expect(RemindersConnectionState.isDenied(status: .fullAccess, deniedInThisSession: false) == false)
        #expect(
            RemindersConnectionState.resolve(
                isAuthorized: true,
                isDenied: RemindersConnectionState.isDenied(status: .fullAccess, deniedInThisSession: false)
            ) == .connected
        )
    }

    /// **The call-site pin.** The function above is pure and would stay green with nobody calling
    /// it — the exact shape `CadenceInboxRemindersSurfaceTests` exists to guard against. The
    /// manager must ask it, must record the refusal, and must not keep its own copy of the
    /// `.denied || .restricted` rule beside it.
    @Test func theManagerDerivesDenialThroughTheSharedRuleRatherThanRespellingIt() throws {
        let source = try remindersManagerSource()

        #expect(
            source.contains("RemindersConnectionState.isDenied("),
            "RemindersManager stopped asking the shared denial rule"
        )
        #expect(
            source.contains("deniedInThisSession = true"),
            "RemindersManager stopped recording a refused in-app prompt"
        )
        #expect(
            source.range(of: "status == \\.denied\\s*\\|\\|\\s*status == \\.restricted", options: .regularExpression) == nil,
            "RemindersManager has its own copy of the denial rule again"
        )
        // The record has to be stored, not computed: `@Observable` only re-renders on stored
        // property mutations, and the whole point is that the surface updates without a relaunch.
        #expect(
            source.contains("private(set) var deniedInThisSession = false"),
            "deniedInThisSession is no longer a stored, observable property"
        )
    }

    /// Stops the scan above going vacuous the way a `/tmp` against `/private/tmp` mismatch once did
    /// — and, second half, proves the stripper actually stripped rather than silently returning the
    /// file unchanged. A stripper that no-ops puts the doc comment's prose mention of
    /// `RemindersConnectionState.isDenied(` back in front of the scan and makes it unfailable again.
    @Test func theManagerSourceScanActuallyReadsTheFileAndStrippedItsComments() throws {
        let source = try remindersManagerSource()
        #expect(source.contains("final class RemindersManager"))
        #expect(source.contains("func requestAccess"))
        #expect(source.count > 2000, "the manager source read \(source.count) characters")

        let raw = try remindersManagerRawSource()
        #expect(raw.contains("/// Set when a request that started from"), "the manager's doc comments moved; re-pick the needle")
        #expect(source.contains("/// Set when a request that started from") == false, "strippingComments left a doc comment behind")
        // The needle the scan above depends on: it must survive stripping exactly once, as code.
        #expect(occurrences(of: "RemindersConnectionState.isDenied(", in: raw) == 2, "expected the prose mention and the call")
        #expect(occurrences(of: "RemindersConnectionState.isDenied(", in: source) == 1, "expected only the call to survive stripping")
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var index = haystack.startIndex
        while let range = haystack.range(of: needle, range: index..<haystack.endIndex) {
            count += 1
            index = range.upperBound
        }
        return count
    }

    /// **Comments stripped, and that is the whole point of this helper existing.** The manager's
    /// doc comment on `deniedInThisSession` names
    /// `RemindersConnectionState.isDenied(status:deniedInThisSession:)` in prose, so a raw
    /// `contains("RemindersConnectionState.isDenied(")` over the file stays green with the actual
    /// call deleted — the "cannot fail at all" failure mode written up in
    /// `Cadence/Shared/AGENTS.md`, "Source-Scanning Tests: The Two Ways They Go Wrong". Mutation
    /// tested: removing the call from `isDenied` while leaving the comment fails this scan only
    /// once the stripper is in front of it.
    private func remindersManagerSource() throws -> String {
        try strippingComments(remindersManagerRawSource())
    }

    private func remindersManagerRawSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent("Cadence/Services/CadenceRemindersManager.swift"),
            encoding: .utf8
        )
    }

    // MARK: - Synced-reminder summary

    @Test func listRowsGroupLoadedRemindersByListBusiestFirst() {
        let rows = RemindersSyncSummary.listRows(from: [
            makeReminder(id: "1", listTitle: "Groceries"),
            makeReminder(id: "2", listTitle: "Work"),
            makeReminder(id: "3", listTitle: "Work"),
            makeReminder(id: "4", listTitle: "Work"),
            makeReminder(id: "5", listTitle: "Groceries")
        ])

        #expect(rows == [
            RemindersListSummaryRow(title: "Work", count: 3),
            RemindersListSummaryRow(title: "Groceries", count: 2)
        ])
    }

    @Test func listRowsBreakCountTiesAlphabeticallyAndHandleAnEmptyStore() {
        let rows = RemindersSyncSummary.listRows(from: [
            makeReminder(id: "1", listTitle: "zeta"),
            makeReminder(id: "2", listTitle: "Alpha")
        ])

        #expect(rows.map(\.title) == ["Alpha", "zeta"])
        #expect(RemindersSyncSummary.listRows(from: []).isEmpty)
    }

    private func makeReminder(id: String, listTitle: String) -> AppleReminderItem {
        AppleReminderItem(
            id: id,
            title: "Reminder \(id)",
            notes: "",
            listTitle: listTitle,
            dueDate: nil,
            priority: 0,
            allowsCompletion: true
        )
    }
}

/// The repo's standard comment stripper, kept `private` per test file exactly as
/// `CadenceNoteReferencePanelSurfaceTests` and five others keep theirs. Replaces each comment with
/// the same number of spaces so offsets and line numbers in a failure message still line up.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
#endif
