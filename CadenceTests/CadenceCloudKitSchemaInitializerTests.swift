import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-15751]]. The debug-only path that publishes this app's schema to CloudKit's **Development**
/// environment, and the pins that keep it away from the signed-in person's store.
///
/// **The whole safety argument is one claim: it never opens the app-group store.** [[T-3013]] took
/// the old route away for a reason — a development-signed build mirroring the *real* store stamps
/// the owner's records as already exported to Development and Production then never receives them
/// ([[T-2053]], four weeks of the owner's Mac not reaching their iPad). A schema-init pass over a
/// store this process made seconds ago under `tmp` carries that risk nowhere, which is exactly why
/// it is allowed where reviving the old route is not. So the claim is pinned here rather than
/// trusted: a store URL is opened only when it is inside the directory this run created, and three
/// separate rules refuse the places the owner's data actually is.
///
/// **Nothing in this suite makes a live CloudKit call.** `perform` takes its CloudKit work as a
/// closure with no default, and every test here passes one that records the URL and returns. It
/// also takes its `SafetyInputs`, so a test that drives the refusal uses directories of its own:
/// the refusal tests below would otherwise prove themselves, when broken, by creating a directory
/// inside the owner's real app-group container.
@MainActor
struct CadenceCloudKitSchemaInitializerTests {

    private typealias Initializer = CadenceCloudKitSchemaInitializer

    // MARK: - Fixtures

    /// A throwaway tree this test owns, removed when the test returns.
    private final class Workspace {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("T15751-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func directory(_ name: String) -> URL {
            root.appendingPathComponent(name, isDirectory: true)
        }
    }

    /// A recorder standing in for `publishSchema(fromStoreAt:)`.
    private final class SchemaCall {
        private(set) var urls: [URL] = []
        private(set) var directoriesPresentWhenCalled: [Bool] = []
        var failure: Error?

        func initialize(_ url: URL) throws {
            urls.append(url)
            directoriesPresentWhenCalled.append(
                FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
            )
            if let failure { throw failure }
        }
    }

    private static func safety(
        store: URL? = nil,
        appGroup: URL? = nil,
        legacy: URL? = nil
    ) -> Initializer.SafetyInputs {
        Initializer.SafetyInputs(
            storeThisLaunchWouldOpen: store,
            appGroupContainerURL: appGroup,
            legacyApplicationSupportStoreDirectoryURL: legacy
        )
    }

    // MARK: - 1. The refusal, over the live process

    /// **The pin [[T-15751]] names by hand: the store this launch would open is refused.**
    ///
    /// Asked of `PersistenceController.resolvedStoreURL()` itself rather than of a second spelling
    /// of the app-group path — one resolver is the standing rule ([[T-1530]]), and a safety test
    /// built on a hand-rolled copy of it would keep passing after the resolver moved.
    ///
    /// In this test host that URL is the redirected test-host store, which is *also* outside the
    /// throwaway directory. The expected case is therefore `isTheStoreThisLaunchWouldOpen` and not
    /// the generic `notInsideThisRunsThrowawayDirectory`: the refusal says which store it is.
    @Test func theRefusalRejectsTheStoreThisLaunchWouldOpen() throws {
        let workspace = try Workspace()
        let throwaway = workspace.directory(Initializer.throwawayDirectoryPrefix + UUID().uuidString)
        let resolved = try PersistenceController.resolvedStoreURL()

        #expect(
            Initializer.refusal(
                forStoreURL: resolved,
                safety: .live(),
                throwawayDirectoryURL: throwaway
            ) == .isTheStoreThisLaunchWouldOpen,
            "the schema-init path accepted \(resolved.path), which is the store this launch opens"
        )
    }

    /// The app-group container, asked of the live `FileManager`, and composed rather than created
    /// (`storeDirectoryLocation` exists so asking where the store is does not make a folder in the
    /// owner's container — [[T-1852]]).
    @Test func theRefusalRejectsTheRealStoreAndEverythingBesideIt() throws {
        let workspace = try Workspace()
        let throwaway = workspace.directory(Initializer.throwawayDirectoryPrefix + UUID().uuidString)
        let groupStoreDirectory = try CadenceStoreSupport.storeDirectoryLocation()

        let candidates: [URL] = [
            groupStoreDirectory.appendingPathComponent(CadenceStoreSupport.storeFilename),
            groupStoreDirectory.appendingPathComponent("default.store-wal"),
            groupStoreDirectory.appendingPathComponent("default.store-shm"),
            groupStoreDirectory
                .appendingPathComponent("Recovery", isDirectory: true)
                .appendingPathComponent("recovery.store"),
            groupStoreDirectory
                .appendingPathComponent("Cadence Store Backups", isDirectory: true)
                .appendingPathComponent("some-backup", isDirectory: true)
                .appendingPathComponent("default.store"),
            groupStoreDirectory,
        ]

        for candidate in candidates {
            let verdict = Initializer.refusal(
                forStoreURL: candidate,
                safety: .live(),
                throwawayDirectoryURL: throwaway
            )
            #expect(
                verdict == .insideTheAppGroupContainer || verdict == .isTheStoreThisLaunchWouldOpen,
                "the schema-init path answered \(String(describing: verdict)) for \(candidate.path)"
            )
        }
    }

    // MARK: - 2. The refusal, exhaustively, over fixtures

    /// Every rule, and the one shape that is allowed, with the inputs supplied rather than read
    /// from the running process — so the table reads the same on both platform legs.
    @Test func theRefusalTableAcceptsOnlyAStoreInsideThisRunsThrowawayDirectory() throws {
        let workspace = try Workspace()
        let group = workspace.directory("Group Containers/group.com.haoranwei.Cadence")
        let legacy = workspace.directory("Application Support/Cadence")
        let store = group
            .appendingPathComponent("Library/Application Support/Cadence", isDirectory: true)
            .appendingPathComponent("default.store")
        let throwaway = workspace.directory(Initializer.throwawayDirectoryPrefix + "fixed")
        let inputs = Self.safety(store: store, appGroup: group, legacy: legacy)

        let table: [(URL, Initializer.Refusal?)] = [
            // The store itself, named exactly.
            (store, .isTheStoreThisLaunchWouldOpen),

            // Anywhere under the app-group container, including the container itself.
            (group, .insideTheAppGroupContainer),
            (group.appendingPathComponent("anything.store"), .insideTheAppGroupContainer),
            (store.deletingLastPathComponent(), .insideTheAppGroupContainer),

            // The legacy Application Support store directory, which is still a recovery-export
            // candidate and therefore still the owner's data.
            (legacy, .insideTheLegacyApplicationSupportStore),
            (legacy.appendingPathComponent("default.store"), .insideTheLegacyApplicationSupportStore),

            // Not inside the directory this run made: a sibling, the parent, the directory itself,
            // and a neighbour whose name merely *starts* with the same characters.
            (workspace.directory("elsewhere").appendingPathComponent("x.store"), .notInsideThisRunsThrowawayDirectory),
            (workspace.root.appendingPathComponent("x.store"), .notInsideThisRunsThrowawayDirectory),
            (throwaway, .notInsideThisRunsThrowawayDirectory),
            (
                workspace.directory(Initializer.throwawayDirectoryPrefix + "fixed-other")
                    .appendingPathComponent(Initializer.throwawayStoreFilename),
                .notInsideThisRunsThrowawayDirectory
            ),

            // The one accepted shape, and one nested below it.
            (throwaway.appendingPathComponent(Initializer.throwawayStoreFilename), nil),
            (throwaway.appendingPathComponent("nested/x.store"), nil),
        ]

        for (candidate, expected) in table {
            #expect(
                Initializer.refusal(
                    forStoreURL: candidate,
                    safety: inputs,
                    throwawayDirectoryURL: throwaway
                ) == expected,
                "\(candidate.path) expected \(String(describing: expected))"
            )
        }
    }

    /// A refusal must not depend on the two spellings of a temporary path agreeing as strings:
    /// `/var` and `/private/var` are one directory, and a string-prefix test answers "not inside"
    /// for the resolved form of the container every time.
    @Test func theContainmentTestResolvesSymlinksRatherThanComparingStrings() throws {
        let workspace = try Workspace()
        let group = workspace.directory("group")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)

        // `workspace.root` is under `temporaryDirectory`, which on this platform is reached by a
        // symlink — so `group` and `group.resolvingSymlinksInPath()` are two spellings of one
        // directory, and a string comparison answers that they are different places.
        #expect(Initializer.isSamePath(group, group.resolvingSymlinksInPath()))
        #expect(
            Initializer.refusal(
                forStoreURL: group.resolvingSymlinksInPath().appendingPathComponent("x.store"),
                safety: Self.safety(appGroup: group),
                throwawayDirectoryURL: workspace.directory("throwaway")
            ) == .insideTheAppGroupContainer,
            "the resolved spelling of a path inside the app-group container read as outside it"
        )

        let dotted = group.appendingPathComponent("a/../b/../anything.store")
        #expect(
            Initializer.refusal(
                forStoreURL: dotted,
                safety: Self.safety(appGroup: group),
                throwawayDirectoryURL: workspace.directory("throwaway")
            ) == .insideTheAppGroupContainer,
            "a `..`-bearing path inside the app-group container was not recognised as inside it"
        )
        #expect(!Initializer.isDescendant(group, of: group), "a directory is not inside itself")
    }

    // MARK: - 3. `perform` opens only what the refusal cleared

    @Test func performOpensOneFreshThrowawayStoreAndRemovesItAfterwards() throws {
        let workspace = try Workspace()
        let temporaryDirectory = workspace.directory("tmp")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let call = SchemaCall()

        let outcome = Initializer.perform(
            environment: [Initializer.environmentKey: "1"],
            temporaryDirectory: temporaryDirectory,
            safety: Self.safety(
                store: workspace.root.appendingPathComponent("real/default.store"),
                appGroup: workspace.directory("group"),
                legacy: workspace.directory("legacy")
            ),
            initialize: { try call.initialize($0) }
        )

        #expect(call.urls.count == 1, "expected exactly one store to be opened, got \(call.urls.count)")
        let opened = try #require(call.urls.first)
        #expect(opened.lastPathComponent == Initializer.throwawayStoreFilename)
        #expect(
            opened.deletingLastPathComponent().lastPathComponent
                .hasPrefix(Initializer.throwawayDirectoryPrefix),
            "the store was not inside a directory named for this path: \(opened.path)"
        )
        #expect(
            Initializer.isDescendant(opened, of: temporaryDirectory),
            "the store was opened outside the temporary directory it was given"
        )
        #expect(
            call.directoriesPresentWhenCalled == [true],
            "the throwaway directory did not exist when the schema call was made"
        )
        #expect(outcome == .initialized(path: opened.path))
        #expect(
            !FileManager.default.fileExists(atPath: opened.deletingLastPathComponent().path),
            "the throwaway directory outlived the run"
        )
    }

    /// Two runs never share a store. A fixed name would let one run read the other's mirroring
    /// metadata, which is the only thing that made the old route dangerous.
    @Test func eachRunGetsItsOwnThrowawayDirectory() throws {
        let workspace = try Workspace()
        let temporaryDirectory = workspace.directory("tmp")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let call = SchemaCall()
        let inputs = Self.safety(appGroup: workspace.directory("group"))

        for _ in 0..<2 {
            _ = Initializer.perform(
                environment: [Initializer.environmentKey: "1"],
                temporaryDirectory: temporaryDirectory,
                safety: inputs,
                initialize: { try call.initialize($0) }
            )
        }

        #expect(call.urls.count == 2)
        #expect(Set(call.urls.map(\.path)).count == 2, "two runs shared one throwaway store")
    }

    /// **The refusal is load-bearing inside `perform`, not decoration beside it.**
    ///
    /// The injected `SafetyInputs` name a directory this test owns, so the mutation that proves
    /// this test — deleting the app-group rule from `refusal` — writes into the test's own
    /// temporary tree rather than into the owner's real container.
    @Test func performRefusesWithoutCreatingAnythingWhenTheThrowawayPathIsTheOwnersData() throws {
        let workspace = try Workspace()
        let group = workspace.directory("group")
        let call = SchemaCall()

        let outcome = Initializer.perform(
            environment: [Initializer.environmentKey: "1"],
            temporaryDirectory: group,
            safety: Self.safety(appGroup: group),
            initialize: { try call.initialize($0) }
        )

        guard case let .refused(refusal, path) = outcome else {
            Issue.record("expected a refusal, got \(outcome)")
            return
        }
        #expect(refusal == .insideTheAppGroupContainer)
        #expect(path.hasPrefix(group.path))
        #expect(call.urls.isEmpty, "the schema call was made over \(call.urls.map(\.path))")
        #expect(
            !FileManager.default.fileExists(atPath: group.path),
            "a refused run created a directory inside the container it refused"
        )
        #expect(outcome.exitCode == 1)
    }

    // MARK: - 4. The gate

    @Test func onlyTheExactEnvironmentValueAsksForThis() throws {
        let workspace = try Workspace()
        let temporaryDirectory = workspace.directory("tmp")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let closed: [[String: String]] = [
            [:],
            [Initializer.environmentKey: "0"],
            [Initializer.environmentKey: ""],
            [Initializer.environmentKey: "true"],
            [Initializer.environmentKey: "YES"],
            [Initializer.environmentKey: " 1"],
            [Initializer.environmentKey: "1 "],
            [Initializer.environmentKey.lowercased(): "1"],
            ["CADENCE_LOCAL_STORE_ONLY": "1"],
            ["CADENCE_UI_TEST_MODE": "1", "CADENCE_UI_TEST_STORE_ID": "t15751"],
        ]

        for environment in closed {
            let call = SchemaCall()
            let outcome = Initializer.perform(
                environment: environment,
                temporaryDirectory: temporaryDirectory,
                safety: Self.safety(appGroup: workspace.directory("group")),
                initialize: { try call.initialize($0) }
            )
            #expect(outcome == .notRequested, "\(environment) opened the schema-init path")
            #expect(call.urls.isEmpty)
            #expect(!Initializer.requested(in: environment))
        }

        #expect(Initializer.requested(in: [Initializer.environmentKey: "1"]))
    }

    // MARK: - 5. No Release configuration reaches it

    private static let initializerPath = "Cadence/Services/CadenceCloudKitSchemaInitializer.swift"
    private static let appPath = "Cadence/CadenceApp.swift"
    private static let persistencePath = "Cadence/Services/PersistenceController.swift"

    /// The entry point is `#if DEBUG`, structurally — everything the file declares sits inside one
    /// fence, so a Release build compiles no part of it.
    @Test func theWholeInitializerIsFencedOutOfAReleaseBuild() throws {
        let code = try CadenceCommitSurfaceScan.scanned(Self.initializerPath)
        let directives = code
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#if") || $0.hasPrefix("#else") || $0.hasPrefix("#endif") }

        #expect(
            directives == ["#if DEBUG", "#endif"],
            "\(Self.initializerPath) must be one `#if DEBUG` fence and nothing else; found \(directives)"
        )

        // And the fence encloses the declaration rather than sitting beside it.
        let lines = code.components(separatedBy: "\n")
        let fence = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "#if DEBUG" })
        let end = try #require(lines.lastIndex { $0.trimmingCharacters(in: .whitespaces) == "#endif" })
        let declaration = try #require(
            lines.firstIndex { $0.hasPrefix("enum CadenceCloudKitSchemaInitializer") }
        )
        #expect(fence < declaration && declaration < end)
    }

    /// The one call site, also fenced. Walks upwards for the nearest directive, the same reading
    /// `CadenceCalendarAuthorizationFenceTests` uses: the call is fenced only when the nearest
    /// directive above it is `#if DEBUG` and has not already been closed.
    @Test func theOnlyCallSiteIsFencedAndIsTheFirstStatementOfTheLaunch() throws {
        let code = try CadenceCommitSurfaceScan.scanned(Self.appPath)
        let lines = code.components(separatedBy: "\n")

        let sites = lines.enumerated().filter { $0.element.contains("CadenceCloudKitSchemaInitializer") }
        #expect(sites.count == 1, "expected one call site in \(Self.appPath), found \(sites.count)")
        let site = try #require(sites.first)
        #expect(site.element.contains("runIfRequestedAndExit()"))

        var fence: String?
        var index = site.offset - 1
        while index >= 0 {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#endif") || line.hasPrefix("#if") {
                fence = line
                break
            }
            index -= 1
        }
        #expect(
            fence == "#if DEBUG",
            """
            \(Self.appPath):\(site.offset + 1) — the schema-init entry point is not inside \
            `#if DEBUG` (nearest directive above it: \(fence ?? "none")), so a Release build can \
            reach it.
            """
        )

        // Above every other statement in `init()`: the claim is that this path never opens the
        // app-group store, and a `PersistenceController` touch before it would be true of the
        // statement and false of the launch.
        let initializerIndex = try #require(lines.firstIndex { $0.contains("init() {") })
        let firstStoreTouch = try #require(
            lines.firstIndex { $0.contains("PersistenceController.shared.container") }
        )
        #expect(initializerIndex < site.offset && site.offset < firstStoreTouch)
        let between = lines[(initializerIndex + 1)..<site.offset]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        #expect(between.isEmpty, "statements run before the schema-init gate: \(between)")
    }

    /// `initializeCloudKitSchema` is reachable from exactly one product file. The ticket's own
    /// premise was that `rg initializeCloudKitSchema` answered nothing in this tree; the state
    /// that replaces it is *one* caller, not a second one somewhere unfenced.
    @Test func theCloudKitSchemaCallHasOneProductCallSite() throws {
        let offenders = try CadenceSourceScan.swiftFiles(under: "Cadence")
            .filter { path in
                try CadenceSourceScan.strippingComments(CadenceSourceScan.sourceFile(path))
                    .contains("initializeCloudKitSchema")
            }
        #expect(
            offenders == [Self.initializerPath],
            "`initializeCloudKitSchema` is called from \(offenders)"
        )
    }

    // MARK: - 6. The gate this sits beside is untouched

    /// [[T-3013]]'s store gate still decides the normal launch exactly as it did, and this path is
    /// beside it rather than inside it.
    ///
    /// Source-read rather than behavioural, and deliberately so: `makeContainer()` opens the
    /// signed-in person's store, so there is no calling it from a test. What is checkable is that
    /// its three configurations and the `.developmentBuild` banner still read as themselves, and
    /// that the new path is named nowhere in that file.
    @Test func theSigningGateAndItsBannerAreUnchangedByThisPath() throws {
        let source = try CadenceSourceScan.sourceFile(Self.persistencePath)
        let code = CadenceSourceScan.strippingComments(source)
        let body = try #require(
            CadenceSourceScan.declarationBody("private static func makeContainer(", in: code),
            "PersistenceController.makeContainer did not read as itself"
        )

        #expect(body.contains("if shouldUseLocalStoreOnly {"))
        #expect(body.contains("CadenceSigningEnvironment.currentProcessVerdict().mustOpenLocalStoreOnly"))
        #expect(body.contains("kind: .developmentBuild"))
        #expect(body.contains("message: CadenceSigningEnvironment.localStoreOnlyMessage"))
        #expect(CadenceSourceScan.matchCount(#"cloudKitDatabase: \.none"#, in: body) == 2)
        #expect(
            CadenceSourceScan.matchCount(
                #"cloudKitDatabase: \.private\("iCloud\.com\.haoranwei\.Cadence"\)"#,
                in: body
            ) == 1
        )
        #expect(
            !code.contains("CadenceCloudKitSchemaInitializer"),
            "the schema-init path reached into the store gate instead of sitting beside it"
        )

        // And the gate's own decision, behaviourally — the one value that refuses, still refusing.
        #expect(
            CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: "development")
                .mustOpenLocalStoreOnly
        )
        #expect(
            !CadenceSigningEnvironment.verdict(forPushEnvironmentEntitlement: "production")
                .mustOpenLocalStoreOnly
        )
    }

    /// The two paths publish the same model list, because there is only one.
    @Test func theSchemaAndTheModelListAreTheSameList() {
        #expect(CadenceSchema.schema.entities.count == CadenceSchema.models.count)
        #expect(
            Set(CadenceSchema.schema.entities.map(\.name))
                == Set(CadenceSchema.models.map { String(describing: $0) })
        )
    }
}
