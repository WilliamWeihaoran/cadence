# iOS compact shell: replacing the Home grid with a tab bar — **LANDED, kept as the design record**

Agreed with the owner on 2026-08-15; built and landed. **Where this and the code disagree, the code
wins** — `Cadence/iOS/iOSCompactTabShell.swift` is the shell, `Cadence/iOS/AGENTS.md` says what is
actually there, and `Cadence/Shared/CadenceCompactTab.swift` owns the tab enum.

Nothing in the repository links here. It is kept anyway, because the decisions below are the ones a
future reader comes back for, and three of them were made *against* this plan.

Re-checked against the tree 2026-10-20: all five of the hard parts named under *"What makes this a
rewrite"* landed. Each tab holds its own path (`iOSCompactTabPaths`), the tab mapping lives in
`Cadence/Shared/CadenceCompactTab.swift` with `CadenceCompactTabTests` beside it where the macOS
test target can see it, the selected tab persists through `@AppStorage("ios.compact.selectedTab")`,
and the iPad shell was left alone. One nuance the plan did not anticipate and the code did: this is
a **custom** four-tab bottom bar, not a SwiftUI `TabView` — so "the app contains no `TabView`",
which this file used to flag as the problem, is still literally true and is now deliberate.

## What it replaced

A single `NavigationStack` bound to one `NavigationPath`, rooted at `iOSCompactHomeView`: a grid of
eight tiles, every feature a push onto that one path.

The grid kept failing review, and the reason is the part worth keeping. It was not a badly designed
home screen; it was a substitute for navigation the app did not have. With no bar you had to return
to Home to reach anything, and because Home therefore had to list everything, six of its eight tiles
were silent boxes carrying no information. Restyling could not fix that, and three rounds of trying
is what produced the bar.

## The design that was agreed

```
[ Tasks ]  [ Calendar ]  ( + )  [ Notes ]  [ More ]
```

- **Tasks** — the default tab; the app opens here. A segmented switcher in its header selects
  **Today / All / Inbox**, the same pattern Calendar already uses for Week/Month/Board, so the two
  are learned once. **All** keeps the existing sort and grouping controls; **Inbox** keeps its
  inline capture bar, faster than a sheet for a burst of entries.
- **Calendar** — unchanged content, now a tab.
- **`+`** — the centre control opens task capture. It is **not** a tab: it presents, it does not
  select. Before this, the floating `+` existed only on Home, so from most screens you could not
  capture without navigating away first.
- **Notes** — unchanged content, with the `n-a1` header (title and tabs on one row).
- **More** — Focus, Lists, Goals, Habits, Search, Settings, grouped under quiet eyebrows.

`iOSCompactHomeView` was deleted. `CadenceHomeSummarySupport`'s greeting and stat logic moved to
Tasks → Today rather than being thrown away.

## Three things changed during the build, all at the owner's direction

This is the part the code cannot tell you: what was designed, built, and then cut.

- **Tasks → Today has no "up next" hero.** The plan gave Today an up-next item with *Start focus*
  and *Done* acting on it in place. It was built and then cut: it was one task promoted above the
  list that already contained it, and its two buttons were tinted red and green for no reason a
  reader could name. `CadenceHomeSummarySupport`'s `todayStats` / `nextAction` / `nextActionDetail`
  went with it (git history has them); the greeting, the date and the habit fraction survive in
  `CadenceCompactShellSupport`.
- **Tasks → Today has no capture bar.** Capture is the bar's centre `+`, which is the point of
  putting it there. The capture bars on All Tasks, Inbox, list detail and iPad Today all stay.
- **The bar is a `VStack` sibling of the content, not a `safeAreaInset`.** See the note in
  `Cadence/iOS/AGENTS.md`; the inset measured as nothing on screens that paint
  `Theme.bg.ignoresSafeArea()` behind their scroll view.

## What made this a rewrite rather than a restyle

All five landed; they are kept because each names a failure mode that is cheap to re-introduce.

1. **One path became four.** Each tab needs its own `NavigationPath` so switching tabs preserves
   where you were. Keep it type-erased per tab: a homogeneous `[CadenceFeatureDestination]`
   silently discards a `NavigationLink(value:)` of any other type, which was a real bug.
2. **Deep links and widget routing.** `CadenceDeepLink` / `CadenceDeepLinkManager` and the widget
   intents pushed onto the one path. Every one had to resolve to *(tab, path)* instead. A deep link
   that lands on the wrong tab, or pushes onto a tab the user is not looking at, is the obvious
   failure.
3. **`CadenceFeatureDestination` gained a tab mapping.** Eleven cases each answer "which tab owns
   me". It lives in `Shared/` with tests, because `Cadence/iOS/` is inside `#if os(iOS)` and
   invisible to the macOS-built `CadenceTests`.
4. **iPad is untouched.** `iPadMacStyleRootShell` keeps its sidebar. This is compact width only.
5. **State restores across launches.** The selected tab persists, like `ios.calendar.anchorDateKey`
   does — and note the lesson from `ecaf80f`: a persisted navigation value written from a bad
   initial reading compounds across launches.

## Risks that were named before starting

- The `+` in the middle of a bar of tabs is not a tab, and users reasonably expect bar items to
  select. It must look distinct (filled circle, no label) and must never show a selected state.
- Search used to live as a magnifier on Home, which no longer exists. The plan kept a magnifier in
  the Tasks header *and* a Search row under More; if that reads as two entry points for one thing,
  cut the More row.
- Anything reachable only from Home had to be checked off explicitly — all eleven
  `CadenceFeatureDestination` cases enumerated and each proven reachable after the change.
