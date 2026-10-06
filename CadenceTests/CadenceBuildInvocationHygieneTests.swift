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

    /// T-975. The runner asks whether this checkout is still HEAD before it runs tests, and it
    /// asks BEFORE taking the test-host lock — a run that cannot be trusted must not hold the host
    /// while it produces an answer about the wrong code, which is the same reasoning the
    /// locked-screen guard is placed by.
    ///
    /// Read over the script's commands with comment lines blanked, for the reason the zero-test
    /// pin gives: prose describing a guard must not be able to stand in for the guard. The order
    /// is asserted, not just the presence of both, because a drift check placed after `acquire`
    /// would still contain both strings and would still be wrong.
    @Test func theGuardedRunnerAsksWhetherTheCheckoutIsStillHeadBeforeTakingTheTestHost() throws {
        let runner = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        #expect(runner.contains("Guarded xcodebuild"), "scripts/xcb.sh is not the runner any more")

        let commands = CadenceTestRunGuard.commandLines(runner)
        let drift = try #require(
            commands.range(of: #"worktree-drift.sh" check"#),
            "scripts/xcb.sh no longer runs the T-975 drift check; a test run against a checkout behind HEAD tests the wrong code"
        )
        let lock = try #require(
            commands.range(of: #"test-host-lock.sh" acquire"#),
            "scripts/xcb.sh no longer acquires the test-host lock"
        )
        #expect(
            drift.lowerBound < lock.lowerBound,
            "the drift check runs after the test-host lock is taken, so a run that will be refused holds the host anyway"
        )
        // The refusal has to be a refusal. A check whose exit status nothing reads is a report.
        #expect(commands.contains("exit 7"),
                "scripts/xcb.sh reads the drift check's verdict but no longer fails on it")
        // And it must refuse on the FINDING, not merely on a non-zero exit. The runbook tells
        // agents to build in a `git archive HEAD` tree, which has no `.git`, so the check there
        // answers NOT-REPO-ROOT — a question that could not be asked. Refusing on that would
        // refuse the prescribed workflow, so the finding has to be named.
        #expect(commands.contains("WORKTREE-BEHIND-HEAD"),
                "scripts/xcb.sh refuses on any non-zero drift exit, which also refuses an archive tree that has no .git to compare against")
        // And it has to be scoped to the action that executes tests against this checkout. `raw`
        // must stay ungated: `mutate.sh` runs `raw test` inside a scratch tree it has deliberately
        // mutated, and gating that would refuse every mutation whose needle deletes lines.
        #expect(commands.contains(#"$ACTION" == "test""#),
                "the drift check is no longer scoped to the `test` action")
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

    /// T-1147, and it is the same question as the test above asked of the other two counters in
    /// the same banner: do they *discriminate*. They did not. `xcb.sh` counted warnings with
    /// `grep -c 'warning:'` — the loose pattern `AGENTS.md` bans for errors, one line above the
    /// anchored error count that obeys it — and MEASURED on 2026-09-12 that pattern matched
    /// exactly one line on a full test build of this repository: an `appintentsmetadataprocessor`
    /// notice about the test bundle having no AppIntents.framework dependency. So the banner read
    /// `warnings: 1` against a stated baseline of zero on every run that actually compiled
    /// something, and `warnings: 0` on the incremental runs that compiled nothing at all.
    ///
    /// Only `SWIFT_WARNING_PATTERN` is lifted and executed here. It is written in the intersection
    /// of POSIX ERE and ICU for the reason the test above gives — no `^`, nothing either engine
    /// spells differently. `SWIFT_COMPILE_TASK_PATTERN` is anchored with `^[[:space:]]*`, which is
    /// correct for grep and is exactly the construct that would mean something else here, so it is
    /// pinned as source rather than run: this asserts it exists and still names the task line.
    @Test func theRunnersWarningPatternTellsACompilerDiagnosticFromAToolNotice() throws {
        let runner = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        let pattern = try #require(
            CadenceTestRunGuard.singleQuotedAssignment("SWIFT_WARNING_PATTERN", in: runner),
            "scripts/xcb.sh declares no SWIFT_WARNING_PATTERN"
        )

        #expect(CadenceSourceScan.matchCount(pattern, in: Self.realSwiftWarningLog) == 1)
        #expect(CadenceSourceScan.matchCount(pattern, in: Self.appIntentsNoticeLog) == 0)
        // The control that makes the line above evidence rather than a pattern matching nothing:
        // the notice really does say `warning:`, which is why the loose reading counted it.
        #expect(Self.appIntentsNoticeLog.contains("warning:"))

        // The denominator half. A warning count from a run that recompiled nothing is vacuous —
        // AGENTS.md has said so for months, and every brief repeated it by hand because no
        // instrument said it. These two lines are what makes the banner able to say it itself.
        let commands = CadenceTestRunGuard.commandLines(runner)
        #expect(
            CadenceTestRunGuard.singleQuotedAssignment("SWIFT_COMPILE_TASK_PATTERN", in: runner)?
                .contains("SwiftCompile") == true,
            "scripts/xcb.sh no longer counts the compile tasks its warning count is a count over"
        )
        #expect(
            commands.contains("VACUOUS-COUNT"),
            "scripts/xcb.sh no longer says when a warning count is a count over nothing"
        )
        // And the finding itself, stated where it can regress: the line that PRINTS the count must
        // not be the loose grep. The script still runs `grep -c 'warning:'` — that is the separate
        // tool-notice count, which is the point — so asking whether the loose pattern appears
        // anywhere would assert nothing. This asks the one question that was wrong.
        let banner = commands.split(separator: "\n").filter { $0.contains("\"  warnings:") }
        #expect(banner.count == 1, "scripts/xcb.sh no longer prints exactly one `warnings:` line")
        #expect(
            banner.first?.contains("grep") == false,
            "scripts/xcb.sh prints its warning count straight out of a grep again (T-1147)"
        )
    }

    /// T-1516, and it is the same question a third time — does the counter *discriminate* — asked
    /// of the category the T-1147 anchor could not reach. `SWIFT_WARNING_PATTERN` is right and is
    /// deliberately not widened: the comment above it says the only way to lose the next
    /// `ld: warning:` for good is to grep only for `.swift:`. The cost of that is a real compiler
    /// warning raised inside a MACRO EXPANSION, which is attributed to the expansion buffer rather
    /// than to a file and so carries no `.swift:N:C:` prefix at all. It was therefore swept into
    /// the loose count and printed under a banner reading "not a compiler diagnostic", which was
    /// false about it — and `#expect` is in ~5,200 tests here, so the blind spot was the suite.
    ///
    /// **Both directions, and both witnesses are real.** A fixture proving the new pattern matches
    /// a string this test wrote itself would prove almost nothing; the whole defect was a pattern
    /// that could not match a real line. Every witness below is verbatim from `build-for-testing`
    /// logs of this repository captured 2026-09-29, with only absolute paths shortened. The macro
    /// witness carries its **whole diagnostic block** — the continuation line, the `+---` expansion
    /// banner and the `note:` line — because three of those say `warning:` or `macro expansion`
    /// and exactly one is the diagnostic: a pattern that counts the block as three reports one
    /// warning as three, which against a zero baseline is a different lie in the same place.
    ///
    /// **Two spellings exist**, and the ticket had only seen one. A freestanding macro names
    /// itself `#expect`; an ATTACHED macro names itself `@ObservationTracked`. The pattern T-1516
    /// proposed, `macro expansion [A-Za-z#]+:`, matches the first and misses every diagnostic from
    /// `@Model`, `@Observable` and `@Test` — all of which this repository expands. `[^ :]+` is
    /// name-agnostic without leaving the anchor, and is spelled in the POSIX-ERE/ICU intersection
    /// for the reason the two tests above give: it is lifted out of `xcb.sh` and run here.
    @Test func theRunnersMacroExpansionPatternCatchesTheWarningsWithNoSwiftPathPrefix() throws {
        let runner = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        let sourcePattern = try #require(
            CadenceTestRunGuard.singleQuotedAssignment("SWIFT_WARNING_PATTERN", in: runner),
            "scripts/xcb.sh declares no SWIFT_WARNING_PATTERN"
        )
        let macroPattern = try #require(
            CadenceTestRunGuard.singleQuotedAssignment("MACRO_WARNING_PATTERN", in: runner),
            "scripts/xcb.sh declares no MACRO_WARNING_PATTERN — T-1516's blind spot is back"
        )

        // The defect itself, restated as a measurement over the real line: the anchored source
        // pattern scores ZERO on a log carrying a real Swift warning, which is how `warnings: 0`
        // was printed over fourteen of them.
        #expect(CadenceSourceScan.matchCount(sourcePattern, in: Self.macroExpansionWarningBlock) == 0)
        #expect(CadenceSourceScan.matchCount(macroPattern, in: Self.macroExpansionWarningBlock) == 1)
        // …and the block really is the shape that makes the count-once claim non-trivial.
        #expect(Self.macroExpansionWarningBlock.contains("`- warning:"))
        #expect(Self.macroExpansionWarningBlock.contains("+--- macro expansion #expect"))

        // The second spelling. Attached macros print `@name`, not `#name`.
        #expect(CadenceSourceScan.matchCount(macroPattern, in: Self.attachedMacroWarningLog) == 1)
        #expect(Self.attachedMacroWarningLog.contains("macro expansion @"))

        // The direction the anchor exists to protect, which is the reason the first pattern was
        // not simply widened: every line below says `warning:` and none of them is a diagnostic.
        #expect(CadenceSourceScan.matchCount(macroPattern, in: Self.appIntentsNoticeLog) == 0)
        #expect(CadenceSourceScan.matchCount(macroPattern, in: Self.linkerAndAssetNoticeLog) == 0)
        #expect(CadenceSourceScan.matchCount(sourcePattern, in: Self.linkerAndAssetNoticeLog) == 0)
        #expect(Self.linkerAndAssetNoticeLog.contains("ld: warning:"))
        #expect(Self.linkerAndAssetNoticeLog.contains("actool: warning:"))
        // And the two patterns do not overlap: an ordinary file diagnostic is not relabelled.
        #expect(CadenceSourceScan.matchCount(macroPattern, in: Self.realSwiftWarningLog) == 0)

        // Counting it is half the ticket; GATING on it is the half that was missing. The number
        // the banner prints and the gate reads must be the sum of the two patterns, and the
        // refusal must quote the macro line or the reader is sent grepping for a path that is
        // not in the log.
        let commands = CadenceTestRunGuard.commandLines(runner)
        #expect(
            commands.contains("MACRO_WARNING_PATTERN"),
            "scripts/xcb.sh declares the macro pattern and never counts with it (T-1516)"
        )
        #expect(
            commands.contains("MACRO-EXPANSION-WARNING"),
            "scripts/xcb.sh no longer says when a warning has no `.swift:N:C:` prefix to grep for"
        )

        // The load-bearing line, read rather than trusted: the gating total must be the SUM. A
        // script that declares the second pattern, greps with it and prints the finding, while
        // leaving `warnings=` reading the first count alone, passes every check above and gates on
        // nothing — which is the state this ticket found, one pattern earlier. Neither variable
        // name is pinned; they are recovered from the two grep lines and required in the sum.
        let lines = commands.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        func assignee(countingWith pattern: String) -> String? {
            guard let line = lines.first(where: { $0.contains("grep -cE \"$\(pattern)\"") }),
                  let name = line.split(separator: "=").first, !name.isEmpty else { return nil }
            return String(name)
        }
        let sourcedVariable = try #require(assignee(countingWith: "SWIFT_WARNING_PATTERN"),
                                           "scripts/xcb.sh no longer counts with SWIFT_WARNING_PATTERN")
        let macroVariable = try #require(assignee(countingWith: "MACRO_WARNING_PATTERN"),
                                         "scripts/xcb.sh declares MACRO_WARNING_PATTERN but never counts with it")
        #expect(sourcedVariable != macroVariable, "both counts land in one variable, so one of them is lost")
        let total = try #require(lines.first(where: { $0.hasPrefix("warnings=") }),
                                 "scripts/xcb.sh no longer assigns the warning total in one place")
        #expect(
            total.contains(sourcedVariable) && total.contains(macroVariable),
            "the gating total `\(total)` does not add both counts — a macro-expansion warning is back to exiting 0 (T-1516)"
        )
    }

    /// T-1620, and it is the counter *beside* the two above asked the same question a fourth time.
    /// `tool notices:` is the subtraction left over when the anchored warning counts are taken out
    /// of the loose `grep -c 'warning:'` reading, and its own banner says what it claims to hold:
    /// "lines saying `warning:` that are not a compiler diagnostic". It was wrong about that on
    /// exactly the runs it matters on.
    ///
    /// **A diagnostic is not one line.** The Swift snippet renderer prints the primary
    /// `file:LINE:COL: warning:` line and then repeats the whole message on a caret continuation
    /// inside the source snippet. The continuation says `warning:` and carries no
    /// `name:LINE:COL:`, so it matches neither anchored pattern — correctly, because counting it
    /// would report one warning as two — and fell straight through into the notice bucket. Every
    /// real warning therefore manufactured at least one phantom notice, which means the one number
    /// in the banner that is supposed to be diagnostic-free was inflated **precisely** on the runs
    /// that have diagnostics: the runs somebody is reading the banner to triage.
    ///
    /// **Measured, twice, on real bytes.** On the captured T-1516 probe log of 2026-09-29: 6 loose
    /// `warning:` lines over 3 real macro-expansion diagnostics, reported as `warnings: 3` plus
    /// `tool notices: 3`, where the true tool-notice count in that log is **0**. And on the
    /// witness below, captured fresh from `xcrun swiftc -typecheck` of a two-deprecation probe on
    /// 2026-10-01: 4 loose lines over 2 diagnostics, 2 of them continuations, true notices 0.
    ///
    /// **Why this test can only be written with a log that has BOTH.** A fixture with one notice
    /// and no diagnostics passes with the defect fully intact — `loose - warnings` is right
    /// whenever there is nothing to continue — and a fixture with diagnostics and no notices is
    /// equally satisfied by a counter hard-wired to zero, which would delete the `ld:` and
    /// `actool:` readings the T-1147 anchor exists to keep. So the controls below are as
    /// load-bearing as the finding: a genuine notice must NOT match the continuation pattern, and
    /// neither must a primary diagnostic line, which is already subtracted as a warning and would
    /// otherwise be subtracted twice.
    @Test func theRunnersNoticeCountReadsADiagnosticsContinuationAsPartOfTheDiagnostic() throws {
        let runner = try CadenceSourceScan.sourceFile("scripts/xcb.sh")
        let sourcePattern = try #require(
            CadenceTestRunGuard.singleQuotedAssignment("SWIFT_WARNING_PATTERN", in: runner),
            "scripts/xcb.sh declares no SWIFT_WARNING_PATTERN"
        )
        let macroPattern = try #require(
            CadenceTestRunGuard.singleQuotedAssignment("MACRO_WARNING_PATTERN", in: runner),
            "scripts/xcb.sh declares no MACRO_WARNING_PATTERN"
        )
        let continuationPattern = try #require(
            CadenceTestRunGuard.singleQuotedAssignment("CONTINUATION_WARNING_PATTERN", in: runner),
            "scripts/xcb.sh declares no CONTINUATION_WARNING_PATTERN — T-1620's phantom notices are back"
        )

        // The defect restated as arithmetic over the real block: four lines say `warning:`, two of
        // them are the diagnostics, and the old reading called the other two tool notices.
        #expect(CadenceSourceScan.matchCount("warning:", in: Self.continuedSwiftWarningBlock) == 4)
        #expect(CadenceSourceScan.matchCount(sourcePattern, in: Self.continuedSwiftWarningBlock) == 2)
        #expect(CadenceSourceScan.matchCount(macroPattern, in: Self.continuedSwiftWarningBlock) == 0)
        #expect(CadenceSourceScan.matchCount(continuationPattern, in: Self.continuedSwiftWarningBlock) == 2)
        // The relation, which is what the count above is for and is the thing that must hold on
        // any toolchain: nothing in that block is a tool notice.
        #expect(
            CadenceSourceScan.matchCount("warning:", in: Self.continuedSwiftWarningBlock)
                == CadenceSourceScan.matchCount(sourcePattern, in: Self.continuedSwiftWarningBlock)
                + CadenceSourceScan.matchCount(macroPattern, in: Self.continuedSwiftWarningBlock)
                + CadenceSourceScan.matchCount(continuationPattern, in: Self.continuedSwiftWarningBlock),
            "a log of nothing but compiler diagnostics still yields a tool notice (T-1620)"
        )
        // The same shape one layer in, on the block T-1620 was actually measured on.
        #expect(CadenceSourceScan.matchCount(continuationPattern, in: Self.macroExpansionWarningBlock) == 1)

        // CONTROLS. A genuine tool notice is not a continuation, so the subtraction does not eat
        // it — the direction a pattern widened to `warning:` would break, and the whole reason
        // `tool notices:` is reported separately rather than deleted.
        #expect(CadenceSourceScan.matchCount(continuationPattern, in: Self.linkerAndAssetNoticeLog) == 0)
        #expect(CadenceSourceScan.matchCount(continuationPattern, in: Self.appIntentsNoticeLog) == 0)
        #expect(Self.linkerAndAssetNoticeLog.contains("ld: warning:"))
        // …and a PRIMARY diagnostic line is not one either. It is already subtracted as a warning;
        // a pattern matching both would subtract it twice and drive the count negative.
        #expect(CadenceSourceScan.matchCount(continuationPattern, in: Self.realSwiftWarningLog) == 0)
        #expect(CadenceSourceScan.matchCount(continuationPattern, in: Self.attachedMacroWarningLog) == 0)

        // And that the script SUBTRACTS it, which is the half a pattern declared and never used
        // would pass. The variable is not pinned by name: it is recovered from the banner that
        // prints it, so renaming it is free and losing the subtraction is not.
        let joined = CadenceTestRunGuard.commandLines(runner)
            .replacingOccurrences(of: "\\\n", with: " ")
        let lines = joined.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let banner = try #require(
            lines.first(where: { $0.hasPrefix("say ") && $0.contains("tool notices:") }),
            "scripts/xcb.sh no longer prints a tool-notice count at all"
        )
        let reported = try #require(
            Self.firstShellVariableName(in: banner),
            "scripts/xcb.sh's tool-notice banner `\(banner)` prints no variable"
        )
        let assignment = try #require(
            lines.first(where: { $0.hasPrefix("\(reported)=") }),
            "scripts/xcb.sh prints `\(reported)` and never assigns it"
        )
        #expect(
            assignment.contains("CONTINUATION_WARNING_PATTERN"),
            "the tool-notice count `\(assignment)` does not exclude a diagnostic's continuation line (T-1620)"
        )
    }

    /// The name of the first `$name` in a shell line, or `nil`. Used to read which variable a
    /// banner prints without pinning what it is called.
    private static func firstShellVariableName(in line: String) -> String? {
        guard let dollar = line.firstIndex(of: "$") else { return nil }
        let name = line[line.index(after: dollar)...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    /// The other half of T-1516, and the generalised lesson it was closed under: a guard fixed in
    /// the one place somebody could name is not a guard fixed. `.github/scripts/check-log.sh` is a
    /// second, independent copy of this reading — it gates all three CI jobs `if: always()` — and
    /// it had the identical blind spot for the identical reason. Measured 2026-09-29 against the
    /// captured log: the pre-fix script exited **0** over three real macro-expansion warnings.
    ///
    /// This does not pin a spelling, because the two scripts are in different languages and one of
    /// them may reasonably be written differently. It pins the PROPERTY, over the same real lines:
    /// some warning pattern in the CI gate must see the macro-expansion diagnostic, and no warning
    /// pattern in it may see a linker or asset notice.
    @Test func theCIGateSeesTheSameWarningsTheLocalRunnerDoes() throws {
        let ci = try CadenceSourceScan.sourceFile(".github/scripts/check-log.sh")
        let patterns = CadenceTestRunGuard.singleQuotedGrepPatterns(ci).filter { $0.contains("warning:") }
        #expect(patterns.count >= 2, ".github/scripts/check-log.sh greps for warnings with \(patterns.count) pattern(s); T-1516 needs the macro-expansion one as well")
        #expect(
            patterns.contains { CadenceSourceScan.matchCount($0, in: Self.macroExpansionWarningBlock) == 1 },
            "no warning pattern in the CI gate matches a real macro-expansion diagnostic (T-1516): \(patterns)"
        )
        #expect(
            patterns.allSatisfy { CadenceSourceScan.matchCount($0, in: Self.linkerAndAssetNoticeLog) == 0 },
            "the CI gate now counts a linker/asset notice as a compiler warning: \(patterns)"
        )
        #expect(
            patterns.allSatisfy { CadenceSourceScan.matchCount($0, in: Self.appIntentsNoticeLog) == 0 },
            "the CI gate now counts the AppIntents notice as a compiler warning: \(patterns)"
        )
        // The control for the two lines above: those logs really do say `warning:`, which is why
        // the loose reading counted them and why the anchor is not being widened.
        #expect(Self.linkerAndAssetNoticeLog.contains("warning:"))
        #expect(Self.appIntentsNoticeLog.contains("warning:"))
    }

    // MARK: - T-1851: the gate's own test counter

    /// **The number the job summary prints, counted against a log whose true contents are known.**
    ///
    /// [[T-1851]]. `.github/scripts/check-log.sh` counted a test run with a pattern that required
    /// the `identifier()` spelling and no result verb at all. Both halves of that were wrong and
    /// both were silent, because nothing in the job ever compared the figure to a second reading:
    ///
    ///  * every `@Test("A sentence in quotes")` was invisible to it, and
    ///  * each failing test matched TWICE -- once on its `recorded an issue` line and once on its
    ///    `failed after` line -- so the failure count was doubled, which is the number feeding the
    ///    `failed > 100` concurrency-collision heuristic.
    ///
    /// Measured off run `36759839618`'s `test-log` artifact, 2026-09-30: 5237 identifier results +
    /// 137 named results = 5374, exactly swift-testing's own summary line in that log. The gate
    /// printed `tests executed: 5242` (5237 real results plus 5 `recorded an issue` lines) and
    /// `tests failed: 10` over 5 failing tests.
    ///
    /// Nothing here pins a figure from CI. CI runs Xcode 26 and this Mac runs 27.0, and a log's
    /// line shapes are a toolchain property; the fixtures below are written by this test, so every
    /// number asserted is a COUNT this test itself put into the file. The claim is a RELATION:
    /// **the gate's two counts equal the fixture's own two counts**, for three fixtures that
    /// differ in exactly the dimensions the old pattern was blind to.
    ///
    /// The second and third fixtures are the controls, and they are not decoration. A `ran` reading
    /// that simply counted every `Test` line would satisfy the first fixture too; the all-identifier
    /// fixture holds it to the same answer where there is nothing extra to see, and the two must
    /// disagree with each other or the named half is being proved by a one-row table. Likewise a
    /// `failed` reading hard-wired to halve its match count would pass a one-failure fixture, so a
    /// second fixture carries two.
    @Test func theCIGateCountsEveryTestResultOnceAndEachFailureOnce() throws {
        let fixtures: [(label: String, log: CIGateTestLog)] = [
            ("mixed", CIGateTestLog(identifierTests: 3, namedTests: 2, failures: 1)),
            ("identifier-only", CIGateTestLog(identifierTests: 3, namedTests: 0, failures: 1)),
            ("two failures", CIGateTestLog(identifierTests: 4, namedTests: 3, failures: 2)),
        ]

        var observed: [String: (ran: Int, failed: Int)] = [:]
        for fixture in fixtures {
            let reading = try Self.runCIGate(over: fixture.log)
            observed[fixture.label] = (reading.ran ?? -1, reading.failed ?? -1)
            #expect(
                reading.ran == fixture.log.totalResults,
                """
                fixture `\(fixture.label)` holds \(fixture.log.totalResults) test results \
                (\(fixture.log.identifierTests) identifier-named, \(fixture.log.namedTests) \
                quoted-name, \(fixture.log.failures) failing) and the CI gate counted \
                \(reading.ran.map(String.init) ?? "nothing") (T-1851)
                \(reading.output)
                """
            )
            #expect(
                reading.failed == fixture.log.failures,
                """
                fixture `\(fixture.label)` holds \(fixture.log.failures) failing test(s), each \
                writing one `recorded an issue` line and one `failed after` line, and the CI gate \
                counted \(reading.failed.map(String.init) ?? "nothing") (T-1851)
                \(reading.output)
                """
            )
        }

        // The control, stated as its own assertion rather than left implicit: the two fixtures
        // with the same identifier count must NOT report the same total, or the named half of the
        // pattern is being proved by a table where it cannot matter.
        #expect(
            observed["mixed"]?.ran != observed["identifier-only"]?.ran,
            """
            the gate gives the same total for a fixture with 2 quoted-name tests and one with none \
            (\(observed["mixed"]?.ran ?? -1) vs \(observed["identifier-only"]?.ran ?? -1)); \
            whatever it is counting, it is not test results (T-1851)
            """
        )
        #expect(
            observed["mixed"]?.failed != observed["two failures"]?.failed,
            "the gate gives the same failure count for a 1-failure and a 2-failure fixture (T-1851)"
        )
    }

    /// The other two readings the counter is responsible for, which the fix above must not have
    /// cost: T-552's zero-test refusal, and T-1851's own new self-audit.
    ///
    /// The first is the gate's actual job -- a `-only-testing:` name that matches nothing is a
    /// GREEN run over zero tests -- and it is the one place a NARROWER pattern could have done
    /// damage. The second is why the blind spot was able to hide for as long as it did: nothing
    /// compared the grep to swift-testing's own declared total. Now a shortfall says so by name,
    /// so the next spelling this pattern cannot read announces itself instead of printing a
    /// plausible wrong number.
    @Test func theCIGateStillRefusesAZeroTestRunAndNowNoticesAShortfall() throws {
        let empty = try Self.runCIGate(over: CIGateTestLog(identifierTests: 0, namedTests: 0, failures: 0))
        #expect(empty.ran == 0, "a log with no test results counted \(empty.ran.map(String.init) ?? "nothing")")
        #expect(empty.status != 0, "the T-552 zero-test refusal no longer fails the gate\n\(empty.output)")
        #expect(empty.output.contains("T-552"), "the zero-test refusal no longer names T-552\n\(empty.output)")

        // A log whose declared total exceeds the results the pattern can see: exactly the shape of
        // the defect, synthesised by overstating the summary line rather than by inventing a name
        // form, so this stays true whatever spelling a future toolchain picks.
        var overstated = CIGateTestLog(identifierTests: 3, namedTests: 2, failures: 1)
        overstated.declaredTotalOverride = 99
        let shortfall = try Self.runCIGate(over: overstated)
        #expect(
            shortfall.output.contains("T-1851"),
            """
            the gate saw \(shortfall.ran.map(String.init) ?? "nothing") results against a declared \
            99 and said nothing about the gap; that silence is the whole reason the undercount \
            survived (T-1851)
            \(shortfall.output)
            """
        )
        // ...and the control for it: the honest fixture must NOT raise the shortfall notice, or
        // the notice is noise and will be tuned out.
        let honest = try Self.runCIGate(over: CIGateTestLog(identifierTests: 3, namedTests: 2, failures: 1))
        #expect(
            !honest.output.contains("T-1851"),
            "the shortfall notice fires on a log whose counts agree, so it says nothing\n\(honest.output)"
        )
    }

    /// **The failure count was printed and not gated: `tests failed: 1`, exit 0.**
    ///
    /// [[T-1981]], measured 2026-10-02 by running the shipped `.github/scripts/check-log.sh` over
    /// two real logs from this Mac's own `$TMPDIR`: `cadence-xcb-landgate-unit` 20261001-192525
    /// (46 results, 1 failing) read `tests failed: 1` and exited **0**, and
    /// `cadence-xcb-heartbeat` 20261001-192612 (5451 results, 3 failing) read `tests failed: 3`
    /// and exited **0**. The only test-shaped gates were [[T-552]]'s `ran == 0` and the
    /// `failed > 100` *warning* for [[T-236]]'s collision shape, and neither covers one failure.
    ///
    /// **Why the fixture now carries SUCCEEDED banners, and why that is the whole test.** A
    /// failing `CIGateTestLog` ends `** TEST FAILED **` and nothing else, so `succeeded == 0`
    /// reddened it already — an assertion that "the gate fails on a failing log" would have passed
    /// over a gate that never reads the failure count at all. A real red `test` log is not that
    /// shape: the one measured above carries **6** per-target `** BUILD SUCCEEDED **` banners
    /// beside its `** TEST FAILED **`, which is exactly why `succeeded == 0` never fired on it.
    /// The fixtures below mirror that, and the test asserts the gate does NOT name the banner
    /// check — so the redness can only be coming from the count.
    ///
    /// **And a real red log trips BOTH of T-1981's gates**, so a status alone does not say which
    /// one is carrying it — the one-candidate trap wearing a different hat. Measured against a copy
    /// of the script with the failure gate deleted: the realistic fixture still exited 1, on the
    /// banner. The count gate is therefore held by its own message AND by a second fixture with no
    /// final banner at all, the shape a clipped artifact takes, where the count is the only signal.
    ///
    /// **And the other direction**, because a gate that fires on everything is worth no more than
    /// one that fires on nothing: the same fixture with zero failures must stay green, and the
    /// `failed > 100` collision heuristic must stay a *warning* rather than becoming a second
    /// error on a log that is already red for the honest reason.
    @Test func theCIGateFailsARunWhoseTestsFailedInsteadOfPrintingTheCount() throws {
        var red = CIGateTestLog(identifierTests: 40, namedTests: 5, failures: 1)
        red.succeededBanners = 6
        let redReading = try Self.runCIGate(over: red)
        #expect(redReading.failed == 1, "fixture holds 1 failing test; the gate counted \(redReading.failed.map(String.init) ?? "nothing")")
        #expect(
            redReading.status != 0,
            """
            the gate read `tests failed: 1` off a log with a failing test and exited \
            \(redReading.status); that is T-1981 verbatim
            \(redReading.output)
            """
        )
        #expect(redReading.output.contains("T-1981"), "the failure gate does not name its ticket\n\(redReading.output)")
        // The reason this fixture is not proved by an unrelated gate: the banner check cannot be
        // what reddened it, because six SUCCEEDED banners are in the log.
        #expect(
            !redReading.output.contains("no BUILD/TEST SUCCEEDED banner"),
            """
            the fixture went red on `succeeded == 0`, not on its failure count, so this proves \
            nothing about T-1981 — a real red test log carries 6 SUCCEEDED banners
            \(redReading.output)
            """
        )
        // ...and the SECOND thing that could be reddening it, which a status alone cannot rule
        // out: T-1981 adds TWO gates and a real red log trips both. Measured 2026-10-02 against a
        // copy of the script with the failure gate deleted — the fixture above still exited 1, on
        // the banner. So the count gate is held by its own message, and by the fixture below.
        #expect(
            redReading.output.contains("1 test(s) failed"),
            """
            the gate reddened without saying a test failed, so the failure COUNT is still ungated \
            and something else is carrying the status (T-1981)
            \(redReading.output)
            """
        )

        // THE ISOLATING FIXTURE. One failing test and NO `** TEST FAILED **` banner at all — the
        // shape a clipped or truncated artifact takes, and the only shape in which the failure
        // count is the sole signal. Deleting the count gate leaves this green; measured.
        var countOnly = CIGateTestLog(identifierTests: 40, namedTests: 5, failures: 1)
        countOnly.succeededBanners = 6
        countOnly.finalBannerOverride = ""
        let countOnlyReading = try Self.runCIGate(over: countOnly)
        #expect(
            countOnlyReading.status != 0,
            """
            a log with a failing test and no final banner read as a clean run (exit \
            \(countOnlyReading.status)); with the banner absent the count is the only signal there \
            is, so this is the failure gate on its own (T-1981)
            \(countOnlyReading.output)
            """
        )

        // CONTROL, the other direction. Same shape, no failing test: the gate must stay green, or
        // it has stopped discriminating and every CI run is red from here on.
        var green = CIGateTestLog(identifierTests: 40, namedTests: 5, failures: 0)
        green.succeededBanners = 6
        let greenReading = try Self.runCIGate(over: green)
        #expect(greenReading.failed == 0, "a fixture with no failing test counted \(greenReading.failed.map(String.init) ?? "nothing")")
        #expect(
            greenReading.status == 0,
            """
            the new failure gate reddens a log with zero failing tests (exit \(greenReading.status)); \
            a gate that fires on everything says as little as one that fires on nothing
            \(greenReading.output)
            """
        )
        #expect(
            !greenReading.output.contains("T-1981"),
            "the failure gate announces itself on a green log, so its message is noise\n\(greenReading.output)"
        )

        // ...and the two readings must DIFFER, stated rather than left to be inferred from two
        // separate expectations that a constant would satisfy one at a time.
        #expect(
            redReading.status != greenReading.status,
            "the gate gives the same status for a 1-failure log and a 0-failure log (T-1981)"
        )

        // T-236's collision heuristic stays a WARNING. It explains a large count; it is not a
        // second error, and promoting it would re-triage every genuine red run as a collision.
        #expect(
            !redReading.output.contains("::warning::1 failures"),
            "the collision heuristic fired on a single failure\n\(redReading.output)"
        )
    }

    /// **The banner, separately — because the count can be zero on a run that still failed.**
    ///
    /// [[T-1981]]'s second half. A crashed test host, or a runner that exits early, ends the log
    /// with `** TEST FAILED **` and leaves no `failed after` line to count. T-552's `ran == 0`
    /// catches only the subset where nothing ran at all, and `succeeded == 0` cannot catch it
    /// either once per-target build banners are in the log.
    ///
    /// **The anchor is the point, and its witness is real.** `cadence-xcb-heartbeat` 20261001-192612
    /// contains the string `** TEST FAILED **` TWICE: once as xcodebuild's banner at column 0, and
    /// once as `          "** TEST FAILED **" \`, a line of `scripts/xcb.sh`'s own selftest
    /// fixture quoted back into the log by a failing `CadenceGuardScriptSelftestTests` expectation.
    /// That is [[T-1971]]'s defect in banner form: a loose grep would redden a GREEN run whose
    /// output happens to print that script. The second fixture here is that exact line, in an
    /// otherwise passing run, and it must stay green.
    @Test func theCIGateTreatsATestFailedBannerAsFatalWithoutReadingEveryQuotedCopyOfIt() throws {
        // A run that failed with nothing countable: every result passed, and the run still ended
        // `** TEST FAILED **`.
        var crashed = CIGateTestLog(identifierTests: 12, namedTests: 0, failures: 0)
        crashed.succeededBanners = 6
        crashed.finalBannerOverride = "** TEST FAILED **"
        let crashedReading = try Self.runCIGate(over: crashed)
        #expect(crashedReading.failed == 0, "the fixture has no failing result line; the gate counted \(crashedReading.failed.map(String.init) ?? "nothing")")
        #expect(crashedReading.ran == 12, "the fixture has 12 results; the gate counted \(crashedReading.ran.map(String.init) ?? "nothing")")
        #expect(
            crashedReading.status != 0,
            """
            a log ending `** TEST FAILED **` with 12 passing results and no failing one read as a \
            clean run (exit \(crashedReading.status)). The failure COUNT cannot see this shape and \
            T-552's zero-test refusal does not either, because 12 tests ran (T-1981)
            \(crashedReading.output)
            """
        )

        // CONTROL. The same green run, with one INDENTED line quoting the banner, as a real log of
        // this repository's own suite contains. The anchor is the only thing between this and a
        // gate that reddens whenever a test prints a script.
        var quoting = CIGateTestLog(identifierTests: 12, namedTests: 0, failures: 0)
        quoting.succeededBanners = 6
        quoting.quotesTheBannerInTestOutput = true
        let quotingReading = try Self.runCIGate(over: quoting)
        #expect(
            quotingReading.status == 0,
            """
            the banner gate reddened a passing run because its OUTPUT quoted the banner, indented, \
            which `cadence-xcb-heartbeat` 20261001-192612 really does (T-1971's shape, T-1981's \
            gate); exit \(quotingReading.status)
            \(quotingReading.output)
            """
        )
        #expect(
            crashedReading.status != quotingReading.status,
            """
            the gate gives the same status for a log whose banner is xcodebuild's and one whose \
            banner is a quoted line of shell in a passing test's output (T-1981)
            """
        )
    }

    /// A synthetic `xcodebuild` test log, in the shapes Swift Testing actually writes. Only the
    /// lines this gate reads are modelled; the suite scaffolding is there so the fixture is a
    /// plausible log rather than a list of needles.
    struct CIGateTestLog {
        var identifierTests: Int
        var namedTests: Int
        var failures: Int
        /// Overstates the `Test run with N tests` summary without changing the body, to synthesise
        /// a result spelling the gate cannot read.
        var declaredTotalOverride: Int?
        /// Per-target `** BUILD SUCCEEDED **` banners, which a real red `test` log carries
        /// ALONGSIDE its `** TEST FAILED **` -- six of them in the log [[T-1981]] was measured on.
        /// Without these a failing fixture is red for the WRONG reason (`succeeded == 0`), and a
        /// test asserting that the gate reddens on a failure would pass over a gate that does not
        /// read the failure count at all.
        var succeededBanners: Int = 0
        /// Replaces the final banner the body would otherwise choose, to synthesise the one shape
        /// the failure COUNT cannot see: a run that failed without any countable result line.
        var finalBannerOverride: String?
        /// Emits, inside the test output, an INDENTED line that merely quotes the banner. Measured
        /// off `cadence-xcb-heartbeat` 20261001-192612, where a failing
        /// `CadenceGuardScriptSelftestTests` expectation printed `scripts/xcb.sh`'s own selftest
        /// fixture back into the log: `          "** TEST FAILED **" \\`. A loose banner grep
        /// counts that line.
        var quotesTheBannerInTestOutput: Bool = false

        /// Failing tests are identifier-named, matching the artifact this was measured against.
        var totalResults: Int { identifierTests + namedTests + failures }

        var text: String {
            var lines = [
                "Command line invocation:",
                "    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test",
                "SwiftCompile normal arm64 Compiling\\ Fixture.swift /fixture/Fixture.swift",
            ]
            for _ in 0..<succeededBanners {
                lines.append("** BUILD SUCCEEDED **")
            }
            lines.append(contentsOf: [
                "Testing started",
                "◇ Suite CadenceFixtureSuite started.",
            ])
            for index in 0..<identifierTests {
                lines.append("◇ Test aFixtureTestNumber\(index)() started.")
                lines.append("✔ Test aFixtureTestNumber\(index)() passed after 0.001 seconds.")
            }
            for index in 0..<namedTests {
                lines.append("◇ Test \"A fixture sentence number \(index)\" started.")
                lines.append("✔ Test \"A fixture sentence number \(index)\" passed after 0.001 seconds.")
            }
            for index in 0..<failures {
                lines.append("◇ Test aFailingFixtureTest\(index)() started.")
                lines.append("✘ Test aFailingFixtureTest\(index)() recorded an issue at Fixture.swift:1:1: Expectation failed")
                lines.append("✘ Test aFailingFixtureTest\(index)() failed after 0.001 seconds with 1 issue.")
            }
            lines.append("✔ Suite CadenceFixtureSuite passed after 0.100 seconds.")
            if quotesTheBannerInTestOutput {
                lines.append("          \"** TEST FAILED **\" \\")
            }
            if totalResults > 0 {
                let declared = declaredTotalOverride ?? totalResults
                let mark = failures > 0 ? "✘" : "✔"
                let verb = failures > 0 ? "failed" : "passed"
                lines.append("\(mark) Test run with \(declared) tests in 1 suites \(verb) after 0.100 seconds.")
            }
            lines.append(finalBannerOverride ?? (failures > 0 ? "** TEST FAILED **" : "** TEST SUCCEEDED **"))
            return lines.joined(separator: "\n") + "\n"
        }
    }

    struct CIGateReading {
        var status: Int32
        var output: String
        var ran: Int?
        var failed: Int?
    }

    /// Writes the fixture under the TEST's own temporary directory -- never beside anything the
    /// gate or the repository owns -- and runs the real `.github/scripts/check-log.sh` over it.
    ///
    /// Run under `/bin/bash` because that is the script's shebang. This repository mixes shells and
    /// a reading taken under the wrong one is not a reading of the shipped script (T-1334/T-1343).
    static func runCIGate(over log: CIGateTestLog) throws -> CIGateReading {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("cadence-ci-gate-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let logURL = scratch.appendingPathComponent("cadence-xcb-fixture-tests.log")
        try log.text.write(to: logURL, atomically: true, encoding: .utf8)

        let script = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent(".github/scripts/check-log.sh").path
        let shebang = try String(contentsOfFile: script, encoding: .utf8).hasPrefix("#!/bin/bash")
        #expect(shebang, "check-log.sh's shebang changed; this test runs it under /bin/bash on purpose")
        let run = try CadenceSelftestRun.run("/bin/bash", [script, logURL.path, "test"])
        return CIGateReading(
            status: run.status,
            output: run.output,
            ran: number(after: "tests executed:", in: run.output),
            failed: number(after: "tests failed:", in: run.output)
        )
    }

    static func number(after label: String, in output: String) -> Int? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " })
            guard trimmed.hasPrefix(label) else { continue }
            return Int(trimmed.dropFirst(label.count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    // MARK: - T-1781: the warning gate is not a macOS gate

    /// **An iOS-only compiler warning and the zero-warning baseline, measured rather than
    /// reasoned — and the ticket's central claim is REFUTED.**
    ///
    /// [[T-1781]] reads: *"every gate that enforces it builds macOS ... `scripts/xcb.sh` exit 9 and
    /// `.github/scripts/check-log.sh` only ever see a macOS log, so the baseline is structurally
    /// blind to an entire platform."* Half of that is true and the load-bearing half is not.
    ///
    /// Measured 2026-09-30 on one `git archive HEAD` tree with one deliberate iOS-only warning
    /// injected inside `Cadence/iOS/iOSAppDelegate.swift`'s `#if os(iOS)` fence (an unused
    /// immutable, `[#NoUsage]`), built twice through `scripts/xcb.sh`:
    ///
    /// | destination                          | compile tasks | warnings | `xcb.sh` | `check-log.sh` |
    /// |--------------------------------------|---------------|----------|----------|----------------|
    /// | `platform=macOS`                     | 695           | 0        | exit 0   | exit 0         |
    /// | `generic/platform=iOS Simulator`     | 1390          | 2        | **9**    | **1**          |
    ///
    /// **Neither task count is a floor, and the pair is not a coincidence** (T-1703, re-measured
    /// 2026-10-06): `xcb.sh` counts one `SwiftCompile` task per file *per architecture*, a generic
    /// simulator destination resolves to arm64 **and** x86_64, and a concrete `id=<udid>` resolves
    /// to one. So 1390 is exactly 2 x 695, the same tree gave 1382 / 691 a month later as files
    /// changed, and **695 on a concrete iOS destination is a complete, non-vacuous iOS build.**
    /// The macOS arm64 slice and the iOS arm64 slice compile a byte-identical list of file names,
    /// so the count cannot identify the platform at all — only `-destination` can.
    ///
    /// So a macOS build really is blind — it compiles none of `#if os(iOS)`, and 695 tasks of it
    /// saw nothing. But **neither counter is**: both are destination-agnostic, they gate whatever
    /// log they are handed, and `.github/workflows/ci.yml`'s `ios-build` job has piped its own
    /// `cadence-xcb-ci-ios.log` through `check-log.sh` since the workflow's first commit
    /// (`6c6ce44a`, 2026-08-31), `if: always()`, on every push and pull request that survives
    /// `paths-ignore`. The three instances that prompted the ticket belonged to an *uncommitted*
    /// sibling edit, which is why CI never saw them — not because CI could not have.
    ///
    /// **What was actually missing is this test.** Nothing anywhere required the iOS job to keep
    /// its gate, so the property the ticket assumed was absent could have become absent at any
    /// time without a single failure. The residual hole is now one of latency and not of
    /// blindness: an agent who builds only macOS locally lands an iOS-only warning and learns
    /// about it from CI rather than before the push. `AGENTS.md` names the destination for that
    /// reason.
    ///
    /// The property is deliberately keyed on the *log file name* rather than on job names or step
    /// ordering: `xcb.sh` writes `${TMPDIR}cadence-xcb-<id>.log`, so `<id>` is the only thing that
    /// ties a compile to the gate that reads it, and a job that builds under a new id and forgets
    /// the Gates step fails here by name.
    @Test func everyCompilingCIJobRoutesItsOwnLogThroughTheSameWarningGate() throws {
        let shell = try Self.shellText(at: ".github/workflows/ci.yml")
        let runs = CadenceTestRunGuard.guardedRunnerInvocations(in: shell)
        let gated = CadenceTestRunGuard.gatedLogIds(in: shell)

        // Non-vacuity first: a walk that found nothing would satisfy every "for all" below.
        let compiling = runs.filter { $0.action == "build" || $0.action == "test" }
        #expect(compiling.count >= 3, "ci.yml runs \(compiling.count) compiling xcb.sh invocation(s); the walk or the workflow lost one")
        let ids = Set(compiling.map { $0.id })
        #expect(ids.isSuperset(of: ["ci-mcp", "ci-tests", "ci-ios"]), "ci.yml's compiling jobs are \(ids.sorted())")

        let ungated = compiling.filter { !gated.contains($0.id) }.map { $0.id }.sorted()
        #expect(
            ungated.isEmpty,
            """
            \(ungated) compile(s) Swift in CI and no step passes cadence-xcb-<id>.log to \
            .github/scripts/check-log.sh, so that job's warnings gate nothing (T-1781)
            """
        )

        // The half that is specifically about the platform. A gate that ran on three macOS logs
        // would satisfy everything above and would be exactly the instrument T-1781 describes.
        let gatedDestinations = compiling.filter { gated.contains($0.id) }.map { $0.destination }
        #expect(
            gatedDestinations.contains { $0.contains("iOS Simulator") },
            "no GATED CI invocation names an iOS Simulator destination, so the zero-warning baseline is a macOS baseline (T-1781): \(gatedDestinations)"
        )
        #expect(
            gatedDestinations.contains { $0.contains("platform=macOS") },
            "no gated CI invocation names a macOS destination: \(gatedDestinations)"
        )
    }

    // MARK: - T-1703: the iOS task count is an arch count

    /// **The "~1,390 swift compile tasks" floor every brief was quoting is a doubled arch count,
    /// and a brief that quotes it without the destination shape makes agents distrust good runs.**
    ///
    /// Measured 2026-10-06 through `scripts/xcb.sh` on one tree: `platform=macOS` **691**,
    /// `platform=iOS Simulator,id=<udid>` **691**, `generic/platform=iOS Simulator` **1382**,
    /// split exactly 691 `arm64` + 691 `x86_64`. A generic simulator destination resolves to every
    /// valid arch and compiles the target twice; a concrete one compiles it once. T-1492's
    /// 1,390/695 is the same 2x pair measured 2026-09-30 over four more files.
    ///
    /// So the number is not a floor — it tracks the file count and rots — and, worse, the macOS
    /// and iOS arm64 slices compile a **byte-identical list of file names**, because target
    /// membership picks the files and `#if os(iOS)` lives inside them. No count can say which
    /// platform a log is; only `-destination` can.
    ///
    /// This pins the correction where agents read it, because the wrong figure survived in briefs
    /// for a month without anything going red. Each positive check below is paired with a control
    /// that genuinely fires: the guide must still carry T-1781's macOS-blindness rule, so a rewrite
    /// that drops one half to satisfy the other cannot pass.
    @Test func theRootGuideStatesBothIOSDestinationShapesRatherThanOneTaskCount() throws {
        let guide = try CadenceSourceScan.sourceFile("AGENTS.md")
        let reference = try CadenceSourceScan.sourceFile("docs/AGENTS_REFERENCE.md")

        // Non-vacuity: these two files are read by path and an empty string satisfies nothing
        // below, but it would satisfy a `!contains` check, so assert the denominator first.
        #expect(guide.count > 5_000, "AGENTS.md read as \(guide.count) bytes")
        #expect(reference.count > 5_000, "docs/AGENTS_REFERENCE.md read as \(reference.count) bytes")

        // The correction itself. `2x` is the only stable fact; the absolute numbers are examples.
        #expect(
            guide.contains("ARCH count, not a floor"),
            "root AGENTS.md no longer says a compile-task count is an arch count (T-1703)"
        )
        #expect(
            guide.contains("concrete `platform=iOS Simulator,id=<udid>`"),
            "root AGENTS.md names no concrete iOS destination, so 695 still reads as a failed build"
        )
        #expect(
            guide.contains("generic/platform=iOS Simulator"),
            "root AGENTS.md no longer names the generic destination the doubled count comes from"
        )
        #expect(
            guide.contains("NON-vacuous"),
            "root AGENTS.md no longer says a concrete-destination iOS build is non-vacuous"
        )

        // The control that keeps the clause honest: T-1781's finding must survive the correction.
        // Collapsing "the count cannot identify the platform" into "macOS is fine for iOS" would
        // satisfy every check above and is the misreading this replaces one misreading with.
        #expect(
            guide.contains("a macOS build is not"),
            "root AGENTS.md lost T-1781's rule that a macOS build is blind to `#if os(iOS)`"
        )

        // And the long half, which is where the measurement lives.
        #expect(
            reference.contains("## The iOS compile-task count is an ARCH count, not a floor"),
            "docs/AGENTS_REFERENCE.md lost the section the guide's clause is the summary of"
        )
        for row in ["| **691**", "| **1382**", "arm64 **+** x86_64"] {
            #expect(reference.contains(row), "docs/AGENTS_REFERENCE.md lost the measured row \(row)")
        }
    }

    // MARK: - T-1516 witnesses

    /// ONE real diagnostic, whole, out of a `build-for-testing` log of this repository captured
    /// 2026-09-29 — the absolute source path is the only edit. The cause is the one T-1516
    /// recorded: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app target plus the
    /// `InferIsolatedConformances` upcoming feature make a synthesised `Equatable` conformance
    /// main-actor isolated, while the `#expect` expansion that uses it is not.
    ///
    /// Four of its nine lines say `warning:` or `macro expansion`. Exactly one is the diagnostic.
    private static let macroExpansionWarningBlock = """
    SwiftCompile normal arm64 Compiling\\ ZZProbeMacroWarning.swift /repo/CadenceTests/ZZProbeMacroWarning.swift (in target 'CadenceTests' from project 'Cadence')
    macro expansion #expect:1:39: warning: main actor-isolated conformance of \
    'RemindersConnectionState' to 'Equatable' cannot be used in nonisolated context; this is an \
    error in the Swift 6 language mode [#IsolatedConformances]
    `- /repo/CadenceTests/ZZProbeMacroWarning.swift:8:24: note: expanded code originates here
     8 |         #expect(a == b)
       |         `- note: in expansion of macro 'expect' here
       +--- macro expansion #expect ----------------------------------------
       |1 | Testing.__checkBinaryOperation(a,{ $0 == $1() },b,expression: .__fromBinaryOperation(.__fromSyntaxNode("a"),"==",.__fromSyntaxNode("b")),comments: [],isRequired: false,sourceLocation: Testing.SourceLocation.__here()).__expected()
       |  |                                       `- warning: main actor-isolated conformance of \
    'RemindersConnectionState' to 'Equatable' cannot be used in nonisolated context; this is an \
    error in the Swift 6 language mode [#IsolatedConformances]
       +--------------------------------------------------------------------
    """

    /// The second spelling, from the same batch of logs: an ATTACHED macro names itself with `@`.
    /// `@Observable` expands to `@ObservationTracked`, and a deprecation raised inside that
    /// expansion is reported against the expansion, not against the property that caused it.
    private static let attachedMacroWarningLog = """
    SwiftCompile normal arm64 Compiling\\ ZZProbeMacroWarning.swift /repo/CadenceTests/ZZProbeMacroWarning.swift (in target 'CadenceTests' from project 'Cadence')
    macro expansion @ObservationTracked:2:24: warning: 'ZZProbeDeprecated' is deprecated: probe [#DeprecatedDeclaration]
    """

    // MARK: - T-1620 witness

    /// Two real Swift diagnostics WITH their snippet continuations, captured verbatim from
    /// `xcrun swiftc -typecheck` of a two-deprecation probe on this Mac, 2026-10-01, with only the
    /// path shortened to `/repo/`. Four of its lines say `warning:` and exactly two are
    /// diagnostics; the other two are the caret continuations the notice count used to claim.
    ///
    /// It is a fresh capture rather than a hand-written shape for the reason every witness in this
    /// file is: the defect is about which real lines a pattern reaches. Six real diagnostics across
    /// three probe compiles on this toolchain print the continuation marker as `` `- `` and nothing
    /// else — `|- warning:` was looked for in all of them and never seen, which is why the pattern
    /// lifted above does not try to match a shape this repository cannot show a line for.
    private static let continuedSwiftWarningBlock = """
    /repo/CadenceTests/Probe.swift:5:13: warning: 'zzDeprecated()' is deprecated: probe [#DeprecatedDeclaration]
    5 |     let p = zzDeprecated() + zzDeprecated()
      |             `- warning: 'zzDeprecated()' is deprecated: probe [#DeprecatedDeclaration]
    /repo/CadenceTests/Probe.swift:5:30: warning: 'zzDeprecated()' is deprecated: probe [#DeprecatedDeclaration]
    5 |     let p = zzDeprecated() + zzDeprecated()
      |                              `- warning: 'zzDeprecated()' is deprecated: probe [#DeprecatedDeclaration]
    """

    /// The two notices the `.swift:` anchor exists to exclude, in the canonical form the comment
    /// above `SWIFT_WARNING_PATTERN` names them in. Unlike every other witness here these are NOT
    /// captured from this tree — it emits neither today, which is precisely why they have to be
    /// asserted rather than waited for: the failure they guard against is a later widening that
    /// turns every link and asset notice into a red build.
    private static let linkerAndAssetNoticeLog = """
    ld: warning: ignoring duplicate libraries: '-lc++'
    actool: warning: The app icon set "AppIcon" has an unassigned child.
    """

    // MARK: - T-1147 witnesses

    /// One real Swift diagnostic, copied out of a build log of this repository on 2026-09-12.
    private static let realSwiftWarningLog = """
    /repo/CadenceTests/HabitFrequencyLabelTests.swift:15:13: warning: initialization of immutable \
    value 'instrufixWarningProbe' was never used; consider replacing with assignment to '_'
    """

    /// The tool notice that was being counted as one. Also copied verbatim: it is the only line
    /// matching `warning:` in a full `build-for-testing` log of this repository.
    private static let appIntentsNoticeLog = """
    2026-09-12 04:37:24.072 appintentsmetadataprocessor[66824:4236838] warning: Metadata \
    extraction skipped. No AppIntents.framework dependency found.
    """

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
        singleQuotedAssignment("TEST_RESULT_PATTERN", in: shell)
    }

    /// The value of a `NAME='...'` assignment among the script's commands, unquoted. Comment lines
    /// are already gone, so prose quoting a pattern cannot stand in for the pattern (T-552's rule,
    /// and the reason this reads `commandLines` rather than the raw source).
    static func singleQuotedAssignment(_ name: String, in shell: String) -> String? {
        let prefix = name + "='"
        for line in commandLines(shell).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("'") else { continue }
            return String(trimmed.dropFirst(prefix.count).dropLast())
        }
        return nil
    }

    /// Every single-quoted pattern the script hands to `grep -E` / `grep -cE`, in source order.
    /// Comments are blanked first, so a pattern quoted in prose is not mistaken for one the gate
    /// runs — which matters here, because `check-log.sh`'s own header quotes the pattern it uses.
    static func singleQuotedGrepPatterns(_ shell: String) -> [String] {
        var found: [String] = []
        let text = commandLines(shell)
        for opener in ["grep -cE '", "grep -E '", "grep -acE '", "grep -aE '"] {
            var cursor = text.startIndex
            while let start = text.range(of: opener, range: cursor..<text.endIndex) {
                guard let end = text.range(of: "'", range: start.upperBound..<text.endIndex) else { break }
                found.append(String(text[start.upperBound..<end.lowerBound]))
                cursor = end.upperBound
            }
        }
        return found
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

    // MARK: - T-1781: what CI compiles, and what reads the log it wrote

    /// Every `scripts/xcb.sh <id> <action> ... -destination <value>` in the shell text, with its
    /// backslash continuations joined first.
    ///
    /// Joining is the whole of why this reads the invocation rather than the line: in `ci.yml`
    /// the id and the action sit on the `xcb.sh` line and the destination is four continuations
    /// below it, so a per-physical-line walk would find the id of every job and the destination of
    /// none — and would then happily report that no CI job builds for a simulator.
    static func guardedRunnerInvocations(in shell: String) -> [(id: String, action: String, destination: String)] {
        var found: [(id: String, action: String, destination: String)] = []
        let joined = commandLines(shell).replacingOccurrences(of: "\\\n", with: " ")
        for line in joined.split(separator: "\n", omittingEmptySubsequences: false) {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let index = tokens.firstIndex(where: { $0.hasSuffix("xcb.sh") }),
                  index + 2 < tokens.count else { continue }
            var destination = ""
            if let flag = tokens.firstIndex(of: "-destination"), flag + 1 < tokens.count {
                // The value is single-quoted and holds a space (`generic/platform=iOS Simulator`),
                // so it is read from the raw line rather than reassembled out of tokens.
                if let open = line.range(of: "-destination '"),
                   let close = line[open.upperBound...].firstIndex(of: "'") {
                    destination = String(line[open.upperBound..<close])
                } else {
                    destination = tokens[flag + 1]
                }
            }
            found.append((id: tokens[index + 1], action: tokens[index + 2], destination: destination))
        }
        return found
    }

    /// The `<id>` of every `cadence-xcb-<id>.log` handed to `check-log.sh` in the shell text.
    ///
    /// Keyed on the log name and not on the job or step, because the log name is the only thing
    /// that ties a gate to the compile it is a gate for: `xcb.sh` writes
    /// `${TMPDIR}cadence-xcb-<id>.log`, and a `Gates` step naming a DIFFERENT id would read a log
    /// this job never wrote and pass over it.
    static func gatedLogIds(in shell: String) -> Set<String> {
        var ids: Set<String> = []
        for line in commandLines(shell).split(separator: "\n", omittingEmptySubsequences: false)
        where line.contains("check-log.sh") {
            guard let start = line.range(of: "cadence-xcb-") else { continue }
            let rest = line[start.upperBound...]
            guard let end = rest.range(of: ".log") else { continue }
            ids.insert(String(rest[..<end.lowerBound]))
        }
        return ids
    }
}
