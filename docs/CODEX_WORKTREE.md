# Codex Worktree Protocol

Codex writes code here, in its own worktree, on its own branch. The coordinator lands it.

This exists because **two writers in one checkout collide in two measured ways**, neither of which
announces itself:

- **[[T-1385]]** — `scripts/agent-commit.sh` stages **whole files**. When two writers edit one file,
  one commit silently carries the other's half-finished work: no refusal, no declined hunk, nothing
  in `git status` that looks wrong. It reddened CI on `d65d294`, where a commit swept in a sibling's
  in-progress block that contained a forward reference to a declaration still uncommitted.
- **[[T-975]]** — a commit lands through a private index and never writes the shared checkout, so
  the tree drifts behind HEAD. `[stale base]`, `[stale copy]` and `[never checked out]` ([[T-1394]])
  are three different repairs and picking the wrong one destroys work.

A separate worktree removes the first entirely — disjoint filesystems cannot interleave — and makes
the second Codex's own problem rather than a shared one.

## The flow

1. **Codex works in its worktree**, on a branch named `codex/<topic>`, based on `origin/main`.
2. **Codex commits with plain `git commit`.** It does *not* run `scripts/agent-commit.sh`: that
   script enforces ledger discipline that requires editing `docs/TODO.md`, which is the one file
   guaranteed to conflict.
3. **Codex never touches the ledger.** Instead it appends its ticket entries to
   `docs/CODEX_LEDGER_INBOX.md` — **append-only, newest last**. Appending merges cleanly; editing
   a 12,000-line file in place does not.
4. **The coordinator reviews** with `./scripts/codex-land.sh review codex/<topic>`, which refuses on
   lease violations, ledger edits, missing inbox entries and id clashes.
5. **The coordinator runs the tests and lands it** through `scripts/agent-commit.sh`, folding the
   inbox entries into `docs/TODO.md` in the same commit. Every guard the repository has then applies
   to Codex's work exactly as it applies to everyone's.

The coordinator is the bottleneck on step 5 deliberately. It costs minutes, and it is what keeps
`FOREIGN-STAGED`, `REMOVES-HEAD-LINES`, `LEDGER-ID-UNFILED`, the closure reading and the foreign-hunk
notice applying to code that did not come through them.

## The lease

Codex may write **only** to paths matching the lease below, and never to a path another writer holds.
The coordinator updates this block when the assignment changes; `codex-land.sh lease` parses it, so
this file is the single source of truth and there is no second list to drift.

Patterns are shell globs matched against repository-relative paths. `docs/CODEX_LEDGER_INBOX.md` is
always allowed and never needs listing.

```lease
Cadence/iOS/iOSList*.swift
Cadence/Shared/CadenceTypography.swift
CadenceTests/CadenceTypographyScaleTests.swift
CadenceTests/CadenceCodex*.swift
```

### LEASE RETRACTED 2026-10-04 — the 16 T-1458 paths are back, because the work landed

`7bdb0c32` landed Codex's T-1458 work: the prepared-query search, the single-pass goal
next-action, the chunk-bounded MCP audit reader and the four widget follow-ups. `codex-land.sh
review codex/search-widget-followups` now answers **`CODEX-BRANCH-ALREADY-LANDED` — all 20 files
already in main, 20 identical, 0 where main moved past**, which is the terminal state a spent
branch is supposed to reach.

So the sixteen production paths granted on 2026-10-04 are retracted and free for any writer.
Retracted rather than left standing because this file's own warning applies: *a lease granting
paths nobody is working on is a lease that will eventually be believed*, and [[T-2069]] is the
precedent — four separate agents were blocked or forced to edit through a fence that was
protecting branches with nothing in them.

**What stays open does NOT need these paths.** [[T-1461]]'s native widget visual checks are device
work, not source edits. [[T-1458]]'s file-extraction half is still deferred and still needs an
owner decision about `project.pbxproj` target registration, not a lease. [[T-1462]], the midnight
habit-intent race, names `Cadence/Services/CadenceWidgetIntents.swift` — a path that was **never in
this grant** and is unchanged by the landing, so it would be a fresh request if Codex picks it up.

The four patterns above are untouched and still live: `iOSList*.swift` and the typography trio
remain [[T-1411]]'s standing assignment, and `CadenceTests/CadenceCodex*.swift` is a namespace
rather than a file -- dropping it would make `codex-land.sh` refuse Codex's next branch for doing
exactly what it was asked.


### LEASE GRANTED 2026-10-04 — 16 paths for T-1458, on `codex/search-widget-followups`

Codex requested the minimum production lease for the owner's search / goal-summary / MCP
audit-log / widget follow-ups, and asked that these be reserved from other writers. The ticket,
with the patch order and the verification plan, is `docs/CODEX_LEDGER_INBOX.md:227`; the worktree
is `/Users/williamwei/.codex/worktrees/9e4a/Cadence`, read at `24c671c4` with 0 dirty files.

**These are additive to the four patterns above, not a reversal of the narrowing.** The narrowing
retired the iOS task-UI fence because every branch behind it was spent ([[T-2069]]); this grant
covers a different subtree that a live branch is actually working on. None of the sixteen was held
by another writer when it was published, and none is in any running agent's scope.

**The file-extraction half is NOT granted and is deferred by agreement.** The owner's sixth
optimization recommendation would split `PersistenceController.swift`'s `StoreBackupManager`
boundary and declarations preceding `CadenceWriteService`. New files must be registered as build
inputs in `Cadence.xcodeproj/project.pbxproj` — which MCP explicitly compiles (`project.pbxproj:690`)
— and that file is not edited while the owner has Xcode open ([[T-117]]). Target registration is an
owner decision, not a lease question. Codex deferred it; the coordinator confirms the deferral.

### LEASE NARROWED 2026-10-04 — 35 patterns to 4, because every Codex branch is spent

**Measured, not read off the branch names.** `./scripts/codex-land.sh review` was run against all
seven `codex/*` branches in this repository on 2026-10-04 at `24c671c4`. **Not one of them has a
single code file that is not already in `main`:**

| branch | `review` verdict | exit |
| --- | --- | --- |
| `codex/archive-typography-20261002` | `CODEX-ONLY-THE-INBOX-IS-UNLANDED` — 30 of 31 files already in main | 3 |
| `codex/calendar-day-drop-commit` | `CODEX-ONLY-THE-INBOX-IS-UNLANDED` — 6 of 7 files already in main | 3 |
| `codex/archive-large-text-20261002` | `CODEX-BRANCH-ALREADY-LANDED` — all 18 files | 5 |
| `codex/context-budget` | `CODEX-BRANCH-ALREADY-LANDED` — all 4 files | 5 |
| `codex/save-report-closure-detector` | `CODEX-BRANCH-ALREADY-LANDED` — all 3 files | 5 |
| `codex/task-page-large-text` | `CODEX-REVIEW-VACUOUS` — 0 commits over main | 4 |
| `codex/task-page-typography-finish` | `CODEX-REVIEW-VACUOUS` — 0 commits over main | 4 |

The Codex worktree at `~/.codex/worktrees/9e4a/Cadence` was read at the same time: `git status` is
**empty**, so no path in this fence was mid-edit. Nothing was reset, deleted or force-pushed; the
branches are left exactly as Codex left them, and the two that still carry unlanded
`docs/CODEX_LEDGER_INBOX.md` entries carry ids the ledger already has formal entries for, which is
the T-1800 shape and not pending work.

**This is the rule in this file being kept rather than cited:** *a lease granting paths nobody is
working on is a lease that will eventually be believed.* It had been believed. [[T-2058]] designed
the three row indicator glyphs and wrote **no code**, on the stated evidence that
`codex/archive-typography-20261002` was "3 commits ahead of `main` and UNLANDED". The commit count
is three; the content is zero. `git log main..<branch>` answers a different question from
`codex-land.sh review`, and only the second one is the lease's question.

**What came back, and why.** Twenty-six paths whose assignment is closed in the inbox
([[T-1440]], [[T-1442]], [[T-1450]], [[T-1454]], [[T-1457]]) and whose branches `review` calls
spent — every converted iOS page surface, every shared component T-1442 closed, the three
context-budget paths, and the guards written for that closed work. Four of them were named by
T-2058 as the thing blocking it: `Cadence/iOS/iOSTaskViews.swift`,
`CadenceTests/CadenceTodayUnificationTests.swift`, `CadenceTests/CadenceSharedTaskRowJobsTests.swift`
and `CadenceTests/CadenceTagChipStyleTests.swift`.

**What stayed, and why — this is the conservative half.** [[T-1411]] is still **PARTIAL** and is
still Codex's standing first assignment under R66; [[T-1453]] says Lists is the one task page not
yet declared. So `Cadence/iOS/iOSList*.swift` stays, and with it the two files any further
conversion must edit: `Cadence/Shared/CadenceTypography.swift`, which is where the roles and the
scaling environment are decided, and `CadenceTests/CadenceTypographyScaleTests.swift`, which carries
the "exactly N declared roots" sweep that this file's own *one converter at a time* rule is about.
`CadenceTests/CadenceCodex*.swift` stays because it is Codex's reserved **namespace**, not a file:
a new conversion writes a new guard there, and dropping the glob would make `codex-land.sh` refuse
Codex's next branch with `CODEX-LEASE-VIOLATION` for doing exactly what it was asked to do.

**One edit was made inside that namespace at the same time, deliberately and under the permission
[[T-2061]] names.** `CadenceTests/CadenceCodexTaskSummaryTypographyTests.swift:74` required
`.cadenceFont(` in `CadenceTaskGroupHeading`, and [[T-2056]] deleted the count capsule that was that
file's only call of it. That is the *re-point, never weaken* case below, T-2061 asked the
coordinator to land it rather than route it to Codex, and `main` had been red on it for a day. The
check is not deleted: the heading keeps every other assertion in the loop and gains the stronger
`SectionEyebrowLabel` source read. **If Codex is mid-edit on that file when it reads this, say so
and the coordinator rebases it — the worktree was clean when this was written.**

### The context-budget grant (2026-10-02), and the two things it does not permit

**LEASE ENDED 2026-10-04: [[T-1454]] landed on `main` and `codex/context-budget` reviews as
`CODEX-BRANCH-ALREADY-LANDED` (all four files). `CLAUDE.md`, `scripts/codex-inbox.sh` and
`docs/CODEX_REQUESTS.md` are out of the `lease` block above.** The section below is kept as the
record of what was asked, and its two boundaries still describe what those files are for.

`CLAUDE.md`, `scripts/codex-inbox.sh` and `docs/CODEX_REQUESTS.md` are leased to Codex for the
context-budget work Codex itself scoped. Measured at `74c1d186`: the request document is **306 KB**
with no per-request lookup, and `CLAUDE.md` repeats directory maps, build commands and incident
history that `AGENTS.md` already owns.

Two boundaries, both load-bearing:

**`scripts/codex-inbox.sh` has a selftest and it is a landing gate.** It currently offers
`report | fold R<n> | selftest`. Add `show R<n>`; do not change what `fold` or the id-clash check
mean. The selftest must be green and must gain a case for the new subcommand — a lookup that
silently returns the wrong request is worse than no lookup. `codex-inbox.sh` is `#!/bin/bash`;
`codex-land.sh` is `#!/bin/sh`; do not assume either from the extension.

**`CLAUDE.md` is startup context for every agent, so trimming it is in charter but rewriting it is
not.** Its own rule says: when adding an always-read rule, remove or link out something else. Move
duplicated material to `docs/CLAUDE_REFERENCE.md` or the scoped `AGENTS.md` and leave a link. Do not
remove a safety rule, and do not remove the first-reads ordering. If a line looks redundant but you
cannot find where it is covered, keep it and say so.

**Archiving acted-on requests is permitted only if ids and acknowledgement tracking survive byte for
byte.** The whole point of the inbox is that an id resolves to exactly one entry; an archive that
loses that is a regression, not a saving. Measure the before and after sizes and state both.

**Not granted, and not to be inferred:** `docs/TODO.md`, `AGENTS.md`, `scripts/xcb.sh`,
`scripts/agent-commit.sh`, `scripts/codex-land.sh`, `.github/`. The largest saving in this area —
never reading the 2.4 MB ledger, using `./scripts/ledger-view.sh show`/`brief` instead — is a
coordinator habit that has already been fixed in the agent brief, not a change to any file here.

### T-1980 was leased to Codex (2026-10-02), and it is a FINISH, not a start

**LEASE ENDED 2026-10-02: T-1980 landed on `main`, and its six paths are out of the `lease` block
above.** The section below is kept as the record of what was asked.

Six macOS paths are leased for [[T-1980]] only. This is the first time Codex has held anything under
`Cadence/macOS/Views/`, and the grant is narrow and temporary: it ends when T-1980 lands.

**The implementation already exists and is ~80% done.** Agent `boarddrops` built it and ran out of
budget mid-verification. The work is a patch, not a blank page, and the instruction is **finish and
verify it, do not redesign it**. If Codex believes a design decision is wrong, it says so and stops
rather than rewriting — the decisions were measured, and two of them were measured *against* the
obvious alternative.

**What is already proven:** M1, the headline mutation — both drops restored to the swallowing form
with the `commit:` seam kept — produced **31 issues across 6 tests**, linked and re-signed. The
macOS build is clean at 696 compile tasks, 0 warnings.

**What is missing, and it is the whole job:** M2 (`calendarEventID` dropped from `restore(to:)`,
expected to redden **only** the block-move calendar-link assertions) and M3
(`CadenceTaskBundleSlotSnapshot` dropping `startMin`/`durationMinutes`, expected to redden **only**
the clamp test). These are *attribution* mutations: each must redden exactly one group and leave the
rest green. That is the evidence that proved [[T-1952]] and caught that copying [[T-1580]]'s shape
unaltered would have made it worse. Also missing: a full `-only-testing:CadenceTests` run over final
bytes, and an **iOS build**, which is owed because `Cadence/Shared/CadenceTaskFieldEditCommit.swift`
is touched.

**Two design decisions not to undo.** `CadenceTaskMutationSupport.updateBundle` was deliberately not
reused: it writes `title`, clamps against its own literals, and does not clear members' calendar
links, so reusing it would have changed what the drop does while fixing what it reports. And
`CalendarBoardDayColumn.handleDrop` returned `true` unconditionally because both callbacks were
`Void`; they answer `Bool` now, and the one surviving `return true` is the hit-test deferral to a
bundle card, which is correct.

**`CadenceSaveCommitRule.reportExemptions` is empty (`[:]`) and stays empty.** Fix defects; never
widen or add an exemption.

### `CadenceSaveCommitDisciplineTests.swift` is leased for T-1990 only (2026-10-02)

**LEASE ENDED 2026-10-03: the direct-only detector ([[T-1457]]) landed on `main` from
`codex/save-report-closure-detector`, and this path is out of the `lease` block above.** [[T-1990]]
stays PARTIAL for the stored-callback transport sites; a later grant for them is a new lease.
The section below is kept as the record of what was asked.

Codex asked for this rather than assuming it, which is the behaviour the lease exists to produce.
[[T-1990]] is a change to the **detector**, and `CadenceSaveCommitRule` and its file-private parser
live inside that test file — 118 references — so the ticket is unreachable without it. Granted for
T-1990 only; it ends when T-1990 lands.

**Reserved from other writers while that lease is live.** It was clean and unheld when granted: no
in-flight agent had it, and the only uncommitted paths were `palettecopy`'s four. A coordinator
assigning work that touches this file must check the lease first rather than discovering the clash
at `agent-commit.sh`.

**`reportExemptions` is EMPTY (`[:]`) and stays empty.** [[T-1952]] emptied it by fixing the defect
and [[T-1980]] kept it empty. A detector that makes 47 sites fail and is then made tolerable by
re-populating that list would undo both. If the new rule needs an escape hatch, that is a finding to
file, not a list to refill.

**The trap, which Codex identified itself when filing the ticket:** a structural "a `Void`
declaration may not swallow" rule names **47 of 51** sites in one change, and most are the in-place
field edits the rule deliberately allows. The landable rule is the narrow one — a swallowing
declaration whose only caller is a closure argument whose parameter type returns `Bool`, the
`.dropDestination` shape where the `true` the UI reads is built one frame up in another file.

## The coordinator's side

A lease is a **two-sided** promise and the first draft of this file only wrote one side. Codex's
first assignment reported the gap before writing a line: the lease named paths, but nothing stopped
the coordinator from handing one of those same paths to a subagent an hour later, which is the
collision the worktree was built to remove, re-entering through the coordinator's own door.

So, while a lease is in force:

- **The coordinator does not assign a leased path to a subagent**, and does not edit one itself
  except to land Codex's branch. If something on a leased path needs fixing first, the lease comes
  back before the fix goes out.
- **The coordinator publishes the protocol before assigning work.** Codex branches from
  `origin/main`; a file that exists only in the shared checkout's working tree is a file Codex
  cannot read, cannot run, and is right to refuse to proceed without.
- **Shared test files count as leased paths.** `CadenceTypographyScaleTests` carries the "exactly N
  declared roots" sweep, so *every* typography conversion edits it. Two converters means two writers
  in that one file, which is [[T-1385]] exactly. One converter at a time, and right now that is
  Codex.
- **The coordinator narrows the lease when the assignment ends**, rather than letting it accumulate.
  A lease granting paths nobody is working on is a lease that will eventually be believed.

### The four paths T-1451 asked for, and the two embedded surfaces

**LEASE ENDED 2026-10-04: all four are out of the `lease` block above**, along with
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` and `CadenceTests/CadenceTodayUnificationTests.swift`
— `codex/archive-typography-20261002` reviews with every one of its code files already in `main`.
The section below is kept as the record of what was asked. Its *re-point, never delete or loosen*
direction still binds whoever edits those guards next; it is a property of the guards, not of the
lease.

Three of the four are granted above. The fourth was already granted and Codex could not see it:
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` and `CadenceTests/CadenceTodayUnificationTests.swift`
entered the lease **after** `codex/task-page-typography-finish` branched from `4e6f4feb`, so the
branch's own copy of this file does not list them. Re-point `:675`'s three-read count as T-1451
proposes — the narrow permission in the section above applies to it word for word: re-point, never
delete, loosen or route around, and do not add production reads whose only purpose is to satisfy the
old count. Read the lease from `origin/main`, not from the branch, when in doubt.

`Cadence/Shared/Components/CadenceBoardColumnHeader.swift` is the one grant here that is **not**
iOS-only: `Cadence/macOS/Views/KanbanColumnSupportViews.swift` and the two Calendar views draw it
too. The constraint is the one T-1451 proposed itself — prepare it with fixed-mode preservation and
an explicit caller inventory, and do not opt the macOS or Calendar callers in. There are open
scrolling-performance tickets against the macOS Kanban board; if one of them needs this file, the
lease comes back before that fix goes out, the same way [[T-1492]] took `CadenceDatePicker.swift`.

**Both embedded surfaces: the proposal in T-1451 is accepted.** Today `.timeline` and Lists
`.documents` get explicitly fixed Cadence chrome on the embedding, matching Today's agreed Notes
boundary, and the Calendar and Notes conversions behind them stay separate work. No new lease is
needed for it: `iOSTodayView.swift`, `iOSTodaySchedulePanel.swift`, `iOSListDetailView.swift` and
`iOSListNotesView.swift` all already match `iOSToday*.swift` and `iOSList*.swift`.

`Cadence/Shared/Components/CadenceDatePicker.swift` does **not** return, and the commit that removed
it said it would. It is already a declared scaled root in the inventory at
`CadenceTests/CadenceTypographyScaleTests.swift:422`, and T-1451's own remaining patch order does not
name it, so returning it would grant a path nobody is working on — which this file's own rule says is
the kind of lease that eventually gets believed. It comes back the moment an assignment needs it; say
so rather than working around it.

### The two files loaned for T-1702 have come back — and they came back

The promise this section carried while the loan was in force, kept word for word because it is the
one being discharged:

**They return when T-1702 lands.** [[T-1492]] made the same promise about `CadenceDatePicker.swift`
and I did not keep it; [[T-1800]] records why that was defensible and it is still a promise I broke.

**T-1702 landed as `3d1f5c33` on 2026-09-30, and both files are back in the lease as of 2026-10-01.**
That is this promise kept on its own terms. [[T-1492]]'s is still outstanding and is still recorded
as outstanding in the section above; nothing here discharges it.

What changed under the loan, so Codex is not surprised by the bytes: `iOSFeatureComponents.swift`
gained `CadencePageHeaderEyebrow.ladder(eyebrow:compactEyebrow:detail:)`, three **named** rungs fed to
a `ViewThatFits` on the header line. Two things about that are load-bearing and must not be undone by
a typography pass. First, the budget is not the pane and not the column — it is **what the two chips
on the same row leave behind**, which is why the fix is a ladder and not a width rule in the layout
support. Second, **an `if` inside a `ViewThatFits` builder produces an empty candidate that fits every
width and draws nothing**, and `ViewThatFits` renders its *final* candidate whether it fits or not —
so the rungs are unconditional and ordered deliberately. Re-spelling either property is a change to
the ladder, not to a font.

`iPadTodaySupportViews.swift` is unchanged in substance.

**Open against these two files, and yours now:** [[T-1880]] — `iPadTodayTaskHeader` reads `Date()`
twice for one header, because `iOSTodayView.todayTaskColumn` passes an eyebrow built from one `Date()`
and the header takes another. It was left unfixed precisely because the file was leased. It is a real
two-reads-one-render defect, not a tidy-up: the two reads can straddle midnight.

## Do not edit `Cadence.xcodeproj/project.pbxproj`

`Cadence/` and `CadenceTests/` are `PBXFileSystemSynchronizedRootGroup`s, so a new file under either
is picked up by the app and test targets **with no project-file edit at all**. The explicit entries
still in that file exist only for sources that must also compile into a *second* target — the widget
and the MCP server, which is why `Cadence/Models/*` appears there by hand.

Nothing in the typography work needs a second target. If Codex ever believes a new file does, that
is the moment to stop and say so, because `project.pbxproj` is the single highest-collision file in
the repository and a merge there is not reviewable.

### A leased guard may be re-pointed, never weakened

**`CadenceTests/CadenceSharedBoardChromeTests.swift` left the `lease` block on 2026-10-04**, and
this rule did not leave with it. It is why the two [[T-2061]] re-points landed as re-points: a guard
whose subject moved is pointed at where the subject went, never deleted, loosened, or routed around,
and the assertions bracketing it that stop it going vacuous stay.

`CadenceTests/CadenceSharedBoardChromeTests.swift` is leased because converting
`CadenceTodayOverdueSummaryCards.swift` invalidates a source-substring assertion in it
(`:671`, `size: SectionEyebrowLabel.fontSize`), and the converter is the only party who knows what
the call becomes. A guard edited at landing by someone reading a diff is a guard being rubber-stamped.

The permission is narrow and it is a direction, not a budget. Re-point the assertion at the new
call. Do **not** delete it, loosen it to a weaker predicate, or route around it — and keep the two
assertions bracketing it, which are what stop it going vacuous: the non-vacuity check that the file
is still the heading's file, and the negative control that an 11pt eyebrow tier has not come back.
Note also that the three checks above them (`SectionEyebrowLabel.fontSize == 10` and the two
`countSize ==` identities) are **model** assertions, not source reads, and a conversion should leave
them alone.

### A new test that reads the real product tree is not green until the manifest is regenerated

`CadenceTests/CadenceRealTreeSweepManifest.txt` is the exact list of every `@Test` that sweeps the
real product tree, and two suites compare the committed file against a fresh derivation:
`CadenceTestTargetHygieneTests.theRealTreeSweepManifestIsExactlyWhatTheScanFinds` and
`CadenceGuardScriptSelftestTests.theCheapPrecheckStillAnswersWhatTheAuthoritativeScanAnswers`. A new
sweep that is not listed fails both, and neither is reachable from a scoped run of the suites a
ticket touches — which is how `codexChipAndInspectorReadTheOneLineHeightRatio` arrived at landing
with a cold green, a 193-test run and a named known red, and still reddened the full suite.

**Codex does not regenerate the manifest and the file is not leased.** Every writer in the repository
adds sweeps, the file is derived rather than typed, and a branch that regenerates it conflicts with a
main that also did. Instead: **say in the inbox entry that the ticket adds a real-tree sweep, and
name the tests.** The coordinator runs `scripts/real-tree-sweep-manifest.sh <id> --write` at landing,
where it is one derivation against one tree.

So those two suites being red on the branch is expected when a sweep was added, and is not something
to chase. Every *other* red still is.

## What Codex must not do

- **Never edit `docs/TODO.md` or `docs/TODO_DONE.md`.** Use the inbox.
- **Never force-push, rebase a shared branch, or rewrite history.**
- **Never push to `main`.** Only `codex/<topic>` branches.
- **Never run `scripts/agent-commit.sh --commits-stale`,** or "repair a stale base".
- **Never touch a path outside the lease**, even to fix something obviously broken — say so instead.
- **Never point a test at `~/Library/Containers/com.haoranwei.Cadence/Data/`**, the real app group,
  or the owner's iCloud container.
- **Never kill a process merely named `Cadence`** — the owner runs `/Applications/Cadence.app` and
  an Xcode debug build. Terminate only pids Codex launched.
- **Never erase, boot or shut down a simulator it did not create.**

## What Codex must do

- Build and test through `./scripts/xcb.sh <id> …` with `-scheme` and `-destination`, never a bare
  `xcodebuild`. `-only-testing:` takes `CadenceTests/<SuiteName>` — a **filename runs zero tests and
  exits 0**, and so does a nonexistent suite. Verify names against `./scripts/test-suite-index.sh`.
- Read the real `XCODEBUILD_EXIT=` line from the result block, never `$?` after a pipe, and check
  `swift compile tasks:` is non-vacuous — a warm run printing `VACUOUS-COUNT` carries no evidence.
- Hold the warning baseline at **zero**.
- Write one inbox entry per ticket it closes or files, in the ledger's own shape: the id, a bold
  one-line headline, and the measurement. A closure is written **as** a closure
  (`**CLOSED <date> (codex) — …`), not described as one ([[T-1335]]).
- Use only ids from the range the coordinator reserved for it, recorded at the top of the inbox.
