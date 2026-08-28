# Shared Guide

This folder contains cross-platform design tokens, shared components, hover styles, date/time
helpers, and `Cadence*Support.swift` presentation/query/mutation code. Keep this guide compact.
The full former guide is preserved at `../../docs/SHARED_AGENTS_REFERENCE.md`.

## Read First

- Shared code must stay genuinely shared or intentionally platform-conditional.
- Prefer `Theme`, existing shared components, and existing support types before adding a new helper.
- Avoid pulling macOS-only managers or AppKit assumptions into shared code.
- When a detail is not here, search `../../docs/SHARED_AGENTS_REFERENCE.md` for the relevant section
  rather than reading that full file.

## Theme And Colour

`Theme.swift` is the only source of app-defined colour.

- No `Color(hex:)` literals outside `Theme.swift` and model/user-owned `colorHex` values.
- No bare `.white`, `.black`, `.gray`, or other direct colour tokens at call sites.
- Use the named ramps: `bg`, `surface*`, `border*`, `text`, `muted`, `subdued`, `dim`, `rule`.
- Use `onColor*` for content drawn on saturated fills.
- Use `scrim`, `selectionWash`, `subtleWash`, and named shadow tokens instead of one-off opacity
  overlays.
- Use `Theme.priorityColor(_:)` and `Theme.statusColor(_:)` with enums, not strings.
- Add AppKit mirrors in `Theme.ns*` rather than creating editor-local `NSColor(hex:)` literals.

The neutral ramp is fixed. Accents are selectable and computed:

- Accent colours and `*Hex` strings are `static var`s: `blue`, `red`, `green`, `amber`, `purple`,
  `teal`, plus light variants and string forms.
- Never read an accent into a `static let`; it freezes the active palette on first access.
- Reading a neutral into a `static let` is fine.
- `Theme.swift` is also compiled into `CadenceWidgets`, so widgets follow the same rule.

## Date And Time

- Persisted dates are `yyyy-MM-dd` strings unless an existing model says otherwise.
- Use `DateFormatters` and `TimeFormatters`.
- Do not create inline `DateFormatter()` instances in views.

## Source-Scanning Tests

Source-scanning tests are sometimes necessary because `Cadence/iOS/` is behind `#if os(iOS)` while
`CadenceTests` builds on macOS. They are also easy to make useless.

Rules:

- Prefer positive assertions over vague absence checks.
- Strip comments before scanning. The stripper **blanks** comments to spaces of equal length, so
  the stripped string is never shorter: a `stripped.count < raw.count` guard is red whatever the
  code does. Assert `stripped != raw` instead, and pair it with `stripped.count == raw.count`.
- Add non-vacuity checks so an empty or wrong-path read cannot pass.
- For regex needles, include a self-check that must match and must not match.
- Mutate the thing you claim to pin and confirm the test fails for the intended assertion.
- `CadenceSourceScan.functionBody(named:)` cannot read a function whose signature carries a
  **defaulted closure parameter** — it takes the first `{` after `func name(`, which is the
  default closure, and returns its body. Check what a body reader returned before trusting a
  scan over it.
- A scoped run only proves something if it ran **your** tests. A file here can hold several
  suites, and tests appended inside the wrong `struct` are invisible to
  `-only-testing:.../ThatSuite` while still passing in a full run — so every mutation reads as
  a survivor. Check the scoped run's test count before trusting a green mutation.
- **A test name reused in another suite makes mutation evidence ambiguous.** Two suites may each
  declare `theSourceScanReachesTheFilesItClaimsTo`; both compile and both run, because Swift
  Testing scopes by `struct`. But the log prints the bare function name with no suite qualifier,
  so `grep '✔ Test thatName()'` cannot tell them apart — and a survivor in your suite is masked
  by a pass in the other one, which reads as a kill. Before trusting a mutation, confirm
  `grep -c '✔ Test <name>()'` on a green log returns exactly **1**. If it returns more, rename
  yours to something suite-specific rather than reasoning about which line is which.
- Avoid ambiguous substring traps; use word boundaries, negative lookbehind, or a narrower call-site
  assertion.
- When comparing a `CGFloat` with arithmetic in `#expect`, bind the arithmetic to a typed
  `CGFloat` first.

Detailed examples are in `../../docs/SHARED_AGENTS_REFERENCE.md`.

## Known Shared Invariants

- `GoalListLink` writes go through `ModelContext.attachList(_:to:)`,
  `detachGoalListLink(_:)`, or `toggleGoalListLink(_:on:)`. Never insert/delete links directly at a
  call site, and never write `goal.listLinks`, `area.goalLinks`, or `project.goalLinks` directly.
- `GoalLinkTarget` expresses exactly one of area/project. Keep that invariant unspellable-wrong.
- `CadenceTaskQuerySupport.isFinishedTask(_:)` / `finishedTasks(from:)` is the completed/logbook
  predicate: done or cancelled. Active lists keep their own `!isDone && !isCancelled`.
- `completedTaskCount` counts `isDone` only; do not replace it with the finished predicate.
- Row-level settled state is `CadenceTaskCompletionState.isSettled`.
- Global search has one candidate layer: `CadenceSearchCandidateSupport.swift`
  (`CadenceTaskSearchSupport`, `CadenceListSearchSupport`, `CadenceSearchTagSupport`) owns
  searchable fields, lifecycle aliases, tag name+slug text, and which lists search can see.
  Surfaces render their own rows from those facts; no surface builds its own field list. The list
  rule (T-378) is **typing reaches every list, idle suggestions offer only active ones** — the
  evidence for it is recorded on `CadenceListSearchSupport`.
- `CadenceTaskPresentationSupport.rowDatePlan(...)` decides how many date chips a task row
  draws. Two dates naming one day are one fact: the flag survives, the sun folds into it (T-304).
  Rows read the plan; they do not count their own chips from `isEmpty`.
- `CalendarVisibilityPreferences`, `CalendarWorkHoursPreferences`, `TaskDragPayload`, and
  `CadenceCompactTab` live here because both platforms need them.
- `CompactTagStrip` is declared inside `Components/CadenceTagChip.swift`; there is no
  `CompactTagStrip.swift`.

## Page Headers

- One header per platform: `DesktopPageHeader` and `iOSPageHeader`.
- Header wrappers such as `CommitmentPageHeader` and `CadenceSettingsHeader` are wrappers, not
  separate header systems.
- Page headers do not carry descriptive subtitles or identity tiles.
- Search rows, pickers, empty states, and other rows may keep subtitles when they add information.
- Header tint belongs on the count capsule.
- `CadencePageHeaderRole`: `.page` for full screens, `.pane` for columns.
- `CadencePageHeaderSurface`: `.compact`, `.regular`, `.desktop`; macOS has its own tier.

## Shared Components

- Prefer one parameterized shared component over platform near-copies.
- iPhone and iPad share visual language; they differ by layout.
- Preserve hover semantics in `CadenceHoverStyles.swift`: task/event/bundle hovers preserve colour
  and lift/brighten rather than gray out.
- Use one hover/selection layer at one radius.
- The shared board header is `CadenceBoardColumnHeader` in `Shared/Components/`.
- The shared estimate popover is `EstimatePickerPopoverContent`; platform wrappers should delegate.
- Habit detail chrome lives in `Components/HabitProgressViews.swift` and is shared.
- `CadenceChoicePicker`, field rows, empty states, tag chips, value tiles, and today rollover/overdue
  components should be reused before introducing new row chrome.

## Reference Sections

Search `../../docs/SHARED_AGENTS_REFERENCE.md` for:

- `Theme Is The Only Source Of Colour`
- `The Neutrals Are Stored And The Accents Are Computed`
- `#expect`
- `Source-Scanning Tests`
- `The File Name Is Not The Type Name`
- `One Write Path For GoalListLink`
- `One Predicate For "This Task Is Over"`
- `One Page Header Per Platform`
- `The Primary Task Row`
- `Component Expectations`
