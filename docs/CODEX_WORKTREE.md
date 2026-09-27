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
Cadence/iOS/iOSInbox*.swift
Cadence/iOS/iOSToday*.swift
Cadence/iOS/iPadTodaySupportViews.swift
Cadence/iOS/iOSList*.swift
Cadence/iOS/iOSSearch*.swift
Cadence/iOS/iOSTaskCollection*.swift
Cadence/iOS/iOSTaskViews.swift
Cadence/iOS/iOSTaskRowActionViews.swift
Cadence/iOS/iOSTaskGroupSection.swift
Cadence/iOS/iOSTasksPageView.swift
Cadence/iOS/iOSTasksTabView.swift
Cadence/iOS/iOSSwipeActionRow.swift
Cadence/Shared/Components/CadenceDatePicker.swift
Cadence/iOS/iOSFeatureComponents.swift
Cadence/iOS/iOSDesignSystem.swift
Cadence/Shared/Components/EmptyStateView.swift
Cadence/Shared/Components/CadenceTaskGroupHeading.swift
Cadence/Shared/Components/CadenceTodayRolloverBanner.swift
Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift
CadenceTests/CadenceCodex*.swift
CadenceTests/CadencePickerLargeTextLayoutTests.swift
CadenceTests/CadencePresentedTypographyBoundaryTests.swift
CadenceTests/CadenceTypographyScaleTests.swift
CadenceTests/CadenceTagChipStyleTests.swift
```

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

## Do not edit `Cadence.xcodeproj/project.pbxproj`

`Cadence/` and `CadenceTests/` are `PBXFileSystemSynchronizedRootGroup`s, so a new file under either
is picked up by the app and test targets **with no project-file edit at all**. The explicit entries
still in that file exist only for sources that must also compile into a *second* target — the widget
and the MCP server, which is why `Cadence/Models/*` appears there by hand.

Nothing in the typography work needs a second target. If Codex ever believes a new file does, that
is the moment to stop and say so, because `project.pbxproj` is the single highest-collision file in
the repository and a merge there is not reviewable.

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
