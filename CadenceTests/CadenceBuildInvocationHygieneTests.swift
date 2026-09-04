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
        #expect(paths.contains(".github/workflows/ci.yml"), "CI's own xcodebuild invocations are outside the walk (T-709)")
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

    // MARK: - T-709: the sweep must reach CI's own YAML, not just markdown and shell

    /// Before this ticket, `scannedPaths()` only appended `.md` and `.sh`, so `.github/workflows/*.yml`
    /// sat outside the walk entirely while carrying real `xcodebuild` invocations behind
    /// `scripts/xcb.sh`. Two things have to be true at once: the walk reaches the workflow files, and
    /// the extractor reads their `run:` steps as shell rather than as YAML prose (a raw read of the
    /// file would see `steps:`, `uses:`, indentation and all, none of which is a command).
    @Test func theWalkAndTheParserReachGitHubWorkflowRunSteps() throws {
        let paths = Self.scannedPaths()
        #expect(paths.contains(".github/workflows/ci.yml"))
        #expect(paths.contains(".github/workflows/docs.yml"))

        // Fixture mirrors this repository's own shape: an inline `run:`, a literal block scalar
        // (`run: |`) with a leading comment line and a continued command, and a sibling `if:` key
        // that must not be swept as if it were shell.
        let fixture = #"""
        jobs:
          build:
            steps:
              - name: Not a command
                if: >-
                  github.event_name == 'workflow_dispatch'
              - name: Build
                run: |
                  # a comment inside the block
                  /usr/bin/xcodebuild -scheme Cadence                     -derivedDataPath /tmp/d                     build
              - name: Inline and unflagged
                run: xcodebuild -scheme Cadence build
        """#

        let shell = Self.yamlRunBlocks(fixture)
        #expect(!shell.contains("workflow_dispatch"), "the if: block scalar leaked into the shell text")
        #expect(!shell.contains("steps:"), "bare YAML structure leaked into the shell text")

        let invocations = CadenceBuildInvocation.parse(shell)
        #expect(invocations.count == 2)
        #expect(invocations.first?.namesDerivedDataPath == true)
        #expect(invocations.last?.namesDerivedDataPath == false)

        // Non-vacuity for the real files: they must actually contain `run:` steps worth extracting,
        // not just parse to nothing because the fixture is what does all the work above.
        let realCIShell = try Self.shellText(at: ".github/workflows/ci.yml")
        #expect(realCIShell.contains("xcb.sh"))
        #expect(!realCIShell.contains("runs-on:"), "job-level YAML keys leaked into the shell text")
    }

    // MARK: - T-552: the runner refuses a green run over zero tests

    /// **`-only-testing:` takes a suite name, not a file name, and a name that matches nothing is
    /// not an error.** Measured 2026-08-31: `-only-testing:CadenceTests/<NoSuchSuite>` prints
    /// `Executed 0 tests`, `** TEST SUCCEEDED **` and exits 0, with no warning and no diagnostic.
    /// 33 of this target's 255 test files declare more than one suite and 14 declare none named
    /// after the file, so a run scoped by *filename* against any of those exercises nothing and
    /// reports success — which is character for character what a surviving mutation looks like.
    /// An agent nearly filed a false "this sweep is blind" finding from exactly that; re-scoped to
    /// the suite the source actually declares, the same mutation killed a test.
    ///
    /// **Why the runner and not a naming guard.** The other candidate was a rule that every test
    /// file declare a suite matching its basename, which would make `-only-testing:<basename>`
    /// always valid. It is the worse fix on three counts: it costs 14 files today; it does not
    /// touch the failure, because a *typo* still returns green-over-zero and so does scoping to a
    /// multi-suite file's basename when the test you meant lives in a sibling suite (the residual
    /// T-465 case, which nothing can see from the filename); and it buys a convention rather than
    /// a guard. Refusing the empty run catches every route into it at once, including the ones
    /// nobody has thought of, and costs nothing today.
    ///
    /// This test pins that `scripts/xcb.sh` still carries the refusal. It is a source scan and
    /// says so: it cannot run the script from a sandboxed test host, so it checks the two things a
    /// scan honestly can — that the postflight still counts, branches and fails, and that the
    /// pattern it counts with still tells a real result line apart from an empty run's log.
    @Test func theGuardedRunnerStillRefusesATestRunThatExecutedNothing() throws {
        let instrument = try CadenceScanInstrument(
            "a runner that lets a zero-test run report success",
            fires: Self.unguardedPostflightWitness,
            andNotOn: Self.guardedPostflightWitness,
            by: CadenceTestRunGuard.letsAnEmptyTestRunPass
        )

        let runner = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        // Non-vacuity: this is the runner, read whole. A scan of an empty string would satisfy the
        // detector's own definition of "unguarded" and so could only ever fail loudly — but a scan
        // of the *wrong file* could not, so pin which file this is.
        #expect(runner.count > 4_000, "scripts/xcb.sh read as \(runner.count) characters")
        #expect(runner.contains("Guarded xcodebuild"), "scripts/xcb.sh is not the runner any more")

        #expect(
            !instrument.fires(on: runner),
            "scripts/xcb.sh no longer turns a test run that executed nothing into a failure"
        )
    }

    /// The other half, and the one a text scan usually cannot give: the runner's detector still
    /// *discriminates*. The pattern is lifted out of the script and run against two literal logs —
    /// the empty run xcodebuild calls a success, and a real one — so a typo inside the shell
    /// quotes fails here instead of silently matching nothing and passing every run.
    ///
    /// The pattern is written in the intersection of POSIX ERE and ICU on purpose: alternation, a
    /// bracket class, `+` and an escaped paren, and nothing else. **No `^`** — grep anchors it to
    /// each line and `NSRegularExpression` anchors it to the whole string unless told otherwise,
    /// so a `^` here would mean two different things and this test would stop being evidence about
    /// the script. If the pattern ever needs a construct the two spell differently, replace this
    /// test rather than relax it.
    @Test func theRunnersTestResultPatternStillTellsAnEmptyRunFromARealOne() throws {
        let runner = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        let pattern = try #require(
            CadenceTestRunGuard.testResultPattern(in: runner),
            "scripts/xcb.sh declares no TEST_RESULT_PATTERN"
        )

        // The pattern is a real regex, not `-1`-returning rubble. 4, not 2 (T-667): the bareword
        // pass/fail pair and the quoted-display-name pass/fail pair must both be seen, or the
        // pattern has regressed to the blind spot that read a passing named suite as empty.
        #expect(CadenceSourceScan.matchCount(pattern, in: Self.swiftTestingRunLog) == 4)
        #expect(CadenceSourceScan.matchCount(pattern, in: Self.xctestRunLog) == 1)
        #expect(CadenceSourceScan.matchCount(pattern, in: Self.emptyRunLog) == 0)

        // And the empty log really is the green-over-nothing shape, not just any text: it carries
        // both of the lines that make this hazard invisible.
        #expect(Self.emptyRunLog.contains("Executed 0 tests"))
        #expect(Self.emptyRunLog.contains("** TEST SUCCEEDED **"))
    }

    // MARK: - T-552 witnesses

    /// The postflight as it stood before T-552: exit code, error count, warning count, leak check.
    /// Nothing in it can tell a suite that passed from a filter that matched nothing.
    private static let unguardedPostflightWitness = """
    say "  XCODEBUILD_EXIT=$STATUS"
    say "  compile errors:  $(grep -cE '\\.swift:[0-9]+:[0-9]+: error:' "$LOG" | tr -d ' ')"
    say "  warnings:        $(grep -c 'warning:' "$LOG" | tr -d ' ')"
    exit $STATUS
    """

    /// The nearest guarded shape: the same postflight, plus a count of per-test result lines, a
    /// branch on that count being zero, and a non-zero exit assigned inside it.
    private static let guardedPostflightWitness = """
    tests_seen() { grep -acE "$TEST_RESULT_PATTERN" "$1" 2>/dev/null | tr -d ' '; }
    say "  XCODEBUILD_EXIT=$STATUS"
    say "  warnings:        $(grep -c 'warning:' "$LOG" | tr -d ' ')"
    if (( IS_TEST_RUN )); then
      RAN=$(tests_seen "$LOG")
      if (( RAN == 0 )); then
        empty_run_diagnostic "$LOG"
        (( STATUS == 0 )) && STATUS=4
      fi
    fi
    exit $STATUS
    """

    /// A run that was filtered to a suite name matching nothing. Every line of it is a success.
    private static let emptyRunLog = """
    Test Suite 'Selected tests' started at 2026-08-31 10:00:00.000
    Test Suite 'Selected tests' passed at 2026-08-31 10:00:00.001.
    \t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
    ** TEST SUCCEEDED **
    """

    /// A real swift-testing run: one pass and one failure in the bareword form, plus the same pair
    /// in the quoted-display-name form a `@Test("...")` case prints (T-667) -- `xcb.sh`'s pattern
    /// used to see only the first two of these four lines, which is exactly how a suite that ran
    /// and passed every case got counted as zero.
    private static let swiftTestingRunLog = """
    ◇ Test theRowStillDraws() started.
    ✔ Test theRowStillDraws() passed after 0.001 seconds.
    ✘ Test theRowDoesNot() recorded an issue at Foo.swift:12:5
    ◇ Test "The row still draws, named" started.
    ✔ Test "The row still draws, named" passed after 0.001 seconds.
    ✘ Test "The row does not, named" recorded an issue at Foo.swift:13:5
    ** TEST FAILED **
    """

    /// The XCTest shape, which this target still emits for its `XCTestCase` subclasses.
    private static let xctestRunLog = """
    Test Case '-[CadenceTests.FooTests testBar]' started.
    Test Case '-[CadenceTests.FooTests testBar]' passed (0.002 seconds).
    """

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
            if entry.hasSuffix(".md") || entry.hasSuffix(".sh") || entry.hasSuffix(".yml") || entry.hasSuffix(".yaml") {
                found.append(entry)
            }
        }
        return found.sorted()
    }

    private static let excludedPrefixes = [".git", ".build", ".codex-build", "build"]

    /// The shell text of a file: a script is shell throughout, a markdown file only inside its
    /// fenced code blocks, and a GitHub Actions workflow only inside its `run:` steps.
    static func shellText(at relativePath: String) throws -> String {
        let text = try CadenceSourceScan.sourceFile(relativePath)
        if relativePath.hasSuffix(".md") { return fencedShell(text) }
        if relativePath.hasSuffix(".yml") || relativePath.hasSuffix(".yaml") { return yamlRunBlocks(text) }
        return text
    }

    /// The shell text of every `run:` step in a GitHub Actions workflow, concatenated.
    ///
    /// Handles both shapes this repository's own workflows use: the inline form
    /// (`run: ./scripts/xcb.sh ... build`) and the block-scalar form (`run: |`, followed by an
    /// indented block) that every multi-line step here is written in. Folding style (`run: >`) is
    /// read the same as literal (`run: |`) -- this walk only needs each `xcodebuild` invocation on
    /// its own line, not YAML's own folding semantics, and preserving line breaks does that.
    ///
    /// A block scalar's extent is "more indented than the `run:` key", the same rule YAML itself
    /// uses, so a line that dedents back to the key's own indent (the next step, or a sibling key
    /// such as `if:`) ends it. `if:`, `uses:`, and every other step key are left alone; only `run:`
    /// contributes shell text, so YAML syntax elsewhere in the file is never misread as a command.
    static func yamlRunBlocks(_ yaml: String) -> String {
        var shell: [String] = []
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let indent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("run:") else { index += 1; continue }

            let after = trimmed.dropFirst("run:".count).trimmingCharacters(in: .whitespaces)
            let blockIndicators: Set<String> = ["|", "|-", "|+", ">", ">-", ">+"]
            index += 1
            if after.isEmpty || blockIndicators.contains(after) {
                while index < lines.count {
                    let body = lines[index]
                    if body.trimmingCharacters(in: .whitespaces).isEmpty {
                        shell.append("")
                        index += 1
                        continue
                    }
                    guard body.prefix(while: { $0 == " " }).count > indent else { break }
                    shell.append(body)
                    index += 1
                }
            } else {
                // Inline form: a bare command or a quoted one (YAML allows either).
                var command = after
                if let quote = command.first, quote == "\"" || quote == "'", command.count > 1,
                   command.last == quote {
                    command = String(command.dropFirst().dropLast())
                }
                shell.append(command)
            }
        }
        return shell.joined(separator: "\n")
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

    /// The value of this invocation's `-destination`, unquoted, or `nil` when it names none.
    ///
    /// Read off the command text rather than out of `tokens`, because a destination may contain a
    /// space: `'generic/platform=iOS Simulator'` tokenises into two, and the second half is not a
    /// destination. Skips rather than asserts on every malformed shape — a scan helper that traps
    /// takes the test host with it (`docs/SUBAGENT_RUNBOOK.md`).
    var destination: String? {
        guard let flag = command.range(of: "-destination ") else { return nil }
        let rest = command[flag.upperBound...].drop(while: { $0 == " " })
        guard let opening = rest.first else { return nil }
        guard opening == "'" || opening == "\"" else {
            return String(rest.prefix(while: { !$0.isWhitespace }))
        }
        let body = rest.dropFirst()
        guard let end = body.firstIndex(of: opening) else { return nil }
        return String(body[..<end])
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


/// The two readable facts about `scripts/xcb.sh`'s zero-test guard (T-552).
///
/// Separated from the suite because both are statements about *shell text* rather than about
/// Swift, and because the pattern extractor is the piece that makes the pinning worth more than
/// "the words are still in the file".
enum CadenceTestRunGuard {

    /// Whether a runner would let a test run that executed nothing report success.
    ///
    /// Three things have to be present, and the conjunction is the point: counting result lines
    /// with nothing branching on the count is a report, and branching with nothing assigning a
    /// failing status is a warning. Only all three make the empty run an error.
    ///
    /// Read over the script's commands, with `#` comment lines dropped — prose describing the
    /// guard must not be able to stand in for the guard, which is the exact substitution this
    /// whole ticket is about.
    static func letsAnEmptyTestRunPass(_ shell: String) -> Bool {
        let commands = commandLines(shell)
        let counts = commands.contains("tests_seen()")
        let branchesOnZero = CadenceSourceScan.matchCount("RAN == 0", in: commands) > 0
        let failsOnIt = CadenceSourceScan.matchCount("STATUS=4", in: commands) > 0
        return !(counts && branchesOnZero && failsOnIt)
    }

    /// The value of the script's `TEST_RESULT_PATTERN='...'` assignment, unquoted.
    static func testResultPattern(in shell: String) -> String? {
        for line in commandLines(shell).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("TEST_RESULT_PATTERN='"), trimmed.hasSuffix("'") else { continue }
            return String(trimmed.dropFirst("TEST_RESULT_PATTERN='".count).dropLast())
        }
        return nil
    }

    /// The script with whole-line `#` comments blanked, newlines kept. Deliberately crude: a
    /// trailing `#` inside a command is left alone, because dropping from it would eat the `#`
    /// in a `${TMPDIR}` idiom or a quoted path and shorten lines the checks above read.
    static func commandLines(_ shell: String) -> String {
        shell
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") ? "" : String($0) }
            .joined(separator: "\n")
    }
}
