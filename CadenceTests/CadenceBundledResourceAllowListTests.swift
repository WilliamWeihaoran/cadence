// Compiled for macOS only, like `AppStoreReviewReadinessTests`: it reads the working tree beside
// this file, and the macOS leg is the one CI runs it on.
#if os(macOS)
import Foundation
import Testing

/// **T-7277, the pin [[T-7101]] asked for and never got.** `Cadence/` and `CadenceWidgets/` are
/// `PBXFileSystemSynchronizedRootGroup`s, so every file under them that Xcode does not recognise
/// as source becomes a bundled RESOURCE, with no line in `project.pbxproj` for anybody to notice.
/// That is how `CalendarPageView.swift.orig` -- 19 KB of macOS SwiftUI source -- shipped inside
/// both products. `.gitignore` now names `*.orig`, `*.rej` and `*.bak`, which stops such a file
/// reaching git and so removes the `??` in `git status` that found the first one; Xcode's sync
/// does not consult `.gitignore`, so the bundle is exactly as exposed as before.
///
/// **An ALLOW-list, not a deny-list.** Re-encoding the three `.gitignore` patterns would catch the
/// last stray and miss the next one -- an editor's `.Foo.swift.swp`, a `.tmp`, a stray `.md`. A
/// file is admitted only if it is a kind the targets are meant to carry, or if the project file
/// itself excepts it from membership. A new resource type that is meant to ship extends the list
/// below; that is one deliberate line, which is the point.
///
/// **It walks the FILESYSTEM, not `git ls-files`,** because the stray that shipped was untracked.
/// In CI that is a clean checkout; here it is a tree a dozen agents write, which is the case the
/// test exists for.
struct CadenceBundledResourceAllowListTests {
    /// Kinds Xcode compiles, signs with, or bundles on purpose, anywhere under a target folder.
    static let admittedExtensions: Set<String> = ["swift", "entitlements", "xcprivacy"]
    /// Kinds that are only legitimate INSIDE an asset catalog, which actool compiles into
    /// `Assets.car`. A `.png` or `.json` loose in the source tree would be copied as-is.
    static let assetCatalogExtensions: Set<String> = ["png", "json"]
    /// Finder metadata. Xcode's sync skips it and it is in no built bundle measured; every other
    /// dotfile -- including vim's `.Name.swift.swp` -- is NOT admitted.
    static let ignoredNames: Set<String> = [".DS_Store"]

    @Test(arguments: ["Cadence", "CadenceWidgets"])
    func everyFileUnderTheTargetFolderIsAKindTheBundleIsMeantToCarry(_ folder: String) throws {
        let excepted = try membershipExceptions(ofSynchronizedFolder: folder)
        let root = repositoryRoot.appendingPathComponent(folder)
        let walker = try #require(FileManager.default.enumerator(atPath: root.path))
        var walked = 0
        var strays: [String] = []
        while let entry = walker.nextObject() as? String {
            guard walker.fileAttributes?[.type] as? FileAttributeType != .typeDirectory else { continue }
            walked += 1
            let name = (entry as NSString).lastPathComponent
            let ext = (entry as NSString).pathExtension
            if Self.ignoredNames.contains(name) || excepted.contains(entry) { continue }
            if Self.admittedExtensions.contains(ext) { continue }
            if Self.assetCatalogExtensions.contains(ext), entry.contains(".xcassets/") { continue }
            strays.append("\(folder)/\(entry)")
        }
        // Non-vacuity: a walk that read nothing admits everything.
        #expect(walked > 0, "walked no files under \(folder)")
        #expect(strays.isEmpty, """
            \(strays.count) file(s) under \(folder)/ would be bundled into the shipped product as \
            resources (T-7101): \(strays.sorted()). Delete a leftover; for a resource meant to ship, \
            add its kind to CadenceBundledResourceAllowListTests.
            """)
    }

    /// The precondition the walk rests on, so a project restructure that drops the synchronized
    /// group says so here instead of leaving the test above guarding a mechanism that is gone.
    @Test func bothShippingTargetFoldersAreStillSynchronizedRootGroups() throws {
        let objects = try projectObjects()
        let synchronized = Set(objects.values.compactMap { object -> String? in
            object["isa"] as? String == "PBXFileSystemSynchronizedRootGroup" ? object["path"] as? String : nil
        })
        #expect(synchronized.isSuperset(of: ["Cadence", "CadenceWidgets"]))
    }

    /// The paths the project file excepts from the folder's membership -- the `AGENTS.md` guides
    /// and `Info.plist` -- read out of `project.pbxproj` rather than restated, so a new guide that
    /// nobody excepted is a stray here too, which it is: it would ship.
    private func membershipExceptions(ofSynchronizedFolder folder: String) throws -> Set<String> {
        let objects = try projectObjects()
        let group = try #require(
            objects.values.first { $0["isa"] as? String == "PBXFileSystemSynchronizedRootGroup" && $0["path"] as? String == folder },
            "no synchronized root group for \(folder)"
        )
        let exceptionIDs = group["exceptions"] as? [String] ?? []
        return Set(exceptionIDs.flatMap { objects[$0]?["membershipExceptions"] as? [String] ?? [] })
    }

    private func projectObjects() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("Cadence.xcodeproj/project.pbxproj"))
        let project = try #require(
            try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        return try #require(project["objects"] as? [String: [String: Any]])
    }
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
#endif
