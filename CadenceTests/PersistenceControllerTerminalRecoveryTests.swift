import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-813.** `PersistenceController.init` used to end its three-tier boot sequence — CloudKit,
/// then an on-disk recovery store, then a fully in-memory one — with `fatalError` if all three
/// failed. An outside audit found it was the one `fatalError` in the app not already guarded or
/// literal-backed, and the last-resort trap crashed on launch with no explanation and nothing
/// offered. This suite pins its replacement: `container` goes `nil`, `terminalFailure` records why,
/// and `CadenceTerminalRecoveryView`'s "try to export what's there" path
/// (`recoveryExportCandidateStoreURLs` / `openReadOnlyStore` / `recoverFirstExportableStore`) is
/// real logic, not a screen that always says no.
///
/// **T-1099 added the second half of that search.** The screen used to stop at the first store that
/// *opened*, and an open is not an export: the archive runs twenty-one throwing fetches afterwards,
/// so a store SwiftData could attach to and not read ended the search with a later, readable store
/// never tried. The tests below inject an open that succeeds and an export that throws, because no
/// file fixture can arrange that pair on demand.
@MainActor
struct PersistenceControllerTerminalRecoveryTests {
    // MARK: - The trap is gone, not moved

    /// The exact count, not a ceiling: one `fatalError` remains in this file (the `isRunningTests`
    /// path, out of this ticket's scope — a broken test host, not a user-facing failure) and the
    /// bootstrap trap this ticket is about is not it.
    @Test func exactlyOneFatalErrorRemainsAndItIsTheTestOnlyOne() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )

        #expect(
            CadenceSourceScan.matchCount("fatalError\\(", in: source) == 1,
            "expected exactly one fatalError left in PersistenceController.swift"
        )
        #expect(source.contains("fatalError(\"Could not create test ModelContainer"))
        #expect(!source.contains("In-memory recovery store creation also failed: \\(error.localizedDescription)\")"))
    }

    /// `makeRecoveryContainer`'s final catch — the one the trap used to sit in — now records a
    /// `terminalFailure` and returns `nil` instead. Read from the real function body so a rewrite
    /// that keeps the fatal error out but forgets to set `terminalFailure` (leaving
    /// `CadenceTerminalRecoveryView` with no explanation to show) is caught here rather than only
    /// by a UI test that never runs this deep a failure.
    @Test func theFinalRecoveryCatchRecordsATerminalFailureInsteadOfCrashing() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        let body = try #require(
            CadenceSourceScan.functionBody(named: "makeRecoveryContainer", in: source),
            "makeRecoveryContainer is gone or its braces do not balance"
        )

        #expect(body.contains("terminalFailure = CadenceStartupTerminalFailure("))
        #expect(body.contains("return nil"))
        // Non-vacuity: an empty or wrong read would trivially satisfy both `contains` checks above.
        #expect(body.contains("isStoredInMemoryOnly: true"))
    }

    /// `container`'s type is the other half of the fix: a bare `ModelContainer` cannot be `nil`,
    /// so keeping it non-optional would have forced the fatal error (or a force unwrap standing in
    /// for one) to stay.
    @Test func theContainerPropertyIsOptional() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        #expect(source.contains("let container: ModelContainer?"))
    }

    // MARK: - The app falls back to the recovery screen, not a force unwrap

    /// `CadenceApp` cannot branch its `Scene` on `container` being `nil` — `SceneBuilder` only
    /// supports `if` for `#available`, not ordinary conditions — so the branch has to live one
    /// level down, inside `WindowGroup`'s view content, with `.modelContainer(_:)` attached to
    /// each branch's own view rather than to the `Scene`. This reads the real source so a future
    /// edit that moves `.modelContainer` back up to the `Scene` (which would not compile with an
    /// optional, and would force a non-optional unwrap back in to make it compile) is caught here.
    @Test func theAppFallsBackToTheTerminalRecoveryViewInsteadOfForcingAContainer() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/CadenceApp.swift")
        )

        #expect(source.contains("let sharedModelContainer: ModelContainer?"))
        #expect(source.contains("if let sharedModelContainer {"))
        #expect(source.contains("CadenceTerminalRecoveryView(failure: PersistenceController.terminalFailure)"))

        // `.modelContainer(sharedModelContainer)` must appear only ahead of the `else` that shows
        // the recovery view — i.e. only inside the branch that actually has one.
        let ifRange = try #require(source.range(of: "if let sharedModelContainer {"))
        let elseRange = try #require(source.range(of: "} else {", range: ifRange.upperBound..<source.endIndex))
        let ifBranch = String(source[ifRange.upperBound..<elseRange.lowerBound])
        let elseBranch = String(source[elseRange.upperBound...])

        #expect(CadenceSourceScan.matchCount("\\.modelContainer\\(sharedModelContainer\\)", in: ifBranch) == 2)
        #expect(!elseBranch.contains(".modelContainer(sharedModelContainer)"))
        #expect(elseBranch.contains("CadenceTerminalRecoveryView"))
    }

    /// The two floating panels that build their own `.modelContainer` outside the main window
    /// group (`QuickTaskPanelController`, `TaskNotesPanelController`) read the same optional
    /// `container` `CadenceApp` does. A force unwrap at either site would be a new crash this
    /// ticket's own constraint forbids introducing.
    @Test func theFloatingPanelControllersGuardAgainstNoContainerRatherThanForceUnwrapping() throws {
        let quickTaskSource = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Services/QuickTaskPanelController.swift")
        )
        #expect(quickTaskSource.contains("guard let container = PersistenceController.shared.container else"))
        #expect(!quickTaskSource.contains("PersistenceController.shared.container!"))

        let taskNotesSource = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        )
        #expect(taskNotesSource.contains("guard let container = PersistenceController.shared.container else"))
        #expect(!taskNotesSource.contains("PersistenceController.shared.container!"))
    }

    /// The test host itself always takes the `isRunningTests` fast path, so under ordinary test
    /// conditions `terminalFailure` should never be set. This is the non-vacuity check for every
    /// scan above: if `PersistenceController.shared` were somehow already in the terminal state,
    /// nothing in this suite's scans would be trustworthy evidence about a "healthy" launch.
    @Test func theTestHostItselfNeverReachesTheTerminalState() {
        #expect(PersistenceController.shared.container != nil)
        #expect(PersistenceController.terminalFailure == nil)
    }

    // MARK: - `recoveryExportCandidateStoreURLs` — pure ordering

    @Test func candidateURLsPutThePrimaryStoreFirst() {
        let primary = URL(fileURLWithPath: "/store/default.store")
        let recoveryOne = URL(fileURLWithPath: "/recovery/one", isDirectory: true)
        let recoveryTwo = URL(fileURLWithPath: "/recovery/two", isDirectory: true)

        let candidates = PersistenceController.recoveryExportCandidateStoreURLs(
            primaryStoreURL: primary,
            recoveryDirectoryCandidates: [recoveryOne, recoveryTwo]
        )

        #expect(candidates.map(\.path) == [
            "/store/default.store",
            "/recovery/one/recovery.store",
            "/recovery/two/recovery.store",
        ])
    }

    /// A `nil` primary store URL is dropped entirely, not turned into a placeholder that
    /// `recoverFirstExportableStore` would then have to filter back out.
    @Test func candidateURLsDropANilPrimaryStoreRatherThanPassingItThrough() {
        let recoveryOne = URL(fileURLWithPath: "/recovery/one", isDirectory: true)

        let candidates = PersistenceController.recoveryExportCandidateStoreURLs(
            primaryStoreURL: nil,
            recoveryDirectoryCandidates: [recoveryOne]
        )

        #expect(candidates.map(\.path) == ["/recovery/one/recovery.store"])
    }

    @Test func candidateURLsAreEmptyWhenNothingWasResolved() {
        #expect(PersistenceController.recoveryExportCandidateStoreURLs(
            primaryStoreURL: nil,
            recoveryDirectoryCandidates: []
        ).isEmpty)
    }

    // MARK: - The candidate search — real disk I/O, isolated

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceControllerTerminalRecoveryTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A real, on-disk, non-in-memory store — the exact shape `openReadOnlyStore(at:)` has to
    /// open — seeded with one distinguishing task title.
    private func seedRealStore(at storeURL: URL, taskTitle: String) throws {
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: storeURL
        )
        let context = ModelContext(container)
        context.insert(AppTask(title: taskTitle))
        try context.save()
    }

    private func exportedTitles(_ result: PersistenceController.RecoveryExportResult) throws -> [String] {
        guard case .exported(let export) = result else {
            Issue.record("expected an export, got \(result)")
            return []
        }
        return try CadenceDataExportService.decode(export.data).tasks.map(\.title)
    }

    @Test func noCandidatesRecoversNothing() {
        #expect(PersistenceController.recoverFirstExportableStore(from: []) == .noStoreOpened)
    }

    @Test func aCandidateListOfOnlyMissingFilesRecoversNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent("never-created.store")
        #expect(PersistenceController.recoverFirstExportableStore(from: [missing]) == .noStoreOpened)
    }

    /// The core promise of the open half: a store that genuinely exists on disk is opened and its
    /// rows are readable — not an empty container that happens to exist.
    @Test func aRealOnDiskStoreOpensAndItsRowsAreReadable() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try seedRealStore(at: storeURL, taskTitle: "Recovered task")

        let container = try #require(PersistenceController.openReadOnlyStore(at: storeURL))
        let titles = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title)
        #expect(titles == ["Recovered task"])
    }

    /// A missing first candidate is skipped in favour of a second one that exists — proving this
    /// walks the list in order rather than only ever trying the first entry.
    @Test func aMissingFirstCandidateFallsThroughToTheNextOneThatExists() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.store")
        let real = directory.appendingPathComponent("real.store")
        try seedRealStore(at: real, taskTitle: "Second candidate")

        let result = PersistenceController.recoverFirstExportableStore(from: [missing, real])

        #expect(try exportedTitles(result) == ["Second candidate"])
        guard case .exported(let export) = result else { return }
        // A candidate that was never there is not reported as a failure: an absent recovery store
        // is the ordinary case, and naming it would bury a real one.
        #expect(export.precedingFailures.isEmpty)
        #expect(export.storeURL == real)
    }

    /// Given two stores that both export, the first in the list wins — the primary store, when the
    /// caller is `attemptRecoveryExport`, ranked ahead of any recovery directory.
    @Test func theFirstExportableCandidateWinsOverALaterOne() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.store")
        let second = directory.appendingPathComponent("second.store")
        try seedRealStore(at: first, taskTitle: "From the first store")
        try seedRealStore(at: second, taskTitle: "From the second store")

        let result = PersistenceController.recoverFirstExportableStore(from: [first, second])

        #expect(try exportedTitles(result) == ["From the first store"])
        guard case .exported(let export) = result else { return }
        #expect(export.storeURL == first)
        #expect(export.precedingFailures.isEmpty)
    }

    /// `allowsSave: false` is not decorative: the returned container refuses a write, so this
    /// recovery path cannot itself corrupt or extend a store it did not create.
    @Test func theOpenedContainerRefusesToSave() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try seedRealStore(at: storeURL, taskTitle: "Existing task")

        let container = try #require(PersistenceController.openReadOnlyStore(at: storeURL))
        let context = ModelContext(container)
        context.insert(AppTask(title: "Should never be written"))
        #expect(throws: (any Error).self) {
            try context.save()
        }
    }

    // MARK: - T-1099: an open is not an export

    /// **The defect.** Both candidates are real stores that open. The first one's export throws —
    /// the shape `CadenceDataExportService.makeArchive` fails in, a throwing fetch after a
    /// successful open — and the second holds the row the user still has. Before T-1099 the search
    /// ended at the first open and this row never reached a file.
    @Test func aStoreThatOpensAndFailsToExportDoesNotEndTheSearch() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.store")
        let second = directory.appendingPathComponent("second.store")
        try seedRealStore(at: first, taskTitle: "In the store that will not export")
        try seedRealStore(at: second, taskTitle: "Sentinel in the later store")

        var exportAttempts = 0
        let result = PersistenceController.recoverFirstExportableStore(
            from: [first, second],
            export: { container in
                exportAttempts += 1
                if exportAttempts == 1 {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return try CadenceDataExportService.exportArchive(in: ModelContext(container))
            }
        )

        #expect(exportAttempts == 2, "the second candidate was never asked to export")
        #expect(try exportedTitles(result) == ["Sentinel in the later store"])
        guard case .exported(let export) = result else { return }
        // Provenance, and the failure it stepped over — an archive that silently drops a store is
        // how a user concludes the rest of their data is gone.
        #expect(export.storeURL == second)
        #expect(export.precedingFailures.map(\.storeURL) == [first])
        #expect(export.precedingFailures.allSatisfy { !$0.reason.isEmpty })
        #expect(export.recordCount == 1)
    }

    /// When every store that opens refuses, the result is not `.noStoreOpened`: "nothing is on this
    /// device" and "everything on this device refused" are different sentences, and the screen says
    /// different things for them.
    @Test func everyOpenedStoreFailingIsReportedInOrderRatherThanAsNothingFound() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.store")
        let second = directory.appendingPathComponent("second.store")
        try seedRealStore(at: first, taskTitle: "One")
        try seedRealStore(at: second, taskTitle: "Two")

        let result = PersistenceController.recoverFirstExportableStore(
            from: [first, second],
            export: { _ in throw CocoaError(.fileReadCorruptFile) }
        )

        guard case .everyOpenedStoreFailed(let failures) = result else {
            Issue.record("expected every candidate to be reported, got \(result)")
            return
        }
        #expect(failures.map(\.storeURL) == [first, second])
    }

    /// The other half of the same distinction, from the other side: candidates that never open
    /// leave `.noStoreOpened`, so an empty device is never reported as a store that refused.
    @Test func aStoreThatNeverOpensIsNotReportedAsAFailedExport() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.store")

        let result = PersistenceController.recoverFirstExportableStore(
            from: [missing],
            open: { _ in nil },
            export: { _ in Issue.record("nothing opened, so nothing should have been exported"); throw CocoaError(.fileReadUnknown) }
        )
        #expect(result == .noStoreOpened)
    }

    // MARK: - What the screen says about a partial recovery

    @Test func aPartialRecoverySaysWhatWasSavedBeforeWhatWasNot() {
        let skipped = URL(fileURLWithPath: "/store/first.store")
        let sentence = CadenceTerminalRecoveryView.partialRecoverySentence(
            PersistenceController.RecoveryExport(
                storeURL: URL(fileURLWithPath: "/store/second.store"),
                data: Data(),
                recordCount: 412,
                precedingFailures: [
                    PersistenceController.RecoveryExportFailure(storeURL: skipped, reason: "The file is corrupt.")
                ]
            )
        )

        // The count first, so the line cannot be read as "nothing was recovered"...
        #expect(sentence.hasPrefix("Saved 412 records from /store/second.store."))
        // ...and then the store that is not in the file, named, with its reason.
        #expect(sentence.contains("One other store"))
        #expect(sentence.contains("/store/first.store"))
        #expect(sentence.contains("The file is corrupt."))
    }

    @Test func aTotalFailureNamesEveryStoreItTried() {
        let sentence = CadenceTerminalRecoveryView.everyStoreFailedSentence([
            PersistenceController.RecoveryExportFailure(
                storeURL: URL(fileURLWithPath: "/store/first.store"),
                reason: "Corrupt."
            ),
            PersistenceController.RecoveryExportFailure(
                storeURL: URL(fileURLWithPath: "/store/second.store"),
                reason: "Also corrupt."
            ),
        ])

        #expect(sentence.contains("Found 2 stores"))
        #expect(sentence.contains("/store/first.store: Corrupt."))
        #expect(sentence.contains("/store/second.store: Also corrupt."))
    }

    // MARK: - The end-to-end export a user would actually run

    /// The full path `CadenceTerminalRecoveryView`'s button takes: the search's own default
    /// `export` is the same `CadenceDataExportService.exportArchive` every other export surface in
    /// the app uses, with no seam left in the shipped path.
    @Test func aRecoveredStoreExportsThroughTheSameServiceEveryOtherExportSurfaceUses() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try seedRealStore(at: storeURL, taskTitle: "Exported from recovery")

        let result = PersistenceController.recoverFirstExportableStore(from: [storeURL])

        #expect(try exportedTitles(result) == ["Exported from recovery"])
        guard case .exported(let export) = result else { return }
        #expect(export.recordCount == 1)
    }

    // MARK: - The screen's diagnosis

    /// **[[T-1097]]. The explanation described a backup this app does not have, and diagnosed a
    /// cause nobody measured.**
    ///
    /// It said startup tried "a backup location on this device", and that all three failing
    /// "usually means the device was very low on memory or storage". Neither survives contact with
    /// `makeRecoveryContainer`, pinned by the test below it: the second tier opens a *separate,
    /// empty* store at `recovery.store` and restores nothing into it, so calling it a backup tells
    /// a user in the worst moment of the app's life that a safety copy was tried and failed — the
    /// opposite of what is true about their disk. And "usually" is a frequency claim with no
    /// measurement anywhere in this repository behind it.
    ///
    /// Read with comments stripped, because the paragraph above quotes both retired sentences.
    @Test func theTerminalRecoveryExplanationDropsTheBackupAndTheUnmeasuredCause() throws {
        let raw = try CadenceSourceScan.sourceFile(
            "Cadence/Shared/Components/CadenceTerminalRecoveryView.swift"
        )
        let source = CadenceSourceScan.strippingComments(raw)
        // Non-vacuity: the read found a real file, the stripper ran, and it kept every offset.
        #expect(source.contains("private var explanation: String {"))
        #expect(source != raw)
        #expect(source.count == raw.count)

        #expect(!source.contains("backup location on this device"))
        #expect(!source.contains("very low on memory or storage"))
        #expect(!source.contains("This usually means"))

        // What replaces them says what the fallbacks are, and what they are not.
        #expect(source.contains(
            "The second and third are fallbacks rather than backups: nothing was restored from them, and nothing has been deleted."
        ))
        // …and points at the one thing on this screen that *is* measured.
        #expect(source.contains("The recorded reason is at the bottom of this screen."))

        // The export card keeps its own "backup" promise, because that one is a copy this screen
        // is about to attempt rather than one it claims already exists. Without this line, deleting
        // the word from the whole file would also pass.
        #expect(source.contains("it only tries to get a backup of what is already on this device"))
    }

    /// The code fact that sentence rests on: the recovery tier **creates** an empty store, it does
    /// not restore one. If this ever becomes a real restore, the copy pinned above becomes wrong
    /// and has to change with it.
    @Test func theRecoveryTierCreatesAnEmptyStoreRatherThanRestoringABackup() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/PersistenceController.swift")
        )
        let body = try #require(
            CadenceSourceScan.functionBody(named: "makeRecoveryContainer", in: source),
            "could not find makeRecoveryContainer in PersistenceController"
        )
        #expect(body.contains("url: recoveryDirectoryURL.appendingPathComponent(\"recovery.store\")"))
        #expect(body.contains("return try ModelContainer(for: schema, configurations: [recoveryConfig])"))
    }
}
