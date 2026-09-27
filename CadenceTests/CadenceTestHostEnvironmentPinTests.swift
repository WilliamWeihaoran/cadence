import Foundation
import Testing

/// What a green `CadenceTests` run is still standing on that nothing states, and the rule that
/// stops the next such claim ageing quietly into a decision.
///
/// **[[T-1116]] pinned the two ambient inputs it found and left the CHANNEL unstated.** The
/// scheme's `TestAction` pins `TZ=UTC` through the environment and `-AppleLocale en_US` through the
/// argument domain, and `CadenceTimeZoneIndependenceTests` asserts that each *value* arrived. What
/// neither assertion says is how far those channels reach. The argument domain is a per-process
/// overlay over one key at a time: it can set `AppleLocale`, and it cannot touch any *other* key
/// that System Settings writes into the global domain. Language & Region has at least four
/// switches that do exactly that, and every one of them survives the pin:
///
/// * **`AppleFirstWeekday`** — "First day of week". Moves `Calendar.current.firstWeekday` to 2 on a
///   Mac set to Monday, which is every week-shaped derivation in the target.
/// * **`AppleICUForce24HourTime`** — the 24-hour switch. This one is already *measured* in
///   `CadenceTestClocks`' doc — "read only from the global domain and ignores the argument domain
///   entirely" — and the conclusion drawn there was that the suite states its own locale. The
///   conclusion left standing was that the host's own clock is pinned. It is not, and
///   `theTestHostRunsInTheClockTheSchemePins` reports such a failure as *"either that argument was
///   dropped or `shouldUseLaunchSchemeArgsEnv` went back to YES"* — a diagnosis that cannot be true
///   of a switch the scheme has no way to set.
/// * **`AppleICUDateFormatStrings`** — the "custom date format" overrides, which re-template
///   `DateFormatter`'s `.short`/`.medium` styles under the locale that IS pinned.
/// * **`AppleICUNumberSymbols`** — the decimal/grouping separator overrides, same channel.
///
/// So the honest statement of the dependency is: **a green run additionally requires that the Mac
/// it ran on has no Language & Region override set**, and until this suite existed nothing said so,
/// nothing checked it, and the one test positioned to notice blamed the scheme.
///
/// The guard is deliberately a refusal with a name rather than a workaround. There is no way to
/// pin these from a scheme — that is the finding — so the only thing worth building is the sentence
/// that tells the next reader the machine moved and the code did not.
///
/// **[[T-1153]] is the general case of the same failure**, and it is the second half of this file.
/// A claim about the execution environment gets made once, in prose, and is then quoted, widened
/// and decided upon — T-959's one measured fact ("`/bin/ps` is refused at `posix_spawn`") became
/// "cannot spawn `ps` or `pgrep`", then "an unrecognised exec target", and three decisions cited
/// the generalisation by number. `CadenceTestHostSandboxCapabilityTests` stopped *that* sentence
/// drifting. `everyEnvironmentClaimInAnAlwaysReadGuideNamesThePinThatHoldsIt` is the rule that
/// makes the next one name its pin, the way the `try? save()` rule names
/// `CadenceSaveCommitDisciplineTests`.
@Suite struct CadenceTestHostEnvironmentPinTests {

    // MARK: - T-1116. The switches the scheme's argument domain cannot reach

    /// The keys System Settings' Language & Region pane writes into the **global** preferences
    /// domain, each of which changes an answer this target asserts on.
    ///
    /// Spelled as a list rather than checked one at a time so the failure message can name *which*
    /// switch is set: "a date assertion moved" is the symptom every one of them produces, and the
    /// whole cost of this dependency was that the symptom never named its cause.
    static let languageAndRegionOverrideKeys = [
        "AppleFirstWeekday",
        "AppleICUForce24HourTime",
        "AppleICUDateFormatStrings",
        "AppleICUNumberSymbols",
    ]

    /// Which of `keys` this process reads a value for that the scheme did not put there.
    ///
    /// A pure function of two lookups on purpose. The real caller fills them from the global
    /// preferences domain and from the process's own argv, and a detector that reached for either
    /// of those itself could only be tested on the machine it was already measuring — which is the
    /// shape of instrument this file exists to argue against.
    ///
    /// The argument-domain half is not decoration. It is the difference between "this machine has
    /// a switch set" and "the scheme pinned this key", and the two need opposite responses: the
    /// first is the unstated dependency, the second is the fix somebody eventually lands if Apple
    /// ever makes one of these reachable from a scheme.
    static func unpinnedOverrides(
        keys: [String],
        readingValueFor value: (String) -> Any?,
        pinnedByTheScheme: Set<String>
    ) -> [String] {
        keys.filter { value($0) != nil && !pinnedByTheScheme.contains($0) }
    }

    /// What the **global** preferences domain holds for `key` — `.GlobalPreferences.plist`, the one
    /// domain System Settings writes these into and the one no scheme can overlay.
    ///
    /// `CFPreferencesCopyValue` against `kCFPreferencesAnyApplication` rather than a merged
    /// defaults read, and not merely because `CadenceDefaultsRoutingSweepTests` forbids this target
    /// to name the signed-in person's own domain (T-1170). It is the more precise question: a merged
    /// read would also return a value *this app* had put in its own domain, which is not the
    /// dependency being named here. It reads and never writes.
    static func globalDomainValue(_ key: String) -> Any? {
        CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    /// Every `-key` this process was launched with — the scheme's `CommandLineArguments`, as
    /// `NSArgumentDomain` sees them.
    ///
    /// Read off `ProcessInfo` rather than `UserDefaults.volatileDomain(forName:)` because the
    /// question is what the SCHEME passed, and the volatile domain is a merged answer that a
    /// registration elsewhere could also produce. Both spellings of a scheme argument are
    /// accepted: Xcode splits `-AppleLocale en_US` into two argv entries, but a single entry
    /// carrying both words is what the scheme file literally holds, and a reader comparing the two
    /// should not have to know which one survived.
    static func schemeArgumentKeys(_ arguments: [String]) -> Set<String> {
        var keys: Set<String> = []
        for argument in arguments where argument.hasPrefix("-") {
            let name = argument.dropFirst().prefix(while: { $0 != " " })
            if !name.isEmpty { keys.insert(String(name)) }
        }
        return keys
    }

    /// The dependency itself, named.
    ///
    /// This asserts an *absence*, which is the shape that goes hollow most easily, so the
    /// detector it rests on is proven separately below against values that are actually there.
    /// What keeps this half honest is the second expectation: the pin the scheme DOES carry must
    /// be visible through the same reading. If `schemeArgumentKeys` came back empty — a run
    /// launched some other way, a scheme that lost its arguments — the absence above would be
    /// unanimous and meaningless, and this says so before that can happen.
    @Test func theLanguageAndRegionSwitchesTheSchemeCannotPinAreUnsetOnThisMachine() {
        let pinned = Self.schemeArgumentKeys(ProcessInfo.processInfo.arguments)
        #expect(
            pinned.contains("AppleLocale"),
            """
            this process was not launched with -AppleLocale, so the argument domain reading below \
            has nothing in it and its silence proves nothing. Either the run did not come from the \
            Cadence scheme's TestAction or that block lost its CommandLineArguments.
            """
        )

        let unpinned = Self.unpinnedOverrides(
            keys: Self.languageAndRegionOverrideKeys,
            readingValueFor: { Self.globalDomainValue($0) },
            pinnedByTheScheme: pinned
        )
        #expect(
            unpinned.isEmpty,
            """
            this Mac has Language & Region override(s) set that the test scheme cannot pin: \
            \(unpinned.map { "\($0) = \(String(describing: Self.globalDomainValue($0)))" }
                .joined(separator: ", ")). \
            These live in the GLOBAL preferences domain; the TestAction's -AppleLocale is a \
            per-process argument-domain overlay on one key and does not reach them. So this is not \
            a code regression and not a dropped pin — it is the machine, and every date-, week- and \
            clock-shaped assertion in this target is now measuring it. Clear the switch in System \
            Settings > General > Language & Region (or state the calendar/locale in the failing \
            test, the way CadenceTestTimeZones and CadenceTestClocks do) rather than editing the \
            scheme, which has no way to override a global-domain key. See T-1116.
            """
        )
    }

    /// The detector, proven on values that exist — the half a green run of the test above cannot
    /// show, because success there is an empty list and an empty list is also what a broken
    /// reader returns.
    @Test func theOverrideDetectorSeesASwitchThatIsSetAndIgnoresOneTheSchemePinned() {
        let machine: [String: Any] = ["AppleFirstWeekday": ["gregorian": 2], "AppleICUForce24HourTime": 1]

        #expect(
            Self.unpinnedOverrides(
                keys: Self.languageAndRegionOverrideKeys,
                readingValueFor: { machine[$0] },
                pinnedByTheScheme: ["AppleLocale"]
            ) == ["AppleFirstWeekday", "AppleICUForce24HourTime"],
            "the detector did not name the two switches this fixture sets"
        )

        // A key the scheme itself passes is NOT a machine dependency, and must not be reported as
        // one — otherwise landing a future pin would make this suite red for doing the right thing.
        #expect(
            Self.unpinnedOverrides(
                keys: Self.languageAndRegionOverrideKeys,
                readingValueFor: { machine[$0] },
                pinnedByTheScheme: ["AppleFirstWeekday", "AppleICUForce24HourTime"]
            ).isEmpty
        )

        #expect(
            Self.unpinnedOverrides(
                keys: Self.languageAndRegionOverrideKeys,
                readingValueFor: { _ in nil },
                pinnedByTheScheme: []
            ).isEmpty,
            "a machine with nothing set must read clean, or the guard above can never be green"
        )

        // And the argv reading, in both spellings, since which one arrives is Xcode's choice.
        #expect(Self.schemeArgumentKeys(["-AppleLocale", "en_US"]).contains("AppleLocale"))
        #expect(Self.schemeArgumentKeys(["-AppleLocale en_US"]).contains("AppleLocale"))
        #expect(Self.schemeArgumentKeys(["/path/to/Cadence", "en_US"]).isEmpty,
                "a bare value must not read as a key, or every run looks pinned")
    }

    // MARK: - T-1153. An environment claim must name the test that holds it

    /// The guides a coordinator reads before deciding anything, which is where a claim about the
    /// execution environment turns into a rule.
    ///
    /// Four files, and the boundary is argued rather than convenient. These are the documents read
    /// *without* a reason to open them: root and startup context, the long root runbook they route
    /// to, and the subagent runbook every batch is pointed at. A claim in one of them is what T-959
    /// became.
    ///
    /// **The scripts are not in this corpus, and they are not unguarded either** — they are held
    /// one fold coarser, by `everyScriptThatMakesAnEnvironmentClaimNamesAPinInOneOfThem` below.
    /// T-1380 measured the alternatives rather than arguing them; the numbers are in that test's
    /// own doc comment. A guide is read end to end by someone about to decide something, so every
    /// block in it carries its own citation. A script is read at the function you are editing, and
    /// most of its claims are the same four facts restated wherever a workaround sits.
    ///
    /// **T-1333 added the fifth, and it is the same inclusion as the second long reference.**
    /// Splitting `docs/SUBAGENT_RUNBOOK.md` moved three environment claims — the ledger's
    /// `$TMPDIR`, the `xcrun` shims, the shim on `$PATH` that is silently skipped — into
    /// `docs/SUBAGENT_RUNBOOK_REFERENCE.md`. Leaving the corpus alone would have let a
    /// reorganisation do what no edit was allowed to do: retire the citations by relocating the
    /// sentences. The reference is in for exactly the reason `docs/AGENTS_REFERENCE.md` already
    /// was — it is where its guide's reasoning went, and a claim does not stop being quotable for
    /// having been displaced.
    static let alwaysReadGuides = [
        "AGENTS.md",
        "CLAUDE.md",
        "docs/AGENTS_REFERENCE.md",
        "docs/SUBAGENT_RUNBOOK.md",
        "docs/SUBAGENT_RUNBOOK_REFERENCE.md",
    ]

    /// What counts as a claim about what the execution environment can do.
    ///
    /// Every needle names a *mechanism*, never a mood. That is the lesson of T-1343, where a
    /// selftest was written off as "can't run under the sandboxed test host" and the real cause was
    /// `zsh`'s `$TMPPREFIX` pointing at `/tmp/zsh`: the same script gave 8 passes under `zsh -f` and
    /// 41 under `sh`. A guard keyed on the word "sandbox" alone would have passed that sentence and
    /// flagged a hundred others, so the word on its own is not here.
    static let environmentClaimNeedles = [
        "App Sandbox",
        "App-Sandbox",
        "posix_spawn",
        "process list",
        "setuid",
        "TMPPREFIX",
        "xcrun shim",
        "cannot spawn",
        "cannot exec",
        "sandboxed test host",
        "EPERM",
    ]

    /// The suites that hold an environment claim, and therefore the names a claim may cite.
    ///
    /// Two, because there are two kinds of claim: `CadenceTestHostSandboxCapabilityTests` measures
    /// what the host can and cannot do directly, and `CadenceGuardScriptSelftestTests` is where a
    /// claim about a *script* running in that host is exercised.
    static let pinningSuites = [
        "CadenceTestHostSandboxCapabilityTests",
        "CadenceGuardScriptSelftestTests",
    ]

    struct GuideBlock {
        let file: String
        let line: Int
        let text: String
    }

    /// `markdown` split into the units a citation is judged over: a paragraph, or a single list
    /// item with its continuation lines.
    ///
    /// A blank line ends a block, and so does the start of a new list item — without the second
    /// rule a twelve-bullet list would be one block and a citation on any bullet would excuse the
    /// other eleven.
    ///
    /// **A heading is dropped rather than made into a one-line block.** `### The App-Sandboxed test
    /// host cannot EXECUTE a file it just wrote` is a title for the paragraph under it, and
    /// requiring a suite name inside a heading would mean writing prose for this test instead of
    /// for the reader.
    static func guideBlocks(_ markdown: String, file: String) -> [GuideBlock] {
        var blocks: [GuideBlock] = []
        var current: [String] = []
        var start = 0

        func flush() {
            guard !current.isEmpty else { return }
            blocks.append(GuideBlock(file: file, line: start, text: current.joined(separator: "\n")))
            current = []
        }

        for (offset, raw) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            let trimmed = line.drop(while: { $0 == " " })
            let numbered = trimmed.prefix(while: { $0.isNumber })
            let startsItem = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
                || (!numbered.isEmpty && trimmed.dropFirst(numbered.count).hasPrefix(". "))
            if line.trimmingCharacters(in: .whitespaces).isEmpty || startsItem || line.hasPrefix("#") {
                flush()
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            if current.isEmpty { start = offset + 1 }
            current.append(line)
        }
        flush()
        return blocks
    }

    static func makesAnEnvironmentClaim(_ text: String) -> Bool {
        environmentClaimNeedles.contains { text.contains($0) }
    }

    static func citesAPin(_ text: String) -> Bool {
        pinningSuites.contains { text.contains($0) }
    }

    /// The rule, over the real guides.
    ///
    /// Three separate expectations, and the order matters: the census has to be non-empty and has
    /// to contain a claim this test names outright before "no offenders" is worth anything. A
    /// needle list that stopped matching would otherwise report a clean sweep of nothing.
    @Test func everyEnvironmentClaimInAnAlwaysReadGuideNamesThePinThatHoldsIt() throws {
        var claims: [GuideBlock] = []
        for guide in Self.alwaysReadGuides {
            let text = try CadenceSourceScan.sourceFile(guide)
            claims += Self.guideBlocks(text, file: guide).filter { Self.makesAnEnvironmentClaim($0.text) }
        }

        #expect(
            claims.count >= 5,
            """
            only \(claims.count) environment claim(s) found across \(Self.alwaysReadGuides.joined(separator: ", ")). \
            Five is the count measured on 2026-09-25; fewer means the needles stopped matching, not \
            that the guides stopped claiming.
            """
        )
        #expect(
            claims.contains { $0.file == "AGENTS.md" && $0.text.contains("denied the process list") },
            """
            the AGENTS.md bullet about a lock driven from inside a test no longer reads as a claim, \
            so this scan is no longer pointed at the sentence it was built for
            """
        )

        let uncited = claims.filter { !Self.citesAPin($0.text) }
        #expect(
            uncited.isEmpty,
            """
            \(uncited.count) claim(s) about what the execution environment can do name no test that \
            holds them: \(uncited.map { "\($0.file):\($0.line)" }.joined(separator: ", ")). \
            A claim nobody can check is how T-959's one measured fact became three decisions (T-1153). \
            Name \(Self.pinningSuites.joined(separator: " or ")) in the same paragraph, or measure it \
            there and add the case.
            """
        )
    }

    /// The scan, proven on text that breaks it — the half the sweep above cannot show while it is
    /// green, since a detector that matched nothing would produce the same empty offender list.
    @Test func theClaimScanSplitsBlocksAndNoticesAnUncitedClaim() throws {
        let markdown = """
        ## A heading about posix_spawn

        - A bullet that says the host is denied the process list, and cites nothing.
          Its continuation line belongs to it.
        - A second bullet, about setuid binaries, which names CadenceTestHostSandboxCapabilityTests.

        An ordinary paragraph with no claim in it at all.
        """
        let blocks = Self.guideBlocks(markdown, file: "fixture.md")
        #expect(blocks.count == 3, "got \(blocks.count) blocks: \(blocks.map(\.text))")
        #expect(blocks[0].text.contains("continuation line"), "a bullet lost its continuation")
        #expect(!blocks.contains { $0.text.hasPrefix("##") }, "a heading became a block of its own")

        let claims = blocks.filter { Self.makesAnEnvironmentClaim($0.text) }
        #expect(claims.count == 2, "the two claiming bullets did not both read as claims")
        #expect(claims.filter { !Self.citesAPin($0.text) }.count == 1,
                "the uncited bullet and the cited one were not told apart")

        // The citation has to resolve to a suite that exists, or the rule buys a name and not a
        // check. Asserted against the target's own source rather than a list kept here.
        for suite in Self.pinningSuites {
            let declared = try CadenceSourceScan.sourceFile("CadenceTests/\(suite).swift")
            #expect(declared.contains("struct \(suite)"),
                    "\(suite) is cited as a pin but declares no suite of that name")
        }
    }

    // MARK: - T-1380. The same rule over the scripts, folded per FILE rather than per block

    /// Every file the script-side rule is judged over: the guard scripts plus the hook.
    ///
    /// Enumerated rather than listed, so a script added tomorrow is swept the day it lands. The
    /// hook is in because it is the same kind of file and carries the same two claims twice over;
    /// it is not under `scripts/`, so it is named.
    static func claimCorpusPaths() throws -> [String] {
        let scripts = try FileManager.default
            .contentsOfDirectory(atPath: CadenceSourceScan.repositoryRoot().appendingPathComponent("scripts").path)
            .filter { $0.hasSuffix(".sh") }
            .map { "scripts/\($0)" }
        return (scripts + [".githooks/pre-commit"]).sorted()
    }

    /// A shell file split into runs of consecutive comment lines.
    ///
    /// The shell analogue of `guideBlocks`, and deliberately not the same function: a markdown
    /// paragraph is bounded by blank lines, a shell comment block is bounded by the first line
    /// that is *code*. One blank line inside a comment run therefore ends the block here, which is
    /// what a reader sees too — an unbroken column of `#` is one thought.
    ///
    /// The shebang joins the header block it sits above. That costs nothing under a per-file fold
    /// and is worth having: `scripts/test-host-lock.sh` states its whole sandbox position in that
    /// header, and a splitter that dropped line 1 would drop the claim with it.
    static func shellCommentBlocks(_ source: String, file: String) -> [GuideBlock] {
        var blocks: [GuideBlock] = []
        var current: [String] = []
        var start = 0

        func flush() {
            guard !current.isEmpty else { return }
            blocks.append(GuideBlock(file: file, line: start, text: current.joined(separator: "\n")))
            current = []
        }

        for (offset, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(raw)
            if line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("#") {
                if current.isEmpty { start = offset + 1 }
                current.append(line)
            } else {
                flush()
            }
        }
        flush()
        return blocks
    }

    /// The per-file rule, as one predicate over one file's text, so `CadenceScanInstrument` can
    /// hold it against a witness in each direction.
    ///
    /// **A citation only counts when it sits in a block that itself makes the claim, and that is
    /// the whole difference between this rule and a rule that checks nothing.** Measured
    /// 2026-09-26: under the looser reading — the suite name anywhere in the file — 9 of the 12
    /// claiming files already passed, on sentences about the ledger's vocabulary, about
    /// `agent-commit.sh`'s own diff rules, about a precheck. That reading costs 3 lines and
    /// inspects 3 files. This one costs 5 and inspects 12.
    static func fileMakesAnUncitedEnvironmentClaim(_ source: String, file: String = "") -> Bool {
        let claims = shellCommentBlocks(source, file: file).filter { makesAnEnvironmentClaim($0.text) }
        guard !claims.isEmpty else { return false }
        return !claims.contains { citesAPin($0.text) }
    }

    /// The rule, over the real scripts.
    ///
    /// **T-1380 named two folds and this took the cheaper one, on numbers rather than taste.**
    /// Measured 2026-09-26 over `scripts/*.sh` and `.githooks/pre-commit`, grouping consecutive
    /// comment lines, with the eleven needles above:
    ///
    /// | fold | new citation lines | what it inspects |
    /// | --- | --- | --- |
    /// | per block, the guides' rule | **30** | every restatement |
    /// | per file × fact family | **13** | each distinct fact, once per file |
    /// | per file, citation inside a claim block — **this one** | **5** | each claiming file |
    /// | per file, citation anywhere in the file | 3 | 3 of the 12 files |
    ///
    /// 38 claim blocks in 12 files, 8 cited, 30 not — and the ticket's own census a day earlier
    /// was 30/7/23. **That drift is the argument.** The population grew by 8 blocks in a day while
    /// [[T-1382]] and [[T-1384]] were landing, so the per-block fold does not cost 30 lines once,
    /// it costs about 8 lines a day forever, every one of them the same name in a file nobody
    /// reads end to end — the cure looking like the disease [[T-434]] is about. The per-file fold
    /// costs 5 lines once and roughly nothing after, because a new claim in an already-citing file
    /// needs no line at all.
    ///
    /// **What that buys and what it does not, stated rather than implied.** It buys: every file
    /// that says something about this execution environment names, in a claiming comment, a suite
    /// that measures it, and that suite must exist. It does not buy: that the *particular*
    /// restatement you are reading is the one that was measured. `scripts/mutate.sh`'s comment —
    /// where T-959's one fact was widened to "an unrecognised exec target", which [[T-959]] then
    /// had to disprove — is the case that motivated the ticket, and it is already cited today. The
    /// per-file fold would not have required that citation; the per-block fold would. That is the
    /// honest cost of taking the cheap one, and the 13-line middle fold is where it is recoverable
    /// if the widening happens again.
    @Test func everyScriptThatMakesAnEnvironmentClaimNamesAPinInOneOfThem() throws {
        let paths = try Self.claimCorpusPaths()

        // The census first, so "no offenders" has something behind it. A needle list that stopped
        // matching, or a splitter that returned nothing, both produce an empty offender list.
        var blocks = 0
        var claimingFiles: [String] = []
        for path in paths {
            let source = try CadenceSourceScan.sourceFile(path)
            let claims = Self.shellCommentBlocks(source, file: path).filter { Self.makesAnEnvironmentClaim($0.text) }
            blocks += claims.count
            if !claims.isEmpty { claimingFiles.append(path) }
        }
        #expect(
            blocks >= 30 && claimingFiles.count >= 10,
            """
            the script census found \(blocks) claim block(s) in \(claimingFiles.count) file(s). \
            38 in 12 is what 2026-09-26 measured and 30 in 12 is the floor this asserts; below it \
            the needles or the block splitter stopped matching, which is not the same as the \
            scripts having stopped claiming.
            """
        )
        #expect(
            claimingFiles.contains("scripts/test-host-lock.sh") && claimingFiles.contains(".githooks/pre-commit"),
            """
            the two files this scan was built for — the lock, whose header states the whole sandbox \
            position, and the hook, which restates the `$TMPPREFIX` and `xcrun` notes — no longer \
            read as making a claim, so this sweep is pointed somewhere else than where it was aimed
            """
        )

        let instrument = try CadenceScanInstrument(
            "script file with an uncited environment claim",
            fires: """
            #!/bin/zsh
            # `/usr/bin/git` is an xcrun shim and xcrun refuses to run inside an App Sandbox.
            git --version
            # A later, unrelated block that happens to name CadenceGuardScriptSelftestTests.
            print done
            """,
            andNotOn: """
            #!/bin/zsh
            # `/usr/bin/git` is an xcrun shim and xcrun refuses to run inside an App Sandbox;
            # CadenceTestHostSandboxCapabilityTests measures both spellings in that host.
            git --version
            # A later, unrelated block that happens to name CadenceGuardScriptSelftestTests.
            print done
            """,
            by: { Self.fileMakesAnUncitedEnvironmentClaim($0) }
        )

        let offenders = try instrument.sweep(
            paths,
            atLeast: 20,
            including: "scripts/test-host-lock.sh",
            read: { try CadenceSourceScan.sourceFile($0) }
        )
        #expect(
            offenders.isEmpty,
            """
            \(offenders.count) script(s) say something about what this execution environment can \
            do and name no test that holds any of it: \(offenders.joined(separator: ", ")). \
            One citation per FILE is the whole rule (T-1380) — put \
            \(Self.pinningSuites.joined(separator: " or ")) in one of that file's own claiming \
            comment blocks, not in an unrelated one, or measure the claim there and add the case.
            """
        )
    }

    /// The script-side reader, proven in both directions on text built to break it — the half the
    /// sweep above cannot show while it is green.
    ///
    /// `CadenceScanInstrument` already holds the file predicate against one witness each way. What
    /// it cannot hold is the *splitter*, and the splitter is where this rule is won or lost: the
    /// looser fold it replaces differs from this one by exactly the question "is the citation in a
    /// block that claims anything", and a splitter that ran comment runs together would answer
    /// that question wrong while still returning a non-empty list.
    @Test func theShellBlockSplitterKeepsACitationOutOfABlockThatClaimsNothing() throws {
        let script = """
        #!/bin/zsh
        # A header that mentions no mechanism at all.

        # This block claims: the App-Sandboxed host is denied the process list.
        # Its continuation line belongs to it.
        pgrep -f cadence

        # This block claims nothing, and names CadenceGuardScriptSelftestTests anyway.
        print done
        """
        let blocks = Self.shellCommentBlocks(script, file: "fixture.sh")
        #expect(blocks.count == 3, "got \(blocks.count) blocks: \(blocks.map(\.text))")
        #expect(blocks[1].text.contains("continuation line"), "a comment run lost its second line")
        #expect(blocks[0].text.hasPrefix("#!/bin/zsh"), "the shebang did not join the header block")

        let claims = blocks.filter { Self.makesAnEnvironmentClaim($0.text) }
        #expect(claims.count == 1, "the claiming block was not told from the two that claim nothing")

        // The negative the looser fold gets wrong: a citation is present in the FILE, and the file
        // still offends, because no block that claims anything carries it.
        #expect(script.contains("CadenceGuardScriptSelftestTests"))
        #expect(Self.fileMakesAnUncitedEnvironmentClaim(script, file: "fixture.sh"),
                "a citation sitting in a block that claims nothing was accepted as a citation")

        // And the positive: move the name into the claiming block and the file is clean.
        let repaired = script.replacingOccurrences(
            of: "# Its continuation line belongs to it.",
            with: "# CadenceTestHostSandboxCapabilityTests measures that."
        )
        #expect(!Self.fileMakesAnUncitedEnvironmentClaim(repaired, file: "fixture.sh"),
                "a citation in the claiming block was not accepted")

        // A file that claims nothing is not an offender, or every script in the tree would be one.
        #expect(!Self.fileMakesAnUncitedEnvironmentClaim("#!/bin/sh\n# nothing here\nprint x\n"))

        // The corpus has to be a real walk, not a list that silently emptied.
        let paths = try Self.claimCorpusPaths()
        #expect(paths.count >= 20 && paths.contains(".githooks/pre-commit"),
                "the corpus walk returned \(paths.count) path(s)")
    }
}
