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
        // T-1304, and it is [[T-1222]]'s unshipped half. That ticket's name rule stops two agents
        // writing the same `-F` file; nothing stopped a correctly-named file holding the wrong
        // work, which is what `938cdb7` committed -- one agent's T-1206/T-1207/T-1209 ledger diff
        // under another's T-1174/T-1175 subject, past every guard above. The reading is that the
        // message ids and the ids whose ledger entries the hunk rewrites are both non-empty and
        // DISJOINT. It is a GATE rather than a note because the replay says it can afford to be:
        // `scripts/replay-message-vs-ledger.sh`, left in the tree to be re-run rather than quoted,
        // refuses 4 of the 511 ledger-touching commits reachable from HEAD -- none in the last 150
        // -- against T-1300's 191 in 274, which is why that reading warns and this one refuses.
        // Naming it here means deleting mode 4m goes red rather than quietly retiring the gate.
        "LEDGER-HUNK-UNCLAIMED",
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

    /// Every refusal `scripts/ledger-view.sh` makes (T-1331, registered under T-1343). The view is
    /// derived rather than maintained, which is what makes `LEDGER-VIEW-VACUOUS` the load-bearing
    /// one: a renamed ledger, an empty file or a `cd` into the wrong tree all produce a run that
    /// read nothing and prints a tidy, empty backlog — the [[T-1282]] / [[T-1291]] shape, and the
    /// most reassuring way for this particular tool to fail. `LEDGER-VIEW-NO-SUCH-ID` is the same
    /// question asked of one lookup rather than of the whole file.
    ///
    /// `LEDGER-VIEW-BAD-ID` and `LEDGER-VIEW-UNKNOWN-MODE` are the two the script had to be
    /// restructured for, and the reason is in `everyRefusalTheScriptsMakeIsStillInducedByTheirOwnSelftest`
    /// below rather than here: both were made inside the trailing `case "$mode"`, which in an `sh`
    /// script must sit BELOW the selftest it dispatches to, so the source-level reading counted
    /// them as named-by-the-selftest-only. The dispatch is a shell `main` function defined above the marker now,
    /// called from the file's last line — the refusals did not move, the code that makes them did.
    static let ledgerViewRefusals = [
        "LEDGER-VIEW-VACUOUS",
        "LEDGER-VIEW-NO-SUCH-ID",
        "LEDGER-VIEW-BAD-ID",
        "LEDGER-VIEW-UNKNOWN-MODE",
    ]

    /// Every check `scripts/codex-inbox.sh`'s selftest names (T-1334). This one is not a list of
    /// refusals because the script makes none: `report` is a report and always exits 0, so what
    /// there is to lose is a READING, and a reading that has quietly stopped discriminating looks
    /// exactly like one that never had to.
    ///
    /// That is not hypothetical here — it is the ticket this script was fixed under. T-1330's
    /// defect was a single high-water marker read as "everything below this is dealt with", and
    /// Codex answers whichever request it picks up rather than the lowest, so folding R63 while
    /// R55-R62 were open would have swallowed every later answer to those eight, permanently and
    /// **invisibly**: `still unanswered` is computed separately and went on listing them exactly
    /// as before. The selftest that came out of that fix was then run by nothing at all, which is
    /// why it is here — a guard whose own guard is a habit is the shape this whole file exists
    /// for, and this one had survived unnoticed until a reader happened to open the source.
    ///
    /// Check 2 is the one to keep if the list ever has to shrink: it is the non-vacuity half, and
    /// without it check 1 also passes against a script that has stopped filtering anything at all.
    static let codexInboxChecks = [
        "an answer below an out-of-order fold is still reported",
        "an already-folded answer is not reported",
        "fold records only the id it was given",
        "closing the gap advances the baseline",
        "closing the gap empties the named set",
        "folding does not change what is still unanswered",
        "the unanswered list is non-vacuous",
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
    /// Six of the eleven properties were listed here as unprovable, which is a poor ratio for a
    /// suite whose job is to notice rot. That was [[T-1161]], and its answer was **five**, every
    /// one of them for the same single reason. [[T-1381]], the same day, took it to **one**; the
    /// paragraphs below are in the order the readings were made, so read to the end before
    /// believing a count.
    ///
    /// **NAME THE MECHANISM, NEVER "THE SANDBOX".** A property is unprovable here only if a
    /// specific syscall or path refusal stops it; "awkward" is not one, and neither is a mood.
    /// Three refusals are in play, each measured by `CadenceTestHostSandboxCapabilityTests`:
    ///
    /// * **M1 — exec of a setuid binary is refused at `posix_spawn` (EPERM).** `/bin/ps` is `4555`,
    ///   so `waiter_alive`'s `ps -o command= -p $pid` can never run, for any pid.
    /// * **M2 — the process list is not readable at all.** `/usr/bin/pgrep` is not setuid, spawns
    ///   fine, and exits 3; measured in here on 2026-09-25 it says *"sysmon request failed with
    ///   error: sysmond service not found"*, and in-process `proc_listpids` returns ≤ 0 by the same
    ///   denial. `live_test_hosts` therefore refuses rather than counting, and every property whose
    ///   fixture needs a live host to be SEEN fails honestly.
    /// * **M3 — a file this process wrote cannot be exec'd**, even at 0755 and even as a
    ///   byte-identical copy of `/bin/ls`. This is the one that shuts the obvious escape: M1 and M2
    ///   are about the REAL probes, and the selftest already has knobs for substituting fake ones
    ///   (`CADENCE_LOCK_PS_CMD`, `CADENCE_LOCK_PGREP_CMD`, added by T-1152) — but a stub the fixture
    ///   writes into `$TMPDIR` cannot be launched from in here either, which is what mode 6's own
    ///   comment used to record about `blindpgrep`. M3 is still exactly this; what T-1381 found is
    ///   that it only ever shut the escape because the knobs named ONE WORD, and `/bin/zsh <stub>`
    ///   was never an exec of a file this process wrote.
    ///
    /// **`ordering` IS PROVABLE HERE, AND HAS BEEN SINCE T-1152 — measured 2026-09-25, `PASS
    /// ordering: w1 w2 w3 w4`.** It was tolerated on M1, and M1 stopped stranding it the moment
    /// T-1152 gave `waiter_alive` a third answer: a blind `ps` is now "cannot tell", `prune_queue`
    /// falls through to the ticket-age check instead of deleting every sibling's ticket, and the
    /// FIFO survives a host that cannot see a single process. The repair that made the toleration
    /// obsolete is the same commit the toleration was re-argued in, and nothing noticed for
    /// thirteen days — because nothing read `passed ∩ tolerating`. That is now a complaint
    /// (`staleTolerations`), which is how this line came to be written.
    ///
    /// **AND IT WAS PROVABLE HERE WHILE FAILING ON CI, WHICH IS [[T-1430]] — the asymmetry, not
    /// the red.** `ordering` was a duration comparison wearing an ordering assertion's clothes:
    /// mode 1's handoff took ~3.6s of wall clock against a 4s selftest lease, so past that margin
    /// the head of the queue reached the RECLAIM branch, and what happens there is decided by
    /// something the mode was never about — whether the caller can read the process list. From a
    /// shell the head reclaims the holder's lock and the mode prints PASS anyway; in here it cannot
    /// ask (M2), refuses, exits 2 and leaves the queue, so a waiter goes MISSING — CI's
    /// `got 'w1 w3 w4'`. Measured over the blind leg with the holder held N seconds: `w1 w2 w3 w4`
    /// at N=0 and N=1.5, `w4` at N=1 and N=2. NON-MONOTONE IN LOAD. The fixture registers a fake
    /// live test host for mode 1 now and holds PAST the lease deliberately, so every head defers
    /// and more load can only add deferrals; it asserts the order plus two counts — nobody
    /// reclaimed, and somebody did meet the expired lease. The argument is at the mode itself.
    ///
    /// So all five survivors of T-1161 were **M2 alone**, and the asymmetry looked like the useful
    /// part: this host can prove anything the lock decides from its own files, and nothing it
    /// decides by asking the kernel who else is running. That reading was right about the
    /// mechanism and wrong about the consequence — four of the five were not asking the kernel
    /// anything they could not have faked.
    ///
    /// **FOUR OF THE FIVE WERE RECLAIMED ON 2026-09-25, AND ONE SHELL CHANGE BOUGHT ALL FOUR
    /// ([[T-1381]]).** M3 shut the substitution escape only *as the knobs were spelled*:
    /// `"$PGREP_CMD" -f …` was one word, exec'd directly, so pointing it at a stub this process
    /// wrote pointed it at a file this process cannot launch. The host CAN run `/bin/zsh <script>`
    /// — that is how every selftest in this file runs at all — so the knobs are **command arrays**
    /// now (`PGREP_CMD=(/bin/zsh -f "$root/fakepgrep")`, splatted at the call site), and
    /// `no-reclaim`, `reclaim`, `dead-owner-reclaims-early` and `dead-owner-defers-to-live-host`
    /// are proved in here like everything else.
    ///
    /// **Nothing was given up to get them.** Those four fixtures already matched a FAKE pattern
    /// (`CADENCE_LOCK_PGREP`) against a FAKE process (`zsh $root/fakehost*`) on a developer Mac
    /// too — what they prove is the lock's DECISION given what the probe said, so a probe the
    /// fixture controls proves exactly as much. The stand-in reads the selftest's own process
    /// table (one file per fake host, named by pid) and answers liveness with `kill -0`, which is
    /// a signal to a process the fixture started rather than a read of the process list, and so
    /// works in here where M2 bites. Non-vacuity was measured rather than argued: with the
    /// registration of a fake host turned into a no-op, `no-reclaim` and
    /// `dead-owner-defers-to-live-host` both go red and say the lock reclaimed.
    ///
    /// `host-pattern-calibration` is the one survivor and is unprovable under any spelling of any
    /// knob: its whole subject is the REAL constant read by a REAL `pgrep` over REAL argv (T-1162),
    /// so substituting either would delete the property rather than move it. In here `pgrep` runs,
    /// is denied the process list and exits 3; `live_test_hosts` correctly refuses to answer, the
    /// fixture correctly calls that a failure, and the run outside the sandbox is where the
    /// calibration is read.
    ///
    /// **The list is pinned in both directions.** Until 2026-09-25 a tolerated property that
    /// started PASSING was accepted in silence, so this set could only grow — the rot the ticket
    /// names, in the field meant to record it. `complaintsForNamedRuns` now complains about
    /// `passed ∩ tolerating` too, so a name only stays here while the host really cannot prove it;
    /// this shrink from five to one had to land in the same change as the script, or the suite
    /// goes red on four stale tolerations.
    static let testHostLockPropertiesUnverifiableInThisSandbox: Set<String> = [
        "host-pattern-calibration",
    ]

    /// Every property `scripts/simulator-claim.sh`'s selftest names. T-749 ported
    /// `test-host-lock.sh`'s T-650 queue over wholesale rather than reinventing it, so it is pinned
    /// the same way: `ordering` is the fairness fix itself (a 16-minute starvation measured on the
    /// same race the FIFO closes), `killed-waiter` is the new queue's own prune-liveness check,
    /// exercised for real rather than read off the source.
    ///
    /// `cannot-tell-keeps-queue` is [[T-1382]]'s, and it is the port's missing half: a `ps` that
    /// RUNS and answers nothing must leave the queue alone. Same name as the lock's mode 6b,
    /// because it is the same property of the same queue.
    ///
    /// `cannot-tell-keeps-claim` is [[T-1384]]'s, and it is the same correction one function over.
    /// `live_simctl_for` was still the `pgrep -f … | wc -l | tr -d ' '` expression [[T-1152]]
    /// abolished in `test-host-lock.sh` — stderr discarded, exit status swallowed by the pipe, and
    /// empty stdin into `wc -l` printing a confident `0`. Zero is the PERMISSIVE answer at its one
    /// call site, which `rm -rf`s an expired claim, so a probe that could not read the process list
    /// used to free a device a sibling might be `simctl install`ing to. The mode is deliberately a
    /// discrimination rather than a refusal: a blind `pgrep` must not reclaim, an idle one still
    /// must, and one naming a live op still must not — a `live_simctl_for` hard-wired to "cannot
    /// tell" would pass a one-stub version of this while pinning the fleet behind any stale claim.
    static let simulatorClaimProperties = [
        "ordering",
        "killed-waiter",
        "cannot-tell-keeps-queue",
        "cannot-tell-keeps-claim",
    ]

    /// **Empty, as of [[T-1382]], and the emptiness is the finding.** `ordering` was tolerated
    /// here for one reason: `waiter_alive`'s setuid `ps`, which an App-Sandboxed caller is refused
    /// at `posix_spawn` (M1). That stopped stranding `test-host-lock.sh`'s `ordering` the moment
    /// T-1152 gave the function a third answer — but T-749 had ported this queue over wholesale
    /// and the repair never followed it, so for thirteen days two copies of one FIFO disagreed
    /// about what an unanswerable probe means. Measured together on 2026-09-25 (T-1161): the
    /// lock's `ordering` PASSED in this host and this one FAILED, and the difference was that one
    /// function. It now has the same three-way reading and the same `prune_queue` fall-through to
    /// the ticket-age check, so a blind `ps` is "cannot tell" and no live ticket is deleted.
    ///
    /// The honest size of what that fixed, since a guard oversold is a guard nobody re-reads:
    /// `ps` runs perfectly well from an ordinary agent shell, which is where this script is driven
    /// from, and the repository's rule is already never to drive a claim from inside a test. The
    /// reachable case was narrow. The divergence between two copies of one queue was not.
    static let simulatorClaimPropertiesUnverifiableInThisSandbox: Set<String> = []

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
    /// T-1516 adds a sixth, and like `VACUOUS-COUNT` it is a notice rather than a refusal — the
    /// refusal it decorates is still `WARNING-BASELINE`, whose exit code it now shares. What it
    /// says is the thing a reader cannot work out from the count: that some of the warnings in it
    /// carry **no `.swift:N:C:` prefix at all**, because they were raised inside a macro expansion
    /// and are attributed to the expansion buffer. `#expect` is in ~5,200 tests here and its
    /// diagnostics print as `macro expansion #expect:1:39: warning:`, so for a year the anchored
    /// counter could not see them, swept them into `tool notices:` under a banner reading "not a
    /// compiler diagnostic", and reported `warnings: 0` over fourteen real ones.
    ///
    /// It is pinned here for the same reason `VACUOUS-COUNT` is and with one addition: an agent
    /// who reads `warnings: 3` and greps the log for `\.swift.*warning:` finds nothing and
    /// concludes the banner is broken. Deleting the notice would leave the gate working and the
    /// gate's output unreadable, which is the shape of a fix that gets reverted. Section 6 of the
    /// selftest must still induce it over a fixture carrying a REAL `macro expansion …: warning:`
    /// line, and section 7 must still show that line exiting 9 — a name in a list proves neither.
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
    /// T-1741 adds a seventh, and like `PARTIAL-SCOPE` it is a notice rather than a refusal — for
    /// the same reason, which is why pinning it here is the only thing that keeps it.
    ///
    /// `INTERACTIVE-SKIPPED` is what the runner says when a test run skipped tests that the build
    /// produced. `CadenceUITests` gates every pointer-taking test behind a marker file in the
    /// runner's container, correctly: they take over the Mac's pointer and keyboard, one of them
    /// right-clicks a sidebar, and nothing unattended exists here to run them on — CI does not run
    /// that target at all (T-531: macOS UI testing needs a one-time authorisation granted at a GUI
    /// prompt with the user's password, and a hosted runner has nobody to grant it). So the gate
    /// stays and the **silence** was the defect: a default `-only-testing:CadenceUITests` run
    /// skipped four geometry guards — the only tests in this repository that can see where a
    /// popover actually lands — and printed `** TEST SUCCEEDED **`.
    ///
    /// That is the shape this repository keeps rediscovering: T-1516's warning counter reporting
    /// zero over fourteen real warnings, T-535's release gate that never compiled iOS, and
    /// T-1724's opt-in that no channel could set. The notice does not gate, deliberately — the
    /// ordinary correct daily invocation is the one that skips these — and a notice that does not
    /// gate is exactly the kind a later edit calls noise and deletes. Section 9a of the selftest
    /// must still induce it over a fixture log in XCTest's real skip shape, and must still show
    /// the run in which everything executed staying **silent**: a banner that printed on every run
    /// would be scrolled past within a week and would then be worth nothing.
    /// `SCREEN-LOCKED-MID-RUN` is the same shape one layer in, and T-1890 is the cost of not
    /// having had it. The locked-screen guard above it is a **preflight**: it reads the lock state
    /// once, before the build, and `requireAnUnlockedScreen()` reads it again in `setUpWithError`,
    /// at each test's start. Neither can see a screen that locks *during* a test body — and that
    /// case does not present as the activation failure T-563 measured. It presents as a launched
    /// app that reaches `.runningForeground` and then publishes an **empty accessibility tree**,
    /// so every element query times out and every failure is attributed to whichever line asked.
    /// Four runs across three suites were read as a product regression for a day on that reading.
    ///
    /// It does not gate, for the reason `INTERACTIVE-SKIPPED` does not: the run's reds are already
    /// red, and promoting an environmental cause over a genuine failure would hide the second
    /// behind the first. What was missing was anyone *saying* the reds are not about the code.
    ///
    /// **The report must print the lock TIME, not only the state, and section 9b pins that.**
    /// *Locked underneath a live run* and *already locked before the run started* are different
    /// diagnoses with different fixes, and `CGSSessionScreenLockedTime` is the only thing that
    /// separates them. 2026-10-01 is why the distinction is pinned rather than assumed: this Mac
    /// had been locked for **7h37m** before the run that reported it was ever launched, and a
    /// state-only report would have called that a mid-run lock and sent the next reader hunting a
    /// race that was not there.
    ///
    /// Section 9b must keep inducing it over a fixture session dictionary — the live condition
    /// needs the host's screen to lock out from under a run, so it cannot be induced — and must
    /// keep both CONTROLS: an ordinary unlocked run, and a run whose only lock predates it, both
    /// **silent**. The timestamp half is also what catches a screen locked and unlocked again
    /// inside one run, which leaves no state behind for a postflight boolean to find.
    static let buildRunnerRefusals = [
        "UNKNOWN-SUITE",
        "PARTIAL-SCOPE",
        // T-3080, and it is pinned SEPARATELY from `PARTIAL-SCOPE` above rather than folded into
        // it, because folding it in is precisely what would let it be deleted unnoticed: the
        // preflight half satisfies `body.contains("PARTIAL-SCOPE")` on its own, so a later edit
        // that removed the postflight call would leave every pin in this file green.
        //
        // The defect it answers is placement, not detection. T-1076's notice fires correctly and
        // it fires in the PREFLIGHT -- before the drift check, before a test-host queue that has
        // reached forty minutes, before the build -- and `== xcb result ==` said nothing about it.
        // The result block is what a run is actually read from, so on 2026-10-08 a scoped run over
        // `CadenceSidebarLayoutTests` ended `22 tests in 1 suite passed`, exit 0, with the THIRTEEN
        // tests that had just been written sitting unexecuted in the same file's other suite. In a
        // repository where every change is mutation-proved, that is the worst shape available: the
        // scoped run that proves the kill never ran the tests that would have failed.
        //
        // Like `PARTIAL-SCOPE` and `INTERACTIVE-SKIPPED` it REPORTS and does not gate, and that is
        // the half most likely to be "tightened" later. 39 files in this target declare more than
        // one suite and scoping to one of them is the ordinary daily invocation; a gate on it would
        // fail the ordinary case, and agents route around those -- taking the notice with them.
        // Section 14b induces it over a REAL `xcb.sh <id> test` on the production path, asserts it
        // inside the slice of the output that begins at `== xcb result`, keeps a non-vacuity check
        // that the preflight half still fires exactly once before the build, and keeps a
        // file-scoped-in-full CONTROL silent.
        "PARTIAL-SCOPE-UNRUN",
        "VACUOUS-COUNT",
        "WARNING-BASELINE",
        "NO-SUCH-SIMULATOR",
        "MACRO-EXPANSION-WARNING",
        "INTERACTIVE-SKIPPED",
        "SCREEN-LOCKED-MID-RUN",
        // T-2046: a DerivedData poisoned by a metadata-only touch of the entitlements file reads
        // as VACUOUS-COUNT plus "executed 0 tests" -- a wrong suite name -- unless this is named.
        // Section 8c induces it and keeps a red-without-it and an exit-0 control silent.
        "ENTITLEMENTS-POISONED-DD",
        // T-2070: an unanswered "Enable UI Automation" prompt wedges the UNIT suite too, and the
        // only thing an agent can read from inside one is a run that died at ~445s. The name is
        // pinned here because the probe behind it is the part that rots silently: the predicate
        // this ticket shipped counted `/usr/bin/log`'s own invocation records, so it read HEALTHY
        // over a standing prompt, and a refusal that has quietly stopped firing looks exactly
        // like a host nobody has wedged lately. Section 8e induces it, keeps a granted-request
        // CONTROL silent, and pins both the noise filter and the scoping of the predicate.
        "AUTOMATION-PROMPT-OUTSTANDING",
        // T-2070's other half, and it is pinned because it is the half a reader would call
        // redundant and delete. An unmatched automation request is NOT by itself a standing
        // prompt: an unattended UI run raises the owner's prompt, times out after ~70s and leaves
        // exactly that line behind over a host that then runs unit suites fine. The refusal needs
        // a second reading -- a test session that connected and never got transport -- and this
        // NOTE is what the other case produces. Deleting it does not break the refusal; it
        // collapses "a prompt is standing" into "someone ran a UI test earlier", which is the
        // false positive that would refuse every macOS run on this Mac for six hours.
        "AUTOMATION-PROMPT-UNMATCHED",
        // T-2071 / T-1920: the seven verdicts of `xcb.sh run-state`, and they are pinned as a SET
        // because the instrument's whole value is that they are distinguishable. Deleting any one
        // of them does not break the others -- it quietly collapses two states into one, which is
        // the defect itself: a queued run, a slow run and a wedged run looked identical from
        // outside, and agents repeatedly read a queue as a death and started a second run on top
        // of it. STALLED is the one most likely to be called noise and removed, and it is the one
        // that keeps the tool honest: it is the verdict for a silent run that does NOT carry
        // T-2067's signature, and folding it into WEDGED would make the tool assert a hung host
        // over every slow test body. Section 13 induces each of them, and induces QUEUED, RUNNING,
        // ABANDONED and WEDGED against REAL `xcb.sh <id> test` runs on the production path rather
        // than against a fixture that merely contains the word.
        "run-state: QUEUED",
        "run-state: RUNNING",
        "run-state: WEDGED",
        "run-state: STALLED",
        "run-state: FINISHED",
        "run-state: ABANDONED",
        "run-state: NO-LOG",
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

    /// T-1920. The three verdicts of `scripts/heartbeat-progress.sh`, the three marks it reads, and
    /// — unusually for this file — **a sentence it must keep printing.**
    ///
    /// T-1920 nominated a tell for a hung heartbeat, refuted it, replaced it and refuted the
    /// replacement: three readings, all wrong the same way, all inferring a process's liveness from
    /// a run list of two timestamps and a status string, in which a usage-limit wait and a hang are
    /// the same row. This script answers a different question on purpose — did any work LAND —
    /// and reads it from three marks on this Mac's disk that cannot move unless it did: `git` HEAD,
    /// the `xcb.sh last-green` record, and a growing xcb log.
    ///
    /// `NO-MARKS` is pinned beside `SILENT` because collapsing them is the obvious future edit and
    /// is wrong in the expensive direction: a machine that has never run the heartbeat has nothing
    /// that could have advanced, and reporting that as "no progress" is the same mistake as reading
    /// a queue as a death.
    ///
    /// **`NOT A LIVENESS VERDICT` is in this list as a string, which is deliberate.** Every other
    /// name here is a state; this one is a non-claim, and it is the only part of the instrument
    /// that keeps the fourth wrong reading from being written on top of the third. A SILENT verdict
    /// that quietly starts saying "hung" is exactly the tool T-1920 says not to build, and section
    /// 3 of the selftest also checks the output for the words *hung* and *wedged* and fails on
    /// either.
    static let heartbeatProgressVerdicts = [
        "heartbeat-progress: ADVANCING",
        "heartbeat-progress: SILENT",
        "heartbeat-progress: NO-MARKS",
        "NOT A LIVENESS VERDICT",
        "HEAD",
        "LAST-GREEN",
        "XCB-LOG",
    ]

    /// T-1176. The three verdicts of `scripts/group-defaults-probe.sh`, its one refusal, and the
    /// two non-claims it must keep printing.
    ///
    /// The verdicts are the easy half. The other names are what keep this instrument from quietly
    /// becoming a weaker one:
    ///
    /// - `REFUSING-TO-WRITE` is the probe declining to put its own record inside a group container,
    ///   a `Cadence Store Backups` folder or the Recovery store. A probe that writes what it
    ///   measures is not a probe, and the owner's real data is what is on the other side of it.
    /// - `NOT AN ATTRIBUTION` is on every verdict. `MOVED` says this file differs between two
    ///   readings and nothing more: cfprefsd, the owner's own `Cadence.app` and an agent's launched
    ///   build all write this suite, and the file records none of them. T-1176 asks what an *agent
    ///   launch* writes, and no comparison of two file states answers that on its own.
    /// - `ATTRIBUTION WITHHELD` is that non-claim made concrete. A sample taken while the owner's
    ///   copy was up — or while whether it was up could not be read — cannot be the measurement,
    ///   and says so in the verdict instead of passing for one.
    static let groupDefaultsProbeVerdicts = [
        "group-defaults: UNMOVED",
        "group-defaults: MOVED",
        "group-defaults: RE-ENCODED",
        "group-defaults: NO-SAMPLE",
        "REFUSING-TO-WRITE",
        "NOT AN ATTRIBUTION",
        "ATTRIBUTION WITHHELD",
        "FLOAT32-TRUNCATION",
        "owner-app=unknown",
        "CREATED",
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

    /// T-1920. Runs entirely against throwaway fixtures under `$TMPDIR` — a throwaway git
    /// repository, a fabricated `last-green` record and a fabricated xcb log — and **substitutes
    /// the clock** rather than waiting out a window, so a reading about 26 hours of silence costs
    /// no wall clock and says nothing about this checkout.
    ///
    /// The checks worth knowing about are section 4's pair. Each of the three marks has to be able
    /// to produce `ADVANCING` **on its own, over two stale companions** — a verdict that ORs three
    /// inputs is the shape where one input silently stops being read and the other two keep the
    /// answer looking right. Section 7 is the other one: the `last-green` record's filename is
    /// compared as text against `scripts/xcb.sh`'s own spelling, because a hash that drifts by one
    /// character reads a file that is never there and this tool would report `NO-MARKS` forever
    /// while the heartbeat worked perfectly.
    @Test func theHeartbeatProgressReadingsOwnChecksStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/heartbeat-progress.sh")
        let complaints = run.complaints(requiring: Self.heartbeatProgressVerdicts)
        #expect(complaints.isEmpty, "./scripts/heartbeat-progress.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-1176. Runs entirely against throwaway XML plists under `$TMPDIR`, and **must stay that
    /// way**: what `scripts/group-defaults-probe.sh` is built to read is the owner's real app-group
    /// suite under `~/Library/Group Containers/`, and nothing in this target may go near it. That
    /// is the whole reason the reading is a script a person runs with the owner's knowledge and
    /// this target holds only its selftest — a test that read that path would be the exact mistake
    /// T-1176 is about.
    ///
    /// `RE-ENCODED` is the verdict running the instrument on live data bought. On 2026-10-09 the
    /// owner's own suite went sha256 `81c4a4ac…` → `9eae14a7…` at **135 bytes both times with all
    /// four keys identical to the character**: cfprefsd re-encodes a binary plist when it likes, so
    /// a sha difference on its own does not mean anything wrote those keys. Reported as `MOVED`,
    /// that is a false positive in the expensive direction — on the single reading the owner's
    /// window is being spent to get. §2b requires the two to be told apart in both directions.
    ///
    /// Four of the checks it requires are controls rather than assertions.
    ///
    /// **§2 is the cfprefsd trap.** Two byte-identical fixtures whose mtimes are thirty years apart
    /// must compare `UNMOVED`, and the same pair with one value changed and *identical* mtimes must
    /// compare `MOVED`. Measured twice on the real file — 2026-10-06 and again 2026-10-09 — its
    /// mtime moves while its 135 bytes and its sha256 do not, because cfprefsd rewrites it without
    /// changing its content. A verdict taken off mtimes passes neither direction here.
    ///
    /// **§4 is `FLOAT32-TRUNCATION`.** `PlistBuddy -c Print` renders that file's
    /// `cadence.widgets.lastReloadAt` as `1791260160.000000` where `plutil -p` renders the same
    /// bytes as `1791260184.86859`: PlistBuddy prints the stored double through a single-precision
    /// float, 24.87 seconds early — so T-1176's own recorded baseline figure is 25 seconds early,
    /// and a small write to that key would be invisible to it. The fixture's value is one no
    /// float32 can reproduce, so swapping the reader back reddens here rather than in six months'
    /// prose.
    ///
    /// **§6 is both directions of `REFUSING-TO-WRITE`, and it is here because the one-directional
    /// form was already wrong once.** The first spelling of that refusal named
    /// `com.haoranwei.Cadence/Data` whole — correct everywhere except the place this test runs,
    /// since the App-Sandboxed host's own `$TMPDIR` is
    /// `~/Library/Containers/com.haoranwei.Cadence/Data/tmp/`. It refused the selftest's own
    /// workspace and failed 9 of its own checks (measured 2026-10-09) while appearing to protect
    /// something. So §6 now requires a record in the container's `Library` to be refused *and* one
    /// in the same container's `tmp` to be written: a guard that refuses everything protects
    /// nothing, and only the second half tells the two apart.
    ///
    /// `owner-app=unknown` is pinned beside the verdicts for the T-1152 reason: inside this host
    /// `pgrep` runs but is denied the process list and exits 3, and reading that as "the owner's app
    /// was not running" is exactly the sentence that would let a worthless sample pass for the
    /// measurement.
    @Test func theGroupDefaultsProbesOwnChecksStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/group-defaults-probe.sh")
        let complaints = run.complaints(requiring: Self.groupDefaultsProbeVerdicts)
        #expect(complaints.isEmpty, "./scripts/group-defaults-probe.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
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
        // `#!/bin/sh`, so `/bin/sh` (T-1343). It had been run under zsh and passed, which is luck
        // and not evidence: it writes its fixtures with `printf` rather than here-documents, and
        // that is the only reason the zsh temp-file trap that hid `ledger-view.sh`'s selftest for a
        // whole red run never touched this one. A landmine left armed because it has not gone off.
        let run = try CadenceSelftestRun.of("scripts/ledger-lag-check.sh", interpreter: "/bin/sh")
        let complaints = run.complaints(requiring: Self.ledgerLagRefusals)
        #expect(complaints.isEmpty, "./scripts/ledger-lag-check.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-1331, registered under T-1343. Two markdown fixtures under `$TMPDIR` and nothing else: no
    /// git, no build, no network, and it says nothing about — and does nothing to — the real
    /// `docs/TODO.md` a sibling may be editing. Under a second.
    ///
    /// **Run under `/bin/sh`, not `/bin/zsh`, and this one is not a style point either.** The first
    /// attempt at this registration used the default interpreter and went red with 33 of the 41
    /// checks reporting `LEDGER-VIEW-VACUOUS` against fixture paths that existed — which reads
    /// exactly like an App Sandbox write failure and is not one. The selftest lays its fixtures
    /// down with here-documents; **zsh** writes those to `$TMPPREFIX`, which it sets itself at
    /// startup to `/tmp/zsh` and never to `$TMPDIR`, and this host cannot write `/tmp`. Each
    /// fixture was therefore created and left EMPTY, so the tool correctly refused a ledger of zero
    /// entries. Reproduced outside the sandbox by pointing `TMPPREFIX` at a path that does not
    /// exist: 8 passed / 33 failed under `zsh -f`, 41 / 0 under `sh`, byte-identical script.
    /// `ledger-lag-check.sh` above is `#!/bin/sh` too and survives the wrong shell only because it
    /// writes its fixtures with `printf` — luck, not design, which is why the shebang is the rule.
    /// The script also pins `TMPPREFIX` into `$TMPDIR` itself now, so the next caller to hand it to
    /// zsh gets fixtures rather than silence.
    @Test func theLedgerViewsOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/ledger-view.sh", interpreter: "/bin/sh")
        let complaints = run.complaints(requiring: Self.ledgerViewRefusals)
        #expect(complaints.isEmpty, "./scripts/ledger-view.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// T-1334. Runs entirely inside a throwaway directory under `$TMPDIR`: it writes fixture
    /// queue documents, reports over them and folds them, so it says nothing about — and does
    /// nothing to — the real `docs/CODEX_REQUESTS.md`, which a sibling may be editing. Well under
    /// a second, and it needs neither `git` nor `python3`, so it is the one member of this family
    /// that cannot be defeated by the App Sandbox.
    ///
    /// **Run under `/bin/bash`, not `/bin/zsh`.** This script's shebang is the odd one out, and
    /// the difference is not cosmetic: `is_folded` and `cmd_fold` both iterate `$also` unquoted,
    /// which zsh passes as a single word. Under the wrong shell the fold set collapses to one
    /// element and the selftest goes red for a reason that has nothing to do with the script.
    @Test func theCodexInboxGuardsOwnChecksStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/codex-inbox.sh", interpreter: "/bin/bash")
        let complaints = run.complaints(requiring: Self.codexInboxChecks)
        #expect(complaints.isEmpty, "./scripts/codex-inbox.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// Every check `scripts/codex-land.sh`'s selftest names (T-1426). It is `#!/bin/sh` — not bash
    /// like `codex-inbox.sh`, not zsh like the `agent-commit.sh` family — so it is run under
    /// `/bin/sh` here, and `bash -n` on it proves nothing about the shell that will execute it.
    ///
    /// The last two are the ones to keep if the list ever has to shrink, and neither is decorative.
    ///
    /// "an empty lease refuses rather than allowing all" is the fail-open half: a lease block that
    /// a parser change stops finding is indistinguishable, at the call site, from a branch that
    /// touched nothing it should not have.
    ///
    /// "a NEW file under a glob that also matches an existing file passes" is T-1428, and it is
    /// here because the guard was wrong in the one direction nobody checks. The lease is a list of
    /// globs and `for pat in $lease` performed PATHNAME EXPANSION on it: with three
    /// `iOSTaskCollection*.swift` files on disk the lease line stopped being a pattern and became
    /// those three literal names. Every path that already existed was inside its own expansion and
    /// passed, so the guard looked perfect — and it refused only a **new** file, which is precisely
    /// what a lease is for. It fired on Codex's first branch and read as Codex breaking the
    /// protocol. The fixture has to review from `main` for this to reproduce: with the branch
    /// checked out the new file is on disk too, the glob expands to include it, and the check goes
    /// green against the bug. The first draft of it did exactly that.
    static let codexLandChecks = [
        "a lease with patterns is readable",
        "an empty branch is VACUOUS, not clean",
        // T-2051: the refusal's NUMBER, not only its status — `grep -c '^'` on an empty diff
        // said 1 changed file for a branch that changed none.
        "an empty branch's refusal counts 0 changed files, not 1",
        "a branch whose commits cancel out is VACUOUS too",
        "...and its refusal counts 2 commits and 0 changed files",
        "editing the ledger is refused",
        "a path outside the lease is refused",
        "code with no inbox entry is refused",
        "an id the ledger already has is refused",
        // T-1800, and it is a *wording* check on purpose. The clash refusal fired exactly as
        // designed on T-3003 and T-3004, where the coordinator had pre-filed the stub and assigned
        // the branch to it — so exit 3 was the expected state of a branch that was ready to land —
        // and both times Codex halted and asked what to do, because the message named the hazard
        // and no way out. Nothing about the check changed; the refusal now names the two supported
        // resolutions, and a refusal's words are the only documentation this script has.
        "...and the clash refusal names the stub-replace landing path",
        "a branch inside the lease with an entry passes",
        "a NEW file under a glob that also matches an existing file passes",
        "an inbox id the coordinator already folded is not a clash",
        // T-1930, and the first two of these are a pair that must stay a pair. `review` reported a
        // branch whose every file was already in `main` with the SAME exit code and the SAME words
        // it gives a genuinely blocked one: 31 files, three `CODEX-INBOX-ID-CLASH` refusals, exit 3
        // — read plainly, a blocked branch with 31 files of pending work, when the truth was the
        // opposite and the ids clashed BECAUSE the work had landed. A fixture holding only the
        // spent branch passes with the whole per-file reading deleted, because the clash fires on
        // it either way; the pending control beside it, and the assertion that the two reports
        // DIFFER, is what makes any of this evidence.
        "a branch whose every file is already in main is SPENT, not blocked",
        "a genuinely pending branch is NOT reported as landed",
        "the spent and the pending branch do not get the same report",
        "the spent branch's report names the state",
        "the pending branch's report does NOT",
        "every named file carries its own verdict against main",
        // Two of the 31 measured files were this shape: the work landed and `main` then moved PAST
        // it, so the bytes differ while the branch contributes nothing. A pure two-dot byte
        // comparison calls that pending, which would leave the branch reading as blocked over a
        // file nobody is missing.
        "a file main has moved PAST still counts as landed, not as pending",
        // The shape the live branch was actually in once main had advanced: every CODE file landed
        // and the one path left was the branch's own inbox entries, which the coordinator never
        // published (T-1800). It is still a refusal — those entries are real, unlanded work — but
        // it must not read as 31 files of pending code.
        "a branch whose only unlanded path is the inbox still refuses on the clash",
        "...and SAYS the code landed, instead of reading as pending work",
        "an empty lease refuses rather than allowing all",
    ]

    @Test func theCodexLandGuardsOwnChecksStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/codex-land.sh", interpreter: "/bin/sh")
        let complaints = run.complaints(requiring: Self.codexLandChecks)
        #expect(complaints.isEmpty, "./scripts/codex-land.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
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
    /// `host-pattern-calibration` is TOLERATED, not required -- **one of eleven since T-1381**,
    /// where it was five: the probe knobs became command arrays, the four properties that only
    /// needed a substituted probe became provable in here, and the tolerated list had to shrink in
    /// the same change (see the `testHostLockPropertiesUnverifiableInThisSandbox` doc). Tolerating
    /// a named failure is not the same as ignoring it: this still fails loudly if it PASSES
    /// unexpectedly (the limit lifted, this list is stale) or if anything NOT on the tolerated
    /// list fails.
    ///
    /// That second sentence was **false for eighteen days** and is true as of T-1161: nothing read
    /// `passed ∩ tolerating`, so "it fails loudly if either PASSES" described a check that did not
    /// exist. Left in place, now that it is the behaviour -- and kept in mind as the exact shape
    /// T-1153 is about, since it is a claim about the test environment that survived on being
    /// written down next to the thing it described.
    @Test func theTestHostLocksOwnGuardsStillFire() throws {
        let run = try CadenceSelftestRun.of("scripts/test-host-lock.sh")
        let complaints = run.complaintsForNamedRuns(
            requiring: Self.testHostLockProperties,
            tolerating: Self.testHostLockPropertiesUnverifiableInThisSandbox
        )
        #expect(complaints.isEmpty, "./scripts/test-host-lock.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// **T-1641: a guard tolerated everywhere is a guard nowhere, and this is what stops it
    /// becoming one again.**
    ///
    /// `tolerating:` above is honest about one thing and silent about another. It is honest that
    /// this HOST cannot prove `host-pattern-calibration` — the property's whole subject is the real
    /// `HOST_PATTERN` read by a real `pgrep` over real argv (T-1162), and the App-Sandboxed test
    /// host is denied the process list on this Mac and on CI alike. It was silent about the
    /// consequence: the comment on the tolerated set said *"the run outside the sandbox is where
    /// the calibration is read"* and **nothing outside the sandbox ran it**, on any schedule, on
    /// any machine. The property with the worst failure history in this family — T-1162 is where
    /// the shipped pattern matched no test run this repository makes, so the lock read
    /// `live test hosts: 0` on a busy box — was the one property nobody ever ran.
    ///
    /// So tolerating a name now *costs* something: it obliges `ci.yml` to run that script's
    /// selftest as a plain, unsandboxed shell step, where `pgrep` works. The obligation is
    /// conditional on the tolerated set being non-empty, which is the right polarity — emptying
    /// the set (T-1381 shrank it from five to one) releases the obligation, and adding to it
    /// creates one.
    ///
    /// **The step must be a step.** This reads `ci.yml`'s `run:` blocks through
    /// `CadenceBuildInvocationHygieneTests.shellText`, never the file's raw text, because the job
    /// that runs the selftest also has a thirty-line comment ABOUT the selftest directly above it,
    /// and a raw `contains` would be satisfied by the prose alone — a test that passes on a
    /// workflow whose step was deleted and whose comment was left behind. That shape is exactly
    /// what this suite exists to refuse.
    ///
    /// Measured on this Mac 2026-09-30, outside the sandbox: 65 seconds wall clock, 11 of 11
    /// properties `PASS`, `host-pattern-calibration` among them.
    ///
    /// **Unverified until the owner's next push.** No agent here can watch a `.github/` change
    /// run, so what this pins is that the step is *written* and that the tolerated set is what
    /// obliges it. Whether a hosted runner's `pgrep`, `exec -a` and `pkill -P` behave as this
    /// Mac's do is a claim the first real Actions run either confirms or reddens — and it reddens
    /// the job, deliberately, rather than being advisory.
    @Test func everyPropertyToleratedInThisSandboxIsProvedByAnUnsandboxedCIStep() throws {
        let steps = try CadenceBuildInvocationHygieneTests.shellText(at: ".github/workflows/ci.yml")

        // Non-vacuity, and the trap named above: the workflow's prose must NOT be what satisfies
        // this. If the extractor ever starts handing back comments, this fails first.
        #expect(
            !steps.contains("proves eleven properties"),
            "ci.yml's job comments leaked into its run: steps, so every check below could pass on prose"
        )
        #expect(steps.contains("xcb.sh"), "no run: steps were extracted from ci.yml at all")

        let tolerated: [(script: String, names: Set<String>)] = [
            ("scripts/test-host-lock.sh", Self.testHostLockPropertiesUnverifiableInThisSandbox),
            ("scripts/simulator-claim.sh", Self.simulatorClaimPropertiesUnverifiableInThisSandbox),
        ]
        var missing: [String] = []
        for entry in tolerated where !entry.names.isEmpty {
            let runsIt = steps.split(separator: "\n").contains {
                $0.contains(entry.script) && $0.contains("selftest")
            }
            if !runsIt {
                missing.append("\(entry.script) tolerates \(entry.names.sorted()) in this sandbox and no ci.yml step runs its selftest")
            }
        }
        #expect(missing.isEmpty, "\(missing.joined(separator: "; ")) (T-1641)")

        // The obligation is only worth anything while something is tolerated, so say so: an empty
        // set here would make the loop above vacuous, and that is a fact about the day it happens
        // rather than a silent pass.
        #expect(
            Self.testHostLockPropertiesUnverifiableInThisSandbox.contains("host-pattern-calibration"),
            "the lock's tolerated set no longer names T-1162's property; re-read whether the CI step is still the right remedy"
        )

        // **A table with one eligible row cannot tell "the rule fired" from "there was nothing
        // else to choose".** `simulator-claim.sh` is the second row and it is the control: since
        // T-1382 nothing of its is tolerated, so it is NOT obliged — and `ci.yml` indeed runs no
        // selftest for it. If the loop above had been written over every row rather than over the
        // tolerated ones, it would be red today on this very script rather than passing for the
        // wrong reason, and these two expectations are what make that legible instead of lucky.
        #expect(
            Self.simulatorClaimPropertiesUnverifiableInThisSandbox.isEmpty,
            "simulator-claim.sh now tolerates \(Self.simulatorClaimPropertiesUnverifiableInThisSandbox.sorted()), so it owes ci.yml a step too and this control has become a second requirement"
        )
        #expect(
            !steps.split(separator: "\n").contains(where: { $0.contains("scripts/simulator-claim.sh") && $0.contains("selftest") }),
            "ci.yml runs simulator-claim.sh's selftest, so the check above can no longer tell an obliged script from an unobliged one"
        )

        // And it must FAIL the job. An advisory step is one more green line proving nothing, which
        // is the failure shape the tolerated property itself guards against.
        let workflow = try CadenceSourceScan.sourceFile(".github/workflows/ci.yml")
        #expect(
            !workflow.contains("continue-on-error"),
            "a ci.yml step is advisory; a selftest that cannot redden its job proves nothing (T-1641)"
        )
    }

    /// T-1640's classifier, run for real. Pure shell over fixtures it writes itself — no `gh`, no
    /// network, no build — so unlike the lock's selftest this one needs nothing the sandbox
    /// withholds and nothing is tolerated.
    ///
    /// The named modes are the discriminations, not the outputs. `cancelled-is-not-never-pushed`
    /// is the ticket; `docs-only-push-is-not-a-missing-run` is the state the ticket's own four-way
    /// reading loses, and the one that would have made the instrument cry wolf on the majority of
    /// this repository's commits (`ci.yml` counts 308 of the 430 that ever touched `docs/TODO.md`
    /// as compiling nothing); `eligible-push-with-no-run-is-reported` is its non-vacuity, because
    /// a classifier answering CI-SKIPPED to everything passes the other two.
    @Test func theCIRunCoverageReaderTellsADroppedRunFromASkippedOne() throws {
        let run = try CadenceSelftestRun.of("scripts/ci-run-coverage.sh")
        let complaints = run.complaints(requiring: Self.ciRunCoverageProperties)
        #expect(complaints.isEmpty, "./scripts/ci-run-coverage.sh selftest: \(complaints.joined(separator: "; "))\n[\(CadenceSelftestRun.probe())]\n\(run.output)")
    }

    /// Mirrors the mode names `scripts/ci-run-coverage.sh selftest` prints, so deleting a mode
    /// from the script fails here rather than shrinking the selftest in silence.
    static let ciRunCoverageProperties = [
        "cancelled-is-not-never-pushed",
        "docs-only-push-is-not-a-missing-run",
        "eligible-push-with-no-run-is-reported",
        "a-completed-run-outranks-a-cancelled-one",
        "in-flight-is-not-completed",
        "the-ignore-list-is-read-from-the-workflow",
        // T-1950. The mode the one-candidate caution is about: a check that "every code commit has
        // its own run" passes vacuously on a history where every push is single-commit, so the
        // mode pins a grouped push AND a single-commit push and asserts the two readings DIFFER.
        "a-code-commit-riding-behind-a-push-is-unattributed",
        // T-2044. An empty rev-list split into one empty element read "1 commit(s)" for a floor at
        // HEAD; the mode builds a fixture repository, so it also proves git spawns in here (T-2045).
        "report-counts-the-commits-after-the-floor",
        // T-1993. The caller T-1950's guard was missing: the push event itself. The mode walks a
        // real `<before>..<after>` range out of a fixture repository rather than reading a
        // hand-written manifest, because the walk is the part `.github/workflows/ci.yml`'s
        // `push-attribution` job adds and therefore the part that can be wrong.
        "the-push-event-is-the-only-caller-that-can-see-the-group",
    ]

    /// T-749. Runs against a throwaway claims root and a fake `simctl` (`CADENCE_SIM_CLAIMS_DIR` /
    /// `CADENCE_SIMCTL`), so this is safe alongside sibling agents holding real device claims —
    /// and MORE safely than before T-1382, which found the selftest process's own `$CLAIMS` and
    /// `$QUEUE` still naming the real store, fixed at startup from an environment that did not yet
    /// carry the overrides. Every mode reached the sandbox through a `$SELF` subprocess, so
    /// nothing noticed until a mode read the queue in-process; they are repointed before any mode
    /// runs now, as `test-host-lock.sh`'s selftest already did (T-1343).
    ///
    /// **Nothing is tolerated here as of T-1382** — all four properties are required. `ordering`
    /// was the one exception, on `waiter_alive`'s setuid `ps` (T-959), until that function got the
    /// three-way reading the lock has had since T-1152. T-1384's `cannot-tell-keeps-claim` needs no
    /// toleration either, for the same reason and by the same mechanism: every `pgrep` it consults
    /// is a `/bin/zsh <stub>` the fixture wrote, so the property never asks the host a question the
    /// host cannot answer.
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

        // T-1161. A tolerated property that PASSES falsifies the claim that put it on the list, so
        // it is a complaint in its own right -- and it is the ONLY way the tolerated list can ever
        // shrink. Until 2026-09-25 this ran green, while the test that passes `tolerating:` claimed
        // in its own doc comment that it "fails loudly if either PASSES unexpectedly".
        let toleratedPropertyStartedPassing = CadenceSelftestRun(
            status: 0,
            output: "PASS ordering: w1 w2 w3 w4\nPASS killed-waiter: ok\nselftest: 0 failure(s)\n"
        )
        let stale = toleratedPropertyStartedPassing.complaintsForNamedRuns(
            requiring: ["ordering", "killed-waiter"], tolerating: ["ordering"]
        )
        #expect(!stale.isEmpty,
                "a tolerated property that passed must be complained about: the toleration is stale")
        #expect(stale.contains { $0.contains("ordering") },
                "the complaint must NAME the property whose toleration went stale, not just object")
        // ...and the same output with nothing tolerated is the ordinary green run, so the new
        // reading cannot be a blanket objection to a PASS.
        #expect(toleratedPropertyStartedPassing.complaintsForNamedRuns(requiring: ["ordering", "killed-waiter"]).isEmpty,
                "an all-passing selftest with no tolerations must still read as green")

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
    ///
    /// **What "the body" is, and the trap it set for `ledger-view.sh` (T-1343).** The split is the
    /// FIRST `# --- selftest`, so "body" means everything a reader would call production code — and
    /// every guard here is a shell script, which cannot dispatch to a function it has not read yet.
    /// The trailing `case "$mode"` therefore sits BELOW the marker in **all ten** of them: the
    /// convention is that the selftest section comes last, *not* that the dispatch does, and the
    /// two scripts checked before believing otherwise both confirm it. The others escape by
    /// accident — their dispatches only route, and the refusals are made in functions defined
    /// above. `ledger-view.sh` refused `LEDGER-VIEW-BAD-ID` and `LEDGER-VIEW-UNKNOWN-MODE` inline
    /// in the dispatch, so this reading counted both as named-by-the-selftest-only and proved
    /// nothing about them. The repair is on that script — the dispatch is a shell `main` function defined above
    /// the marker and called from the file's last line — and deliberately not here: relaxing the
    /// split is the whole property, since a refusal that exists only below it is one the selftest
    /// can name without the script ever making it.
    @Test func everyRefusalTheScriptsMakeIsStillInducedByTheirOwnSelftest() throws {
        for (script, refusals) in [
            ("scripts/mutate.sh", Self.mutationRunnerRefusals),
            ("scripts/agent-commit.sh", Self.commitHelperRefusals),
            ("scripts/agent-scratch.sh", Self.scratchGuardRefusals),
            ("scripts/worktree-drift.sh", Self.worktreeDriftRefusals),
            ("scripts/ledger-lag-check.sh", Self.ledgerLagRefusals),
            ("scripts/ledger-view.sh", Self.ledgerViewRefusals),
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

    /// T-1933, and T-1153's rule is why it is here: a claim about what the test host can do names
    /// the test that holds it, and this is a claim about two of them at once.
    ///
    /// **One fact, two decisions, and each had grown its own proxy for it.** `xcb.sh`'s
    /// locked-screen guard (T-563) refused on `[[ "${args[*]}" == *CadenceUITests* ]]` — the target
    /// name anywhere in the argument list — and the test-host lease (T-236) was taken for the
    /// `test` **action** whatever that action selected. Both proxies are wrong in the same one
    /// direction and were measured wrong on the same day: `-only-testing:CadenceUITests/`
    /// `CadenceOverdrawVerdictTests` was refused with exit 5 on a locked Mac, and on an unlocked
    /// one the same selection queued **800 seconds** behind two siblings for a container it never
    /// opens. That suite launches nothing, takes no pointer and reads no screen. So the two now
    /// call one function on one parsed selection, and the check below is that they still both do —
    /// a later edit repairing one and leaving the other is precisely how this started.
    ///
    /// **Source-level, like the `-only-testing:` pin above and for the same reason.** Shelling out
    /// reaches a selftest whose live halves degrade to a printed `skip` inside an App Sandbox
    /// (T-719), so it would assert progressively less while looking like it asserted more.
    ///
    /// **The stale sentence is pinned as an absence, which is unusual and is the point.** The
    /// guard's own comment used to say that with `CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN=1` *"the tests
    /// skip instead"*. That is false for `CadenceOverdrawVerdictTests`, which carries no skip and
    /// would run — the sentence was true of the suites the guard was written against and was never
    /// re-read when the target grew one that launches nothing. A comment that confidently describes
    /// behaviour the code no longer has is the same instrument-is-the-defect shape as the guard it
    /// sat on, and restoring it would restore the reading that stopped anyone looking.
    @Test func theLockedScreenGuardAndTheTestHostLeaseAskOneQuestionAboutTheSelection() throws {
        let source = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent("scripts/xcb.sh"),
            encoding: .utf8
        )
        guard let split = source.range(of: "\n# --- selftest") else {
            Issue.record("scripts/xcb.sh has no `# --- selftest` section to read")
            return
        }
        // The selftest is ONE function, and it ends at the first column-0 `}` after the marker.
        // Slicing to end-of-file instead — the shape the sweeps above use — is vacuous HERE, and
        // that was this test's second defect: everything below the function is the dispatch and
        // the preflight, where `check-ui-selection` prints `SCREEN-FREE` and `LAUNCHES-AN-APP` and
        // three comments name `CadenceOverdrawVerdictTests`. With section 10 deleted outright, all
        // three expectations at the bottom of this test stayed green.
        let afterMarker = source[split.lowerBound...]
        let selftest = String(afterMarker[..<(afterMarker.range(of: "\n}\n")?.upperBound ?? afterMarker.endIndex)])
        #expect(selftest.contains("SELFTEST PASSED"),
                "the slice taken as xcb.sh's selftest does not reach the end of the selftest function")
        // NOT `source[..<split]`, and the distinction cost this test one red run. For `xcb.sh` the
        // `# --- selftest` marker sits at a third of the way down the file and the whole preflight
        // — every guard that reads the command line, including both of this ticket's — is BELOW it.
        // The convention the sweep above relies on is that the selftest section comes last, not
        // that the dispatch does; `xcb.sh` escapes it only because its refusal FUNCTIONS are
        // defined above the marker. The two decisions this test is about are made inline in the
        // preflight, so they are read from the whole file.
        let body = source

        // The reading itself, and the floor under it: a suite is screen-free because its SOURCE
        // never names `XCUIApplication`, not because a list in this script says so. A list is a
        // second copy of a fact and T-1382 is thirteen days of what two copies of one rule do.
        #expect(body.contains("ui_suite_launches_an_app"),
                "xcb.sh no longer reads whether a named suite can launch an app")
        // The grep, not the bare word: the comments name `XCUIApplication` a dozen times, so a
        // bare `contains` would stay green with the reading replaced by a list.
        #expect(body.contains("grep -qF 'XCUIApplication'"),
                "the screen-free reading no longer asks the suite's own source; a hardcoded exemption list is a second copy of the fact")

        // ONE call site, and the number is T-1933's own proposal REFUTED, not a half-fix.
        //
        // The ticket said these two decisions share an input — *does this selection launch an app* —
        // and should share an answer, and for two days this file asserted exactly that. The LEASE
        // half holds: a run that starts no test host opens no app-group container, which is all
        // T-236 is about, and the saving was measured at 800 seconds of queueing for a lease that
        // was never needed. The SCREEN half does not, and only a locked Mac could say so. Measured
        // 2026-10-02, on a Mac locked at 01:22:41: `-only-testing:CadenceUITests/`
        // `CadenceOverdrawVerdictTests` built clean — 1095 compile tasks, 0 warnings — and then
        // executed **zero** tests, because the UI-test RUNNER is itself an app and cannot start
        // while loginwindow holds an authentication session:
        //
        //     CadenceUITests-Runner (82754) encountered an error (The test runner failed to
        //     initialize for UI testing. (Underlying Error: Authentication canceled. System
        //     authentication is running.))
        //
        // The A/B is clean: the same selection on the same tree ran ten result lines unlocked six
        // hours earlier. So a screen-free suite is not screen-free in the way that matters, T-563
        // was right for a reason it did not state, and a per-suite exemption buys a five-minute
        // build, a `** TEST FAILED **`, and the zero-test guard confidently advising the reader to
        // check their suite name. Wiring the selection back into the locked-screen guard reads as
        // the obvious fix — it was one — so it has to come past this expectation and the two below.
        let call = #"selection_launches_an_app "${only_testing[@]}""#
        let callSites = body.components(separatedBy: call).count - 1
        #expect(callSites == 1,
                "only the test-host lease may consult the selection: a locked screen stops EVERY suite in the target (T-1933). Found \(callSites) call site(s), want 1")

        // ...and each in its OWN section, so a count that stays at two while one call moves
        // somewhere else — or both sit in one decision — fails. A section runs from its
        // `# --- <name>` header to the next `\n# --- `.
        func section(_ header: String) -> String? {
            guard let start = body.range(of: "\n# --- " + header) else { return nil }
            let rest = body[start.upperBound...]
            return String(rest[..<(rest.range(of: "\n# --- ")?.lowerBound ?? rest.endIndex)])
        }
        let guardSection = section("the locked-screen guard") ?? ""
        let leaseSection = section("the test-host lock") ?? ""
        #expect(!guardSection.contains(call),
                "the locked-screen guard consults the selection again. It must not: measured 2026-10-02, the screen-free suite executed 0 tests on a locked Mac because the UI-test runner could not initialize (T-1933)")
        #expect(guardSection.contains("REFUSING: the screen is locked"),
                "the locked-screen refusal itself is gone — T-563 is not weakened by T-1933")
        #expect(guardSection.contains("test runner failed to"),
                "the refusal no longer names the measured mechanism. T-563 blamed app.launch(), which only a suite launching something ever reaches, and that wording is precisely why exempting a screen-free suite looked correct for two days")
        #expect(leaseSection.contains(call),
                "the test-host lease no longer asks selection_launches_an_app of the parsed selection")
        #expect(leaseSection.contains("test-host lock: not taken"),
                "nothing says a lease was skipped, so a run that skips one cannot be told from one that holds it")

        // The false sentence. NOT pinned as an absence — the string still occurs, inside the
        // comment that QUOTES it in order to refute it, and an absence check reads that as the
        // claim coming back. (It did: this expectation was red for exactly that reason before the
        // refutation was what it looked for.) So what is pinned is the refutation standing beside
        // it: the escape hatch must not be described as making the tests skip, because
        // `CadenceOverdrawVerdictTests` carries no skip and would run.
        #expect(body.contains("THAT IS FALSE FOR AT LEAST ONE SUITE"),
                "the guard's comment no longer refutes its own claim that the tests skip under CADENCE_ALLOW_LOCKED_SCREEN_UI_RUN")
        #expect(body.contains("Authentication canceled"),
                "the guard no longer carries the measurement that refutes its own per-suite exemption; without it the next reader re-derives the exemption from the same correct-looking argument")

        // And the selftest must still induce BOTH verdicts. One fixture suite cannot tell a working
        // reading from `return 1`: the exemption would simply be unconditional and every
        // SCREEN-FREE assertion would stay green.
        #expect(selftest.contains("SCREEN-FREE"), "xcb.sh's selftest no longer induces the screen-free verdict")
        #expect(selftest.contains("LAUNCHES-AN-APP"), "xcb.sh's selftest no longer induces the app-launching control")
        #expect(selftest.contains("CadenceOverdrawVerdictTests"),
                "xcb.sh's selftest no longer asks the LIVE suite this ticket is about, so a drifted fixture would pass in silence")
    }

    /// The other half of the claim above, and it is a fact about `CadenceUITests` rather than about
    /// the script: `xcb.sh` exempts `CadenceOverdrawVerdictTests` from the **test-host lease**
    /// (never from the locked-screen refusal — see above, that exemption is refuted)
    /// because that suite cannot reach an app, and the script decides
    /// that by reading this file. If the suite ever gains an `XCUIApplication`, the exemption must
    /// stop — and it does, automatically, which is the reason the reading is taken from source. What
    /// this pins is the thing the script cannot see: that a *new* file in the target does not quietly
    /// hand the suite a launch through a helper.
    @Test func theSuiteExemptedFromTheLockedScreenGuardStillCannotLaunchAnApp() throws {
        let uiTests = CadenceSelftestRun.repositoryRoot().appendingPathComponent("CadenceUITests")
        let names = try FileManager.default.contentsOfDirectory(atPath: uiTests.path)
            .filter { $0.hasSuffix(".swift") }
        // The floor: an enumeration that found nothing must not read as a clean sweep.
        #expect(names.count >= 5, "only \(names.count) file(s) in CadenceUITests — the sweep read almost nothing")

        let suiteFile = "CadenceOverdrawVerdictTests.swift"
        #expect(names.contains(suiteFile), "\(suiteFile) is gone; xcb.sh's exemption now names a suite that does not exist")
        let suite = try String(contentsOf: uiTests.appendingPathComponent(suiteFile), encoding: .utf8)
        #expect(!suite.contains("XCUIApplication"),
                "\(suiteFile) now names XCUIApplication, so it is no longer the screen-free suite the exemption is for")

        // The helpers it actually reaches. `CadenceUITestPixelSupport` is the one it imports work
        // from; a launch smuggled in there would be invisible to a per-suite reading of the suite.
        let support = try String(
            contentsOf: uiTests.appendingPathComponent("CadenceUITestPixelSupport.swift"), encoding: .utf8
        )
        #expect(!support.contains("XCUIApplication"),
                "CadenceUITestPixelSupport now reaches XCUIApplication, so the screen-free suite can launch an app through it")

        // The control, and it is what makes the two assertions above evidence rather than a tautology
        // over a target that happens to name the class nowhere: at least one real suite here DOES.
        let launching = names.filter {
            (try? String(contentsOf: uiTests.appendingPathComponent($0), encoding: .utf8))?
                .contains("XCUIApplication") == true
        }
        #expect(launching.count >= 4,
                "only \(launching.count) file(s) in CadenceUITests name XCUIApplication — the reading is not discriminating")
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
    ///
    /// `INTERRUPTED-REPAIR` is T-3007: a run stopped between its compare-and-swap and its shared-index
    /// repair landed its commit and left the index holding a staged revert of it, which the next
    /// agent was refused `FOREIGN-STAGED` over, with only forbidden cures in reach. A signal in that
    /// window is now trapped, and the next run recognises the leftover and repairs it in place —
    /// a reading, not a refusal, so it is pinned here, and mode 9 of the selftest induces it by
    /// SIGKILLing a run the instant its swap lands.
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
        for reading in ["LEDGER-CLOSURE-LAGGED", "ledger_rewrites_only_new_entries", "T-1305", "INTERRUPTED-REPAIR"] {
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

        // T-1359's second pass is the same shape: a reading that WITHDRAWS a candidate finding, so
        // it names no refusal of its own and would otherwise be deletable without a red run. A
        // `**PARTIAL` first line excuses the commit that WROTE it and no other, which is the one
        // clause that keeps the widening from being rideable — write `**PARTIAL` on an entry once
        // and, under the reading this replaced, every later commit naming that id passes for free.
        for reading in ["T-1359", "partial_written_here", "first_line_partial"] {
            #expect(body.contains(reading), "scripts/ledger-lag-check.sh no longer makes the reading \(reading)")
        }
        #expect(
            selftest.contains("T-1359"),
            "scripts/ledger-lag-check.sh's selftest no longer induces T-1359's PARTIAL reading"
        )

        // T-1325's re-open arm is the same shape a third time: a reading that WITHDRAWS a candidate
        // finding, so it names no refusal of its own and would otherwise be deletable without a red
        // run. `closed_in_own_ledger` is the whole widening — an id counts as closed at `<rev>` OR
        // in the ledger that commit itself left — and the clause that keeps it from being rideable
        // is that it reads `$_sha`'s ledger and not HEAD's, so the excuse belongs to the commit
        // that owned the closure and expires for every commit that landed after the re-open.
        for reading in ["T-1325", "closed_in_own_ledger", "OWN_LEDGER_AWK"] {
            #expect(body.contains(reading), "scripts/ledger-lag-check.sh no longer makes the reading \(reading)")
        }
        #expect(
            selftest.contains("T-1325"),
            "scripts/ledger-lag-check.sh's selftest no longer induces T-1325's re-open reading"
        )
        // T-1434's provenance arm is the same shape a fourth time, and it is the one that
        // corrects `partialhere` rather than adding beside it. `agent-commit.sh` stages WHOLE
        // FILES ([[T-679]]) and `docs/TODO.md` is the one file every agent edits, so "did THIS
        // commit's diff write the **PARTIAL line" is answered by the shared index and not by the
        // author: `a4c12b09` and `3c9d28dd` each wrote a correct line for their own ticket, each
        // had a sibling's commit carry it away, and both were false positives in the same run.
        // The clause that keeps `partial_named_here` from being rideable is that the line must
        // name THAT COMMIT'S SHA — a rider would have to be written down, by sha, by a later
        // author, which is the same deliberate statement a `**CLOSED` line has always carried.
        for reading in ["T-1434", "partial_named_here", "PARTIAL_NAMED_AWK"] {
            #expect(body.contains(reading), "scripts/ledger-lag-check.sh no longer makes the reading \(reading)")
        }
        #expect(
            selftest.contains("T-1434"),
            "scripts/ledger-lag-check.sh's selftest no longer induces T-1434's provenance reading"
        )

        // The three copies the widening replaced with one. `LEDGER_READING` is the closure and
        // PARTIAL functions lifted out of `AWK_PROG` so the second-pass probe can share them
        // rather than carry a fourth spelling of a rule T-1335 and T-1359 already converged.
        #expect(
            body.contains("LEDGER_READING=$(cat <<'AWK'"),
            "scripts/ledger-lag-check.sh no longer spells its ledger reading once for both passes"
        )
    }

    /// **T-1325, and the owner decided the question rather than an agent.** A finding here does not
    /// expire, so an entry that is correctly closed and later RE-OPENED turns the commit that
    /// closed it permanently red — on a commit that is in history and cannot be rewritten. The two
    /// answers the ticket offered both spent something an agent does not own: a follow-up-id rule
    /// retires re-opening, which this ledger uses to keep one ticket's history in one place, and a
    /// reviewed exception list is a second allowlist in the repository whose [[T-1170]] is the
    /// story of the first one. The owner kept re-opening, so the check widened.
    ///
    /// What this test holds is the MEASUREMENT, for the same reason `replay-partial-reading.sh` and
    /// `replay-closure-reading.sh` are pinned beside their readings: the number that justified the
    /// widening stays in the tree to be re-run rather than quoted. `headleg` is named explicitly
    /// because it is the table's CONTROL — the disjunction's other, already-shipped leg read on its
    /// own, which the replay expects to be DISQUALIFIED. A disqualifying column that never
    /// disqualifies anything is indistinguishable from one that cannot reach the reading, which is
    /// [[T-1394]]'s defect, caught by its own author before adoption.
    @Test func theReOpenReadingIsMeasuredAndItsFoundingCasesArePinned() throws {
        let replay = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("scripts/replay-reopen-reading.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-reopen-reading.sh is missing or not executable, so T-1325's number cannot be re-derived"
        )
        let text = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["today", "ownhere", "ownledger", "headleg"] {
            #expect(
                text.contains(reading),
                "scripts/replay-reopen-reading.sh no longer measures the \(reading) candidate"
            )
        }
        // T-1298's three founding cases, by name. A reading that excuses one of them is not
        // adoptable however good its coverage column looks, and the replay refuses over them
        // rather than reporting them.
        for sha in ["00d576f", "e4719e3", "44eced5"] {
            #expect(
                text.contains(sha),
                "scripts/replay-reopen-reading.sh no longer checks T-1298's founding case \(sha)"
            )
        }
        // And the positive half: the one commit in this history that wrote its own closures and had
        // them re-opened underneath it three pushes later. Without it the adopted reading is never
        // once evaluated by the column that exists to disqualify it.
        #expect(
            text.contains("1273ea8"),
            "scripts/replay-reopen-reading.sh no longer checks the re-open T-1325 was filed for"
        )
        for floor in ["REPLAY-REOPEN-VACUOUS", "REPLAY-REOPEN-FOUNDING-LOST"] {
            #expect(
                text.contains(floor),
                "scripts/replay-reopen-reading.sh lost its \(floor) floor, so a run that read nothing reports a clean sweep"
            )
        }
    }

    /// **T-1434, and it is the half of [[T-1359]] the SHARED INDEX makes unanswerable.** That
    /// ticket decided a `**PARTIAL` first line excuses only the commit whose own diff wrote it,
    /// because the loose reading is rideable. What it could not know is that `agent-commit.sh`
    /// stages WHOLE FILES ([[T-679]]) and `docs/TODO.md` is the one file every agent edits, so an
    /// in-flight ledger edit lands under whoever commits that path NEXT. On 2026-09-27 that
    /// produced two findings in one run: `a4c12b09` (T-1366) and `3c9d28dd` (T-1122) had each
    /// written a correct `**PARTIAL` line for their own ticket, had it carried away by a sibling,
    /// and then landed code against a ledger path that was already clean.
    ///
    /// The adopted repair is `partialnamed` — the line must NAME the commit's sha — and it is
    /// pinned here for the same reason `replay-reopen-reading.sh` is: the number that justified
    /// the widening stays in the tree to be re-run rather than quoted. `partialany` is named
    /// explicitly because it is the table's CONTROL, T-1359's rejected loose reading, which the
    /// replay expects to be DISQUALIFIED; a disqualifying column that never disqualifies anything
    /// is indistinguishable from one that cannot reach the reading ([[T-1394]]). `partialpush` is
    /// named because it is T-1434's own candidate (a) and the table is the argument against it:
    /// this repository pushes one commit at a time, so it is NEVER REACHED and excuses nothing.
    @Test func thePartialProvenanceReadingIsMeasuredAndItsFoundingCasesArePinned() throws {
        let replay = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("scripts/replay-partial-provenance-reading.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-partial-provenance-reading.sh is missing or not executable, so T-1434's number cannot be re-derived"
        )
        let text = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["today", "partialpush", "partialnamed", "partialany"] {
            #expect(
                text.contains(reading),
                "scripts/replay-partial-provenance-reading.sh no longer measures the \(reading) candidate"
            )
        }
        // T-1298's three founding cases, by name. A reading that excuses one of them is not
        // adoptable however good its coverage column looks, and the replay refuses over them.
        for sha in ["00d576f", "e4719e3", "44eced5"] {
            #expect(
                text.contains(sha),
                "scripts/replay-partial-provenance-reading.sh no longer checks T-1298's founding case \(sha)"
            )
        }
        // And the positive half: the two commits whose PARTIAL line a sibling carried. Without
        // them the adopted reading is never once evaluated by the cases that decide it.
        for sha in ["a4c12b09", "3c9d28dd"] {
            #expect(
                text.contains(sha),
                "scripts/replay-partial-provenance-reading.sh no longer checks the case T-1434 was filed for, \(sha)"
            )
        }
        // `REPLAY-PROV-DISQUALIFIED` is the one a replay in this family has never had before, and
        // it exists because this one printed `DISQUALIFIED` beside its own adopted reading and
        // exited 0 under a mutation. A measurement nobody is obliged to act on is [[T-1343]]'s
        // shape — evidence only failure produces — turned inside out.
        for floor in ["REPLAY-PROV-VACUOUS", "REPLAY-PROV-FOUNDING-LOST", "REPLAY-PROV-DISQUALIFIED", "REFUSED RIDES"] {
            #expect(
                text.contains(floor),
                "scripts/replay-partial-provenance-reading.sh lost its \(floor) floor, so a run that read nothing reports a clean sweep"
            )
        }
    }

    /// T-1359, and it is [[T-1335]]'s convergence finished. That ticket made the three scripts
    /// spell the closure TOKEN identically and left the STATUS MODEL unconverged:
    /// `scripts/ledger-view.sh` has modelled `**PARTIAL` as its own status since it shipped, while
    /// `agent-commit.sh` and `scripts/ledger-lag-check.sh` had two states and PARTIAL fell on the
    /// open side. The gap arrived live — `7b5897d` landed two MCP constructors under [[T-1122]],
    /// whose entry opens `**PARTIAL 2026-09-25 (agent ...)`, and the lag check went red and STAYED
    /// red, because a finding never expires. One rule in three files, pinned here, is the shape
    /// this family keeps having to restore; a fourth reading is the defect.
    ///
    /// The reading is anchored right after the id on purpose, which is why it needs no
    /// `closure_visible` pass: a first line that merely QUOTES the token cannot match it, so
    /// [[T-1335]]'s defect cannot recur through this door. `scripts/replay-partial-reading.sh` is
    /// pinned beside it for the same reason `scripts/replay-closure-reading.sh` is — the number
    /// that justified the widening is left in the tree to be re-run rather than quoted.
    @Test func theThreeLedgerScriptsStillReadPartialWithOneRule() throws {
        let expected = #"""
            function first_line_partial(s) {
                return s ~ /^- \[T-[0-9]+\] \*\*PARTIAL([^A-Za-z]|$)/
            }
            """#
        for script in ["scripts/agent-commit.sh", "scripts/ledger-lag-check.sh", "scripts/ledger-view.sh"] {
            let text = try String(
                contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent(script),
                encoding: .utf8
            )
            #expect(
                text.contains(expected),
                """
                \(script) no longer spells the T-1359 PARTIAL status the way the other two do, \
                so one rule has three implementations again
                """
            )
        }

        let replay = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("scripts/replay-partial-reading.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-partial-reading.sh is missing or not executable, so T-1359's number cannot be re-derived"
        )
        let replayText = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["partialdated", "partialauthored", "partialhere", "ownledger"] {
            #expect(
                replayText.contains(reading),
                "scripts/replay-partial-reading.sh no longer measures the \(reading) candidate"
            )
        }
        #expect(
            replayText.contains("REPLAY-PARTIAL-VACUOUS"),
            "scripts/replay-partial-reading.sh lost its floor, so a replay that read nothing reports a clean sweep"
        )
    }

    /// **T-1385. The hole every other refusal in `agent-commit.sh` is on the wrong side of.**
    ///
    /// That script stages WHOLE FILES. `FOREIGN-STAGED` watches paths you did NOT name and the
    /// declined-hunk ledger records what a `=` reconstruction left behind; inside a path you DID
    /// name in the bare form both are silent by construction, because the staged content *is* the
    /// worktree. `d65d294` named `CadenceTests/CadenceGuardScriptSelftestTests.swift` legitimately
    /// and carried sibling `sweepcheck`'s whole in-flight [[T-1139]] block with it —
    /// `git show dacb9d4:<that file> | grep -c precheckShortfall` is 0 and the same read at
    /// `d65d294` is 5 — and the block cited a declaration still sitting in `sweepcheck`'s other,
    /// uncommitted file, so `CadenceCommentSymbolClaimTests` went red in CI on a commit that was
    /// green locally. The committing agent reported *"no declined hunks"*, which was true.
    ///
    /// The reading ships as a NOTICE and the replay is why: `open` would print on 94 of the last
    /// 300 commits, and two agents editing one file is normal. What this test holds is that the
    /// two NARROWER candidates stay named in the replay as DISQUALIFIED rather than quietly
    /// adopted later — both are quieter and both are blind to `d65d294` itself, because T-1139 and
    /// T-1151 are backlog ids two hundred below the highest one filed that evening. That is
    /// [[T-1356]]'s `wholeactive` a second time.
    @Test func theCommitHelperNoticesAForeignHunkInsideAPathItWasToldToStage() throws {
        let source = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent("scripts/agent-commit.sh"),
            encoding: .utf8
        )
        guard let split = source.range(of: "\ncmd_selftest()") else {
            Issue.record("scripts/agent-commit.sh has no `cmd_selftest()` to split on")
            return
        }
        let body = String(source[source.startIndex..<split.lowerBound])
        let selftest = String(source[split.lowerBound...])

        for reading in ["FOREIGN-HUNK", "added_hunk_citations", "T-1385"] {
            #expect(body.contains(reading), "scripts/agent-commit.sh no longer makes the reading \(reading)")
        }
        // The helper is body-only by construction, so only the two names the fixture can induce
        // are required of the selftest. Mode 4n is what actually drives it.
        for reading in ["FOREIGN-HUNK", "T-1385"] {
            #expect(selftest.contains(reading), "scripts/agent-commit.sh's selftest no longer induces \(reading)")
        }
        // `--unified=0` is the clause, not an optimisation: with context lines a hunk spreads into
        // its neighbours and an id three lines above an unrelated edit reads as cited by it, which
        // is the same `-U3` merge that made marker-based hunk filtering take a sibling's work in
        // the first place.
        #expect(
            body.contains("git diff --no-index --unified=0"),
            "the foreign-hunk scan no longer reads a zero-context diff, so a hunk absorbs its neighbours' ids"
        )
        // T-1343: a check whose evidence only FAILURE produces proves nothing on a green run.
        #expect(
            body.contains("foreign-hunk scan:"),
            "the scan no longer prints what it read, so a run that scanned nothing looks like a clean one"
        )

        let replay = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("scripts/replay-foreign-hunk-reading.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-foreign-hunk-reading.sh is missing or not executable, so T-1385's number cannot be re-derived"
        )
        let replayText = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["subjectonly", "msgledger", "openrecent", "opennear"] {
            #expect(
                replayText.contains(reading),
                "scripts/replay-foreign-hunk-reading.sh no longer measures the \(reading) candidate"
            )
        }
        #expect(
            replayText.contains("REPLAY-FOREIGN-VACUOUS"),
            "scripts/replay-foreign-hunk-reading.sh lost its floor, so a replay that read nothing reports a clean sweep"
        )
        #expect(
            replayText.contains("REPLAY-FOREIGN-FOUNDING-LOST") && replayText.contains("d65d294"),
            """
            scripts/replay-foreign-hunk-reading.sh no longer refuses when it cannot see its own \
            founding case, so a reading that is blind to d65d294 can be adopted on an aggregate
            """
        )
    }

    /// **T-1342. `scripts/ledger-lag-check.sh`'s mirror image, and it is a NOTICE.**
    ///
    /// That check asks whether a commit that LANDS CODE closed anything. Nothing asked the other
    /// direction: an id that reads CLOSED with nothing landed. It happens because
    /// `agent-commit.sh` stages whole files and `docs/TODO.md` is the one file every agent edits,
    /// so any agent naming the ledger carries a sibling's unlanded closure lines with it. Measured
    /// over this repository by `scripts/replay-closure-code-lag.sh`: 250 of the 734 closures ever
    /// written are for tickets that never had code to land, which is why a refusal is disqualified
    /// and the duration is the quantity that matters — median 20 minutes, none over a day, and the
    /// four founding cases resolved in 11, 11, 12 and 12.
    ///
    /// `anywhere` is the disqualifying column made into a reading, and the replay shows it is
    /// blind to all four founding cases: each self-resolved, so hindsight sees code that a guard
    /// standing at the tip cannot. Naming it here means it cannot be adopted as "the quiet one".
    @Test func theLagCheckNoticesAClosureWhoseCodeIsInNoCommit() throws {
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

        for reading in ["LEDGER-CLOSURE-UNLANDED", "tipclosed", "hascode", "T-1342"] {
            #expect(body.contains(reading), "scripts/ledger-lag-check.sh no longer makes the reading \(reading)")
        }
        #expect(
            selftest.contains("LEDGER-CLOSURE-UNLANDED"),
            "scripts/ledger-lag-check.sh's selftest no longer induces T-1342's notice"
        )
        // T-1343 / T-1350: the denominator is printed on every run, so a green one is evidence the
        // reading ran rather than evidence only that nothing tripped it.
        #expect(
            body.contains("closure-lag: %s wrote %d closure(s); %d name no code in this history"),
            "the closure count is no longer printed unconditionally, so a green run proves nothing"
        )

        let replay = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("scripts/replay-closure-code-lag.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-closure-code-lag.sh is missing or not executable, so T-1342's number cannot be re-derived"
        )
        let replayText = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["hereorbefore", "unnamed", "anywhere"] {
            #expect(
                replayText.contains(reading),
                "scripts/replay-closure-code-lag.sh no longer measures the \(reading) candidate"
            )
        }
        #expect(
            replayText.contains("REPLAY-LAG-VACUOUS"),
            "scripts/replay-closure-code-lag.sh lost its floor, so a replay that read nothing reports a clean sweep"
        )
        for founding in ["b358aa3/T-1334", "b358aa3/T-1339", "e28bc87/T-1348", "e28bc87/T-1349"] {
            #expect(
                replayText.contains(founding),
                "scripts/replay-closure-code-lag.sh no longer checks the founding case \(founding) by name"
            )
        }
        #expect(
            replayText.contains("REPLAY-LAG-FOUNDING-LOST"),
            "scripts/replay-closure-code-lag.sh no longer refuses when it cannot read its own founding cases"
        )
    }

    /// **T-1394. The ADD direction of [[T-984]]'s ambiguity, and the one half of it that CAN be
    /// resolved.** `agent-commit.sh` commits through a private index so a landed commit never
    /// writes the shared checkout ([[T-975]]), which means a file a commit ADDS can fail to reach
    /// the checkout at all. Measured 2026-09-26: `1eddce0` created `docs/MODELS_AGENTS_REFERENCE.md`
    /// and rewrote `Cadence/Models/AGENTS.md` to route to it in seven places, and all seven were
    /// dangling the moment it landed. `worktree-drift.sh` could not restore it, because a
    /// never-checked-out addition and a deliberate in-flight deletion are the same two facts —
    /// tracked in HEAD, absent from disk — and at that exact moment
    /// `CadenceTests/CadenceBlankingPassParityTests.swift` was the second kind.
    ///
    /// PROVENANCE separates them where content cannot: a path HEAD's own commit added had no local
    /// content by construction. `scripts/replay-absent-addition-reading.sh` measures that rather
    /// than asserting it — 206 of 206 additions restored and 0 deletions fought over the 372
    /// commits since `agent-commit.sh` landed, against `add40` and `anyabsent` both DISQUALIFIED
    /// for restoring the founding deletion. The add-then-delete-inside-one-batch shape that would
    /// break it has happened once in 1225 commits (`c562834`/`1070e24`, 2026-04-28) and never in
    /// the era where the drift exists.
    ///
    /// Both founding paths are named here, not just the one that had to be restored: T-1356's
    /// `wholeactive` and T-1385's `openrecent` were each their ticket's preferred reading and each
    /// was blind to the case that founded it, so a reading is only pinned once the case it must
    /// LEAVE ALONE is pinned beside the case it must fix.
    @Test func theDriftCheckTellsANeverCheckedOutAdditionFromADeletionInFlight() throws {
        let root = CadenceSelftestRun.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("scripts/worktree-drift.sh"),
            encoding: .utf8
        )
        guard let split = source.range(of: "\n# --- selftest") else {
            Issue.record("scripts/worktree-drift.sh has no `# --- selftest` section to read")
            return
        }
        let body = String(source[source.startIndex..<split.lowerBound])
        let selftest = String(source[split.lowerBound...])

        for reading in ["never-checked-out", "never checked out", "head_added_path", "staged_deletion", "T-1394"] {
            #expect(body.contains(reading), "scripts/worktree-drift.sh no longer makes the reading \(reading)")
        }
        // The deletion half must still be left alone, and it is the half a widening would lose
        // first — so the sentence that names it stays pinned too.
        #expect(
            body.contains("absent from the worktree -- a deletion in flight looks like this"),
            "scripts/worktree-drift.sh no longer leaves a deletion in flight alone, which is what T-984 bought"
        )
        // `repair` has to restore the new kind, or the reading is a report nobody can act on.
        #expect(
            body.contains("\"never checked out\" ]]") || body.contains("== \"never checked out\""),
            "scripts/worktree-drift.sh's repair no longer restores a never-checked-out addition"
        )
        for induced in [
            "mode 6 (T-1394)",
            "[never checked out]",
            "STILL not restored",
            "STAGED deletion of that same path withdraws the reading",
        ] {
            #expect(
                selftest.contains(induced),
                "scripts/worktree-drift.sh's selftest no longer induces T-1394's \(induced)"
            )
        }

        let replay = root.appendingPathComponent("scripts/replay-absent-addition-reading.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-absent-addition-reading.sh is missing or not executable, so T-1394's number cannot be re-derived"
        )
        let replayText = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["today", "add1", "add3", "add10", "add40", "anyabsent", "guideonly"] {
            #expect(
                replayText.contains(reading),
                "scripts/replay-absent-addition-reading.sh no longer measures the \(reading) candidate"
            )
        }
        #expect(
            replayText.contains("REPLAY-ADD-VACUOUS"),
            "scripts/replay-absent-addition-reading.sh lost its floor, so a replay that read nothing reports a clean sweep"
        )
        // The floor with teeth, and the reason it is separate: with no path added AND later
        // deleted, no must-not interval contains an addition and `add1` — the adopted reading — is
        // never once judged by the column that exists to disqualify it.
        #expect(
            replayText.contains("MIN_ADD_THEN_DELETE"),
            "scripts/replay-absent-addition-reading.sh lost the floor that makes its disqualifying column reach `add1`"
        )
        for founding in [
            "docs/MODELS_AGENTS_REFERENCE.md",
            "CadenceTests/CadenceBlankingPassParityTests.swift",
            "1eddce0",
            "52d727f",
        ] {
            #expect(
                replayText.contains(founding),
                "scripts/replay-absent-addition-reading.sh no longer checks the founding case \(founding) by name"
            )
        }
        for refusal in ["REPLAY-ADD-FOUNDING-LOST", "REPLAY-ADD-ADOPTED-UNSOUND"] {
            #expect(
                replayText.contains(refusal),
                "scripts/replay-absent-addition-reading.sh no longer refuses (\(refusal)) when its own reading stops holding"
            )
        }
    }

    /// T-1340, first half. `scripts/prune-shared-derived-data.sh selftest` is the one guard in
    /// `scripts/` that this test target structurally cannot run: the entire trial is a heredoc fed
    /// to `$PYTHON_BIN`, and the App-Sandboxed host is refused by the `/usr/bin/python3` xcrun shim
    /// with *"cannot be used within an App Sandbox"* (T-719). So this is the `xcb.sh` treatment —
    /// the reading that survives an environment which cannot execute the thing being read.
    ///
    /// **It is weaker than a run and the difference is the point.** A shell-out proves the guard
    /// still FIRES; this proves only that the discriminator is still written down and that the
    /// trial still claims to exercise it. It catches deletion, not rot. That is worth having
    /// anyway, because deletion is the failure this family actually suffers: a script whose
    /// selftest nothing runs loses a check silently, and every ticket in this file's history —
    /// T-719, T-1330, T-1334, T-1343 — is a variant of "the instrument was hollow and looked fine".
    ///
    /// The body half and the trial half are deliberately different lists rather than one list asked
    /// twice, because they are not the same claim and pretending otherwise would force a false
    /// symmetry. `UNREADABLE` used to be the proof of that: a real classification the script made
    /// which the trial did not induce, so requiring it on both sides would have failed.
    ///
    /// **[[T-1350]] closed that, and the asymmetry survives it for a better reason.** The trial now
    /// induces both halves of the branch — an `info.plist` that is not a plist at all, and a
    /// well-formed one whose `WorkspacePath` key is gone, which is what an Xcode release renaming
    /// the key would do to every entry at once — and asserts that `prune-dd` leaves both on disk.
    /// Measured while closing it: with the branch flipped to `ORPHAN`, both fixtures are DELETED,
    /// which is the whole hazard in one line. So `UNREADABLE` is now a needle on both lists, while
    /// the lists stay separate because "the script still makes this reading" and "the trial still
    /// exercises it" remain two claims about two halves of one file.
    @Test func thePruneScriptsDiscriminatorsAreStillInducedByItsOwnSelftest() throws {
        let source = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot()
                .appendingPathComponent("scripts/prune-shared-derived-data.sh"),
            encoding: .utf8
        )
        guard let split = source.range(of: "\n# --- selftest") else {
            Issue.record("scripts/prune-shared-derived-data.sh has no `# --- selftest` section to read")
            return
        }
        let body = String(source[source.startIndex..<split.lowerBound])
        let selftest = String(source[split.lowerBound...])

        // The readings the script makes. `lsof` is THE HARD RULE — never delete an entry a live
        // process holds open — and the known-live hash is the positive control both discriminators
        // are checked against before either is trusted, which is what stops the whole tool being
        // an elaborate way to delete somebody's Xcode.
        for reading in [
            "\"/usr/sbin/lsof\", \"+D\"",
            "positive_control",
            "WorkspacePath",
            "ORPHAN",
            "UNREADABLE",
            "cfagpqwpaaoeixfvenakmzkidwtg",
        ] {
            #expect(body.contains(reading), "scripts/prune-shared-derived-data.sh no longer makes the reading \(reading)")
        }

        // Every check its trial names. Whole sentences rather than keywords: a label is what the
        // run prints, so a check renamed out from under this is a check whose disappearance from
        // the output nobody would notice either.
        for check in [
            "hash reproduces the known-live entry for this repository's own project path",
            "info.plist pointing at a live workspace is ATTRIBUTED",
            "info.plist pointing at a gone workspace is ORPHAN",
            "no info.plist, hash matches a live project, is ATTRIBUTED",
            "no info.plist, hash matches nothing, is ORPHAN",
            "an entry a live process holds open is LIVE, never ORPHAN, regardless of attribution",
            "an info.plist that is not a plist at all is UNREADABLE, never ORPHAN",
            "an info.plist with no WorkspacePath string is UNREADABLE, never ORPHAN",
            "the run reports the unreadable entries as skipped rather than silently counting them elsewhere",
            "prune-dd removes both orphans and leaves attributed/live/unreadable entries untouched",
        ] {
            #expect(selftest.contains(check), "scripts/prune-shared-derived-data.sh's selftest no longer checks: \(check)")
        }
    }

    /// T-1340, second half, and the answer turned out to be that there is nothing to build.
    ///
    /// `scripts/real-tree-sweep-manifest.sh <id> selftest` is the stale-manifest trial (T-873): it
    /// removes an entry from the COMMITTED manifest in the checkout, runs a real
    /// `xcb.sh <id> test`, and restores the file from a trap. Three reasons it does not belong in
    /// this suite, and only the first is the one the ticket gave. It takes a build, in a suite whose
    /// premise is about a second a member. It writes to the shared checkout siblings are editing.
    /// And it would be a nested `xcodebuild test` spawned from inside a test host that already
    /// holds the test-host lock — which cannot work and should not be made to.
    ///
    /// **T-1151 asked which of those is the MECHANISM, because the reason on record was not one.**
    /// `ci.yml` said this host *"cannot spawn `xcodebuild`, ps or pgrep at all"*, and Xcode's own
    /// `xcodebuild` exits 0 in here. The answer is the second sentence above and it is now
    /// measured end to end rather than asserted:
    /// `CadenceTestHostSandboxCapabilityTests.theSweepManifestSelftestIsStoppedByTheWritePolicyAndNotBySomethingVaguer`
    /// walks the selftest's own steps from inside a real test host and finds the read and the
    /// `$TMPDIR` backup working and the `sed -i ''` into `CadenceTests/` refused — a write policy,
    /// not a spawn refusal and not "the sandbox". The build and the held lock are a separate,
    /// non-sandbox objection that would survive even if the write policy changed.
    ///
    /// It is not unpinned, though, which is what a sweep of `scripts/` and `.githooks/` could not
    /// see: `.github/workflows/ci.yml` has run it on every push since T-977, reusing the derived
    /// data and signing overrides the test job above it already paid for. A hosted runner is not
    /// sandboxed, so it is the one place that CAN lay the stale tree down. The ticket's own
    /// preferred answer — "a CI job rather than a unit test" — was already in the tree.
    ///
    /// What was genuinely unpinned is this: delete that workflow step and nothing goes red. The
    /// selftest goes back to having no caller anywhere, silently, which is the exact state T-977
    /// found it in. So the one thing left to do is the cheapest possible: name the caller.
    @Test func theRealTreeSweepManifestsBuildDrivenSelftestStillHasACaller() throws {
        let workflow = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot()
                .appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        #expect(
            workflow.contains("real-tree-sweep-manifest.sh"),
            """
            .github/workflows/ci.yml no longer runs scripts/real-tree-sweep-manifest.sh, so its \
            build-driven selftest (T-873/T-977) has no caller anywhere again — this test target \
            cannot run it (it writes to the checkout and spawns a nested xcodebuild test), so CI \
            is the only place it runs at all.
            """
        )
        let invokesTheSelftest = workflow
            .split(separator: "\n")
            .contains { $0.contains("real-tree-sweep-manifest.sh") && $0.contains("selftest") && !$0.contains("#") }
        #expect(
            invokesTheSelftest,
            """
            .github/workflows/ci.yml still names scripts/real-tree-sweep-manifest.sh but no longer \
            invokes its `selftest` mode, which is the half nothing else in the repository runs — \
            `precheck-selftest` is chained by agent-commit.sh's mode 8 and is not this.
            """
        )
    }

    // MARK: - The build-free precheck against the authoritative answer (T-1139)

    /// Manifest entries the build-free precheck does NOT reach.
    ///
    /// Empty, measured 2026-09-25 over all 330 files under `CadenceTests/`: the precheck names 293
    /// of the manifest's 293, with 0 false positives, in about 3s and with no build.
    ///
    /// A declared set rather than a comment, because the comparison below reads it in BOTH
    /// directions: a name here the precheck does in fact reach is as much a complaint as an entry
    /// it misses. A list nobody reads in the passing direction is the stale toleration this file
    /// was already caught by once (T-1161) — thirteen days green while proving nothing.
    ///
    /// And a set rather than a recall floor, because [[T-1092]] promises the cheap reader is
    /// SOUND, not complete. A sweep it cannot see is allowed. It may not be *silent*: adding a
    /// name here is one visible line somebody has to write, which is the whole difference between
    /// an admission and a decay.
    static let precheckShortfall: Set<String> = []

    /// One manifest entry per REACH the precheck has, each chosen by ablation rather than by
    /// reading: cut the machinery named beside it out of the reader and that entry is the one that
    /// disappears. Measured 2026-09-25 against the whole of `CadenceTests/` — of the 293 entries
    /// the precheck names, 156 survive a body-only reader, 249 survive a single-hop one, 44 need
    /// the transitive closure, 15 need `var`/`let` admitted as hop targets, and 5 need file-scope
    /// names resolved ACROSS files.
    ///
    /// Positional, and that is [[T-1139]]'s own argument: a recall percentage would make the
    /// precheck's incompleteness a failure, which is exactly what [[T-1092]] declines to promise.
    /// What this catches instead is the failure that really happened — a whole FAMILY of sweeps
    /// going dark, the 46 cross-file ones [[T-1092]] recovered, while the reader still looked at
    /// the right six needles and still reported a clean tree.
    static let precheckReaches: [(entry: String, reach: String)] = [
        (
            "DateFormatterSupportTests/everyDateFormatterInTheAppIsDeclaredInTheFormatterFile",
            "the walk is in the @Test's own body — the one reach a reader that hops nothing has"
        ),
        (
            "CadenceDefaultsRoutingSweepTests/everyPreferenceInTheAppTargetResolvesThroughTheDefaultsRouter",
            "one hop, into a helper beside it — the T-1091 shape; 93 entries need at least this"
        ),
        (
            "CadenceSaveCommitDisciplineTests/everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule",
            "two hops or more — 44 entries vanish when the closure is cut back to a single hop"
        ),
        (
            "CadenceContextlessListSurfaceTests/theAddFirstListRowIsOneComponentBothCallersShare",
            "a file-scope helper in ANOTHER file — 5 entries, and the one [[T-1092]] names"
        ),
        (
            "CadenceInMemoryStoreHygieneTests/noInMemoryStoreInTheRepositoryLeavesCloudKitMirroringOn",
            "the product root is reached through a stored `var`/`let` — 15 entries"
        ),
    ]

    /// **T-1139. Two readers of one rule, and nothing compared their ANSWERS.**
    ///
    /// `CadenceTestTargetHygieneTests.theCheapPrecheckLooksForExactlyTheWalkNeedlesTheScanDoes`
    /// compares the two readers' NEEDLES — the smallest thing that can differ between them, and
    /// not the thing that went wrong. The precheck once missed 46 entries, every sweep written as
    /// a bare call to a file-scope helper in the file next door, while looking at exactly the
    /// right six needles, reporting a clean tree and passing every test in the repository. Needle
    /// equality cannot see a lost family. Answer equality can, and this is it.
    ///
    /// **The authoritative answer is the committed manifest**, which is not a second opinion:
    /// `CadenceTestTargetHygieneTests` regenerates it from `CadenceRealTreeSweepScan` on every run
    /// and fails on any difference, so the file in the tree is what the scan said the last time
    /// this target was green. The precheck's own answer is taken the way its header documents —
    /// hand it a manifest naming no real test, and everything it can see comes back as unlisted.
    ///
    /// **It refuses rather than reports when it cannot compare.** Exit 2 is the script's own
    /// refusal (no usable `python3`, an unreadable or empty manifest, no sources) and fails here;
    /// so does exit 0, which over a manifest naming nothing means the reader saw nothing at all;
    /// so does a line that is not `<repo path>\t<test>`, a test named twice, a manifest that
    /// parsed to fewer entries than it can have, a census of source files too small to mean
    /// anything, and a manifest whose test names stopped being unique — that last one because the
    /// test name is the key the two answers come back on. None of those states may read as
    /// agreement. Each is quoted, with `CadenceSelftestRun.probe()`, rather than summarised.
    ///
    /// **Cost**, honestly: about 3s, against this suite's usual one. That is the price of asking
    /// for an answer instead of a needle list, and it is still 50x cheaper than the build the
    /// authoritative scan needs.
    @Test func theCheapPrecheckStillAnswersWhatTheAuthoritativeScanAnswers() throws {
        let complaints = try Self.precheckComparisonComplaints()
        #expect(
            complaints.isEmpty,
            """
            the build-free precheck in scripts/real-tree-sweep-manifest.sh and the authoritative \
            scan behind CadenceTests/CadenceRealTreeSweepManifest.txt no longer agree, or could \
            not be compared at all:
            - \(complaints.joined(separator: "\n- "))
            """
        )
    }

    /// Every reason the two readers disagree, and every reason they could not be compared. Empty
    /// means they agree. Separated from the `@Test` so the reasons are a value rather than a pile
    /// of expectations, and so an unreadable answer stops the comparison instead of being carried
    /// into assertions that would then pass over nothing.
    static func precheckComparisonComplaints() throws -> [String] {
        var complaints: [String] = []
        let root = CadenceSelftestRun.repositoryRoot()
        let testsDirectory = root.appendingPathComponent("CadenceTests")
        let script = root.appendingPathComponent("scripts/real-tree-sweep-manifest.sh").path

        let entries = try String(
            contentsOf: testsDirectory.appendingPathComponent("CadenceRealTreeSweepManifest.txt"),
            encoding: .utf8
        )
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard entries.count >= 250 else {
            return ["""
            the committed manifest parsed to \(entries.count) entr(ies), and 293 were there on \
            2026-09-25. Below that this would be measuring the reader of the manifest rather than \
            the precheck, so there is no comparison to report.
            """]
        }
        let authoritative = Set(entries.map { Self.testName(of: $0) })
        guard authoritative.count == entries.count else {
            return ["""
            two manifest entries share a test name, and the test name is the key the two answers \
            come back on (the precheck reports a FILE, and a file does not have to be named for \
            the suite it declares). Compare on whole entries instead of weakening this.
            """]
        }

        let sourceNames = try FileManager.default
            .contentsOfDirectory(atPath: testsDirectory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        guard sourceNames.count >= 300 else {
            return ["""
            only \(sourceNames.count) source file(s) under CadenceTests/, and 330 were there on \
            2026-09-25 — too few for an answer taken over them to mean anything.
            """]
        }

        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cadence-precheck-comparison-\(ProcessInfo.processInfo.processIdentifier)"
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        // The script header's own technique for reading the precheck's WHOLE answer rather than
        // its delta: hand it a manifest that names no real test, so everything it can see is
        // unlisted. Written into this host's own container, the one place it may write.
        let namesNothing = workspace.appendingPathComponent("names-nothing.txt")
        try "Fixture/nothingRealIsNamedHere\n"
            .write(to: namesNothing, atomically: true, encoding: .utf8)

        func target(_ name: String) -> String {
            "CadenceTests/\(name)=\(testsDirectory.appendingPathComponent(name).path)"
        }
        func precheckRun(_ corpus: [String], _ targets: [String]) throws -> CadenceSelftestRun {
            try CadenceSelftestRun.run(
                "/bin/zsh",
                ["-f", script, "precheck-comparison", "precheck"] + corpus + [namesNothing.path]
                    + targets
            )
        }

        let full = try precheckRun(["--corpus", testsDirectory.path], sourceNames.map(target))
        let reading = Self.precheckAnswer(full)
        guard let precheck = reading.answer else { return [reading.why] }

        let falsePositives = precheck.subtracting(authoritative).sorted()
        if !falsePositives.isEmpty {
            complaints.append("""
            \(falsePositives.count) test(s) the cheap precheck calls a real-tree sweep are not on \
            the manifest the authoritative scan wrote: \(falsePositives.joined(separator: ", ")). \
            Soundness is the entire reason the cheap reader is allowed to exist ([[T-1092]]) — \
            every one of these refuses somebody's commit over a sweep that is not one.
            """)
        }

        for shape in Self.precheckReaches {
            guard entries.contains(shape.entry) else {
                complaints.append("""
                \(shape.entry) is no longer on the manifest, so it can no longer stand for a reach \
                — name another entry that needs: \(shape.reach)
                """)
                continue
            }
            if !precheck.contains(Self.testName(of: shape.entry)) {
                complaints.append("""
                the precheck no longer reaches \(shape.entry), whose reach is \(shape.reach). One \
                named shape lost is one FAMILY of sweeps the cheap reader has gone blind to.
                """)
            }
        }

        let unadmitted = authoritative.subtracting(precheck).subtracting(Self.precheckShortfall)
        if !unadmitted.isEmpty {
            complaints.append("""
            \(unadmitted.count) manifest entr(ies) the precheck does not reach and nothing admits \
            to: \(unadmitted.sorted().joined(separator: ", ")). The cheap reader is allowed to be \
            incomplete ([[T-1092]]); it is not allowed to become so quietly. Add the name to \
            CadenceGuardScriptSelftestTests.precheckShortfall, or teach the reader the shape.
            """)
        }
        let stale = Self.precheckShortfall.intersection(precheck).sorted()
        if !stale.isEmpty {
            complaints.append("""
            precheckShortfall still admits \(stale.joined(separator: ", ")), which the precheck \
            DOES now reach. A toleration that has stopped being true is how a green run and a \
            vacuous one come to look identical (T-1161) — delete the name.
            """)
        }

        complaints += try Self.corpusReachComplaints(precheckRun: precheckRun, target: target)
        return complaints
    }

    /// The cross-file reach, ablated live rather than asserted from a table.
    ///
    /// One file, read twice: with the corpus and with `--no-corpus`. The difference must be
    /// exactly the entry whose only route to a walk is a file-scope helper in ANOTHER file, and
    /// the entry that never needed the corpus must survive both — otherwise the two readings are
    /// two silences rather than two answers. Without this the positional check above would also
    /// be satisfied by a reader that answers from the corpus alone, which is the unsoundness the
    /// script's header records an earlier spelling of this reach having had.
    static func corpusReachComplaints(
        precheckRun: ([String], [String]) throws -> CadenceSelftestRun,
        target: (String) -> String
    ) throws -> [String] {
        var complaints: [String] = []
        let file = "CadenceContextlessListSurfaceTests.swift"
        let needsTheCorpus = "theAddFirstListRowIsOneComponentBothCallersShare"
        let staysWithoutIt = "theListEditorContextRowIsDeclaredInExactlyOnePlace"
        let corpusDirectory = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("CadenceTests").path

        let readings: [(label: String, flags: [String], mustReachIt: Bool)] = [
            ("with the corpus", ["--corpus", corpusDirectory], true),
            ("with --no-corpus", ["--no-corpus"], false),
        ]
        for reading in readings {
            let run = try precheckRun(reading.flags, [target(file)])
            let answered = precheckAnswer(run)
            guard let answer = answered.answer else {
                complaints.append("the one-file ablation \(reading.label) has no answer: \(answered.why)")
                continue
            }
            if !answer.contains(staysWithoutIt) {
                complaints.append("""
                \(reading.label), the precheck no longer names \(staysWithoutIt) in \(file). That \
                one never needed the corpus, so losing it makes this ablation a comparison of two \
                silences.
                """)
            }
            if reading.mustReachIt, !answer.contains(needsTheCorpus) {
                complaints.append("""
                with the corpus the precheck no longer names \(needsTheCorpus), whose only route is \
                a file-scope helper in another file — the family [[T-1092]] recovered.
                """)
            }
            if !reading.mustReachIt, answer.contains(needsTheCorpus) {
                complaints.append("""
                with --no-corpus the precheck still names \(needsTheCorpus), so whatever reaches it \
                is not the corpus and this ablation establishes nothing about the cross-file reach.
                """)
            }
        }
        return complaints
    }

    /// The test name a manifest entry ends in — the key the two answers are compared on, because
    /// the precheck reports the FILE a test lives in and a file is under no obligation to be named
    /// for the suite it declares (39 of the 293 are not, measured 2026-09-25).
    static func testName(of entry: String) -> String {
        String(entry.split(separator: "/").last ?? "")
    }

    /// The precheck's answer, or the reason there is none. Exit 4 is the only reading that carries
    /// one here: 0 means it named nothing over a manifest that lists no real test, which is a
    /// reader that has stopped reading rather than a clean tree, and 2 is its own refusal.
    static func precheckAnswer(_ run: CadenceSelftestRun) -> (answer: Set<String>?, why: String) {
        guard run.status == 4 else {
            return (nil, """
            the precheck exited \(run.status) rather than 4 over a manifest that names no real \
            test. 4 is "it has findings"; 0 would mean it saw nothing at all; 2 is its own refusal \
            — no usable python3, an unreadable or empty manifest, no sources. There is no answer \
            to compare either way. \(CadenceSelftestRun.probe()). It said: \(run.output)
            """)
        }
        var answer: Set<String> = []
        var unreadable: [String] = []
        var repeated: [String] = []
        for line in run.output.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].hasPrefix("CadenceTests/"),
                  parts[0].hasSuffix(".swift"), !parts[1].isEmpty else {
                unreadable.append(String(line))
                continue
            }
            if !answer.insert(String(parts[1])).inserted { repeated.append(String(parts[1])) }
        }
        if !unreadable.isEmpty {
            return (nil, """
            the precheck printed \(unreadable.count) line(s) that are not `<repo path>\\t<test>`, \
            so its answer cannot be read at all: \(unreadable.prefix(5).joined(separator: " | "))
            """)
        }
        if !repeated.isEmpty {
            return (nil, """
            the precheck named \(repeated.count) test(s) twice (\(repeated.prefix(5).joined(separator: ", "))), \
            and a test name is the key the two answers come back on.
            """)
        }
        if answer.isEmpty {
            return (nil, "the precheck exited 4 — it has findings — and named none of them")
        }
        return (answer, "")
    }

    /// **T-1328. One rule with two implementations, and a divergence between them is a new trap.**
    ///
    /// `CadenceSourceScan.codeOnly` and the `blank()` inside `scripts/test-suite-index.sh` blank
    /// the same thing in two languages, and the script is what tells an agent which suite to scope
    /// a run to. A fix landing on one side only leaves the shell reporting `<file scope>` — and
    /// `xcb.sh` refusing the suite as `UNKNOWN-SUITE` — for a file the Swift guard calls clean,
    /// which is a fresh version of the original finding rather than a fix for it.
    ///
    /// Source-level on the shell side, for the sandbox reason this suite gives above: this test
    /// host cannot run the `/usr/bin/python3` shim (T-719), so the alternative to reading the
    /// source is asserting nothing. Behavioural on the Swift side, in the same test, because the
    /// two halves are only worth pinning together.
    @Test func theTwoBlankingPassesOfOneRuleStillHandleInterpolatedCode() throws {
        let script = try Self.blankingScriptSource()
        for marker in ["def scan_literal(", "def scan_code(", "stop_at_close_paren", "T-1328"] {
            #expect(
                script.contains(marker),
                """
                scripts/test-suite-index.sh's blanker no longer carries \(marker), so it has \
                diverged from CadenceSourceScan.codeOnly
                """
            )
        }

        let source = #"""
        struct Suite {
            func seed(_ names: [String]) -> String {
                "tags: [\(names.map { "\"\($0)\"" }.joined(separator: ", "))]"
            }
        }
        """#
        let code = CadenceSourceScan.codeOnly(source)
        #expect(
            code.filter { $0 == "{" }.count == code.filter { $0 == "}" }.count,
            "the Swift half lost the interpolation rule, so brace depth desynchronises again"
        )
        #expect(code.contains("tags:") == false, "non-vacuity: the literal is blanked whole")
        #expect(code.contains("struct Suite"), "non-vacuity: the code around it is not")
    }

    // MARK: - The same two passes, the other two divergences (T-1338, folded home by T-1353)

    /// The one script both blanking tests read. A shared accessor rather than the same seven lines
    /// twice: when [[T-1338]]'s fixtures lived in their own file the duplicate read was invisible,
    /// and putting them beside [[T-1328]]'s is only an improvement if the near-copy goes with it.
    private static func blankingScriptSource() throws -> String {
        try String(
            contentsOf: CadenceSelftestRun.repositoryRoot()
                .appendingPathComponent("scripts/test-suite-index.sh"),
            encoding: .utf8
        )
    }

    /// **[[T-1338]], and it is the test above's finding twice more.** Same rule, same two
    /// implementations, two further ways they indexed text differently — and it lives here, next to
    /// its sibling, because of [[T-1353]]: these fixtures spent a fortnight in a file of their own
    /// for no reason but that `CadenceGuardScriptSelftestTests.swift` belonged to a concurrent
    /// agent the hour they were written, which is an ownership fact and not a design one. T-1338
    /// itself named `theTwoBlankingPassesOfOneRuleStillHandleInterpolatedCode` as *the test that
    /// should grow the fixture*.
    ///
    /// **Both divergences were real and both were measured**, on 2026-09-25, by compiling each
    /// implementation out of this repository and running them over one fixture:
    ///
    /// - **Width.** A literal holding a combining acute, a ZWJ pair, an emoji with U+FE0F and a
    ///   regional-indicator flag blanked to **26** characters on the Swift side and **31** on the
    ///   Python one, so every column offset after it on that line differed by five.
    /// - **Line terminators.** A lone `\r` ends a `//` comment in Swift's grammar. The Swift pass
    ///   stopped there; the Python pass ran to the next `\n`, so `let b = 2` after the CR read as
    ///   **comment** on one side and as **code** on the other — a worse shape than the ticket
    ///   predicted, which only expected a `\r` inside a literal to blank differently.
    ///
    /// The repair is one change on each side: `CadenceSourceScan.blankedSpansAsSpaces` spells a
    /// blanked cluster as one space *per unicode scalar*, and the script's `blank()` ends a line on
    /// any of Swift's seven line terminators rather than on `\n` alone. Re-measured after it, over
    /// all 938 `.swift` files in `Cadence/`, `CadenceTests/`, `CadenceWidgets/` and
    /// `CadenceMCPServer/`: the two passes agree on every one, and the Swift pass's output is
    /// byte-identical to what it produced before the change, because the exposure was zero.
    ///
    /// Swift's own grammar — and `Character.isNewline` — ends a line on each of these. `\r\n` is one
    /// `Character` and two scalars; both of its scalars are here.
    private static let lineTerminators: Set<Unicode.Scalar> = [
        "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{85}", "\u{2028}", "\u{2029}",
    ]

    /// A scalar that attaches itself to whatever precedes it, which is the whole class the two
    /// passes count differently: combining marks and variation selectors (Grapheme_Extend), the
    /// zero-width joiner, and regional indicators.
    private static func joinsWhatPrecedesIt(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isGraphemeExtend
            || scalar == "\u{200D}"
            || (0x1F1E6...0x1F1FF).contains(scalar.value)
    }

    /// A combining acute, a ZWJ pair, an emoji with a variation selector and a flag — inside a
    /// literal and inside a comment, which are the two spans that get blanked.
    private static let multiScalarFixture = """
    struct Combining {
        func caption() -> String {
            "cafe\u{301} \u{1F469}\u{200D}\u{1F4BB} \u{2764}\u{FE0F} \u{1F1EF}\u{1F1F5}"
        }
        // a comment holding cafe\u{301} and \u{1F469}\u{200D}\u{1F4BB} too
        func brace() -> Int { 1 }
    }
    """

    /// **The fixture that made the two passes disagree, and the property that makes them agree.**
    ///
    /// A code-point walk and a grapheme-cluster walk can only produce the same text if a blanked
    /// span comes back the same number of *scalars* wide — one space per scalar, not one per
    /// cluster. Asserted as the scalar count rather than by re-running the Python pass, because
    /// this host cannot run it; the equality over all 938 real files was measured out of band and
    /// is recorded in the doc above.
    @Test func blankingAMultiScalarClusterKeepsTheScalarWidthTheShellPassCounts() {
        let fixture = Self.multiScalarFixture
        // Non-vacuity: this really is a fixture the two walks index differently. A pure-ASCII one
        // would satisfy everything below while proving nothing.
        #expect(
            fixture.count != fixture.unicodeScalars.count,
            "the fixture holds no multi-scalar grapheme cluster, so it cannot separate the two walks"
        )

        let code = CadenceSourceScan.codeOnly(fixture)
        #expect(
            code.unicodeScalars.count == fixture.unicodeScalars.count,
            """
            codeOnly returned \(code.unicodeScalars.count) scalars for a \
            \(fixture.unicodeScalars.count)-scalar fixture, so every column offset after the \
            first multi-scalar cluster on that line disagrees with scripts/test-suite-index.sh
            """
        )

        // Non-vacuity for the blanking itself: the literal and the comment are gone, the code is not.
        #expect(!code.contains("cafe"), "the literal and the comment were not blanked")
        #expect(code.contains("struct Combining"))
        #expect(code.contains("func brace() -> Int { 1 }"))
        #expect(
            code.filter { $0 == "{" }.count == code.filter { $0 == "}" }.count,
            "brace depth desynchronised over a multi-scalar cluster"
        )
    }

    /// A lone `\r` and a `\r\n` ending a `//` comment, and a line separator (U+2028) ending
    /// another. Swift's grammar ends a line on all three; the shell pass used to end one only on
    /// `\n`.
    private static let lineTerminatorFixture =
        "let a = 1 // alpha\rlet b = 2\r\nlet c = 3 // beta\u{2028}let d = 4\n"

    @Test func aCommentEndsOnEverySpellingOfALineSwiftEndsOneOn() {
        let fixture = Self.lineTerminatorFixture
        let code = CadenceSourceScan.codeOnly(fixture)

        #expect(code.unicodeScalars.count == fixture.unicodeScalars.count)

        // The terminators are in the same places, and no blanking invented or removed one. This is
        // what keeps line indices aligned between the two passes.
        let before = Array(fixture.unicodeScalars)
        let after = Array(code.unicodeScalars)
        #expect(before.count == after.count)
        for position in before.indices where position < after.count {
            #expect(
                Self.lineTerminators.contains(before[position])
                    == Self.lineTerminators.contains(after[position]),
                "scalar \(position) changed its line-terminator status"
            )
        }

        // The claim the shell pass used to get wrong: the comment stops at the terminator, so the
        // code after it on the next line is code.
        #expect(!code.contains("alpha"), "the CR-terminated comment survived")
        #expect(!code.contains("beta"), "the U+2028-terminated comment survived")
        #expect(code.contains("let b = 2"), "code after a lone CR was blanked as comment")
        #expect(code.contains("let d = 4"), "code after a U+2028 was blanked as comment")
        #expect(code.contains("let a = 1"))
        #expect(code.contains("let c = 3"))
    }

    /// The shell half of the same repair. The script cannot be executed from this host, so it is
    /// read — each marker is a half of T-1338 that a rewrite of `blank()` would silently lose.
    @Test func theShellBlankingPassStillEndsALineTheWaySwiftDoes() throws {
        let script = try Self.blankingScriptSource()
        for marker in [
            "NEWLINES = ",
            "def line_end(",
            "if out[k] not in NEWLINES:",
            "if not multiline and src[pos] in NEWLINES:",
            "j = line_end(i)",
            "T-1338",
        ] {
            #expect(
                script.contains(marker),
                """
                scripts/test-suite-index.sh's blank() no longer carries \(marker), so it has \
                diverged from CadenceSourceScan.codeOnly again — see T-1338
                """
            )
        }
        // …and the spelling the repair replaced is gone, so a partial revert is visible too.
        #expect(
            !script.contains("j = src.find('\\n', i)"),
            "the shell pass ends a // comment on \\n again, so a lone CR reads as comment there and as code in Swift"
        )
    }

    /// **What the repair does not close, held at zero so the next agent is told rather than
    /// surprised.**
    ///
    /// The two passes still *index* text differently — one cluster here is several code points
    /// there — so a joining scalar written **directly onto a syntactic character** (a quote, a
    /// `#`, a slash, a backslash, a parenthesis or a brace) would still be read as one unit by the
    /// Swift scanner and as two by the Python one, and the widths would come apart again. Nothing
    /// in this tree does that and nothing plausibly would; closing it properly means giving the
    /// shell pass a grapheme segmenter, which is not proportionate to a class with zero members.
    ///
    /// Measured 2026-09-25: zero offenders across all `.swift` files in the four source roots.
    /// This is a *pinned divergence*, in T-1338's own words: it fails the day such a file enters
    /// the tree. It is the one member of this group on
    /// `CadenceTests/CadenceRealTreeSweepManifest.txt`, so moving it between suites is a manifest
    /// change too — regenerated, never hand-edited, by
    /// `scripts/real-tree-sweep-manifest.sh <id> --write`.
    @Test func noSourceFileWritesAJoiningScalarOntoASyntacticCharacter() throws {
        let syntactic: Set<Unicode.Scalar> = ["\"", "#", "/", "\\", "(", ")", "{", "}", "*"]
        var scanned = 0
        var offenders: [String] = []

        for root in ["Cadence", "CadenceTests", "CadenceWidgets", "CadenceMCPServer"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                scanned += 1
                let scalars = Array(try CadenceSourceScan.sourceFile(path).unicodeScalars)
                for index in scalars.indices.dropFirst()
                where Self.joinsWhatPrecedesIt(scalars[index]) && syntactic.contains(scalars[index - 1]) {
                    offenders.append("\(path): U+\(String(scalars[index].value, radix: 16, uppercase: true))")
                    break
                }
            }
        }

        #expect(scanned > 900, "the walk read \(scanned) files; an empty walk would pass vacuously")
        #expect(
            offenders == [],
            """
            a joining scalar sits on a syntactic character, which is the one text shape \
            CadenceSourceScan.codeOnly and the blank() in scripts/test-suite-index.sh still index \
            differently (T-1338): \(offenders)
            """
        )
    }

    /// Non-vacuity for the sweep above: the detector fires on the shape it is hunting and not on
    /// an ordinary multi-scalar cluster, which is now harmless.
    @Test func theJoiningScalarDetectorSeparatesTheHarmfulShapeFromTheHarmlessOne() {
        let harmful = Array("let s = \"\u{301}x\"".unicodeScalars)
        let harmless = Array("let s = \"cafe\u{301}\"".unicodeScalars)
        let syntactic: Set<Unicode.Scalar> = ["\""]

        #expect(
            harmful.indices.dropFirst().contains {
                Self.joinsWhatPrecedesIt(harmful[$0]) && syntactic.contains(harmful[$0 - 1])
            },
            "the detector cannot see a combining mark written onto a quote"
        )
        #expect(
            !harmless.indices.dropFirst().contains {
                Self.joinsWhatPrecedesIt(harmless[$0]) && syntactic.contains(harmless[$0 - 1])
            },
            "the detector fires on an ordinary accented letter, which the repair already handles"
        )
    }

    /// **T-1590's tripwire, and the reason it had to be written rather than cited.**
    ///
    /// T-1590 records a second divergence one function over:
    /// `CadenceCommentSymbolClaim.partition`'s `extract` emits one space per `Character` where
    /// `CadenceSourceScan.codeOnly`'s `blankedSpansAsSpaces` emits one per unicode **scalar**, so
    /// `theCodeHalfOfThePartitionIsTheAuditedReader`'s character-for-character equality is only
    /// true for text whose graphemes are one scalar wide. The ticket states that *"exposure is
    /// zero today and is held there by a test"* and names the sweep above.
    ///
    /// **It is not held there by that sweep.** That one hunts a joining scalar written onto a
    /// SYNTACTIC character, and `theJoiningScalarDetectorSeparatesTheHarmfulShapeFromTheHarmlessOne`
    /// — directly above — asserts in as many words that `let s = "cafe\u{301}"` must NOT fire it,
    /// calling the ordinary accented letter *harmless*. It is harmless for T-1338, whose subject
    /// is column offsets shared with the Python pass. It is precisely the case T-1590 measured:
    /// `let s = "cafe\u{301}"` is 14 characters through `extract` and 15 through
    /// `blankedSpansAsSpaces`. So the cited tripwire excludes T-1590's own example, and until this
    /// test the only thing holding the exposure at zero was T-1338's 2026-09-25 MEASUREMENT, with
    /// nothing re-running it.
    ///
    /// This is that measurement, turned into a check. It is a deliberate over-approximation — any
    /// multi-scalar grapheme cluster anywhere in a source file, not only one inside a blanked span
    /// — because the cheap reading is the one that cannot be subtly wrong, and because the honest
    /// answer today is that the tree has none at all. Re-measured 2026-09-30: **977 files, 0
    /// offenders**, including zero CRLF line endings (a `\r\n` is one `Character` of two scalars
    /// and would land here too).
    ///
    /// Like its neighbour this is a PINNED DIVERGENCE, not a prohibition on ever writing an emoji:
    /// the day a file needs one, this fails and the next agent reads T-1590 and picks which
    /// contract `partition` owes, which is the work that ticket says is not a one-liner.
    @Test func noSourceFileHoldsAMultiScalarGraphemeTheTwoBlankingPassesWouldSpellDifferently() throws {
        var scanned = 0
        var offenders: [String] = []

        for root in ["Cadence", "CadenceTests", "CadenceWidgets", "CadenceMCPServer"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                scanned += 1
                let text = try CadenceSourceScan.sourceFile(path)
                guard text.count != text.unicodeScalars.count else { continue }
                let cluster = text.first { $0.unicodeScalars.count > 1 }
                let spelled = (cluster?.unicodeScalars ?? "?".unicodeScalars)
                    .map { "U+" + String($0.value, radix: 16, uppercase: true) }
                    .joined(separator: " ")
                offenders.append("\(path): \(spelled)")
            }
        }

        #expect(scanned > 900, "the walk read \(scanned) files; an empty walk would pass vacuously")
        #expect(
            offenders == [],
            """
            a source file holds a grapheme cluster of more than one unicode scalar. \
            CadenceCommentSymbolClaim.partition blanks it to ONE space and \
            CadenceSourceScan.codeOnly to one space PER SCALAR, so \
            theCodeHalfOfThePartitionIsTheAuditedReader's equality no longer holds over this \
            tree (T-1590): \(offenders)
            """
        )
    }

    /// **T-1335. One closure reading, three scripts, and a divergence between them is the defect.**
    ///
    /// `agent-commit.sh`'s `ledger_closed_ids`, `scripts/ledger-lag-check.sh`'s part-1 pass and
    /// `scripts/ledger-view.sh`'s `status_of` all answer *is this ledger entry closed*, and until
    /// T-1335 they answered it three different ways: the first two looked for the bare token
    /// anywhere on the entry's own first line, so an entry that merely QUOTED the marker read as
    /// closed, while the view already required a bold run. The measured victim was `T-1136` — an
    /// open, decided, not-started ticket whose first line quotes the marker inside backticks, which
    /// the view reported OPEN and the two guards read as done, so a commit could name it, land code
    /// and pass `LEDGER-CLOSURE-LAGGED` having closed nothing.
    ///
    /// They now carry one text, and this is what stops a fourth reading being written or one of the
    /// three being edited alone. Source-level for the sandbox reason this suite gives above, and
    /// exact rather than fuzzy: the whole finding is that two readings one clause apart look
    /// identical to a reader and are not.
    ///
    /// `scripts/replay-closure-reading.sh` is pinned beside them because the reading is only
    /// defensible with its number — how many honest closures a stricter reading stops recognising —
    /// and that number rots with the next commit. The script is left in the tree to be re-run rather
    /// than quoted, exactly as `scripts/replay-message-vs-ledger.sh` is for T-1304.
    @Test func theThreeLedgerScriptsStillReadClosureWithOneRule() throws {
        let expected = #"""
            bq = sprintf("%c", 96)
            while (match(s, bq "[^" bq "]*" bq)) s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
            return s
        }
        function first_line_closed(s) {
            return closure_visible(s) ~ /\*\*([A-Z]+ )?CLOSED([^A-Za-z]|$)/
        }
        """#
        // The closing delimiter sits at the `let`'s indent, so Swift hands back exactly the
        // four-space-indented text the three scripts carry -- no re-indentation step to get wrong.

        for script in ["scripts/agent-commit.sh", "scripts/ledger-lag-check.sh", "scripts/ledger-view.sh"] {
            let text = try String(
                contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent(script),
                encoding: .utf8
            )
            #expect(
                text.contains(expected),
                """
                \(script) no longer spells the T-1335 closure reading the way the other two do, \
                so one rule has three implementations again
                """
            )
            #expect(
                text.contains("function closure_visible(s,   bq) {"),
                "\(script) no longer defines closure_visible, so a QUOTED marker reads as a closure"
            )
        }

        // The two shapes the reading replaced. Either one back in any of the three is the hole.
        let commitHelper = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent("scripts/agent-commit.sh"),
            encoding: .utf8
        )
        #expect(
            commitHelper.contains(#"s/^- \[\(T-[0-9][0-9]*\)\].*CLOSED.*/\1/p"#) == false,
            "scripts/agent-commit.sh is back on the loose sed reading T-1335 replaced"
        )
        let lagCheck = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot().appendingPathComponent("scripts/ledger-lag-check.sh"),
            encoding: .utf8
        )
        #expect(
            lagCheck.contains("|| $0 ~ /CLOSED/)") == false,
            "scripts/ledger-lag-check.sh is back on the loose first-line reading T-1335 replaced"
        )

        let replay = CadenceSelftestRun.repositoryRoot()
            .appendingPathComponent("scripts/replay-closure-reading.sh")
        #expect(
            FileManager.default.isExecutableFile(atPath: replay.path),
            "scripts/replay-closure-reading.sh is missing or not executable, so T-1335's number cannot be re-derived"
        )
        let replayText = try String(contentsOf: replay, encoding: .utf8)
        for reading in ["anchored", "boldrun", "nocode", "dated"] {
            #expect(
                replayText.contains(reading),
                "scripts/replay-closure-reading.sh no longer measures the \(reading) candidate"
            )
        }
        #expect(
            replayText.contains("REPLAY-CLOSURE-VACUOUS"),
            "scripts/replay-closure-reading.sh lost its floor, so a replay that read nothing reports a clean sweep"
        )
    }

    /// And every guard has to be there to be run. A renamed script would otherwise make the
    /// tests above fail for a reason that reads nothing like "the guard is gone".
    ///
    /// The last three are the ones nothing above SHELLS OUT to — `ledger-view.sh` is run under its
    /// own shebang above, while `prune-shared-derived-data.sh` and `real-tree-sweep-manifest.sh`
    /// are pinned by reading source (T-1340) — and they need this most, not least: a source-level
    /// reading is completely blind to a lost mode, and a `chmod` that turned one of them off would
    /// otherwise be discovered by whoever next typed `./scripts/...` and got "permission denied".
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
            "scripts/codex-inbox.sh",
            "scripts/codex-land.sh",
            "scripts/xcb.sh",
            ".githooks/pre-commit",
            "scripts/ledger-view.sh",
            "scripts/prune-shared-derived-data.sh",
            "scripts/real-tree-sweep-manifest.sh",
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


    // MARK: - T-1396. One three-way probe rule, four copies of it

    /// The four functions, named and located, so the reader below cannot quietly find three.
    ///
    /// `(file, function)`. Two shapes: a **count** probe that reads `pgrep`'s two signals, and a
    /// **liveness** probe that reads one pid's command line out of `ps`.
    static let threeWayProbeSites = [
        ("scripts/test-host-lock.sh", "live_test_hosts"),
        ("scripts/test-host-lock.sh", "waiter_alive"),
        ("scripts/simulator-claim.sh", "live_simctl_for"),
        ("scripts/simulator-claim.sh", "waiter_alive"),
    ]

    /// Every top-level function in a zsh guard script, as `(name, body)`.
    ///
    /// A definition starts at column zero and a column-zero `}` closes it. A brace counter is the
    /// obvious alternative and is worse here: zsh writes `${x:-}`, `*(N.:t)` and `(( … ))` often
    /// enough that counting braces means writing a zsh lexer to get it wrong in a new way.
    ///
    /// **Two lines of this are not tidiness, they are a blindness this reader already had.** A
    /// first draft closed only on `^}` and `scripts/simulator-claim.sh` writes
    /// `claim_field() { cat … }` on one line — so that function never closed, swallowed the four
    /// hundred lines under it, and `live_simctl_for` was reported as a probe *named `claim_field`*
    /// while the real one went missing. The census below is what caught it, which is the whole
    /// reason the census is written before the comparison. So: a definition whose own line already
    /// closes is complete on that line, and any later column-zero definition closes an open one.
    static func topLevelShellFunctions(in source: String) -> [(name: String, body: String)] {
        var found: [(name: String, body: String)] = []
        var name: String?
        var body: [String] = []

        /// `(name, remainderAfterTheBrace)` when `line` opens a function at column zero.
        func opener(_ line: String) -> (String, String)? {
            let candidate = line.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
            guard !candidate.isEmpty else { return nil }
            var rest = Substring(line.dropFirst(candidate.count))
            guard rest.hasPrefix("()") else { return nil }
            rest = rest.dropFirst(2).drop(while: { $0 == " " || $0 == "\t" })
            guard rest.hasPrefix("{") else { return nil }
            return (String(candidate), String(rest.dropFirst()))
        }

        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let (candidate, rest) = opener(line) {
                if let open = name { found.append((open, body.joined(separator: "\n"))) }
                let tail = rest.trimmingCharacters(in: .whitespaces)
                if tail.hasSuffix("}") && !tail.hasPrefix("#") {
                    // A whole function on one line.
                    found.append((candidate, String(tail.dropLast()).trimmingCharacters(in: .whitespaces)))
                    name = nil
                } else {
                    name = candidate
                    body = []
                }
            } else if name != nil, line == "}" {
                found.append((name!, body.joined(separator: "\n")))
                name = nil
            } else if name != nil {
                body.append(line)
            }
        }
        if let open = name { found.append((open, body.joined(separator: "\n"))) }
        return found
    }

    /// A probe body reduced to the rule it spells, with everything that is legitimately per-script
    /// replaced by a placeholder.
    ///
    /// Derived by shape rather than by a table of the four names that exist today, so a fifth copy
    /// under new names normalises too and is compared rather than skipped. What is erased:
    ///
    /// * the probe command array — `PS_CMD`, `SIM_PS_CMD`, `PGREP_CMD`, `SIM_PGREP_CMD`;
    /// * the two output globals — `LIVE_HOSTS_COUNT` / `LIVE_SIMCTL_COUNT` and their `_WHY`;
    /// * the pattern the probe is pointed at, which is a global in one copy and `$1` in the other;
    /// * the marker a liveness probe matches its own script's name against;
    /// * comments, and runs of whitespace.
    ///
    /// Everything left is the rule: which exit statuses mean what, which one is *cannot tell*, and
    /// that an empty answer is never *dead*.
    static func normalisedProbeBody(_ body: String) -> String {
        var text = body
        for (pattern, replacement) in [
            ("^[ \\t]*#.*$", ""),
            ("\\$\\{[A-Z][A-Z0-9_]*_CMD\\[[@*]\\]\\}", "${PROBE[@]}"),
            ("[A-Z][A-Z0-9_]*_CMD", "PROBE"),
            ("LIVE_[A-Z0-9_]*_COUNT", "LIVE_COUNT"),
            ("LIVE_[A-Z0-9_]*_WHY", "LIVE_WHY"),
            ("-f \"[^\"]*\"", "-f PATTERN"),
            ("== \\*[A-Za-z0-9_-]+\\*", "== *MARKER*"),
            ("[ \\t]+", " "),
        ] {
            text = text.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression]
            )
        }
        return text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// The rule, over the real scripts.
    ///
    /// **[[T-1396]] asked for a decision between this and a sourced `scripts/lib/probe.zsh`, and
    /// the library lost on measurement, not on taste.** Measured 2026-09-26:
    ///
    /// * The two count probes are **30 lines each and differ on 2 of them** after renaming — the
    ///   trailing comment on the `()` line, and `-f "$HOST_PATTERN"` against `-f "simctl .*$1"`.
    ///   The two `waiter_alive`s are 8 lines each and differ on 2. `prune_queue` — the function
    ///   whose fall-through is the other half of [[T-1152]] — is **byte-identical** in both files.
    /// * So a library would hold roughly 62 lines and remove roughly 62, plus a file header, plus
    ///   two `source` lines, plus the parameterisation of the pattern and the self-marker. It does
    ///   not shrink the repository; it moves the lines and adds a lookup.
    /// * That lookup is not free here. Both scripts are exec'd by absolute path from four
    ///   different roots — the user's checkout via `xcb.sh`, a scratch tree minted by
    ///   `agent-scratch.sh new` (`git archive HEAD | tar -x`), a tree `mutate.sh` is mutating, and
    ///   `/bin/zsh -f <repo>/scripts/<script> selftest` from inside the App-Sandboxed test host.
    ///   A committed `scripts/lib/probe.zsh` does resolve in all four, so the library is not
    ///   *unworkable*. But the two scripts already answer "where am I" two different ways —
    ///   `SELF="${0:A}"` in the lock, `SELF="${ZSH_ARGZERO:-$0}"` in the claim script, and the lock
    ///   also repoints `SELF` from `CADENCE_LOCK_SELFTEST_TARGET` — so a `source` relative to `$0`
    ///   would be a third spelling of a thing these two files already disagree about.
    ///
    /// **The decisive asymmetry is what each one binds.** A library binds the files that opt into
    /// it. The failure this ticket is filed against is the opposite: [[T-749]] ported the lock's
    /// queue into `simulator-claim.sh` *wholesale*, [[T-1152]] then repaired one copy, and
    /// [[T-1382]] found thirteen days later that the port had never received it — with [[T-1384]]
    /// the same omission one function over, a day after that. A fifth copy written by the next
    /// port would not source a library either, and nothing would notice. This test reads every
    /// top-level function in every guard script — all 23, not the two that hold a probe today —
    /// so a fifth copy is compared the moment it lands, whether or not its author knew there was
    /// a rule. That is the one thing a library cannot do, and it is why this is the answer here.
    ///
    /// A library remains the right answer the day a probe needs a change neither script can make
    /// alone. It is not the right answer for holding two copies of thirty lines in agreement.
    @Test func everyThreeWayProbeInTheGuardScriptsSpellsOneRule() throws {
        var counts: [(String, String)] = []     // (site, normalised body)
        var liveness: [(String, String)] = []
        var sites: [String] = []

        // Every guard script, not the two that hold a probe today — see the doc comment: a fifth
        // copy written by the next port is the failure this test is for, and it will not be in a
        // file this list names. Measured 2026-09-26 over all 23 of them: exactly these four, no
        // false positive.
        let corpus = try CadenceTestHostEnvironmentPinTests.claimCorpusPaths()
        #expect(corpus.count >= 20 && corpus.contains("scripts/test-host-lock.sh"),
                "the probe sweep walked \(corpus.count) script(s), which is not a walk")
        for path in corpus {
            let source = try CadenceSourceScan.sourceFile(path)
            for function in Self.topLevelShellFunctions(in: source) {
                let normalised = Self.normalisedProbeBody(function.body)
                let site = "\(path):\(function.name)"
                if normalised.contains("-o command= -p") {
                    liveness.append((site, normalised))
                    sites.append(site)
                } else if normalised.contains("2>&1); rc=$?") && normalised.contains("return 4") {
                    counts.append((site, normalised))
                    sites.append(site)
                }
            }
        }

        // The census, before anything is compared. Two identical readings is also what a reader
        // that found ONE function returns, and a reader that found none returns "no divergence"
        // most convincingly of all.
        let expected = Self.threeWayProbeSites.map { "\($0.0):\($0.1)" }.sorted()
        #expect(
            sites.sorted() == expected,
            """
            the probe reader found \(sites.count) three-way probe(s): \
            \(sites.sorted().joined(separator: ", ")). T-1396 names exactly four: \
            \(expected.joined(separator: ", ")). A probe that vanished from this reading is a \
            probe this test no longer holds — if one was deliberately renamed or removed, say so \
            in `threeWayProbeSites`; if the reader stopped recognising it, that is the bug.
            """
        )
        #expect(counts.count == 2 && liveness.count == 2,
                "\(counts.count) count probe(s) and \(liveness.count) liveness probe(s), not 2 and 2")

        for family in [counts, liveness] where family.count > 1 {
            let (firstSite, reference) = family[0]
            for (site, normalised) in family.dropFirst() where normalised != reference {
                #expect(
                    Bool(false),
                    """
                    \(site) and \(firstSite) no longer spell the same three-way probe. \
                    Two copies of this reading disagreeing for thirteen days is T-1382, and one \
                    function over is T-1384; the rule is 0 = yes / 1 = no / 2-or-4 = cannot tell, \
                    and a blind probe is never an answer.
                    ---- \(firstSite)
                    \(reference)
                    ---- \(site)
                    \(normalised)
                    """
                )
            }
        }

        // Said as the rule, not only as a diff — four identical copies of the WRONG reading would
        // satisfy everything above. These are the three answers, spelled out.
        for (site, normalised) in liveness {
            #expect(normalised.contains("[[ -n \"$cmd\" ]] || return 2"),
                    "\(site) does not read an empty command line as *cannot tell* (return 2)")
            #expect(normalised.contains("kill -0 \"$pid\" 2>/dev/null || return 1"),
                    "\(site) lost the kill -0 fast path that answers *gone* without a process list")
        }
        for (site, normalised) in counts {
            #expect(
                CadenceSourceScan.matchCount("return 4", in: normalised) >= 3,
                """
                \(site) has \(CadenceSourceScan.matchCount("return 4", in: normalised)) \
                *cannot tell* exits, fewer than the three the rule needs: a noise line, an exit \
                status of 2 or more, and a count that contradicts its own exit status
                """
            )
            #expect(normalised.contains("LIVE_COUNT=0; LIVE_WHY=\"\""),
                    "\(site) no longer clears its two output globals before reading")
        }

        // And `prune_queue`, the caller — the half of T-1152 that is NOT in `waiter_alive`. A
        // three-way probe whose caller still prunes on 2 is the T-1382 defect exactly.
        for path in ["scripts/test-host-lock.sh", "scripts/simulator-claim.sh"] {
            let source = try CadenceSourceScan.sourceFile(path)
            guard let prune = Self.topLevelShellFunctions(in: source).first(where: { $0.name == "prune_queue" })
            else {
                #expect(Bool(false), "\(path) declares no prune_queue for the probe to feed")
                continue
            }
            #expect(
                prune.body.contains("if (( wrc == 1 ))"),
                """
                \(path):prune_queue does not gate its `rm` on *gone* alone. Pruning on anything \
                other than `wrc == 1` deletes every sibling's ticket the moment the probe goes \
                blind, which is T-1382 in one line.
                """
            )
        }
    }

    /// The probe reader, proven in both directions and proven to say so when it reads nothing.
    ///
    /// The sweep above is an equality between two strings. If `topLevelShellFunctions` returned
    /// nothing, or `normalisedProbeBody` erased everything, the comparison would hold vacuously —
    /// and the census assertion is what catches that in the real run. This is the same three
    /// questions asked of fixtures: does the reader see agreement, does it see the one-token
    /// divergence that was T-1382, and does it come back empty on a file with no probe in it.
    @Test func theProbeReaderTellsAgreementFromDivergenceAndComesBackEmptyOnNeither() throws {
        let agreeing = """
        #!/bin/zsh
        waiter_alive() {   # 0 = alive, 1 = gone, 2 = cannot tell
          local pid="${1:-}" cmd
          [[ -n "$pid" ]] || return 1
          kill -0 "$pid" 2>/dev/null || return 1
          cmd=$("${PS_CMD[@]}" -o command= -p "$pid" 2>/dev/null)
          [[ -n "$cmd" ]] || return 2
          [[ "$cmd" == *test-host-lock* ]]
        }
        other_alive() {   # a second copy under other names
          local pid="${1:-}" cmd
          [[ -n "$pid" ]] || return 1
          kill -0 "$pid" 2>/dev/null || return 1
          cmd=$("${SIM_PS_CMD[@]}" -o command= -p "$pid" 2>/dev/null)
          [[ -n "$cmd" ]] || return 2
          [[ "$cmd" == *simulator-claim* ]]
        }
        """
        let functions = Self.topLevelShellFunctions(in: agreeing)
        #expect(functions.map(\.name) == ["waiter_alive", "other_alive"],
                "the function reader found \(functions.map(\.name))")

        let normalised = functions.map { Self.normalisedProbeBody($0.body) }
        #expect(!normalised[0].isEmpty, "normalisation erased the body it was meant to reduce")
        #expect(
            normalised[0] == normalised[1],
            """
            two copies that differ only in their command array and their own script's name did not \
            normalise to one reading:
            ---- \(normalised[0])
            ---- \(normalised[1])
            """
        )

        // The T-1382 divergence itself, one token wide: *cannot tell* written back as *dead*.
        let diverging = agreeing.replacingOccurrences(
            of: "[[ -n \"$cmd\" ]] || return 2\n  [[ \"$cmd\" == *simulator-claim* ]]",
            with: "[[ -n \"$cmd\" ]] || return 1\n  [[ \"$cmd\" == *simulator-claim* ]]"
        )
        #expect(diverging != agreeing, "the divergence fixture did not actually change anything")
        let divergent = Self.topLevelShellFunctions(in: diverging).map { Self.normalisedProbeBody($0.body) }
        #expect(divergent[0] != divergent[1],
                "the one-token T-1382 divergence normalised away, which is the reader going blind")

        // Nested braces must not close a function early, and a file with no probe must read as no
        // probe — an empty answer that the census in the real sweep is what turns into a failure.
        let nested = """
        #!/bin/zsh
        one_liner() { cat "$1" 2>/dev/null }
        spaced()   { print spaced }
        outer() {
          if true; then
            print "{}"
          fi
          print tail
        }
        """
        let nestedFunctions = Self.topLevelShellFunctions(in: nested)
        #expect(
            nestedFunctions.map(\.name) == ["one_liner", "spaced", "outer"],
            """
            the function reader found \(nestedFunctions.map(\.name)). A one-line definition that             never closes swallows every function under it — which is exactly how this reader first             reported `claim_field` as a three-way probe and lost `live_simctl_for` (T-1396).
            """
        )
        #expect(nestedFunctions[2].body.contains("print tail"),
                "a nested brace closed the multi-line function early")
        #expect(nestedFunctions[0].body == "cat \"$1\" 2>/dev/null",
                "the one-line body came back as \(nestedFunctions[0].body)")
        #expect(!Self.normalisedProbeBody(nestedFunctions[2].body).contains("-o command= -p"),
                "a function with no probe in it read as a probe")
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
            // T-1397. Stopping at ANY quote read `local hseen="" hline hno hid` as declaring
            // `hseen` alone, which hid a real in-loop redeclaration in `agent-commit.sh` from the
            // very check written to catch it. The `break` is still right when a quoted value is
            // UNBALANCED inside this token, because the value then contains the spaces this line
            // was split on and every later token is a fragment of it rather than a name. Balanced
            // here means the token closes what it opened, so the next token really is the next
            // declaration. Measured across `scripts/*.sh` and `.githooks/pre-commit`: 27 lines
            // stopped the old parser early, of which exactly one declared anything after the quote.
            let doubles = rest.filter { $0 == "\"" }.count
            let singles = rest.filter { $0 == "'" }.count
            if !doubles.isMultiple(of: 2) || !singles.isMultiple(of: 2) { break }
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

    /// `interpreter` exists for T-1334 and is not a style choice: every other guard in this
    /// family is `#!/bin/zsh`, and `scripts/codex-inbox.sh` is `#!/bin/bash`. Run under zsh it
    /// does not merely warn — `for a in $also` iterates ONE word rather than the list, because
    /// zsh does not word-split unquoted parameters, so the fold reading silently changes meaning.
    /// The shebang is the contract; the caller names it rather than assuming one shell for all.
    static func of(_ relativeScript: String, interpreter: String = "/bin/zsh") throws -> CadenceSelftestRun {
        let script = repositoryRoot().appendingPathComponent(relativeScript).path
        let flags = interpreter.hasSuffix("zsh") ? ["-f"] : []
        return try run(interpreter, flags + [script, "selftest"])
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
    ///
    /// **And since T-1161 a tolerated property that PASSES is a complaint too**, which is the only
    /// direction the tolerated list could previously move in. See `staleTolerations` below.
    ///
    /// Every reading here is taken off `PASS`/`FAIL` lines the selftest prints on EVERY run,
    /// whatever its outcome -- not off a diagnostic that only a failure produces. That distinction
    /// is what T-1343 cost a session to learn: `complaints(requiring:)` above reads needles that
    /// its script prints only when a check fails, so a green run named one refusal of four and the
    /// test looked thorough while proving almost nothing. The named-run vocabulary does not have
    /// that shape, and nothing added here may reintroduce it.
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

        // T-1161. The claim `theTestHostLocksOwnGuardsStillFire` has made since T-959 -- "this still
        // fails loudly if either PASSES unexpectedly (the sandbox limit lifted, this list is
        // stale)" -- was not true of this function until 2026-09-25. Nothing here read
        // `passed ∩ tolerating`, so a tolerated property that started passing was accepted in
        // silence and the list could only ever grow. That is the T-1153 defect in miniature and
        // inside the suite written to catch it: a sentence about the environment, believed because
        // it was written down, guarding nothing.
        //
        // A tolerated name is a CLAIM that this host cannot prove that property. A PASS falsifies
        // it, and the right response to a falsified claim is to delete it, not to bank the win.
        let staleTolerations = passed.intersection(tolerating)
        if !staleTolerations.isEmpty {
            complaints.append("""
                tolerated propert(y/ies) PASSED: \(staleTolerations.sorted().joined(separator: ", ")). \
                Tolerating one is a claim that this host CANNOT prove it; a pass falsifies that claim. \
                Take the name off the tolerated list (T-1161)
                """)
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
