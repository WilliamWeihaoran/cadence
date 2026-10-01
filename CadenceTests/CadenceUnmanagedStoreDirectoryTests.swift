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

    // MARK: - Asking where the store is does not make one ([[T-1852]])

    /// **The question itself was a write, and this is the filesystem reading that says it is not.**
    ///
    /// `CadenceStoreSupport.primaryStoreDirectoryURL` ends in a `createDirectory`, and until
    /// [[T-1852]] it was the only way to ask where the app-group store is — so every read-only
    /// caller created the directory as a side effect of wondering about it. The two spellings are
    /// driven here against the **same** injected container, one after the other, so the difference
    /// is the function and not the fixture: the non-creating form leaves the container absent, and
    /// the creating form then makes it. A control, and not one reading taken alone: a test that only
    /// checked "the location did not create" would pass just as well against a container the stub
    /// could never have created at all.
    @Test func askingWhereTheStoreIsCreatesNothingAndAskingForItStillDoes() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // A container path under this test's own root, deliberately **not** created. Never the real
        // group container: the whole hazard being pinned is a resolver that makes a directory
        // inside it.
        let container = root.appendingPathComponent("GroupContainer", isDirectory: true)
        let stub = CadenceAppGroupContainerStub(container: container)
        #expect(!FileManager.default.fileExists(atPath: container.path), "the fixture started dirty")

        let located = try CadenceStoreSupport.storeDirectoryLocation(fileManager: stub)
        #expect(
            located.standardizedFileURL.path
                == container
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
                    .appendingPathComponent(CadenceStoreSupport.storeDirectoryName, isDirectory: true)
                    .standardizedFileURL.path,
            "the non-creating form composed \(located.path), which is not the app-group layout"
        )
        #expect(
            tree(under: root).isEmpty,
            "asking where the store is wrote \(tree(under: root))"
        )

        // The control: the creating form answers the *same* path and does make it.
        let created = try CadenceStoreSupport.primaryStoreDirectoryURL(fileManager: stub)
        #expect(created.standardizedFileURL == located.standardizedFileURL, "the two forms disagree about the path")
        #expect(
            FileManager.default.fileExists(atPath: created.path),
            "the creating form stopped creating, so the test above is about nothing"
        )
    }

    /// The three read-only resolvers that asked it. Same control, one level up.
    ///
    /// Each of these is a *listing* — the store folders Data Safety shows, the backup folders it
    /// shows beside them, and the terminal recovery screen's candidate search ([[T-1842]]) — and
    /// each used to create the signed-in person's store directory on its way to answering. They are
    /// driven here with an injected container that does not exist, and the assertion is the one the
    /// safety rule is written in: the tree under this test's own root is unchanged.
    @Test func theReadOnlyResolversNoLongerCreateTheStoreDirectoryTheyAskAbout() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let container = root.appendingPathComponent("GroupContainer", isDirectory: true)
        let stub = CadenceAppGroupContainerStub(container: container)
        let storeDirectory = try CadenceStoreSupport.storeDirectoryLocation(fileManager: stub)

        // Three resolutions, all unredirected — the half that reaches the app-group container, and
        // therefore the half that could write into it.
        let recovery = PersistenceController.recoveryStoreDirectoryCandidates(
            in: [:],
            temporaryDirectory: root.appendingPathComponent("Temporary", isDirectory: true),
            fileManager: stub
        )
        let backups = try StoreBackupManager.storeDirectoryLocation(
            in: [:],
            temporaryDirectory: root.appendingPathComponent("Temporary", isDirectory: true),
            fileManager: stub
        )
        let exportCandidates = PersistenceController.recoveryExportCandidateStoreURLs(
            in: [:],
            temporaryDirectory: root.appendingPathComponent("Temporary", isDirectory: true),
            fileManager: stub
        )

        // Non-vacuity first: each one really did resolve *through* the injected container, so the
        // "nothing was written" reading below is about these calls and not about three refusals.
        #expect(
            recovery.first?.standardizedFileURL.path
                == storeDirectory.appendingPathComponent("Recovery", isDirectory: true).standardizedFileURL.path,
            "the recovery candidates resolved \(recovery.first?.path ?? "nil")"
        )
        #expect(backups.standardizedFileURL == storeDirectory.standardizedFileURL)
        #expect(
            exportCandidates.first?.standardizedFileURL.path
                == storeDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename).standardizedFileURL.path,
            "the export candidates resolved \(exportCandidates.first?.path ?? "nil")"
        )

        #expect(
            tree(under: root).isEmpty,
            "a read-only resolver wrote into the container it was only asked about: \(tree(under: root))"
        )
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

        // **[[T-1850]]: driven on all three app-group floors instead of on this Mac's.** The first
        // line of this test used to be `try CadenceStoreSupport.primaryStoreDirectoryURL()`, which
        // *throws* on a hosted runner — no provisioning profile, so `.github/ci.entitlements`
        // carries no app group — and took every assertion below down with it the first time CI ran
        // this suite. The candidate list is built from `CadenceStoreSupport`, so what has to be
        // asserted is that it *agrees* with it: the app-group Recovery folder where there is an app
        // group, and the documented `Application Support` fallback where there is none. Both are
        // exact; neither is skipped.
        let expected = CadenceUITestStoreDirectory
            .rootDirectory(in: temporaryDirectory)
            .appendingPathComponent("t1680", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)

        for floor in CadenceAppGroupFloor.all(in: temporaryDirectory) {
            // Unset: the shipping app, and the app-group path exactly.
            let unset = PersistenceController.recoveryStoreDirectoryCandidates(
                in: [:],
                temporaryDirectory: temporaryDirectory,
                fileManager: floor.fileManager
            )
            let firstUnset = unset.first?.standardizedFileURL.path
            // **[[T-1852]] changed which reference this owes agreement to, and that is the point of
            // the ticket rather than an accommodation to it.** The candidate base was
            // `primaryStoreDirectoryURL`, which *creates*, so on a container that is named and
            // cannot be written — CI's floor exactly — this fell into the `.refused` branch below
            // and could only assert the `Application Support` fallback. The base is now
            // `storeDirectoryLocation`, which composes and creates nothing, so that floor resolves
            // and the **exact app-group Recovery path** is asserted there too. The `.refused` branch
            // survives for the one floor that still takes it: no container at all, nothing to name.
            switch floor.locationReference {
            case .directory:
                #expect(
                    firstUnset == floor.locationReference.appending("Recovery").url?.standardizedFileURL.path,
                    "[\(floor.name)] an environment naming nothing resolved \(firstUnset ?? "nil") instead of the app-group Recovery folder"
                )
            case .refused:
                // No reachable app group. The resolver must fall through to the *second* candidate
                // `CadenceStoreSupport` defines — `Application Support/Cadence/Recovery` — and not
                // to something it invented. Asserted against the same `FileManager` the resolver
                // asked, so this is still a relation and not a literal path.
                let applicationSupport = try #require(
                    floor.fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                )
                #expect(
                    firstUnset == applicationSupport
                        .appendingPathComponent("Cadence", isDirectory: true)
                        .appendingPathComponent("Recovery", isDirectory: true)
                        .standardizedFileURL.path,
                    "[\(floor.name)] with no app group the recovery store resolved \(firstUnset ?? "nil") instead of the Application Support fallback"
                )
            }

            // Redirected: the launch's own private store, and the production path nowhere in the list.
            let redirected = PersistenceController.recoveryStoreDirectoryCandidates(
                in: ["CADENCE_UI_TEST_STORE_ID": "t1680"],
                temporaryDirectory: temporaryDirectory,
                fileManager: floor.fileManager
            )
            #expect(
                redirected.first?.standardizedFileURL.path == expected.standardizedFileURL.path,
                "[\(floor.name)] a redirected launch resolved \(redirected.first?.path ?? "nil") instead of its private Recovery folder"
            )
            let appGroupRecovery = floor.locationReference.appending("Recovery")
            #expect(
                !redirected.contains {
                    CadenceAppGroupStoreOutcome.directory($0.standardizedFileURL.path) == appGroupRecovery
                },
                "[\(floor.name)] a redirected launch can still create a recovery store in the app-group container"
            )
            #expect(
                firstUnset != redirected.first?.standardizedFileURL.path,
                "[\(floor.name)] the redirect makes no difference, so it is not a redirect"
            )
        }

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
            card.contains("CadenceUnmanagedStoreCopy.resetLeavesThem"),
            "the reset card still lists five things it deletes and nothing it does not"
        )

        let sheet = try #require(
            CadenceSourceScan.declarationBody("private struct SettingsDataResetConfirmationSheet: View", in: source),
            "SettingsDataResetConfirmationSheet did not read as itself"
        )
        #expect(
            sheet.contains("CadenceUnmanagedStoreCopy.resetGateLeavesThem"),
            "the last gate before an irreversible delete does not mention the store folder it leaves behind"
        )
        // ...and the two claims the shared sentence is carrying on its behalf. Asserting only
        // that the view names the constant would pass over a constant emptied of its meaning,
        // which is this repository's recurring hollow-instrument shape.
        #expect(
            CadenceUnmanagedStoreCopy.resetGateLeavesThem.contains("recovery store"),
            "the shared gate sentence no longer names the folder it is leaving behind"
        )
        #expect(
            CadenceUnmanagedStoreCopy.resetGateLeavesThem.contains(CadenceUnmanagedStoreCopy.sectionTitle),
            "the gate does not say where to find the folders it is leaving"
        )
    }

    // MARK: - T-1841: the phone says the same thing, and now has a screen to say it on

    /// **iOS said what the reset takes and stopped, and had nowhere to point.**
    ///
    /// [[T-1841]]. [[T-1680]] taught both macOS sentences to end by naming what the reset leaves
    /// behind and pointing at the section that lists it; `iOSDataResetSettingsSection` still
    /// enumerated five things and stopped, at the card and again inside the typed-phrase gate.
    /// A list that specific reads as exhaustive on a phone exactly as it does on a Mac, and the
    /// gate is the last thing read before an irreversible button.
    ///
    /// The claim is pinned as a RELATION rather than as two string literals: **both platforms
    /// reach the same declaration**, so the way these drift apart — [[T-1782]]'s shape, two
    /// platforms and two different "what is in here" sentences — is not available. The section
    /// title in particular is named in four places (two section labels, two reset gates) and is
    /// now spelled once.
    @Test func bothPlatformsTellTheSameStoryAboutWhatTheResetLeaves() throws {
        let iOSReset = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSDataResetSettingsSection.swift")
        #expect(iOSReset.contains("struct iOSDataResetSettingsSection: View {"), "the file did not read as itself")
        #expect(
            iOSReset.contains("CadenceUnmanagedStoreCopy.resetLeavesThem"),
            "the iOS reset card still lists five things it deletes and nothing it does not (T-1841)"
        )
        #expect(
            iOSReset.contains("CadenceUnmanagedStoreCopy.resetGateLeavesThem"),
            "the iOS typed-phrase gate does not name the store folders it leaves behind (T-1841)"
        )

        // The shared sentences are not empty of the claims the two views are delegating to them.
        #expect(CadenceUnmanagedStoreCopy.resetLeavesThem.contains("left alone"))
        #expect(CadenceUnmanagedStoreCopy.whatCadenceDoesNotDo.contains("deleting all Cadence data does not delete them"))
        #expect(CadenceUnmanagedStoreCopy.whatTheyAre.contains("recovery store"))

        // One spelling of the section name. It is named in four places — two section labels and
        // two reset gates — and a view that writes it as a literal is how a renamed section leaves
        // a reset pointing at a section that no longer exists.
        //
        // The three view files are named rather than swept. A `CadenceSourceScan.swiftFiles(under:)`
        // walk would be a stronger claim and would also make this a real-tree sweep, which is a
        // manifest entry (T-808) and not this ticket's to add; these are the only files that
        // render or point at the section, and a fourth would have to come from the same change
        // that moved one of them.
        var offenders: [String] = []
        for relativePath in [
            "Cadence/iOS/iOSUnmanagedStoreSettingsSection.swift",
            "Cadence/iOS/iOSDataResetSettingsSection.swift",
            "Cadence/macOS/Views/SettingsDataSafetySection.swift",
        ] {
            let source = try CadenceSourceScan.sourceFile(relativePath)
            if source.contains("\"\(CadenceUnmanagedStoreCopy.sectionTitle)\"") { offenders.append(relativePath) }
        }
        #expect(
            offenders.isEmpty,
            """
            `\(CadenceUnmanagedStoreCopy.sectionTitle)` is spelled as a literal in \
            \(offenders.joined(separator: ", ")) rather than read from the shared copy, so the \
            two platforms can come to point at different section names (T-1841)
            """
        )
        // The control: the string really is declared somewhere, so the emptiness above is the
        // views deferring rather than the name having been deleted.
        let shared = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceSettingsSectionCopy.swift")
        #expect(
            shared.contains("\"\(CadenceUnmanagedStoreCopy.sectionTitle)\""),
            "the section name is not a literal anywhere, including where it is supposed to be"
        )
    }

    /// **The phone now has the screen, and its row carries no action — which is the macOS rule in
    /// its stronger form, not a weaker port of it.**
    ///
    /// macOS's `UnmanagedStoreDirectoryRow` takes `directory` and `onReveal` and nothing else, so
    /// a delete cannot be handed to a path the app does not own. The **Reveal** half does not
    /// survive the crossing: `Cadence/Info.plist` declares neither `UIFileSharingEnabled` nor
    /// `LSSupportsOpeningDocumentsInPlace`, so there is no Files route into Cadence's container
    /// for a reveal to open, and no `NSWorkspace` to open it with. The iOS row therefore takes
    /// `directory` alone. Asserting that is asserting the rule at its binding site: a row that
    /// cannot be handed an action cannot grow a destructive one.
    @Test func theiPhoneHasAScreenToListTheStoreFoldersOnAndItsRowCarriesNoAction() throws {
        let section = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSUnmanagedStoreSettingsSection.swift")
        #expect(
            section.contains("StoreBackupManager.unmanagedStoreDirectories()"),
            "the iOS section names no store folder, so it is a section about nothing (T-1841)"
        )
        #expect(
            section.contains("CadenceSettingsSectionLabel(text: CadenceUnmanagedStoreCopy.sectionTitle)"),
            "the iOS section does not carry the section name the reset points at (T-1841)"
        )

        let row = try #require(
            CadenceSourceScan.declarationBody("private struct iOSUnmanagedStoreDirectoryRow: View", in: section),
            "iOSUnmanagedStoreDirectoryRow did not read as itself"
        )
        #expect(row.contains("directory.url.path"), "the row does not show the folder's path")
        #expect(row.contains("directory.displayDetail"), "the row does not say what kind of folder it is")
        for forbidden in [
            "onReveal",
            "deleteAllBackups",
            "cleanUpAutomaticBackups",
            "deleteRetainedUnrestoredOriginals",
            "removeItem",
            "scheduleRestore",
            "role: .destructive",
            "Theme.red",
            "Button",
        ] {
            #expect(
                !row.contains(forbidden),
                "the iOS store-folder row reaches \(forbidden); it is supposed to carry no action at all (T-1841)"
            )
        }
        // The reveal that is absent is absent because the platform cannot support it, and that is
        // a property of the shipped plist rather than of this view's taste.
        let plist = try CadenceSourceScan.sourceFile("Cadence/Info.plist")
        for key in ["UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace"] {
            #expect(
                !plist.contains(key),
                """
                Cadence/Info.plist now declares \(key), so there IS a Files route into the \
                container and the iOS row's missing reveal is worth revisiting (T-1841)
                """
            )
        }

        // ...and it is actually on the page, below the reset, because the reset's own sentence
        // says these are "listed further down this page".
        let settings = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsView.swift")
        let dataSafety = try #require(
            CadenceSourceScan.declarationBody("private var dataSafetySection: some View", in: settings),
            "dataSafetySection did not read as itself"
        )
        let resetAt = try #require(
            dataSafety.range(of: "iOSDataResetSettingsSection()"),
            "the iOS Data Safety page no longer presents the reset at all"
        )
        let listAt = try #require(
            dataSafety.range(of: "iOSUnmanagedStoreSettingsSection()"),
            "the iOS Data Safety page does not list the store folders the reset says it leaves (T-1841)"
        )
        #expect(
            resetAt.lowerBound < listAt.lowerBound,
            """
            the store-folder list is ABOVE the reset, and the reset's own copy says they are \
            "listed further down this page" (T-1841)
            """
        )
    }

    /// **There is no "Other Backup Folders" section on iOS, and that is a measurement rather than
    /// an omission.**
    ///
    /// [[T-1841]] asks for both of macOS's lists. The store list is real on a phone — a
    /// `Recovery/` folder inside the app-group store directory is exactly as reachable here as on
    /// a Mac. The *backup* list is not, and the reason is structural rather than circumstantial:
    /// `StoreBackupManager` only ever writes into the **live** store directory's own
    /// `Cadence Store Backups`, and `unmanagedBackupDirectories` excludes precisely that root by
    /// construction. Its remaining candidates are the legacy store locations, and on iOS
    /// `CadenceStoreSupport.legacyStoreCandidateDirectories()` resolves them under the app's own
    /// sandbox — `Library/Containers/…` cannot exist on this platform, and no iOS build has ever
    /// kept a store outside the app group. So the section could hold a row only if iOS had once
    /// used a second store directory, and it has not. A permanently empty section is a claim a
    /// screen cannot keep, so none was added.
    ///
    /// The fixture is the iOS shape: backups beside the live store and nowhere else. The CONTROL
    /// is the second half and is what keeps this from being a test that passes because the
    /// fixture is empty — the identical call, over the identical tree, with one *second* store
    /// directory handed in, finds it. Empty is therefore a property of where the backups are, not
    /// of the walk failing to run.
    @Test func theOnlyBackupRootAnIPhoneWritesIsTheOneTheListExcludes() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // The app-group container as iOS lays it out, and the store directory inside it.
        let groupSupport = root
            .appendingPathComponent("Group Containers/group.com.haoranwei.Cadence/Library/Application Support", isDirectory: true)
        let live = groupSupport.appendingPathComponent("Cadence", isDirectory: true)
        try plantPrimaryStore(in: live)
        try plantBackupFolder(named: "2026-09-29 Automatic", besideStoreAt: live)
        try plantBackupFolder(named: "2026-09-30 Automatic", besideStoreAt: live)

        // The two legacy candidates an iOS launch would be handed: paths under the app's own
        // sandbox that no iOS build has ever written a store into. Deliberately NOT created.
        let sandbox = root.appendingPathComponent("Containers/Data/Application/UUID", isDirectory: true)
        let neverUsed = [
            sandbox.appendingPathComponent("Library/Containers/com.haoranwei.Cadence/Data/Library/Application Support/Cadence", isDirectory: true),
            sandbox.appendingPathComponent("Library/Application Support/Cadence", isDirectory: true),
        ]

        let listed = StoreBackupManager.unmanagedBackupDirectories(
            liveStoreDirectoryURL: live,
            legacyStoreDirectories: neverUsed
        )
        #expect(
            listed.isEmpty,
            """
            an iOS-shaped tree produced \(listed.count) unmanaged backup folder(s) \
            (\(listed.map(\.url.standardizedFileURL.path).joined(separator: ", "))); if that is now reachable on a \
            phone, iOS needs the Other Backup Folders section too (T-1841)
            """
        )

        // The control, and the reason the emptiness above means something. Same call, same tree,
        // plus one store directory Cadence is no longer using that has backups of its own.
        let secondStore = sandbox.appendingPathComponent("Library/Application Support/Cadence", isDirectory: true)
        try plantPrimaryStore(in: secondStore)
        try plantBackupFolder(named: "2026-05-21 Manual", besideStoreAt: secondStore)

        let withAnOrphan = StoreBackupManager.unmanagedBackupDirectories(
            liveStoreDirectoryURL: live,
            legacyStoreDirectories: neverUsed
        )
        #expect(
            withAnOrphan.map(\.url.standardizedFileURL.path)
                == [secondStore.appendingPathComponent("Cadence Store Backups", isDirectory: true).standardizedFileURL.path],
            """
            the walk did not find a backup folder beside a second store directory, so the empty \
            reading above is the walk failing rather than the layout: \
            \(withAnOrphan.map(\.url.standardizedFileURL.path))
            """
        )
        #expect(withAnOrphan.first?.backupCount == 1, "the control folder was found but not counted")

        // ...and the store list, over the very same tree, is NOT empty: a recovery folder inside
        // the live store directory is what a phone really can have, and it is why one of the two
        // sections was worth porting and the other was not.
        try plantRecoveryStore(in: live.appendingPathComponent("Recovery", isDirectory: true))
        let stores = StoreBackupManager.unmanagedStoreDirectories(
            liveStoreDirectoryURL: live,
            recoveryStoreDirectories: [live.appendingPathComponent("Recovery", isDirectory: true)],
            legacyStoreDirectories: neverUsed
        )
        #expect(
            stores.map(\.kind) == [.recovery, .previousLocation],
            "the store list over an iOS-shaped tree read \(stores.map(\.kind)) (T-1841)"
        )
    }

    /// `StoreBackupManager.listBackups` only reports a folder it recognises, so a fixture backup
    /// is a directory with a store item in it. Named apart from the store planters above because
    /// this plants *beside* a store rather than *as* one.
    private func plantBackupFolder(named name: String, besideStoreAt storeDirectoryURL: URL) throws {
        let backupURL = storeDirectoryURL
            .appendingPathComponent("Cadence Store Backups", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: 4096)
            .write(to: backupURL.appendingPathComponent("default.store"))
    }
}
