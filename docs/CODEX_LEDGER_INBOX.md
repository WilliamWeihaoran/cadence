# Codex Ledger Inbox

**Append-only. Newest last. Never edit an existing entry, and never edit `docs/TODO.md`.**

Codex writes its ticket entries here; the coordinator folds them into `docs/TODO.md` when landing
the branch, in the same commit as the code. Appending merges cleanly; editing a 12,000-line ledger
in place is the conflict this file exists to avoid ([[T-1385]]).

Write an entry in the ledger's own shape — the id, a bold one-line headline, then the measurement.
A closure is written **as** a closure (`**CLOSED <date> (codex) — …`), never described as one, because
every reading in this repository anchors on that run and a quoted token is not one ([[T-1335]]).

**Reserved id range for Codex: T-1440 .. T-1469.** Do not use an id outside it. The coordinator
widens the range here when it runs low.

The protocol, the lease and the refusals are in `docs/CODEX_WORKTREE.md`; the coordinator checks a
branch with `./scripts/codex-land.sh review codex/<topic>`.

---

- [T-1440] **CLOSED 2026-09-27 (codex) — T-1413's date-picker implementation: readable date rows replace the seven-column grid at accessibility sizes, or whenever an inline grid cannot fit.** Base read: `18f3c689`; branch: `codex/task-page-large-text`; worktree: `~/.codex/worktrees/9e4a/Cadence`. This closes the implementation, not a rendered accessibility audit or an app-wide Larger Text claim.

  **Implemented:** `Cadence/Shared/Components/CadenceDatePicker.swift:86` owns the pure fit model. Cells grow additively; the ordinary grid remains seven columns. `MonthCalendarPanel` chooses rows using both text size and its actual offered width (`:143`). Rows wrap rather than shrink, use shared date formatters, retain selected/today styling, and preserve selection/month-update/dismissal. The hover wrapper adds no unmodelled width to grid cells. `CadenceQuickDatePopover` reflows shortcuts through `ViewThatFits`, reduces its date scroll viewport to 180pt at accessibility sizes, and retains Clear date. Both the quick panel and independently embeddable month panel declare their own scaled typography. No claim depends on environment propagation across presentations.

  **Deliberate baseline change:** the default non-inline width is now 266pt, not 256pt: `7 * 34 + 2 * 8 + 6 * 2`. The bounded panel height now includes weekday headings, rather than adding them above the old viewport. This is a redesigned picker, not a claim of pixel-identical baseline geometry. The trigger button is unchanged.

  **Measured:** `CadenceCodexDateSelectionTests` walks all 12 text sizes; non-inline widths remain <=343pt, width-dependent inline fallback has positive and negative controls, rows reserve their line plus padding, and the worst-case stacked-shortcut height model remains under 534pt. The 180pt viewport also holds a three-line date row; this does not assert that two wrapped dates and the month heading are simultaneously visible. Source assertions pin each independent scope, the row metric call, shortcut fonts/padding and selection/dismissal wiring. Existing grid, presentation-boundary and declared-root guards were updated, not bypassed.

  **Verification:** guarded macOS run `cadence-xcb-codex-date-large-text.20260927-145315-36888.log`: `XCODEBUILD_EXIT=0`, 127 passing test-result lines, 8 Swift compile tasks, 0 compiler warnings. Earlier cold run: 1,053 compile tasks; expanded typography run: 87 passing tests. Final app-source iOS Simulator build `cadence-xcb-codex-date-large-text-ios.20260927-145319-37289.log`: exit 0, 10 compile tasks, 0 compiler warnings; initial cold iOS build had 1,378 compile tasks. Logs are under `$TMPDIR`; private DerivedData was used throughout, and macOS tests held the test-host lock. No simulator was booted and no owner app was launched.

  **Negative control, measured:** freezing `dateRowHeight` at 44 made `codexDateRowsReserveTheirLineAndPaddingWithoutCappingWrapping` fail with four issues. Combined mutation run `cadence-xcb-codex-date-large-text.20260927-145113-36060.log`: 15 tests executed, three failed with six issues, exit 65, eight compile tasks, zero compiler warnings. The other two failures belong to T-1441's separate opt-in mutation. Both mutations were restored before the 127-test green run. **Not measured:** rendered pixels, clipping on an actual phone, VoiceOver traversal, or Xcode 26 execution. The coordinator should visually check an ordinary size and accessibility5 on a 375pt phone before landing a broader UI claim.

- [T-1441] **PARTIAL 2026-09-27 (codex) — T-1411's granted shared page chrome is prepared and guarded; none of the five task pages is declared converted yet.** Same base/worktree/branch as T-1440. The compact bar refusal is respected. The regular iPad shell was also read: `iOSRootSidebar.swift:51` composes sidebar and `detail()` (`:81`) as siblings, so neither sidebar nor its external expand overlay needs conversion from a page-local root.

  **Implemented inside the lease:** `iOSFeatureComponents.swift:289` keeps the ordinary header arrangement and adds a wrapped, stacked accessibility arrangement under enabled scaling; title, eyebrow detail and count use the role adapter. `iOSDesignSystem.swift:342` gives segmented pills a vertical accessibility arrangement, growing minimum heights and unrestricted wrapping. Header-back and icon-button frames grow additively with their glyphs. `iOSTaskCollectionTypography.swift` owns those pure geometry decisions outside the iOS compilation guard so macOS unit tests execute them. No shared component opts its callers in.

  **The coordinator's grant condition is measured, not inherited:** `CadenceCodexTaskPageTypographyTests` verifies fixed font/geometry identities at all 12 sizes, plus the enabled alternative and font/frame call sites. `CadenceTagChipStyleTests.swift:338` extends the existing caller sweep with explicit inventories for `iOSPageHeader`, `iOSCompactPageHeader`, `iOSSegmentedPill` and its group: 11 header files and seven pill files currently declare no root. Settings and Focus are named explicitly, along with Calendar/AI callers of the pills. Comments and strings are excluded with `codeOnly`; fixtures exercise both a real call and lookalike prose. This is a direct-caller declaration guard, not a proof of transitive reachability.

  **Negative control, measured:** temporarily putting `.cadenceScaledTypography()` on `iOSCompactPageHeader` made the extended caller test fail at `CadenceTagChipStyleTests.swift:383`, explicitly naming `Cadence/iOS/iOSFeatureComponents.swift` as an unauthorized opt-in. The new wiring test failed too. This was the second mutation in T-1440's red run, restored before the 127-test green run. The granted iOS changes also compiled on both simulator architectures with zero compiler warnings. No production page root, tab shell, sidebar, project file or primary ledger was edited.

  **Remaining lease dependencies, observed in live composition, not proposed side quests:**

  - `Cadence/Shared/Components/EmptyStateView.swift:24`: task pages' `iOSEmptyPanel` delegates here; 15pt title and 13pt subtitle remain literals. Conversion in the leased wrapper alone cannot resize them.
  - `Cadence/Shared/Components/CadenceTaskGroupHeading.swift:76`: the task-group eyebrow already follows the environment, but its count at `:95` is fixed. Enabling the page now grows one half of a single heading, not the other.
  - `Cadence/Shared/Components/CadenceTodayRolloverBanner.swift:51`: Today draws this banner from `iOSTodayTaskSections.swift:135`. A 14pt glyph is boxed at 22pt, with literal title, action and task-row fonts. A scaled glyph would be roughly 42pt, before its line box; the current 22pt frame cannot simply be retained. This is prospective scale arithmetic, not a claim that today's fixed banner already clips.
  - `Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift:186`: Today's real cards use a 30pt glyph plate and fixed captions; their shared heading at `:205` combines a scaling eyebrow with a fixed count at `:215`.
  - `Cadence/iOS/iOSTodayView.swift:288` embeds `iOSNotesView(showsTitle: false)` inside the Today root's right inspector. Unlike the shell sidebar, this is a descendant. Decide whether this independently owned Notes surface explicitly stays fixed at the embedding boundary, or whether a Notes conversion and its dependencies enter the lease. No implicit partial declaration or unapproved fixed boundary was added. The optional 64pt header in `iOSNotesView` is NOT evidence of a live Today overflow: `useStandardHeaderHeight` defaults false for this call.

  **Suggested remaining patch order:** coordinator leases the four shared files and settles the embedded Notes boundary; convert shared components with fixed-mode preservation/caller guards; finish leased rows, swipe actions, headers, options, empty states and page-specific content; declare whole page roots last and update both inventories; rerun all-size geometry/source checks plus iOS compilation and visual checks. T-1411 remains unfinished, not silently reduced to a row conversion. The scope question has been sent to the coordinator; no unleased edits were made.

  **Quick confirming run** (suite names verified with `test-suite-index.sh --suite-files`):

  ```sh
  ./scripts/xcb.sh codex-typography-confirm test -scheme Cadence -destination 'platform=macOS' \
    -only-testing:CadenceTests/CadenceCodexDateSelectionTests \
    -only-testing:CadenceTests/CadenceCodexTaskPageTypographyTests \
    -only-testing:CadenceTests/CadenceTagChipScaleTests
  ```

  **Final verification addendum (T-1440/T-1441):** after tightening the date test to assert each scope separately and pin the row/shortcut metric wiring, `cadence-xcb-codex-date-large-text.20260927-145626-38941.log` passed all four date tests: exit 0, three Swift compile tasks, zero compiler warnings. No app-source changes followed the successful iOS build. All test-host leases were released. The branch is intentionally a completed date redesign plus page-chrome preparation, not a closure of T-1411.
