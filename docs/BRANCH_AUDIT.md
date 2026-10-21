# Local branch audit — what every unmerged branch still holds

Agent `branchaudit`, 2026-10-21, read-only, filed as [[T-3271]]. Measured at `main` `611f263f`
(`e66916cd` plus this audit's own stub). **Nothing on any branch was touched**: no checkout, no
reset, no rebase, no merge, no delete. This file recommends; the owner decides.

## Why the question needs an audit at all

`git rev-list --count main..<branch>` answers "does this branch carry commits `main` does not",
and it answers it wrong for this purpose. Landing a branch in this repository does not mutate the
branch — a coordinator rebuilds the hunks onto `main` as a fresh commit — so a fully landed branch
keeps every commit it ever had and reads as "ahead" forever. `docs/SESSION_HANDOFF.md` records this
for `codex/unified-editors`: 9 commits ahead after T-3238 landed its work, deliberately.

A blob comparison is no better. `git diff main:<path> <branch>:<path>` on a branch cut weeks ago
differs in both directions, and on these branches the larger side is almost always `main`'s own
later work. **Never three-dot `git diff main...<branch>`** — it shows what the branch added since
the merge base, never what `main` is missing; `docs/CODEX_WORKTREE.md` records six corrections from
getting that backwards.

The test used here is the one that answers the real question:

```sh
git log --no-merges --format=%H main..<branch> -- <path>   # the branch's OWN commits on that path
git show <sha> -- <path> | grep '^+[^+]'                    # the lines those commits ADDED
```

and then: is each of those lines present in `main`'s copy of that path? Every added line present
means the content landed, whatever the commit graph says. The second measurement, which decides
whether a LIVE branch can still be applied, is how much `main` changed underneath it:
`git rev-list --count $(git merge-base main <branch>)..main -- <path>` for every path the branch
touches. A branch `main` has not touched on any of its paths applies cleanly; one where `main` has
moved seven times does not.

Both were run over all 46 branches. The per-line test is a heuristic in one direction only: a line
counted "present" could sit in a different context in `main`, so **a SPENT verdict is the one to
distrust**, and each SPENT below is backed by a ledger state as well as the line count.

## The measurement

At `e66916cd` the tree held **92 local branches, 46 with zero commits `main` lacks and 46 with
commits `main` lacks**. (The brief this audit was written from said 89 / 40 / 49; the 49 is not
reproducible at `e66916cd` by any counting this audit could construct, and the figure below is the
measured one.) Four of the 46 also exist on `origin` at the identical sha — `gh-pages`,
`recovered-2026-08-25`, `heartbeat/t1475-ios-timeline-drag`, `heartbeat/t1479-mac-context-menu` —
so **42 exist only on this disk**.

`added` below is every line the branch's own commits added across all its paths; `absent` is how
many of those are not in `main`'s copy, with the count outside `docs/` in brackets, since a
differing `docs/TODO.md` or `docs/CODEX_LEDGER_INBOX.md` line is usually just the coordinator
rewriting the ledger entry at landing and never means unlanded work.

| branch | last commit | ahead | behind | absent/added | verdict | what it holds |
| --- | --- | ---: | ---: | --- | --- | --- |
| `recovered-2026-08-25` | 2026-08-25 | 1 | 1556 | 560/3827 (560) | SUPERSEDED | Deliberate recovery dump, its own subject line says "NOT for main". All 53 paths rewritten on `main` since; `Cadence/iOS/iOSCalendarBundleDetailSheet.swift` was **deleted** on `main` by T-3170's eleventh pass. On `origin`. |
| `gh-pages` | 2026-09-05 | 1 | 2060 | 101/101 (101) | LIVE, never for `main` | The orphan GitHub Pages branch: `privacy.html` + `support.html`, the two pages App Review reads. Absent from `main` by design. On `origin`. |
| `codex/archive-large-text-20261002` | 2026-09-27 | 2 | 818 | 23/894 (23) | SPENT | T-1440/T-1441/T-1442 all CLOSED. `main` is larger on every one of the 18 paths (e.g. `CadenceTaskGroupHeading.swift` +90/-31); the 23 are the branch's older spellings. |
| `codex/archive-typography-20261002` | 2026-09-29 | 3 | 761 | 27/750 (27) | SPENT | T-1453 CLOSED, landed by `codexland`. `main` ahead on all 31 paths. |
| `codex/context-budget` | 2026-10-02 | 1 | 711 | 13/127 (13) | SPENT | T-1454 CLOSED. The 12 `CLAUDE.md` lines are the pre-T-3248 routing text that `9b94c28e` rewrote. |
| `codex/calendar-day-drop-commit` | 2026-10-02 | 3 | 706 | 54/754 (44) | SPENT | T-1980 CLOSED 2026-10-02 (T-1455 was never filed as an id). `main` larger on all 7 paths. |
| `codex/save-report-closure-detector` | 2026-10-02 | 3 | 695 | 0/521 (0) | SPENT | Every one of 521 added lines is in `main`. |
| `codex/search-widget-followups` | 2026-10-04 | 4 | 646 | 57/679 (57) | SUPERSEDED | T-1458 PARTIAL. 21 of the 57 are in `CadenceWidgets/HabitCheckInWidget.swift` and `MilestoneMomentumWidget.swift`, which **T-2078 deleted from `main`** — landing this resurrects two retired widgets and the `ToggleHabitCompletionIntent` that closure was about. The search half is spent. |
| `codex/sidebar-drawer` | 2026-10-05 | 3 | 627 | 18/317 (0) | SPENT | T-1464 CLOSED. Nothing absent outside `docs/CODEX_WORKTREE.md` lease lines. T-1463 is still PARTIAL but on `main`'s own two on-screen cases, not on this branch. |
| `codex/continuous-quote-rail` | 2026-10-05 | 2 | 627 | 15/303 (0) | SPENT | T-1465 CLOSED. Absent lines are lease entries only. |
| `codex/tracking-ui-retirement` | 2026-10-05 | 2 | 625 | 11/267 (11) | SPENT | T-1466 CLOSED. `main` ahead on all 22 paths. |
| `codex/data-safety-audit-fixes` | 2026-10-05 | 7 | 610 | 3/699 (3) | SPENT | T-3003 CLOSED at `52a6b408`. `PersistenceController.swift` is 845 lines larger on `main`. |
| `codex/task-list-virtualization` | 2026-10-06 | 2 | 601 | 5/100 (5) | SPENT | T-3004 CLOSED at tip `1b187f9e`. |
| `codex/kanban-rendering` | 2026-10-06 | 2 | 585 | 3/341 (3) | SPENT | T-3005 CLOSED at tip `05de6408`. |
| `codex/typography-lifecycle-batch` | 2026-10-07 | 5 | 547 | 4/482 (4) | SPENT | T-3011 CLOSED; T-2054/T-168 stayed PARTIAL on `main`'s terms. `iOSFocusView.swift` is +212/-14 on `main`. |
| `codex/leased-followup-batch` | 2026-10-07 | 2 | 521 | 0/233 (0) | SPENT | All 233 added lines are in `main`. |
| `codex/parity-functional-batch` | 2026-10-09 | 8 | 450 | 29/556 (7) | SPENT | T-3031, T-3077, T-3086 all CLOSED by `codexland5`. 22 of the 29 are inbox entries folded into the ledger at landing. |
| `codex/mobile-project-deadline` | 2026-10-09 | 1 | 442 | 5/55 (0) | SPENT | T-3091 CLOSED at `4569996f`. Only its inbox entry differs. |
| `codex/phone-capture-hold` | 2026-10-12 | 3 | 397 | 41/276 (13) | SPENT | T-3147 PARTIAL, landed by `holdland` at `f51234ec`. 28 of 41 are inbox; `CadenceCapturePaletteUITests.swift` is 88 lines larger on `main`. |
| `codex/phone-capture-load` | 2026-10-12 | 1 | 391 | 19/148 (3) | SPENT | Same T-3147 measurement, superseded by `codex/phone-capture-hold` before landing. |
| `codex/platform-parity-audit` | 2026-10-16 | 1 | 313 | 24/356 (0) | SPENT | `docs/PLATFORM_PARITY_AUDIT.md` landed, and `main` then added 87 lines to it (T-1467..T-1474 filed from it, PA-01/02 closed by T-3221). |
| `codex/ui-refresh-reconciliation` | 2026-10-16 | 2 | 302 | 17/248 (0) | SPENT | T-3157 PARTIAL on `main`. Nothing absent outside the inbox; all 15 product and test paths are 0/N. |
| `codex/ios-board-drop-refusal` | 2026-10-17 | 1 | 290 | 7/197 (7) | SPENT | PA-13 fix landed: every product-source line is in `main`. The 7 are older assertions in two test files `main` has since grown. |
| `heartbeat/t1479-mac-context-menu` | 2026-10-17 | 1 | 275 | 16/497 (16) | SPENT | T-1479 CLOSED 2026-10-17 by `parkedland`, then `main` refactored `MacTaskRowContextMenu.swift` further (+66 on `main`'s side). On `origin`. |
| `heartbeat/t1475-ios-timeline-drag` | 2026-10-17 | 1 | 273 | 5/695 (5) | SPENT | T-1475 CLOSED 2026-10-17. `iOSCalendarTimelineViews.swift` is 303 lines larger on `main`. On `origin`. |
| `codex/mobile-calendar-notes-parity` | 2026-10-17 | 4 | 261 | 11/519 (11) | SPENT | T-1468, T-1471, T-1472, T-1483 all CLOSED 2026-10-18. The 11 are month-chip spellings `main` replaced. |
| `heartbeat/t3170-trio-parked` | 2026-10-17 | 1 | 240 | 9/411 (9) | SPENT | `main`'s `CadenceCommentSymbolClaimTests.swift` is 438 lines richer after T-3209's rewrite; the 9 are claim-ledger strings that rewrite replaced. |
| `codex/capture-list-sections` | 2026-10-17 | 6 | 238 | 53/1281 (53) | SPENT | T-3195 CLOSED — the card shipped at Codex `8f33d5ce` via `captureland`. `CadenceScheduleCaptureCard.swift` has changed 7 more times on `main` and is 396 lines larger; the 42 absent lines there are the pre-landing shape. |
| `codex/unified-editors` | 2026-10-19 | 9 | 144 | 32/456 (32) | SPENT | T-3238 CLOSED at `0c3cfff9`, landed by `editorland`. This is the branch `docs/SESSION_HANDOFF.md` already names as intentionally-ahead-after-landing. The card moved 6 more times on `main` since. |
| `codex/text-scale-finish` | 2026-10-20 | 2 | 58 | 2/754 (0) | SPENT | T-1364 CLOSED 2026-10-20 at `7ed…`. The 2 are its own ledger lines, rewritten at landing. |
| **`codex/block-removal-finish`** | 2026-10-20 | 5 | 48 | 120/120 (107) | **LIVE** | T-3170's and T-3214's Block retirement. Three whole test suites absent from `main` (`CadenceCodexTimelineBlockRemovalTests`, `…CalendarBlockRemovalTests`, `…BlockMoveRemovalTests`) plus the removal of the retired Block plumbing from 11 macOS sources. **`main` has not touched 19 of its 20 paths since the merge base.** |
| **`worktree-agent-aac002c373297566b`** | 2026-10-20 | 2 | 73 | 193/193 (0) | **LIVE** | The Codex fence freedom audit: `docs/audits/2026-10-20/codex-fence-freedom.md` (185 lines) does not exist on `main`, and **its ticket T-3255 was never filed** — `ledger-view.sh head T-3255` refuses. |
| **`worktree-agent-a4a48572d11821d04`** | 2026-10-20 | 1 | 75 | 128/163 (126) | **LIVE** | T-3171's eighth adoption slice: the Today timeline's drag-create Add creates in place (`QuickCreateChoicePopover.swift` +59, `SchedulePanel.swift` +31, `CadenceQuickCreateTaskInspectorTests.swift` +81). T-3171 is PARTIAL on `main` at the **seventh** slice. **`main` has touched none of its 3 paths since the merge base.** |
| **`worktree-agent-aff2a0732e89bd582`** | 2026-10-20 | 1 | 71 | 11/12 (10) | **LIVE, do not merge** | T-3170's sixteenth pass: the `TaskCreationService.swift` stale Block claim, taking `staleClaims` 11 → 10. `main` still asserts 11. But the branch also carries `tombstones.count == 48` where `main` is at 50 (T-3197) — **apply the two hunks by hand, a merge regresses**. Overlaps `codex/block-removal-finish`, which makes the same fix with the same tombstone staleness. |
| `worktree-agent-a945a3ea3ee375a3c` | 2026-10-20 | 1 | 57 | 0/101 (0) | SPENT | T-3252 PARTIAL on `main`, naming this branch. Every added line is in `main`. |
| `worktree-agent-aa5788bb664ad8626` | 2026-10-20 | 2 | 57 | 0/102 (0) | SPENT | T-3221, T-3235 CLOSED, landed at `99e009b2`. |
| **`worktree-agent-a63166411fae66556`** | 2026-10-20 | 3 | 49 | 6/6 (4) | **LIVE — highest value per line** | Four lines in `CadenceTests/CadenceCodexCaptureSectionBatchTests.swift` that re-point two source-shape pins at the card as it now stands. See "A red on `main`" below. **`main` has not touched that path since the merge base.** |
| `worktree-agent-ab8c3d3d643d7df1e` | 2026-10-20 | 2 | 56 | 0/14 (0) | SPENT | T-3217, T-3223 CLOSED. |
| `worktree-agent-aba0b38d90accc927` | 2026-10-20 | 1 | 57 | 0/1 (0) | SPENT | T-3166 PARTIAL, landed by `n10land` at `2e9ffe9c`. |
| `worktree-agent-ab002a9ca8c25dbd3` | 2026-10-20 | 1 | 57 | 0/2 (0) | SPENT | T-3195 CLOSED, landed from this branch at `2e9ffe9c`. |
| `worktree-agent-acdc97173769963c3` | 2026-10-20 | 3 | 7 | 2/257 (0) | SPENT | Landed at `2e9ffe9c`. The 2 absent lines are the id: the branch filed T-3263, the landing renumbered it T-3266. |
| `worktree-agent-ab7523899b87b5e04` | 2026-10-20 | 1 | 57 | 2/187 (1) | SPENT | T-3200/T-3247 landed at `e66916cd`. The 1 source line is a test renamed at landing (`theRunningProcessIsItselfOutsideTheGate` → `theRunningProcessAsksForNoLaunchPage`, T-3268); the ledger line was renumbered T-3261 → T-3269. |
| **`claude/magical-davinci-7648a2`** | 2026-10-20 | 1 | 10 | 104/104 (1) | **LIVE** | `docs/audits/README.md` (98 lines) — an index of the 47 dated audit files saying which are still cited — does not exist on `main`, and neither do its two routes in `CLAUDE.md` and `docs/CONTEXT_INDEX.md`. **`main` has touched none of its 3 paths since the merge base.** |
| `worktree-agent-a200d80eda5458be2` | 2026-10-20 | 2 | 57 | 3/100 (0) | SPENT | T-3253 PARTIAL, landed at `cdd5ec21`. All source lines present; the 3 are ledger-line rewrites. |
| `worktree-agent-af0ea48e0159bda6b` | 2026-10-20 | 1 | 4 | 0/19 (0) | SPENT | T-3244 PARTIAL, landed at `5702d393`. |
| `claude/festive-zhukovsky-e44f65` | 2026-10-21 | 1 | 0 | 1/1 (0) | **LIVE, in flight** | 0 behind `main`. Agent `scantriage`'s T-3260 triage addendum, written today and not yet landed. A live session's branch, not a leftover. |

## A red on `main` that one of these branches fixes

`worktree-agent-a63166411fae66556` is four lines and it is the most valuable thing in this audit.

T-3254 is **OPEN** on `main` and says `claude/quizzical-lovelace-df2874` was left unlanded because
merging it would redden two source-shape pins. That is no longer the situation: the branch's tip is
an **ancestor of `main`**, so the capture card's new shape did land — and the pins did not move
with it. `main` now holds a card and a test that disagree:

| `main`'s `CadenceScheduleCaptureCard.swift` | `main`'s `CadenceCodexCaptureSectionBatchTests.swift` |
| --- | --- |
| `:625` `EstimatePickerPopoverContent(value: estimateBinding,` | `:21` `#expect(card.contains("EstimatePickerPopoverContent(value: Binding("))` |
| `:371` `let dates = fields.filter { … }` / `:373` `let rest = fields.filter(restCarriesChip)` | `:68` `#expect(card.contains("let chips = fields.filter(isSet)"))` |

Both assertions read a card that no longer contains those strings. The branch carries exactly the
two replacements T-3254 asks for, and `main` has not touched that file since. This audit did not
run tests (it was scoped to need no test host), so the red is read off the two sources rather than
seen fail — but the strings are absent from `main`'s card at 0 occurrences each.

## (a) Branches that can be deleted safely

**None of them, on this audit's evidence, and the recommendation is to delete nothing.** 42 of the
46 exist only on this disk, deletion is irreversible, and the entire cost of keeping them is disk
space. What the evidence does support is a weaker and more useful statement: **37 of the 46 hold no
line `main` lacks that anyone still wants**, so losing them would cost nothing but history.

Those 37 are every row above marked SPENT, plus the two SUPERSEDED. Each is backed by two
independent facts: a CLOSED or landed ledger state for the ticket it was written under, and a line
count showing either 0 lines absent from `main` or absences confined to the branch's own older
spelling of code `main` has since moved past. The two SUPERSEDED ones carry a third fact and are
the ones where landing would actively hurt:

- `codex/search-widget-followups` edits `CadenceWidgets/HabitCheckInWidget.swift` and
  `MilestoneMomentumWidget.swift`, both **deleted from `main` by T-2078**. T-2078's whole point was
  that the surviving `ToggleHabitCompletionIntent` would keep offering a habit write in Shortcuts
  with no Cadence surface behind it. Reviving these files revives that.
- `recovered-2026-08-25` says "NOT for main" in its own subject and edits a file `main` deleted.

**If the owner wants the disk back anyway**, the safe order is: push them to `origin` first (they
cost nothing there and the disk-failure risk disappears), and only then delete locally. A push is
reversible; a delete is not.

## (b) Branches holding work that should be landed, ranked by value

1. **`worktree-agent-a63166411fae66556`** — four lines, fixes what reads as a red on `main`, closes
   T-3254, no churn underneath it. Cheapest and most valuable thing here. The file is Codex-leased,
   so it needs the grant T-3254 already describes, or a Codex pass.
2. **`codex/block-removal-finish`** — the largest genuinely unlanded body of work: T-3170's and
   T-3214's Block retirement, three new test suites and the removal of retired plumbing from 11
   macOS sources, with `main` untouched on 19 of 20 paths. T-3214 is PARKED as *decided, retire
   now*, so the decision this is waiting on has already been made. **Its one stale hunk is
   `CadenceCommentSymbolClaimTests.swift`, which asserts `tombstones.count == 48` where `main` is
   at 50** — take `main`'s 50 and the branch's `stale.count == 10`.
3. **`worktree-agent-a4a48572d11821d04`** — T-3171's eighth adoption slice, 126 lines across three
   paths `main` has not touched. T-3171 is PARTIAL at the seventh slice, so this is the next step
   of work already in progress rather than a new direction.
4. **`claude/magical-davinci-7648a2`** — `docs/audits/README.md`, the index that makes the 47-file
   audit folder answerable without opening it, plus its two routes. Pure documentation, zero
   conflict risk, and it directly serves the context-budget rules in `CLAUDE.md`.
5. **`worktree-agent-aac002c373297566b`** — the fence freedom audit. Its finding (all 108 fence
   lines FREE; the T-3210 "REAL unlanded work" claim at `iOSTaskRowActionViews.swift` refuted) is
   evidence the lease process will want again, and **T-3255 was never filed**, so right now nothing
   in the ledger points at it.
6. **`worktree-agent-aff2a0732e89bd582`** — subsumed by (2). If `codex/block-removal-finish` lands,
   this is spent; if it does not, these two hunks are still worth taking by hand.
7. `gh-pages` and `claude/festive-zhukovsky-e44f65` are not candidates: the first never merges to
   `main`, the second is a session still working.

## One side finding, not a branch verdict

T-1451 is **OPEN** on `main` and reads "on `codex/task-page-typography-finish` at `20e96c2f`, NOT
landed". That branch's tip `c218b6c9` **is an ancestor of `main`** (0 commits ahead), and the sha
`20e96c2f` the entry names is not reachable from `main` at all. So either the ticket is stale or it
is parked on a commit that no longer exists on any reachable ref. It is out of this audit's 46
because the branch is not ahead, and it is recorded here because it is the same class of error the
brief warns about — a ticket parked on a condition that stopped being true.
