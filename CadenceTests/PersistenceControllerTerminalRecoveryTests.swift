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
/// (`recoveryExportCandidateStoreURLs` / `openFirstAvailableReadOnlyStore`) is real logic, not a
/// screen that always says no.
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
    /// `openFirstAvailableReadOnlyStore` would then have to filter back out.
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

    // MARK: - `openFirstAvailableReadOnlyStore` — real disk I/O, isolated

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceControllerTerminalRecoveryTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A real, on-disk, non-in-memory store — the exact shape `openFirstAvailableReadOnlyStore`
    /// has to open — seeded with one distinguishing task title.
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

    @Test func noCandidatesOpensNothing() {
        #expect(PersistenceController.openFirstAvailableReadOnlyStore(from: []) == nil)
    }

    @Test func aCandidateListOfOnlyMissingFilesOpensNothing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let missing = directory.appendingPathComponent("never-created.store")
        #expect(PersistenceController.openFirstAvailableReadOnlyStore(from: [missing]) == nil)
    }

    /// The core promise: a store that genuinely exists on disk is opened and its rows are
    /// readable — not an empty container that happens to exist.
    @Test func aRealOnDiskStoreOpensAndItsRowsAreReadable() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try seedRealStore(at: storeURL, taskTitle: "Recovered task")

        let container = try #require(
            PersistenceController.openFirstAvailableReadOnlyStore(from: [storeURL])
        )
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

        let container = try #require(
            PersistenceController.openFirstAvailableReadOnlyStore(from: [missing, real])
        )
        let titles = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title)
        #expect(titles == ["Second candidate"])
    }

    /// Given two stores that both exist, the first in the list wins — the primary store, when the
    /// caller is `attemptReadOnlyStoreForRecoveryExport`, ranked ahead of any recovery directory.
    @Test func theFirstExistingCandidateWinsOverALaterOne() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.store")
        let second = directory.appendingPathComponent("second.store")
        try seedRealStore(at: first, taskTitle: "From the first store")
        try seedRealStore(at: second, taskTitle: "From the second store")

        let container = try #require(
            PersistenceController.openFirstAvailableReadOnlyStore(from: [first, second])
        )
        let titles = try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title)
        #expect(titles == ["From the first store"])
    }

    /// `allowsSave: false` is not decorative: the returned container refuses a write, so this
    /// recovery path cannot itself corrupt or extend a store it did not create.
    @Test func theOpenedContainerRefusesToSave() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try seedRealStore(at: storeURL, taskTitle: "Existing task")

        let container = try #require(
            PersistenceController.openFirstAvailableReadOnlyStore(from: [storeURL])
        )
        let context = ModelContext(container)
        context.insert(AppTask(title: "Should never be written"))
        #expect(throws: (any Error).self) {
            try context.save()
        }
    }

    // MARK: - The end-to-end export a user would actually run

    /// The full path `CadenceTerminalRecoveryView`'s button takes once a store is found:
    /// open it read-only, then hand the resulting context to the same
    /// `CadenceDataExportService.exportArchive` every other export surface in the app uses.
    @Test func aRecoveredStoreExportsThroughTheSameServiceEveryOtherExportSurfaceUses() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try seedRealStore(at: storeURL, taskTitle: "Exported from recovery")

        let container = try #require(
            PersistenceController.openFirstAvailableReadOnlyStore(from: [storeURL])
        )
        let outcome = try CadenceDataExportService.exportArchive(in: ModelContext(container))
        let archive = try CadenceDataExportService.decode(outcome.data)
        #expect(archive.tasks.map(\.title) == ["Exported from recovery"])
    }
}
