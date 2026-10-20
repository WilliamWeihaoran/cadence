# Codex fence freedom audit, 2026-10-20 ([[T-3255]])

```text
main read:      72fd6d72 (still valid at 7a84c62a: only docs/TODO.md changed, no codex tip moved)
Fence read:     docs/CODEX_WORKTREE.md fenced lease block on main, 108 patterns
                (104 distinct: 4 lines are repeated; 2 globs expand to 8 and 27 files)
Branches read:  all 26 local refs/heads/codex/*; there are no remote codex/* refs
Mode:           read-only against git; no branch modified; the fence was NOT edited
Agent:          n5fence
```

**Verdict: all 108 fence lines are FREE. 0 HELD, 0 MISSING.** No `codex/*` branch holds a single
line of work on any fenced path that `main` lacks. Retiring entries is still the owner's decision;
this file is only the evidence.

**Not verified: uncommitted edits.** This reads refs only. Three worktrees have a `codex/*` branch
checked out (`~/.codex/worktrees/9e4a/Cadence` on `capture-list-sections`,
`~/.codex/worktrees/platform-parity-audit/Cadence` on `mobile-calendar-notes-parity`,
`/private/tmp/cadence-unified-editors` on `unified-editors`), and their working trees were not
read. Before retiring a line, check `git status` in those three.

## The specific claim, refuted

`docs/CODEX_WORKTREE.md` (the 2026-10-19 T-3210 grant) records "REAL unlanded work" on
`Cadence/iOS/iOSTaskRowActionViews.swift` lines 405-414, held by `codex/archive-typography-20261002`
(132/4) and `codex/tracking-ui-retirement` (45/4). **The numbers are right and the reading is
inverted.** Both hunks are MAIN having moved on:

- Each branch's blob of the file was once `main`'s exact blob: `a721ed86` landed in `a3b8fe0f`
  (T-1453, 2026-09-30) and `5bf9a05d` landed in `3c80981c` (T-1466 stage 2, 2026-10-05).
- The only main-side lines in the hunk are the four comment lines `7f9c0307` (T-3196, 2026-10-18)
  left where `iOSTaskRowEstimateChip` was removed. The branch side adds back that removed chip
  (and, on the older branch, the `iOSTaskRowGoalChip` T-1466 retired). That is deleted product,
  not pending work.

## Method

Per fence line, per `codex/*` ref, with Python `fnmatch.fnmatchcase` over the union of main's tree
and every branch's tree (so a glob also catches files that exist only on a branch):

1. `git rev-parse <ref>:<path>` against `main:<path>`. Equal: the branch holds nothing (**same**).
2. Branch lacks the file: it was added to main after the fork (**MAIN-ADDED**), or the branch
   deleted it (none found).
3. Branch blob equals its merge-base blob: the branch never changed the file, only main moved
   (**MAIN-MOVED**).
4. Branch blob appears anywhere in `git log main --raw -- <path>`, by a main commit descended from
   the fork point: the branch's whole content landed and main moved on (**LANDED-BLOB**).
5. Else `git merge-file main base branch`; a clean no-op means the branch's changes are already in
   main (**ABSORBED**).
6. Anything left (10 pairs, all conflicts) was read hunk by hunk: every branch-added line was
   checked against main now and against every main version since the fork, and each never-landed
   line was traced to the main commit that replaced it (**adjudicated**, notes in the row).

Never a three-dot diff. `--no-merges main..<branch> -- <path>` was recorded for every differing
pair; it lists commits, not content, so it narrowed and never decided.

## Stale prose this contradicts

- The T-3210 grant's "two Codex branches hold REAL unlanded work" on `iOSTaskRowActionViews.swift`:
  refuted above.
- The 2026-10-19 admission's "`codex/ios-board-drop-refusal` ... is unlanded; its product change
  ... is not on main": it has since landed as `749d67ad` (T-1470). `iOSCalendarBoardView.swift` is
  identical on the branch and main, and the branch's census file blob is one `main` carried.
- `codex/capture-list-sections` (the "live work" in the six-refinements history) landed as
  `b07655ff` (T-3192 + T-3195). Its remaining differences are native `Picker`s and pins that the
  landing replaced on purpose.

## Tickets whose fence wait this would end

Being FREE removes the "a Codex branch holds it" reason only. Each still needs the owner to retire
the line or publish a grant; nothing here grants anything.

| ticket | state | fenced path(s) it waits on |
|---|---|---|
| [[T-1474]] | PARTIAL, macOS half PARKED | `Cadence/macOS/Views/CalendarPageMonthSupportViews.swift` |
| [[T-3214]] | PARKED | `CadenceTests/CalendarBoardDayDropCommitTests.swift`, `Cadence/Shared/CadenceTaskMutationSupport.swift`, `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` |
| [[T-3254]] | OPEN, LEASE-BLOCKED | `CadenceTests/CadenceCodexCaptureSectionBatchTests.swift` (via `CadenceCodex*.swift`) |
| [[T-3221]] | OPEN, LEASE-BLOCKED | `Cadence/macOS/Views/KanbanCardView.swift`, `docs/PLATFORM_PARITY_AUDIT.md` |
| [[T-3250]] | OPEN | `docs/PLATFORM_PARITY_AUDIT.md` |
| [[T-3233]] | OPEN | `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift` |
| [[T-3078]] | PARTIAL, remainder lease-blocked | "the two leased Codex tests" it must edit first (`CadenceTests/CadenceCodex*.swift`) |
| [[T-3089]] | PARTIAL, Mac half waits on the lease | `Cadence/macOS/Views/GlobalSearchIndexSupport.swift`, `GlobalSearchSupportViews.swift` |
| [[T-3217]] | OPEN | `Cadence/Shared/CadenceTaskMutationSupport.swift`, `Cadence/Services/TaskCreationService.swift` |
| [[T-3244]] | PARTIAL | three `CadenceTests/CadenceCodex*.swift` files kept off the iOS leg |

Found by scanning open, partial and parked ledger lines for lease wording plus a fenced file
name. That is a text match, so it can miss a ticket that names its blocker some other way.

## Columns

`same` / `MAIN-MOVED` / `MAIN-ADDED` / `LANDED-BLOB` / `ABSORBED` / `adjudicated` count
(branch, file) pairs, so a single-file row sums to 26. "landed blob" names the branches whose
exact content `main` once carried.

| # | path | status | evidence |
|---|---|---|---|
| 1 | `Cadence/iOS/iOSList*.swift` | FREE | glob, 8 files; same 137, MAIN-MOVED 65, LANDED-BLOB 6; landed blob: archive-typography-20261002, leased-followup-batch, mobile-project-deadline |
| 2 | `Cadence/Shared/CadenceTypography.swift` | FREE | same 12, MAIN-MOVED 14 |
| 3 | `CadenceTests/CadenceTypographyScaleTests.swift` | FREE | same 2, MAIN-MOVED 21, LANDED-BLOB 3; landed blob: archive-large-text-20261002, archive-typography-20261002, leased-followup-batch |
| 4 | `CadenceTests/CadenceCodex*.swift` | FREE | glob, 27 files; same 345, MAIN-MOVED 75, MAIN-ADDED 270, LANDED-BLOB 11, adjudicated 1; landed blob: archive-large-text-20261002, archive-typography-20261002, kanban-rendering, mobile-project-deadline, parity-functional-batch, search-widget-followups, task-list-virtualization, typography-lifecycle-batch. `capture-list-sections`: branch pins `Picker("Capture kind"…)`; main's `b07655ff` (T-3192+T-3195 landing) re-pointed it at `CadenceScheduleKindSwitch` (no native pickers rule) |
| 5 | `Cadence/Shared/Components/CadenceChoicePicker.swift` | FREE | same 26 |
| 6 | `Cadence/iOS/iOSChoicePicker.swift` | FREE | same 26 |
| 7 | `Cadence/Shared/Components/CadenceTagChip.swift` | FREE | same 25, MAIN-MOVED 1 |
| 8 | `Cadence/macOS/Views/SettingsAppearanceSection.swift` | FREE | same 26 |
| 9 | `Cadence/CadenceApp.swift` | FREE | same 5, MAIN-MOVED 21 |
| 10 | `Cadence/iOS/iOSTaskViews.swift` | FREE | same 1, MAIN-MOVED 22, LANDED-BLOB 3; landed blob: archive-typography-20261002, parity-functional-batch, tracking-ui-retirement |
| 11 | `Cadence/iOS/iOSTaskRowActionViews.swift` | FREE | same 1, MAIN-MOVED 23, LANDED-BLOB 2; landed blob: archive-typography-20261002, tracking-ui-retirement |
| 12 | `Cadence/iOS/iOSTaskGroupSection.swift` | FREE | same 12, MAIN-MOVED 13, LANDED-BLOB 1; landed blob: archive-typography-20261002 |
| 13 | `Cadence/Shared/CadenceCapturePaletteSupport.swift` | FREE | same 11, MAIN-MOVED 14, adjudicated 1. `typography-lifecycle-batch`: only hunk 515-518 is a doc comment; branch's 2-line wording superseded by `bc082946` (T-3011 landing from `codex/leased-followup-batch`); its other 29 added lines all on main |
| 14 | `Cadence/iOS/iOSCaptureRadialMenu.swift` | FREE | same 2, MAIN-MOVED 23, LANDED-BLOB 1; landed blob: typography-lifecycle-batch |
| 15 | `Cadence/iOS/iOSFocusView.swift` | FREE | same 6, MAIN-MOVED 19, LANDED-BLOB 1; landed blob: typography-lifecycle-batch |
| 16 | `Cadence/Shared/CadenceFocusPlanningSupport.swift` | FREE | same 6, MAIN-MOVED 19, LANDED-BLOB 1; landed blob: typography-lifecycle-batch |
| 17 | `CadenceWidgets/CadenceWidgetsBundle.swift` | FREE | same 18, MAIN-MOVED 8 |
| 18 | `Cadence/iOS/iOSFloatingCreateTaskButton.swift` | FREE | same 11, MAIN-MOVED 14, LANDED-BLOB 1; landed blob: archive-typography-20261002 |
| 19 | `Cadence/Shared/Components/CadenceBoardMetadataChip.swift` | FREE | same 11, MAIN-MOVED 15 |
| 20 | `CadenceTests/CadenceTagChipStyleTests.swift` | FREE | MAIN-MOVED 23, LANDED-BLOB 3; landed blob: archive-large-text-20261002, archive-typography-20261002, leased-followup-batch |
| 21 | `Cadence/iOS/iOSMarkdownStylingSupport.swift` | FREE | same 11, MAIN-MOVED 15 |
| 22 | `Cadence/iOS/iOSMarkdownEditor.swift` | FREE | MAIN-MOVED 24, LANDED-BLOB 2; landed blob: leased-followup-batch, mobile-calendar-notes-parity |
| 23 | `Cadence/iOS/iOSMarkdownTableGridRendering.swift` | FREE | same 11, MAIN-MOVED 15 |
| 24 | `Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift` | FREE | same 11, MAIN-MOVED 14, LANDED-BLOB 1; landed blob: continuous-quote-rail |
| 25 | `Cadence/macOS/Services/CadenceMCPRefreshCoordinator.swift` | FREE | same 11, MAIN-MOVED 15 |
| 26 | `Cadence/macOS/Services/FocusManager.swift` | FREE | same 6, MAIN-MOVED 20 |
| 27 | `Cadence/macOS/Services/QuickTaskPanelController.swift` | FREE | same 26 |
| 28 | `Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift` | FREE | same 4, MAIN-MOVED 20, LANDED-BLOB 2; landed blob: calendar-day-drop-commit, leased-followup-batch |
| 29 | `Cadence/macOS/Views/TimelineDropInteractionSupport.swift` | FREE | same 5, MAIN-MOVED 20, LANDED-BLOB 1; landed blob: leased-followup-batch |
| 30 | `Cadence/Services/CadenceRemindersManager.swift` | FREE | same 10, MAIN-MOVED 15, LANDED-BLOB 1; landed blob: leased-followup-batch |
| 31 | `Cadence/Services/CadenceForkedOccurrenceRemover.swift` | FREE | same 11, MAIN-MOVED 15 |
| 32 | `Cadence/Services/CadenceWidgetRefreshCenter.swift` | FREE | same 15, MAIN-MOVED 10, LANDED-BLOB 1; landed blob: search-widget-followups |
| 33 | `Cadence/Services/CadenceTodayWidgetSupport.swift` | FREE | same 15, MAIN-MOVED 10, LANDED-BLOB 1; landed blob: search-widget-followups |
| 34 | `Cadence/iOS/iOSCompactTabShell.swift` | FREE | same 5, MAIN-MOVED 21 |
| 35 | `Cadence/iOS/iOSRootView.swift` | FREE | same 2, MAIN-MOVED 23, LANDED-BLOB 1; landed blob: ui-refresh-reconciliation |
| 36 | `Cadence/macOS/Views/CalendarEventPresentationSupport.swift` | FREE | same 19, MAIN-MOVED 7 |
| 37 | `Cadence/iOS/iOSCalendarBoardView.swift` | FREE | same 4, MAIN-MOVED 21, LANDED-BLOB 1; landed blob: parity-functional-batch |
| 38 | `Cadence/iOS/iOSBoardCards.swift` | FREE | same 5, MAIN-MOVED 19, LANDED-BLOB 2; landed blob: archive-typography-20261002, parity-functional-batch |
| 39 | `Cadence/macOS/Views/GlobalSearchIndexSupport.swift` | FREE | same 2, MAIN-MOVED 22, LANDED-BLOB 2; landed blob: parity-functional-batch, search-widget-followups |
| 40 | `Cadence/macOS/Views/GlobalSearchSupportViews.swift` | FREE | same 2, MAIN-MOVED 23, LANDED-BLOB 1; landed blob: parity-functional-batch |
| 41 | `Cadence/macOS/Views/macOSRootCommandActionSupport.swift` | FREE | same 10, MAIN-MOVED 16 |
| 42 | `Cadence/macOS/Views/EventNoteSupportViews.swift` | FREE | same 10, MAIN-MOVED 15, LANDED-BLOB 1; landed blob: data-safety-audit-fixes |
| 43 | `Cadence/macOS/Views/NotesView.swift` | FREE | same 10, MAIN-MOVED 16 |
| 44 | `Cadence/iOS/iOSTodayCompactViews.swift` | FREE | same 3, MAIN-MOVED 20, LANDED-BLOB 3; landed blob: archive-typography-20261002, parity-functional-batch, ui-refresh-reconciliation |
| 45 | `Cadence/Shared/CadenceSavedLinkPersistence.swift` | FREE | same 5, MAIN-MOVED 20, LANDED-BLOB 1; landed blob: parity-functional-batch |
| 46 | `CadenceTests/CadenceSavedLinkPersistenceTests.swift` | FREE | same 8, MAIN-MOVED 17, LANDED-BLOB 1; landed blob: parity-functional-batch |
| 47 | `Cadence/macOS/Views/LinksView.swift` | FREE | same 8, MAIN-MOVED 17, LANDED-BLOB 1; landed blob: parity-functional-batch |
| 48 | `CadenceTests/CadenceInboxRemindersSurfaceTests.swift` | FREE | same 10, MAIN-MOVED 16 |
| 49 | `CadenceTests/CadenceSharedConstantReuseSweepTests.swift` | FREE | same 1, MAIN-MOVED 24, LANDED-BLOB 1; landed blob: parity-functional-batch |
| 50 | `Cadence/macOS/Views/ListNotesView.swift` | FREE | same 10, MAIN-MOVED 16 |
| 51 | `CadenceUITests/CadenceCapturePaletteUITests.swift` | FREE | same 1, MAIN-MOVED 4, MAIN-ADDED 18, LANDED-BLOB 2, adjudicated 1; landed blob: phone-capture-hold, phone-capture-load. `capture-list-sections`: branch queries `segmentedControls["capture-kind"]`; main's `b07655ff` replaced them with `capture-kind-*` buttons; 66/71 added lines on main, the 5 others are those queries |
| 52 | `Cadence/Services/CadenceArchiveImportService.swift` | FREE | same 5, MAIN-MOVED 21 |
| 53 | `CadenceTests/CadenceArchiveImportSurfaceTests.swift` | FREE | MAIN-MOVED 25, LANDED-BLOB 1; landed blob: ui-refresh-reconciliation |
| 54 | `Cadence/macOS/Views/CalendarPageView.swift` | FREE | same 4, MAIN-MOVED 21, ABSORBED 1 |
| 55 | `Cadence/macOS/Views/CalendarPageSupportViews.swift` | FREE | same 5, MAIN-MOVED 21 |
| 56 | `Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift` | FREE | same 5, MAIN-MOVED 21 |
| 57 | `Cadence/macOS/Views/CalendarPageComponents.swift` | FREE | same 5, MAIN-MOVED 21 |
| 58 | `Cadence/macOS/Views/CalendarPageMonthSupportViews.swift` | FREE | same 1, MAIN-MOVED 24, LANDED-BLOB 1; landed blob: ui-refresh-reconciliation |
| 59 | `Cadence/macOS/Views/TimelineDayCanvas.swift` | FREE | MAIN-MOVED 25, LANDED-BLOB 1; landed blob: ui-refresh-reconciliation |
| 60 | `Cadence/macOS/Views/CalendarPageMonthSupportViews.swift` | FREE (duplicate) | repeats fence line 58; see that row |
| 61 | `Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift` | FREE | same 1, MAIN-MOVED 24, LANDED-BLOB 1; landed blob: ui-refresh-reconciliation |
| 62 | `Cadence/macOS/Views/TimelineTaskBlock.swift` | FREE | same 5, MAIN-MOVED 21 |
| 63 | `Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift` | FREE | same 5, MAIN-MOVED 21 |
| 64 | `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` | FREE | same 1, MAIN-MOVED 24, LANDED-BLOB 1; landed blob: calendar-day-drop-commit |
| 65 | `docs/PLATFORM_PARITY_AUDIT.md` | FREE | same 4, MAIN-ADDED 21, adjudicated 1. `platform-parity-audit`: single-commit branch landed by `81573e03` with landing corrections folded in place; branch-only lines are the pre-correction evidence lines |
| 66 | `Cadence/Shared/CadenceTaskMutationSupport.swift` | FREE | same 1, MAIN-MOVED 23, LANDED-BLOB 2; landed blob: data-safety-audit-fixes, ios-board-drop-refusal |
| 67 | `CadenceTests/CalendarBoardDayDropCommitTests.swift` | FREE | same 1, MAIN-MOVED 18, MAIN-ADDED 5, LANDED-BLOB 2; landed blob: calendar-day-drop-commit, ios-board-drop-refusal |
| 68 | `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift` | FREE | MAIN-MOVED 23, LANDED-BLOB 3; landed blob: calendar-day-drop-commit, data-safety-audit-fixes, ios-board-drop-refusal |
| 69 | `Cadence/Shared/CadenceTaskDateEditing.swift` | FREE | same 4, MAIN-MOVED 22 |
| 70 | `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift` | FREE | MAIN-MOVED 25, LANDED-BLOB 1; landed blob: ios-board-drop-refusal |
| 71 | `Cadence/iOS/iOSCalendarManager.swift` | FREE | same 1, MAIN-MOVED 23, LANDED-BLOB 2; landed blob: data-safety-audit-fixes, mobile-calendar-notes-parity |
| 72 | `Cadence/iOS/iOSTaskDetailSheet.swift` | FREE | same 1, MAIN-MOVED 24, LANDED-BLOB 1; landed blob: tracking-ui-retirement |
| 73 | `Cadence/iOS/iOSTaskDetailSheetSections.swift` | FREE | same 6, MAIN-MOVED 19, LANDED-BLOB 1; landed blob: tracking-ui-retirement |
| 74 | `Cadence/iOS/iOSCalendarEventEditSheet.swift` | FREE | same 1, MAIN-MOVED 25 |
| 75 | `Cadence/iOS/iOSCalendarMonthViews.swift` | FREE | same 1, MAIN-MOVED 24, adjudicated 1. `mobile-calendar-notes-parity`: 0 never-landed lines; landed `f1fe7afc`, then `6717a9b3` (T-3225) changed the AM/PM spelling and T-3170 removed `bundles: 0` |
| 76 | `Cadence/iOS/iOSNotesView.swift` | FREE | same 10, MAIN-MOVED 15, LANDED-BLOB 1; landed blob: data-safety-audit-fixes |
| 77 | `Cadence/iOS/iOSMarkdownEditingSurface.swift` | FREE | MAIN-MOVED 25, LANDED-BLOB 1; landed blob: mobile-calendar-notes-parity |
| 78 | `Cadence/iOS/iOSNoteEditorSheetHeader.swift` | FREE | same 26 |
| 79 | `CadenceTests/CadenceCalendarFixtureEventsTests.swift` | FREE | same 2, MAIN-MOVED 2, MAIN-ADDED 22 |
| 80 | `CadenceTests/CadenceCalendarChipTreatmentTests.swift` | FREE | MAIN-MOVED 5, MAIN-ADDED 20, LANDED-BLOB 1; landed blob: mobile-calendar-notes-parity |
| 81 | `CadenceTests/CadenceNoteReferencePanelSurfaceTests.swift` | FREE | same 2, MAIN-MOVED 24 |
| 82 | `CadenceTests/CadenceOutlineParserRegexTests.swift` | FREE | same 2, MAIN-MOVED 23, MAIN-ADDED 1 |
| 83 | `Cadence/iOS/iOSMarkdownEditor.swift` | FREE (duplicate) | repeats fence line 22; see that row |
| 84 | `CadenceUITests/CadenceIOSCalendarAndNoteParityUITests.swift` | FREE | same 2, MAIN-ADDED 24 |
| 85 | `Cadence/iOS/iOSCalendarView.swift` | FREE | same 2, MAIN-MOVED 24 |
| 86 | `Cadence/iOS/iOSCreateTaskSheet.swift` | FREE | same 2, MAIN-MOVED 24 |
| 87 | `Cadence/iOS/iOSCreateTaskSheetSupportViews.swift` | FREE | same 2, MAIN-MOVED 24 |
| 88 | `Cadence/macOS/Views/KanbanListColumnView.swift` | FREE | same 13, MAIN-MOVED 13 |
| 89 | `Cadence/macOS/Views/KanbanColumnSupportViews.swift` | FREE | same 13, MAIN-MOVED 13 |
| 90 | `Cadence/macOS/Views/KanbanSupportViews.swift` | FREE | same 13, MAIN-MOVED 13 |
| 91 | `Cadence/macOS/Views/KanbanCardView.swift` | FREE | same 24, MAIN-MOVED 2 |
| 92 | `Cadence/Shared/CadenceSectionEditingSupport.swift` | FREE | same 2, MAIN-MOVED 24 |
| 93 | `Cadence/Shared/CadenceSectionConfigMerge.swift` | FREE | same 26 |
| 94 | `Cadence/macOS/Views/ListDetailComponents.swift` | FREE | same 2, MAIN-MOVED 24 |
| 95 | `Cadence/Shared/Components/CadenceSectionCreationRow.swift` | FREE | same 2, MAIN-ADDED 24 |
| 96 | `Cadence/Shared/Components/CadenceSchedulePanel.swift` | FREE | MAIN-MOVED 4, MAIN-ADDED 20, ABSORBED 1, adjudicated 1. `capture-list-sections`: all 22 branch-added lines on main now; branch removes nothing (landed `b07655ff`) |
| 97 | `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift` | FREE | MAIN-ADDED 24, adjudicated 2. `capture-list-sections`: new file on branch; 348/377 lines on main, 18 more were on main once, the 11 never-landed are native `Picker`s main replaced in `b07655ff` `unified-editors`: one branch-only line, the inline tag predicate; `db52ebbd` resolved the recorded conflict as `.filter { isOffered($0, by: options) }` |
| 98 | `Cadence/Services/TaskCreationService.swift` | FREE | same 2, MAIN-MOVED 24 |
| 99 | `Cadence/iOS/iOSTimelineDraftCreate.swift` | FREE | same 1, MAIN-MOVED 5, MAIN-ADDED 20 |
| 100 | `Cadence/Shared/Components/EstimatePickerControl.swift` | FREE | same 2, MAIN-MOVED 24 |
| 101 | `Cadence/iOS/iOSCalendarManager.swift` | FREE (duplicate) | repeats fence line 71; see that row |
| 102 | `CadenceUITests/CadenceCapturePaletteUITests.swift` | FREE (duplicate) | repeats fence line 51; see that row |
| 103 | `CadenceTests/CadenceComposerContainerSurfaceTests.swift` | FREE | same 2, MAIN-MOVED 24 |
| 104 | `CadenceTests/CadenceCapturePaletteTests.swift` | FREE | same 2, MAIN-MOVED 24 |
| 105 | `CadenceTests/CadenceInlineTagCommitSurfaceTests.swift` | FREE | same 2, MAIN-MOVED 24 |
| 106 | `CadenceTests/CadenceChoicePickerDismissalTests.swift` | FREE | same 1, MAIN-MOVED 23, LANDED-BLOB 1, adjudicated 1; landed blob: tracking-ui-retirement. `capture-list-sections`: census counts 4/28 on branch vs 7/31 on main: landing T-3195 added three non-native pickers, explained in main's own comment |
| 107 | `CadenceTests/CadenceContainerPickerConsolidationTests.swift` | FREE | same 2, MAIN-MOVED 24 |
| 108 | `CadenceTests/CadencePresentedTypographyBoundaryTests.swift` | FREE | same 2, MAIN-MOVED 22, LANDED-BLOB 2; landed blob: archive-large-text-20261002, tracking-ui-retirement |
