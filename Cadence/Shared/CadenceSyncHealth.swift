import CloudKit
import SwiftUI

/// Why the store Cadence is running on is not the store it asked for.
///
/// `PersistenceController` falls back to a local recovery store whenever the CloudKit-backed one
/// cannot be opened — the right call, because losing access to your own data because CloudKit is
/// unavailable is worse than not syncing. What made it a defect is that the fallback was recorded
/// only as a free-form `String`, so the one surface that rendered it had to decide from prose
/// whether sync was off. Two of the three issues Cadence can record leave the store local; the
/// third does not touch sync at all. That distinction is this enum.
enum CadenceStartupIssueKind: String, Equatable, CaseIterable {
    /// The CloudKit store could not be opened, so a local recovery store was used instead.
    case recoveryStore
    /// The recovery store failed too; the app is running entirely in memory.
    case inMemoryStore
    /// The store opened normally — a startup maintenance save failed afterwards.
    case maintenanceSaveFailed

    /// Whether the store Cadence actually opened has no CloudKit database behind it.
    ///
    /// This is the whole point of the type: a maintenance save failure is a real problem worth a
    /// banner, but it is **not** a sync failure, and reporting it as one would be its own lie.
    var disablesCloudSync: Bool {
        switch self {
        case .recoveryStore, .inMemoryStore: return true
        case .maintenanceSaveFailed: return false
        }
    }

    /// Whether quitting the app loses whatever was written during this launch.
    var losesDataOnQuit: Bool { self == .inMemoryStore }
}

/// One recorded startup problem: what went wrong, and the message describing it.
struct CadenceStartupIssue: Equatable {
    let kind: CadenceStartupIssueKind
    let message: String

    init(kind: CadenceStartupIssueKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

extension CadenceStartupIssue {
    var bannerTitle: String {
        switch kind {
        case .recoveryStore: return "iCloud Sync Is Off"
        case .inMemoryStore: return "Temporary Store — Changes Will Be Lost"
        case .maintenanceSaveFailed: return "Startup Maintenance Failed"
        }
    }

    /// The recorded message plus the consequence it does not state.
    ///
    /// The stored strings explain what Cadence *did* ("opened a recovery store because …"); a user
    /// looking at a banner needs to know what that costs them, which is that nothing they do here
    /// reaches their other devices.
    var bannerDetail: String {
        switch kind {
        case .recoveryStore:
            return "\(message) Changes made on this device will not sync to your other devices."
        case .inMemoryStore:
            return "\(message) Nothing is saved to disk and nothing syncs — quitting Cadence discards this session."
        case .maintenanceSaveFailed:
            return "\(message) Your data is intact and still syncing; some startup housekeeping did not complete."
        }
    }

    var bannerIcon: String {
        switch kind {
        case .recoveryStore: return "externaldrive.badge.exclamationmark"
        case .inMemoryStore: return "exclamationmark.triangle.fill"
        case .maintenanceSaveFailed: return "wrench.and.screwdriver.fill"
        }
    }

    var bannerTone: CadenceSyncHealthTone {
        kind.losesDataOnQuit ? .critical : .caution
    }
}

/// The device's CloudKit account, in terms this app cares about.
///
/// A platform-neutral mirror of `CKAccountStatus` plus the three states that are not statuses at
/// all — not checked yet, check in flight, check failed. Those three used to be inferred from a
/// pair of optionals at every call site.
enum CadenceCloudAccountState: Equatable {
    case notChecked
    case checking
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
    case failed(String)

    /// `isChecking` wins, then an error, then the status. The previous iOS-only version of this
    /// decision applied that precedence to the title and the *opposite* precedence to the
    /// subtitle, so a failed check that was being retried read "Checking iCloud" over the old
    /// error text.
    init(accountStatus: CKAccountStatus?, accountError: String?, isChecking: Bool) {
        if isChecking {
            self = .checking
            return
        }
        if let accountError, !accountError.isEmpty {
            self = .failed(accountError)
            return
        }
        guard let accountStatus else {
            self = .notChecked
            return
        }
        switch accountStatus {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .couldNotDetermine
        @unknown default: self = .couldNotDetermine
        }
    }
}

/// How much colour a sync answer has earned. Kept separate from the level so the tint is pinned by
/// a test without a test having to compare `Color` values.
enum CadenceSyncHealthTone: Equatable {
    case positive
    case info
    case neutral
    case caution
    case critical

    var tint: Color {
        switch self {
        case .positive: return Theme.green
        case .info: return Theme.blue
        case .neutral: return Theme.dim
        case .caution: return Theme.amber
        case .critical: return Theme.red
        }
    }
}

/// Ordered worst-last, so `max` is "the thing to tell the user about".
enum CadenceSyncHealthLevel: Int, Comparable, CaseIterable {
    /// CloudKit store open, account available.
    case syncing = 0
    /// Account check in flight.
    case checking = 1
    /// Account not checked, or the device could not say.
    case unknown = 2
    /// The store is CloudKit-backed but the account cannot back it.
    case degraded = 3
    /// The store has no CloudKit database at all. Nothing will sync, whatever the account says.
    case notSyncing = 4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The single "is sync actually working" answer, shared by the startup banner and iOS Settings.
///
/// Before this existed there were two unrelated indicators: a macOS-only banner reading
/// `PersistenceController.startupIssue`, and an iOS Settings row reading `CKAccountStatus`. They
/// could — and on a device that had dropped to a recovery store, did — disagree: Settings showed a
/// green `checkmark.icloud` and "CloudKit should be able to sync Cadence data" while the open store
/// had `cloudKitDatabase: .none` and could not sync anything. An available account is a necessary
/// condition, not a sufficient one, so the store's own state has to win.
struct CadenceSyncHealth: Equatable {
    let level: CadenceSyncHealthLevel
    let tone: CadenceSyncHealthTone
    let title: String
    let detail: String
    let iconName: String

    static func resolve(
        startupIssue: CadenceStartupIssue?,
        account: CadenceCloudAccountState
    ) -> CadenceSyncHealth {
        // The store wins. A CloudKit account that is perfectly healthy cannot sync a store that
        // was opened with no CloudKit database behind it.
        if let startupIssue, startupIssue.kind.disablesCloudSync {
            return CadenceSyncHealth(
                level: .notSyncing,
                tone: startupIssue.bannerTone,
                title: startupIssue.bannerTitle,
                detail: startupIssue.bannerDetail,
                iconName: startupIssue.bannerIcon
            )
        }

        switch account {
        case .available:
            return CadenceSyncHealth(
                level: .syncing,
                tone: .positive,
                title: "iCloud available",
                detail: "CloudKit should be able to sync Cadence data.",
                iconName: "checkmark.icloud"
            )
        case .checking:
            return CadenceSyncHealth(
                level: .checking,
                tone: .info,
                title: "Checking iCloud",
                detail: "Asking Apple for this device's account status.",
                iconName: "icloud"
            )
        case .notChecked:
            return CadenceSyncHealth(
                level: .unknown,
                tone: .neutral,
                title: "iCloud not checked",
                detail: "Check status before relying on TestFlight sync.",
                iconName: "icloud"
            )
        case .couldNotDetermine:
            return CadenceSyncHealth(
                level: .unknown,
                tone: .caution,
                title: "iCloud unknown",
                detail: "Try again or check device network/iCloud settings.",
                iconName: "icloud.slash"
            )
        case .noAccount:
            return CadenceSyncHealth(
                level: .degraded,
                tone: .caution,
                title: "No iCloud account",
                detail: "Sign into iCloud on this device to sync.",
                iconName: "icloud.slash"
            )
        case .restricted:
            return CadenceSyncHealth(
                level: .degraded,
                tone: .caution,
                title: "iCloud restricted",
                detail: "iCloud is restricted by device or account policy.",
                iconName: "icloud.slash"
            )
        case .temporarilyUnavailable:
            return CadenceSyncHealth(
                level: .degraded,
                tone: .caution,
                title: "iCloud temporarily unavailable",
                detail: "Apple reported iCloud is temporarily unavailable.",
                iconName: "icloud.slash"
            )
        case .failed(let message):
            return CadenceSyncHealth(
                level: .degraded,
                tone: .caution,
                title: "Could not check iCloud",
                detail: message,
                iconName: "exclamationmark.icloud"
            )
        }
    }
}
