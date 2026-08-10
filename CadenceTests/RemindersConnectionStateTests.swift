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

    // MARK: - EventKit status mapping

    @Test func fullAccessIsTheOnlyStatusThatCountsAsConnected() {
        #expect(RemindersConnectionState.resolve(status: .fullAccess) == .connected)
        #expect(RemindersConnectionState.resolve(status: .denied) == .denied)
        #expect(RemindersConnectionState.resolve(status: .restricted) == .denied)
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
#endif
