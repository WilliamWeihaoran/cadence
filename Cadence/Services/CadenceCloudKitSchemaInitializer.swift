import CloudKit
import CoreData
import Foundation
import SwiftData
import os

#if DEBUG

/// Publish this app's CloudKit schema to the **Development** environment, from a throwaway store.
///
/// ## Why this exists at all
///
/// SwiftData used to teach Development its own schema: a debug build ran, mirrored, and
/// `NSPersistentCloudKitContainer` created each record type and column in the Development database
/// as a side effect. The owner then pressed *Deploy Schema Changes* in the CloudKit Console to
/// promote it to Production. [[T-3013]] ended that, deliberately and correctly — a development
/// signed build opening the signed-in person's real app-group store with mirroring on stamps their
/// real records as already exported to Development, and those records then never reach Production
/// ([[T-2053]], four weeks of the owner's Mac not reaching their iPad). Since that commit no debug
/// build of this app mirrors anything, so **nothing in this tree can teach Development a new record
/// type or field** ([[T-15750]]), and the owner has to hand-add each one in the Console before every
/// deploy. [[T-15700]] is what that costs in practice: three fields on the note record type, typed
/// one at a time, invisible to code review.
///
/// ## Why it is safe where reviving the old route is not
///
/// Apple's intended mechanism needs no user data and no mirroring run. `initializeCloudKitSchema`
/// derives the schema from the managed object model, pushes a throwaway record of each type to
/// prove the type exists, and deletes it again. The risk in [[T-3013]] is not CloudKit — it is the
/// **store**: a real store mirrored from a development-signed build carries export metadata that
/// Production then believes. A store this process created seconds ago under `tmp`, which has never
/// held a row of the owner's and is deleted when the process exits, carries that risk nowhere.
///
/// **So the whole safety argument reduces to one claim: this never opens the app-group store.**
/// `refusal(forStoreURL:…)` is that claim as code rather than as care, and
/// `CadenceCloudKitSchemaInitializerTests` is it as tests. `PersistenceController.makeContainer()`
/// and `CadenceSigningEnvironment` are untouched; this is a separate path beside that gate, not a
/// widening of it, and it is `#if DEBUG` so no Release configuration compiles it at all.
///
/// ## How the owner runs it
///
/// A development-signed Debug build, on their own Mac, with
/// `CADENCE_INITIALIZE_CLOUDKIT_SCHEMA=1` in the environment — the Xcode scheme's Run action, or
/// `env CADENCE_INITIALIZE_CLOUDKIT_SCHEMA=1 open -W <Debug>/Cadence.app`. It prints one line and
/// exits before any window is made. **Not** `scripts/run-macos-app.sh`, which forces
/// `CADENCE_LOCAL_STORE_ONLY=1` and therefore has no CloudKit container to publish to.
///
/// ## Deviation from the shape [[T-15751]] asked for
///
/// The ticket describes opening the temporary store through SwiftData with
/// `cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")`. SwiftData's `ModelContainer`
/// exposes no `initializeCloudKitSchema`, so the Core Data container is the only route to the call:
/// `NSManagedObjectModel.makeManagedObjectModel(for:)` over the same `CadenceSchema.models` list,
/// then `NSPersistentCloudKitContainer` with `NSPersistentCloudKitContainerOptions` scoped to the
/// private database. Same container identifier, same model, same one authoritative type list.
/// Main-actor isolated rather than `nonisolated`, which is this target's default and is what the
/// one caller is: `App.init()`. `PersistenceController.resolvedStoreURL()` is main-actor isolated
/// too, and the alternative — a `nonisolated` enum reaching across to it — is the warning this
/// target's baseline refuses.
enum CadenceCloudKitSchemaInitializer {

    /// The gate. Nothing below runs for any other value, and nothing reads a launch argument — the
    /// environment is what an Xcode scheme, `env` and `SIMCTL_CHILD_*` all agree on.
    static let environmentKey = "CADENCE_INITIALIZE_CLOUDKIT_SCHEMA"

    /// The same container `PersistenceController.makeContainer()` mirrors the real store into. A
    /// development-signed build reaches its **Development** environment, which is the whole point.
    static let cloudKitContainerIdentifier = "iCloud.com.haoranwei.Cadence"

    /// The throwaway directory's name carries this prefix and a fresh UUID, so it can never be an
    /// existing store directory, a `Recovery/` folder, or another run of this same path.
    static let throwawayDirectoryPrefix = "CadenceCloudKitSchemaInit-"

    static let throwawayStoreFilename = "schema-init.store"

    private static let logger = Logger(
        subsystem: "com.haoranwei.Cadence",
        category: "CloudKitSchemaInit"
    )

    // MARK: - The refusal

    /// Why a candidate store URL was rejected. Every case is a way of being the signed-in person's
    /// data rather than a throwaway.
    enum Refusal: String, Equatable, CaseIterable {
        /// Exactly the store this launch would otherwise open — `PersistenceController`'s answer.
        case isTheStoreThisLaunchWouldOpen
        /// Anywhere inside `group.com.haoranwei.Cadence`: the real store, its WAL, its
        /// `Recovery/` store and every local backup live under there.
        case insideTheAppGroupContainer
        /// Anywhere inside `~/Library/Application Support/Cadence`, which is the legacy
        /// pre-app-group store location and still a recovery-export candidate.
        case insideTheLegacyApplicationSupportStore
        /// Not inside the directory this run created. The positive half: a store that is not
        /// somewhere this process just made is not a throwaway, whatever else it is or is not.
        case notInsideThisRunsThrowawayDirectory
    }

    /// **The one safety claim, as a pure function.**
    ///
    /// Order is deliberate: the three "never" rules are asked before the positive one, so a URL
    /// that is both the real store and outside the throwaway directory reports *which store it is*
    /// rather than the generic refusal. A `nil` answer is the only thing `perform` will open.
    ///
    /// Every comparison resolves symlinks and standardizes first — `/var` and `/private/var` name
    /// one directory on macOS, and a prefix test on unresolved strings answers "not inside" for the
    /// app-group container every time it is handed the resolved form of itself. Containment is a
    /// path-**component** prefix, never a string prefix: `…/Cadence-other` is not inside
    /// `…/Cadence`.
    static func refusal(
        forStoreURL candidate: URL,
        storeThisLaunchWouldOpen: URL?,
        appGroupContainerURL: URL?,
        legacyApplicationSupportStoreDirectoryURL: URL?,
        throwawayDirectoryURL: URL?
    ) -> Refusal? {
        if let storeThisLaunchWouldOpen, isSamePath(candidate, storeThisLaunchWouldOpen) {
            return .isTheStoreThisLaunchWouldOpen
        }
        if let appGroupContainerURL,
           isSamePath(candidate, appGroupContainerURL) || isDescendant(candidate, of: appGroupContainerURL) {
            return .insideTheAppGroupContainer
        }
        if let legacyApplicationSupportStoreDirectoryURL,
           isSamePath(candidate, legacyApplicationSupportStoreDirectoryURL)
            || isDescendant(candidate, of: legacyApplicationSupportStoreDirectoryURL) {
            return .insideTheLegacyApplicationSupportStore
        }
        guard let throwawayDirectoryURL, isDescendant(candidate, of: throwawayDirectoryURL) else {
            return .notInsideThisRunsThrowawayDirectory
        }
        return nil
    }

    /// The three places the signed-in person's data actually is, gathered once per run.
    ///
    /// A value rather than three parameters so a test can replace the whole set with directories
    /// of its own: a test that drives `perform` into a refusal with the *live* set would, the
    /// moment the refusal were removed, create a directory inside the owner's real app-group
    /// container to prove it. Injecting them means the worst a broken refusal can do under test is
    /// write into the test's own temporary tree.
    struct SafetyInputs {
        var storeThisLaunchWouldOpen: URL?
        var appGroupContainerURL: URL?
        var legacyApplicationSupportStoreDirectoryURL: URL?

        static func live(fileManager: FileManager = .default) -> SafetyInputs {
            SafetyInputs(
                // Composed, never created: `resolvedStoreURL()` is the one resolver the store and
                // its backups both ask ([[T-1530]]), so this asks it rather than spelling the
                // app-group path a second time.
                storeThisLaunchWouldOpen: try? PersistenceController.resolvedStoreURL(),
                appGroupContainerURL: fileManager.containerURL(
                    forSecurityApplicationGroupIdentifier: CadenceStoreSupport.appGroupIdentifier
                ),
                legacyApplicationSupportStoreDirectoryURL: fileManager
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first?
                    .appendingPathComponent(
                        CadenceStoreSupport.storeDirectoryName,
                        isDirectory: true
                    )
            )
        }
    }

    /// The same question asked of a gathered set.
    static func refusal(
        forStoreURL candidate: URL,
        safety: SafetyInputs,
        throwawayDirectoryURL: URL?
    ) -> Refusal? {
        refusal(
            forStoreURL: candidate,
            storeThisLaunchWouldOpen: safety.storeThisLaunchWouldOpen,
            appGroupContainerURL: safety.appGroupContainerURL,
            legacyApplicationSupportStoreDirectoryURL: safety.legacyApplicationSupportStoreDirectoryURL,
            throwawayDirectoryURL: throwawayDirectoryURL
        )
    }

    // MARK: - Path arithmetic

    static func normalizedComponents(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath()
            .standardizedFileURL
            .pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
    }

    static func isSamePath(_ one: URL, _ other: URL) -> Bool {
        normalizedComponents(one) == normalizedComponents(other)
    }

    static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let candidateComponents = normalizedComponents(candidate)
        let directoryComponents = normalizedComponents(directory)
        guard !directoryComponents.isEmpty,
              candidateComponents.count > directoryComponents.count else { return false }
        return Array(candidateComponents.prefix(directoryComponents.count)) == directoryComponents
    }

    // MARK: - Running it

    static func requested(in environment: [String: String]) -> Bool {
        environment[environmentKey] == "1"
    }

    enum Outcome: Equatable {
        case notRequested
        case refused(Refusal, path: String)
        case failed(String)
        case initialized(path: String)

        var summary: String {
            switch self {
            case .notRequested:
                return "CloudKit schema init: not requested."
            case let .refused(refusal, path):
                return """
                    CloudKit schema init REFUSED (\(refusal.rawValue)): \(path). This path exists so \
                    the Development schema can be published from a store that has never held your \
                    data; it will not open one that has.
                    """
            case let .failed(reason):
                return "CloudKit schema init FAILED: \(reason)"
            case let .initialized(path):
                return """
                    CloudKit schema init OK: published \(CadenceSchema.models.count) record types to \
                    the Development environment of \(cloudKitContainerIdentifier) from \(path). \
                    Now press Deploy Schema Changes in the CloudKit Console.
                    """
            }
        }

        var exitCode: Int32 {
            switch self {
            case .notRequested, .initialized: return 0
            case .refused, .failed: return 1
            }
        }
    }

    /// Everything except the exit, with the CloudKit call injected.
    ///
    /// `initialize` has **no default** on purpose: a test drives this whole flow — the directory,
    /// the refusal, the URL that is actually handed on — with a closure that touches no network,
    /// and a defaulted real call is how one of those tests would quietly reach the owner's
    /// container instead.
    static func perform(
        environment: [String: String],
        fileManager: FileManager = .default,
        temporaryDirectory: URL? = nil,
        safety: SafetyInputs? = nil,
        initialize: @MainActor (URL) throws -> Void
    ) -> Outcome {
        guard requested(in: environment) else { return .notRequested }

        let throwawayDirectoryURL = (temporaryDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(throwawayDirectoryPrefix + UUID().uuidString, isDirectory: true)
        let storeURL = throwawayDirectoryURL.appendingPathComponent(throwawayStoreFilename)

        if let refusal = refusal(
            forStoreURL: storeURL,
            safety: safety ?? .live(fileManager: fileManager),
            throwawayDirectoryURL: throwawayDirectoryURL
        ) {
            return .refused(refusal, path: storeURL.path)
        }

        do {
            try fileManager.createDirectory(
                at: throwawayDirectoryURL,
                withIntermediateDirectories: true
            )
            defer { try? fileManager.removeItem(at: throwawayDirectoryURL) }
            try initialize(storeURL)
            return .initialized(path: storeURL.path)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The app's one entry point. Returns when the gate is closed; otherwise prints and exits
    /// without a window ever being made.
    static func runIfRequestedAndExit(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard requested(in: environment) else { return }
        let outcome = perform(
            environment: environment,
            initialize: { try Self.publishSchema(fromStoreAt: $0) }
        )
        // Both, and for different readers: `print` is what someone running this from a terminal or
        // the Xcode console sees, and the log is what survives when neither is attached.
        print(outcome.summary)
        logger.log("\(outcome.summary, privacy: .public)")
        exit(outcome.exitCode)
    }

    // MARK: - The CloudKit call

    enum Failure: LocalizedError {
        case managedObjectModelUnavailable

        var errorDescription: String? {
            switch self {
            case .managedObjectModelUnavailable:
                return "NSManagedObjectModel.makeManagedObjectModel(for:) answered nil for CadenceSchema.models"
            }
        }
    }

    /// The real thing, over a store URL `perform` has already cleared.
    static func publishSchema(fromStoreAt storeURL: URL) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: CadenceSchema.models) else {
            throw Failure.managedObjectModelUnavailable
        }

        let description = NSPersistentStoreDescription(url: storeURL)
        // Synchronous: the completion below has to have run before `initializeCloudKitSchema` is
        // asked anything, and this is the default rather than a change of behaviour.
        description.shouldAddStoreAsynchronously = false
        // Mirroring refuses a store without both of these, and refuses it at load time, which
        // would read here as a schema failure rather than as a missing option.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        let options = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        options.databaseScope = .private
        description.cloudKitContainerOptions = options

        let container = NSPersistentCloudKitContainer(
            name: "CadenceSchemaInit",
            managedObjectModel: model
        )
        container.persistentStoreDescriptions = [description]

        var loadFailure: Error?
        container.loadPersistentStores { _, error in loadFailure = error }
        if let loadFailure { throw loadFailure }

        try container.initializeCloudKitSchema(options: [])
    }
}

#endif
