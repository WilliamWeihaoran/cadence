# Decisions waiting on you

Six tickets are blocked on a product decision, not on work. Each has options, costs, what the
existing code already assumes, and a recommendation. Written 2026-08-30 against `5c5b124`.

Two are visual and **nobody has seen them on screen** — that is stated where it applies.

---

## T-352 — should the root destination persist? **Recommend: static destinations only**

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

## T-481 — one top-level suite per test file? **Recommend: adopt with the 33 allowlisted**

33 files hold 102 suites; 213 already obey the rule. It is a **ratchet, not detection** — measured
incidence of the defect is zero, but the failure is invisible: a test in the wrong sibling suite
means a scoped mutation run silently omits it, which reads as a survivor.

Do **not** mass-split. `private` file scope is load-bearing across the target — `sourceFile` is
declared privately in 31 files, `strippingComments` in 30, `repositoryRoot` in 29 — and 17 of the 33
share helpers between their sibling suites. Make the allowlist fail when stale so it drains without
anyone scheduling it.

## T-487 — delete `TasksPanel`'s `.byDoDate` mode? **Recommend: delete**

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

## T-489 — `.stroke` → `.strokeBorder` app-wide? **Recommend: sweep all 78, as its own commit**

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

## T-491 — should the iPad capture scrim cover the sidebar? **Recommend: declare page-scoped correct**

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

## T-497 Tier 3 — what does undo mean for a field the user still has focus in?

Two sites left: `iOSSearchSupportViews` (note editor Done) and
`iOSTaskDetailSheet.finishEditingAndDismiss`. Both are "flush an in-place edit, then close". Tier 2's
inline row editors were the easy half — they hold their drafts in `@State`, so restoring the model
does not fight a caret. These two do. Answer it once and both fall out.
