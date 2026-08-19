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

A `find . -name TypeName.swift` that comes back empty is therefore not evidence the type is
elsewhere, and this exact mismatch is what left two docs describing `CalendarVisibilityPreferences`
as a macOS service after it had moved. Grep for the declaration, not for the filename.

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
