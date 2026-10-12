import Foundation
import Testing
@testable import Cadence

/// `CadenceStoreSupport.preflightSharedStoreWrite`, driven directly ([[T-3132]]).
///
/// `CadenceSharedStoreWriteGateTests` reaches the gate only through `makeSharedWriteContainer`
/// and a real SwiftData store, so each of its refusals is asserted once, in one state. This suite
/// asks the gate itself, state by state, which reason it refuses with — including the precedence
/// between the two refusals and the store items that count as "prepared" — with nothing but empty
/// placeholder files: the gate is an existence check, and a placeholder is what proves that.
///
/// Every directory here is a fresh child of `FileManager.default.temporaryDirectory`, and
/// `makeTemporaryDirectory()` asserts so before a test may use it. Nothing in this file names, or
/// composes, the app-group store location.
struct CadenceSharedStoreWritePreflightTests {
    // MARK: - Fixtures

    private func makeTemporaryDirectory(create: Bool = true) throws -> URL {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
        let url = temporaryRoot
            .appendingPathComponent("CadenceSharedStoreWritePreflightTests.\(UUID().uuidString)", isDirectory: true)
        let path = url.standardizedFileURL.path
        #expect(path.hasPrefix(temporaryRoot.path + "/"), "\(path) is not under the temporary directory")
        #expect(!path.contains("/Library/Application Support"), "\(path) reaches a store location")
        #expect(!path.contains("Group Containers"), "\(path) reaches an app group")
        #expect(!path.contains("Cadence Store Backups"), "\(path) reaches a backup directory")
        if create {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func touch(_ name: String, in directoryURL: URL) {
        #expect(FileManager.default.createFile(atPath: directoryURL.appendingPathComponent(name).path, contents: Data()))
    }

    private func directoryContents(_ directoryURL: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []).sorted()
    }

    /// The reason the gate refused with, or `nil` when it let the write through. Any other error is
    /// a failure of its own, not a `nil`.
    private func refusal(_ directoryURL: URL) throws -> CadenceSharedStoreWriteRefusal? {
        do {
            try CadenceStoreSupport.preflightSharedStoreWrite(storeDirectoryURL: directoryURL)
            return nil
        } catch let refusal as CadenceSharedStoreWriteRefusal {
            return refusal
        }
    }

    // MARK: - storeNotPrepared

    @Test func anEmptyStoreDirectoryIsRefusedAsNotPreparedAndLeftEmpty() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try refusal(directory) == .storeNotPrepared)
        #expect(directoryContents(directory).isEmpty)
    }

    @Test func aMissingStoreDirectoryIsRefusedAsNotPreparedAndIsNotCreated() throws {
        let directory = try makeTemporaryDirectory(create: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try refusal(directory) == .storeNotPrepared)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// A file that is not one of `managedStoreItemNames` is not a store, so a directory holding one
    /// is still unprepared — the predicate `migrateLegacyStoreIfNeeded` guards on, not "non-empty".
    @Test func aDirectoryHoldingOnlyFilesThatAreNotStoreItemsIsStillNotPrepared() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        touch(CadenceStoreSupport.externalWriteMarkerFilename, in: directory)
        touch("unrelated.txt", in: directory)

        #expect(try refusal(directory) == .storeNotPrepared)
        #expect(directoryContents(directory).count == 2)
    }

    /// With no store **and** a restore marker, the store is the thing to name: the restore cannot
    /// be what fixes a store that was never set up, and the first guard runs first.
    @Test func notPreparedTakesPrecedenceOverAPendingRestore() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        CadenceStoreSupport.setRestorePending(true, inStoreDirectory: directory)
        #expect(CadenceStoreSupport.restoreIsPending(inStoreDirectory: directory))

        #expect(try refusal(directory) == .storeNotPrepared)
    }

    // MARK: - restorePending

    @Test func aPreparedStoreWithARestorePendingIsRefusedAsRestorePending() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        touch(CadenceStoreSupport.storeFilename, in: directory)
        CadenceStoreSupport.setRestorePending(true, inStoreDirectory: directory)

        #expect(try refusal(directory) == .restorePending)
        // The refusal neither consumed the marker nor touched the store.
        #expect(CadenceStoreSupport.restoreIsPending(inStoreDirectory: directory))
        #expect(directoryContents(directory) == [CadenceStoreSupport.restorePendingMarkerName, CadenceStoreSupport.storeFilename].sorted())
    }

    // MARK: - The allow path

    @Test func aPreparedStoreWithNoRestorePendingIsAllowed() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        touch(CadenceStoreSupport.storeFilename, in: directory)

        #expect(try refusal(directory) == nil)
        #expect(directoryContents(directory) == [CadenceStoreSupport.storeFilename])
    }

    @Test func clearingTheRestoreMarkerAllowsTheWriteAgain() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        touch(CadenceStoreSupport.storeFilename, in: directory)

        CadenceStoreSupport.setRestorePending(true, inStoreDirectory: directory)
        #expect(try refusal(directory) == .restorePending)
        CadenceStoreSupport.setRestorePending(false, inStoreDirectory: directory)
        #expect(try refusal(directory) == nil)
    }

    /// Any one managed store item is enough, so a store mid-checkpoint (only `-wal`, say) is not
    /// mistaken for a missing one. Counted, so an empty `managedStoreItemNames` cannot pass.
    @Test func everyManagedStoreItemOnItsOwnCountsAsAPreparedStore() throws {
        var allowed = 0
        var refusedAsPending = 0
        for name in CadenceStoreSupport.managedStoreItemNames {
            let directory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            touch(name, in: directory)
            if try refusal(directory) == nil { allowed += 1 }

            CadenceStoreSupport.setRestorePending(true, inStoreDirectory: directory)
            if try refusal(directory) == .restorePending { refusedAsPending += 1 }
        }
        #expect(CadenceStoreSupport.managedStoreItemNames.count == 5)
        #expect(allowed == CadenceStoreSupport.managedStoreItemNames.count)
        #expect(refusedAsPending == CadenceStoreSupport.managedStoreItemNames.count)
    }
}
