import Foundation
import Testing

/// T-719. `scripts/xcb.sh`'s guards are pinned: `CadenceBuildInvocationHygieneTests` scans the
/// repository and fails if the zero-test refusal is deleted. The other guard scripts each carry
/// a `selftest` that induces every one of their refusals — and **nothing ran any of them**. No
/// test target invoked them, no hook called them, and the only thing standing between a deleted
/// refusal and a silently useless instrument was somebody remembering to type the command.
///
/// That is the hollow-instrument shape one layer up: a guard whose own guard is a habit. So these
/// tests shell out to the selftests and fail on a non-zero exit. `mutate.sh` and `agent-commit.sh`
/// build nothing and finish in about a second, so cost is not the objection there.
///
/// `test-host-lock.sh` and `simulator-claim.sh` (T-748, T-749) are a different shape: their
/// selftests prove FAIRNESS and ORPHAN-HANDLING under real concurrency, which means real
/// subprocesses and real `sleep`s rather than a single pass over a fixture. They run tens of
/// seconds each, not about one — that is the honest cost of testing "the waiter that arrived first
/// is served first" instead of asserting it in a comment, and it is why they get their own
/// `@Test` functions rather than folding into the loop above them.
///
/// **Exit 0 is not enough on its own.** A selftest gutted to `return 0` also exits 0, which is the
/// same failure wearing a different hat. So each run must additionally name every refusal it claims
/// to exercise, and print a tally of checks that really ran — a count the gutted version cannot
/// produce. `theCheckerRejectsASelftestThatAssertsNothing` proves that reading is not vacuous by
/// running it against a stub that exits 0 in silence.
struct CadenceGuardScriptSelftestTests {

    /// Every refusal `scripts/mutate.sh` makes, by the name it prints. Exact, and each occurrence
    /// named: a floor like "at least four modes" would pass a runner that had lost three of them.
    static let mutationRunnerRefusals = [
        "NEEDLE-ABSENT",
        "NOT-PRISTINE",
        "NEEDLE-AMBIGUOUS",
        "DID-NOT-COMPILE",
        "TOOLCHAIN-CRASH",
        "NO-TESTS-RAN",
        "RED-WITHOUT-A-FAILING-TEST",
        "INCONCLUSIVE",
    ]

    /// Every refusal `scripts/agent-commit.sh` makes. `SHARED-INDEX-DIRTY` is the post-commit repair
    /// (T-679's third measured failure: a private index used correctly, leaving the shared one 274
    /// deletions behind HEAD); `DECLINED-HUNK-LOST` is the fourth, where a hunk both agents declined
    /// landed nowhere and HEAD stopped compiling. `LEDGER-IDS-LOST` and `REMOVES-HEAD-LINES` are the
    /// two the tool grew from its own first hours of use: a reconstruction built on a stale copy
    /// reverts a sibling's landed work, and inside a line count a lost ticket is invisible.
    /// `HEAD-MOVED` is T-974, and it is the one that made the others conditional: every refusal
    /// above answers a question about the HEAD it read, and the script used to read HEAD afresh at
    /// each step and commit onto whichever HEAD existed last. A sibling landing in that window took
    /// a ticket with it while `LEDGER-IDS-LOST` reported nothing — because it had been satisfied,
    /// correctly, against a commit that was no longer HEAD.
    /// `DECLINED-HUNK-STALE` and `DECLINED-HUNKS-OUTSTANDING` are T-781, the missing backstop:
    /// `DECLINED-HUNK-LOST` only fires on the next commit of that same path, so a record nobody
    /// ever revisits fired nothing at all — two of them sat outstanding for hours in one run,
    /// printed at the end of every commit and acted on by nobody.
    static let commitHelperRefusals = [
        "FOREIGN-STAGED",
        "HEAD-MOVED",
        "SHARED-INDEX-DIRTY",
        "DECLINED-HUNK-LOST",
        "DECLINED-HUNK-STALE",
        "DECLINED-HUNKS-OUTSTANDING",
        "LEDGER-IDS-LOST",
        "LEDGER-CLOSURE-LOST",
        "REMOVES-HEAD-LINES",
        "NO-PATHS",
        "UNKNOWN-PATH",
        "NOTHING-TO-COMMIT",
        "NO-COAUTHOR-TRAILER",
        "NOT-REPO-ROOT",
    ]

    /// Every refusal `scripts/worktree-drift.sh` makes (T-975). Two, because the script's job is
    /// almost entirely to NOT refuse: it exists because `git status` prints ` M <path>` for a
    /// stale checkout copy and for real in-flight work in the same three characters, and telling
    /// those apart wrongly in the other direction would stop the whole batch.
    static let worktreeDriftRefusals = [
        "WORKTREE-BEHIND-HEAD",
        "NOT-REPO-ROOT",
    ]

    /// Every property `scripts/test-host-lock.sh`'s selftest names with a `PASS <name>` line.
    /// `ordering` is T-650 (a FIFO of waiters, not a race on release); `no-reclaim` / `reclaim` are
    /// the lease-vs-live-host conjunction that stops a second test host starting against the same
    /// app-group container; `dead-parent-declines` / `dead-parent-recovers` are T-748 -- a waiter
    /// whose caller died must decline the lock at the head of the queue rather than take it and
    /// strand it, and the queue behind it must not stall because one waiter declined.
    static let testHostLockProperties = [
        "ordering",
        "no-reclaim",
        "reclaim",
        "killed-waiter",
        "dead-parent-declines",
        "dead-parent-recovers",
    ]

    /// `ordering` and `no-reclaim` cannot be PROVEN from inside this test host -- not "are awkward
    /// to", cannot. Both read cross-process liveness through `ps`/`pgrep` (`waiter_alive`'s
    /// `ps -o command= -p $pid`, `live_test_hosts`'s `pgrep -f`), and CadenceTests runs
    /// App-Sandboxed: measured 2026-09-04, spawning `/bin/ps` from inside this host throws
    /// `Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"` before it produces a
    /// single byte of output, and the selftest's own child `zsh` inherits the same sandbox, so its
    /// internal `ps`/`pgrep` calls fail identically -- see T-959, which generalises this past the
    /// two scripts here. So these two are TOLERATED failures below, not required, and they are
    /// proven the other way instead: direct terminal invocation, captured in docs/TODO.md's T-748
    /// and T-650 entries (`w4 w1 w2 w3` before the fix, `w1 w2 w3 w4` after, three runs of three).
    static let testHostLockPropertiesUnverifiableInThisSandbox: Set<String> = ["ordering", "no-reclaim"]

    /// Every property `scripts/simulator-claim.sh`'s selftest names. T-749 ported
    /// `test-host-lock.sh`'s T-650 queue over wholesale rather than reinventing it, so it is pinned
    /// the same way: `ordering` is the fairness fix itself (a 16-minute starvation measured on the
    /// same race the FIFO closes), `killed-waiter` is the new queue's own prune-liveness check,
    /// exercised for real rather than read off the source.
    static let simulatorClaimProperties = [
        "ordering",
        "killed-waiter",
    ]

    /// Same T-959 sandbox limit as above: `ordering` depends on `waiter_alive`'s `ps` call the same
    /// way test-host-lock.sh's does (this script's queue is a direct port of that one). Proven by
    /// terminal instead -- docs/TODO.md's T-749 entry (`w4 w1 w2 w3` before, `w1 w2 w3 w4` after).
    static let simulatorClaimPropertiesUnverifiableInThisSandbox: Set<String> = ["ordering"]

    @Test func theMutationRunnersOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/mutate.sh")
        let complaints = run.complaints(requiring: Self.mutationRunnerRefusals)
        #expect(complaints.isEmpty, "./scripts/mutate.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    @Test func theCommitHelpersOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/agent-commit.sh")
        let complaints = run.complaints(requiring: Self.commitHelperRefusals)
        #expect(complaints.isEmpty, "./scripts/agent-commit.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-975. Runs entirely inside a throwaway git repository under `$TMPDIR`, so it is safe
    /// alongside siblings editing the real checkout — and it never reads the real checkout's own
    /// drift, which would make this test's result depend on what other agents happen to have
    /// in flight. About a second, like the two above it.
    @Test func theWorktreeDriftGuardsOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/worktree-drift.sh")
        let complaints = run.complaints(requiring: Self.worktreeDriftRefusals)
        #expect(complaints.isEmpty, "./scripts/worktree-drift.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-748. Runs against the REAL lock's own sandbox (`CADENCE_LOCK_DIR`, not the live
    /// `${TMPDIR}cadence-macos-test-host.lock`), so this is safe to run alongside sibling agents
    /// actually holding that lock. Real subprocesses and real `sleep`s, so this one runs for tens of
    /// seconds rather than about one -- see the type doc above.
    ///
    /// `ordering` / `no-reclaim` are TOLERATED, not required (T-959: this host cannot spawn `ps` or
    /// `pgrep` at all, and both properties depend on one of them). Tolerating a named failure is not
    /// the same as ignoring it: this still fails loudly if either PASSES unexpectedly (the sandbox
    /// limit lifted, this list is stale) or if anything NOT on the tolerated list fails.
    @Test func theTestHostLocksOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/test-host-lock.sh")
        let complaints = run.complaintsForNamedRuns(
            requiring: Self.testHostLockProperties,
            tolerating: Self.testHostLockPropertiesUnverifiableInThisSandbox
        )
        #expect(complaints.isEmpty, "./scripts/test-host-lock.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-749. Runs against a throwaway claims root and a fake `simctl` (`CADENCE_SIM_CLAIMS_DIR` /
    /// `CADENCE_SIMCTL`), so this is safe alongside sibling agents holding real device claims.
    /// `ordering` is TOLERATED, not required -- same T-959 sandbox limit as above.
    @Test func theSimulatorClaimsOwnGuardStillFires() throws {
        let run = try CadenceSelftestRun.of("scripts/simulator-claim.sh")
        let complaints = run.complaintsForNamedRuns(
            requiring: Self.simulatorClaimProperties,
            tolerating: Self.simulatorClaimPropertiesUnverifiableInThisSandbox
        )
        #expect(complaints.isEmpty, "./scripts/simulator-claim.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// The reading above is only worth its runtime if it can tell a selftest from a script that
    /// exits 0. Three stubs, each a way the pin could go hollow, and each must be complained about.
    @Test func theCheckerRejectsASelftestThatAssertsNothing() throws {
        let silent = CadenceSelftestRun(status: 0, output: "")
        #expect(!silent.complaints(requiring: ["FOREIGN-STAGED"]).isEmpty,
                "a script that exits 0 in silence must not read as a passing selftest")

        let announcesButCountsNothing = CadenceSelftestRun(
            status: 0,
            output: " mode 1 (FOREIGN-STAGED) -- ...\nchecks: 0 passed, 0 failed\nSELFTEST PASSED\n"
        )
        #expect(!announcesButCountsNothing.complaints(requiring: ["FOREIGN-STAGED"]).isEmpty,
                "printing the mode headers while running no check must not read as a passing selftest")

        let lostAMode = CadenceSelftestRun(
            status: 0,
            output: " mode 1 (FOREIGN-STAGED) -- ...\n  ok  something\nchecks: 1 passed, 0 failed\nSELFTEST PASSED\n"
        )
        #expect(lostAMode.complaints(requiring: ["FOREIGN-STAGED"]).isEmpty)
        #expect(!lostAMode.complaints(requiring: ["FOREIGN-STAGED", "DECLINED-HUNK-LOST"]).isEmpty,
                "a selftest that no longer exercises a refusal must be complained about by name")

        let red = CadenceSelftestRun(
            status: 1,
            output: " mode 1 (FOREIGN-STAGED) -- ...\nchecks: 3 passed, 1 failed\nSELFTEST FAILED: x\n"
        )
        #expect(!red.complaints(requiring: ["FOREIGN-STAGED"]).isEmpty,
                "a non-zero exit must be complained about")
    }

    /// Same rigor as `theCheckerRejectsASelftestThatAssertsNothing`, for the `PASS <name>` /
    /// `selftest: N failure(s)` vocabulary `test-host-lock.sh` and `simulator-claim.sh` speak --
    /// plus the T-959 `tolerating` parameter, which has its own way to go hollow: silently
    /// tolerating everything.
    @Test func theCheckerRejectsANamedRunSelftestThatAssertsNothing() throws {
        let silent = CadenceSelftestRun(status: 0, output: "")
        #expect(!silent.complaintsForNamedRuns(requiring: ["ordering"]).isEmpty,
                "a script that exits 0 in silence must not read as a passing selftest")

        let noTrailer = CadenceSelftestRun(status: 0, output: "PASS ordering: w1 w2 w3 w4\n")
        #expect(!noTrailer.complaintsForNamedRuns(requiring: ["ordering"]).isEmpty,
                "printing a PASS line but crashing before the trailer must not read as passing")

        let lostAProperty = CadenceSelftestRun(
            status: 0,
            output: "PASS ordering: w1 w2 w3 w4\nselftest: 0 failure(s)\n"
        )
        #expect(lostAProperty.complaintsForNamedRuns(requiring: ["ordering"]).isEmpty)
        #expect(!lostAProperty.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"]).isEmpty,
                "a selftest that no longer exercises a property must be complained about by name")

        let red = CadenceSelftestRun(
            status: 0,
            output: "PASS ordering: w1 w2 w3 w4\nFAIL killed-waiter: queue stalled\nselftest: 1 failure(s)\n"
        )
        #expect(!red.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"]).isEmpty,
                "a non-zero failure trailer must be complained about even at exit 0")

        // A tolerated failure is exactly what T-959 is FOR: exit 1, one named FAIL, and no
        // complaint, as long as the failing name is the one on the tolerated list.
        let toleratedFailure = CadenceSelftestRun(
            status: 1,
            output: "PASS killed-waiter: ok\nFAIL ordering: got 'w4 w1 w2 w3'\nselftest: 1 failure(s)\n"
        )
        #expect(toleratedFailure.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"], tolerating: ["ordering"]).isEmpty,
                "a failure on the tolerated list must not be complained about")

        // The same output, but WITHOUT the tolerance, must go back to complaining -- proves the
        // parameter is doing something rather than the reading having quietly gone lenient for
        // everyone.
        #expect(!toleratedFailure.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"]).isEmpty,
                "the same failing output must be complained about when nothing is tolerated")

        // A failure NOT on the tolerated list still fails this check even when something IS
        // tolerated -- tolerating one name must not silently tolerate everything.
        let untoleratedFailureAlongsideATolerated = CadenceSelftestRun(
            status: 1,
            output: "FAIL ordering: got 'w4 w1 w2 w3'\nFAIL killed-waiter: queue stalled\nselftest: 2 failure(s)\n"
        )
        #expect(!untoleratedFailureAlongsideATolerated.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"], tolerating: ["ordering"]).isEmpty,
                "an unexpected failure must still be complained about even while a different one is tolerated")

        // A tolerated property that is not even MENTIONED (deleted from the selftest outright)
        // must still be complained about -- tolerating a FAIL is not the same as not caring whether
        // the check still exists.
        let toleratedPropertyDeletedEntirely = CadenceSelftestRun(
            status: 0,
            output: "PASS killed-waiter: ok\nselftest: 0 failure(s)\n"
        )
        #expect(!toleratedPropertyDeletedEntirely.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"], tolerating: ["ordering"]).isEmpty,
                "a tolerated property that stopped running at all must still be complained about")

        // Setup failures (this script family's `exit 2`, e.g. "could not claim the fake device")
        // must be complained about even if, by construction, no property ever got the chance to
        // FAIL and so the name-based checks above would otherwise see nothing wrong.
        let setupFailure = CadenceSelftestRun(status: 2, output: "selftest: could not claim the fake device\n")
        #expect(!setupFailure.complaintsForNamedRuns(requiring: ["ordering"], tolerating: ["ordering"]).isEmpty,
                "an exit code outside {0, 1} must be complained about regardless of what is tolerated")
    }

    /// The shell-out above is the strong form: it proves the guards still *fire*. This is the
    /// `xcb.sh` form, and it is here because the two answer different questions and one of them
    /// survives a hostile environment. A refusal deleted from the script body, or a selftest that
    /// quietly stopped inducing one, is a source-level fact readable without spawning anything.
    @Test func everyRefusalTheScriptsMakeIsStillInducedByTheirOwnSelftest() throws {
        for (script, refusals) in [
            ("scripts/mutate.sh", Self.mutationRunnerRefusals),
            ("scripts/agent-commit.sh", Self.commitHelperRefusals),
            ("scripts/worktree-drift.sh", Self.worktreeDriftRefusals),
        ] {
            let source = try String(
                contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent(script),
                encoding: .utf8
            )
            guard let split = source.range(of: "\n# --- selftest") else {
                Issue.record("\(script) has no `# --- selftest` section to read")
                continue
            }
            let body = String(source[source.startIndex..<split.lowerBound])
            let selftest = String(source[split.lowerBound...])
            for refusal in refusals {
                #expect(body.contains(refusal), "\(script) no longer makes the refusal \(refusal)")
                #expect(selftest.contains(refusal), "\(script)'s selftest no longer induces \(refusal)")
            }
        }
    }

    /// And all five scripts have to be there to be run. A renamed script would otherwise make the
    /// tests above fail for a reason that reads nothing like "the guard is gone".
    @Test func allGuardScriptsExistAndAreExecutable() throws {
        for script in [
            "scripts/mutate.sh",
            "scripts/agent-commit.sh",
            "scripts/test-host-lock.sh",
            "scripts/simulator-claim.sh",
            "scripts/worktree-drift.sh",
        ] {
            let path = CadenceSelftestRun.repositoryRoot().appendingPathComponent(script).path
            #expect(FileManager.default.isExecutableFile(atPath: path), "\(script) is missing or not executable")
        }
    }
}

/// One run of a guard script's `selftest`, and the reading of it. Kept separate from the tests so
/// the reading can itself be exercised against stub output.
struct CadenceSelftestRun {
    let status: Int32
    let output: String

    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func of(_ relativeScript: String) throws -> CadenceSelftestRun {
        let script = repositoryRoot().appendingPathComponent(relativeScript).path
        return try run("/bin/zsh", ["-f", script, "selftest"])
    }

    /// A control, quoted into any failure message: the cheapest possible child process, plus the
    /// environment that decides whether the script can work at all. Both of these bit once
    /// (2026-09-03, T-719): the test host is App-Sandboxed, so `/usr/bin/git` and `/usr/bin/python3`
    /// — xcrun shims — refuse with *"cannot be used within an App Sandbox"*, and zsh could not write
    /// its here-document temp file because `$TMPPREFIX` defaults to `/tmp/zsh` rather than `$TMPDIR`.
    /// Both are fixed in the scripts; this is what made them findable.
    static func probe() -> String {
        let control = (try? run("/bin/echo", ["cadence-probe"])).map { "exit \($0.status)" } ?? "threw"
        let env = ProcessInfo.processInfo.environment
        let interesting = ["HOME", "TMPDIR", "PATH", "TMPPREFIX"]
            .map { "\($0)=\(env[$0] ?? "(unset)")" }
            .joined(separator: " ")
        return "control /bin/echo \(control); \(interesting)"
    }

    static func run(_ tool: String, _ arguments: [String]) throws -> CadenceSelftestRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        // Read to EOF before waiting: a script that outgrows the pipe buffer would otherwise block
        // on write while we block on exit.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CadenceSelftestRun(
            status: process.terminationStatus,
            output: String(decoding: stdout, as: UTF8.self) + String(decoding: stderr, as: UTF8.self)
        )
    }

    /// Empty means the selftest ran, passed, and really exercised each named refusal.
    func complaints(requiring refusals: [String]) -> [String] {
        var complaints: [String] = []
        if status != 0 { complaints.append("exited \(status)") }

        let missing = refusals.filter { !output.contains($0) }
        if !missing.isEmpty { complaints.append("exercises no mode named: \(missing.joined(separator: ", "))") }

        guard let tally = Self.tally(in: output) else {
            complaints.append("printed no `checks: N passed, M failed` tally, so nothing says a check ran")
            return complaints
        }
        if tally.failed != 0 { complaints.append("\(tally.failed) check(s) failed") }
        if tally.passed == 0 { complaints.append("the tally says 0 checks passed") }
        return complaints
    }

    static func tally(in output: String) -> (passed: Int, failed: Int)? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("checks: ") else { continue }
            let numbers = line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard numbers.count == 2 else { continue }
            return (numbers[0], numbers[1])
        }
        return nil
    }

    /// The reading for `test-host-lock.sh` / `simulator-claim.sh`, whose selftests speak a
    /// different vocabulary than `mutate.sh` / `agent-commit.sh`'s `checks: N passed, M failed`:
    /// one `PASS <property>` / `FAIL <property>` line per property, and a `selftest: N failure(s)`
    /// trailer rather than a tally.
    ///
    /// `tolerating` exists for T-959: a property in it is allowed to `FAIL` here (or even to never
    /// run at all is NOT allowed -- see `missingTolerated` below) without failing this check, because
    /// this test HOST cannot prove it, not because the property stopped mattering. Tolerating is not
    /// the same as ignoring: a tolerated name still has to be NAMED (either PASS or FAIL) by the
    /// selftest, and any failure NOT on the list still fails this check by name. A required property
    /// (`properties` minus `tolerating`) has to show `PASS`, not merely "not FAIL" -- a property
    /// deleted from the selftest entirely would satisfy the latter and this is exactly the
    /// hollow-instrument shape this whole file exists to catch.
    func complaintsForNamedRuns(requiring properties: [String], tolerating: Set<String> = []) -> [String] {
        var complaints: [String] = []
        // 0 = every property passed; 1 = at least one failed (tolerated or not) -- both are the
        // trial running to completion. Anything else (2 = "could not set up the fixture at all",
        // a crash, a signal) means the trial never really happened.
        if status != 0 && status != 1 {
            complaints.append("exited \(status) (expected 0 or 1; this looks like a setup failure, not a property failing)")
        }

        let passed = Self.namedResults(in: output, verb: "PASS")
        let failed = Self.namedResults(in: output, verb: "FAIL")

        let required = properties.filter { !tolerating.contains($0) }
        let missingRequired = required.filter { !passed.contains($0) }
        if !missingRequired.isEmpty {
            complaints.append("exercises no PASSING property named: \(missingRequired.joined(separator: ", "))")
        }

        let missingTolerated = properties.filter { tolerating.contains($0) && !passed.contains($0) && !failed.contains($0) }
        if !missingTolerated.isEmpty {
            complaints.append("tolerated propert(y/ies) never ran at all, not even a FAIL: \(missingTolerated.joined(separator: ", "))")
        }

        let unexpectedFailures = failed.subtracting(tolerating)
        if !unexpectedFailures.isEmpty {
            complaints.append("unexpected failure(s): \(unexpectedFailures.sorted().joined(separator: ", "))")
        }

        if Self.trailerFailureCount(in: output) == nil {
            complaints.append("printed no `selftest: N failure(s)` trailer, so nothing says the run finished")
        }
        return complaints
    }

    /// Every property name on a `PASS <name>: ...` / `FAIL <name>: ...` line. Anchored on the verb
    /// at line-start (after stripping leading spaces, since Swift Testing re-indents a multi-line
    /// diagnostic it did not write): `output.contains("PASS ordering")` alone would also match a
    /// sentence like "no-reclaim's PASS ordering only holds once ordering itself is fixed", which a
    /// hand-written comment could plausibly contain.
    static func namedResults(in output: String, verb: String) -> Set<String> {
        var names: Set<String> = []
        let prefix = "\(verb) "
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop(while: { $0 == " " })
            guard trimmed.hasPrefix(prefix) else { continue }
            let rest = trimmed.dropFirst(prefix.count)
            let name = rest.prefix(while: { $0 != ":" && $0 != " " })
            if !name.isEmpty { names.insert(String(name)) }
        }
        return names
    }

    static func trailerFailureCount(in output: String) -> Int? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("selftest: "), line.contains("failure(s)") else { continue }
            let numbers = line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            return numbers.first
        }
        return nil
    }
}
