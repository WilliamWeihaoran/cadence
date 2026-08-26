import Foundation
import SwiftData

/// Why a write-capable open of the shared store was refused (T-311).
///
/// These reach the user: an App Intent that throws shows `errorDescription` on the widget, so each
/// case has to name the one thing that fixes it.
nonisolated enum CadenceSharedStoreWriteRefusal: LocalizedError, Equatable {
    /// Cadence has never opened this store, so nobody has run the legacy migration yet.
    case storeNotPrepared
    /// A backup is waiting to replace this store on the next launch.
    case restorePending

    var errorDescription: String? {
        switch self {
        case .storeNotPrepared:
            return "Open Cadence once so it can finish setting up your data. Until then, widgets can show it but not change it."
        case .restorePending:
            return "Open Cadence to finish restoring your backup. Changes made from a widget now would be replaced by the restore."
        }
    }
}

nonisolated enum CadenceStoreSupport {
    nonisolated static let appContainerIdentifier = "com.haoranwei.Cadence"
    nonisolated static let appGroupIdentifier = "group.com.haoranwei.Cadence"
    nonisolated static let storeDirectoryName = "Cadence"
    nonisolated static let storeFilename = "default.store"
    nonisolated static let managedStoreItemNames = [
        storeFilename,
        "default.store-wal",
        "default.store-shm",
        ".default_SUPPORT",
        "default_ckAssets",
    ]

    nonisolated static func primaryStoreDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        try sharedStoreDirectoryURL(fileManager: fileManager)
    }

    nonisolated static func sharedStoreDirectoryURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        let baseURL: URL
        if let containerURL {
            baseURL = containerURL
        } else if let groupContainerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            baseURL = groupContainerURL
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        let storeDirectoryURL = baseURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(storeDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        return storeDirectoryURL
    }

    nonisolated static func primaryStoreURL(fileManager: FileManager = .default) throws -> URL {
        try primaryStoreDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(storeFilename)
    }

    nonisolated static func makePrimaryContainer(
        allowsSave: Bool,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none,
        storeURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? primaryStoreURL(fileManager: fileManager)
        let configuration = ModelConfiguration(
            "Cadence",
            schema: CadenceSchema.schema,
            url: resolvedStoreURL,
            allowsSave: allowsSave,
            cloudKitDatabase: cloudKitDatabase
        )
        return try ModelContainer(for: CadenceSchema.schema, configurations: [configuration])
    }

    // MARK: - Out-of-process writes

    /// The one door every write-capable open of the shared store outside the app's own startup
    /// goes through.
    ///
    /// **T-311.** A read-only open of a missing store fails and leaves the directory empty; a
    /// write-capable open *creates* it. The three App Intents below `perform()` in the widget
    /// extension, which never runs `PersistenceController.init` — so before T-311 the first
    /// widget button tap after an update could create `default.store` in the app group, and
    /// `migrateLegacyStoreIfNeeded` would then find a non-empty directory and decline to copy the
    /// user's legacy store into it. The migration was skipped, permanently, and nothing said so.
    ///
    /// The gate refuses instead of preparing the store itself, because an extension cannot do what
    /// preparing it means:
    ///
    /// - The legacy store sits in the **app's** container (`~/Library/Containers/
    ///   com.haoranwei.Cadence/Data/...`). A widget extension is a separate sandboxed process with
    ///   its own container and no right to read that path, so a migration run from there would find
    ///   nothing, report success, and create the empty store anyway — today's bug with more code
    ///   in front of it.
    /// - A pending restore is recorded in `UserDefaults.standard`, which the extension does not
    ///   share, and applying one stages and swaps whole store directories. That is not something a
    ///   second process should be doing behind the app's back.
    /// - There is no `SchemaMigrationPlan` in this project, so whichever process first creates the
    ///   store is the one that writes its version on disk. Keeping creation in exactly one process
    ///   is the conservative invariant, not an incidental one.
    ///
    /// What a refusal costs is a widget button that does nothing until Cadence has been opened once
    /// — at which point there was nothing in the widget to tap anyway, since the read side already
    /// declines to create the store.
    nonisolated static func preflightSharedStoreWrite(
        storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws {
        // Deliberately the same predicate `migrateLegacyStoreIfNeeded` guards on, so the two are
        // exact complements: this refuses in precisely the states where that would still migrate.
        guard !storeItemURLs(in: storeDirectoryURL, fileManager: fileManager).isEmpty else {
            throw CadenceSharedStoreWriteRefusal.storeNotPrepared
        }
        guard !restoreIsPending(inStoreDirectory: storeDirectoryURL, fileManager: fileManager) else {
            throw CadenceSharedStoreWriteRefusal.restorePending
        }
    }

    /// A write-capable container for the shared store, opened only if the store is already there.
    nonisolated static func makeSharedWriteContainer(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none,
        storeDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        let directoryURL = try storeDirectoryURL ?? primaryStoreDirectoryURL(fileManager: fileManager)
        try preflightSharedStoreWrite(storeDirectoryURL: directoryURL, fileManager: fileManager)
        return try makePrimaryContainer(
            allowsSave: true,
            cloudKitDatabase: cloudKitDatabase,
            storeURL: directoryURL.appendingPathComponent(storeFilename),
            fileManager: fileManager
        )
    }

    /// A restore the user scheduled and the app has not applied yet, recorded where a second
    /// process can see it.
    ///
    /// The scheduled restore itself lives in `UserDefaults.standard`, which the widget extension
    /// does not share, so a file beside the store is what makes it visible across the app group.
    /// The name is not in `managedStoreItemNames`, so no backup, restore, migration or store-item
    /// scan ever mistakes it for part of the store.
    nonisolated static let restorePendingMarkerName = ".cadence-restore-pending"

    nonisolated static func restorePendingMarkerURL(inStoreDirectory storeDirectoryURL: URL) -> URL {
        storeDirectoryURL.appendingPathComponent(restorePendingMarkerName)
    }

    nonisolated static func restoreIsPending(
        inStoreDirectory storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: restorePendingMarkerURL(inStoreDirectory: storeDirectoryURL).path)
    }

    nonisolated static func setRestorePending(
        _ pending: Bool,
        inStoreDirectory storeDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        let markerURL = restorePendingMarkerURL(inStoreDirectory: storeDirectoryURL)
        if pending {
            try? fileManager.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
            fileManager.createFile(atPath: markerURL.path, contents: Data())
        } else {
            try? fileManager.removeItem(at: markerURL)
        }
    }

    /// The marker a process that is **not** the app touches after it saves to the shared store,
    /// so the app knows to adopt the write.
    ///
    /// The name is historical — the MCP server was the first such process — and is left alone
    /// because renaming it would strand the marker an already-installed app is watching. Like
    /// `restorePendingMarkerName` it is deliberately absent from `managedStoreItemNames`, so no
    /// backup, restore, migration or store-item scan mistakes it for part of the store.
    nonisolated static let externalWriteMarkerFilename = ".cadence-mcp-refresh"

    nonisolated static func externalWriteMarkerURL(besideStoreAt storeURL: URL) -> URL {
        storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(externalWriteMarkerFilename)
    }

    /// Records "another process just wrote to this store" beside `storeURL`.
    ///
    /// **This lives here, in the one file every out-of-process target compiles, on purpose.** The
    /// app group has two writers that are not the app — the MCP server and the widget extension
    /// running an App Intent — and neither of them may reconcile OS notifications itself:
    /// `NotificationManager.reconcile` reads `notificationsEnabled` out of `UserDefaults.standard`,
    /// which is per-process, so the extension would read its own empty defaults, conclude
    /// notifications are off, and cancel every reminder the app had scheduled. It is the same
    /// per-process-defaults problem `restorePendingMarkerName` above exists for, and it gets the
    /// same answer: a file in the app group. They post; the app, the one process that can see that
    /// setting, reconciles when it adopts the write. `docs/TODO.md` T-306 and T-312.
    ///
    /// Truncate-and-rewrite rather than create-and-replace: `CadenceMCPRefreshCoordinator` watches
    /// this path through a `DispatchSource` holding an open descriptor, and replacing the file
    /// would leave that descriptor pointed at an unlinked inode — a watcher that never fires again.
    /// Returns whether the marker was actually written.
    @discardableResult
    nonisolated static func postExternalWrite(
        besideStoreAt storeURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Bool {
        let markerURL = externalWriteMarkerURL(besideStoreAt: storeURL)
        let data = Data(ISO8601DateFormatter().string(from: now).utf8)

        if fileManager.fileExists(atPath: markerURL.path),
           let handle = try? FileHandle(forWritingTo: markerURL) {
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: data)
            try? handle.close()
            return true
        }
        return fileManager.createFile(atPath: markerURL.path, contents: data)
    }

    nonisolated static func legacyStoreCandidateDirectories(
        homeDirectoryURL: URL = userHomeDirectory
    ) -> [URL] {
        var seenPaths: Set<String> = []
        return [
            homeDirectoryURL
                .appendingPathComponent("Library/Containers", isDirectory: true)
                .appendingPathComponent(appContainerIdentifier, isDirectory: true)
                .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
                .appendingPathComponent(storeDirectoryName, isDirectory: true),
            homeDirectoryURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(storeDirectoryName, isDirectory: true),
        ]
        .filter { candidate in
            seenPaths.insert(candidate.standardizedFileURL.path).inserted
        }
    }

    @discardableResult
    nonisolated static func migrateLegacyStoreIfNeeded(
        appGroupDirectoryURL: URL,
        candidateLegacyDirectories: [URL],
        fileManager: FileManager = .default,
        backupHandler: ((URL) throws -> Void)? = nil
    ) throws -> URL? {
        try fileManager.createDirectory(at: appGroupDirectoryURL, withIntermediateDirectories: true)
        guard storeItemURLs(in: appGroupDirectoryURL, fileManager: fileManager).isEmpty else {
            return nil
        }

        for legacyDirectory in candidateLegacyDirectories {
            let legacyItems = storeItemURLs(in: legacyDirectory, fileManager: fileManager)
            guard !legacyItems.isEmpty else { continue }

            try backupHandler?(legacyDirectory)

            do {
                for sourceURL in legacyItems {
                    let destinationURL = appGroupDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
                return legacyDirectory
            } catch {
                for sourceURL in legacyItems {
                    let destinationURL = appGroupDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
                    try? fileManager.removeItem(at: destinationURL)
                }
                throw error
            }
        }

        return nil
    }

    nonisolated static func storeItemURLs(in directoryURL: URL, fileManager: FileManager = .default) -> [URL] {
        managedStoreItemNames
            .map { directoryURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    /// macOS is the one platform where the process home and the *user's* home differ: under the App
    /// Sandbox `NSHomeDirectory()` is the container, and only `homeDirectoryForCurrentUser` reaches
    /// `~`. Everywhere else the container **is** the home.
    ///
    /// Spelled as macOS-or-not rather than by listing platforms. It used to read
    /// `#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)`, and this app builds two of those
    /// six names — so three of the four listed compiled to nothing, while implying targets that do
    /// not exist. This way a platform added later is right by default rather than by remembering
    /// to name it here.
    private nonisolated static var userHomeDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }
}
