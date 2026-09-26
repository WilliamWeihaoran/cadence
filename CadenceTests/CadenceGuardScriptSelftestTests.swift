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
    static let simulatorClaimProperties = [
        "ordering",
        "killed-waiter",
        "cannot-tell-keeps-queue",
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

    /// T-749. Runs against a throwaway claims root and a fake `simctl` (`CADENCE_SIM_CLAIMS_DIR` /
    /// `CADENCE_SIMCTL`), so this is safe alongside sibling agents holding real device claims —
    /// and MORE safely than before T-1382, which found the selftest process's own `$CLAIMS` and
    /// `$QUEUE` still naming the real store, fixed at startup from an environment that did not yet
    /// carry the overrides. Every mode reached the sandbox through a `$SELF` subprocess, so
    /// nothing noticed until a mode read the queue in-process; they are repointed before any mode
    /// runs now, as `test-host-lock.sh`'s selftest already did (T-1343).
    ///
    /// **Nothing is tolerated here as of T-1382** — all three properties are required. `ordering`
    /// was the one exception, on `waiter_alive`'s setuid `ps` (T-959), until that function got the
    /// three-way reading the lock has had since T-1152.
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
    /// symmetry. `UNREADABLE` is the proof: it is a real classification the script makes and the
    /// trial does NOT induce it, so requiring it on both sides would fail today and the honest
    /// response to that is [[T-1350]], not a needle quietly dropped from the body list.
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
            "prune-dd removes both orphans and leaves attributed/live entries untouched",
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
        let script = try String(
            contentsOf: CadenceSelftestRun.repositoryRoot()
                .appendingPathComponent("scripts/test-suite-index.sh"),
            encoding: .utf8
        )
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
