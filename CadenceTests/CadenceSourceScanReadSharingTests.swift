import Foundation
import Testing

/// **[[T-3242]]: one run reads the tree once.**
///
/// The sweep helpers in `CadenceSourceScanSupport` re-read the same ~1,100 files once per test.
/// [[T-3261]] measured that and left it alone on the strength of its cost — **21,462** `sourceFile`
/// calls for **1.2 s** in all, against the 230 s of pure derivation it did cache. That number is
/// true on a warm page cache with the machine idle, and the failure this ticket is about happens on
/// a machine that is anything but: a sweep test failed after **267.688 s** with
/// `NSPOSIXErrorDomain Code=60 "Operation timed out"` on one `Cadence/Shared/` file, with six xcb
/// legs contending for the disk, Xcode open and `bird`/`fileproviderd` working an iCloud-backed
/// tree. The identical rerun passed in 49.8 s. A plain `python3` walk reading the same 631 files
/// took **2m14.9s at 0% CPU** — pure I/O wait — while a single `wc -c` on the file that timed out
/// took 0.002 s. What stalls is sustained re-reading, so what this change removes is not CPU: it is
/// ~20,000 opportunities to be the read that blocks. The owner chose this over capping how many
/// sweeps run concurrently (2026-10-22), because a cap lowers throughput permanently and the
/// timeout returns whenever the machine is busy anyway.
///
/// **What is asserted here is the sharing and its one boundary**, not a duration. A duration
/// measured in this target would be a figure about this Mac's afternoon. The count that answers the
/// ticket — reads performed against reads asked for — is in `CadenceSourceScan.ioCensus`, which
/// every run prints at exit.
struct CadenceSourceScanReadSharingTests {

    // MARK: - A path read once is not read again

    /// The read is injected, so this counts it directly rather than watching a census delta while
    /// the rest of the target reads files on other threads. The key is a path no file has.
    @Test func aPathReadOnceIsNeverReadFromDiskAgain() throws {
        let key = "T-3242/read-sharing/\(UUID().uuidString).swift"
        var reads = 0

        let first = CadenceSourceScan.cachedSourceText(for: key) { _ in
            reads += 1
            return "the one reading"
        }
        let second = CadenceSourceScan.cachedSourceText(for: key) { _ in
            reads += 1
            return "a second reading, which must never be asked for"
        }

        #expect(reads == 1, "the second call went to disk again")
        #expect(first == "the one reading")
        #expect(second == first, "the second call did not get the cached reading")
    }

    /// Two paths are two entries: a cache that answered every key from one reading would pass the
    /// test above and break every census in this target.
    @Test func twoPathsAreTwoReadings() throws {
        let stem = UUID().uuidString
        var reads = 0
        let readerFor: (String) -> (String) -> String = { body in
            { _ in
                reads += 1
                return body
            }
        }

        let a = CadenceSourceScan.cachedSourceText(for: "T-3242/\(stem)/a.swift", read: readerFor("A"))
        let b = CadenceSourceScan.cachedSourceText(for: "T-3242/\(stem)/b.swift", read: readerFor("B"))

        #expect(reads == 2)
        #expect(a == "A")
        #expect(b == "B")
    }

    /// The same for a directory enumeration, which is the other half of what a sweep costs.
    @Test func aSubtreeWalkedOnceIsNeverWalkedAgain() throws {
        let key = "T-3242/walk-sharing/\(UUID().uuidString)"
        var walks = 0

        let first = CadenceSourceScan.cachedSubtreeWalk(for: key) { _ in
            walks += 1
            return ["\(key)/One.swift"]
        }
        let second = CadenceSourceScan.cachedSubtreeWalk(for: key) { _ in
            walks += 1
            return []
        }

        #expect(walks == 1, "the second call enumerated the directory again")
        #expect(first == ["\(key)/One.swift"])
        #expect(second == first)
    }

    // MARK: - The real helpers answer the same thing twice

    /// Not a tautology against the memo above: this is the assertion that the memo is actually
    /// wired into the helper every sweep calls, over a real path and a real subtree.
    @Test func theRealHelpersAreStableAcrossTwoCalls() throws {
        let text = try CadenceSourceScan.sourceFile("CadenceTests/CadenceSourceScanSupport.swift")
        #expect(text.contains("cachedSourceText"), "the read is no longer routed through the memo")
        #expect(try CadenceSourceScan.sourceFile("CadenceTests/CadenceSourceScanSupport.swift") == text)

        let widgets = try CadenceSourceScan.swiftFiles(under: "CadenceWidgets")
        #expect(!widgets.isEmpty, "the walk read nothing, so this proves nothing")
        #expect(try CadenceSourceScan.swiftFiles(under: "CadenceWidgets") == widgets)
    }

    /// Asked for more than it performed, and never the other way round. A relation, not a figure:
    /// the absolute counts depend on which suites this run scheduled.
    @Test func theCensusNeverPerformsMoreIOThanItWasAskedFor() throws {
        _ = try CadenceSourceScan.sourceFile("AGENTS.md")
        _ = try CadenceSourceScan.files(under: "CadenceWidgets")

        let counts = CadenceSourceScan.ioCensus.counts
        #expect(counts.sourceFileCalls > 0, "the census counted nothing, so it is measuring nothing")
        #expect(counts.sourceFileReads <= counts.sourceFileCalls)
        #expect(counts.walks <= counts.walkCalls)
        #expect(CadenceSourceScan.ioCensus.summary.contains("SCAN-IO-CENSUS reads="))

        // Point-in-time, and said so: the run's own figure is the line `atexit` prints after the
        // summary. This one is the backstop that proves the instrument reaches the log at all.
        print("SCAN-IO-CENSUS (point-in-time, \(#function)) \(CadenceSourceScan.ioCensus.summary)")
    }

    // MARK: - The boundary: a tree this target built itself is never shared

    /// **The one place the path key would be wrong.** `repositoryPaths(under:)` is also handed
    /// fixture trees built under `temporaryDirectory` moments earlier, and the reader tests walk
    /// such a root, change it, and walk it again — which is the whole of what they assert. Caching
    /// by root path would answer the second walk from the first and let those tests pass without
    /// reading anything.
    @Test func aFixtureTreeOutsideThisCheckoutIsWalkedEveryTime() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-t3242-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "one".write(to: root.appendingPathComponent("One.swift"), atomically: true, encoding: .utf8)
        let before = CadenceSourceScan.repositoryPaths(under: root)
        #expect(before == ["One.swift"])

        try "two".write(to: root.appendingPathComponent("Two.swift"), atomically: true, encoding: .utf8)
        let after = CadenceSourceScan.repositoryPaths(under: root)
        #expect(after.sorted() == ["One.swift", "Two.swift"], "a fixture tree was answered from a stale walk")
    }

    /// And this checkout's own whole-tree walk *is* shared — the same list, twice, pruned the same
    /// way. `repositoryPaths` is the most expensive walk in the target.
    @Test func thisCheckoutsWholeTreeWalkIsSharedAcrossCallers() {
        let first = CadenceSourceScan.repositoryPaths()
        let second = CadenceSourceScan.repositoryPaths()

        #expect(!first.isEmpty, "the whole-tree walk read nothing")
        #expect(first == second)
        #expect(first.contains("AGENTS.md"), "the walk no longer reaches the repository root's own files")

        // Keyed by the prune list too: a different prune list is a different answer, not a hit.
        let pruned = CadenceSourceScan.repositoryPaths(pruningDirectoriesNamed: ["CadenceTests"])
        #expect(pruned.count < first.count, "pruning a directory was answered from the unpruned walk")
    }
}
