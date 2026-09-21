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
    ///
    /// `STRANDED` is T-1044, and it is the one that is about the runner's own report rather than a
    /// mutation's verdict. The closing tree check compared each file against the baseline *this
    /// run* took, then printed `OK` — wording an agent reads as "the tree is clean". A runner
    /// SIGKILLed mid-mutation leaves its mutation in the tree, and the next run under that ident
    /// reads exactly those bytes as its baseline, so `OK` was printed over a file that still held
    /// the dead runner's edit. Reproduced 2026-09-06. A surviving mutant and a stranded mutation
    /// look identical in a report, so losing this verdict turns the whole runner into theatre.
    ///
    /// `BASELINE-NOT-GREEN` is T-1245, and it is the same hollowness one level up from a verdict:
    /// the baseline exists because *"in a tree whose suite is already red, or which does not
    /// build, KILLED means nothing at all"* — and that was asked of `mutations[0].suite` alone,
    /// so a plan naming two suites never established that the second one was green unmutated.
    /// An already-red suite goes red under the mutation too, which `classify_run` reads as
    /// **KILLED**: the reassuring answer, over a run that measured nothing. The runner now
    /// baselines every distinct `suite:` in the plan and refuses at the first that is not green;
    /// its selftest drives the baseline phase with a control that greens the first suite and reds
    /// the second, and pins that the one-probe form it replaces refuses nothing over that tree.
    static let mutationRunnerRefusals = [
        "NEEDLE-ABSENT",
        "NOT-PRISTINE",
        "NEEDLE-AMBIGUOUS",
        "DID-NOT-COMPILE",
        "TOOLCHAIN-CRASH",
        "NO-TESTS-RAN",
        "RED-WITHOUT-A-FAILING-TEST",
        "INCONCLUSIVE",
        "STRANDED",
        "BASELINE-NOT-GREEN",
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
    /// `WORKTREE-BEHIND-HEAD` is T-982, and it is `worktree-drift.sh`'s refusal moved one step
    /// earlier: that script gates the run that *reads* a drifted checkout, but drift is *created*
    /// here, when a bare `<path>` stages a worktree copy behind HEAD and writes it into history,
    /// where no drift check looks. Reproduced 2026-09-05: `REMOVES-HEAD-LINES` did fire on that
    /// commit — and told the agent the number to type to get past it, after which a sibling's
    /// landed line left HEAD. `DRIFT-CHECK-MISSING` and `DRIFT-CHECK-FAILED` are the other half:
    /// a check that cannot run must refuse rather than pass, or the guard is decoration that
    /// nobody had to edit to disable.
    /// `REBUILD-BEHIND-HEAD` is T-992, and it is the same question asked of the *cure*: the `=`
    /// reconstruction form is what a `WORKTREE-BEHIND-HEAD` refusal tells the agent to reach for,
    /// and for a long time nothing asked which revision that content file had been rebuilt on — so
    /// repairing one stale commit by rebuilding on a sha read twenty minutes earlier put the
    /// staleness straight back, and arrived as a `REMOVES-HEAD-LINES` count with an invitation to
    /// type it. Measured 2026-09-05 in a throwaway repository, and again over this repository's own
    /// history: content built two commits back is caught 13 times out of 13, while the reading
    /// false-refuses none of the last 80 real `docs/TODO.md` commits replayed through it.
    /// It did false-refuse one shape, and it is the commonest legitimate commit there is (T-1246):
    /// closing the NEWEST ledger entry rewrites every line HEAD introduced, so what is left
    /// contains the previous revision whole and reads `stale base` — with `--commits-stale`, the
    /// flag every brief forbids, as the only escape offered. Reproduced on this repository's own
    /// history: the real T-1216 closure with its five quoted lines removed reads
    /// `behind / stale base` against `cea1746`. The two causes are byte-identical, so the
    /// separation is the ledger's own: an agent that never saw the ticket cannot be carrying its
    /// entry, and cannot have written its closure.
    ///
    /// `MESSAGE-FILE-SHARED` is T-1222, and it is the one refusal here about a file that is not in
    /// the repository at all. Every agent in a session writes into ONE scratchpad directory, so
    /// `-F msg.txt` names a file with several writers and no lock: `938cdb7` (rewritten as
    /// `0fb5504`) carried `ledgerguard`'s whole diff — this script, the runbook, this suite, the
    /// ledger — under `reorderfeel`'s subject line about T-1174/T-1175, because both had written
    /// `…/scratchpad/msg.txt` and `-F` read whichever landed last. The repair every brief carried
    /// afterwards was *"name it `msg-<agent>-<ticket>.txt`"*, which is a rule about remembering;
    /// the basename must now name the agent id, so the name that collided names nobody and is
    /// refused for both of them.
    ///
    /// **It asked the wrong question ([[T-1317]]).** The first reading was
    /// `[[ "${2:t}" == *"$id"* ]]` — membership anywhere in the string — and agent ids here are
    /// short words that sit inside other short words: `sync` was accepted for `msg-async-T-1.txt`
    /// and `order` for `msg-reorder-T-1.txt`, which is the cross-agent mix-up the refusal exists to
    /// stop, written in the shape its own advice produces. The id must be a whole **component** of
    /// the basename now, bounded by a non-alphanumeric character or by an end of the name. Mode 4k
    /// carries both directions: those two names refused, and `msg-<id>-<ticket>.txt` and `<id>.txt`
    /// still committing. The asymmetry worth remembering is that a refusal is proved by the
    /// selftest written in the same commit, so one that is too LOOSE passes its own proof.
    ///
    /// **`REMOVES-HEAD-LINES` counts diff arithmetic, not set membership ([[T-1316]]).** It was
    /// `grep -F -x -v -f <new> <old> | grep -c .`, which counts old line TEXTS absent from the new
    /// file — so deleting one of two identical lines counted 0, and deleting a blank line counted 0
    /// because `grep -c .` drops empty lines. Both are deletions and both committed in silence.
    /// That is not a contrived shape in a ledger built of repeated `  body` continuations and blank
    /// separators: mode 4d2's own archive fixture declared `--removes 1` for a three-line deletion
    /// until this was repaired. Mode 4b1 is the pair of fixtures, read in both directions.
    static let commitHelperRefusals = [
        "MESSAGE-FILE-SHARED",
        "FOREIGN-STAGED",
        "HEAD-MOVED",
        "WORKTREE-BEHIND-HEAD",
        "REBUILD-BEHIND-HEAD",
        "DRIFT-CHECK-MISSING",
        "DRIFT-CHECK-FAILED",
        "SHARED-INDEX-DIRTY",
        "DECLINED-HUNK-LOST",
        "DECLINED-HUNK-STALE",
        "DECLINED-HUNKS-OUTSTANDING",
        "LEDGER-IDS-LOST",
        "LEDGER-CLOSURE-LOST",
        // T-1106, and the pair is one finding read from both ends. `LEDGER-CLOSURE-BURIED` is the
        // other side of `LEDGER-CLOSURE-LOST`'s anchor: that guard defends the READING of the
        // closure marker on an entry's own first line, and nothing asked whether the ledger writes
        // its closures where that reading looks. Fourteen entries in docs/TODO.md were closed in
        // their body and open on their first line when this was measured, T-1085 among them --
        // which read as open for five days after it shipped. `LEDGER-ID-UNFILED` is T-1072's rule
        // made enforceable: the ledger IS the id allocator, so an id that exists only in a commit
        // message is invisible to the next agent computing "next free", and T-1119 went to two
        // agents in one week exactly that way. Naming both here means deleting mode 4e from the
        // selftest goes red rather than quietly halving what the ledger guards prove.
        "LEDGER-CLOSURE-BURIED",
        "LEDGER-ID-UNFILED",
        // T-1206 and T-1207, and they are the two halves `LEDGER-ID-UNFILED` claimed and did not
        // keep. Its header says an id invisible to the allocator is one that lives only in a commit
        // message *or only in another entry's prose*, and it read the message alone:
        // `LEDGER-LINK-UNFILED` is the prose half, read as a delta against HEAD so the 22 links
        // HEAD carries with nothing behind them need no floor and no backfill. Replayed over every
        // commit that ever touched a ledger — 447 of them — it refuses 42, and the seven since
        // 2026-09-03 name T-1117 (the incident T-1106 cites) and four of the eight ids T-1123 spent
        // a day recovering out of commit history by hand.
        // `LEDGER-UNFILED-UNTRACED` is the escape hatch closing behind itself: `--unfiled-ids`
        // authorised a message and wrote nothing anywhere an allocator reads, which is how T-1155
        // and T-1156 became message-only ids — through this family's own flag, one day after T-1123
        // was filed to recover eight others. An id waved past must now be named in a ledger the
        // same commit leaves behind, and `--not-an-id` is the separate, smaller claim for a
        // fragment like `gone=T-3` that is no ticket reference at all. Naming both here means
        // deleting mode 4h or 4i goes red rather than quietly restoring the hole.
        "LEDGER-LINK-UNFILED",
        "LEDGER-UNFILED-UNTRACED",
        // T-1072, and it is the half `LEDGER-ID-UNFILED` structurally cannot reach. That guard
        // makes an id that is in no ledger impossible; in a CONCURRENT allocation both agents file
        // a stub, so both messages pass it and the collision lands anyway. The only artefact two
        // agents reading "next free" before either committed leaves behind is a ledger with two
        // formal `- [T-n]` entries for one id -- T-1119, T-1109/T-1110 and T-1043 all landed in
        // exactly that shape, and `b05869d` committed the whole file twice without anything saying
        // a word. Naming it here means deleting mode 4f goes red rather than quietly leaving the
        // allocator guarded only against the sequential mistake.
        "LEDGER-ID-DUPLICATE",
        // T-1142, and it is the third failure of the one step `LEDGER-CLOSURE-BURIED` guards: the
        // moment an agent writes a closure into an entry. That guard asks whether the closure was
        // written where every instrument looks. This asks whether writing it REPLACED the draft it
        // was meant to replace, or was pasted underneath it -- leaving the entry stating its case
        // twice and, where the draft was a progress note, stating `CLOSED` on its first line and
        // `NOT YET IN HEAD` in its body at the same time. Nothing above can see it: the id is
        // still there, the first line is still a closure, and the line count only ever goes UP.
        // Four entries in docs/TODO.md were in that state when this was measured -- T-781, T-986,
        // T-991, T-992 -- all four written by one commit, `7584c5f`, and unread for the 40 commits
        // of that file since. Naming it here means deleting mode 4g goes red rather than quietly
        // leaving the closure-writing step guarded at two of its three failures.
        "LEDGER-ENTRY-DUPLICATED",
        // T-1148, and it is `LEDGER-IDS-LOST`'s unasked second question. That guard asks whether
        // dropping an id was DELIBERATE, `--drops-ids` answers it, and nothing then asks where the
        // ticket WENT -- while the ordinary way an entry leaves docs/TODO.md is that it MOVES to
        // the archive, i.e. a drop plus an arrival. Only the drop was ever read, so `193f257f`
        // moved 85 entries, left an 86th (T-441) on the floor, and was authorised by the same one
        // flag as the 85. Naming it here means deleting mode 4d3 goes red: measured 2026-09-12,
        // removing that block leaves the string `LEDGER-ID-UNARCHIVED` in the selftest's output
        // exactly zero times, because mode 4c only ever holds it inside a passing check's unprinted
        // detail. Mode 4d3 is also where the two-ids-on-the-floor fixture lives, and that fixture
        // is not decoration -- with one id on the floor, collecting only the LAST unarchived id
        // passed all 173 checks that existed before it.
        "LEDGER-ID-UNARCHIVED",
        "REMOVES-HEAD-LINES",
        "NO-PATHS",
        "UNKNOWN-PATH",
        "NOTHING-TO-COMMIT",
        "NO-COAUTHOR-TRAILER",
        "NOT-REPO-ROOT",
        // T-1092. The commit is where a new product-tree sweep gets its manifest entry, or does not
        // and costs someone else a 22-minute suite run. Naming all three here means deleting mode 8
        // from the selftest goes red rather than quietly halving what the guard is asked to prove.
        "SWEEP-MANIFEST-MISSING",
        "SWEEP-CHECK-MISSING",
        "SWEEP-CHECK-FAILED",
    ]

    /// Every refusal `scripts/agent-scratch.sh` makes (T-1094). The ticket was filed over work that
    /// stopped existing, twice, and its prescribed fix was a paragraph in
    /// `docs/AGENT_BRIEF_PREAMBLE.md`. **It happened a third time on 2026-09-11 with that paragraph
    /// in place**, because the paragraph opened *"a refused commit means your files are the only
    /// copy"* and that agent deleted its tree before reaching a refusal at all. The predicate that
    /// covers both shapes is not about the commit path — it is *is this work in HEAD yet* — so the
    /// guard reads the tree three ways: against the sha it was minted from, against HEAD, and
    /// refuses only what is in neither. `GENERIC-SCRATCH-NAME` and `SCRATCH-NAME-TAKEN` are the
    /// second loss measured that week, when a sibling's `git archive` landed on top of an agent's
    /// tree at `.../scratchpad/tree` and its whole first build-and-test round measured HEAD.
    /// Naming them here means deleting a mode goes red rather than quietly halving the guard.
    static let scratchGuardRefusals = [
        "GENERIC-SCRATCH-NAME",
        "SCRATCH-NAME-TAKEN",
        "SCRATCH-HOLDS-UNLANDED-WORK",
        "UNKNOWN-SCRATCH",
        "NOT-REPO-ROOT",
    ]

    /// Every refusal `scripts/ledger-lag-check.sh` makes (T-1298), and the pair is one finding read
    /// from both ends. `LEDGER-CLOSURE-LAGGED` is the direction `agent-commit.sh` never ran: that
    /// script's `LEDGER-ID-UNFILED` means a commit message cannot name an id the ledger has never
    /// heard of, so an id cannot be LOST — and nothing asked whether an id a landed commit named is
    /// still sitting in the open sections. Three were on 2026-09-19, one and two days after their
    /// code shipped, and T-626's entry was still telling its next reader *"BLOCKED ON iOS
    /// DISTRIBUTION — do not implement until that changes"* about work that had already landed.
    ///
    /// `LEDGER-LAG-VACUOUS` is the half that keeps the first one from becoming decoration, and it
    /// is this session's recurring shape rather than a precaution: T-1282 found an iOS gate that
    /// passed having compiled nothing and T-1291 a canary that had silently stopped guarding. A
    /// GitHub Actions checkout defaults to `fetch-depth: 1`; over one commit this check examines
    /// zero commits, finds nothing and exits 0. So it counts what it read — commits, ledger
    /// entries, and commits actually EXAMINED — and refuses a run below any of the three floors.
    /// The third is the one a renamed ledger or a rotted path predicate trips while the other two
    /// still look healthy. Naming both here means deleting either mode goes red rather than
    /// quietly halving what the guard proves.
    ///
    /// **And the floor caught the script's own parser, which is what a floor is for ([[T-1317]]).**
    /// The three inputs were told apart positionally with `FNR == 1 { part++ }`, and an empty file
    /// never yields `FNR == 1`: with the optional archive missing — it is written as a zero-byte
    /// file when `git show` cannot find it — the commit log was parsed as the archive and no line
    /// was read as a commit at all. Measured at HEAD,
    /// `CADENCE_LEDGER_LAG_DONE=docs/NO_SUCH_ARCHIVE.md` reported "0 commits, 0 examined" and
    /// refused `LEDGER-LAG-VACUOUS`. The parts are keyed on `FILENAME` now, and mode 6 holds both
    /// directions plus the same defect written the other way round, a zero-byte `docs/TODO.md`.
    static let ledgerLagRefusals = [
        "LEDGER-CLOSURE-LAGGED",
        "LEDGER-LAG-VACUOUS",
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
    /// strand it, and the queue behind it must not stall because one waiter declined. `dead-owner-
    /// reclaims-early` / `dead-owner-defers-to-live-host` are T-956 -- the symmetric case one level
    /// later: an OWNER that dies after already taking the lock must not strand it for the full
    /// LEASE (a dead owner pid shortcuts the wait), but still must not reclaim out from under a
    /// live test host the dead owner's shell happened to start.
    ///
    /// `cannot-tell-refuses` / `cannot-tell-keeps-queue` are T-1152, and they are the case
    /// underneath every entry above: all of those ask a probe about other processes, and until
    /// 2026-09-12 a probe that could not answer was read as answering *no*. `live_test_hosts` was
    /// `pgrep … 2>/dev/null | wc -l`, which turns a denied process list into a confident `0` — the
    /// one value that unlocks the reclaim branch — and `waiter_alive`'s `ps -o command=` turns the
    /// same denial into "this waiter is dead" for every ticket in the queue at once. Both fixtures
    /// carry their own failing-first half: the selftest runs the OLD expression over the same
    /// fixture first and prints what it answered, so a `PASS` line that did not discriminate would
    /// say so in its own text (`the old reading answered '0'`, `called all 3 waiters dead`).
    ///
    /// `host-pattern-calibration` is T-1162, and it is the one property about the **constant**.
    /// Every entry above overrides `HOST_PATTERN` wholesale through `CADENCE_LOCK_PGREP`, so ten
    /// green properties proved the plumbing and none of them had ever read the pattern the script
    /// actually ships — which was `'^/Applications/.*/xcodebuild test'`, i.e. the action as the
    /// FIRST argument. `xcb.sh` appends the action LAST, so that pattern matched no test run this
    /// repository makes; measured 2026-09-12 against a live run, it printed nothing and exited 1
    /// while `ps` showed the process. The property keeps the real action half verbatim, swaps only
    /// the binary anchor, and runs both the old and the new form over five live processes whose
    /// argv is a command line copied from a real invocation.
    static let testHostLockProperties = [
        "ordering",
        "no-reclaim",
        "reclaim",
        "killed-waiter",
        "dead-parent-declines",
        "dead-parent-recovers",
        "dead-owner-reclaims-early",
        "dead-owner-defers-to-live-host",
        "cannot-tell-refuses",
        "cannot-tell-keeps-queue",
        "host-pattern-calibration",
    ]

    /// `ordering` and `no-reclaim` cannot be PROVEN from inside this test host -- not "are awkward
    /// to", cannot. Both read cross-process liveness (`waiter_alive`'s `ps -o command= -p $pid`,
    /// `live_test_hosts`'s `pgrep -f`) and CadenceTests runs App-Sandboxed -- but the two halves
    /// fail by DIFFERENT mechanisms, which T-959 originally ran together and which
    /// `CadenceTestHostSandboxCapabilityTests` now pins apart (measured 2026-09-12):
    ///
    /// * `/bin/ps` is refused at `posix_spawn` -- `NSPOSIXErrorDomain Code=1` before a byte of
    ///   output -- because it is **setuid root**, not because it is `ps`. `waiter_alive` then reads
    ///   an empty command line and calls every waiter dead.
    /// * `/usr/bin/pgrep` is NOT setuid and spawns perfectly well. It exits 3 saying *"Cannot get
    ///   process list"*, so `live_test_hosts` pipes nothing into `wc -l` and reports a completely
    ///   plausible **0**. That is the worse of the two: a refusal announces itself, an answer of
    ///   zero does not (T-1152).
    ///
    /// A child `zsh` inherits the same sandbox, so a script's own internal calls hit the same wall.
    /// So these two are TOLERATED failures below, not required, and they are
    /// proven the other way instead: direct terminal invocation, captured in docs/TODO.md's T-748
    /// and T-650 entries (`w4 w1 w2 w3` before the fix, `w1 w2 w3 w4` after, three runs of three).
    ///
    /// `dead-owner-defers-to-live-host` (T-956) joins them for the identical reason: it also proves
    /// its property through `live_test_hosts`'s `pgrep`, by way of the same fake-host fixture as
    /// `no-reclaim`.
    ///
    /// `reclaim` and `dead-owner-reclaims-early` JOINED THEM ON 2026-09-12, and how they did is
    /// the most useful thing in this comment. Until T-1152 both passed in here, and the paragraph
    /// that used to sit at this spot explained why in so many words: *"a `pgrep` that runs but can
    /// read no process list reports zero matches, which is indistinguishable from a real zero and
    /// proves the property regardless"*. Both of those properties assert that a lease IS
    /// reclaimed, and both were being proved by the blind zero that T-1152 exists to abolish --
    /// passing on the lie, in the suite written to catch lies. Now that the script refuses rather
    /// than counting when it cannot ask, the two fail here and are tolerated honestly. Nothing
    /// about the lock got weaker; two green lines stopped being green for no reason.
    ///
    /// Six of the eleven properties are now unprovable from this host, which is a poor ratio for a
    /// suite whose job is to notice rot. That is filed as [[T-1161]] rather than absorbed here.
    static let testHostLockPropertiesUnverifiableInThisSandbox: Set<String> = [
        "ordering", "no-reclaim", "dead-owner-defers-to-live-host",
        "reclaim", "dead-owner-reclaims-early",
        // T-1162's property is the same sandbox limit one step earlier: it asks a real `pgrep`
        // about real processes it spawned, and in here `pgrep` runs, is denied the process list
        // and exits 3. `live_test_hosts` correctly refuses to answer, the fixture correctly calls
        // that a failure, and the run outside the sandbox is where the calibration is read.
        "host-pattern-calibration",
    ]

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

    /// T-1076. `scripts/xcb.sh`'s two `-only-testing:` outcomes, and they are deliberately
    /// asymmetric. `UNKNOWN-SUITE` REFUSES (exit 8, before the build and before the test-host
    /// lock): a name matching no suite selects nothing, and xcodebuild calls that a success.
    /// `PARTIAL-SCOPE` only PRINTS: scoping to one suite of a file that holds several is usually
    /// deliberate, and a guard that failed the ordinary case would be switched off inside a week.
    ///
    /// Pinning the pair matters more than pinning either alone. The whole finding behind the
    /// ticket is that the quiet case must be *visible without being fatal* — 26 files declare a
    /// suite named after the file plus siblings, and scoping one by filename skips 311 of the 688
    /// tests in them while exiting 0 — so a later "tightening" that made `PARTIAL-SCOPE` fail the
    /// run would read as an improvement and would in fact be the thing that removes it.
    ///
    /// Source-level only, no shell-out: `xcb.sh selftest`'s live half asks `test-suite-index.sh`
    /// for the real index, which runs `python3` — and this test host is App-Sandboxed, where the
    /// `/usr/bin/python3` xcrun shim refuses outright (T-719). The selftest degrades to a printed
    /// `skip` there rather than a failure, so shelling out would assert progressively less while
    /// looking like it asserted more. Reading the source proves the refusals still exist and are
    /// still induced, and it cannot be defeated by the environment.
    ///
    /// T-1147 adds a third, and like `PARTIAL-SCOPE` it is a notice rather than a refusal — which
    /// is the reason it has to be pinned here. `VACUOUS-COUNT` is what the banner says when a run
    /// compiled 0 Swift files, and the count it decorates is `warnings: 0`: the most reassuring
    /// line the runner can print, over an empty set. `AGENTS.md` had been asking agents to check
    /// that by hand for months, every brief repeated it, and the one thing that could delete the
    /// instrument without deleting a refusal is a later edit that decides the notice is noise.
    /// The warning counter it guards was itself the loose `grep -c 'warning:'` this repository
    /// bans for errors, and it reported the AppIntents metadata notice as a compiler warning on
    /// every full test build — `warnings: 1` against a baseline of zero — until 2026-09-12.
    ///
    /// T-1149 adds a fourth, and this one IS a refusal: `WARNING-BASELINE` is what the runner says
    /// when a run that recompiled Swift produced anchored warnings, and it is the only one of the
    /// four that changes the exit code (9). Pinning it matters more than the other three rather
    /// than less, for the reason the ticket exists: the baseline of zero was stated in `AGENTS.md`,
    /// in `CLAUDE.md` and in the release checklist for months while nothing local acted on it, so
    /// the failure mode this repository has actually demonstrated is a rule that everybody quotes
    /// and no instrument enforces. A later edit that removes the gate and leaves the banner would
    /// restore exactly that state, and every caller reading an exit code would go on reading zero.
    /// Both halves of the check earn their keep here: the body must still make the refusal, and
    /// section 7 of the selftest must still induce it over a fixture log carrying a real
    /// `\.swift:N:C: warning:` — a gate asserted only by a name in a list is a gate nobody has run.
    ///
    /// T-1282 adds a fifth, and it is `UNKNOWN-SUITE` asked one step earlier: `NO-SUCH-SIMULATOR`
    /// refuses an `-destination 'platform=iOS Simulator,name=…'` naming a device this Mac does not
    /// have. Measured 2026-09-18, that destination returns **exit 70 with `compile errors: 0` and
    /// `warnings: 0`** over **zero** compiled Swift files, and the shell pipeline around it exits
    /// 0 — so the only dissent in the whole run is `VACUOUS-COUNT`, which says the count is about
    /// nothing rather than that the build was. It is worse than an ordinary red because the macOS
    /// test target never compiles `Cadence/iOS/`: an agent that accepts it has never compiled the
    /// code it changed, and the macOS suite stays green over the top. Pinning it here is the part
    /// that does not rot — a device name written into a guide was correct until an Xcode update
    /// dropped the device, which is exactly how `iPhone 15` came to be typed, so the guard reads
    /// `simctl` live and the selftest drives it through a fixture in that format.
    static let buildRunnerRefusals = [
        "UNKNOWN-SUITE",
        "PARTIAL-SCOPE",
        "VACUOUS-COUNT",
        "WARNING-BASELINE",
        "NO-SUCH-SIMULATOR",
    ]

    /// T-780. `.githooks/pre-commit` is the only guard in this family that is not a script anybody
    /// types: git runs it, with no arguments, or nothing runs it at all. That makes it the one most
    /// able to rot unnoticed — a hook that has quietly stopped refusing looks exactly like a hook
    /// nobody has tripped lately.
    ///
    /// Two names, and the second is not a refusal at all, which is the point. `BARE-COMMIT` is the
    /// refusal itself; `ALLOW-OVERRIDE` is the escape hatch **announcing that it was used**. A guard
    /// with a silent bypass is a guard whose bypass becomes the habit, so the notice is as
    /// load-bearing as the refusal and is pinned the same way.
    ///
    /// What is deliberately NOT pinned here is that the hook is armed. `core.hooksPath` lives in
    /// the untracked `.git/config`, so this file lands inert and stays inert until the repository's
    /// owner types `git config core.hooksPath .githooks` — their decision, because it also refuses
    /// their own by-hand commits. A test that asserted the live checkout was armed would be an
    /// agent installing that decision by the back door, and would fail in every fresh clone.
    static let preCommitHookRefusals = [
        "BARE-COMMIT",
        "ALLOW-OVERRIDE",
    ]

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

    /// T-1094. Runs entirely inside a throwaway git repository under `$TMPDIR`: it mints trees,
    /// edits them, commits in that repository and releases them, and touches neither this checkout
    /// nor any tree a sibling is building in. About two seconds. The two checks worth knowing about
    /// are the pair in mode 3 — the same tree is REFUSED before its commit and releasable the moment
    /// the commit reaches HEAD — and the one above them, an untouched tree eight commits behind HEAD
    /// naming zero files, which is what a two-way reading against HEAD alone could not do.
    @Test func theScratchGuardsOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/agent-scratch.sh")
        let complaints = run.complaints(requiring: Self.scratchGuardRefusals)
        #expect(complaints.isEmpty, "./scripts/agent-scratch.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-1298. Runs entirely inside a throwaway git repository under `$TMPDIR`: it writes fixture
    /// ledgers, commits against them and runs the check over its own history, so it says nothing
    /// about — and does nothing to — this checkout, and is safe alongside siblings committing in
    /// it. Under a second.
    ///
    /// The two checks worth knowing about are the controls rather than the refusal. Mode 2 is the
    /// whole design problem in six lines: an id can be named by a commit that FILED it rather than
    /// closed it, and this repository files residue tickets out of the very commit that closed
    /// their parent (`bc91b2c` closed T-1135 and filed T-1163, which is open to this day). So the
    /// rule is per-COMMIT — a commit that lands code must close at least one of the ids it names —
    /// and mode 2 proves each way an id is legitimately still open: a docs-only commit, a pair
    /// where the other half closed, a `## Done` entry with no marker at all, an entry archived to
    /// `TODO_DONE.md`, and an id no ledger has ever heard of. Mode 4's last check is the other one:
    /// a real `git clone --depth 1`, which is what Actions does unless a workflow says otherwise.
    @Test func theLedgerLagGuardsOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/ledger-lag-check.sh")
        let complaints = run.complaints(requiring: Self.ledgerLagRefusals)
        #expect(complaints.isEmpty, "./scripts/ledger-lag-check.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-780. Runs entirely inside a throwaway git repository under `$TMPDIR`, like the drift
    /// guard's: it arms `core.hooksPath` **there**, never here, so it says nothing about — and does
    /// nothing to — whether the real checkout has the hook installed. About a second.
    ///
    /// The selftest's own mode 0 is what makes the rest of it evidence: the same bare commit must
    /// SUCCEED with the hook unarmed. Without that control every refusal below it could equally be
    /// a fixture that cannot commit at all, which is the shape of a guard that passes for the wrong
    /// reason. Mode 3 is the other half — it runs the real `scripts/agent-commit.sh` against the
    /// armed repository, because "plumbing runs no hooks" is a claim about git that this repository
    /// is now betting its commit path on, and citing it is cheaper than checking by exactly the
    /// margin that makes it worth checking.
    @Test func theBareCommitHooksOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of(".githooks/pre-commit")
        let complaints = run.complaints(requiring: Self.preCommitHookRefusals)
        #expect(complaints.isEmpty, ".githooks/pre-commit selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-748. Runs against the REAL lock's own sandbox (`CADENCE_LOCK_DIR`, not the live
    /// `${TMPDIR}cadence-macos-test-host.lock`), so this is safe to run alongside sibling agents
    /// actually holding that lock. Real subprocesses and real `sleep`s, so this one runs for tens of
    /// seconds rather than about one -- see the type doc above.
    ///
    /// `ordering` / `no-reclaim` are TOLERATED, not required (T-959: this host cannot spawn the
    /// setuid `ps` at all, and the `pgrep` it can spawn cannot read the process list -- see the
    /// `testHostLockPropertiesUnverifiableInThisSandbox` doc). Tolerating a named failure is not
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
    /// `ordering` is TOLERATED, not required -- `waiter_alive`'s setuid `ps`, same as above (T-959).
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
            ("scripts/agent-scratch.sh", Self.scratchGuardRefusals),
            ("scripts/worktree-drift.sh", Self.worktreeDriftRefusals),
            ("scripts/ledger-lag-check.sh", Self.ledgerLagRefusals),
            ("scripts/xcb.sh", Self.buildRunnerRefusals),
            (".githooks/pre-commit", Self.preCommitHookRefusals),
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

    /// The two readings `scripts/agent-commit.sh` makes that are deliberately NOT refusals, and are
    /// therefore invisible to the sweep above — a refusal at least leaves its name in a list.
    ///
    /// `LEDGER-CLOSURE-LAGGED` is T-1300: `ledger-lag-check.sh` asks in CI whether an id named by a
    /// commit that landed code is still open, and by then the commit is pushed, the run is red and
    /// the owner has an email — the noise they have complained about before. Everything that
    /// reading needs is in the commit path one step earlier. It warns rather than refuses because
    /// of the replay the ticket demanded first: over 1139 commits, the same rule as a refusal would
    /// have stopped 191 of the 274 that land code and name a filed id, and 22 of the last 128 —
    /// four of them with the closure landing in the very next commit, which is this repository's
    /// own practice. A refusal that fires on ordinary work gets routed around, and then it guards
    /// nothing; the CI check stays the gate, and this names the ticket before anything is pushed.
    ///
    /// `ledger_rewrites_only_new_entries` is T-1246, and it is a refusal being WITHDRAWN rather
    /// than made: closing the newest ledger entry rewrites every line HEAD introduced, which reads
    /// as `stale base` and was refused as `REBUILD-BEHIND-HEAD` with `--commits-stale` — the flag
    /// every brief forbids — as its only escape. The two causes are byte-identical to any function
    /// of the content and the history, so the separation is the ledger's own: an entry for an id
    /// that exists nowhere but HEAD, carrying that ticket's closure, cannot have been written by an
    /// agent that never saw it. Naming the function here means deleting the rule, or the mode that
    /// induces it, goes red rather than quietly restoring the false refusal.
    @Test func theCommitHelpersReadingsThatAreNotRefusalsAreStillInducedByItsSelftest() throws {
        let source = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent("scripts/agent-commit.sh"),
            encoding: .utf8
        )
        guard let split = source.range(of: "\n# --- selftest") else {
            Issue.record("scripts/agent-commit.sh has no `# --- selftest` section to read")
            return
        }
        let body = String(source[source.startIndex..<split.lowerBound])
        let selftest = String(source[split.lowerBound...])
        for reading in ["LEDGER-CLOSURE-LAGGED", "ledger_rewrites_only_new_entries", "T-1305"] {
            #expect(body.contains(reading), "scripts/agent-commit.sh no longer makes the reading \(reading)")
            #expect(selftest.contains(reading), "scripts/agent-commit.sh's selftest no longer induces \(reading)")
        }
    }

    /// The same question of `scripts/ledger-lag-check.sh`, whose T-1303 reading is likewise a
    /// refusal WITHDRAWN rather than made and so leaves no name in `ledgerLagRefusals`.
    ///
    /// An id is open only while NO entry of it is closed. Reading "open" off whichever entry came
    /// last made a DOUBLE-ALLOCATED id flag its own closing commit: at `dcb0a15`, `docs/TODO.md`
    /// held two formal `- [T-1043]` entries, one closed and one open — T-1072's concurrent-
    /// allocation residue — and that commit closed T-1043 on the entry's own first line, in the
    /// commit that landed the fix, which is the exact discipline this check exists to enforce.
    /// It was flagged anyway, in both entry orders. This check runs in both CI workflows on every
    /// push, so a false positive is an email to the owner about work that was done correctly.
    /// Naming the ticket here means deleting the rule, or mode 2b that induces it — the only
    /// fixture in that suite holding one id twice — goes red rather than quietly restoring it.
    @Test func theLagChecksReadingThatIsNotARefusalIsStillInducedByItsSelftest() throws {
        let source = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent("scripts/ledger-lag-check.sh"),
            encoding: .utf8
        )
        guard let split = source.range(of: "\n# --- selftest") else {
            Issue.record("scripts/ledger-lag-check.sh has no `# --- selftest` section to read")
            return
        }
        let body = String(source[source.startIndex..<split.lowerBound])
        let selftest = String(source[split.lowerBound...])
        for reading in ["T-1303", "closedi"] {
            #expect(body.contains(reading), "scripts/ledger-lag-check.sh no longer makes the reading \(reading)")
        }
        #expect(selftest.contains("T-1303"), "scripts/ledger-lag-check.sh's selftest no longer induces T-1303")
    }

    /// And all eight guards have to be there to be run. A renamed script would otherwise make the
    /// tests above fail for a reason that reads nothing like "the guard is gone".
    ///
    /// The executable bit is not a formality for `.githooks/pre-commit` (T-780): git **silently
    /// skips** a hook it cannot execute — no warning, no non-zero exit, the commit simply goes
    /// through — so a mode lost to a `chmod`, a `cp`, or a patch applied by hand turns the refusal
    /// off while leaving every line of it in the file for a reader to be reassured by.
    @Test func allGuardScriptsExistAndAreExecutable() throws {
        for script in [
            "scripts/mutate.sh",
            "scripts/agent-commit.sh",
            "scripts/agent-scratch.sh",
            "scripts/test-host-lock.sh",
            "scripts/simulator-claim.sh",
            "scripts/worktree-drift.sh",
            "scripts/ledger-lag-check.sh",
            "scripts/xcb.sh",
            ".githooks/pre-commit",
        ] {
            let path = CadenceSelftestRun.repositoryRoot().appendingPathComponent(script).path
            #expect(FileManager.default.isExecutableFile(atPath: path), "\(script) is missing or not executable")
        }
    }

    /// T-1074, and it is a property of the *shell*, not of any one refusal: a second bare
    /// `local x` in one zsh function does not redeclare the parameter, it PRINTS it —
    /// `x=<value>` on stdout — because that is `typeset`'s listing behaviour reached by a
    /// declaration that looks like C. Inside a loop the declaration is reached again on every
    /// iteration, so the leak starts on the second pass and never stops. Any flag suppresses the
    /// listing (`local -a x` twice is silent), which is most of why the shape hides.
    ///
    /// These scripts' stdout **is** how they report refusals and readings, so the corruption
    /// arrives dressed as a diagnostic in the middle of a message an agent is reading to decide
    /// whether its work is safe to commit. Three shipped instances were found this way; the two
    /// live ones sat inside `xcb.sh`'s `UNKNOWN-SUITE` refusal, one of them between
    /// *"Did you mean:"* and the answer.
    ///
    /// `agent-commit.sh`, `worktree-drift.sh` and `xcb.sh` each pin their own instance
    /// *behaviourally*, by inducing a refusal twice and grepping the output. This is the other
    /// half: a structural sweep of every script in `scripts/`, so a bare declaration added to a
    /// loop nobody thought to induce is still caught — including in `mutate.sh`,
    /// `test-host-lock.sh` and `simulator-claim.sh`, which had never been swept at all.
    @Test func noZshScriptReachesABareLocalDeclarationTwice() throws {
        // Every script in `scripts/`, not just the six with selftests: the shape is a property of
        // the shell, so naming a list would leave the next script written here unswept. The floor
        // below is what stops a broken enumeration from sweeping nothing and reading as a pass.
        let root = CadenceSelftestRun.repositoryRoot()
        let scripts = root.appendingPathComponent("scripts")
        let names = try FileManager.default.contentsOfDirectory(atPath: scripts.path)
            .filter { $0.hasSuffix(".sh") }
            .sorted()
        // `.githooks/pre-commit` (T-780) is a zsh script with a `selftest` and a `check` loop like
        // the rest of them, and it is the one member of the family with no `.sh` on the end —
        // git requires the bare name. Enumerating `scripts/` alone would have left exactly the
        // guard nobody invokes by hand as the only one unswept.
        var targets = names.map { (path: scripts.appendingPathComponent($0).path, label: "scripts/\($0)") }
        targets.append((path: root.appendingPathComponent(".githooks/pre-commit").path, label: ".githooks/pre-commit"))
        var findings: [String] = []
        var declarationsRead = 0
        for target in targets {
            let scan = try CadenceShellLocalScan.of(path: target.path, label: target.label)
            findings.append(contentsOf: scan.findings.map(\.description))
            declarationsRead += scan.declarationsRead
        }
        // The floor, because a clean sweep and a sweep that stopped reading print the same nothing.
        // 12 scripts declared 229 names when this was written, and `.githooks/pre-commit` adds 12
        // more (T-780); a reading that has fallen under 100 has lost a parse, not a script. (228
        // before the `case`-arm read below was added — the 229th is `run-macos-app.sh`'s
        // `(status) local -a pf`, which the reader used to skip.) Re-measured at `17b5b61`:
        // **340** across 13 scripts plus the hook, and the floor is deliberately left at 100 —
        // it is there to catch a parse that died, not to be retyped every time a script grows.
        // The 340 was confirmed by a second, independently written reader (T-1074), which agreed
        // to the declaration: same total, same zero findings.
        #expect(names.count >= 6, "scripts/ holds \(names.count) .sh files, so this sweep is reading less than it claims")
        #expect(declarationsRead >= 100, "the sweep read only \(declarationsRead) declarations, so its silence means nothing")
        #expect(
            findings.isEmpty,
            """
            a bare `local x` reached twice in one zsh function prints `x=<value>` instead of \
            redeclaring it (T-1074). Hoist the declaration out of the loop, or give it a flag:
            \(findings.joined(separator: "\n"))
            """
        )
    }

    /// The sweep above says nothing on a healthy tree, which is exactly the shape this repository
    /// keeps catching as hollow — a reading that would also be silent if it had stopped reading.
    /// So the scanner is run against source it must complain about, and against the near-misses it
    /// must stay quiet on. The near-misses are the load-bearing half: a scanner that flagged every
    /// `local` in a loop would have flagged the two `local -a` declarations sitting beside the real
    /// findings in `xcb.sh`, and would have been turned off rather than fixed.
    @Test func theBareLocalScanCanTellTheShapeFromItsNearMisses() throws {
        let cases: [(name: String, source: String, leaks: Bool)] = [
            ("a bare local reached twice in one scope", "f() {\n  local x=1\n  local x\n}\n", true),
            ("a bare local inside a loop", "f() {\n  for i in 1 2; do\n    local g\n    g=\"v$i\"\n  done\n}\n", true),
            ("a bare local in a loop nested two deep", "f() {\n  for j in 1 2; do\n    for i in 1 2; do\n      local g\n    done\n  done\n}\n", true),
            // The three shapes the sweep used to walk straight past. The first two are the C-style
            // arithmetic `for`, whose `do` zsh serialises onto the header line — the loop form
            // every one of this repo's own `for ((…))` loops uses, including the one T-1074 was
            // filed about. The third is a declaration sharing a `case` arm's pattern line.
            ("a bare local inside a C-style arithmetic for loop", "f() {\n  for ((i=1;i<=2;i++)); do\n    local g\n    g=$i\n  done\n}\n", true),
            ("a bare local in a C-style for loop written with braces", "f() {\n  for ((i=1;i<=2;i++)) { local g; g=$i }\n}\n", true),
            ("a declaration sharing a case arm's pattern line", "f() {\n  case $1 in\n    (a) local z=1;;\n  esac\n  local z\n}\n", true),
            ("a case arm that declares nothing", "f() {\n  case $1 in\n    (a) say hi;;\n  esac\n  local x\n}\n", false),
            ("one bare local, declared once", "f() {\n  local x\n  x=1\n}\n", false),
            ("the second declaration assigns", "f() {\n  local x=1\n  local x=2\n}\n", false),
            ("the declaration in the loop carries a flag", "f() {\n  for i in 1 2; do\n    local -a g\n    g=(1)\n  done\n}\n", false),
            ("the same name in two different functions", "f() {\n  local x\n}\ng() {\n  local x\n}\n", false),
            ("a bare local after the loop that used the name has closed", "f() {\n  for i in 1 2; do\n    : $i\n  done\n  local x\n}\n", false),
            ("`local` inside a comment or a string", "f() {\n  # local x\n  say \"local x\"\n  local x\n}\n", false),
        ]
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cadence-local-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for probe in cases {
            let path = dir.appendingPathComponent("probe.sh")
            try probe.source.write(to: path, atomically: true, encoding: .utf8)
            let scan = try CadenceShellLocalScan.of(path: path.path, label: probe.name)
            #expect(
                scan.findings.isEmpty != probe.leaks,
                probe.leaks
                    ? "the scan missed: \(probe.name)"
                    : "the scan flagged \(probe.name), which does not leak: \(scan.findings.map(\.description))"
            )
        }
    }

}

/// Reads a zsh script for the T-1074 shape: a bare `local`/`typeset`/`declare` declaration that one
/// run of a function can reach twice.
///
/// **It does not grep.** A needle that matches itself in a comment or a doc string is how two
/// checks in this family were hollowed out this week, and `local` appears in the prose of these
/// scripts more often than in their code. `CadenceSourceScan.strippedSourceReader()` is the answer
/// on the Swift side; the shell equivalent is better than stripping, because zsh will hand over its
/// own parse: `functions f` prints a function's body **re-serialised from the parse tree** — no
/// comments, one statement per line, `do`/`done` on lines of their own, and tab indentation that is
/// real block nesting rather than whatever the author typed. Wrapping the whole file in one
/// function definition and asking for it back gets that reading for a script, and `eval` of a
/// function *definition* parses the body without running a line of it.
struct CadenceShellLocalScan {
    struct Finding: CustomStringConvertible {
        let label: String
        let scope: String
        let name: String
        let reason: String

        var description: String { "  \(label): `local \(name)` in \(scope)() — \(reason)" }
    }

    let findings: [Finding]
    /// How many names the reading actually looked at. A scan that has quietly stopped parsing
    /// reports no findings, exactly like a clean one; this is what tells the two apart.
    let declarationsRead: Int

    static func of(path: String, label: String) throws -> CadenceShellLocalScan {
        let run = try CadenceSelftestRun.run("/bin/zsh", [
            "-f", "-c",
            """
            eval "__cadence_scan_wrap() {
            $(cat -- "$1")
            }"
            functions __cadence_scan_wrap
            """,
            "zsh", path,
        ])
        guard run.status == 0 else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [NSLocalizedDescriptionKey: "zsh could not parse \(label): \(run.output)"]
            )
        }
        let read = reading(inNormalised: run.output, label: label)
        return CadenceShellLocalScan(findings: read.findings, declarationsRead: read.declarationsRead)
    }

    /// One scope per function definition, plus the outermost wrapper, which stands for the script's
    /// own top level. `local` is function-scoped in zsh, not block-scoped, so a name declared
    /// anywhere in a function counts against every later declaration in it.
    static func reading(inNormalised text: String, label: String) -> (findings: [Finding], declarationsRead: Int) {
        struct Scope {
            let indent: Int
            let name: String
            var seen: Set<String> = []
            var openLoops = 0
        }
        var scopes: [Scope] = []
        var found: [Finding] = []
        var read = 0

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let indent = rawLine.prefix(while: { $0 == "\t" }).count
            let line = rawLine.drop(while: { $0 == "\t" })
            if line.isEmpty { continue }

            if let name = functionHeaderName(line) {
                scopes.append(Scope(indent: indent, name: scopes.isEmpty ? "<top level>" : name))
                continue
            }
            if line == "}", let current = scopes.last, current.indent == indent {
                scopes.removeLast()
                continue
            }
            guard !scopes.isEmpty else { continue }
            if opensLoop(line) {
                scopes[scopes.count - 1].openLoops += 1
                continue
            }
            if line == "done" || line.hasPrefix("done ") {
                scopes[scopes.count - 1].openLoops = max(0, scopes[scopes.count - 1].openLoops - 1)
                continue
            }
            guard let (hasFlag, names) = declaration(casePatternStripped(line)) else { continue }
            for (name, assigns) in names {
                if !assigns && !hasFlag {
                    if scopes[scopes.count - 1].seen.contains(name) {
                        found.append(Finding(label: label, scope: scopes[scopes.count - 1].name, name: name,
                                             reason: "the scope already declares it, so this prints it"))
                    } else if scopes[scopes.count - 1].openLoops > 0 {
                        found.append(Finding(label: label, scope: scopes[scopes.count - 1].name, name: name,
                                             reason: "it is inside a loop, so every pass after the first prints it"))
                    }
                }
                scopes[scopes.count - 1].seen.insert(name)
                read += 1
            }
        }
        return (found, read)
    }

    /// Whether this line opens a loop body — `do` alone, **or** `do` closing a loop header.
    ///
    /// **This is what let the very shape T-1074 is about through the sweep (T-1085 batch).** zsh
    /// re-serialises every loop it has a keyword for — `for x in …`, `while`, `until`, `repeat`,
    /// `select` — with `do` on a line of its own, and exactly one form differently: the C-style
    /// arithmetic `for ((…))`, which comes back as `for ((i = 1; i <= n; i++ )) do`. A reader that
    /// only recognised a standalone `do` therefore never entered those bodies, `openLoops` stayed
    /// 0, and a bare declaration inside one was invisible — while `done` still balanced away under
    /// `max(0,)`, so nothing went wrong loudly.
    ///
    /// Measured rather than reasoned: un-hoisting `worktree-drift.sh`'s `gone` reproduces
    /// `gone=T-3` in the middle of the drift report, and the sweep as it stood read all 46 of that
    /// file's declarations and reported nothing. The three scripts that hold this repo's
    /// `for ((…))` loops — `agent-commit.sh`, `worktree-drift.sh`, `xcb.sh` — are the same three
    /// that held T-1074's shipped instances.
    private static func opensLoop(_ line: Substring) -> Bool {
        if line == "do" { return true }
        guard line.hasSuffix(" do") else { return false }
        return ["for ", "while ", "until ", "repeat ", "select "].contains { line.hasPrefix($0) }
    }

    /// A `case` arm's first statement shares the pattern's line — `(status) local -a pf` — so a
    /// declaration there begins at the second token and a reader starting at the first sees a
    /// command called `(status)`. Both halves matter: such a declaration is neither flagged nor
    /// *recorded*, so a later bare `local` of the same name reads as the first one.
    ///
    /// A leading parenthesised token is unambiguously a case pattern in this text: zsh writes a
    /// subshell as `(` … `)` across lines of its own, and an arithmetic `(( … ))` leaves a
    /// remainder that is not a declaration.
    private static func casePatternStripped(_ line: Substring) -> Substring {
        guard line.hasPrefix("("), let close = line.firstIndex(of: ")") else { return line }
        var rest = line[line.index(after: close)...]
        while rest.hasPrefix(" ") { rest = rest.dropFirst() }
        return rest.isEmpty ? line : rest
    }

    private static func functionHeaderName(_ line: Substring) -> String? {
        guard line.hasSuffix("{") else { return nil }
        var head = Substring(line.dropLast())
        while head.hasSuffix(" ") { head = head.dropLast() }
        guard head.hasSuffix(")") else { return nil }
        head = head.dropLast()
        guard head.hasSuffix("(") else { return nil }
        head = head.dropLast()
        while head.hasSuffix(" ") { head = head.dropLast() }
        guard let first = head.first, first.isLetter || first == "_" else { return nil }
        guard head.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == ":" || $0 == "." || $0 == "-" }) else { return nil }
        return String(head)
    }

    /// `(hasFlag, [(name, assigns)])` for a declaration line, or nil if the line is not one.
    ///
    /// Any flag at all — `local -a`, `typeset -A`, `local -i` — suppresses zsh's listing, so a
    /// flagged declaration can never leak and is recorded only so a later *bare* one is caught.
    /// Name parsing stops at the first value that could contain whitespace, because zsh serialises
    /// `local a=1 b=2` as three tokens but `local M='some words'` as several: under-reading there
    /// costs a missed finding, over-reading would invent a declaration out of a quoted word.
    private static func declaration(_ line: Substring) -> (Bool, [(String, Bool)])? {
        var tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard let keyword = tokens.first, ["local", "typeset", "declare"].contains(String(keyword)) else { return nil }
        tokens.removeFirst()

        var hasFlag = false
        while let token = tokens.first, token.hasPrefix("-") || token.hasPrefix("+") {
            hasFlag = true
            tokens.removeFirst()
        }

        var names: [(String, Bool)] = []
        for token in tokens {
            guard let first = token.first, first.isLetter || first == "_" else { break }
            let name = token.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
            let rest = token.dropFirst(name.count)
            if rest.isEmpty {
                names.append((String(name), false))
                continue
            }
            guard rest.hasPrefix("=") else { break }
            names.append((String(name), true))
            if rest.contains("'") || rest.contains("\"") { break }
        }
        return names.isEmpty ? nil : (hasFlag, names)
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
