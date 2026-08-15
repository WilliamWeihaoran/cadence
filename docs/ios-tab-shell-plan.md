# iOS compact shell: replacing the Home grid with a tab bar

Agreed with the user on 2026-08-15. **Landed.** Kept as the design record; where it and the code
disagree, the code wins — see `Cadence/iOS/AGENTS.md` for what is actually there.

Three things changed during the build, all at the user's direction:

- **Tasks → Today has no "up next" hero.** The plan gave Today an up-next item with *Start focus*
  and *Done* acting on it in place. It was built and then cut: it was one task promoted above the
  list that already contained it, and its two buttons were tinted red and green for no reason a
  reader could name. `CadenceHomeSummarySupport`'s `todayStats` / `nextAction` /
  `nextActionDetail` went with it (git history has them); the greeting, the date and the habit
  fraction survive in `CadenceCompactShellSupport`.
- **Tasks → Today has no capture bar.** Capture is the bar's centre `+`, which is the point of
  putting it there. The capture bars on All Tasks, Inbox, list detail and iPad Today all stay.
- **The bar is a `VStack` sibling of the content, not a `safeAreaInset`.** See the note in
  `Cadence/iOS/AGENTS.md`; the inset measured as nothing on screens that paint
  `Theme.bg.ignoresSafeArea()` behind their scroll view.

## What is actually there today

`Cadence/iOS/` contains **no `TabView` at all**. Both `CLAUDE.md` and `Cadence/iOS/AGENTS.md`
describe a "compact `TabView` shell"; that is stale and should be corrected when this lands.

The real compact shell is `iOSCompactRootShell` — a single `NavigationStack` bound to one
`NavigationPath`, rooted at `iOSCompactHomeView`, which is a grid of eight tiles. Every feature is
a push onto that one path.

This is why the Home screen kept failing review. It is not a badly designed home screen; it is a
substitute for navigation the app does not have. Because there is no bar, you must return to Home
to reach anything, and because Home must therefore list everything, six of its eight tiles are
silent boxes carrying no information. Restyling it cannot fix that.

## Target

A bottom bar with four tabs and a centre capture button:

```
[ Tasks ]  [ Calendar ]  ( + )  [ Notes ]  [ More ]
```

- **Tasks** — the default tab; the app opens here. A segmented switcher in its header selects
  **Today / All / Inbox**, the same pattern Calendar already uses for Week/Month/Board, so the two
  tabs are learned once.
  - **Today** absorbs the content the Home screen was reaching for: an "up next" item with
    *Start focus* and *Done* acting on it in place, then overdue, then the rest of the day.
  - **All** keeps the existing sort and grouping controls.
  - **Inbox** keeps its inline capture bar — faster than a sheet for a burst of entries.
- **Calendar** — unchanged content, now a tab.
- **`+`** — the centre control opens task capture. It is **not** a tab: it presents, it does not
  select. Today the floating `+` exists only on Home, so from most screens you cannot capture
  without navigating away first.
- **Notes** — unchanged content, with the `n-a1` header (title and tabs on one row).
- **More** — Focus, Lists, Goals, Habits, Search, Settings, grouped under quiet eyebrows.

`iOSCompactHomeView` is deleted. `CadenceHomeSummarySupport`'s greeting/stat/next-action logic
moves to Tasks → Today rather than being thrown away.

## What makes this a rewrite rather than a restyle

1. **One path becomes four.** Each tab needs its own `NavigationPath` so switching tabs preserves
   where you were. `compactPath` is currently a single type-erased `NavigationPath`; note the
   comment on it — a homogeneous `[CadenceFeatureDestination]` silently discards a
   `NavigationLink(value:)` of any other type, which was a real bug. Keep it type-erased per tab.
2. **Deep links and widget routing.** `CadenceDeepLink` / `CadenceDeepLinkManager` and the widget
   intents currently push onto the one path (see the `compactPath = NavigationPath([...])`
   assignments in `iOSRootView`). Every one has to resolve to *(tab, path)* instead. A deep link
   that lands on the wrong tab, or that pushes onto a tab the user is not looking at, is the
   obvious failure here.
3. **`CadenceFeatureDestination` gains a tab mapping.** Eleven cases must each answer "which tab
   owns me". Put that mapping in `Shared/` with tests — `Cadence/iOS/` is inside `#if os(iOS)` and
   invisible to the macOS-built `CadenceTests`.
4. **iPad is untouched.** `iPadMacStyleRootShell` keeps its sidebar. This is compact width only.
5. **Restore state across launches.** The selected tab should persist, like
   `ios.calendar.anchorDateKey` does — and note the lesson from `ecaf80f`: a persisted navigation
   value written from a bad initial reading compounds across launches.

## Risks worth naming before starting

- The `+` in the middle of a bar of tabs is not a tab, and users reasonably expect bar items to
  select. It must look distinct (filled circle, no label) and must never show a selected state.
- Search currently lives as a magnifier on Home, which will not exist. The plan keeps a magnifier
  in the Tasks header *and* a Search row under More; if that reads as two entry points for one
  thing, cut the More row.
- Anything currently reachable only from Home must be checked off explicitly. Enumerate all eleven
  `CadenceFeatureDestination` cases and prove each is reachable after the change.

## Landing it

Its own commit, after the other work, so there is a clean thing to revert if the shell misbehaves.
Verify on a simulator through Claude Code's own tooling only, and tap every tab, the `+`, each
Tasks sub-view, and at least one deep link.
