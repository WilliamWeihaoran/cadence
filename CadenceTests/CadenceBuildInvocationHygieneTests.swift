import Foundation
import Testing

/// T-86. The mitigation for "an agent's build wiped `Build/Products/` under the user's running app"
/// is a private `-derivedDataPath` on every invocation, and it has been a *prose* rule in
/// `AGENTS.md` since 2026-08-18. Prose does not cover the invocations nobody rereads: measured
/// 2026-08-30, three of this repository's own runbook commands still used the default path —
/// `README.md`'s build and test commands, `docs/apple-release-readiness.md`'s two verification
/// commands, and `docs/direct-distribution-runbook.md`'s `archive`. Copying any of them lands in
/// the shared DerivedData.
///
/// **Read-only invocations leak too.** `xcodebuild -showBuildSettings` with no `-derivedDataPath`,
/// run once from a scratch copy, created `~/Library/Developer/Xcode/DerivedData/Cadence-<hash>`
/// with `Logs/`, `SourcePackages/` and an `XCBuildData/PIFCache` — the same shape as the thirteen
/// orphaned entries sitting there from earlier sessions. The hash is derived from the *project
/// path*, so an unflagged invocation from a scratch tree gets its own entry, and an unflagged
/// invocation **from the repository root shares the entry the user's Xcode uses**. That is the
/// T-86 mechanism, one `build` away.
///
/// So the rule is mechanised here rather than restated: every `xcodebuild` invocation in this
/// repository's markdown code fences and shell scripts that names a build action must name a
/// `-derivedDataPath`, and none may point it at the shared root.
struct CadenceBuildInvocationHygieneTests {

    @Test func everyDocumentedBuildInvocationNamesAPrivateDerivedDataPath() throws {
        let instrument = try CadenceScanInstrument(
            "unflagged xcodebuild build action",
            fires: Self.positiveWitness,
            andNotOn: Self.negativeWitness
        ) { shell in
            CadenceBuildInvocation.parse(shell).contains { $0.isBuildAction && !$0.namesDerivedDataPath }
        }

        let offenders = try instrument.sweep(
            Self.scannedPaths(),
            atLeast: 12,
            including: "AGENTS.md",
            read: Self.shellText(at:)
        )

        #expect(offenders.isEmpty, "these name no -derivedDataPath: \(offenders.joined(separator: ", "))")
    }

    @Test func noDocumentedInvocationPointsDerivedDataAtTheSharedRoot() throws {
        let instrument = try CadenceScanInstrument(
            "xcodebuild aimed at the shared DerivedData",
            fires: Self.sharedRootWitness,
            andNotOn: Self.negativeWitness
        ) { shell in
            CadenceBuildInvocation.parse(shell).contains(where: \.namesSharedDerivedDataRoot)
        }

        let offenders = try instrument.sweep(
            Self.scannedPaths(),
            atLeast: 12,
            including: "README.md",
            read: Self.shellText(at:)
        )

        #expect(offenders.isEmpty, "these aim at the shared DerivedData: \(offenders.joined(separator: ", "))")
    }

    /// The sweep above is only worth its runtime if the walk really reaches the files that carry the
    /// commands, and if the parser really sees the multi-line, backslash-continued shape every one of
    /// them is written in. A parser that only understood one-liners would have read `AGENTS.md`'s
    /// correct commands as bare `xcodebuild \` fragments with no action and no flag — vacuously
    /// clean, and blind to the README shape that is written the same way and is *not* clean.
    @Test func theWalkAndTheParserSeeTheCommandsTheyClaimTo() throws {
        let paths = Self.scannedPaths()

        #expect(paths.contains("AGENTS.md"))
        #expect(paths.contains("README.md"))
        #expect(paths.contains("docs/apple-release-readiness.md"))
        #expect(paths.contains("docs/direct-distribution-runbook.md"))
        #expect(paths.contains("plugins/cadence-mcp/scripts/run-cadence-mcp.sh"))
        #expect(paths.contains("scripts/test-host-lock.sh"))
        // Dependency checkouts carry their own `xcodebuild` harnesses; they are not this
        // repository's instructions and must not be swept. Bound before the macro rather than
        // inside it: `allSatisfy` and `contains(where:)` are `rethrows`, and `#expect` expands a
        // rethrowing call into something the compiler wants a `try` on.
        let noVendoredHarnesses = paths.allSatisfy { !$0.contains("SourcePackages/") }
        #expect(noVendoredHarnesses)

        let rootGuide = CadenceBuildInvocation.parse(try Self.shellText(at: "AGENTS.md"))
        let allAreBuildActions = rootGuide.allSatisfy(\.isBuildAction)
        let allNameTheFlag = rootGuide.allSatisfy(\.namesDerivedDataPath)
        let oneIsTheScopedTestRun = rootGuide.contains { $0.command.contains("-only-testing:CadenceTests") }
        #expect(rootGuide.count == 2, "root guide should document exactly a build and a test")
        #expect(allAreBuildActions)
        #expect(allNameTheFlag)
        #expect(oneIsTheScopedTestRun)

        // Markdown prose mentioning `xcodebuild` outside a fence is narrative, not an instruction —
        // the ticket ledgers are full of it. Pin the extraction on a fixture rather than on a
        // ledger's current wording, and pin that it really removes something from a real file:
        // an extractor that returned the whole document would read every ledger sentence as a
        // command, and one that returned "" would sweep every file vacuously clean.
        let fixture = """
        Prose saying you may run xcodebuild build with no flags, which is not an instruction.
        ```sh
        /usr/bin/xcodebuild -scheme Cadence -derivedDataPath /tmp/d build
        ```
        """
        let extracted = CadenceBuildInvocation.parse(Self.fencedShell(fixture))
        #expect(extracted.count == 1)
        #expect(extracted.first?.namesDerivedDataPath == true)

        let ledgerRaw = try CadenceSourceScan.sourceFile("docs/TODO.md")
        let ledgerShell = try Self.shellText(at: "docs/TODO.md")
        #expect(ledgerRaw.contains("xcodebuild"))
        #expect(ledgerShell.count < ledgerRaw.count)

        // `-exportArchive` builds nothing, so it is deliberately not a build action; if that ever
        // flips the export command in the distribution runbook starts failing for no reason.
        let export = "/usr/bin/xcodebuild -exportArchive -archivePath build/Cadence.xcarchive"
        #expect(CadenceBuildInvocation.parse(export).first?.isBuildAction == false)
    }

    // MARK: - Witnesses

    /// The README shape as it stood before this suite: continued across lines, action last, no flag.
    private static let positiveWitness = """
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \\
      -project Cadence.xcodeproj \\
      -scheme Cadence \\
      -destination 'platform=macOS' \\
      build
    """

    /// The nearest clean shape: same command, same continuation, one flag more.
    private static let negativeWitness = """
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \\
      -project Cadence.xcodeproj \\
      -scheme Cadence \\
      -destination 'platform=macOS' \\
      -derivedDataPath /tmp/cadence-build-$$ \\
      build
    """

    /// A flag that is present and still points at the one directory it must never point at.
    private static let sharedRootWitness = """
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \\
      -scheme Cadence \\
      -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Cadence-shared \\
      build
    """

    // MARK: - Walk

    /// Every markdown file and shell script that belongs to this repository, repository-relative.
    /// Discovered rather than listed, so a runbook added tomorrow is covered tomorrow.
    static func scannedPaths() -> [String] {
        let root = CadenceSourceScan.repositoryRoot()
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var found: [String] = []
        for case let entry as String in walker {
            if Self.excludedPrefixes.contains(where: { entry == $0 || entry.hasPrefix($0 + "/") }) { continue }
            if entry.contains("/SourcePackages/") || entry.contains("/DerivedData/") { continue }
            if entry.hasSuffix(".md") || entry.hasSuffix(".sh") { found.append(entry) }
        }
        return found.sorted()
    }

    private static let excludedPrefixes = [".git", ".build", ".codex-build", "build"]

    /// The shell text of a file: a script is shell throughout, a markdown file only inside its
    /// fenced code blocks.
    static func shellText(at relativePath: String) throws -> String {
        let text = try CadenceSourceScan.sourceFile(relativePath)
        return relativePath.hasSuffix(".md") ? fencedShell(text) : text
    }

    /// The contents of every fenced code block in a markdown document, concatenated.
    static func fencedShell(_ markdown: String) -> String {
        var fenced: [Substring] = []
        var inside = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inside.toggle()
                continue
            }
            if inside { fenced.append(line) }
        }
        return fenced.joined(separator: "\n")
    }
}

/// One `xcodebuild` command, with its backslash continuations joined.
struct CadenceBuildInvocation {
    let command: String

    /// Actions that make xcodebuild write into DerivedData. `-exportArchive` is not one of them:
    /// it repackages an existing `.xcarchive` and builds nothing.
    private static let buildActions: Set<String> = [
        "build", "test", "archive", "clean", "analyze", "install", "build-for-testing", "test-without-building"
    ]

    var tokens: [String] {
        command.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isBuildAction: Bool {
        tokens.dropFirst().contains { Self.buildActions.contains($0) }
    }

    var namesDerivedDataPath: Bool {
        tokens.contains { $0 == "-derivedDataPath" }
    }

    var namesSharedDerivedDataRoot: Bool {
        guard let index = tokens.firstIndex(of: "-derivedDataPath"), index + 1 < tokens.count else { return false }
        return tokens[index + 1].contains("Library/Developer/Xcode/DerivedData")
    }

    /// Every invocation in a block of shell text. A line counts as the start of one when its first
    /// token *is* the tool — `xcodebuild`, some path ending in `/xcodebuild`, or the `$XCODEBUILD`
    /// variable the MCP plugin script uses. An assignment such as `XCODEBUILD="…/xcodebuild"` is
    /// not an invocation and must not be read as one.
    static func parse(_ shell: String) -> [CadenceBuildInvocation] {
        var invocations: [CadenceBuildInvocation] = []
        var pending: String?
        for rawLine in shell.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let continues = line.hasSuffix("\\")
            let body = continues ? String(line.dropLast()).trimmingCharacters(in: .whitespaces) : line

            if var accumulated = pending {
                accumulated += " " + body
                if continues {
                    pending = accumulated
                } else {
                    invocations.append(CadenceBuildInvocation(command: accumulated))
                    pending = nil
                }
                continue
            }

            guard let first = body.split(whereSeparator: \.isWhitespace).first.map(String.init),
                  isToolToken(first) else { continue }
            if continues { pending = body } else { invocations.append(CadenceBuildInvocation(command: body)) }
        }
        if let trailing = pending { invocations.append(CadenceBuildInvocation(command: trailing)) }
        return invocations
    }

    private static func isToolToken(_ token: String) -> Bool {
        let bare = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if bare.contains("=") { return false }
        if bare == "$XCODEBUILD" || bare == "${XCODEBUILD}" { return true }
        return bare == "xcodebuild" || bare.hasSuffix("/xcodebuild")
    }
}
