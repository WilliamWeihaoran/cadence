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

## The Primary Task Row: What Is Shared, And What Is Earned

`MacTaskRow` (`macOS/Views/TasksPanelComponents.swift`) and `iOSTaskRow` (`iOS/iOSTaskViews.swift`)
are **not** being merged, and this section exists so the next agent does not re-derive that survey
from scratch. Four passes have now taken the parts that were forks; what is left is platform-bound
for reasons that are measurable rather than historical.

**Shared, and must stay shared:** `CadenceTaskPresentationSupport` (notes preview, subtask list and
its cap, tag cap, estimate label), `CadenceTaskMutationSupport`, `CadenceTaskCompletionGlyph` (the
state → symbol/tint decision, 3 macOS readers and 1 iOS), `CompactTagStrip`,
`CadenceBoardCardMetadata`, and — since T-175 — **`CadenceTaskRowMetrics`**.

`CadenceTaskRowMetrics` had five iOS readers and zero macOS ones while `MacTaskRow` hardcoded the
same figures inline; that is the shape `iOSPageHeaderMetrics` had before `5aa11dc`. It now has three
tiers, `CadenceTaskRowSurface.compact` / `.regular` / **`.desktop`**, for the same reason
`CadencePageHeaderSurface` has three and `CadenceSidebarSurface` has two: the platforms differ in
*input device*, not in taste. `horizontalPadding` and `badgeSpacing` turned out to be literally one
number across `.regular` and `.desktop`; `verticalPadding` (8 pointer against 9–12 touch) and
`titleFontSize` (15 macOS against 13 iOS) stay split and say why beside themselves. Do not flatten
the enum to two cases and do not average those two figures.

**Three figures macOS deliberately does not read**, each pinned by a test in
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` so the exception cannot decay into an oversight:

- `titleLineLimit` — macOS's row is one `HStack` with a `Spacer` and trailing metadata, so its
  height is fixed; iOS's is a `VStack` built to grow.
- `completionGlyphSize` / `completionCircleDiameter` — **not the same measurement.** iOS draws a
  16pt disc and ramps a *frame* around it to reach 44pt, so the number is a layout box. macOS passes
  an SF Symbol **point size** to `TaskCompletionProgressGlyph`, which is also its frame, and whose
  four macOS call sites already use it as a per-surface type ramp (12 / 13 / 15 / 18). This is
  `cdf0896`'s finding again: an apparent fork that is two different jobs under one name.
- The badge/chip geometry — iOS's row chips are `iOSTaskAttributeChipSize.row`, 30pt plates
  hit-expanded to 44pt; macOS's are bare text with a hover underline and a radius-4 wash. Same
  information, different control.

**Platform-bound interaction machinery — do not attempt to unify.** Counts measured at this commit,
and reproducible, so a future claim can be re-checked rather than believed:

```sh
for pat in '\.onHover' '\.onKeyPress' '\.keyboardShortcut' '\.swipeActions' \
           '\.draggable' '\.dropDestination' '\.onDrag' '\.onDrop' 'DropDelegate'; do
  printf "%-20s mac=%s ios=%s\n" "$pat" \
    "$(grep -roE "$pat" Cadence/macOS | wc -l)" "$(grep -roE "$pat" Cadence/iOS | wc -l)"
done
```

| API | macOS | iOS |
| --- | --- | --- |
| `.onHover` | 56 | 0 |
| `.onKeyPress` | 18 | 0 |
| `.keyboardShortcut` | 10 | 0 |
| `.swipeActions` | 0 | 9 |
| `.draggable` / `.dropDestination` | 15 / 16 | 7 / 3 |
| `.onDrag` / `.onDrop` / `DropDelegate` | 6 / 6 / 15 | 6 / 3 / 1 |

Those are four one-sided distributions, not four forks. Hover is the *only* way macOS's row exposes
its focus button, its date nudges and its whole hovered-task shortcut set — a pointer has a resting
position and a finger does not. iOS's equivalent is the swipe tray (`iOSTaskRowActionViews`, ~800
lines with no macOS counterpart). The T-175 ticket in `docs/TODO.md` quotes larger absolute figures
for the same four APIs; the *shape* reproduces and the absolute numbers do not, which is the reason
the command is printed here rather than only its output.

One thing that is **not** earned and must not regress: `MacTaskRow` and `MacTaskRowEstimateChip`
must never read `TaskCompletionAnimationManager`. The completion button and the animated background
are extracted into `TaskCompletionButton` and `TaskRowBackground` with their own `@Environment`
precisely so a `TimelineView(.animation)` tick re-renders those two sub-views instead of every
visible row. `CadenceTodayUnificationTests.theTaskRowStillDoesNotObserveTheCompletionAnimationManager`
pins exactly two environments in that file.

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
