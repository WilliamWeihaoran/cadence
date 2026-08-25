# Shared Guide

This folder contains cross-platform design tokens, shared components, hover styles, date/time
helpers, and the `Cadence*Support.swift` presentation/query/mutation layer that both platforms
build their feature views on top of.

## Theme Is The Only Source Of Colour

`Theme.swift` holds one fixed near-black **neutral ramp** and six **selectable accents**. There is
still no light variant and `preferredColorScheme` is still a hardcoded `.dark`; `ThemeManager` and
its seven light-and-dark themes are still gone and were not asked for back. Read the file before
adding a colour; it already has named tokens for the jobs call sites keep re-inventing:

- Neutral ramp: `bg`, `surfaceRecessed`, `surface`, `surfaceHover`, `surfaceElevated`, `surfaceHighlight`.
- Borders: `borderSubtle`, `border`, `borderStrong`, `rule`.
- Text: `text`, `muted`, `subdued`, `dim`.
- Accents: `blue`/`blueLight`, `red`, `green`/`greenLight`, `amber`/`amberLight`, `purple`, `teal`, `doneFill`, and the `*Hex` string forms (for model `colorHex` fallbacks and app-defined defaults).
- Content drawn **on** a saturated fill: the `onColor*` family — use these instead of `.white.opacity(...)`.
- Overlays and shadows: `scrim`, `selectionWash`, `subtleWash`, `chipShadow`, `sidePanelShadow`, `overlayCardShadow`, `cardElevationShadow`.
- Radii: `radiusControl` (10), `radiusCard` (18), `radiusPanel` (22).
- AppKit mirrors: `Theme.ns*` (`nsBg`, `nsSurface`, `nsBorderStrong`, …) resolve the *same*
  `Color` constants into sRGB `NSColor`s for the markdown editor's custom drawing. Add a
  bridge here rather than an `NSColor(hex:)` literal in editor code.

`priorityColor(_:)` and `statusColor(_:)` take **enums** (`TaskPriority`, `TaskStatus`), not
strings. `Theme.swift` is also in the `CadenceWidgets` target's Sources phase — widgets have no
hardcoded colours either.

### The Neutrals Are Stored And The Accents Are Computed (T-15)

Everything above from `bg` through the text ramp, the marker pen, the `onColor*` family, the
overlays, the shadows and the radii is a `static let` with a fixed value, and no selection can move
one. The six accents, their `*Light` variants and their `*Hex` strings are `static var`s that
resolve from `CadenceAccentPaletteSelection.shared`. That split *is* the decision: the chrome that
appears on every screen cannot regress, and the accents carry the personality.

Three types, all declared in `Theme.swift` rather than in a file of their own — the widget target
takes its sources by explicit reference, so a new file under `Shared/` would compile for the app
and not for `CadenceWidgets`:

- `CadenceAccentPalette` — six hex strings plus a name and a one-line description. Three sets:
  `cadence` (the standard one, the values the app shipped with), `ember` (warm) and `glacier`
  (cool). `CadenceAccentPalette.standard` is the set every compile-time literal mirrors, which is
  what a test pinning a `@Model` `colorHex` default has to state itself against.
- `CadenceAccentResolution` — one palette resolved once into `Color`s and the three accent
  `NSColor` mirrors. A reference type, so `Theme.blue` stays one property load rather than a
  `Scanner` run per read.
- `CadenceAccentPaletteSelection` — `@Observable`, and the observation is load-bearing rather than
  decorative. Every accent accessor funnels through its `resolution`, so a view that reads
  `Theme.blue` anywhere in its body registers a dependency and repaints when the selection changes.
  The alternative considered and rejected was `.id(paletteID)` on the root view, which repaints by
  throwing away every piece of `@State` in the app, including the Settings screen the user is
  standing on.

**Never read an accent into a `static let`.** It initialises once and then draws the palette that
happened to be active the first time that surface appeared — silently, with no diagnostic. Three
declarations were in that shape and were converted: `CadenceColorPalette`'s swatch arrays,
`CadenceTodayPresentationSupport.completedSectionAccent`, and `MarkdownStylist`'s three accent
`NSColor`s. `CadenceAccentStorageSweepTests.noStoredDeclarationAnywhereInTheAppFreezesAnAccent`
sweeps all 512 files under `Cadence/` for both shapes (a direct read and an array literal), with no
allowlist. Reading a *neutral* into a `static let` is fine and 20-odd declarations do it.

The AppKit markdown editor is the one surface SwiftUI's observation does not reach — it draws
through `MarkdownStylist`, not through a `body` — so it repaints on its next restyle rather than
instantly. Its three accent colours are computed precisely so that restyle is correct.

The selection is persisted in the **app group** suite (`cadence.appearance.accentPaletteID`), not
`.standard`, because `CadenceWidgets` is a separate process compiling this same file.
`CadenceWidgetRefreshCenter` already crosses that boundary through the same suite, so selecting a
palette forces a timeline reload and the widgets come back on the new accents. Both Settings
screens render one shared `CadenceAccentPalettePicker` (`Components/`); neither writes its own row,
swatch or copy.

## Working Rules

- Only put code here when it is genuinely shared across platforms or intentionally platform-conditional.
- Use `Theme` tokens and existing shared components before introducing new one-off styling. No `Color(hex:)` literals outside `Theme.swift` and user-owned `colorHex` values.
- Use `DateFormatters` and `TimeFormatters`; do not create inline date formatters in views.
- Preserve hover semantics in `CadenceHoverStyles.swift`: task/event/bundle hovers should preserve original color and lift/brighten rather than gray out.
- Keep shared components small and dependency-light. Avoid pulling macOS-only managers into shared code.

## `#expect`: Never Put Arithmetic Opposite a `CGFloat`

`#expect(someCGFloat == 612 - 84)` **fails when the value is right.** `#expect` captures each
operand of a binary expression separately, and an unannotated arithmetic expression beside a
`CGFloat` is inferred as `Double` in that capture, so the macro compares a `CGFloat` box against a
`Double` box and reports `(options.contentWidth → 528.0) == (612 - 84 → 528)`. Plain Swift
evaluates the same expression to `true`.

Measured against this toolchain in an isolated package (T-194): `== 528`, `== someCGFloatLet` and
`== CGFloat(612 - 84)` all pass; `== 612 - 84` and `== 612.0 - 84.0` both fail; the identical
arithmetic against a `Double` passes. So it is `CGFloat` **beside an arithmetic operand**, nothing
about the numbers.

Bind the arithmetic to a typed `let` first:

```swift
let expectedContentWidth: CGFloat = 612 - 84
#expect(options.contentWidth == expectedContentWidth)
```

This matters more than a spelling nit, because the failure mode is the *inverse* of the usual one:
the assertion is red whatever the code does, so it has **zero** discriminating power and cannot be
mutation-killed. It shipped on the T-194 branch as the one failing test in that ticket's suite and
read as an unimplemented feature. Cadence's metrics are almost all `CGFloat`, so this is reachable
from every layout test in the repo. Comparisons with `>`, `>=` and a bare literal are unaffected.

## Source-Scanning Tests: The Two Ways They Go Wrong

A **source-scanning test** reads a `.swift` file as text and asserts something about the code in
it. This repo has a lot of them, for a good reason and a bad one. The good reason: `Cadence/iOS/`
is entirely inside `#if os(iOS)` and the test target builds for macOS, so for the whole iOS surface
there is no symbol to reference and a text scan is the *only* tool available. The bad one: they are
easy to write and easy to write wrongly. On one day they caught several real regressions **and**
produced every defective assertion an independent verifier found (T-227, T-228). Both failure modes
have names now.

**Kind one: it can fail on correct code.** A substring needle is a claim about text, and the claim
you meant is almost always about *structure*.

- `contains("MinimumWidth") == 0`, meaning "this file has not grown its own width floor", failed
  the moment a file read `CadenceNotesListMetrics.twoColumnMinimumWidth` — which is the edit the
  test's own name asked for.
- A bare `"$0.isDone"` banned from two whole view files, meaning "this column no longer splits its
  cards on done alone", would fail a done-count badge or a done card styled unlike a cancelled one.
- `toggleGoalListLink(` *contains* `GoalListLink(`, so a scan for stray constructors accuses every
  correctly-rewired call site.

Fixes, in order of preference: make the assertion **positive** ("this file reads the shared value")
rather than negative ("this file does not contain a string"); use a **regex with a word boundary or
a negative lookbehind** so a qualified read is exempt (`(?<!CadenceNotesListMetrics\.)`); pick the
**one polarity that can only mean the bug** (`filter { !$0.isDone }` is "work you still intend to
do"; a positive `$0.isDone` cannot be judged out of context, so do not judge it). And **strip
comments before scanning** — `strippingComments` in any of these test files — because explaining in
prose why a file has no `#if os(iOS)` should not fail a test asserting it has none. If the needle
is inherently ambiguous, assert the call site instead of the absence.

**Kind two: it cannot fail at all.** Green forever, and worth nothing.

- Asserting the *helpers* a decision reads while the decision itself — a `??`, a ternary, an
  argument order — sits in a view this target cannot call. Dropping `due ??` from the pill left the
  whole test green and two fixture lines dead.
- Restating something the line above already pins: `noteKindLabel(.meeting) != rawValue.capitalized`
  directly under `noteKindLabel(.meeting) == "Event note"`.
- Comparing through a lossy formatter. The MCP DTO formats `completedAt` with a default
  `ISO8601DateFormatter`, i.e. second precision, so a re-stamp microseconds later serialises
  identically and a DTO-string comparison cannot see it. Compare the stored `Date`, or inject the
  clock.
- A scan that silently read nothing. Every zero-count assertion passes against an empty string,
  which is what a `/tmp` against `/private/tmp` path mismatch produces on an isolated build tree.

So: **mutate the thing you claim to pin and watch the test fail.** That is the only evidence that
an assertion is load-bearing, and it is cheap — one line in a private tree. Read the *xcodebuild
exit status*, and count compile errors beside it: a mutation that fails to build also exits 65 and
looks exactly like a caught regression. Pull the failing expectation out of the `.xcresult`
(`xcrun xcresulttool get test-results tests --path <…>.xcresult --format json`) and check it is the
assertion you meant, not a neighbour. Then add the two guards that make the rest trustworthy: a
**non-vacuity test** over the file reader (`files.count > 300`, plus one positive `contains` and one
that proves the stripper stripped), and, for a regex needle, a **self-check** — run it against a
literal that must match and a literal that must not, so a typo in the pattern cannot quietly pass
every scan built on it.

Worked examples of all of this: `CadenceTests/CadenceSharedTaskRowJobsTests.swift` for the helper
shape, and the four files T-227/T-228 repaired —
`CadenceNoteFolderSurfaceTests`, `CadenceCancelledTaskReachabilityTests`,
`CadenceNoteReferencePanelSurfaceTests`, `CadenceWriteServiceTests`.

## The File Name Is Not The Type Name

Several shared types sit in `Cadence`-prefixed files while carrying no prefix themselves:
`CalendarVisibilityPreferences` in `CadenceCalendarVisibilityPreferences.swift`, `ListDetailPage`
in `CadenceListDetailPage.swift`. Others are the reverse of where a reader expects them —
`CalendarWorkHoursPreferences`, `TaskDragPayload` and `CadenceCompactTab` are all here rather than
under a platform folder, precisely because both platforms use them.

`AppStoreReviewReadiness.swift` is the worst of the family: it declares **three** types and only one
of them is the file's name. `CadenceAppBuildIdentity` (the three strings both About screens report
about the running build) and `CadenceAppReferenceLink` (the Privacy Policy / Support pair both About
screens render, `.all` being the list they iterate) also live there. Both are deliberately outside
every `#if`, because `Cadence/iOS/` is invisible to the macOS-built test target and the values have
to be reachable from `CadenceTests`. Look for a `CadenceAppReferenceLink.swift` and you will find
nothing, then hand-type a second pair of link literals into a view — which is the whole failure mode
this section exists to prevent.

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

## One Write Path For `GoalListLink`

**Attaching or detaching a linked list goes through `ModelContext.attachList(_:to:)`,
`detachGoalListLink(_:)` or `toggleGoalListLink(_:on:)` (`GoalListLinkHelpers.swift`). Never
`insert(GoalListLink(...))` or `delete(link)` at a call site, and never write `goal.listLinks` or
`area.goalLinks` directly** — the link row would have no owner.

Three reasons the helpers exist rather than the four inline spellings macOS had before `23eb847`:

- **`attachList` is idempotent, and has to be.** `GoalContributionResolver` walks `listLinks`, so a
  **Attach is idempotent for a reason this guide previously got wrong.** It is not that a
  duplicate double-counts the percentage — `contributingTasks` dedupes by task `id`, so it
  cannot. A duplicate breaks the things that count *links*: `linkedListCount`, the "N lists"
  chip, the attribution line, two MCP DTOs, and a duplicate row in both inspectors. The old
  claim's test passed under a mutation removing the guard.
  is not a symptom anyone reports.
- **`GoalLinkTarget` makes the model's invariant unspellable-wrong.** A `GoalListLink` points at
  exactly one of an area or a project; an enum with `.area` / `.project` cases cannot express both
  or neither, which a two-optional-parameters initialiser can.
- **Detach severs the link's own references before deleting the row**, matching
  `TrackingDeleteHelpers`: this codebase does not trust inverse back-population to have happened by
  the time anything reads it, and `Goal.listLinks` / `Area.goalLinks` / `Project.goalLinks` are read
  by the resolver on the very next render. Nothing on the other end is orphaned — the goal, the list
  and its tasks all outlive the link.

`GoalLinkPresentation` in the same file owns the read side (`contributionLabel`,
`contributionMetric`, `attributionLine`, `inheritedListNote`), and the two lengths are deliberate:
iPad's 44pt inspector row truncated "2 contributing tasks" to "2 contributing t…", so the metric is
short there while macOS's two-line row keeps the long form — both derived from one count, not two.

**Grep for the constructor with a word boundary.** `toggleGoalListLink(` *contains*
`GoalListLink(`, so a substring scan accuses every correctly-rewired call site of being an offender.
That trap bit two agents in one day.

## One Predicate For "This Task Is Over"

`CadenceTaskQuerySupport.isFinishedTask(_:)` / `finishedTasks(from:)`
(`CadenceTaskQuerySharedSupport.swift`) is **the** completed/logbook filter, and the exact
complement of the private `isOpenTask` the active filters read. Every Completed section goes
through it; the active lists keep their own `!isDone && !isCancelled`.

It exists because the two filters used not to partition the set. Active asked
`!isDone && !isCancelled` and Completed asked `isDone && !isCancelled` — and a **cancelled** task
satisfies neither, so it dropped out of every list in the app (T-147). macOS had independently
arrived at `isDone || isCancelled` in three view files; naming it once is what stops a fourth
Completed surface getting it wrong. `CadenceCancelledTaskReachabilityTests` pins both the predicate
and the call sites, including exact per-file counts of what may still say `isCancelled`.

Two neighbours are deliberately *not* it, and both are pinned:
- `completedTaskCount` counts `isDone` only. It backs the "N done" summary line and the Settings
  Completed tile; a cancellation is not an accomplishment. Reachability is what a Completed
  *section* owes you, not credit.
- `CadenceScheduleSupport`'s slot queries, `CalendarBoardPlannerSupport`'s rails and day buckets,
  and `CadenceSidebarLayout.overdueTaskCount` all still exclude cancelled work outright — a
  cancelled task holds no timeline slot, sits on no rail, and is not work you are late on.

For the *row*, the matching decision is `CadenceTaskCompletionState.isSettled`, read by
`iOSTaskRow` and `iOSTaskEditorTitleCard`. Do not restate either as `isDone || isCancelled`
inline.

**A cancellation is timestamped.** `CadenceTaskRecurrenceWorkflowSupport.markCancelled` sets
`completedAt = now` (`f15db8b`, T-202); it used to clear it, so "settled today" could never be true
of a cancelled task and one you gave up on never reached Today's **Completed** at all. macOS was
strictly worse than iOS here rather than equivalent, which is worth knowing before assuming a
date-scoped Completed section is fine: `TasksPanelDerivedState` in `todayOverview` mode has no
do-date or due-date fallback, so `completedAt` is its only ground and *every* cancelled task was
excluded, not merely undated ones. Two consequences to keep in mind when touching this:
`completionPrecedes` is `completedAt ?? createdAt`, so cancelled and done work in one Completed
section are now ordered by the same event; and any "not already cancelled" guard must read
**status alone** — spelling it as a status clause plus `completedAt == nil` was only correct while a
cancelled task had a nil timestamp, and two MCP write-path guards would have started re-stamping and
double-auditing on re-cancel.

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

## The Two Icon Tiles Are One Vocabulary

`CommitmentIconTile` (`Components/CommitmentSharedViews.swift`, macOS) and `iOSIconTile`
(`iOS/iOSDesignSystem.swift`) are the same control on two platforms, and `HabitIconTile` proves it:
that view's entire body is an `#if os(macOS)` picking between them, at 32/56pt on macOS against
34/52pt on iOS. So a difference between them is a fork, not two contexts, and all four of their
geometry figures now come from `CadencePageHeaderMetrics` — `tileGlyphRatio`, `tileFillOpacity`,
`tileBorderOpacity`, and since T-178 `tileCornerRadius` / `tileCornerStyle`.

The corner was the last one, and it went to the **token** (`Theme.radiusControl`, `.continuous`)
rather than to macOS's `min(12, size * 0.28)`, `.circular`. It was settled by rendering all four
combinations at 32/34/52/56pt with `ImageRenderer` from the test target, and the renders said two
things the argument could not: the formula saturates at 42.86pt, so the only values it produced
anywhere in this app were 8.96 and 12 — both within 2pt of the token, while its one non-habit call
site passed a literal `9` rather than trusting it; and the fear that a 56pt hero would read square
at radius 10 belonged to the **curve**, not the radius, since 10pt `.circular` was plainly the most
cornered of the four while 10pt `.continuous` was the second-roundest. Neither tile takes a
`cornerRadius` override at any call site now, and
`CadencePageHeaderMetricsTests.noTileCallSitePassesItsOwnCorner` fails if one reappears.

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
- **The habit detail's chrome is shared, all of it.** `Components/HabitProgressViews.swift` holds
  `HabitIconTile`, `HabitInfoCard`, `HabitHeatmap` (52 weeks, Monday-start via
  `Habit.isoWeekCalendar`) and `HabitLast7DayStrip`, and **both** habit details read all four. The
  strip is the cautionary one: `940c4da` promoted it here for macOS while iOS's `lastSevenDays` was
  held by another agent, so for a stretch the repo carried the near-copy this folder's whole rule
  exists to prevent — the same failure mode `CompactTagStrip` above has already cost twice. T-219
  deleted the iOS copy. **There was no figure to reconcile, which is the point:** the two agreed on
  the 26pt bar, the 8pt spacing, `Theme.radiusControl - 2`, both font sizes (11/9 semibold) and the
  weekday-label walk. The *only* difference was `ForEach(states.indices, id: \.self)` against
  `ForEach(Array(states.enumerated()), id: \.offset)` — the same identity either way. A fork that
  agrees on every number is exactly what a fork looks like right up until one side is tuned, so
  "they are identical" is a reason to delete one, never a reason to leave both.
- **Match the app's compact visual language — not a desktop one.** This line used to say
  "compact, desktop-focused", which pointed a *cross-platform* folder at the macOS shape and
  contradicted the standing rule that iPhone and iPad are one style. macOS is no longer the
  reference by default: where iOS has the better spelling, macOS changes. The platforms differ in
  **layout** — sidebar and columns against a tab bar and one pane — and should not differ in how a
  row, a chip, a header or a picker looks or behaves. Default to one view parameterised by size
  class over an `iPhoneFoo` beside an `iPadFoo`.
