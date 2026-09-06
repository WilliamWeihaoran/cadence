import Foundation

/// The private store a UI-test launch runs against, and the half [[T-1090]] found missing:
/// removing it afterwards.
///
/// Every `XCUIApplication` launch in `CadenceUITests` sets `CADENCE_UI_TEST_STORE_ID` to a fresh
/// UUID, and `PersistenceController.resolvedStoreURL()` turns that into
/// `<app tmp>/CadenceUITestStores/<id>/default.store`. The isolation is right and stays: the point
/// of a per-launch id is that no UI test can reach the user's real store. What was missing is that
/// nothing ever deleted the directory, so a machine accumulated one per launch — 71 of them,
/// ~34 MB, when the backlog was first counted on 2026-09-06.
///
/// ## Why the app does this and not the test
///
/// **The UI-test runner may read the path and may not write it.** Read off the built runner's own
/// signature on 2026-09-06 (`codesign -d --entitlements`), which is more precise than the guess
/// T-1090 filed: `CadenceUITests-Runner.app` carries `com.apple.security.app-sandbox`, and its only
/// filesystem exception is `com.apple.security.temporary-exception.files.absolute-path.read-only`
/// over `/`. So a `tearDown` there could `stat` the app's store and could **not** `removeItem` it —
/// the cleanup would fail on every run, in a target whose runner is separately containerised
/// (`HOME` and `TMPDIR` redirected into
/// `~/Library/Containers/com.haoranwei.Cadence.CadenceUITests.xctrunner/`, measured from inside a
/// live run and written down in `CadenceUITestEnvironment`). The removal is therefore written on
/// the side of the boundary that can perform it. The read-only half is still useful and is the
/// check a future UI run should add: the runner *can* count what is left under the app's container.
///
/// ## Why a launch-time sweep and not a termination hook
///
/// A hook on quit only fires on a graceful quit. A UI test that fails with
/// `continueAfterFailure = false`, or a crash, or `XCUIApplication.terminate()` escalating to a
/// kill, all leave the directory behind — which is a cleanup that works except in the cases that
/// produce the most files. The sweep runs at launch instead, so it also collects what previous
/// runs died holding. The steady state is one directory (this launch's), not zero, and that is the
/// honest claim: the *next* run removes it.
///
/// ## Why it cannot delete a store a concurrent run is using
///
/// This is the hazard T-1090 named, and it is answered by ownership rather than by age. A launch
/// `flock`s `<id>/.owner` for the whole life of the process; the kernel releases that lock when the
/// process exits, however it exits. The sweep removes a sibling **only** when it can take that same
/// lock — i.e. only when no live process holds it. An age heuristic would have had to guess.
///
/// A directory with **no** `.owner` file is left alone, deliberately. It was made by a build from
/// before this mechanism, so nothing can be said about whether a process still has it open; the
/// conservative reading is the one that cannot corrupt a live run. The population that costs is
/// empty — the pre-existing backlog was cleared by hand on 2026-09-06 before this landed — and a
/// directory left for that reason is *reported*, not silently skipped.
///
/// ## What it may report
///
/// `removed` is re-`stat`ed, never assumed. A path is counted as removed only after the filesystem
/// says it is gone, and one that survives its own `removeItem` goes to `failed` and is printed.
/// That rule is the whole point of [[T-1066]]: a cleanup that reports from its intentions rather
/// than from the filesystem is worse than no cleanup, because it also stops anyone looking.
enum CadenceUITestStoreDirectory {

    /// The directory under the app's temporary directory that holds one subdirectory per launch.
    static let rootDirectoryName = "CadenceUITestStores"

    /// The file a live launch holds an exclusive `flock` on for as long as it runs.
    ///
    /// A dotfile so `contentsOfDirectory(.skipsHiddenFiles)` in any other tool does not report it
    /// as a store, and inside the launch's own directory so it is removed with it.
    static let ownerFileName = ".owner"

    /// What one sweep did, in the three outcomes that are actually distinguishable.
    struct SweepReport: Equatable {
        /// Removed, and the filesystem confirmed it afterwards.
        var removed: [String] = []
        /// Left alone: a live process holds the lock, or there is no lock to take a view on.
        var retained: [String] = []
        /// `removeItem` ran and the directory is still there.
        var failed: [String] = []
        /// Whether this launch now holds the lock on the directory it is about to open a store in.
        ///
        /// Only `claimAndSweep` sets it; a bare `sweep` claims nothing and leaves it `false`. It is
        /// reported rather than assumed for the same reason `removed` is: a launch that failed to
        /// take the lock is a launch some *other* live process already owns that id — two writers
        /// on one store — and the sweep would be free to delete it the moment that other process
        /// exits.
        var claimedOwnership: Bool = false

        var isEmpty: Bool { removed.isEmpty && retained.isEmpty && failed.isEmpty }
    }

    /// The descriptors this process holds, keyed by the directory they own.
    ///
    /// Never closed while the app runs — that is what makes the lock mean "a live process". They
    /// are released by the kernel at exit, and `releaseOwnership(in:)` exists for tests, which need
    /// to run several of these in one process.
    private static var ownedDescriptors: [String: Int32] = [:]
    private static let ownedDescriptorsLock = NSLock()

    /// `<temporaryDirectory>/CadenceUITestStores`.
    static func rootDirectory(
        in temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        temporaryDirectory.appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    /// The directory name this launch's store belongs in, or `nil` when it has no private store.
    ///
    /// Every launch that names an id gets the redirect, `run-macos-app.sh`'s included — that is
    /// what keeps an agent's app off the user's real store.
    static func directoryID(in environment: [String: String]) -> String? {
        guard let raw = environment["CADENCE_UI_TEST_STORE_ID"], !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "/", with: "-")
    }

    /// The id whose launch also claims and sweeps — **`CadenceUITests` only**.
    ///
    /// The redirect is wider than the cleanup on purpose. `run-macos-app.sh` sets the store id and
    /// not `CADENCE_UI_TEST_MODE`, and it has a cleanup of its own: its `stop` was rebuilt by
    /// [[T-1066]] to report from the filesystem, and it exits 1 with `!! NOTHING REMOVED` when the
    /// path is not there. A sweep that collected an agent's abandoned store behind its back would
    /// make that refusal fire over a directory something else had already cleaned — turning a guard
    /// that was just made honest into a false alarm. So this mechanism collects only what this
    /// mechanism made, and an agent-run app's directory is left to `stop`.
    ///
    /// Such a directory is safe from the sweep for a second, independent reason: a launch that does
    /// not claim writes no `.owner` file, and `sweep` retains what it cannot take a lock on.
    static func sweepingLaunchID(in environment: [String: String]) -> String? {
        guard environment["CADENCE_UI_TEST_MODE"] == "1" else { return nil }
        return directoryID(in: environment)
    }

    /// Take this launch's directory and sweep every sibling whose owner is gone.
    ///
    /// Idempotent: called twice in one process for one id, it takes the lock once.
    @discardableResult
    static func claimAndSweep(id: String, in root: URL) -> SweepReport {
        guard !id.isEmpty else { return SweepReport() }
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Claimed before the walk, not after: the lock is what keeps another launch's sweep off
        // this directory, and a window between creating it and owning it is a window to lose it in.
        let claimed = takeOwnership(of: directory)
        var report = sweep(in: root, keeping: [id])
        report.claimedOwnership = claimed
        if !report.claimedOwnership {
            print("[CadenceUITestStore] '\(id)' is already owned by a live process; this launch is a second writer")
        }
        report.failed.forEach {
            print("[CadenceUITestStore] could not remove the leaked store '\($0)'; it is still on disk")
        }
        return report
    }

    /// Remove every launch directory under `root` that no live process owns.
    static func sweep(in root: URL, keeping keptIDs: Set<String>) -> SweepReport {
        let fileManager = FileManager.default
        var report = SweepReport()
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return report }

        for entry in entries {
            let id = entry.lastPathComponent
            guard !keptIDs.contains(id) else { continue }
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            guard let descriptor = takeUnownedLock(in: entry) else {
                report.retained.append(id)
                continue
            }
            try? fileManager.removeItem(at: entry)
            close(descriptor)
            // The filesystem answers this, not the `try?` above: a `removeItem` that threw and one
            // that raced another sweeper to the same directory are the same outcome — gone.
            if fileManager.fileExists(atPath: entry.path) {
                report.failed.append(id)
            } else {
                report.removed.append(id)
            }
        }

        report.removed.sort()
        report.retained.sort()
        report.failed.sort()
        return report
    }

    /// Give up this process's claim on everything under `root`. Tests only — the app holds its
    /// lock until it exits, which is the property the sweep reads.
    static func releaseOwnership(in root: URL) {
        ownedDescriptorsLock.lock()
        defer { ownedDescriptorsLock.unlock() }
        for (path, descriptor) in ownedDescriptors where path.hasPrefix(root.path) {
            close(descriptor)
            ownedDescriptors.removeValue(forKey: path)
        }
    }

    // MARK: - The lock

    static func ownerFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(ownerFileName, isDirectory: false)
    }

    /// Open `<directory>/.owner`, creating it, and hold an exclusive lock on it for the rest of the
    /// process's life. `false` when something else already holds it.
    @discardableResult
    private static func takeOwnership(of directory: URL) -> Bool {
        ownedDescriptorsLock.lock()
        defer { ownedDescriptorsLock.unlock() }
        guard ownedDescriptors[directory.path] == nil else { return true }
        let descriptor = open(ownerFileURL(in: directory).path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { return false }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        ownedDescriptors[directory.path] = descriptor
        return true
    }

    /// A descriptor on `<directory>/.owner` when nothing live owns it, `nil` when something does —
    /// **and `nil` when there is no `.owner` file at all**, which is the conservative half.
    ///
    /// `-1` from `open` cannot be read as "free": the two reasons it fails here are a missing file
    /// (a directory from before this mechanism, whose users cannot be enumerated) and a permission
    /// the sandbox refuses (a directory this process cannot see into). Deleting on either would be
    /// deleting on the strength of not having looked.
    private static func takeUnownedLock(in directory: URL) -> Int32? {
        let descriptor = open(ownerFileURL(in: directory).path, O_RDWR)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }
}
