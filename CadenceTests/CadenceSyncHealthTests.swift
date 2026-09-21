import CloudKit
import Foundation
import Testing
@testable import Cadence

/// The one "is sync actually working" answer.
///
/// The defect these pin: `PersistenceController` falls back to a store opened with
/// `cloudKitDatabase: .none` whenever the CloudKit one cannot be created, and the app then runs
/// normally and syncs nothing forever. macOS rendered that as a banner; iOS rendered nothing, and
/// iOS Settings separately showed a green `checkmark.icloud` sourced from `CKAccountStatus` alone —
/// so the surface a user would actually check actively told them sync was fine.
@MainActor
struct CadenceSyncHealthTests {
    private let recovery = CadenceStartupIssue(
        kind: .recoveryStore,
        message: "Cadence opened a recovery store because the CloudKit store could not be created."
    )
    private let inMemory = CadenceStartupIssue(
        kind: .inMemoryStore,
        message: "Recovery store creation also failed, so Cadence opened a temporary in-memory store."
    )
    private let maintenance = CadenceStartupIssue(
        kind: .maintenanceSaveFailed,
        message: "Cadence could not save startup maintenance changes: disk full."
    )

    // MARK: - The store wins over the account

    @Test func recoveryStoreOverridesAnAvailableAccount() {
        let health = CadenceSyncHealth.resolve(startupIssue: recovery, account: .available, pushRegistration: .registered)

        #expect(health.level == .notSyncing)
        #expect(health.tone != .positive)
        #expect(health.iconName != "checkmark.icloud")
        #expect(!health.detail.contains("should be able to sync"))
    }

    @Test func inMemoryStoreOverridesAnAvailableAccount() {
        let health = CadenceSyncHealth.resolve(startupIssue: inMemory, account: .available, pushRegistration: .registered)

        #expect(health.level == .notSyncing)
        #expect(health.tone == .critical)
    }

    @Test func everySyncDisablingIssueOutranksEveryAccountState() {
        let accounts: [CadenceCloudAccountState] = [
            .notChecked, .checking, .available, .noAccount, .restricted,
            .temporarilyUnavailable, .couldNotDetermine, .failed("boom"),
        ]
        for issue in [recovery, inMemory] {
            for account in accounts {
                let health = CadenceSyncHealth.resolve(startupIssue: issue, account: account, pushRegistration: .registered)
                #expect(health.level == .notSyncing, "\(issue.kind) + \(account) reported \(health.level)")
            }
        }
    }

    // MARK: - A maintenance failure is not a sync failure

    @Test func maintenanceSaveFailureLeavesSyncAlone() {
        #expect(CadenceStartupIssueKind.maintenanceSaveFailed.disablesCloudSync == false)

        let health = CadenceSyncHealth.resolve(startupIssue: maintenance, account: .available, pushRegistration: .registered)
        #expect(health.level == .syncing)
        #expect(health.tone == .positive)

        let offline = CadenceSyncHealth.resolve(startupIssue: maintenance, account: .noAccount, pushRegistration: .registered)
        #expect(offline.level == .degraded)
    }

    @Test func onlyTheStoreLevelIssuesDisableSync() {
        let disabling = CadenceStartupIssueKind.allCases.filter(\.disablesCloudSync)
        #expect(Set(disabling) == [.recoveryStore, .inMemoryStore])
        #expect(CadenceStartupIssueKind.allCases.filter(\.losesDataOnQuit) == [.inMemoryStore])
    }

    // MARK: - Account states

    @Test func healthyAccountWithNoIssueSyncs() {
        let health = CadenceSyncHealth.resolve(startupIssue: nil, account: .available, pushRegistration: .registered)

        #expect(health.level == .syncing)
        #expect(health.tone == .positive)
        #expect(health.iconName == "checkmark.icloud")
    }

    @Test func accountStatesMapToDistinctLevels() {
        let expected: [(CadenceCloudAccountState, CadenceSyncHealthLevel)] = [
            (.available, .syncing),
            (.checking, .checking),
            (.notChecked, .unknown),
            (.couldNotDetermine, .unknown),
            (.noAccount, .degraded),
            (.restricted, .degraded),
            (.temporarilyUnavailable, .degraded),
            (.failed("network down"), .degraded),
        ]
        for (account, level) in expected {
            let health = CadenceSyncHealth.resolve(startupIssue: nil, account: account, pushRegistration: .registered)
            #expect(health.level == level, "\(account) reported \(health.level)")
            #expect(!health.title.isEmpty)
            #expect(!health.detail.isEmpty)
        }
    }

    @Test func aFailedCheckSurfacesItsOwnMessage() {
        let health = CadenceSyncHealth.resolve(startupIssue: nil, account: .failed("The Internet connection is offline."), pushRegistration: .registered)
        #expect(health.detail == "The Internet connection is offline.")
    }

    // MARK: - Push registration (T-1309)

    /// The state that had no surface at all. A device whose registration is refused still opens a
    /// CloudKit store and still has a healthy account, so every input `resolve` used to take said
    /// "iCloud available" in green — while the device was subscribed to nothing and learned about
    /// the user's other devices only at launch.
    @Test func aRefusedPushRegistrationDegradesAnOtherwiseHealthyVerdict() {
        let health = CadenceSyncHealth.resolve(
            startupIssue: nil,
            account: .available,
            pushRegistration: .failed("no valid aps-environment entitlement string found for application")
        )

        #expect(health.level == .degraded)
        #expect(health.level.isHealthy == false)
        #expect(health.tone == .caution)
        #expect(health.iconName != "checkmark.icloud")
        // The system's own words reach the card. This is the sentence that names the entitlement,
        // and on the build that started T-1309 it was written only to the unified log.
        #expect(health.detail.contains("aps-environment"))
    }

    /// The two answers that are not a refusal must not be read as one. `.notAttempted` is what
    /// every test host, UI-test run and local-store-only launch reports, and treating it as a
    /// failure would paint a permanent warning across a perfectly healthy app.
    @Test func onlyAnOutrightRefusalDegradesTheVerdict() {
        for pushRegistration in [CadencePushRegistrationState.notAttempted, .registered] {
            let health = CadenceSyncHealth.resolve(
                startupIssue: nil,
                account: .available,
                pushRegistration: pushRegistration
            )
            #expect(health.level == .syncing, "\(pushRegistration) reported \(health.level)")
        }
    }

    /// Precedence, both directions. A push failure is a symptom when the account or the store is
    /// the cause, and naming the symptom would send the user to fix the wrong thing.
    @Test func aPushFailureNeverOutranksTheStoreOrTheAccount() {
        let noStore = CadenceSyncHealth.resolve(
            startupIssue: recovery,
            account: .available,
            pushRegistration: .failed("no valid aps-environment entitlement")
        )
        #expect(noStore.level == .notSyncing)
        #expect(noStore.title == recovery.bannerTitle)

        let noAccount = CadenceSyncHealth.resolve(
            startupIssue: nil,
            account: .noAccount,
            pushRegistration: .failed("no valid aps-environment entitlement")
        )
        #expect(noAccount.level == .degraded)
        #expect(noAccount.title == "No iCloud account")
    }

    /// The delegate callback's end of the wire, which used to be a `logger.error` and nothing
    /// else. Driven through the registrar rather than the monitor so that deleting the one line
    /// that records the failure fails a test instead of passing quietly.
    @Test func theRegistrarsFailureCallbackRecordsSomethingAViewCanRead() {
        let monitor = CadencePushRegistrationMonitor()
        #expect(monitor.state == .notAttempted)

        CadenceRemoteNotificationRegistrar.noteRegistrationFailure(
            NSError(
                domain: "NSCocoaErrorDomain",
                code: 3000,
                userInfo: [NSLocalizedDescriptionKey: "no valid aps-environment entitlement string found for application"]
            ),
            into: monitor
        )

        #expect(monitor.state == .failed("no valid aps-environment entitlement string found for application"))
        #expect(
            CadenceSyncHealth.resolve(
                startupIssue: nil,
                account: .available,
                pushRegistration: monitor.state
            ).level == .degraded
        )

        CadenceRemoteNotificationRegistrar.noteRegistrationSucceeded(into: monitor)
        #expect(monitor.state == .registered)
    }

    // MARK: - CKAccountStatus bridging

    @Test func checkingBeatsAnErrorWhichBeatsAStaleStatus() {
        // A retry in flight over an old error over the last known status. The iOS-only version of
        // this decision applied one precedence to the title and the reverse to the subtitle, so a
        // retried failure read "Checking iCloud" above the previous error text.
        #expect(CadenceCloudAccountState(accountStatus: .available, accountError: "old", isChecking: true) == .checking)
        #expect(CadenceCloudAccountState(accountStatus: .available, accountError: "old", isChecking: false) == .failed("old"))
        #expect(CadenceCloudAccountState(accountStatus: .available, accountError: nil, isChecking: false) == .available)
        #expect(CadenceCloudAccountState(accountStatus: nil, accountError: nil, isChecking: false) == .notChecked)
        // An empty error string is not an error.
        #expect(CadenceCloudAccountState(accountStatus: .noAccount, accountError: "", isChecking: false) == .noAccount)
    }

    @Test func everyCKAccountStatusIsMapped() {
        let expected: [(CKAccountStatus, CadenceCloudAccountState)] = [
            (.available, .available),
            (.noAccount, .noAccount),
            (.restricted, .restricted),
            (.temporarilyUnavailable, .temporarilyUnavailable),
            (.couldNotDetermine, .couldNotDetermine),
        ]
        for (status, state) in expected {
            #expect(CadenceCloudAccountState(accountStatus: status, accountError: nil, isChecking: false) == state)
        }
    }

    // MARK: - Banner copy

    @Test func everyIssueKindHasItsOwnBannerCopy() {
        let issues = [recovery, inMemory, maintenance]
        #expect(Set(issues.map(\.bannerTitle)).count == issues.count)
        #expect(Set(issues.map(\.bannerIcon)).count == issues.count)
        for issue in issues {
            // The recorded message is what says *what* happened; the banner must not drop it.
            #expect(issue.bannerDetail.hasPrefix(issue.message))
            #expect(issue.bannerDetail.count > issue.message.count, "\(issue.kind) states no consequence")
        }
    }

    @Test func bannerCopyNamesTheConsequence() {
        #expect(recovery.bannerDetail.contains("will not sync"))
        #expect(inMemory.bannerDetail.contains("quitting Cadence discards this session"))
        #expect(maintenance.bannerDetail.contains("still syncing"))
    }

    @Test func onlyTheInMemoryStoreIsCritical() {
        #expect(recovery.bannerTone == .caution)
        #expect(maintenance.bannerTone == .caution)
        #expect(inMemory.bannerTone == .critical)
    }

    // MARK: - Level ordering

    @Test func levelsOrderWorstLast() {
        #expect(CadenceSyncHealthLevel.allCases.sorted() == [.syncing, .checking, .unknown, .degraded, .notSyncing])
        #expect(CadenceSyncHealthLevel.syncing < CadenceSyncHealthLevel.notSyncing)
    }
}
