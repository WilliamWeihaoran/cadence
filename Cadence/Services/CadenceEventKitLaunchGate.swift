import Foundation

/// **[[T-3031]] — whether this launch may touch EventKit at all.**
///
/// A debug build carries bundle id `com.haoranwei.Cadence`, so it inherits the owner's TCC grants
/// for Calendars and Reminders. An agent's `scripts/run-macos-app.sh` launch and every
/// `CadenceUITests` launch therefore resolved the OWNER'S REAL Apple Calendar with create, update
/// and delete rights: `CalendarManager.shared.init` read `.fullAccess`, set `isAuthorized`, and
/// registered a live `EKEventStoreChanged` observer, and from there a stray drag on a day column
/// created a real event with no confirmation at all. The launchers redirect the store, the backups
/// and the preferences suite; nothing redirected EventKit, and there is nothing to redirect it
/// *to* — an `EKEventStore` has no path. So such a launch is **disarmed** instead: the calendar
/// managers answer "not authorized", never prompt, never observe, and refuse every write.
///
/// **Which signal, and why it is three.** Each one is an existing marker that this launch is not
/// the owner's shipping app, and each is already read elsewhere as exactly that:
///
/// - `CADENCE_LOCAL_STORE_ONLY=1` — set by `run-macos-app.sh` (its `start` line) **and** by every
///   `CadenceUITests` suite's `launchEnvironment`; `PersistenceController` turns CloudKit off on it
///   and `CadenceRemoteNotificationRegistrar` refuses push registration on it. It is the one
///   variable both launchers set by hand.
/// - `CADENCE_UI_TEST_STORE_ID` (non-empty) — also set by both: by `run-macos-app.sh` and by
///   `CadenceUITestEnvironment.isolateStoreAndPreferences`. Read through
///   `CadenceUITestStoreDirectory.directoryID(in:)`, the one place that parses it, so "this launch
///   has a private store" and "this launch may not reach EventKit" cannot disagree.
/// - `CADENCE_UI_TEST_MODE=1` — `CadenceUITestSupport.isEnabled`, which `NotificationManager`
///   already treats as a test environment. `run-macos-app.sh` does NOT set it, which is why it
///   cannot be the only signal.
///
/// Any one is enough: the gate fails toward refusing, because the cost of a false positive is an
/// empty Calendar page on a throwaway launch, and the cost of a false negative is an event the
/// owner never made, or one deleted with "This And Future Events".
///
/// **What it deliberately does not include: the XCTest keys.** A `CadenceTests` host sets none of
/// the three variables, so unit tests are unchanged — `CalendarManagerScenarioTests` and the
/// fetch-rate tests depend on the manager behaving as it does in production. The residue the
/// unit-test host still carries (the process-wide grant; see `macOS/Services/AGENTS.md`, "Unit
/// tests reach a live store") is a separate exposure and is not narrowed here.
///
/// **Not covered: `RemindersManager`.** `CadenceRemindersManager.swift` is outside this change; it
/// should read the same predicate when it is next opened.
enum CadenceEventKitLaunchGate {

    /// The variables above, named once so the tests and the doc agree on the spelling.
    static let localStoreOnlyVariable = "CADENCE_LOCAL_STORE_ONLY"
    static let uiTestModeVariable = "CADENCE_UI_TEST_MODE"

    /// `true` when `environment` describes an agent or UI-test launch that must not reach EventKit.
    ///
    /// Pure over its input, so it is tested with literal dictionaries rather than by launching.
    static func isDisarmed(in environment: [String: String]) -> Bool {
        if environment[localStoreOnlyVariable] == "1" { return true }
        if environment[uiTestModeVariable] == "1" { return true }
        if CadenceUITestStoreDirectory.directoryID(in: environment) != nil { return true }
        return false
    }

    /// The answer for this process. Read once, at manager construction.
    static var isDisarmedForThisProcess: Bool {
        isDisarmed(in: ProcessInfo.processInfo.environment)
    }
}
