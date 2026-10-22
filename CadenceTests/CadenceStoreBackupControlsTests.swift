import Foundation
import Testing
@testable import Cadence

/// [[T-1477]]: the calls both Settings → Data Safety screens make on local store backups, and the
/// sentences they show — driven end to end against **disposable stores only**.
///
/// **The owner's ruling for this ticket (2026-10-18): the restore path is tested; the restore is
/// never exercised against a real store.** Every store below is a fresh directory under this
/// process's temporary directory, every defaults suite is `withTemporaryDefaults`'s, and every
/// `CadenceStoreBackupControls` is built with both handed in. Nothing here calls
/// `CadenceStoreBackupControls.forThisLaunch()` or any no-argument `StoreBackupManager` entry
/// point; the one test that reads `forThisLaunch` reads its **source**.
@MainActor
struct CadenceStoreBackupControlsTests {
    // MARK: - Fixtures

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceStoreBackupControlsTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seed(_ directory: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in CadenceStoreSupport.storeItemURLs(in: directory) {
            try FileManager.default.removeItem(at: item)
        }
        // A real SQLite database: the restore gate refuses any other store file (T-3044 (c)).
        try CadenceSQLiteMarkerStoreFixture.write(marker, to: directory.appendingPathComponent(CadenceStoreSupport.storeFilename))
        try Data("\(marker)-wal".utf8).write(to: directory.appendingPathComponent("default.store-wal"))
    }

    private func marker(in directory: URL) -> String? {
        CadenceSQLiteMarkerStoreFixture.marker(at: directory.appendingPathComponent(CadenceStoreSupport.storeFilename))
    }

    private func isInside(_ url: URL, _ root: URL) -> Bool {
        CadenceUITestStoreDirectory.isPath(url, inside: root)
    }

    // MARK: - Create

    @Test func createBackupThroughTheControlsWritesBesideTheDisposableStoreAndSaysWhich() throws {
        try withTemporaryDefaults("CadenceTests.storeBackupControls") { defaults in
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("store", isDirectory: true)
            try seed(store, marker: "live")
            let controls = CadenceStoreBackupControls(storeDirectoryURL: store, defaults: defaults)

            #expect(controls.backups().isEmpty, "non-vacuity: a fresh store starts with no backups")
            let status = controls.createBackup()

            let backups = controls.backups()
            #expect(backups.count == 1)
            let backup = try #require(backups.first)
            #expect(backup.reason == StoreBackupReason.manual.displayName)
            #expect(isInside(backup.url, store), "the backup landed outside the disposable store")
            #expect(status == CadenceStoreBackupPresentation.created(backup.url))
            #expect(marker(in: store) == "live", "creating a backup changed the store")
        }
    }

    @Test func createBackupWithNoStoreSaysSoAndWritesNothing() throws {
        try withTemporaryDefaults("CadenceTests.storeBackupControls") { defaults in
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("empty", isDirectory: true)
            let controls = CadenceStoreBackupControls(storeDirectoryURL: store, defaults: defaults)

            #expect(controls.createBackup() == CadenceStoreBackupPresentation.noActiveStore)
            #expect(controls.backups().isEmpty)
        }
    }

    // MARK: - Stage, then the launch that applies it

    /// The whole path the phone's **Stage Restore** button starts, ending in the launch preflight
    /// that applies it — every leg against the disposable store.
    @Test func aStagedRestoreChangesNothingUntilTheLaunchThenRestoresAndKeepsTheReplacedStore() throws {
        try withTemporaryDefaults("CadenceTests.storeBackupControls") { defaults in
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("store", isDirectory: true)
            try seed(store, marker: "the-backup")
            let controls = CadenceStoreBackupControls(storeDirectoryURL: store, defaults: defaults)
            _ = controls.createBackup()
            let backup = try #require(controls.backups().first)
            try seed(store, marker: "what-is-live")

            let status = controls.stageRestore(backup, on: .phone)

            #expect(status == CadenceStoreBackupPresentation.staged(on: .phone))
            // Nothing changes now — the first claim the confirmation makes.
            #expect(marker(in: store) == "what-is-live")
            let pending = try #require(controls.pendingRestore())
            #expect(pending.snapshot?.id == backup.id)
            #expect(FileManager.default.fileExists(
                atPath: CadenceStoreSupport.restorePendingMarkerURL(inStoreDirectory: store).path
            ), "the widget-facing marker was not written beside the store")

            try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: store, defaults: defaults)

            #expect(marker(in: store) == "the-backup")
            #expect(controls.pendingRestore() == nil)
            // The store it replaced is kept — the confirmation's third claim.
            let preRestore = controls.backups().filter { $0.reason == StoreBackupReason.preRestore.displayName }
            #expect(preRestore.count == 1)
            let kept = try #require(preRestore.first)
            #expect(marker(in: kept.url) == "what-is-live")
        }
    }

    @Test func cancellingAStagedRestoreLeavesTheNextLaunchWithNothingToApply() throws {
        try withTemporaryDefaults("CadenceTests.storeBackupControls") { defaults in
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("store", isDirectory: true)
            try seed(store, marker: "the-backup")
            let controls = CadenceStoreBackupControls(storeDirectoryURL: store, defaults: defaults)
            _ = controls.createBackup()
            let backup = try #require(controls.backups().first)
            try seed(store, marker: "what-is-live")
            _ = controls.stageRestore(backup, on: .phone)
            #expect(controls.pendingRestore() != nil, "non-vacuity: the restore was staged")

            #expect(controls.cancelStagedRestore() == CadenceStoreBackupPresentation.stagedRestoreCancelled)

            #expect(controls.pendingRestore() == nil)
            #expect(!FileManager.default.fileExists(
                atPath: CadenceStoreSupport.restorePendingMarkerURL(inStoreDirectory: store).path
            ))
            try StoreBackupManager.performPendingRestoreIfNeeded(storeDirectoryURL: store, defaults: defaults)
            #expect(marker(in: store) == "what-is-live")
            #expect(controls.backups().count == 1, "a cancelled restore still took a pre-restore backup")
        }
    }

    // MARK: - The two refusals before scheduleRestore

    @Test func aBackupThatIsNotOneOfThisStoresIsRefusedAndNothingIsStaged() throws {
        try withTemporaryDefaults("CadenceTests.storeBackupControls") { defaults in
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appendingPathComponent("store", isDirectory: true)
            let other = root.appendingPathComponent("other", isDirectory: true)
            try seed(store, marker: "live")
            try seed(other, marker: "someone-elses")
            let otherControls = CadenceStoreBackupControls(storeDirectoryURL: other, defaults: defaults)
            _ = otherControls.createBackup()
            let foreign = try #require(otherControls.backups().first)
            let controls = CadenceStoreBackupControls(storeDirectoryURL: store, defaults: defaults)

            #expect(controls.stageRestore(foreign, on: .mac) == CadenceStoreBackupPresentation.notThisStoresBackup)

            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            #expect(!FileManager.default.fileExists(
                atPath: CadenceStoreSupport.restorePendingMarkerURL(inStoreDirectory: store).path
            ))
        }
    }

    /// Under a test or agent launch a store outside the allow-listed temporary directory is refused
    /// before anything is written. Both directories are made *inside* the real temporary directory
    /// and the allow-list is narrowed to one of them, so a mutation that deletes the gate writes
    /// only into a folder this test made.
    @Test func underATestLaunchAStoreOutsideTheAllowListIsRefusedBeforeAnythingIsStaged() throws {
        try withTemporaryDefaults("CadenceTests.storeBackupControls") { defaults in
            let root = try makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let allowed = root.appendingPathComponent("allowed", isDirectory: true)
            let store = root.appendingPathComponent("refused", isDirectory: true)
            try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
            try seed(store, marker: "live")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: store,
                defaults: defaults
            ))
            let environment = ProcessInfo.processInfo.environment
            try #require(
                CadenceUITestStoreDirectory.redirectedStoreDirectory(in: environment, temporaryDirectory: allowed) != nil,
                "precondition: the test host reads as a redirected launch"
            )
            let controls = CadenceStoreBackupControls(
                storeDirectoryURL: store,
                defaults: defaults,
                environment: environment,
                temporaryDirectory: allowed
            )
            let backup = try #require(controls.backups().first { $0.url.lastPathComponent == backupURL.lastPathComponent })

            let status = controls.stageRestore(backup, on: .phone)

            #expect(status.hasPrefix("Could not stage restore:"))
            #expect(status.contains("test or agent launch"))
            #expect(StoreBackupManager.pendingRestoreURL(defaults: defaults) == nil)
            #expect(!FileManager.default.fileExists(
                atPath: CadenceStoreSupport.restorePendingMarkerURL(inStoreDirectory: store).path
            ))
        }
    }

    // MARK: - The confirmation

    @Test func bothConfirmationsSayNothingChangesNowTheReplacedStoreIsKeptAndWhatICloudCanDo() {
        let backup = StoreBackupSnapshot(
            id: "20261018-120000-manual",
            url: URL(fileURLWithPath: "/nonexistent/backup", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 1_760_000_000),
            reason: StoreBackupReason.manual.displayName,
            sizeBytes: 1024
        )
        for platform in CadenceStoreBackupPlatform.allCases {
            let message = CadenceStoreBackupPresentation.confirmationMessage(for: backup, on: platform)
            #expect(message.hasPrefix("Nothing changes now."), "\(platform)")
            #expect(message.contains(CadenceStoreBackupPresentation.rowTitle(backup)), "\(platform): the backup is not named")
            #expect(message.contains(CadenceStoreBackupPresentation.preRestoreBackupNote), "\(platform)")
            #expect(message.contains(CadenceStoreBackupPresentation.cloudKitNote), "\(platform)")
            #expect(message.contains(CadenceStoreBackupPresentation.whenItApplies(on: platform)), "\(platform)")
        }
        #expect(CadenceStoreBackupPresentation.whenItApplies(on: .phone).contains("app switcher"))
        #expect(CadenceStoreBackupPresentation.whenItApplies(on: .phone).contains("background"))
        #expect(CadenceStoreBackupPresentation.whenItApplies(on: .mac).contains("Quit"))
        #expect(CadenceStoreBackupPresentation.preRestoreBackupNote.contains(StoreBackupReason.preRestore.displayName))
    }

    // MARK: - The Mac makes these calls and no others

    @Test func theMacSectionMakesTheSameCallsInsteadOfItsOwn() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        )
        #expect(code.contains("struct SettingsDataSafetySection: View"), "non-vacuity: wrong file")
        func count(_ needle: String) -> Int { code.components(separatedBy: needle).count - 1 }
        #expect(count("CadenceStoreBackupControls.forThisLaunch()") == 1)
        #expect(count("StoreBackupManager.scheduleRestore") == 0)
        #expect(count("StoreBackupManager.createBackupIfStoreExists") == 0)
        #expect(count("StoreBackupManager.cleanUpAutomaticBackups") == 0)
        #expect(count(".stageRestore(backup, on: .mac)") == 1)
        #expect(count("CadenceStoreBackupPresentation.confirmationMessage(for: backup, on: .mac)") == 1)
    }

    // MARK: - The phone makes the same calls

    /// The mirror of the Mac test above, for the section [[T-1477]] added to Settings → Data
    /// Safety on iPhone and iPad. It reads the phone section's SOURCE for the same reason: this
    /// target never compiles `Cadence/iOS/`, and the one thing worth pinning is that the section
    /// reaches backups only through the shared controls and shows only the shared sentences.
    @Test func thePhoneSectionReachesBackupsOnlyThroughTheSharedControls() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSStoreBackupSettingsSection.swift")
        )
        #expect(code.contains("struct iOSStoreBackupSettingsSection: View"), "non-vacuity: wrong file")
        func count(_ needle: String) -> Int { code.components(separatedBy: needle).count - 1 }
        #expect(count("CadenceStoreBackupControls.forThisLaunch()") == 1)
        #expect(count("StoreBackupManager.") == 0, "the phone section calls the engine directly")
        #expect(count(".stageRestore(backup, on: .phone)") == 1)
        #expect(count(".cancelStagedRestore()") == 1)
        #expect(count("CadenceStoreBackupPresentation.confirmationMessage(for: backup, on: .phone)") == 1)
        #expect(count("role: .destructive") == 1, "the stage button is the dialog's one destructive action")
        #expect(count("deleteAllBackups") == 0)
        #expect(count("deleteRetainedUnrestoredOriginals") == 0)

        let settings = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsView.swift"))
        #expect(settings.components(separatedBy: "iOSStoreBackupSettingsSection()").count - 1 == 1)
    }

    /// `forThisLaunch()` is the only place the controls learn where the real store is, and it asks
    /// the redirect-aware, non-creating resolution — never the app group directly.
    @Test func theControlsResolveTheRealStoreInExactlyOnePlaceAndThroughTheRedirect() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/CadenceStoreBackupControls.swift")
        )
        #expect(code.contains("struct CadenceStoreBackupControls"), "non-vacuity: wrong file")
        func count(_ needle: String) -> Int { code.components(separatedBy: needle).count - 1 }
        #expect(count("StoreBackupManager.storeDirectoryLocation(") == 1)
        #expect(count("CadenceDefaults.store") == 1)
        #expect(count("primaryStoreDirectoryURL") == 0)
        #expect(count("StoreBackupManager.storeDirectoryURL(") == 0, "the creating resolution")
    }
}
