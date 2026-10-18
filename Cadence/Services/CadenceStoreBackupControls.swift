import Foundation

/// The calls Settings → Data Safety makes on local store backups, for both platforms ([[T-1477]]).
///
/// The engine is `StoreBackupManager` and nothing here re-implements it: every write below is one
/// of its entry points, handed **this value's** store directory and defaults. That is the point of
/// the type. The Mac section used to call the no-argument entry points inline, which resolve the
/// launch's store implicitly; a second screen doing the same would be a second place where "which
/// store" is answered, and a test of either could only reach it by reaching the real one. Here the
/// store is a stored property, so `CadenceStoreBackupControlsTests` drives every call — create,
/// clean, stage, cancel, and the launch-time restore the stage leads to — against a disposable
/// directory under the test's own temporary directory and a throwaway defaults suite.
///
/// `forThisLaunch()` is the only constructor the views use, and the only place this type learns
/// where the real store is.
struct CadenceStoreBackupControls {
    let storeDirectoryURL: URL
    let defaults: UserDefaults
    let fileManager: FileManager
    /// What `CadenceUITestStoreDirectory.mayWriteBackups` is asked with. Injected so the refusing
    /// half of the gate can be driven by a test; the views never pass it.
    let environment: [String: String]
    /// The allow-listed root that gate compares against, injected for the same reason — so a test
    /// can stand a refused store directory *inside* the real temporary directory, and a mutation
    /// that deletes the gate writes nowhere a test did not make.
    let temporaryDirectory: URL

    init(
        storeDirectoryURL: URL,
        defaults: UserDefaults,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.storeDirectoryURL = storeDirectoryURL
        self.defaults = defaults
        self.fileManager = fileManager
        self.environment = environment
        self.temporaryDirectory = temporaryDirectory
    }

    /// The store this launch opened, resolved the way every `StoreBackupManager` default does —
    /// redirected under a test or agent launch ([[T-1448]], [[T-1530]]) — through the
    /// **non-creating** answer, so opening Settings cannot create the directory it asks about
    /// ([[T-1852]]). `nil` when the store's location cannot be resolved at all.
    static func forThisLaunch() -> CadenceStoreBackupControls? {
        guard let url = try? StoreBackupManager.storeDirectoryLocation(
            in: ProcessInfo.processInfo.environment
        ) else { return nil }
        return CadenceStoreBackupControls(storeDirectoryURL: url, defaults: CadenceDefaults.store)
    }

    // MARK: - Reading

    func backups() -> [StoreBackupSnapshot] {
        StoreBackupManager.listBackups(storeDirectoryURL: storeDirectoryURL, fileManager: fileManager)
    }

    /// The backup a staged restore will apply, if one is staged. `url` is always set when a
    /// restore is pending; `snapshot` is `nil` when the pending path is no longer in the list.
    func pendingRestore() -> (url: URL, snapshot: StoreBackupSnapshot?)? {
        guard let url = StoreBackupManager.pendingRestoreURL(defaults: defaults) else { return nil }
        let path = url.standardizedFileURL.path
        return (url, backups().first { $0.url.standardizedFileURL.path == path })
    }

    func retainedUnrestoredOriginals() -> [URL] {
        StoreBackupManager.retainedUnrestoredOriginalDirectories(in: storeDirectoryURL, fileManager: fileManager)
    }

    // MARK: - Writing. Each returns the sentence the card shows.

    func createBackup() -> String {
        do {
            guard let url = try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectoryURL,
                fileManager: fileManager,
                defaults: defaults
            ) else {
                return CadenceStoreBackupPresentation.noActiveStore
            }
            return CadenceStoreBackupPresentation.created(url)
        } catch {
            return CadenceStoreBackupPresentation.backupFailed(error.localizedDescription)
        }
    }

    func cleanUpAutomaticBackups() -> String {
        do {
            let removed = try StoreBackupManager.cleanUpAutomaticBackups(
                storeDirectoryURL: storeDirectoryURL,
                fileManager: fileManager,
                defaults: defaults
            )
            return CadenceStoreBackupPresentation.cleanedUp(removedCount: removed)
        } catch {
            return CadenceStoreBackupPresentation.cleanupFailed(error.localizedDescription)
        }
    }

    /// Records the instruction the next launch acts on. Nothing in the store moves here.
    ///
    /// Two refusals come before `scheduleRestore`, and both exist because this is the one call on
    /// the screen whose effect lands later, at a launch nobody is watching:
    /// - the backup must still be one of **this store's** listed backups — a row can outlive its
    ///   folder (a reset, a thinning) and a stale path must not become a pending instruction;
    /// - under a test or agent launch the store must be inside the temporary directory, the same
    ///   allow-list every backup writer asks ([[T-3045]] (3)). `scheduleRestore` writes a marker
    ///   beside the store, and that would otherwise be a write into a real store directory.
    func stageRestore(_ backup: StoreBackupSnapshot, on platform: CadenceStoreBackupPlatform) -> String {
        guard writesAllowed else {
            return CadenceStoreBackupPresentation.stageFailed(
                StoreBackupManager.BackupWriteRefusal(storeDirectoryPath: storeDirectoryURL.path).localizedDescription
            )
        }
        let path = backup.url.standardizedFileURL.path
        guard backups().contains(where: { $0.url.standardizedFileURL.path == path }) else {
            return CadenceStoreBackupPresentation.notThisStoresBackup
        }
        do {
            try StoreBackupManager.scheduleRestore(
                from: backup.url,
                defaults: defaults,
                storeDirectoryURL: storeDirectoryURL
            )
            return CadenceStoreBackupPresentation.staged(on: platform)
        } catch {
            return CadenceStoreBackupPresentation.stageFailed(error.localizedDescription)
        }
    }

    /// Withdraws a staged restore before any launch has acted on it. The store and every backup
    /// are untouched; only the instruction and its marker go.
    func cancelStagedRestore() -> String {
        guard writesAllowed else {
            return CadenceStoreBackupPresentation.cancelFailed(
                StoreBackupManager.BackupWriteRefusal(storeDirectoryPath: storeDirectoryURL.path).localizedDescription
            )
        }
        StoreBackupManager.clearPendingRestore(defaults: defaults, storeDirectoryURL: storeDirectoryURL)
        return CadenceStoreBackupPresentation.stagedRestoreCancelled
    }

    private var writesAllowed: Bool {
        CadenceUITestStoreDirectory.mayWriteBackups(
            inStoreDirectory: storeDirectoryURL,
            environment: environment,
            temporaryDirectory: temporaryDirectory
        )
    }
}
