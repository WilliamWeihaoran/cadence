# iOS Guide

The iOS/iPadOS app is a large, actively-developed surface (68 files covering Today, Calendar, Tasks, Focus, Goals, Habits, Notes, Lists, Search, Settings) — not early/stubbed. Do not assume macOS feature parity by default; check the actual view file.

## Working Rules

- Keep iOS-specific UI in this subtree.
- Use shared models/services/components where appropriate, but avoid importing macOS-only managers or AppKit assumptions.
- This is real, shipping UI — treat changes here with the same care as macOS, not as placeholder work.
- When adding real iOS behavior, check shared SwiftData models and platform conditionals carefully.

## Current State

The macOS app is the primary product surface. iOS is a large, real, actively-developed surface. `iOSRootView.swift` is an adaptive root shell: `iPadMacStyleRootShell` (sidebar) at regular width, `iOSCompactRootShell` (bottom tab bar) at compact width, routing to full implementations of most macOS feature areas.

## The iPhone tab shell

Earlier versions of this file and of `CLAUDE.md` described a "compact `TabView` shell". That was
wrong — there was no `TabView` anywhere in this folder. The compact shell was one `NavigationStack`
over one `NavigationPath`, rooted at `iOSCompactHomeView`, a grid of eight tiles that existed only
because there was no bar. `iOSCompactHomeView` is deleted. What is actually here now:

- **`iOSCompactTabShell.swift`** — `iOSCompactRootShell`, the bar, the capture button, the quick
  capture sheet, and `iOSCompactTabPaths`. Four tabs and a centre `+`:
  `[ Tasks ] [ Calendar ] ( + ) [ Notes ] [ More ]`.
- **The `+` is not a tab.** It presents; it never selects. `CadenceCompactTab` has four cases on
  purpose, so no code path can hand it a selected state.
- **One `NavigationPath` per tab, each type-erased.** A homogeneous
  `[CadenceFeatureDestination]` silently discards a `NavigationLink(value:)` of any other type —
  that shipped once, and made every Lists row dead. Four paths, four chances to repeat it.
- **The bar is a sibling of the content in a `VStack`, not an overlay and not a
  `safeAreaInset`.** `safeAreaInset(edge: .bottom)` was tried first and came back as no inset at
  all on screens that paint `Theme.bg.ignoresSafeArea()` behind their scroll view: the last row of
  All Tasks sat under the bar at full scroll. Do not reintroduce per-screen bottom padding to
  compensate for the bar; the layout is what guarantees the clearance.
- **Tabs are built on first visit and kept alive** (`visitedTabs`), which is what preserves scroll
  position and in-progress edits across a tab switch. A cold launch builds Tasks only.
- **`Cadence/Shared/CadenceCompactTab.swift`** owns the routing table — which tab owns each
  `CadenceFeatureDestination`, which Tasks segment, and what a `CadenceDeepLink` resolves to. It
  lives in `Shared/` because this folder is inside `#if os(iOS)` and invisible to the macOS-built
  `CadenceTests`. `CadenceCompactTabTests` pins that every destination is either a tab root or a
  More row, so nothing can become unreachable.
- **iPad regular width is untouched.** All of the above is compact width only.
