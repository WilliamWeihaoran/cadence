import Foundation
import Testing
@testable import Cadence

/// **T-1680 — the store folders "Delete Account & Data" leaves behind, and the screen that named
/// none of them.**
///
/// [[T-1532]] made the stray `Cadence Store Backups` folders visible. It left the stray *stores*
/// invisible, and they are the worse half of the same defect. `PersistenceController` opens a
/// second store at `<store directory>/Recovery/recovery.store` when the primary one will not open;
/// `CadencePrivacyDataResetService` removes the model objects, the backups and the retained
/// unrestored originals and **not** that folder; and because it is not a backups folder, neither
/// `listBackups()` nor `unmanagedBackupDirectories()` can see it. On the owner's Mac on 2026-09-30
/// that was 512 KB written by a failed launch on 2026-08-19, sitting inside the container the
/// reset empties, named by no screen and reached by no control.
///
/// Three different claims are asserted here. The enumeration **finds** those folders, including
/// the `Recovery/` child of the live store directory, which is the one place a search modelled on
/// T-1532's — live directory excluded — would never look. It **cannot touch them**: these are the
/// only copy of whatever a degraded session recorded, because `makeRecoveryContainer` opens with
/// `cloudKitDatabase: .none` and nothing in one ever synced. And the recovery store itself now
/// **follows the redirect**, so a test host or an agent launch cannot create one inside the
/// signed-in person's app-group container — the [[T-1448]] property, asserted in both directions
/// against `CadenceStoreSupport` rather than against a literal path.
@MainActor
struct CadenceUnmanagedStoreDirectoryTests {

    // MARK: - Fixture

    /// A store directory holding a primary store's files.
    private func plantPrimaryStore(in directoryURL: URL, bytes: Int = 4096) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: bytes)
            .write(to: directoryURL.appendingPathComponent("default.store"))
        try Data(repeating: 0x2A, count: bytes)
            .write(to: directoryURL.appendingPathComponent("default.store-wal"))
    }

    /// A recovery directory holding a `recovery.store`, the shape `makeRecoveryContainer` leaves.
    private func plantRecoveryStore(in directoryURL: URL, bytes: Int = 4096) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: bytes)
            .write(to: directoryURL.appendingPathComponent("recovery.store"))
        try Data(repeating: 0x2A, count: bytes)
            .write(to: directoryURL.appendingPathComponent("recovery.store-wal"))
    }

    /// Every path under `url`, sorted — the reading that says whether a "read-only" walk was.
    private func tree(under url: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return [] }
        return enumerator.compactMap { $0 as? String }.sorted()
    }

    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1680-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - It finds them

    /// The whole defect, against a tree shaped like the real one.
    ///
    /// The layout is the machine's: the live store in its own `Cadence/` subdirectory with a
    /// `Recovery/` folder inside it, one legacy store location that exists, one that does not.
    /// The `Recovery/` child is the case a search built on T-1532's rule cannot reach, because
    /// that rule excludes the live directory and this folder is *inside* it.
    @Test func theRecoveryFolderInsideTheLiveStoreAndEveryEarlierStoreLocationAreFound() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let groupSupport = root
            .appendingPathComponent(
                "Group Containers/group.com.haoranwei.Cadence/Library/Application Support",
                isDirectory: true
            )
        let live = groupSupport.appendingPathComponent("Cadence", isDirectory: true)
        let liveRecovery = live.appendingPathComponent("Recovery", isDirectory: true)
        let legacy = root
            .appendingPathComponent(
                "Containers/com.haoranwei.Cadence/Data/Library/Application Support/Cadence",
                isDirectory: true
            )
        let absentLegacy = root.appendingPathComponent("Library/Application Support/Cadence", isDirectory: true)

        try plantPrimaryStore(in: live)
        try plantRecoveryStore(in: liveRecovery)
        try plantPrimaryStore(in: legacy)
        #expect(!FileManager.default.fileExists(atPath: absentLegacy.path))

        // `live` is handed in as a legacy candidate as well, which is not a contrivance: the
        // store directory an earlier version used and the one this launch opened are the same path
        // on any machine that never moved, and the row would then say the open store is one
        // Cadence is not using. The exclusion is what stops it, and a filter nothing exercises is
        // the vacuous guard this repository keeps finding.
        let found = StoreBackupManager.unmanagedStoreDirectories(
            liveStoreDirectoryURL: live,
            recoveryStoreDirectories: [liveRecovery],
            legacyStoreDirectories: [legacy, absentLegacy, live]
        )

        let paths = found.map(\.url.standardizedFileURL.path)
        #expect(
            Set(paths) == Set([liveRecovery, legacy].map(\.standardizedFileURL.path)),
            "the unmanaged store folders came back as \(paths)"
        )
        #expect(
            paths.contains(liveRecovery.standardizedFileURL.path),
            "the Recovery folder inside the live store directory — the whole of T-1680 — is not reported"
        )
        #expect(
            !paths.contains(live.standardizedFileURL.path),
            "the store this launch has open is reported as one the app is not using"
        )

        let byPath = Dictionary(uniqueKeysWithValues: found.map { ($0.url.standardizedFileURL.path, $0) })
        #expect(byPath[liveRecovery.standardizedFileURL.path]?.kind == .recovery)
        #expect(byPath[legacy.standardizedFileURL.path]?.kind == .previousLocation)
        #expect(found.allSatisfy { $0.itemCount == 2 }, "the store items were miscounted")
        #expect(found.allSatisfy { $0.sizeBytes > 0 }, "a folder of 4 KiB store files was sized at zero")
        #expect(found.allSatisfy { $0.lastModified != nil }, "a folder written a moment ago has no date")
    }

    /// **The size is the store's, not the backups folder's beside it.**
    ///
    /// The legacy directory on the owner's Mac holds a `Cadence Store Backups` folder that
    /// [[T-1532]]'s section already reports with its own size. A recursive walk here would print
    /// those bytes twice on one screen, under two headings, which is a worse answer than the
    /// silence this ticket is about.
    @Test func theSizeCountsTheStoreFilesAndNotTheBackupsFolderBesideThem() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let live = root.appendingPathComponent("Live/Cadence", isDirectory: true)
        let legacy = root.appendingPathComponent("Legacy/Cadence", isDirectory: true)
        try plantPrimaryStore(in: legacy, bytes: 4096)

        // A backups folder an order of magnitude larger than the store beside it.
        let backupURL = legacy
            .appendingPathComponent("Cadence Store Backups/20260528-150916-pre-restore", isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: 512 * 1024)
            .write(to: backupURL.appendingPathComponent("default.store"))

        let found = StoreBackupManager.unmanagedStoreDirectories(
            liveStoreDirectoryURL: live,
            recoveryStoreDirectories: [],
            legacyStoreDirectories: [legacy]
        )

        let directory = try #require(found.first, "the legacy store directory was not reported at all")
        #expect(directory.itemCount == 2, "the backups folder was counted as a store item")
        #expect(
            directory.sizeBytes < 128 * 1024,
            "the row is sized at \(directory.sizeBytes) bytes — the backups folder beside the store is in it"
        )
    }

    /// A directory that exists and holds no store files is not a row.
    ///
    /// Both residues are real: a `Recovery/` folder whose store was moved out by hand, and a
    /// legacy location that holds nothing but the backups folder T-1532 already lists. A row for
    /// either would be this screen reporting a discovery it has not made.
    @Test func aDirectoryWithNoStoreFilesIsNotARow() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let live = root.appendingPathComponent("Live/Cadence", isDirectory: true)
        let emptyRecovery = live.appendingPathComponent("Recovery", isDirectory: true)
        let backupsOnly = root.appendingPathComponent("Legacy/Cadence", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyRecovery, withIntermediateDirectories: true)
        try Data("not a store".utf8).write(to: emptyRecovery.appendingPathComponent("README.txt"))
        try FileManager.default.createDirectory(
            at: backupsOnly.appendingPathComponent("Cadence Store Backups", isDirectory: true),
            withIntermediateDirectories: true
        )

        #expect(
            StoreBackupManager.unmanagedStoreDirectories(
                liveStoreDirectoryURL: live,
                recoveryStoreDirectories: [emptyRecovery],
                legacyStoreDirectories: [backupsOnly]
            ).isEmpty,
            "a directory holding no store files earned a row"
        )
    }

    // MARK: - It cannot touch them

    /// **The safety property, read off the filesystem rather than off the call sites.**
    ///
    /// Every other resolver on `StoreBackupManager` creates the directory it resolves — that is
    /// what `storeDirectoryURL(in:)` does, deliberately — and so did `recoveryStoreDirectoryURL`,
    /// which is why this listing had to be built on a resolver that does not. It walks the only
    /// copy of whatever a degraded session recorded, so it must create nothing, and "must" is
    /// asserted by listing the tree either side of the call rather than by reading the body.
    @Test func listingTheStoreFoldersWritesNothingAnywhere() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let live = root.appendingPathComponent("Live/Cadence", isDirectory: true)
        let liveRecovery = live.appendingPathComponent("Recovery", isDirectory: true)
        // Candidates that do not exist at all: the whole branch below each, folder and parent, has
        // to still be absent afterwards.
        let absentRecovery = root.appendingPathComponent("Nowhere/Cadence/Recovery", isDirectory: true)
        let absentLegacy = root.appendingPathComponent("Elsewhere/Cadence", isDirectory: true)
        try plantPrimaryStore(in: live)
        try plantRecoveryStore(in: liveRecovery)

        let before = tree(under: root)
        let found = StoreBackupManager.unmanagedStoreDirectories(
            liveStoreDirectoryURL: live,
            recoveryStoreDirectories: [liveRecovery, absentRecovery],
            legacyStoreDirectories: [absentLegacy]
        )
        let after = tree(under: root)

        #expect(found.count == 1, "the fixture stopped being the fixture: \(found.map(\.url.path))")
        #expect(before == after, "listing the store folders changed the tree")
        for absent in [absentRecovery, absentLegacy, root.appendingPathComponent("Nowhere")] {
            #expect(
                !FileManager.default.fileExists(atPath: absent.path),
                "\(absent.lastPathComponent) was created by being asked about"
            )
        }
    }

    // MARK: - The recovery store follows the store this launch opens

    /// **The [[T-1448]] property, for the one store path that never had it — in both directions.**
    ///
    /// `PersistenceController.recoveryStoreDirectoryURL()` built its first candidate from
    /// `CadenceStoreSupport.primaryStoreDirectoryURL()` whatever `CADENCE_UI_TEST_STORE_ID` said,
    /// and it *creates* the directory it returns. A `CadenceTests` host or an agent launch through
    /// `scripts/run-macos-app.sh` whose preflight failed would therefore have created a `Recovery/`
    /// folder — and opened a store in it — inside the signed-in person's app-group container.
    ///
    /// The unset half is the half that matters for the shipping app and is asserted against
    /// `CadenceStoreSupport` rather than a literal path, so it stays true on a machine whose
    /// container is somewhere else. A test that checked only the redirected half would pass over a
    /// resolver that had stopped answering the production path at all.
    @Test func theRecoveryStoreFollowsTheStoreTheLaunchActuallyOpens() throws {
        let temporaryDirectory = makeRoot()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let production = try CadenceStoreSupport.primaryStoreDirectoryURL()
            .appendingPathComponent("Recovery", isDirectory: true)
            .standardizedFileURL.path

        // Unset: the shipping app, and the app-group path exactly.
        let unset = PersistenceController.recoveryStoreDirectoryCandidates(
            in: [:],
            temporaryDirectory: temporaryDirectory
        )
        #expect(
            unset.first?.standardizedFileURL.path == production,
            "an environment naming nothing resolved \(unset.first?.path ?? "nil") instead of the app-group Recovery folder"
        )

        // Redirected: the launch's own private store, and the production path nowhere in the list.
        let redirected = PersistenceController.recoveryStoreDirectoryCandidates(
            in: ["CADENCE_UI_TEST_STORE_ID": "t1680"],
            temporaryDirectory: temporaryDirectory
        )
        let expected = CadenceUITestStoreDirectory
            .rootDirectory(in: temporaryDirectory)
            .appendingPathComponent("t1680", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
        #expect(
            redirected.first?.standardizedFileURL.path == expected.standardizedFileURL.path,
            "a redirected launch resolved \(redirected.first?.path ?? "nil") instead of its private Recovery folder"
        )
        #expect(
            !redirected.map(\.standardizedFileURL.path).contains(production),
            "a redirected launch can still create a recovery store in the app-group container"
        )
        #expect(
            unset.first?.standardizedFileURL.path != redirected.first?.standardizedFileURL.path,
            "the redirect makes no difference, so it is not a redirect"
        )

        // Resolving is not creating: neither answer may exist merely because it was asked for.
        #expect(!FileManager.default.fileExists(atPath: expected.path), "asking created the private Recovery folder")
    }

    // MARK: - The screen says so, and offers no way to delete them

    /// **Data Safety lists them, read-only, and the reset copy says they survive it.**
    ///
    /// Asserted against the source because the rendered list is not observable from here — an
    /// agent-launched macOS window is not screen-capturable — and because this is a claim about
    /// what the file *may contain*, which a screenshot could not settle anyway. The row type is
    /// where the rule is enforced: `directory` and `onReveal` and nothing else, so a delete cannot
    /// be handed to a path the app does not own.
    @Test func dataSafetyListsTheStoreFoldersAndOffersNoWayToDeleteThem() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        #expect(source.contains("struct SettingsDataSafetySection: View {"), "the file did not read as itself")
        #expect(
            source.contains("StoreBackupManager.unmanagedStoreDirectories()"),
            "Data Safety is back to naming no store folder but the live one"
        )
        #expect(
            source.contains("UnmanagedStoreDirectoryRow("),
            "nothing on the screen renders the store folders Cadence is not using"
        )

        let row = try #require(
            CadenceSourceScan.declarationBody("private struct UnmanagedStoreDirectoryRow: View", in: source),
            "UnmanagedStoreDirectoryRow did not read as itself"
        )
        #expect(row.contains("let onReveal: () -> Void"), "the row lost its one action")
        for forbidden in [
            "deleteAllBackups",
            "cleanUpAutomaticBackups",
            "deleteRetainedUnrestoredOriginals",
            "removeItem",
            "scheduleRestore",
            "role: .destructive",
            "Theme.red",
        ] {
            #expect(
                !row.contains(forbidden),
                "the store-folder row reaches \(forbidden) — the only copy of what a degraded session recorded"
            )
        }
        // "Where" is the half of the question this screen was silently answering wrong, and none
        // of these paths is guessable.
        #expect(row.contains("directory.url.path"), "the row does not show the folder's path")
    }

    /// **The reset enumerates what it takes, so it has to name what it leaves.**
    ///
    /// The card and the typed-phrase gate both list what is about to be deleted, item by item, and
    /// a list that specific reads as exhaustive. It is not: `deleteCadenceDataAndLocalArtifacts`
    /// resolves the live store directory only, so a `Recovery/` folder *inside* that very
    /// directory survives the press. Until [[T-1840]] decides whether it should, saying so is the
    /// whole of the honesty.
    @Test func theResetCopyNamesTheStoreFoldersItDoesNotDelete() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")

        let card = try #require(
            CadenceSourceScan.declarationBody("private struct SettingsDataResetCard: View", in: source),
            "SettingsDataResetCard did not read as itself"
        )
        #expect(
            card.contains("Store folders Cadence is not using are left alone"),
            "the reset card still lists five things it deletes and nothing it does not"
        )

        let sheet = try #require(
            CadenceSourceScan.declarationBody("private struct SettingsDataResetConfirmationSheet: View", in: source),
            "SettingsDataResetConfirmationSheet did not read as itself"
        )
        #expect(
            sheet.contains("recovery store"),
            "the last gate before an irreversible delete does not mention the store folder it leaves behind"
        )
        #expect(
            sheet.contains("Other Cadence Data Folders"),
            "the gate does not say where to find the folders it is leaving"
        )
    }
}
