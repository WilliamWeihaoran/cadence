import Foundation
import Testing

/// **T-3018 — the fence around `CADENCE_MCP_ENABLE_WRITES`, pinned so it cannot rot quietly.**
///
/// `CadenceModelContainerFactory.makeReadWriteContainer()` opens the owner's real app-group store
/// — the same file the running app has open, and with `cloudKitDatabase: .none` against the app's
/// `.private("iCloud.com.haoranwei.Cadence")` — with `allowsSave: true`, and then runs
/// `CadenceMCPStorePreparation.prepare`, whose third step deletes duplicate `Context`, `Area`,
/// `Project` and `Note` rows and saves. Two environment variables decide whether any of that
/// touches the owner's data: `CADENCE_MCP_ENABLE_WRITES` opens the write container, and
/// `CADENCE_MCP_STORE_URL` redirects *which* store both containers resolve
/// (`CadenceModelContainerFactory.resolvedStoreURL()` prefers the override over
/// `CadenceStoreSupport.primaryStoreURL()`, and the audit log and refresh marker derive from it,
/// so the whole write path follows the override).
///
/// That pairing is the entire safety argument for the two scripts that do enable writes, and
/// nothing enforced it. A new script that sets the first without pinning the second would run a
/// deleting merge over the owner's live store with no user in front of it, and would look exactly
/// like the two that are safe.
///
/// So the scripts are **discovered**, never listed: the sweep walks the repository for script
/// files, keeps the ones that *assign* `CADENCE_MCP_ENABLE_WRITES`, and requires an assignment to
/// `CADENCE_MCP_STORE_URL` earlier in the same file. A remembered list of paths would go stale the
/// moment someone adds the third script, which is the only case this test exists for.
///
/// Scope, stated so a later reader does not over-read a green run: this pins **ordering within one
/// file**. It does not prove the pinned path is a throwaway — `docs/screenshots/seed-screenshot-data.py`
/// checks that separately with its own `REFUSED_SUBSTRINGS` over the real container — and it says
/// nothing about an interactive shell, which is `docs/SUBAGENT_RUNBOOK.md:28`'s job.
struct CadenceMCPWriteFenceTests {

    // MARK: - The fence

    /// The assertion with teeth.
    @Test func everyRepositoryScriptEnablingMCPWritesPinsAStoreURLFirst() throws {
        let scripts = try Self.repositoryScriptPaths()
        var enabling: [String] = []
        var unfenced: [String] = []

        for path in scripts {
            guard let text = try? CadenceSourceScan.sourceFile(path) else { continue }
            guard let enableOffset = Self.firstAssignmentOffset(
                of: Self.enableWritesKey, in: text
            ) else { continue }
            enabling.append(path)
            guard let storeOffset = Self.firstAssignmentOffset(of: Self.storeURLKey, in: text),
                  storeOffset < enableOffset
            else {
                unfenced.append(path)
                continue
            }
        }

        // Non-vacuity: the sweep, the needle and the enumeration all have to still be working.
        // Two scripts enable writes today; a drop to zero means the scan broke, not that the repo
        // got safer.
        #expect(
            enabling.count >= 2,
            "found \(enabling.count) scripts assigning \(Self.enableWritesKey); expected at least 2"
        )
        #expect(
            unfenced.isEmpty,
            """
            these scripts set \(Self.enableWritesKey) without pinning \(Self.storeURLKey) first, \
            so they would run the MCP write path — including the deleting integrity repair — \
            against the owner's real app-group store: \(unfenced.sorted().joined(separator: ", "))
            """
        )
    }

    /// Non-vacuity for the enumeration itself. A walk that returns nothing, or that silently stops
    /// seeing `.py` or `.sh`, makes the assertion above green over zero files.
    @Test func theRepositoryScriptSweepSeesBothScriptFlavoursAndEnoughOfThem() throws {
        let scripts = try Self.repositoryScriptPaths()

        #expect(scripts.count >= 25, "repository script sweep found \(scripts.count) files")
        #expect(scripts.contains { $0.hasSuffix(".sh") })
        #expect(scripts.contains { $0.hasSuffix(".py") })
        #expect(
            scripts.contains { $0.hasSuffix("/smoke-test.py") },
            "the MCP smoke test is not in the sweep, so the sweep is not reaching plugins/"
        )
        // Build output is not repository source; a tree with `.codex-build/` checked out would
        // otherwise drag hundreds of vendored scripts in and make the floor above meaningless.
        #expect(scripts.allSatisfy { !$0.contains("/.codex-build/") && !$0.hasPrefix(".codex-build/") })
        // Every path the sweep yields must still be readable through `CadenceSourceScan`.
        for path in scripts.prefix(5) {
            #expect((try? CadenceSourceScan.sourceFile(path)) != nil, "unreadable sweep path: \(path)")
        }
    }

    // MARK: - Self-check on the needle

    /// The needle must match the two spellings that actually occur and must **not** match a
    /// mention that sets nothing — `env.pop("CADENCE_MCP_ENABLE_WRITES", None)` is in the smoke
    /// test and is the opposite of enabling writes.
    @Test func theAssignmentNeedleMatchesSettersAndNotMentions() {
        let python = #"env["CADENCE_MCP_ENABLE_WRITES"] = "1""#
        let shell = "export CADENCE_MCP_ENABLE_WRITES=1"
        let bare = "CADENCE_MCP_ENABLE_WRITES=1 ./run.sh"
        let pop = #"env.pop("CADENCE_MCP_ENABLE_WRITES", None)"#
        let prose = "# never set CADENCE_MCP_ENABLE_WRITES by hand"

        #expect(Self.firstAssignmentOffset(of: Self.enableWritesKey, in: python) != nil)
        #expect(Self.firstAssignmentOffset(of: Self.enableWritesKey, in: shell) != nil)
        #expect(Self.firstAssignmentOffset(of: Self.enableWritesKey, in: bare) != nil)
        #expect(Self.firstAssignmentOffset(of: Self.enableWritesKey, in: pop) == nil)
        #expect(Self.firstAssignmentOffset(of: Self.enableWritesKey, in: prose) == nil)
        #expect(Self.firstAssignmentOffset(of: Self.storeURLKey, in: python) == nil)
    }

    /// The ordering half, on literal fixtures, so a failure here separates "the rule is wrong"
    /// from "a script is wrong".
    @Test func theFenceRuleAcceptsAPinnedStoreAndRejectsAnUnpinnedOne() {
        let fenced = """
        env["CADENCE_MCP_STORE_URL"] = str(tmp / "default.store")
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let reversed = """
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        env["CADENCE_MCP_STORE_URL"] = str(tmp / "default.store")
        """
        let unpinned = #"env["CADENCE_MCP_ENABLE_WRITES"] = "1""#

        #expect(Self.isFenced(fenced))
        #expect(!Self.isFenced(reversed))
        #expect(!Self.isFenced(unpinned))
    }

    // MARK: - Mechanics

    static let enableWritesKey = "CADENCE_MCP_ENABLE_WRITES"
    static let storeURLKey = "CADENCE_MCP_STORE_URL"

    /// `true` when `text` assigns the store override strictly before it enables writes. A text that
    /// never enables writes is fenced by definition.
    static func isFenced(_ text: String) -> Bool {
        guard let enableOffset = firstAssignmentOffset(of: enableWritesKey, in: text) else { return true }
        guard let storeOffset = firstAssignmentOffset(of: storeURLKey, in: text) else { return false }
        return storeOffset < enableOffset
    }

    /// The offset of the first place `key` is **assigned**, or `nil`.
    ///
    /// One pattern covers every shape that occurs: `NAME=`, `export NAME=`, and Python's
    /// `env["NAME"] = value`, where the characters between the name and the `=` are the closing
    /// quote and bracket. A bare mention — a comment, or `pop("NAME", None)` — has a `,` or a line
    /// end where the `=` would be and does not match.
    static func firstAssignmentOffset(of key: String, in text: String) -> Int? {
        let pattern = "\(key)[\"']?\\s*\\]?\\s*="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return match.range.location
    }

    /// Every script file in the repository, as paths relative to the repository root.
    ///
    /// Discovery, not a list. Directories that hold build output or vendored checkouts are skipped
    /// — `.codex-build/` alone carries ~70 vendored SwiftNIO scripts that are not this repository's
    /// to fence — and `.git` is skipped because it is large and holds no source. `.github` and
    /// `.githooks` are **not** skipped: a CI step that enabled writes would be the worst version of
    /// this bug.
    static func repositoryScriptPaths() throws -> [String] {
        let root = CadenceSourceScan.repositoryRoot()
        let skipped: Set<String> = [
            ".git", ".codex-build", ".build", "build", "DerivedData",
            "node_modules", "Pods", ".swiftpm", "__pycache__", ".venv",
        ]
        let scriptExtensions: Set<String> = ["sh", "bash", "zsh", "py", "rb", "pl", "js", "mjs", "command"]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var paths: [String] = []
        let rootPath = root.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if skipped.contains(name) { enumerator.skipDescendants() }
                continue
            }
            let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            let ext = url.pathExtension.lowercased()
            if scriptExtensions.contains(ext) {
                paths.append(relative)
            } else if ext.isEmpty, let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                let head = (try? handle.read(upToCount: 2)) ?? Data()
                if head == Data("#!".utf8) { paths.append(relative) }
            }
        }
        return paths
    }
}
