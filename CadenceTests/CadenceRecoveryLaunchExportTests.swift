import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-3102]] — what a user gets out of a launch that opened a recovery store.**
///
/// The defect was an asymmetry, not a crash. `PersistenceController.init` falls back to
/// `makeRecoveryContainer` when the CloudKit-backed store will not open, and from that moment the
/// app is running on an empty database beside the user's intact one. On iOS that was terminal:
/// `StoreBackupManager.scheduleRestore` has exactly one non-test caller in the tree and it is
/// `Cadence/macOS/Views/SettingsDataSafetySection.swift`, `Info.plist` carries neither
/// `UIFileSharingEnabled` nor `LSSupportsOpeningDocumentsInPlace` so there is no Files route into
/// the container, and `iOSUnmanagedStoreSettingsSection` lists the real store directory with no
/// action on the row at all. The one route off the device was Settings → Export — which read
/// `@Environment(\.modelContext)`, the container the app had *actually opened*, and therefore wrote
/// an archive of the recovery store. Nothing. Meanwhile `iOSDataResetSettingsSection` still reached
/// `PrivacyDataResetService.deleteCadenceDataAndLocalArtifacts`, which calls `deleteAllBackups()`.
///
/// So the destructive operation shipped on that platform and every recuperative one did not.
///
/// **What these tests assert is the user-visible end state, not a call graph**: given a real store
/// on disk holding the user's rows and an empty recovery store open on screen, pressing Export
/// produces a file with the user's rows in it. The discriminating half is the launch where nothing
/// is wrong — an implementation that simply always read the disk would strand every ordinary
/// export the moment a redirect or a second store entered the picture, and that case is driven
/// here too, over the same fixtures, with the store on screen deliberately holding *different*
/// rows from the one on disk.
///
/// **Isolation.** Every path in this file is inside the suite's own temporary root. `RecoveryExportFileManagerStub`
/// below stubs both halves of the resolution the search uses — the app-group container *and*
/// `.applicationSupportDirectory` — because `PersistenceController.recoveryStoreDirectoryCandidates`
/// reads the latter straight off the `FileManager` it is handed, and left real it names a
/// `Recovery/` directory inside the owner's own container. `everyCandidateStaysInsideThisTestsRoot`
/// is that claim asserted rather than assumed.
@MainActor
struct CadenceRecoveryLaunchExportTests {
    // MARK: - Fixtures

    /// Stubs *both* resolutions the recovery search makes, so nothing it tries can leave this
    /// suite's root.
    ///
    /// `CadenceAppGroupContainerStub` is `final` and covers the app group alone, which is not
    /// enough here: `PersistenceController.recoveryStoreDirectoryCandidates` reads
    /// `.applicationSupportDirectory` straight off the `FileManager` it is handed, and under the
    /// test host that resolves inside the owner's own container — so an unstubbed run of this
    /// suite would try to open a `Recovery/recovery.store` belonging to them.
    /// `everyCandidateStaysInsideThisTestsRoot` is that claim asserted rather than assumed.
    private final class RecoveryExportFileManagerStub: FileManager {
        private let container: URL
        private let applicationSupport: URL

        init(container: URL, applicationSupport: URL) {
            self.container = container
            self.applicationSupport = applicationSupport
            super.init()
        }

        override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
            guard groupIdentifier == CadenceStoreSupport.appGroupIdentifier else {
                return super.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
            }
            return container
        }

        override func urls(
            for directory: FileManager.SearchPathDirectory,
            in domainMask: FileManager.SearchPathDomainMask
        ) -> [URL] {
            guard directory == .applicationSupportDirectory else {
                return super.urls(for: directory, in: domainMask)
            }
            return [applicationSupport]
        }
    }

    private struct Fixture {
        let root: URL
        let fileManager: FileManager
        /// Where `CadenceStoreSupport` says this launch's store lives, on the stubbed floor.
        let storeDirectory: URL
        /// The empty recovery container the app has open — a real on-disk store, not in-memory,
        /// because that is what `makeRecoveryContainer` produces.
        let openedRecoveryContext: ModelContext

        var realStoreURL: URL {
            storeDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename)
        }
    }

    private func makeFixture(
        openedRecoveryStoreHolds sentinel: String?
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceT3102-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fileManager = RecoveryExportFileManagerStub(
            container: root.appendingPathComponent("GroupContainer", isDirectory: true),
            applicationSupport: root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        )
        let storeDirectory = try CadenceStoreSupport.storeDirectoryLocation(fileManager: fileManager)

        let openedRecoveryStoreURL = root
            .appendingPathComponent("OpenedRecoveryStore", isDirectory: true)
            .appendingPathComponent("recovery.store")
        try FileManager.default.createDirectory(
            at: openedRecoveryStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let openedRecoveryContainer = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: openedRecoveryStoreURL
        )
        let openedRecoveryContext = ModelContext(openedRecoveryContainer)
        if let sentinel {
            openedRecoveryContext.insert(AppTask(title: sentinel))
            try openedRecoveryContext.save()
        }

        return Fixture(
            root: root,
            fileManager: fileManager,
            storeDirectory: storeDirectory,
            openedRecoveryContext: openedRecoveryContext
        )
    }

    /// A real, on-disk, non-in-memory store — the shape `openReadOnlyStore(at:)` has to open.
    private func seedStore(at storeURL: URL, taskTitle: String) throws {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        let context = ModelContext(container)
        context.insert(AppTask(title: taskTitle))
        try context.save()
    }

    private func exportedTitles(_ export: PersistenceController.DataSafetyExport) throws -> [String] {
        try CadenceDataExportService.decode(export.outcome.data).tasks.map(\.title)
    }

    private func recoveryLaunch(_ message: String = "stubbed") -> CadenceStartupIssue {
        CadenceStartupIssue(kind: .recoveryStore, message: message)
    }

    private func export(
        _ fixture: Fixture,
        startupIssue: CadenceStartupIssue?
    ) throws -> PersistenceController.DataSafetyExport {
        try PersistenceController.exportArchiveForDataSafety(
            openedStoreContext: fixture.openedRecoveryContext,
            startupIssue: startupIssue,
            environment: [:],
            temporaryDirectory: fixture.root,
            fileManager: fixture.fileManager
        )
    }

    // MARK: - Isolation

    /// Standing rule, asserted rather than trusted: nothing the search tries is outside this
    /// suite's own root. Also the non-vacuity check for every test below — a candidate list that
    /// came back empty would satisfy a `allSatisfy` trivially, so the count is checked too.
    @Test func everyCandidateStaysInsideThisTestsRoot() throws {
        let fixture = try makeFixture(openedRecoveryStoreHolds: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let candidates = PersistenceController.recoveryExportCandidateStoreURLs(
            in: [:],
            temporaryDirectory: fixture.root,
            fileManager: fixture.fileManager
        )
        let prefix = fixture.root.standardizedFileURL.path + "/"

        #expect(candidates.count >= 4, "the candidate list is \(candidates.count) long and cannot be doing its job")
        for candidate in candidates {
            #expect(
                candidate.standardizedFileURL.path.hasPrefix(prefix),
                "the recovery search would read \(candidate.path), outside this test's root"
            )
        }
    }

    // MARK: - The defect

    /// **The ticket, at the level of bytes.** The user's rows are on disk; the app is running on an
    /// empty recovery store; Settings → Export produces a file holding the user's rows.
    ///
    /// The non-vacuity half is asserted in the same test and is what makes it the defect's own
    /// test rather than a restatement of `attemptRecoveryExport`'s: exporting the context the view
    /// would have handed over — the thing this code did until now — yields **zero** records out of
    /// the same fixture. One archive with the data, one without, same launch.
    @Test func aRecoveryLaunchExportsTheStoreOnDiskInsteadOfTheEmptyStoreOnScreen() throws {
        let fixture = try makeFixture(openedRecoveryStoreHolds: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try seedStore(at: fixture.realStoreURL, taskTitle: "Belongs to the user")

        // What the screen holds, and what the old behaviour would have written.
        let whatIsOnScreen = try CadenceDataExportService.exportArchive(in: fixture.openedRecoveryContext)
        #expect(whatIsOnScreen.recordCount == 0, "the fixture's recovery store is not empty")

        let archive = try export(fixture, startupIssue: recoveryLaunch())

        #expect(try exportedTitles(archive) == ["Belongs to the user"])
        #expect(archive.outcome.recordCount == 1)
        #expect(
            archive.source == .aStoreReadFromDisk(fixture.realStoreURL),
            "the archive came from \(archive.source)"
        )
        #expect(archive.precedingFailures.isEmpty)
    }

    /// `.inMemoryStore` is the same situation one failure deeper — the recovery store could not be
    /// made either — and it has to behave the same way, because the store on disk is just as
    /// unreachable from the context the view holds.
    @Test func anInMemoryLaunchAlsoExportsTheStoreOnDisk() throws {
        let fixture = try makeFixture(openedRecoveryStoreHolds: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try seedStore(at: fixture.realStoreURL, taskTitle: "Still on disk")

        let archive = try export(
            fixture,
            startupIssue: CadenceStartupIssue(kind: .inMemoryStore, message: "stubbed")
        )

        #expect(try exportedTitles(archive) == ["Still on disk"])
        #expect(archive.source == .aStoreReadFromDisk(fixture.realStoreURL))
    }

    // MARK: - The discriminating half: an ordinary launch is untouched

    /// **The reading that a "just always read the disk" fix would fail.** The store on screen and
    /// the store on disk hold *different* rows, and on every launch whose issue is not a store-level
    /// one the export must be the one on screen — which is the user's own store, open, syncing, and
    /// quite possibly holding edits made this session that the file on disk does not have yet.
    ///
    /// `.developmentBuild` is in this list deliberately and is the near-miss the whole property
    /// exists for: it disables CloudKit sync, so a fix written against `disablesCloudSync` passes
    /// every other test in this file and sends a developer's ordinary export looking on disk.
    @Test func anOrdinaryLaunchStillExportsTheStoreItOpened() throws {
        let untouchedKinds: [CadenceStartupIssueKind?] = [
            nil,
            .developmentBuild,
            .backupFailed,
            .restoreFailed,
            .restoreIncomplete,
            .maintenanceSaveFailed,
        ]

        for kind in untouchedKinds {
            let fixture = try makeFixture(openedRecoveryStoreHolds: "Open on screen")
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            try seedStore(at: fixture.realStoreURL, taskTitle: "On disk and stale")

            let archive = try export(
                fixture,
                startupIssue: kind.map { CadenceStartupIssue(kind: $0, message: "stubbed") }
            )

            let label = kind.map(\.rawValue) ?? "no issue"
            #expect(try exportedTitles(archive) == ["Open on screen"], "[\(label)] exported the wrong store")
            #expect(archive.source == .theStoreThisLaunchOpened, "[\(label)] source was \(archive.source)")
            #expect(archive.provenanceNote == nil, "[\(label)] an ordinary launch explained itself")
            #expect(archive.precedingFailures.isEmpty)
        }
    }

    /// The partition itself, stated once over `allCases` so a seventh kind added later cannot
    /// silently default into either half. `disablesCloudSync` is compared against rather than
    /// restated: the two properties must **not** be the same partition, and `.developmentBuild` is
    /// exactly where they part.
    @Test func onlyTheTwoStoreLevelKindsMeanTheOpenStoreIsNotTheUsersData() {
        #expect(
            CadenceStartupIssueKind.allCases.filter(\.theOpenStoreIsNotTheUsersData)
                == [.recoveryStore, .inMemoryStore]
        )
        #expect(!CadenceStartupIssueKind.developmentBuild.theOpenStoreIsNotTheUsersData)
        #expect(CadenceStartupIssueKind.developmentBuild.disablesCloudSync)
        #expect(
            CadenceStartupIssueKind.allCases.filter(\.theOpenStoreIsNotTheUsersData)
                != CadenceStartupIssueKind.allCases.filter(\.disablesCloudSync),
            "the two properties are the same partition, so one of them is not pulling its weight"
        )
    }

    // MARK: - When there is nothing on disk to find either

    /// A recovery launch with no readable store anywhere is still allowed to export — it returns
    /// exactly what the old code returned, so this can never hand a user *less* than before — and
    /// it has to say so, because a file holding nothing looks identical to a file holding
    /// everything until it is opened.
    @Test func aRecoveryLaunchWithNothingReadableOnDiskStillExportsAndSaysSo() throws {
        let fixture = try makeFixture(openedRecoveryStoreHolds: "Typed into the recovery store")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        // Deliberately no store seeded on disk at all.
        #expect(!FileManager.default.fileExists(atPath: fixture.realStoreURL.path))

        let archive = try export(fixture, startupIssue: recoveryLaunch())

        #expect(archive.source == .onlyTheRecoveryStoreThisLaunchOpened)
        #expect(try exportedTitles(archive) == ["Typed into the recovery store"])
        let note = try #require(archive.provenanceNote)
        #expect(note.contains("could not read your own store"))
        // The one sentence that keeps the incident from compounding: the reset on the same screen
        // reaches `deleteAllBackups()`, and this is the launch on which that is unrecoverable.
        #expect(note.contains("Do not delete Cadence's data"))
    }

    // MARK: - What the screen says

    /// The provenance sentence is derived from the export rather than written in either view, so
    /// it is assertable from a macOS test target that never compiles `Cadence/iOS/`. It has to
    /// carry three things: that the screen is lying, where the bytes really came from, and what to
    /// do before touching anything destructive.
    @Test func theNoteNamesTheStoreTheCountAndWhatToDoBeforeDeletingAnything() throws {
        let fixture = try makeFixture(openedRecoveryStoreHolds: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try seedStore(at: fixture.realStoreURL, taskTitle: "Belongs to the user")

        let archive = try export(fixture, startupIssue: recoveryLaunch())
        let note = try #require(archive.provenanceNote)

        #expect(note.contains("recovery store"))
        #expect(note.contains("the data on screen is not yours"))
        #expect(note.contains(fixture.realStoreURL.path), "the note does not name the store it read")
        #expect(note.contains("1 record"), "the note does not say how much was recovered")
        #expect(note.contains("before deleting anything"))
    }

    /// Singular and plural are both written, because "2 record" is the kind of thing that reaches
    /// a user on the one screen where they are already deciding whether to trust the app.
    @Test func theNoteCountsRecordsGrammatically() {
        #expect(
            CadenceDataExportPresentation
                .readFromDiskNote(recordCount: 1, storePath: "/x")
                .contains("1 record from")
        )
        #expect(
            CadenceDataExportPresentation
                .readFromDiskNote(recordCount: 2, storePath: "/x")
                .contains("2 records from")
        )
    }

    // MARK: - The route stays a round trip

    /// An archive that cannot be read back in is a souvenir, not an escape route. The importer
    /// shipped in T-274/T-1082 and is on iOS (`iOSArchiveImportSettingsSection`), so the file this
    /// ticket makes non-empty is a file the app can put back — asserted end to end here rather
    /// than inferred from the fact that both halves exist.
    @Test func theArchiveARecoveryLaunchWritesCanBeReadBackIn() throws {
        let fixture = try makeFixture(openedRecoveryStoreHolds: nil)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try seedStore(at: fixture.realStoreURL, taskTitle: "Belongs to the user")

        let archive = try export(fixture, startupIssue: recoveryLaunch())

        let destination = try CadenceTestStore.container()
        let destinationContext = ModelContext(destination)
        #expect(try destinationContext.fetch(FetchDescriptor<AppTask>()).isEmpty)

        try CadenceArchiveImportService.importArchive(archive.outcome.data, into: destination)

        #expect(
            try ModelContext(destination).fetch(FetchDescriptor<AppTask>()).map(\.title)
                == ["Belongs to the user"]
        )
    }
}
