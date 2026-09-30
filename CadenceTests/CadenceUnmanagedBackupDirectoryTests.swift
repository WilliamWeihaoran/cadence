import Foundation
import Testing
@testable import Cadence

/// **T-1532 — the backups Settings → Data Safety answered for and could not see.**
///
/// `SettingsDataSafetySection` listed `StoreBackupManager.listBackups()`, which resolves the
/// **live** store directory, and that was the screen's whole answer to "what copies of my data
/// does Cadence keep, and where". On the owner's Mac on 2026-09-29 that answered for 145 MB out of
/// 231 MB across four `Cadence Store Backups` directories; the other three sat beside store
/// locations the app had moved on from, reachable by nothing —
/// `CadenceStoreSupport.legacyStoreCandidateDirectories()` names the old *store* directories, so
/// the migration never touched a backups folder beside them and never will.
///
/// Two things are asserted here and they are different claims. The first is that the enumeration
/// **finds** them, including the one the ticket's own scoped listing missed. The second is that it
/// **cannot touch them**: these are paths the app no longer owns, one of them holding the only
/// copies of pre-app-group state on that machine, so a "Clear backups" control that reached one
/// would be a worse failure than the silence it replaces.
@MainActor
struct CadenceUnmanagedBackupDirectoryTests {

    // MARK: - Fixture

    /// A store directory with `names` planted in its `Cadence Store Backups` folder.
    private func plantBackups(_ names: [String], besideStoreAt storeDirectoryURL: URL) throws {
        let root = storeDirectoryURL.appendingPathComponent("Cadence Store Backups", isDirectory: true)
        for name in names {
            let backupURL = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: backupURL, withIntermediateDirectories: true)
            try Data(repeating: 0x2A, count: 4096)
                .write(to: backupURL.appendingPathComponent("default.store"))
        }
    }

    /// Every path under `url`, sorted — the reading that says whether a "read-only" walk was.
    private func tree(under url: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: url.path) else { return [] }
        return enumerator.compactMap { $0 as? String }.sorted()
    }

    // MARK: - It finds them

    /// The whole defect, reproduced against a tree shaped like the real one and then not
    /// reproduced.
    ///
    /// The layout is the machine's: the live store in its own `Cadence/` subdirectory, one orphan
    /// in the app-group root from before the store moved down a level, and — the case the ticket
    /// counted as absent — an orphan *inside* a legacy store directory as well as beside it.
    @Test func everyBackupsFolderBesideAStoreCadenceHasUsedIsFound() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1532-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let groupSupport = root
            .appendingPathComponent("Group Containers/group.com.haoranwei.Cadence/Library/Application Support", isDirectory: true)
        let live = groupSupport.appendingPathComponent("Cadence", isDirectory: true)
        let containerSupport = root
            .appendingPathComponent("Containers/com.haoranwei.Cadence/Data/Library/Application Support", isDirectory: true)
        let legacy = containerSupport.appendingPathComponent("Cadence", isDirectory: true)
        let unsandboxedLegacy = root
            .appendingPathComponent("Library/Application Support/Cadence", isDirectory: true)

        try plantBackups(["20260928-151149-startup", "20260927-213639-startup"], besideStoreAt: live)
        try plantBackups(["20260511-105736-startup"], besideStoreAt: groupSupport)
        try plantBackups(["20260527-145017-startup", "20260528-150916-pre-restore"], besideStoreAt: legacy)
        try plantBackups(
            ["20260430-163958-manual-after-active-task-restore", "20260527-144945-startup"],
            besideStoreAt: containerSupport
        )
        // A legacy location this machine never had: it must not be reported, and — see the
        // read-only test below — must not be created either.
        #expect(!FileManager.default.fileExists(atPath: unsandboxedLegacy.path))

        let found = StoreBackupManager.unmanagedBackupDirectories(
            liveStoreDirectoryURL: live,
            legacyStoreDirectories: [legacy, unsandboxedLegacy]
        )

        let paths = found.map(\.url.standardizedFileURL.path)
        #expect(
            Set(paths) == Set([
                groupSupport.appendingPathComponent("Cadence Store Backups", isDirectory: true),
                legacy.appendingPathComponent("Cadence Store Backups", isDirectory: true),
                containerSupport.appendingPathComponent("Cadence Store Backups", isDirectory: true),
            ].map(\.standardizedFileURL.path)),
            "the unmanaged folders came back as \(paths)"
        )
        #expect(
            !paths.contains(live.appendingPathComponent("Cadence Store Backups", isDirectory: true).standardizedFileURL.path),
            "the live directory is reported as one the app does not manage"
        )

        // Counted, so a row can say how much is in there rather than only that something is.
        let byPath = Dictionary(uniqueKeysWithValues: found.map { ($0.url.standardizedFileURL.path, $0) })
        #expect(byPath[groupSupport.appendingPathComponent("Cadence Store Backups").standardizedFileURL.path]?.backupCount == 1)
        #expect(byPath[legacy.appendingPathComponent("Cadence Store Backups").standardizedFileURL.path]?.backupCount == 2)
        #expect(byPath[containerSupport.appendingPathComponent("Cadence Store Backups").standardizedFileURL.path]?.backupCount == 2)
        #expect(found.allSatisfy { $0.sizeBytes > 0 }, "a folder of 4 KiB backups was sized at zero")
    }

    /// A `Cadence Store Backups` folder that exists and holds nothing is not a row. It is the
    /// ordinary residue of a `deleteAllBackups` on a directory that has since been abandoned, and
    /// a row for it would be this screen reporting a discovery it has not made.
    @Test func anEmptyLeftoverFolderIsNotReported() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1532-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let live = support.appendingPathComponent("Cadence", isDirectory: true)
        try FileManager.default.createDirectory(
            at: support.appendingPathComponent("Cadence Store Backups", isDirectory: true),
            withIntermediateDirectories: true
        )
        try plantBackups(["20260928-151149-startup"], besideStoreAt: live)

        #expect(
            StoreBackupManager.unmanagedBackupDirectories(
                liveStoreDirectoryURL: live,
                legacyStoreDirectories: []
            ).isEmpty,
            "an empty leftover folder earned a row"
        )
    }

    /// **The parent rule, against the real paths.**
    ///
    /// Machine-independent on purpose: it asserts the *shape* of the candidate set rather than
    /// what happens to be on this Mac. Two of the four directories found on 2026-09-29 sit
    /// directly under `Application Support`, from before the store moved into its own `Cadence/`
    /// folder, so a candidate set built only from `legacyStoreCandidateDirectories()` — which is
    /// what the ticket described — misses them.
    /// **[[T-1850]] made "the real paths" a set of readings rather than this Mac's.** The live
    /// directory used to be one `try CadenceStoreSupport.primaryStoreDirectoryURL()`, and that
    /// throws on a hosted runner, where `.github/ci.entitlements` grants only `get-task-allow`
    /// because there is no provisioning profile to carry an app group. The shape asserted below
    /// never needed the owner's container — it needs *an* app-group store directory — so it is
    /// driven over every floor whose app group resolves, which is at least the injected stand-in on
    /// every host and this Mac's real one here.
    @Test func theCandidatesIncludeEachStoreDirectoryAndItsParent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1850-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = CadenceStoreSupport.legacyStoreCandidateDirectories()
        #expect(!legacy.isEmpty, "there are no legacy store candidates, so this test is about nothing")

        let floors = CadenceAppGroupFloor.resolvable(in: root)
        #expect(!floors.isEmpty, "no floor resolved an app-group store, so this test is about nothing")

        for floor in floors {
            let live = try #require(floor.reference.url)
            let candidates = Set(
                StoreBackupManager
                    .backupDirectoryCandidates(liveStoreDirectoryURL: live, legacyStoreDirectories: legacy)
                    .map(\.standardizedFileURL.path)
            )

            for storeDirectoryURL in [live] + legacy {
                let own = storeDirectoryURL
                    .appendingPathComponent("Cadence Store Backups", isDirectory: true)
                let besideIt = storeDirectoryURL.deletingLastPathComponent()
                    .appendingPathComponent("Cadence Store Backups", isDirectory: true)
                #expect(
                    candidates.contains(own.standardizedFileURL.path),
                    "[\(floor.name)] no candidate inside \(storeDirectoryURL.path)"
                )
                #expect(
                    candidates.contains(besideIt.standardizedFileURL.path),
                    "[\(floor.name)] no candidate beside \(storeDirectoryURL.path) — the layout before the store moved into Cadence/"
                )
            }

            // The app-group root is the one the live store's parent rule is *for*, so name it.
            #expect(
                candidates.contains(
                    live.deletingLastPathComponent()
                        .appendingPathComponent("Cadence Store Backups", isDirectory: true)
                        .standardizedFileURL.path
                ),
                "[\(floor.name)] the app-group root, where 3 backups and 14 MB were on 2026-09-29, is not a candidate"
            )
        }
    }

    // MARK: - It cannot touch them

    /// **The safety property, read off the filesystem rather than off the call sites.**
    ///
    /// Every other resolver on `StoreBackupManager` creates the directory it resolves — that is
    /// what `storeDirectoryURL(in:)` does, deliberately. This one walks paths the app does not own,
    /// so it must create nothing, and "must" is asserted by listing the tree either side of the
    /// call rather than by reading the body.
    @Test func enumeratingTheUnmanagedFoldersWritesNothingAnywhere() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT1532-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let support = root.appendingPathComponent("Library/Application Support", isDirectory: true)
        let live = support.appendingPathComponent("Cadence", isDirectory: true)
        // A legacy directory that does not exist at all: the whole branch below it, folder and
        // parent, has to still be absent afterwards.
        let absentLegacy = root.appendingPathComponent("Nowhere/Cadence", isDirectory: true)
        try plantBackups(["20260928-151149-startup"], besideStoreAt: live)
        try plantBackups(["20260511-105736-startup"], besideStoreAt: support)

        let before = tree(under: root)
        let found = StoreBackupManager.unmanagedBackupDirectories(
            liveStoreDirectoryURL: live,
            legacyStoreDirectories: [absentLegacy]
        )
        let after = tree(under: root)

        #expect(found.count == 1, "the fixture stopped being the fixture: \(found.map(\.url.path))")
        #expect(before == after, "listing the unmanaged folders changed the tree")
        #expect(
            !FileManager.default.fileExists(atPath: absentLegacy.path),
            "a candidate that does not exist was created by being asked about"
        )
        #expect(
            !FileManager.default.fileExists(atPath: root.appendingPathComponent("Nowhere").path),
            "the parent of an absent candidate was created by being asked about"
        )
    }

    /// **The screen lists them and offers no way to delete them.**
    ///
    /// Asserted against the source because the rendered list is not observable from here — an
    /// agent-launched macOS window is not screen-capturable — and because this is a claim about
    /// what the file *may contain*, which a screenshot could not settle anyway. The row type is
    /// where the rule is enforced: a view that takes only `onReveal` cannot grow a delete by
    /// accident the way a shared row with an optional action can.
    @Test func dataSafetyListsTheUnmanagedFoldersAndOffersNoWayToDeleteThem() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        #expect(source.contains("struct SettingsDataSafetySection: View {"), "the file did not read as itself")
        #expect(
            source.contains("StoreBackupManager.unmanagedBackupDirectories()"),
            "Data Safety is back to answering for the live directory only"
        )
        #expect(
            source.contains("UnmanagedBackupDirectoryRow("),
            "nothing on the screen renders the unmanaged folders"
        )

        let row = try #require(
            CadenceSourceScan.declarationBody("private struct UnmanagedBackupDirectoryRow: View", in: source),
            "UnmanagedBackupDirectoryRow did not read as itself"
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
                "the unmanaged-folder row reaches \(forbidden) — a path the app does not own"
            )
        }

        // And the path itself has to be on screen: "where" is the half of the question the screen
        // was silently answering wrong, and a row that says only "3 backups, 14 MB" repeats it.
        #expect(row.contains("directory.url.path"), "the row does not show the folder's path")

        // Nothing anywhere on this screen may remove a file directly. The live backups are cleared
        // through `StoreBackupManager`/`PrivacyDataResetService`, which know which directory they
        // are allowed to act on; a bare `removeItem` here would not.
        #expect(
            CadenceSourceScan.matchCount("removeItem", in: source) == 0,
            "Settings → Data Safety removes a file by hand"
        )
    }
}
