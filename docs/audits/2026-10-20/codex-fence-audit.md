# Codex fence audit, batch 5 (2026-10-20)

Agent `n10land` (batch name `n5fence`), read-only, filed as [[T-3263]]. **Nothing in the fence was
edited and no path was released.** Re-run of [[T-3257]]'s method (`88fd2e80`) against a newer `main`
and a larger fence.

- **Pinned base:** `main` = `c4825ea2`. (The run started at `94fa36c3`; `main` gained `c4825ea2`
  mid-run, which touches the fenced `Cadence/iOS/iOSCalendarTimelineViews.swift`, so everything was
  re-run at `c4825ea2`. Both runs gave the same verdicts.)
- **The fence:** `./scripts/codex-land.sh lease` printed **140 pattern lines, 136 distinct**
  (`Cadence/macOS/Views/CalendarPageMonthSupportViews.swift`, `Cadence/iOS/iOSMarkdownEditor.swift`,
  `Cadence/iOS/iOSCalendarManager.swift` and `CadenceUITests/CadenceCapturePaletteUITests.swift`
  each appear twice). The brief said ~113; the lease grew to 140 with the retroactive T-1364 grant.
  The `CODEX_WORKTREE.md` prose says "Count 140 → 141" for the `TaskBundleTests.swift` grant, but the
  script reports 140 lines. Every pattern matches at least one path.
- **The paths:** **174** repository paths match, using Python `fnmatch.fnmatchcase` over the tree of
  `main` and of every branch. 171 exist on `main`; 3 exist only on `codex/block-removal-finish`.
- **The branches:** all **28** local `codex/*` branches. No remote `codex/*` ref exists.

## Result

**155 free, 19 held.** Every held path is held by ONE branch, `codex/block-removal-finish`
(`a2d4874b`, 5 commits on 2026-10-20 18:26, forked at `e5ff6599`). That is Codex's live [[T-3170]]
tail: the Block removal the owner granted the four paths and `TaskBundleTests.swift` for at
`25e925dc` and `e5ff6599`. Each held hunk is on the BRANCH side: the branch removes lines that `main`
still has, and adds lines `main` lacks, and `main` has not touched any of those strings since the
fork. This is unlanded work, not a stale branch.

**Why it matters:** the 2026-10-20 release in `docs/CODEX_WORKTREE.md` admits LOCAL agents to every
fenced path. That includes these 19, where an in-flight Codex branch holds unlanded deletions. A local
edit to any of them collides at landing. The release was made on [[T-3257]]'s evidence, which was
true at `88fd2e80`, before this branch existed.

**The known case is refuted.** `docs/CODEX_WORKTREE.md` (the 2026-10-19 grant section, ~L3104-3114)
says `Cadence/iOS/iOSTaskRowActionViews.swift` lines 405-414 hold unlanded work on
`codex/archive-typography-20261002` and `codex/tracking-ui-retirement`. **Neither branch holds any.**
- `archive-typography` (fork `f7aabe44`): its own change is +7/-4, and all 7 added lines are in `main`.
  The `git diff main:<path> <branch>:<path>` hunk `-405,10 +405,138` is `main`'s side: `main` removed
  that block after the fork, in 4 commits that touch the path.
- `tracking-ui-retirement` (fork `ab905209`): its own change is +0/-87, removal only. Of the 65
  distinct removed strings, 63 are already gone from `main` and the other 2 were rewritten on `main`
  after the fork. The `-405,10 +405,51` hunk is again `main`'s side.
- This matches the coordinator's spot check recorded in the 2026-10-20 release section.

## Method

Everything here is read-only. `git merge-tree --write-tree` writes only unreachable objects and no
ref, index or worktree.

1. For each (path, branch) pair, 28 × 174 = 4,872 in all:
   - **identical:** the branch blob equals `main`'s (1,494 pairs).
   - **untouched since fork:** the branch blob equals the merge-base blob. Every
     `git diff main:<path> <branch>:<path>` hunk is then `main`'s side (3,256 pairs).
   - **merge = main:** `git merge-tree --write-tree main <branch>` merges the path cleanly to
     `main`'s exact blob. The branch's change is already in `main` (48 pairs).
   - **conflict:** 55 pairs, sided line by line in step 2.
   - **clean merge ≠ main:** a candidate hold (19 pairs, all on `codex/block-removal-finish`).
2. Conflict and candidate pairs were sided line by line over the branch's OWN change
   (`<merge-base>` → `<branch>`), using occurrence counts of each stripped line:
   - A line the branch ADDED is on `main`'s side when `main` already has it. It is also on `main`'s
     side when `main` touched that exact string after the fork (`git log -S <line> <merge-base>..main
     -- <path>`), which means `main` moved past it.
   - A line the branch REMOVED is treated the same way.
   - Whatever is left is UNEXPLAINED.
3. Of the 55 conflict pairs, 48 sided fully to `main`. In 7, a few lines were unexplained. Each of
   those was sided by hand to `main`, with the reason given in the table: `main` rewrote them AT
   LANDING. The clearest case is T-3195's landing replacing `capture-list-sections`' native
   `Picker`s with the app's own controls, so `main` never held the native-picker lines at all.
4. In the 19 `block-removal-finish` pairs, the UNEXPLAINED lines are the branch's own work. No
   `main` commit since the fork touches them.

No three-dot diff was used for siding. `git diff --name-only main...codex/block-removal-finish` was
run once, only to list the branch's paths. The siding itself used two-dot `<merge-base>..<branch>`
and `main:<path>` vs `<branch>:<path>`.

## Not verified

- **Uncommitted work in Codex worktrees.** This includes `/private/tmp/cadence-unified-editors`,
  `~/.codex/worktrees/9e4a/Cadence` (block-removal-finish), `~/.codex/worktrees/platform-parity-audit/Cadence`
  and `~/.codex/worktrees/text-scale-finish/Cadence`. The brief forbade touching any worktree, so
  "free" here means **free of COMMITTED unlanded Codex work** only. [[T-3257]] also checked worktree
  dirt; this pass did not.
- The line-count siding treats identical stripped lines as interchangeable. A branch line that
  happens to match an unrelated `main` line elsewhere in the file reads as landed. The hand-sided
  pairs were read, but the 48 automatically cleared conflict pairs were not read hunk by hunk.
- `codex/text-scale-finish` (`200fe285`) has 2 commits `main` lacks. All of its fenced paths are
  identical or merge to `main`'s blob, so its content is in `main`, but its unfenced paths were not
  audited.

## Table

| Path | On main | Verdict | Evidence (branch, hunk side) |
|---|---|---|---|
| `Cadence/CadenceApp.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Services/CadenceArchiveImportService.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Services/CadenceForkedOccurrenceRemover.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Services/CadenceRemindersManager.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Services/CadenceTodayWidgetSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Services/CadenceWidgetRefreshCenter.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Services/TaskCreationService.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +1/-2 since fork `e5ff6599`; 1 added line(s) absent from main and 2 removed line(s) main still has, none touched on main since the fork |
| `Cadence/Shared/CadenceCapturePaletteSupport.swift` | yes | free | `codex/typography-lifecycle-batch` conflict, hand-sided MAIN: 2 doc-comment lines; main states the same contract reworded at :516 (`calls destroy(_:) only on final release`) |
| `Cadence/Shared/CadenceFocusPlanningSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/CadenceSavedLinkPersistence.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/CadenceSectionConfigMerge.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/CadenceSectionEditingSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/CadenceSettingsPresentationSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/CadenceTaskDateEditing.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/CadenceTaskFieldEditCommit.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +2/-78 since fork `e5ff6599`; 2 added line(s) absent from main and 62 removed line(s) main still has, none touched on main since the fork; `codex/calendar-day-drop-commit` conflict, every own-change line in main (64+/3-) or rewritten on main after fork (8+/0-) |
| `Cadence/Shared/CadenceTaskMutationSupport.swift` | yes | free | `codex/data-safety-audit-fixes` conflict, every own-change line in main (9+/0-) or rewritten on main after fork (1+/0-); `codex/ios-board-drop-refusal` conflict, every own-change line in main (11+/2-) or rewritten on main after fork (7+/0-) |
| `Cadence/Shared/CadenceTypography.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/CadenceAccentPalettePicker.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/CadenceBoardMetadataChip.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/CadenceChoicePicker.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/CadenceFieldRows.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift` | yes | free | `codex/capture-list-sections` conflict, hand-sided MAIN: 11 native `Picker`/`.pickerStyle(.segmented)` lines main lacks: replaced AT LANDING by `CadenceScheduleKindSwitch` + `CadenceChoiceRow` (T-3195 landing note, guard `noMobileOrSharedSurfaceDrawsANativePicker`); main has `identifierPrefix: "capture-kind"` at :199; `codex/unified-editors` conflict, hand-sided MAIN: 1 line (`.filter { $0 != .tags // ... }`): main holds the same condition refactored, `return !options.tagChoices.isEmpty // options.createTag != nil` at :104 |
| `Cadence/Shared/Components/CadenceSchedulePanel.swift` | yes | free | `codex/capture-list-sections` conflict, every own-change line in main (24+/0-) or rewritten on main after fork (0+/0-) |
| `Cadence/Shared/Components/CadenceSectionCreationRow.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/CadenceTagChip.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/Shared/Components/EstimatePickerControl.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSArchiveImportSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSBoardCards.swift` | yes | free | `codex/archive-typography-20261002` conflict, every own-change line in main (17+/9-) or rewritten on main after fork (1+/0-); `codex/parity-functional-batch` conflict, every own-change line in main (5+/3-) or rewritten on main after fork (1+/0-) |
| `Cadence/iOS/iOSCalendarBoardView.swift` | yes | free | `codex/parity-functional-batch` conflict, every own-change line in main (9+/0-) or rewritten on main after fork (1+/0-) |
| `Cadence/iOS/iOSCalendarChromeViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarEventEditSheet.swift` | yes | free | `codex/unified-editors` conflict, every own-change line in main (11+/13-) or rewritten on main after fork (0+/0-) |
| `Cadence/iOS/iOSCalendarManager.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarMetrics.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarMonthAgendaViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarMonthViews.swift` | yes | free | `codex/mobile-calendar-notes-parity` conflict, every own-change line in main (41+/12-) or rewritten on main after fork (10+/0-) |
| `Cadence/iOS/iOSCalendarQuickCreateSheet.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarTimelineViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCalendarView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCaptureRadialMenu.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSChoicePicker.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCompactTabShell.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCreateTaskSheet.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSCreateTaskSheetSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSDataExportSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSDataResetSettingsSection.swift` | yes | free | `codex/tracking-ui-retirement` conflict, every own-change line in main (2+/2-) or rewritten on main after fork (0+/0-) |
| `Cadence/iOS/iOSDateJumpTitle.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSFloatingCreateTaskButton.swift` | yes | free | `codex/archive-typography-20261002` conflict, every own-change line in main (13+/5-) or rewritten on main after fork (0+/0-) |
| `Cadence/iOS/iOSFocusView.swift` | yes | free | `codex/typography-lifecycle-batch` conflict, every own-change line in main (35+/5-) or rewritten on main after fork (7+/0-) |
| `Cadence/iOS/iOSListDeletionSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListDetailView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListEditorViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListNotesView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListWindDownSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSListsRegularPane.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSMarkdownEditingSurface.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSMarkdownEditor.swift` | yes | free | `codex/leased-followup-batch` conflict, every own-change line in main (15+/1-) or rewritten on main after fork (0+/0-) |
| `Cadence/iOS/iOSMarkdownReferenceSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSMarkdownStylingSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSMarkdownTableGridRendering.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSNoteEditorSheetHeader.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSNotesView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSNotificationsSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSRemindersSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSRootView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSettingsComponents.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSettingsContextSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSettingsOverviewSections.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSettingsTagsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSettingsTemplateAndListSections.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSettingsView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSSidebarLayoutSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSStoreBackupSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSTaskDetailSheet.swift` | yes | free | `codex/tracking-ui-retirement` conflict, every own-change line in main (0+/9-) or rewritten on main after fork (0+/0-) |
| `Cadence/iOS/iOSTaskDetailSheetSections.swift` | yes | free | `codex/tracking-ui-retirement` conflict, every own-change line in main (0+/42-) or rewritten on main after fork (1+/0-) |
| `Cadence/iOS/iOSTaskGroupSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSTaskRowActionViews.swift` | yes | free | `codex/tracking-ui-retirement` conflict, every own-change line in main (0+/63-) or rewritten on main after fork (0+/2-) |
| `Cadence/iOS/iOSTaskViews.swift` | yes | free | `codex/archive-typography-20261002` conflict, every own-change line in main (30+/17-) or rewritten on main after fork (4+/0-) |
| `Cadence/iOS/iOSTimelineDraftCreate.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/iOS/iOSTodayCompactViews.swift` | yes | free | `codex/archive-typography-20261002` conflict, every own-change line in main (7+/14-) or rewritten on main after fork (14+/0-) |
| `Cadence/iOS/iOSUnmanagedStoreSettingsSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Services/CadenceMCPRefreshCoordinator.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Services/FocusManager.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Services/QuickTaskPanelController.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Services/SchedulingService.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-13 since fork `e5ff6599`; 0 added line(s) absent from main and 11 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift` | yes | free | `codex/calendar-day-drop-commit` conflict, every own-change line in main (7+/5-) or rewritten on main after fork (2+/0-) |
| `Cadence/macOS/Views/CalendarEventPresentationSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-34 since fork `e5ff6599`; 0 added line(s) absent from main and 30 removed line(s) main still has, none touched on main since the fork; `codex/calendar-day-drop-commit` conflict, every own-change line in main (60+/8-) or rewritten on main after fork (12+/0-) |
| `Cadence/macOS/Views/CalendarPageComponents.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-4 since fork `e5ff6599`; 0 added line(s) absent from main and 3 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/CalendarPageMonthSupportViews.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-12 since fork `e5ff6599`; 0 added line(s) absent from main and 11 removed line(s) main still has, none touched on main since the fork; `codex/ui-refresh-reconciliation` conflict, every own-change line in main (10+/7-) or rewritten on main after fork (0+/0-) |
| `Cadence/macOS/Views/CalendarPageSupportViews.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-4 since fork `e5ff6599`; 0 added line(s) absent from main and 4 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/CalendarPageView.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +2/-10 since fork `e5ff6599`; 2 added line(s) absent from main and 9 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-4 since fork `e5ff6599`; 0 added line(s) absent from main and 4 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/EventNoteSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/GlobalSearchIndexSupport.swift` | yes | free | `codex/parity-functional-batch` conflict, every own-change line in main (21+/1-) or rewritten on main after fork (3+/0-); `codex/search-widget-followups` conflict, every own-change line in main (21+/26-) or rewritten on main after fork (8+/2-) |
| `Cadence/macOS/Views/GlobalSearchSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/KanbanCardView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/KanbanColumnSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/KanbanListColumnView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/KanbanSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/LinksView.swift` | yes | free | `codex/parity-functional-batch` conflict, every own-change line in main (1+/1-) or rewritten on main after fork (0+/0-) |
| `Cadence/macOS/Views/ListDetailComponents.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/ListNotesView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/NotesView.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/SettingsAppearanceSection.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/TimelineDayCanvas.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-21 since fork `e5ff6599`; 0 added line(s) absent from main and 18 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-4 since fork `e5ff6599`; 0 added line(s) absent from main and 4 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/TimelineDropInteractionSupport.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +0/-16 since fork `e5ff6599`; 0 added line(s) absent from main and 16 removed line(s) main still has, none touched on main since the fork |
| `Cadence/macOS/Views/TimelineTaskBlock.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `Cadence/macOS/Views/macOSRootCommandActionSupport.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceArchiveImportSurfaceTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCalendarChipTreatmentTests.swift` | yes | free | `codex/mobile-calendar-notes-parity` conflict, every own-change line in main (16+/0-) or rewritten on main after fork (1+/0-) |
| `CadenceTests/CadenceCalendarFixtureEventsTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCapturePaletteTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceChoicePickerDismissalTests.swift` | yes | free | `codex/capture-list-sections` conflict, hand-sided MAIN: 2 lines are the picker-count pins for those native Pickers, which the landing removed; `codex/tracking-ui-retirement` conflict, every own-change line in main (9+/19-) or rewritten on main after fork (6+/0-) |
| `CadenceTests/CadenceCodexAuditLogPagingTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexBackupAuditTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexBlockMoveRemovalTests.swift` | **no (branch-only file)** | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +20/-0 since fork `e5ff6599`; 18 added line(s) absent from main and 0 removed line(s) main still has, none touched on main since the fork |
| `CadenceTests/CadenceCodexCalendarBlockRemovalTests.swift` | **no (branch-only file)** | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +30/-0 since fork `e5ff6599`; 26 added line(s) absent from main and 0 removed line(s) main still has, none touched on main since the fork |
| `CadenceTests/CadenceCodexCalendarTypographyTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexCaptureSectionBatchTests.swift` | yes | free | `codex/capture-list-sections` conflict, hand-sided MAIN: 1 line asserts the native `Picker("Capture kind"...)` the landing replaced |
| `CadenceTests/CadenceCodexCaptureStoreFixtureTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexDateSelectionTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexDirectBoolCommitReportTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexDropLifetimeTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexEventNoteResolutionTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexFocusLandscapeTests.swift` | yes | free | `codex/typography-lifecycle-batch` conflict, every own-change line in main (38+/0-) or rewritten on main after fork (1+/0-) |
| `CadenceTests/CadenceCodexFunctionalParityTests.swift` | yes | free | `codex/parity-functional-batch` conflict, every own-change line in main (134+/0-) or rewritten on main after fork (3+/0-) |
| `CadenceTests/CadenceCodexKanbanRenderingTests.swift` | yes | free | `codex/kanban-rendering` conflict, every own-change line in main (212+/0-) or rewritten on main after fork (3+/0-) |
| `CadenceTests/CadenceCodexLeasedFollowupTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexLineHeightTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexListCreationChoiceTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexPageCompletionTypographyTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexQuoteRailTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexRefreshRegressionTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexRemindersLaunchGateTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexSearchOptimizationTests.swift` | yes | free | `codex/search-widget-followups` conflict, every own-change line in main (132+/0-) or rewritten on main after fork (5+/0-) |
| `CadenceTests/CadenceCodexSettingsTypographyTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexSidebarDrawerTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexTaskListVirtualizationTests.swift` | yes | free | `codex/task-list-virtualization` conflict, every own-change line in main (74+/0-) or rewritten on main after fork (5+/0-) |
| `CadenceTests/CadenceCodexTaskPageTypographyTests.swift` | yes | free | `codex/archive-large-text-20261002` conflict, every own-change line in main (60+/0-) or rewritten on main after fork (1+/0-) |
| `CadenceTests/CadenceCodexTaskRowTypographyTests.swift` | yes | free | `codex/archive-typography-20261002` conflict, every own-change line in main (110+/0-) or rewritten on main after fork (3+/0-) |
| `CadenceTests/CadenceCodexTaskSummaryTypographyTests.swift` | yes | free | `codex/archive-large-text-20261002` conflict, every own-change line in main (93+/0-) or rewritten on main after fork (3+/0-) |
| `CadenceTests/CadenceCodexTimelineBlockRemovalTests.swift` | **no (branch-only file)** | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +39/-0 since fork `e5ff6599`; 33 added line(s) absent from main and 0 removed line(s) main still has, none touched on main since the fork |
| `CadenceTests/CadenceCodexTrackingUIRetirementTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCodexWidgetFollowupTests.swift` | yes | free | `codex/search-widget-followups` conflict, every own-change line in main (68+/0-) or rewritten on main after fork (19+/0-) |
| `CadenceTests/CadenceCodexWidgetReopenTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceCommentSymbolClaimTests.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +4/-5 since fork `e5ff6599`; 4 added line(s) absent from main and 5 removed line(s) main still has, none touched on main since the fork |
| `CadenceTests/CadenceComposerContainerSurfaceTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceContainerPickerConsolidationTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +3/-9 since fork `e5ff6599`; 3 added line(s) absent from main and 9 removed line(s) main still has, none touched on main since the fork; `codex/calendar-day-drop-commit` conflict, every own-change line in main (19+/9-) or rewritten on main after fork (5+/0-) |
| `CadenceTests/CadenceInboxRemindersSurfaceTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceInlineTagCommitSurfaceTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift` | yes | free | `codex/ios-board-drop-refusal` conflict, every own-change line in main (2+/0-) or rewritten on main after fork (1+/1-) |
| `CadenceTests/CadenceNoteReferencePanelSurfaceTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceOutlineParserRegexTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadencePresentedTypographyBoundaryTests.swift` | yes | free | `codex/archive-large-text-20261002` conflict, every own-change line in main (11+/20-) or rewritten on main after fork (0+/1-); `codex/tracking-ui-retirement` conflict, every own-change line in main (1+/1-) or rewritten on main after fork (1+/0-) |
| `CadenceTests/CadenceRealTreeSweepManifest.txt` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceSavedLinkPersistenceTests.swift` | yes | free | `codex/parity-functional-batch` conflict, every own-change line in main (30+/0-) or rewritten on main after fork (1+/0-) |
| `CadenceTests/CadenceSharedConstantReuseSweepTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceTests/CadenceTagChipStyleTests.swift` | yes | free | `codex/archive-large-text-20261002` conflict, every own-change line in main (55+/0-) or rewritten on main after fork (5+/0-); `codex/archive-typography-20261002` conflict, every own-change line in main (72+/4-) or rewritten on main after fork (3+/0-) |
| `CadenceTests/CadenceTypographyScaleTests.swift` | yes | free | `codex/archive-large-text-20261002` conflict, every own-change line in main (7+/8-) or rewritten on main after fork (0+/0-); `codex/archive-typography-20261002` conflict, every own-change line in main (5+/1-) or rewritten on main after fork (1+/0-) |
| `CadenceTests/CalendarBoardDayDropCommitTests.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +8/-213 since fork `e5ff6599`; 8 added line(s) absent from main and 132 removed line(s) main still has, none touched on main since the fork; `codex/calendar-day-drop-commit` conflict, every own-change line in main (319+/0-) or rewritten on main after fork (18+/0-); `codex/ios-board-drop-refusal` conflict, every own-change line in main (93+/0-) or rewritten on main after fork (6+/0-) |
| `CadenceTests/TaskBundleTests.swift` | yes | **HELD** | `codex/block-removal-finish` `a2d4874b`: BRANCH side -- own change +2/-9 since fork `e5ff6599`; 2 added line(s) absent from main and 8 removed line(s) main still has, none touched on main since the fork |
| `CadenceTests/iOSCalendarMetricsTests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceUITests/CadenceCapturePaletteUITests.swift` | yes | free | `codex/capture-list-sections` conflict, hand-sided MAIN: 4 lines drive `segmentedControls["capture-kind"]`; main drives `buttons["capture-kind-task"/"-event"]` (:139, :200, :244-248), the landing's own control; `codex/phone-capture-hold` conflict, every own-change line in main (128+/0-) or rewritten on main after fork (9+/0-); `codex/phone-capture-load` conflict, every own-change line in main (48+/2-) or rewritten on main after fork (3+/0-) |
| `CadenceUITests/CadenceIOSCalendarAndNoteParityUITests.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `CadenceWidgets/CadenceWidgetsBundle.swift` | yes | free | no branch changed it beyond what main holds (identical / untouched since fork / merge = main's blob, all 28 branches) |
| `docs/PLATFORM_PARITY_AUDIT.md` | yes | free | `codex/platform-parity-audit` conflict, hand-sided MAIN: 17 evidence/summary lines main lacks verbatim: main carries the audit with landing corrections woven in (e.g. PA-26 line 28 gains its *Landing correction*; LANDING NOTE at :435) |
