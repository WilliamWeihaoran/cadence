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
/// Scope, stated so a later reader does not over-read a green run. The first assertion pins
/// **ordering within one file** and nothing more — it is satisfied by a script that pins the
/// owner's own container path, which is the whole reason the second layer below exists.
/// `everyScriptEnablingMCPWritesPinsAThrowawayStoreAndNotTheOwnersOwn` closes that: the pinned
/// value must be derived from a temporary directory **or** be guarded by an explicit refusal over
/// the real container path, and a literal under `~/Library/Containers/com.haoranwei.Cadence` or
/// the app group fails either way. Both layers are source scans over the repository, and neither
/// says anything about an interactive shell — that is `docs/SUBAGENT_RUNBOOK.md`'s rule, it is
/// prose on purpose, and the note there explains why no test can take it over.
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

    // MARK: - The throwaway guarantee

    /// **A pinned store URL is not yet a safe one, and that gap is what this layer closes.**
    ///
    /// `everyRepositoryScriptEnablingMCPWritesPinsAStoreURLFirst` proves only that a script naming
    /// `CADENCE_MCP_ENABLE_WRITES` names *a* store first. A script that pinned
    /// `CADENCE_MCP_STORE_URL` to `~/Library/Containers/com.haoranwei.Cadence/.../default.store`
    /// passes it outright — and would then run the whole write path, including
    /// `CadenceMCPStorePreparation.prepare`'s integrity repair, which deletes duplicate `Context`,
    /// `Area`, `Project` and `Note` rows and saves, over the owner's live data with no user in
    /// front of it.
    ///
    /// **The rule, read off what the two scripts already do rather than invented for them:**
    ///
    /// 1. The pinned value must not **reach** the owner's real store. The assignment's right-hand
    ///    side is resolved transitively through the identifiers and functions the same file
    ///    defines, and any of `realStoreMarkers` turning up anywhere in that closure fails the
    ///    script outright. No other defence excuses it — a refusal list is worth nothing in a file
    ///    that then pins the container path by hand.
    /// 2. **And** at least one of the two defences the repository actually uses must be present:
    ///    - **temporary derivation** — the resolved value names a temporary-directory source
    ///      (`tempfile`, `mkdtemp`, `mktemp`, `$TMPDIR`, …). `plugins/cadence-mcp/scripts/smoke-test.py`
    ///      is defended this way: it pins `str(Path(temp_store.name) / "default.store")`, and
    ///      `temp_store` resolves through `prepare_fixture_store()` to `tempfile.TemporaryDirectory`
    ///      — two hops, which is why the resolution is transitive and not a look at one line.
    ///    - **a refusal guard** — the file holds a real-container marker in a literal it tests the
    ///      candidate path against, inside a function that raises, and that function is called.
    ///      `docs/screenshots/seed-screenshot-data.py` is defended this way, by `REFUSED_SUBSTRINGS`
    ///      and `guard_store_path`; it takes its path from `--store` and has no temp derivation to
    ///      find, which is exactly why one defence alone would have been the wrong rule.
    ///
    /// Comments are blanked with `CadenceSourceScan.strippingHashComments` first, so a commented-out
    /// pin is not a defence and a commented-out `export CADENCE_MCP_ENABLE_WRITES=1` is not a
    /// finding.
    ///
    /// **Scope, stated so a green run is not over-read.** This is a source scan, like its
    /// neighbour, and it reasons about the *text* of an assignment rather than the path a run
    /// resolves:
    ///
    /// - It does not prove the refusal guard is called **with** the value that is pinned.
    ///   `guard_store_path(args.store)` runs in `main` while the pin happens inside
    ///   `MCPClient.__init__`, so there is no within-file ordering to compare and no cheap way to
    ///   follow the argument; `theSeedScriptRefusalListStillCoversTheOwnersRealContainer` pins the
    ///   call-before-construct ordering for that one script by hand instead.
    /// - The refusal-guard detector reads Python `def` blocks only. A future shell script would
    ///   have to carry the temporary derivation, which fails safe (red), not open.
    /// - It cannot see what an operator types into an interactive shell. Nothing here can; that is
    ///   `docs/SUBAGENT_RUNBOOK.md`'s rule and it is prose on purpose.
    @Test func everyScriptEnablingMCPWritesPinsAThrowawayStoreAndNotTheOwnersOwn() throws {
        let scripts = try Self.repositoryScriptPaths()
        var enabling: [String] = []
        var findings: [String] = []
        var assignments = 0
        var temporaryDefences = 0
        var refusalDefences = 0

        for path in scripts {
            guard let raw = try? CadenceSourceScan.sourceFile(path) else { continue }
            let source = CadenceSourceScan.strippingHashComments(raw)
            guard Self.firstAssignmentOffset(of: Self.enableWritesKey, in: source) != nil else { continue }
            enabling.append(path)
            let verdict = Self.throwawayVerdict(path: path, source: source)
            findings.append(contentsOf: verdict.findings)
            assignments += verdict.assignments
            temporaryDefences += verdict.temporaryDefences
            refusalDefences += verdict.refusalDefences
        }

        // Non-vacuity, four ways. The sweep has to still find the scripts, the assignment scan has
        // to still find their pins, and BOTH defence detectors have to still fire on the script
        // that uses them — a detector that silently stopped matching would otherwise make every
        // script look undefended (loud) or, if the fatal test were reordered, make nothing look
        // checked at all (silent).
        #expect(
            enabling.count >= 2,
            "found \(enabling.count) scripts assigning \(Self.enableWritesKey); expected at least 2"
        )
        #expect(
            assignments >= 3,
            "found \(assignments) \(Self.storeURLKey) assignments in those scripts; expected at least 3"
        )
        #expect(
            temporaryDefences >= 1,
            "no pinned store resolved to a temporary directory; the temp-derivation detector stopped working"
        )
        #expect(
            refusalDefences >= 1,
            "no enabling script carried a refusal guard over the real container; the guard detector stopped working"
        )
        #expect(
            findings.isEmpty,
            """
            these scripts enable \(Self.enableWritesKey) without proving the store they pin is a \
            throwaway, so an unattended MCP write — including the deleting integrity repair in \
            CadenceMCPStorePreparation.prepare — could land on the owner's real store:
            \(findings.sorted().joined(separator: "\n"))
            """
        )
    }

    /// The rule on literal fixtures, so a failure separates "the rule is wrong" from "a script is
    /// wrong" — and so the fatal half is proven against a real-container literal without ever
    /// writing one into the repository.
    @Test func theThrowawayRuleRejectsARealContainerPathAndAcceptsEitherDefence() {
        let temporaryDerived = """
        import tempfile
        def fixture_store():
            return tempfile.TemporaryDirectory(prefix="cadence-fixture-")
        box = fixture_store()
        env["CADENCE_MCP_STORE_URL"] = str(Path(box.name) / "default.store")
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let shellTemporary = """
        export CADENCE_MCP_STORE_URL="$TMPDIR/CadenceUITestStores/shots/default.store"
        export CADENCE_MCP_ENABLE_WRITES=1
        """
        let guarded = """
        REFUSED = (
            "Library/Containers/com.haoranwei.Cadence",
        )
        def guard_store(candidate):
            for fragment in REFUSED:
                if fragment in candidate:
                    raise SystemExit("REFUSING: that is the owner's real store")
        guard_store(target)
        env["CADENCE_MCP_STORE_URL"] = target
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let guardListGutted = """
        REFUSED = (
        )
        def guard_store(candidate):
            for fragment in REFUSED:
                if fragment in candidate:
                    raise SystemExit("REFUSING: that is the owner's real store")
        guard_store(target)
        env["CADENCE_MCP_STORE_URL"] = target
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let literalContainer = """
        env["CADENCE_MCP_STORE_URL"] = "/Users/owner/Library/Containers/com.haoranwei.Cadence/Data/default.store"
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let indirectContainer = """
        import tempfile
        target = os.path.expanduser("~/Library/Containers/com.haoranwei.Cadence/Data/default.store")
        env["CADENCE_MCP_STORE_URL"] = target
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let commentedPin = """
        # env["CADENCE_MCP_STORE_URL"] = str(tmp / "default.store")
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """
        let undefended = """
        env["CADENCE_MCP_STORE_URL"] = os.environ["CADENCE_SEED_STORE"]
        env["CADENCE_MCP_ENABLE_WRITES"] = "1"
        """

        #expect(Self.throwawayVerdict(path: "f.py", source: temporaryDerived).findings.isEmpty)
        #expect(Self.throwawayVerdict(path: "f.py", source: temporaryDerived).temporaryDefences == 1)
        #expect(Self.throwawayVerdict(path: "f.sh", source: shellTemporary).findings.isEmpty)
        #expect(Self.throwawayVerdict(path: "f.py", source: guarded).findings.isEmpty)
        #expect(Self.throwawayVerdict(path: "f.py", source: guarded).refusalDefences == 1)

        // A refusal list edited down to nothing stops being a defence, and the script it was the
        // only defence for goes red rather than quietly running on.
        #expect(!Self.throwawayVerdict(path: "f.py", source: guardListGutted).findings.isEmpty)
        // The fatal half: a real-container path fails whether it is written inline or one hop away.
        #expect(!Self.throwawayVerdict(path: "f.py", source: literalContainer).findings.isEmpty)
        #expect(!Self.throwawayVerdict(path: "f.py", source: indirectContainer).findings.isEmpty)
        // …and `import tempfile` sitting in the same file does not excuse it.
        #expect(
            Self.throwawayVerdict(path: "f.py", source: indirectContainer)
                .findings.joined().contains("Library/Containers/com.haoranwei.Cadence")
        )
        // A pin that only exists in a comment is not a pin.
        #expect(!Self.throwawayVerdict(path: "f.py", source: commentedPin).findings.isEmpty)
        #expect(!Self.throwawayVerdict(path: "f.py", source: undefended).findings.isEmpty)
    }

    /// `docs/screenshots/seed-screenshot-data.py` is the one script whose whole defence is its
    /// refusal list, and a list edited down to nothing leaves the script running exactly as before.
    /// The sweep above already turns that red; this names the failure precisely when it happens.
    @Test func theSeedScriptRefusalListStillCoversTheOwnersRealContainer() throws {
        let path = "docs/screenshots/seed-screenshot-data.py"
        let source = CadenceSourceScan.strippingHashComments(try CadenceSourceScan.sourceFile(path))

        let list = Self.assignmentBlock(of: "REFUSED_SUBSTRINGS", in: source)
        #expect(list != nil, "\(path) no longer assigns REFUSED_SUBSTRINGS")
        #expect(
            list?.contains("Library/Containers/com.haoranwei.Cadence") == true,
            """
            \(path)'s REFUSED_SUBSTRINGS no longer names the owner's real container, so \
            --store could be pointed straight at it: \(list ?? "<absent>")
            """
        )

        let body = Self.definitionBlock(of: "guard_store_path", in: source)
        #expect(body != nil, "\(path) no longer defines guard_store_path")
        #expect(body?.contains("REFUSED_SUBSTRINGS") == true, "guard_store_path no longer reads the list")
        #expect(body?.contains("SystemExit") == true, "guard_store_path no longer refuses")

        // It has to run before the client that enables writes is built.
        let lines = source.components(separatedBy: "\n")
        let guardCall = lines.firstIndex { $0.contains("guard_store_path(") && !$0.contains("def ") }
        let clientBuild = lines.firstIndex { $0.contains("MCPClient(") && !$0.contains("class ") }
        #expect(guardCall != nil, "nothing calls guard_store_path in \(path)")
        #expect(clientBuild != nil, "nothing constructs MCPClient in \(path)")
        if let guardCall, let clientBuild {
            #expect(
                guardCall < clientBuild,
                "\(path):\(clientBuild + 1) builds MCPClient before guard_store_path runs"
            )
        }
    }

    // MARK: - Throwaway mechanics

    /// Substrings that mean "this is the owner's real data", not a fixture. The first is the one a
    /// hand-written container path hits; the app group and the iCloud container are the other two
    /// doors onto the same rows.
    static let realStoreMarkers = [
        "Library/Containers/com.haoranwei.Cadence",
        "group.com.haoranwei.Cadence",
        "iCloud.com.haoranwei.Cadence",
        "Library/Application Support/Cadence",
    ]

    /// Every spelling of "a temporary directory" that occurs or plausibly would.
    static let temporaryDirectoryTokens = [
        "tempfile", "TemporaryDirectory", "mkdtemp", "mktemp", "gettempdir",
        "TMPDIR", "NSTemporaryDirectory", "/tmp/",
    ]

    /// Every spelling of "and then stop", for the refusal half.
    static let refusalKeywords = ["SystemExit", "sys.exit(", "RuntimeError", "exit 1", "exit(1)"]

    struct ThrowawayVerdict {
        var findings: [String] = []
        var assignments = 0
        var temporaryDefences = 0
        var refusalDefences = 0
    }

    /// The rule, applied to one already comment-blanked script. `source` is expected to have been
    /// through `CadenceSourceScan.strippingHashComments`; the fixtures below pass raw text and the
    /// helper strips again, which is idempotent.
    static func throwawayVerdict(path: String, source: String) -> ThrowawayVerdict {
        let text = CadenceSourceScan.strippingHashComments(source)
        var verdict = ThrowawayVerdict()
        let pins = storeURLAssignments(in: text)
        guard !pins.isEmpty else {
            verdict.findings.append(
                "\(path): sets \(enableWritesKey) and assigns \(storeURLKey) nowhere outside comments"
            )
            return verdict
        }
        let guardFunction = refusalGuardOverTheRealStore(in: text)

        for pin in pins {
            verdict.assignments += 1
            let resolved = resolvedExpression(pin.expression, in: text)
            let marker = realStoreMarker(in: resolved)
            let temporaryToken = temporaryDirectoryToken(in: resolved)
            if temporaryToken != nil { verdict.temporaryDefences += 1 }
            if guardFunction != nil { verdict.refusalDefences += 1 }

            var missing: [String] = []
            if let marker {
                missing.append("the pinned value reaches the owner's real store (\"\(marker)\")")
            }
            if temporaryToken == nil {
                missing.append(
                    "no temporary-directory derivation (none of \(temporaryDirectoryTokens.joined(separator: ", ")))"
                )
            }
            if guardFunction == nil {
                missing.append("no refusal check over \(realStoreMarkers[0])")
            }
            guard marker != nil || (temporaryToken == nil && guardFunction == nil) else { continue }
            verdict.findings.append(
                "\(path):\(pin.line) pins \(storeURLKey) to `\(pin.expression)` — \(missing.joined(separator: "; "))"
            )
        }
        return verdict
    }

    static func realStoreMarker(in text: String) -> String? {
        realStoreMarkers.first { text.contains($0) }
    }

    static func temporaryDirectoryToken(in text: String) -> String? {
        temporaryDirectoryTokens.first { text.contains($0) }
    }

    /// Every line that assigns `CADENCE_MCP_STORE_URL`, with its 1-based line number and the text
    /// to the right of the `=`.
    static func storeURLAssignments(in text: String) -> [(line: Int, expression: String)] {
        let pattern = "\(storeURLKey)[\"']?[ \t]*\\]?[ \t]*=[ \t]*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var found: [(line: Int, expression: String)] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let captured = Range(match.range(at: 1), in: line)
            else { continue }
            found.append((index + 1, String(line[captured]).trimmingCharacters(in: .whitespaces)))
        }
        return found
    }

    /// `expression` plus everything the same file says about the identifiers inside it, and about
    /// the identifiers inside *those*, to four hops.
    ///
    /// Two hops is the minimum that works on the code as written — `temp_store` ->
    /// `prepare_fixture_store()` -> `tempfile.TemporaryDirectory` — so a one-line look at the
    /// right-hand side would have scored the smoke test as undefended. Identifiers are taken from
    /// the expression with its string literals blanked, so `"default.store"` does not send the
    /// resolver looking for a variable called `store`; the *text* that is searched for markers and
    /// temp tokens keeps its literals, because that is where both actually appear.
    static func resolvedExpression(_ expression: String, in text: String) -> String {
        var resolved = expression
        var visited: Set<String> = []
        var frontier = [expression]
        // Four hops and 400 identifiers: generous next to the two the real scripts need, and a
        // ceiling so a pathological file cannot turn the scan quadratic.
        for _ in 0..<4 where visited.count < 400 {
            var next: [String] = []
            for fragment in frontier {
                for identifier in identifiers(in: quoteBlanked(fragment))
                where !visited.contains(identifier) && visited.count < 400 {
                    visited.insert(identifier)
                    var definitions: [String] = []
                    if let assigned = assignmentBlock(of: identifier, in: text) { definitions.append(assigned) }
                    if let defined = definitionBlock(of: identifier, in: text) { definitions.append(defined) }
                    guard !definitions.isEmpty else { continue }
                    resolved += "\n" + definitions.joined(separator: "\n")
                    next.append(contentsOf: definitions)
                }
            }
            if next.isEmpty { break }
            frontier = next
        }
        return resolved
    }

    /// A refusal guard over the real container, by name, or `nil`.
    ///
    /// Three halves, all required: a literal naming the real container (directly in the function,
    /// or in a collection the function reads), a refusal in the same function, and a call to it.
    /// Gut the literal list and the guard stops existing, which is the failure this is for.
    static func refusalGuardOverTheRealStore(in text: String) -> String? {
        var refusalNames: Set<String> = []
        for identifier in assignedIdentifiers(in: text) {
            guard let block = assignmentBlock(of: identifier, in: text) else { continue }
            if realStoreMarker(in: block) != nil { refusalNames.insert(identifier) }
        }
        for name in definedFunctionNames(in: text) {
            guard let body = definitionBlock(of: name, in: text) else { continue }
            guard refusalKeywords.contains(where: { body.contains($0) }) else { continue }
            let readsTheMarker = realStoreMarker(in: body) != nil
                || refusalNames.contains { body.contains($0) }
            guard readsTheMarker, isCalled(name, in: text) else { continue }
            return name
        }
        return nil
    }

    /// The text assigned to `identifier`, with brackets balanced across lines so a multi-line tuple
    /// — `REFUSED_SUBSTRINGS = (` and the two strings under it — comes back whole.
    static func assignmentBlock(of identifier: String, in text: String) -> String? {
        let pattern = "^[ \t]*(?:export[ \t]+|local[ \t]+)?\(identifier)[ \t]*=[ \t]*(?!=)(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let lines = text.components(separatedBy: "\n")
        var collected: [String] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let captured = Range(match.range(at: 1), in: line)
            else { continue }
            var fragment = String(line[captured])
            var depth = bracketDepth(of: fragment)
            var cursor = index + 1
            while depth > 0, cursor < lines.count, cursor - index < 40 {
                fragment += "\n" + lines[cursor]
                depth += bracketDepth(of: lines[cursor])
                cursor += 1
            }
            collected.append(fragment)
        }
        return collected.isEmpty ? nil : collected.joined(separator: "\n")
    }

    /// The body of `def <name>(`, by indentation. Python only, deliberately — see the scope note.
    static func definitionBlock(of name: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "^([ \t]*)def[ \t]+\(name)[ \t]*\\(") else { return nil }
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let indentRange = Range(match.range(at: 1), in: line)
            else { continue }
            let indent = line[indentRange].count
            var body: [String] = []
            var cursor = index + 1
            while cursor < lines.count, body.count < 200 {
                let next = lines[cursor]
                if !next.trimmingCharacters(in: .whitespaces).isEmpty, leadingWidth(of: next) <= indent { break }
                body.append(next)
                cursor += 1
            }
            return body.joined(separator: "\n")
        }
        return nil
    }

    static func assignedIdentifiers(in text: String) -> [String] {
        capturedNames("^[ \t]*(?:export[ \t]+|local[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[^=]", in: text)
    }

    static func definedFunctionNames(in text: String) -> [String] {
        capturedNames("^[ \t]*def[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\\(", in: text)
    }

    private static func capturedNames(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var names: [String] = []
        var seen: Set<String> = []
        for line in text.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let captured = Range(match.range(at: 1), in: line)
            else { continue }
            let name = String(line[captured])
            if seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    /// `true` when `name(` occurs on a line that is not its own `def`.
    static func isCalled(_ name: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])\(name)[ \t]*\\(") else { return false }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("def ") { continue }
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil { return true }
        }
        return false
    }

    static func identifiers(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*") else { return [] }
        let nsText = text as NSString
        var names: [String] = []
        var seen: Set<String> = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let name = nsText.substring(with: match.range)
            if seen.insert(name).inserted { names.append(name) }
        }
        return names
    }

    /// `text` with the contents of single- and double-quoted runs replaced by spaces. Not a Python
    /// tokenizer: it exists only to keep words inside path literals from being resolved as
    /// variables, and over-blanking can only shrink the resolution, never fake a defence.
    static func quoteBlanked(_ text: String) -> String {
        var output = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                if escaped {
                    escaped = false
                    output.append(" ")
                } else if character == "\\" {
                    escaped = true
                    output.append(" ")
                } else if character == open {
                    quote = nil
                    output.append(character)
                } else {
                    output.append(character == "\n" ? character : " ")
                }
            } else if character == "\"" || character == "'" {
                quote = character
                output.append(character)
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func bracketDepth(of text: String) -> Int {
        var depth = 0
        for character in text {
            if character == "(" || character == "[" || character == "{" { depth += 1 }
            if character == ")" || character == "]" || character == "}" { depth -= 1 }
        }
        return depth
    }

    private static func leadingWidth(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }
}
