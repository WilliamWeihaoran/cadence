# Decisions waiting on you

Six tickets were blocked on a product decision, not on work. Each has options, costs, what the
existing code already assumes, and a recommendation. Written 2026-08-30 against `5c5b124`, plus
T-780 on 2026-09-04.

## **One is still waiting: T-481.** Status re-read from the ledger, 2026-10-20

Every section below is kept whole, because a decision's reasoning is what a future reader comes
back for and because the answer is only legible beside the question it answered. What has changed
is the status line at the head of each: six of the seven are closed, and this file was still asking
for them.

| | State | What happened |
| --- | --- | --- |
| **T-481** | **OPEN — yours** | one top-level suite per test file. Still undecided; T-1076 was reserved to carry the verdict and the verdict was never written into it |
| T-352 | CLOSED `5ae916a` | recommendation *not* taken, and rightly: the premise inverted |
| T-487 | CLOSED `53e223c` | recommendation taken — `.byDoDate` deleted |
| T-489 | CLOSED `2a8a70a` | recommendation taken — swept app-wide |
| T-491 | CLOSED `dcd110c` | recommendation taken — page-scoped scrim kept |
| T-780 | CLOSED `hook4` | recommendation taken — hook landed inert; arming it is still one line and still yours |
| T-497 | ANSWERED `ab9e513` | answered 2026-09-02; its section records the answer |

Two of these were visual and **nobody had seen them on screen** when the recommendation was
written — that is stated where it applies, and it is why one of the two is held loosely.

**The second memo is also nearly spent.** `docs/DECISIONS_CALENDAR_LINKS_AND_LIST_DELETION.md`
covered T-623, T-624, T-899 and T-1043; all four are closed. What survives it is **T-1117**, the
five-minute test inside the app that was split out of T-624 so it stayed addressed to you. That
and T-481 are the whole of what either memo still wants.

---

## T-352 — should the root destination persist? **CLOSED 2026-08-31 (`5ae916a`)**

> **Answered by inverting the premise, and no persistence was added.** The defect was never a
> missing feature: it was the comment below, asserting a launch-restore mechanism that has never
> existed — `@SceneStorage` appears in zero of the 300+ files under `Cadence/`. The comment was
> rewritten with a tombstone naming the claim it replaced, and
> `CadenceRootSelectionLaunchContractTests` pins the contract. The options below are kept because
> they are what made "decline" a decision rather than an omission.

The recommendation when this was written was *static destinations only*.

The comment at `macOSRootSupportViews.swift:720` describing "an `.inbox` selection restored at
launch" is **wrong** — there is no restore path at all. Fix the comment whichever way you decide.

The app already persists everything *inside* a page (tasks scope, four sort/group keys, calendar
zoom, remembered timeline hour and date, goals mode and scale, sidebar width) and nothing about
*which* page. iPhone compact **does** persist its root; iPad regular does not. Same platform, two
answers by width.

- **Persist static destinations only** (Today, All Tasks, Inbox, Habits, Goals, Calendar, Notes,
  Focus) — ~30 lines. Static destinations cannot go stale, so this needs no new invariant and no
  interaction with the deletion machinery. **Recommended.**
- Persist list ids too — needs `initial: true` on both `SidebarSelectionNormalizer` `onChange`
  calls, or a restored id for a deleted list sails past it onto `MissingListDetailView`. Only worth
  it if you actually want to relaunch into a project.
- Decline — zero code, still needs the comment fixed.

## T-481 — one top-level suite per test file? **STILL OPEN — this is the one** *(Recommend: adopt with the 33 allowlisted)*

> The verdict was written once and never landed: `fa4b331` reserved T-1076 to carry it, T-1076 was
> closed for something else, and the body was never written. So this is undecided rather than
> decided-and-unfiled, and it is the only question in this file still addressed to you.

33 files hold 102 suites; 213 already obey the rule. It is a **ratchet, not detection** — measured
incidence of the defect is zero, but the failure is invisible: a test in the wrong sibling suite
means a scoped mutation run silently omits it, which reads as a survivor.

Do **not** mass-split. `private` file scope is load-bearing across the target — `sourceFile` is
declared privately in 31 files, `strippingComments` in 30, `repositoryRoot` in 29 — and 17 of the 33
share helpers between their sibling suites. Make the allowlist fail when stale so it drains without
anyone scheduling it.

## T-487 — delete `TasksPanel`'s `.byDoDate` mode? **CLOSED 2026-08-31 (`53e223c`) — deleted**

> Recommendation taken: `.byDoDate` deleted along with every branch, helper and view behind it.

Confirmed unreachable: the only `.byDoDate` panel in the repo is in a test. It is not a *planned*
All Tasks panel but a *replaced* one — All Tasks ships today via `TasksPageView`, a different view
with controls `.byDoDate` does not have.

It is not free: `TasksPanelDerivedState` computes `byDoDateBaseTasks` **and**
`byDoDateBaseSortedTasks` unconditionally, so every Today render sorts the full open-task set and
throws it away. It has already accumulated three pieces of wrong content — two retired strings and a
button labelled "New task for today" that opens an unseeded composer — precisely because no
reviewer could ever see it. Dropping the enum to one case makes the compiler do the migration.

If you want to keep the idea, delete the mode and file "should All Tasks get a do-date view?" as a
product ticket.

## T-489 — `.stroke` → `.strokeBorder` app-wide? **CLOSED 2026-09-03 (`2a8a70a`) — swept**

> Recommendation taken: swept app-wide wherever the shape is a border, as its own commit.

> **Not seen on screen.** Derived from source and documented SwiftUI geometry.

Not a new decision — an unfinished one. The shared components already use `.strokeBorder`, and
`CadenceSettingsWell`'s own doc names `.stroke` as the defect verbatim: *"straddles the edge, so the
well is 1pt wider than it measures."* Scope is **78 border sites**, not the ticket's 28; the other 45
`.stroke` uses are progress rings, `Path` dividers and chart lines where `.stroke` is correct.

What changes: **nothing reflows** (an overlay does not participate in layout). Each bordered
control's *painted* extent shrinks 0.5pt per side. Borders stop rendering as two half-point bands of
slightly different colour — most of these border colours are translucent — and read as one uniform
hairline. Where two bordered controls sit flush, the gap grows 1pt.

Land it alone so disliking it is a one-commit revert.

## T-491 — should the iPad capture scrim cover the sidebar? **CLOSED 2026-09-06 (`dcd110c`) — page-scoped kept**

> Recommendation taken, and the mechanism was verified rather than argued: `iPadMacStyleRootShell`
> clips `detail()` and the iPad capture host is mounted per page inside that clip, while the
> phone's is mounted on `iOSCompactRootShell`, which contains no `.clipped()` at all. The risk
> named below — that it might simply read as a rendering bug — did not materialise.

> **Not seen on screen**, and the recommendation is explicitly held loosely.

`Theme.scrim` is 34% black. On iPad it covers the detail column only, with a hard vertical edge at
the divider; on iPhone it covers everything. The mechanism is `iPadMacStyleRootShell`'s `.clipped()`,
which is load-bearing for a documented overflow bug, plus a `zIndex` the sidebar wins.

The `+` is a page-corner control with page-local state by explicit design — `iOSFloatingCreateTaskLayer`
holds its interaction per page so that only the page under the finger opens a composer, which is what
replaced the old drop-coordinator routing. And the scrim is `.allowsHitTesting(false)` on **both**
platforms, so it was never a barrier — the iPhone tab bar under its scrim is still tappable. Under
the T-282 rule (placement may differ across widths, capability may not), this is placement.

**The risk, stated:** a 34% wash with a hard edge down a 1024pt screen may simply read as a rendering
bug however defensible the reasoning. If it looks broken, take the full-window scrim — the argument
above is a justification, not a preference, and should not survive contact with the screen.

## T-780 — should a git hook refuse a bare `git commit` in this checkout? **CLOSED 2026-09-07 — landed inert**

> The hook is tracked and executable and changes nothing until you type the one line at the foot
> of this section. That was the answer: ship the code, leave the switch with you. Nothing further
> is owed unless you want it armed.

Added 2026-09-04. This one is about the agent tooling, not the product, and it is here because it
would change **your** git behaviour in your own repository — so it is not an agent's call.

**The problem.** `scripts/agent-commit.sh` is mandatory in prose only: it is a line in `AGENTS.md`
and a section in the runbook. That is exactly the shape T-679 was filed about. `git add <specific
paths>` was also prose, was also followed every time, and was also insufficient — the index is one
object shared by every agent in the checkout, so a bare `git commit` still works and still sweeps a
sibling's staged hunk into your commit. Nothing mechanical prevents it today.

**What a hook would do.** A tracked `.githooks/pre-commit`, with `core.hooksPath` pointed at it,
that exits non-zero unless `CADENCE_ALLOW_BARE_COMMIT=1` is set. Measured in a throwaway repository
on 2026-09-04:

- a bare `git commit` is **refused**, from the repo root and from a subdirectory;
- `git commit --amend` is **refused** too;
- `agent-commit.sh` is **unaffected** — it commits by `write-tree`/`commit-tree`/`update-ref`, and
  git runs no hooks for plumbing. This is the whole reason the hook can be strict;
- `git commit --no-verify` **bypasses it**, by design and unfixably.

`core.hooksPath` is already set explicitly in this checkout's `.git/config` (to the default
`.git/hooks`), so this is a one-line change to a value that is already non-default.

**What it costs you.** Every `git commit` and `git commit --amend` you type in this checkout is
refused once, until you use `--no-verify` or set the variable. Measured 2026-09-07 with the hook
armed in a throwaway repository: `merge --no-ff`, `cherry-pick`, `revert`, `rebase` and `stash` are
all unaffected — only `git commit` runs `pre-commit`. **The one exception is a conflicted merge**,
which you finish with a literal `git commit`, and which is therefore refused; `--no-verify` finishes
it. Some GUI git clients pass `--no-verify` themselves and would notice nothing. The refusal
message names both escapes, so the cost is one surprise, not a recurring one.

**The part that is not solved by the hook.** `core.hooksPath` lives in `.git/config`, which is not
tracked, so a fresh clone has no hook and nothing reminds anyone to install it — the same prose
problem one level down. The fix is for the tools every agent already runs (`scripts/xcb.sh`,
`scripts/agent-commit.sh`) to set `core.hooksPath` idempotently on each invocation, which costs one
`git config` call. That is the part that makes the hook real rather than aspirational, and it is
also the part that installs configuration into your repository without asking, which is why the
whole thing is here.

- **Install it, with both escapes named in the message** — the accident it stops (a swept sibling
  hunk) has happened; the determination it does not stop has not. **Recommended.**
- **Install it but gate on `CADENCE_AGENT_SESSION`**, so it only refuses when an agent session is
  marked active. Costs you nothing at all, and protects nothing during the sessions where nobody
  remembered to set the variable — which are the sessions where a bare `git commit` happens.
- **Decline** — zero code. The rule stays prose, and the next sweep is a matter of when.

**Status 2026-09-07: the hook is now in the repository, and it does nothing.** `.githooks/pre-commit`
is tracked, executable, and tested (25/25 checks in its own `selftest`, pinned from Swift by
`CadenceGuardScriptSelftestTests`, 4 of 4 mutations killed). Landing it changes **nothing** about
your `git commit` until you decide, because `core.hooksPath` is untracked local config. So the
decision above is now one line rather than a piece of work:

```sh
git config core.hooksPath .githooks     # arm it
git config --unset core.hooksPath       # take it back off
```

Nothing else in the repository sets that value, and `AGENTS.md` and the subagent runbook both now
tell agents in bold not to run it. That closes the "a fresh clone gets nothing" gap the only way
that does not install configuration into your repository unasked: the hook ships with the code, and
the one line that turns it on stays yours.

## T-497 Tier 3 — what does undo mean for a field the user still has focus in? **ANSWERED**

**Answered 2026-09-02. Decision: don't close, don't undo — just report.**

> The edit is **in-place on an object the store already holds**, so there is nothing to un-insert.
> Keep the surface open, keep what the user typed, show the failure inline, let them retry. The rule
> is broken here only because closing **claims** it worked — stop claiming it, and the undo question
> disappears.

So the question had no answer because it was the wrong question: an undo here would restore the
model out from under a live caret, deleting what the user typed in order to tell them it was not
saved. Landed in `ab9e513` across all four sites — `iOSSearchSupportViews`,
`iOSTaskDetailSheet.finishEditingAndDismiss` and `iOSMarkdownReferenceSupport` through the new
`CadenceInPlaceEditFlush`, which commits and answers and touches nothing else (and which
`CadenceTaskDateEditing.setPlanningDates` used too, because removing the sheet's literal `try?`
exposed a swallow one frame below it — deleted by [[T-4467]] once the sheet's draft save left it
caller-less); and
`KanbanCardMetaSupportViews.select`, which was never blocked and keeps the ordinary
`commitEdit(in:undo:)` repair because its popover holds no draft. Pinned by
`CadenceInPlaceEditFlushCommitTests`. See [[T-497]] in `docs/TODO.md` for the closure.
