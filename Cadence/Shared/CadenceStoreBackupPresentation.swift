import Foundation

/// Which Settings screen is asking. The only sentences that differ are the ones about getting
/// Cadence to start again, because quitting an app is a menu command on a Mac and is not one on a
/// phone ([[T-1477]]).
nonisolated enum CadenceStoreBackupPlatform: Hashable, CaseIterable {
    case mac
    case phone
}

/// Every sentence Settings → Data Safety says about **local store backups**, on both platforms.
///
/// **[[T-1477]].** Until this ticket only the Mac could create a backup, thin the automatic ones or
/// stage a restore, and its sentences lived inline in `SettingsDataSafetySection`. The phone is to
/// get the same three controls (its section is built and parked — T-1477 is PARTIAL until a lease
/// on one census line is granted), and two copies of "what does a restore do" is how one of them
/// would come to promise something the engine does not do. The engine is `StoreBackupManager`;
/// the calls both screens make are `CadenceStoreBackupControls`.
///
/// **The two decisions the ticket required before any UI was written** are argued here, because
/// this is where a reader meets them:
///
/// 1. **The confirmation.** A restore is *staged*, never applied while the app is running, and the
///    dialog says so first: nothing changes now. It names the backup by its date and kind, says
///    when the restore will actually happen, and says the store it replaces is kept as a
///    pre-restore backup — which `StoreBackupManager.applyRestore` takes before its swap and
///    `CadenceStoreRestoreTests.aRestoreThatSucceedsReplacesTheStoreAndClearsThePendingFlag`
///    holds. On a phone "the next time it starts" is not a moment the user chooses — iOS can
///    relaunch an app in the background — so the phone's dialog says that, and the phone's
///    section offers **Cancel Staged Restore** (`CadenceStoreBackupControls.cancelStagedRestore`)
///    for as long as one is pending.
///
/// 2. **CloudKit.** The restore cannot race a sync *in this process*: it runs in
///    `PersistenceController`'s launch preflight, before `makeContainer()` opens the CloudKit-backed
///    store, and the widget extension is held off by the restore-pending marker beside the store.
///    What happens *after* is iCloud's: the restored store syncs again from the point the backup
///    was taken, so changes iCloud holds that are newer than the backup can come back in. That
///    half is stated as a possibility, not a promise either way, because it cannot be measured
///    against a disposable store and the owner's ruling forbids measuring it against a real one.
///    The sentence is `cloudKitNote`, shown in the confirmation on both platforms.
enum CadenceStoreBackupPresentation {
    // MARK: - The card

    static let title = "Backups"

    static let description = "Cadence copies the local store — including CloudKit assets and external files — at every launch, before a restore, and whenever you ask. Automatic copies are thinned over time."

    static let createButtonTitle = "Create Backup"
    static let cleanUpButtonTitle = "Clean Automatic"
    static let restoreButtonTitle = "Restore"
    static let availableBackupsLabel = "Available Backups"
    static let noBackupsText = "No backups available."

    /// How many rows the list draws. The Mac has drawn sixteen since before this ticket.
    static let listedBackupLimit = 16

    static func rowTitle(_ backup: StoreBackupSnapshot) -> String {
        backup.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    static func rowDetail(_ backup: StoreBackupSnapshot) -> String {
        "\(backup.reason) • \(backup.displaySize)"
    }

    // MARK: - The confirmation

    static let confirmationTitle = "Restore Backup?"
    static let confirmButtonTitle = "Stage Restore"
    static let cancelButtonTitle = "Cancel"

    /// The CloudKit half of decision 2 in the type comment. Shown on both platforms: a Mac's store
    /// syncs the same way a phone's does.
    static let cloudKitNote = "A restore replaces the copy on this device only. With iCloud sync on, changes iCloud holds that are newer than this backup can sync back in afterwards, so a restore does not roll back your other devices."

    static let preRestoreBackupNote = "The store it replaces is kept first, as a Before Restore backup in this list."

    static func whenItApplies(on platform: CadenceStoreBackupPlatform) -> String {
        switch platform {
        case .mac:
            return "Quit and reopen Cadence after staging."
        case .phone:
            return "To apply it, close Cadence from the app switcher and open it again. iOS can also start Cadence in the background, and the restore applies then."
        }
    }

    /// The whole message under `confirmationTitle`. Leads with what does *not* happen, because the
    /// button the reader is about to press is red and says Restore.
    static func confirmationMessage(
        for backup: StoreBackupSnapshot,
        on platform: CadenceStoreBackupPlatform
    ) -> String {
        [
            "Nothing changes now. Cadence restores the \(backup.reason) backup from \(rowTitle(backup)) the next time it starts, before it opens the store or syncs.",
            whenItApplies(on: platform),
            preRestoreBackupNote,
            cloudKitNote,
        ].joined(separator: " ")
    }

    // MARK: - The staged restore, while it waits

    static let pendingRestoreLabel = "Staged Restore"
    static let cancelStagedRestoreButtonTitle = "Cancel Staged Restore"

    static func pendingRestoreDescription(
        backup: StoreBackupSnapshot?,
        on platform: CadenceStoreBackupPlatform
    ) -> String {
        let named = backup.map { "The \($0.reason) backup from \(rowTitle($0))" } ?? "A backup"
        return "\(named) will replace this device's store the next time Cadence starts. \(whenItApplies(on: platform))"
    }

    // MARK: - Status sentences

    static func created(_ backupURL: URL) -> String {
        "Created \(backupURL.lastPathComponent)."
    }

    static let noActiveStore = "No active store exists yet."

    static func backupFailed(_ reason: String) -> String {
        "Backup failed: \(reason)"
    }

    static func cleanedUp(removedCount: Int) -> String {
        removedCount == 0
            ? "Automatic backups are already thinned."
            : "Removed \(removedCount) older automatic backup\(removedCount == 1 ? "" : "s")."
    }

    static func cleanupFailed(_ reason: String) -> String {
        "Cleanup failed: \(reason)"
    }

    static func staged(on platform: CadenceStoreBackupPlatform) -> String {
        switch platform {
        case .mac:
            return "Restore staged. Quit and reopen Cadence to apply it."
        case .phone:
            return "Restore staged. Close Cadence from the app switcher and open it again to apply it."
        }
    }

    static func stageFailed(_ reason: String) -> String {
        "Could not stage restore: \(reason)"
    }

    /// Refused before `scheduleRestore` is reached: the row was not one of this store's backups by
    /// the time the button was pressed — deleted by a reset, thinned, or never this store's.
    static let notThisStoresBackup = "Could not stage restore: that backup is no longer in this device's backup list."

    static let stagedRestoreCancelled = "Staged restore cancelled. Nothing was changed."

    static func cancelFailed(_ reason: String) -> String {
        "Could not cancel the staged restore: \(reason)"
    }

    // MARK: - Unrestored store files

    static let unrestoredSectionTitle = "Unrestored Store Files"

    static let unrestoredExplanation = "A restore that did not finish moved these store files aside, and Cadence kept them rather than delete them. They can be the only copy of your data as it was before that restore. Cadence does not back them up or read them; deleting all Cadence data removes them, and nothing else does."
}
