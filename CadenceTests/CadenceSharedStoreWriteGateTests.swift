import Foundation
import SwiftData
import Testing
@testable import Cadence

/// What an out-of-process write is allowed to do to a store the app has not prepared yet: nothing.
///
/// **T-311.** The asymmetry these tests are built on was measured, not assumed, and the first test
/// pins it: opening the store `allowsSave: false` at a path with no store fails and leaves the
/// directory empty, while opening it `allowsSave: true` *creates* the store. The four widgets
/// render through the read-only side, so passive rendering was never the problem. The three App
/// Intents wrote, and they run in the widget extension, which never executes
/// `PersistenceController.init`.
///
/// So a widget button tapped once after an update, before the app had been opened, created
/// `default.store` in the app group — and `migrateLegacyStoreIfNeeded` refuses to copy into a
/// non-empty directory. The user's legacy store stayed where it was and the app opened the empty
/// one instead, silently and for good.
///
/// A happy-path test would not have caught that, so the test that matters here is shaped like the
/// failure: seed a real legacy store, run the intents' container creation **first**, then migrate,
/// then ask whether the row is in the store the app would open.
@MainActor
struct CadenceSharedStoreWriteGateTests {
    // MARK: - Fixtures

    /// Always a fresh temporary directory. Nothing in this file may touch the real app-group store.
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceSharedStoreWriteGateTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func seedRealStore(in directoryURL: URL, taskTitle: String) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: directoryURL.appendingPathComponent(CadenceStoreSupport.storeFilename)
        )
        let context = ModelContext(container)
        context.insert(AppTask(title: taskTitle))
        try context.save()
    }

    /// Read the store back the way the app would: open it and fetch, rather than compare bytes.
    private func taskTitles(inStoreDirectory directoryURL: URL) throws -> [String] {
        let container = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: false,
            cloudKitDatabase: .none,
            storeURL: directoryURL.appendingPathComponent(CadenceStoreSupport.storeFilename)
        )
        return try ModelContext(container).fetch(FetchDescriptor<AppTask>()).map(\.title).sorted()
    }

    private func directoryContents(_ directoryURL: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []).sorted()
    }

    // MARK: - The asymmetry the fix is built on

    @Test func aWriteCapableOpenCreatesAMissingStoreAndAReadOnlyOpenDoesNot() throws {
        let readOnlyDirectory = try makeTemporaryDirectory()
        let writeDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: readOnlyDirectory)
            try? FileManager.default.removeItem(at: writeDirectory)
        }

        #expect(throws: (any Error).self) {
            _ = try CadenceStoreSupport.makePrimaryContainer(
                allowsSave: false,
                cloudKitDatabase: .none,
                storeURL: readOnlyDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename)
            )
        }
        #expect(directoryContents(readOnlyDirectory).isEmpty)

        _ = try CadenceStoreSupport.makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: .none,
            storeURL: writeDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename)
        )
        #expect(directoryContents(writeDirectory).contains(CadenceStoreSupport.storeFilename))
    }

    // MARK: - The migration a widget write used to be able to skip

    @Test func aWidgetWriteBeforeTheAppHasMigratedCannotStrandTheLegacyStore() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
        let appGroupDirectory = root.appendingPathComponent("group", isDirectory: true)
        try FileManager.default.createDirectory(at: appGroupDirectory, withIntermediateDirectories: true)

        // The user's data, in the store the app used to keep before it moved to the app group.
        try seedRealStore(in: legacyDirectory, taskTitle: "Legacy task")

        // The widget taps first: this is exactly what every write intent's `perform()` calls.
        #expect(throws: CadenceSharedStoreWriteRefusal.storeNotPrepared) {
            _ = try CadenceStoreSupport.makeSharedWriteContainer(storeDirectoryURL: appGroupDirectory)
        }
        #expect(
            CadenceStoreSupport.storeItemURLs(in: appGroupDirectory).isEmpty,
            "a refused write must leave the app group with no store for the migration to trip over"
        )

        // Now the app launches and runs the startup sequence the extension could not.
        let migratedFrom = try CadenceStoreSupport.migrateLegacyStoreIfNeeded(
            appGroupDirectoryURL: appGroupDirectory,
            candidateLegacyDirectories: [legacyDirectory]
        )

        #expect(migratedFrom == legacyDirectory)
        #expect(try taskTitles(inStoreDirectory: appGroupDirectory) == ["Legacy task"])
    }

    @Test func theSameWriteSucceedsOnceTheAppHasPreparedTheStore() throws {
        let storeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        try seedRealStore(in: storeDirectory, taskTitle: "Existing task")

        let container = try CadenceStoreSupport.makeSharedWriteContainer(storeDirectoryURL: storeDirectory)
        let context = ModelContext(container)
        context.insert(AppTask(title: "Captured from a widget"))
        try context.save()

        #expect(try taskTitles(inStoreDirectory: storeDirectory) == ["Captured from a widget", "Existing task"])
    }

    // MARK: - The other thing the app does before it opens the store

    @Test func aScheduledRestoreRefusesOutOfProcessWritesUntilTheAppAppliesIt() throws {
        try withTemporaryDefaults("CadenceTests.sharedStoreWriteGate") { defaults in
            let storeDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }

            try seedRealStore(in: storeDirectory, taskTitle: "What the backup holds")
            let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
                reason: .manual,
                storeDirectoryURL: storeDirectory
            ))

            // The store is present, so the first guard would wave this through. A restore is about
            // to replace it, which the extension cannot learn from `UserDefaults.standard`.
            try StoreBackupManager.scheduleRestore(
                from: backupURL,
                defaults: defaults,
                storeDirectoryURL: storeDirectory
            )
            #expect(throws: CadenceSharedStoreWriteRefusal.restorePending) {
                _ = try CadenceStoreSupport.makeSharedWriteContainer(storeDirectoryURL: storeDirectory)
            }

            try StoreBackupManager.performPendingRestoreIfNeeded(
                storeDirectoryURL: storeDirectory,
                defaults: defaults
            )

            _ = try CadenceStoreSupport.makeSharedWriteContainer(storeDirectoryURL: storeDirectory)
            #expect(try taskTitles(inStoreDirectory: storeDirectory) == ["What the backup holds"])
        }
    }

    @Test func aRestoreMarkerLeftBehindByNothingIsClearedByTheNextLaunch() throws {
        try withTemporaryDefaults("CadenceTests.sharedStoreWriteGate") { defaults in
            let storeDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: storeDirectory) }
            try seedRealStore(in: storeDirectory, taskTitle: "Still here")

            // A marker with no pending restore behind it would otherwise refuse every widget write
            // from now until a reinstall.
            CadenceStoreSupport.setRestorePending(true, inStoreDirectory: storeDirectory)
            #expect(CadenceStoreSupport.restoreIsPending(inStoreDirectory: storeDirectory))

            try StoreBackupManager.performPendingRestoreIfNeeded(
                storeDirectoryURL: storeDirectory,
                defaults: defaults
            )

            #expect(!CadenceStoreSupport.restoreIsPending(inStoreDirectory: storeDirectory))
            _ = try CadenceStoreSupport.makeSharedWriteContainer(storeDirectoryURL: storeDirectory)
        }
    }

    @Test func theRestoreMarkerIsNeverMistakenForPartOfTheStore() throws {
        let storeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        try seedRealStore(in: storeDirectory, taskTitle: "Still here")
        CadenceStoreSupport.setRestorePending(true, inStoreDirectory: storeDirectory)

        #expect(!CadenceStoreSupport.managedStoreItemNames.contains(CadenceStoreSupport.restorePendingMarkerName))
        #expect(
            !CadenceStoreSupport.storeItemURLs(in: storeDirectory)
                .map(\.lastPathComponent)
                .contains(CadenceStoreSupport.restorePendingMarkerName)
        )
    }

    // MARK: - Nothing may open the shared store for writing around the gate

    /// Scoped to each `perform()` **body**, not to the file: a file-wide count would pass for a
    /// fourth intent that opened its own container as long as the totals happened to line up.
    @Test func everyIntentThatOpensTheStoreOpensItThroughTheGate() throws {
        let source = try sourceWithoutCommentLines("Cadence/Services/CadenceWidgetIntents.swift")
        let bodies = functionBodies(startingWith: "func perform(", in: source)
        #expect(bodies.count == 4, "found \(bodies.count) perform() bodies")

        var gatedBodies = 0
        for body in bodies where body.contains("ModelContext(") {
            #expect(body.contains("CadenceStoreSupport.makeSharedWriteContainer("))
            #expect(!body.contains("makePrimaryContainer("))
            gatedBodies += 1
        }
        // Three write intents; `OpenCadenceTodayIntent` opens the app and touches no store.
        #expect(gatedBodies == 3)
        #expect(!source.contains("allowsSave: true"))
    }

    @Test func theWidgetsThemselvesStillOpenTheStoreReadOnly() throws {
        var readOnlyOpens = 0
        for relativePath in try swiftFilesUnder("CadenceWidgets") {
            let source = try sourceWithoutCommentLines(relativePath)
            #expect(!source.contains("allowsSave: true"), "\(relativePath) opens the shared store for writing")
            readOnlyOpens += occurrences(of: "allowsSave: false", in: source)
        }
        #expect(readOnlyOpens == 4)
    }

    // MARK: - Source scanning

    /// Drops whole-line comments before scanning, so a doc comment that quotes `allowsSave: true`
    /// cannot fail a test about code. Line-trailing comments are left alone deliberately: nothing
    /// here needs them, and a `//` matcher that has to survive `https://` is its own bug.
    private func sourceWithoutCommentLines(_ relativePath: String) throws -> String {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths,
    /// and `#filePath` can name the repo through a symlinked prefix an isolated build tree resolves.
    private func swiftFilesUnder(_ relativeDirectory: String) throws -> [String] {
        let directoryURL = repositoryRoot().appendingPathComponent(relativeDirectory)
        guard let enumerator = FileManager.default.enumerator(atPath: directoryURL.path) else { return [] }
        return enumerator.compactMap { element in
            guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
            return "\(relativeDirectory)/\(relativePath)"
        }
    }

    /// Every function body whose declaration starts with `prefix`, brace-matched from its opening
    /// `{` to the matching `}`.
    private func functionBodies(startingWith prefix: String, in source: String) -> [String] {
        var bodies: [String] = []
        var searchStart = source.startIndex
        while let declaration = source.range(of: prefix, range: searchStart..<source.endIndex) {
            searchStart = declaration.upperBound
            guard let bodyStart = source[declaration.upperBound...].firstIndex(of: "{") else { break }
            var depth = 0
            var index = bodyStart
            while index < source.endIndex {
                if source[index] == "{" { depth += 1 }
                if source[index] == "}" {
                    depth -= 1
                    if depth == 0 {
                        bodies.append(String(source[bodyStart...index]))
                        searchStart = source.index(after: index)
                        break
                    }
                }
                index = source.index(after: index)
            }
        }
        return bodies
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
