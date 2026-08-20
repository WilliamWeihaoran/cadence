# Shared Guide

This folder contains cross-platform design tokens, shared components, hover styles, date/time
helpers, and the `Cadence*Support.swift` presentation/query/mutation layer that both platforms
build their feature views on top of.

## Theme Is The Only Source Of Colour

`Theme.swift` holds one fixed near-black dark palette — there is no theme picker and no light
variant (`ThemeManager` and its seven themes were removed). Read the file before adding a colour;
it already has named tokens for the jobs call sites keep re-inventing:

- Neutral ramp: `bg`, `surfaceRecessed`, `surface`, `surfaceHover`, `surfaceElevated`, `surfaceHighlight`.
- Borders: `borderSubtle`, `border`, `borderStrong`, `rule`.
- Text: `text`, `muted`, `subdued`, `dim`.
- Accents: `blue`/`blueLight`, `red`, `green`/`greenLight`, `amber`/`amberLight`, `purple`, `doneFill`, `blueHex` (the string form, for model `colorHex` fallbacks).
- Content drawn **on** a saturated fill: the `onColor*` family — use these instead of `.white.opacity(...)`.
- Overlays and shadows: `scrim`, `selectionWash`, `subtleWash`, `chipShadow`, `sidePanelShadow`, `overlayCardShadow`, `cardElevationShadow`.
- Radii: `radiusControl` (10), `radiusCard` (18), `radiusPanel` (22).
- AppKit mirrors: `Theme.ns*` (`nsBg`, `nsSurface`, `nsBorderStrong`, …) resolve the *same*
  `Color` constants into sRGB `NSColor`s for the markdown editor's custom drawing. Add a
  bridge here rather than an `NSColor(hex:)` literal in editor code.

`priorityColor(_:)` and `statusColor(_:)` take **enums** (`TaskPriority`, `TaskStatus`), not
strings. `Theme.swift` is also in the `CadenceWidgets` target's Sources phase — widgets have no
hardcoded colours either.

## Working Rules

- Only put code here when it is genuinely shared across platforms or intentionally platform-conditional.
- Use `Theme` tokens and existing shared components before introducing new one-off styling. No `Color(hex:)` literals outside `Theme.swift` and user-owned `colorHex` values.
- Use `DateFormatters` and `TimeFormatters`; do not create inline date formatters in views.
- Preserve hover semantics in `CadenceHoverStyles.swift`: task/event/bundle hovers should preserve original color and lift/brighten rather than gray out.
- Keep shared components small and dependency-light. Avoid pulling macOS-only managers into shared code.

## The File Name Is Not The Type Name

Several shared types sit in `Cadence`-prefixed files while carrying no prefix themselves:
`CalendarVisibilityPreferences` in `CadenceCalendarVisibilityPreferences.swift`, `ListDetailPage`
in `CadenceListDetailPage.swift`. Others are the reverse of where a reader expects them —
`CalendarWorkHoursPreferences`, `TaskDragPayload` and `CadenceCompactTab` are all here rather than
under a platform folder, precisely because both platforms use them.

Some shared views are not top-level files at all. **`CompactTagStrip` — the read-only compact tag
strip used by task rows, board cards and note rows on both platforms — is declared inside
`Components/CadenceTagChip.swift`**, beside the chip and overflow badge it is built from. There is
no `CompactTagStrip.swift`, so `find` finds nothing.

That one is worth naming because it has already cost twice. `CompactTagStrip` used to be inside
`#if os(macOS)`, so `CadenceNotesListSupport` grew a private `NoteRowTagStrip` that was it line for
line, and iOS's board card was about to become a third copy before `3c8de23` moved the strip here
and deleted the duplicate.

A `find . -name TypeName.swift` that comes back empty is therefore not evidence the type is
elsewhere, and this exact mismatch is what left two docs describing `CalendarVisibilityPreferences`
as a macOS service after it had moved. Grep for the declaration, not for the filename — and when a
component is a second declaration inside another component's file, say so in `CLAUDE.md`'s inventory,
because that inventory is a list of *files* and a reader counting it will not see you.

## One Page Header Per Platform

`DesktopPageHeader` (`macOS/Views/macOSRootSupportViews.swift`) and `iOSPageHeader`
(`iOS/iOSFeatureComponents.swift`) are **the** two header views. Everything else with "header" in
its name is a name-only wrapper that decides nothing about appearance: `PanelHeader`,
`CommitmentPageHeader` and `CadenceSettingsHeader` on macOS, `iOSPanelHeader` and
`iOSSettingsPageHeader` on iOS. Both root guides used to name the three macOS wrappers alongside
`DesktopPageHeader` as if they were peers — which was true until `5aa11dc` and is the reason a
subtitle, a title size and three glyph ratios (32/15, 32/13, 42/17) each had to be removed three or
four times to actually be gone. Change the header in one place; check the wrapper only for the
parameter it passes.

All of them draw their measurements from `CadencePageHeaderMetrics` (here, outside any platform
guard so the macOS-built test target can pin it — `CadenceTests/CadencePageHeaderMetricsTests.swift`).
Two axes:

- **`CadencePageHeaderRole`** — `.page` for the top of a whole screen, `.pane` for one column
  inside a split, where the page has already said what it is. Volume, not vocabulary: title and
  tile size vary by role; eyebrow, count badge and padding do not.
- **`CadencePageHeaderSurface`** — `.compact`, `.regular`, **`.desktop`**. macOS is deliberately a
  third tier and not an alias for `.regular`: a Mac window is wider than an iPad but sets type
  *smaller*, not larger — Apple's large title is 26pt on macOS against 34 on iOS, and Cadence's
  desktop body is 13pt against the phone's 15–17. Folding the two would put a 30pt title over 13pt
  rows. Do not "simplify" the enum to two cases; the third one is the finding.

## Component Expectations

- Components should be reusable through explicit props and bindings.
- Avoid hidden global state unless the existing component pattern already uses it.
- **Match the app's compact visual language — not a desktop one.** This line used to say
  "compact, desktop-focused", which pointed a *cross-platform* folder at the macOS shape and
  contradicted the standing rule that iPhone and iPad are one style. macOS is no longer the
  reference by default: where iOS has the better spelling, macOS changes. The platforms differ in
  **layout** — sidebar and columns against a tab bar and one pane — and should not differ in how a
  row, a chip, a header or a picker looks or behaves. Default to one view parameterised by size
  class over an `iPhoneFoo` beside an `iPadFoo`.
