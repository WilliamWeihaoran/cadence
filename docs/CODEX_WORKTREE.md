# Codex Worktree Protocol

Codex writes code here, in its own worktree, on its own branch. The coordinator lands it.

This exists because **two writers in one checkout collide in two measured ways**, neither of which
announces itself:

- **[[T-1385]]** — `scripts/agent-commit.sh` stages **whole files**. When two writers edit one file,
  one commit silently carries the other's half-finished work: no refusal, no declined hunk, nothing
  in `git status` that looks wrong. It reddened CI on `d65d294`, where a commit swept in a sibling's
  in-progress block that contained a forward reference to a declaration still uncommitted.
- **[[T-975]]** — a commit lands through a private index and never writes the shared checkout, so
  the tree drifts behind HEAD. `[stale base]`, `[stale copy]` and `[never checked out]` ([[T-1394]])
  are three different repairs and picking the wrong one destroys work.

A separate worktree removes the first entirely — disjoint filesystems cannot interleave — and makes
the second Codex's own problem rather than a shared one.

## The flow

1. **Codex works in its worktree**, on a branch named `codex/<topic>`, based on `origin/main`.
2. **Codex commits with plain `git commit`.** It does *not* run `scripts/agent-commit.sh`: that
   script enforces ledger discipline that requires editing `docs/TODO.md`, which is the one file
   guaranteed to conflict.
3. **Codex never touches the ledger.** Instead it appends its ticket entries to
   `docs/CODEX_LEDGER_INBOX.md` — **append-only, newest last**. Appending merges cleanly; editing
   a 12,000-line file in place does not.
4. **The coordinator reviews** with `./scripts/codex-land.sh review codex/<topic>`, which refuses on
   lease violations, ledger edits, missing inbox entries and id clashes.
5. **The coordinator runs the tests and lands it** through `scripts/agent-commit.sh`, folding the
   inbox entries into `docs/TODO.md` in the same commit. Every guard the repository has then applies
   to Codex's work exactly as it applies to everyone's. **When the coordinator PRE-FILED a stub for
   the id and assigned the branch to it, the fold REPLACES THAT STUB'S BODY IN PLACE** — one id, one
   entry, no second entry, no deletion, no renumber ([[T-1458]], [[T-3003]], [[T-3004]]). Step 4's
   `CODEX-INBOX-ID-CLASH` on a pre-filed id is that case, not a blocker ([[T-1800]]).

The coordinator is the bottleneck on step 5 deliberately. It costs minutes, and it is what keeps
`FOREIGN-STAGED`, `REMOVES-HEAD-LINES`, `LEDGER-ID-UNFILED`, the closure reading and the foreign-hunk
notice applying to code that did not come through them.

## The lease

Codex may write **only** to paths matching the lease below, and never to a path another writer holds.
The coordinator updates this block when the assignment changes; `codex-land.sh lease` parses it, so
this file is the single source of truth and there is no second list to drift.

Patterns are shell globs matched against repository-relative paths. `docs/CODEX_LEDGER_INBOX.md` is
always allowed and never needs listing.

```lease
Cadence/iOS/iOSList*.swift
Cadence/Shared/CadenceTypography.swift
CadenceTests/CadenceTypographyScaleTests.swift
CadenceTests/CadenceCodex*.swift
Cadence/Shared/Components/CadenceChoicePicker.swift
Cadence/iOS/iOSChoicePicker.swift
Cadence/Shared/Components/CadenceTagChip.swift
Cadence/macOS/Views/SettingsAppearanceSection.swift
Cadence/CadenceApp.swift
Cadence/iOS/iOSTaskViews.swift
Cadence/iOS/iOSTaskRowActionViews.swift
Cadence/iOS/iOSTaskGroupSection.swift
Cadence/Shared/CadenceCapturePaletteSupport.swift
Cadence/iOS/iOSCaptureRadialMenu.swift
Cadence/iOS/iOSFocusView.swift
Cadence/Shared/CadenceFocusPlanningSupport.swift
CadenceWidgets/CadenceWidgetsBundle.swift
Cadence/iOS/iOSFloatingCreateTaskButton.swift
Cadence/Shared/Components/CadenceBoardMetadataChip.swift
CadenceTests/CadenceTagChipStyleTests.swift
Cadence/iOS/iOSMarkdownStylingSupport.swift
Cadence/iOS/iOSMarkdownEditor.swift
Cadence/iOS/iOSMarkdownTableGridRendering.swift
Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift
Cadence/macOS/Services/CadenceMCPRefreshCoordinator.swift
Cadence/macOS/Services/FocusManager.swift
Cadence/macOS/Services/QuickTaskPanelController.swift
Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift
Cadence/macOS/Views/TimelineDropInteractionSupport.swift
Cadence/Services/CadenceRemindersManager.swift
Cadence/Services/CadenceForkedOccurrenceRemover.swift
Cadence/Services/CadenceWidgetRefreshCenter.swift
Cadence/Services/CadenceTodayWidgetSupport.swift
Cadence/iOS/iOSCompactTabShell.swift
Cadence/iOS/iOSRootView.swift
Cadence/macOS/Views/CalendarEventPresentationSupport.swift
Cadence/iOS/iOSCalendarBoardView.swift
Cadence/iOS/iOSBoardCards.swift
Cadence/macOS/Views/GlobalSearchIndexSupport.swift
Cadence/macOS/Views/GlobalSearchSupportViews.swift
Cadence/macOS/Views/macOSRootCommandActionSupport.swift
Cadence/macOS/Views/EventNoteSupportViews.swift
Cadence/macOS/Views/NotesView.swift
Cadence/iOS/iOSTodayCompactViews.swift
Cadence/Shared/CadenceSavedLinkPersistence.swift
CadenceTests/CadenceSavedLinkPersistenceTests.swift
Cadence/macOS/Views/LinksView.swift
CadenceTests/CadenceInboxRemindersSurfaceTests.swift
CadenceTests/CadenceSharedConstantReuseSweepTests.swift
Cadence/macOS/Views/ListNotesView.swift
CadenceUITests/CadenceCapturePaletteUITests.swift
Cadence/Services/CadenceArchiveImportService.swift
CadenceTests/CadenceArchiveImportSurfaceTests.swift
Cadence/macOS/Views/CalendarPageView.swift
Cadence/macOS/Views/CalendarPageSupportViews.swift
Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift
Cadence/macOS/Views/CalendarPageComponents.swift
Cadence/macOS/Views/CalendarPageMonthSupportViews.swift
Cadence/macOS/Views/TimelineDayCanvas.swift
Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift
Cadence/macOS/Views/TimelineTaskBlock.swift
Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift
Cadence/macOS/Views/CalendarPageBoardSupportViews.swift
docs/PLATFORM_PARITY_AUDIT.md
Cadence/Shared/CadenceTaskMutationSupport.swift
CadenceTests/CalendarBoardDayDropCommitTests.swift
CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift
Cadence/Shared/CadenceTaskDateEditing.swift
CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift
Cadence/iOS/iOSCalendarManager.swift
Cadence/iOS/iOSTaskDetailSheet.swift
Cadence/iOS/iOSTaskDetailSheetSections.swift
Cadence/iOS/iOSCalendarEventEditSheet.swift
Cadence/iOS/iOSCalendarMonthViews.swift
Cadence/iOS/iOSNotesView.swift
Cadence/iOS/iOSMarkdownEditingSurface.swift
Cadence/iOS/iOSNoteEditorSheetHeader.swift
CadenceTests/CadenceCalendarFixtureEventsTests.swift
CadenceTests/CadenceCalendarChipTreatmentTests.swift
CadenceTests/CadenceNoteReferencePanelSurfaceTests.swift
CadenceTests/CadenceOutlineParserRegexTests.swift
CadenceUITests/CadenceIOSCalendarAndNoteParityUITests.swift
Cadence/iOS/iOSCalendarView.swift
Cadence/iOS/iOSCreateTaskSheet.swift
Cadence/iOS/iOSCreateTaskSheetSupportViews.swift
Cadence/macOS/Views/KanbanListColumnView.swift
Cadence/macOS/Views/KanbanColumnSupportViews.swift
Cadence/macOS/Views/KanbanSupportViews.swift
Cadence/macOS/Views/KanbanCardView.swift
Cadence/Shared/CadenceSectionEditingSupport.swift
Cadence/Shared/CadenceSectionConfigMerge.swift
Cadence/macOS/Views/ListDetailComponents.swift
Cadence/Shared/Components/CadenceSectionCreationRow.swift
Cadence/Shared/Components/CadenceSchedulePanel.swift
Cadence/Shared/Components/CadenceScheduleCaptureCard.swift
Cadence/Services/TaskCreationService.swift
Cadence/iOS/iOSTimelineDraftCreate.swift
Cadence/Shared/Components/EstimatePickerControl.swift
CadenceTests/CadenceComposerContainerSurfaceTests.swift
CadenceTests/CadenceCapturePaletteTests.swift
CadenceTests/CadenceInlineTagCommitSurfaceTests.swift
CadenceTests/CadenceChoicePickerDismissalTests.swift
CadenceTests/CadenceContainerPickerConsolidationTests.swift
CadenceTests/CadencePresentedTypographyBoundaryTests.swift
Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift
Cadence/macOS/Services/SchedulingService.swift
Cadence/Shared/CadenceTaskFieldEditCommit.swift
CadenceTests/CadenceCommentSymbolClaimTests.swift
Cadence/Shared/CadenceSettingsPresentationSupport.swift
Cadence/Shared/Components/CadenceAccentPalettePicker.swift
Cadence/Shared/Components/CadenceFieldRows.swift
Cadence/iOS/iOSArchiveImportSettingsSection.swift
Cadence/iOS/iOSCalendarChromeViews.swift
Cadence/iOS/iOSCalendarMetrics.swift
Cadence/iOS/iOSCalendarMonthAgendaViews.swift
Cadence/iOS/iOSCalendarQuickCreateSheet.swift
Cadence/iOS/iOSCalendarSettingsSection.swift
Cadence/iOS/iOSCalendarTimelineViews.swift
Cadence/iOS/iOSDataExportSettingsSection.swift
Cadence/iOS/iOSDataResetSettingsSection.swift
Cadence/iOS/iOSDateJumpTitle.swift
Cadence/iOS/iOSMarkdownReferenceSupport.swift
Cadence/iOS/iOSNotificationsSettingsSection.swift
Cadence/iOS/iOSRemindersSettingsSection.swift
Cadence/iOS/iOSSettingsComponents.swift
Cadence/iOS/iOSSettingsContextSection.swift
Cadence/iOS/iOSSettingsOverviewSections.swift
Cadence/iOS/iOSSettingsTagsSection.swift
Cadence/iOS/iOSSettingsTemplateAndListSections.swift
Cadence/iOS/iOSSettingsView.swift
Cadence/iOS/iOSSidebarLayoutSettingsSection.swift
Cadence/iOS/iOSStoreBackupSettingsSection.swift
Cadence/iOS/iOSUnmanagedStoreSettingsSection.swift
CadenceTests/CadenceRealTreeSweepManifest.txt
CadenceTests/iOSCalendarMetricsTests.swift
CadenceTests/TaskBundleTests.swift
CadenceTests/CadencePendingChangePersistenceTests.swift
CadenceTests/MarkdownImageDropAffordanceTests.swift
CadenceTests/MobileTaskSortStabilityTests.swift
CadenceTests/DataIntegrityRepairServiceTests.swift
CadenceTests/CadenceNoteFolderMoveCommitTests.swift
CadenceTests/CadenceEventKitLaunchGateTests.swift
CadenceTests/CadenceCaptureEditorTests.swift
Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift
Cadence/Shared/CadenceTodayOverdueSummarySupport.swift
Cadence/iOS/iOSTodayTaskSections.swift
Cadence/iOS/iOSTodayView.swift
CadenceTests/CadenceTodaySectionMetricsTests.swift
CadenceTests/CadenceTodayOverdueSummarySurfaceTests.swift
CadenceTests/CadenceTaskInspectorHostTests.swift
CadenceTests/CadenceSharedBoardChromeTests.swift
Cadence/Shared/CadenceScheduleDraft.swift
Cadence/macOS/Views/QuickCreateChoicePopover.swift
Cadence/macOS/Views/SchedulePanelShellViews.swift
Cadence/macOS/Views/TaskInspectorContentSupportViews.swift
Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift
Cadence/macOS/Views/TaskInspectorStatusActionsRow.swift
Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift
CadenceTests/CadenceQuickCreateTaskInspectorTests.swift
Cadence/macOS/Views/SchedulePanelComponents.swift
Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift
AGENTS.md
CadenceMCPServer/AGENTS.md
Cadence/Shared/AGENTS.md
Cadence/Models/AGENTS.md
docs/AGENTS_REFERENCE.md
docs/SHARED_AGENTS_REFERENCE.md
docs/SUBAGENT_RUNBOOK.md
.github/workflows/docs.yml
CadenceTests/AgentContextBudgetTests.swift
CadenceTests/CadenceGuardScriptSelftestTests.swift
CadenceTests/CadenceTaskContextInheritanceTests.swift
CadenceTests/CadenceTestTargetHygieneTests.swift
CadenceTests/iOSEditorSheetMetricsTests.swift
Cadence/iOS/iOSTaskDetailComponents.swift
```

Each pattern above has one row below naming the branch its grant was made for, the date it
entered the fence, the commit that added it and -- once the grant is spent -- the commit that
released it. `codex-land.sh` refuses when the two blocks disagree in either direction, so a path
cannot be fenced without recording who holds it. Ask `./scripts/codex-land.sh held <path>` rather
than reading either block by eye: *listed* and *held* are different questions, and [[T-6400]]
below is what it cost to keep answering the first one.

```lease-grants
Cadence/iOS/iOSList*.swift                                       branch=-                           granted=2026-09-27  grant=dec37fea  spent=b537dd50
Cadence/Shared/CadenceTypography.swift                           branch=-                           granted=2026-09-27  grant=991ed76e  spent=b537dd50
CadenceTests/CadenceTypographyScaleTests.swift                   branch=-                           granted=2026-09-27  grant=dec37fea  spent=b537dd50
CadenceTests/CadenceCodex*.swift                                 branch=-                           granted=2026-10-04  grant=c2ba2a77  spent=b537dd50
Cadence/Shared/Components/CadenceChoicePicker.swift              branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/iOS/iOSChoicePicker.swift                                branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/Shared/Components/CadenceTagChip.swift                   branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/macOS/Views/SettingsAppearanceSection.swift              branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/CadenceApp.swift                                         branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/iOS/iOSTaskViews.swift                                   branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/iOS/iOSTaskRowActionViews.swift                          branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/iOS/iOSTaskGroupSection.swift                            branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/Shared/CadenceCapturePaletteSupport.swift                branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/iOS/iOSCaptureRadialMenu.swift                           branch=-                           granted=2026-10-07  grant=524c3e41  spent=b537dd50
Cadence/iOS/iOSFocusView.swift                                   branch=-                           granted=2026-10-07  grant=2a508cc9  spent=b537dd50
Cadence/Shared/CadenceFocusPlanningSupport.swift                 branch=-                           granted=2026-10-07  grant=2a508cc9  spent=b537dd50
CadenceWidgets/CadenceWidgetsBundle.swift                        branch=-                           granted=2026-10-07  grant=2a508cc9  spent=b537dd50
Cadence/iOS/iOSFloatingCreateTaskButton.swift                    branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/Shared/Components/CadenceBoardMetadataChip.swift         branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
CadenceTests/CadenceTagChipStyleTests.swift                      branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/iOS/iOSMarkdownStylingSupport.swift                      branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/iOS/iOSMarkdownEditor.swift                              branch=-                           granted=2026-10-17  grant=288f86d1  spent=b537dd50
Cadence/iOS/iOSMarkdownTableGridRendering.swift                  branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift                  branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/macOS/Services/CadenceMCPRefreshCoordinator.swift        branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/macOS/Services/FocusManager.swift                        branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/macOS/Services/QuickTaskPanelController.swift            branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift     branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/macOS/Views/TimelineDropInteractionSupport.swift         branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/Services/CadenceRemindersManager.swift                   branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/Services/CadenceForkedOccurrenceRemover.swift            branch=-                           granted=2026-10-07  grant=1db66078  spent=b537dd50
Cadence/Services/CadenceWidgetRefreshCenter.swift                branch=-                           granted=2026-10-07  grant=0cbd6479  spent=b537dd50
Cadence/Services/CadenceTodayWidgetSupport.swift                 branch=-                           granted=2026-10-07  grant=0cbd6479  spent=b537dd50
Cadence/iOS/iOSCompactTabShell.swift                             branch=-                           granted=2026-10-07  grant=0cbd6479  spent=b537dd50
Cadence/iOS/iOSRootView.swift                                    branch=-                           granted=2026-10-07  grant=0cbd6479  spent=b537dd50
Cadence/macOS/Views/CalendarEventPresentationSupport.swift       branch=-                           granted=2026-10-07  grant=1be71038  spent=b537dd50
Cadence/iOS/iOSCalendarBoardView.swift                           branch=-                           granted=2026-10-08  grant=6929cfa7  spent=b537dd50
Cadence/iOS/iOSBoardCards.swift                                  branch=-                           granted=2026-10-08  grant=6929cfa7  spent=b537dd50
Cadence/macOS/Views/GlobalSearchIndexSupport.swift               branch=-                           granted=2026-10-08  grant=6929cfa7  spent=b537dd50
Cadence/macOS/Views/GlobalSearchSupportViews.swift               branch=-                           granted=2026-10-09  grant=2d9a65b3  spent=b537dd50
Cadence/macOS/Views/macOSRootCommandActionSupport.swift          branch=-                           granted=2026-10-09  grant=2d9a65b3  spent=b537dd50
Cadence/macOS/Views/EventNoteSupportViews.swift                  branch=-                           granted=2026-10-09  grant=2d9a65b3  spent=b537dd50
Cadence/macOS/Views/NotesView.swift                              branch=-                           granted=2026-10-09  grant=2d9a65b3  spent=b537dd50
Cadence/iOS/iOSTodayCompactViews.swift                           branch=-                           granted=2026-10-09  grant=2d9a65b3  spent=b537dd50
Cadence/Shared/CadenceSavedLinkPersistence.swift                 branch=-                           granted=2026-10-09  grant=11d230d5  spent=b537dd50
CadenceTests/CadenceSavedLinkPersistenceTests.swift              branch=-                           granted=2026-10-09  grant=11d230d5  spent=b537dd50
Cadence/macOS/Views/LinksView.swift                              branch=-                           granted=2026-10-09  grant=11d230d5  spent=b537dd50
CadenceTests/CadenceInboxRemindersSurfaceTests.swift             branch=-                           granted=2026-10-09  grant=c114f1f3  spent=b537dd50
CadenceTests/CadenceSharedConstantReuseSweepTests.swift          branch=-                           granted=2026-10-09  grant=ce48bb2f  spent=b537dd50
Cadence/macOS/Views/ListNotesView.swift                          branch=-                           granted=2026-10-09  grant=915b2f65  spent=b537dd50
CadenceUITests/CadenceCapturePaletteUITests.swift                branch=-                           granted=2026-10-17  grant=e5b85893  spent=b537dd50
Cadence/Services/CadenceArchiveImportService.swift               branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
CadenceTests/CadenceArchiveImportSurfaceTests.swift              branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/CalendarPageView.swift                       branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/CalendarPageSupportViews.swift               branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift   branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/CalendarPageComponents.swift                 branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/CalendarPageMonthSupportViews.swift          branch=-                           granted=2026-10-17  grant=4fdd74ed  spent=b537dd50
Cadence/macOS/Views/TimelineDayCanvas.swift                      branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift         branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/TimelineTaskBlock.swift                      branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift          branch=-                           granted=2026-10-16  grant=840fe34f  spent=b537dd50
Cadence/macOS/Views/CalendarPageBoardSupportViews.swift          branch=-                           granted=2026-10-16  grant=7ef2fde2  spent=b537dd50
docs/PLATFORM_PARITY_AUDIT.md                                    branch=-                           granted=2026-10-16  grant=38224bd8  spent=b537dd50
Cadence/Shared/CadenceTaskMutationSupport.swift                  branch=-                           granted=2026-10-16  grant=e616745b  spent=b537dd50
CadenceTests/CalendarBoardDayDropCommitTests.swift               branch=-                           granted=2026-10-16  grant=e616745b  spent=b537dd50
CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift           branch=-                           granted=2026-10-16  grant=e616745b  spent=b537dd50
Cadence/Shared/CadenceTaskDateEditing.swift                      branch=-                           granted=2026-10-17  grant=2b393a28  spent=b537dd50
CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift        branch=-                           granted=2026-10-17  grant=1b198364  spent=b537dd50
Cadence/iOS/iOSCalendarManager.swift                             branch=-                           granted=2026-10-18  grant=e6a226b6  spent=b537dd50
Cadence/iOS/iOSTaskDetailSheet.swift                             branch=-                           granted=2026-10-19  grant=3b4756e2  spent=b537dd50
Cadence/iOS/iOSTaskDetailSheetSections.swift                     branch=-                           granted=2026-10-19  grant=3b4756e2  spent=b537dd50
Cadence/iOS/iOSCalendarEventEditSheet.swift                      branch=-                           granted=2026-10-19  grant=3b4756e2  spent=b537dd50
Cadence/iOS/iOSCalendarMonthViews.swift                          branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
Cadence/iOS/iOSNotesView.swift                                   branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
Cadence/iOS/iOSMarkdownEditingSurface.swift                      branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
Cadence/iOS/iOSNoteEditorSheetHeader.swift                       branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
CadenceTests/CadenceCalendarFixtureEventsTests.swift             branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
CadenceTests/CadenceCalendarChipTreatmentTests.swift             branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
CadenceTests/CadenceNoteReferencePanelSurfaceTests.swift         branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
CadenceTests/CadenceOutlineParserRegexTests.swift                branch=-                           granted=2026-10-17  grant=b7cd0fcf  spent=b537dd50
CadenceUITests/CadenceIOSCalendarAndNoteParityUITests.swift      branch=-                           granted=2026-10-17  grant=288f86d1  spent=b537dd50
Cadence/iOS/iOSCalendarView.swift                                branch=-                           granted=2026-10-17  grant=8171fff2  spent=b537dd50
Cadence/iOS/iOSCreateTaskSheet.swift                             branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/iOS/iOSCreateTaskSheetSupportViews.swift                 branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/macOS/Views/KanbanListColumnView.swift                   branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/macOS/Views/KanbanColumnSupportViews.swift               branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/macOS/Views/KanbanSupportViews.swift                     branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/macOS/Views/KanbanCardView.swift                         branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/Shared/CadenceSectionEditingSupport.swift                branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/Shared/CadenceSectionConfigMerge.swift                   branch=-                           granted=2026-10-17  grant=d2d86efb  spent=b537dd50
Cadence/macOS/Views/ListDetailComponents.swift                   branch=-                           granted=2026-10-17  grant=4fca5348  spent=b537dd50
Cadence/Shared/Components/CadenceSectionCreationRow.swift        branch=-                           granted=2026-10-17  grant=4fca5348  spent=b537dd50
Cadence/Shared/Components/CadenceSchedulePanel.swift             branch=-                           granted=2026-10-17  grant=4fca5348  spent=b537dd50
Cadence/Shared/Components/CadenceScheduleCaptureCard.swift       branch=-                           granted=2026-10-17  grant=4fca5348  spent=b537dd50
Cadence/Services/TaskCreationService.swift                       branch=-                           granted=2026-10-17  grant=4fca5348  spent=b537dd50
Cadence/iOS/iOSTimelineDraftCreate.swift                         branch=-                           granted=2026-10-17  grant=e78488b7  spent=b537dd50
Cadence/Shared/Components/EstimatePickerControl.swift            branch=-                           granted=2026-10-17  grant=fac1bee9  spent=b537dd50
CadenceTests/CadenceComposerContainerSurfaceTests.swift          branch=-                           granted=2026-10-17  grant=e5b85893  spent=b537dd50
CadenceTests/CadenceCapturePaletteTests.swift                    branch=-                           granted=2026-10-17  grant=a985429c  spent=b537dd50
CadenceTests/CadenceInlineTagCommitSurfaceTests.swift            branch=-                           granted=2026-10-17  grant=a985429c  spent=b537dd50
CadenceTests/CadenceChoicePickerDismissalTests.swift             branch=-                           granted=2026-10-17  grant=a985429c  spent=b537dd50
CadenceTests/CadenceContainerPickerConsolidationTests.swift      branch=-                           granted=2026-10-17  grant=a985429c  spent=b537dd50
CadenceTests/CadencePresentedTypographyBoundaryTests.swift       branch=-                           granted=2026-10-17  grant=a985429c  spent=b537dd50
Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift          branch=codex/block-removal-finish  granted=2026-10-20  grant=25e925dc  spent=6803ddda
Cadence/macOS/Services/SchedulingService.swift                   branch=codex/block-removal-finish  granted=2026-10-20  grant=25e925dc  spent=6803ddda
Cadence/Shared/CadenceTaskFieldEditCommit.swift                  branch=codex/block-removal-finish  granted=2026-10-20  grant=25e925dc  spent=6803ddda
CadenceTests/CadenceCommentSymbolClaimTests.swift                branch=codex/block-removal-finish  granted=2026-10-20  grant=25e925dc  spent=6803ddda
Cadence/Shared/CadenceSettingsPresentationSupport.swift          branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/Shared/Components/CadenceAccentPalettePicker.swift       branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/Shared/Components/CadenceFieldRows.swift                 branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSArchiveImportSettingsSection.swift                branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSCalendarChromeViews.swift                         branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSCalendarMetrics.swift                             branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSCalendarMonthAgendaViews.swift                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSCalendarQuickCreateSheet.swift                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSCalendarSettingsSection.swift                     branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSCalendarTimelineViews.swift                       branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSDataExportSettingsSection.swift                   branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSDataResetSettingsSection.swift                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSDateJumpTitle.swift                               branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSMarkdownReferenceSupport.swift                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSNotificationsSettingsSection.swift                branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSRemindersSettingsSection.swift                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSettingsComponents.swift                          branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSettingsContextSection.swift                      branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSettingsOverviewSections.swift                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSettingsTagsSection.swift                         branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSettingsTemplateAndListSections.swift             branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSettingsView.swift                                branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSSidebarLayoutSettingsSection.swift                branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSStoreBackupSettingsSection.swift                  branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
Cadence/iOS/iOSUnmanagedStoreSettingsSection.swift               branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
CadenceTests/CadenceRealTreeSweepManifest.txt                    branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
CadenceTests/iOSCalendarMetricsTests.swift                       branch=codex/text-scale-finish     granted=2026-10-20  grant=e711077c  spent=e711077c
CadenceTests/TaskBundleTests.swift                               branch=codex/block-removal-finish  granted=2026-10-20  grant=e5ff6599  spent=6803ddda
CadenceTests/CadencePendingChangePersistenceTests.swift          branch=codex/t3260-source-pins     granted=2026-10-21  grant=993cc30a  spent=9d26528e
CadenceTests/MarkdownImageDropAffordanceTests.swift              branch=codex/t3260-source-pins     granted=2026-10-21  grant=993cc30a  spent=9d26528e
CadenceTests/MobileTaskSortStabilityTests.swift                  branch=codex/t3260-source-pins     granted=2026-10-21  grant=44e84dbe  spent=9d26528e
CadenceTests/DataIntegrityRepairServiceTests.swift               branch=codex/t3260-source-pins     granted=2026-10-21  grant=44e84dbe  spent=9d26528e
CadenceTests/CadenceNoteFolderMoveCommitTests.swift              branch=codex/t3260-source-pins     granted=2026-10-21  grant=44e84dbe  spent=9d26528e
CadenceTests/CadenceEventKitLaunchGateTests.swift                branch=codex/t3260-source-pins     granted=2026-10-21  grant=44e84dbe  spent=9d26528e
CadenceTests/CadenceCaptureEditorTests.swift                     branch=codex/t3260-source-pins     granted=2026-10-21  grant=44e84dbe  spent=9d26528e
Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift  branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
Cadence/Shared/CadenceTodayOverdueSummarySupport.swift           branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
Cadence/iOS/iOSTodayTaskSections.swift                           branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
Cadence/iOS/iOSTodayView.swift                                   branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
CadenceTests/CadenceTodaySectionMetricsTests.swift               branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
CadenceTests/CadenceTodayOverdueSummarySurfaceTests.swift        branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
CadenceTests/CadenceTaskInspectorHostTests.swift                 branch=codex/batch2-cleanup        granted=2026-10-21  grant=04d51751  spent=82901ff6
CadenceTests/CadenceSharedBoardChromeTests.swift                 branch=codex/batch2-cleanup        granted=2026-10-21  grant=9e020baa  spent=82901ff6
Cadence/Shared/CadenceScheduleDraft.swift                        branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/QuickCreateChoicePopover.swift               branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/SchedulePanelShellViews.swift                branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/TaskInspectorContentSupportViews.swift       branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift         branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/TaskInspectorStatusActionsRow.swift          branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift      branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
CadenceTests/CadenceQuickCreateTaskInspectorTests.swift          branch=codex/subtasks-inspector    granted=2026-10-23  grant=460313ab  spent=21834d4c
Cadence/macOS/Views/SchedulePanelComponents.swift                branch=codex/subtasks-inspector    granted=2026-10-23  grant=6bb56ed7  spent=21834d4c
Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift       branch=codex/subtasks-inspector    granted=2026-10-23  grant=6bb56ed7  spent=21834d4c
AGENTS.md                                                        branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
CadenceMCPServer/AGENTS.md                                       branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
Cadence/Shared/AGENTS.md                                         branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
Cadence/Models/AGENTS.md                                         branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
docs/AGENTS_REFERENCE.md                                         branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
docs/SHARED_AGENTS_REFERENCE.md                                  branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
docs/SUBAGENT_RUNBOOK.md                                         branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
.github/workflows/docs.yml                                       branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
CadenceTests/AgentContextBudgetTests.swift                       branch=codex/agents-cap-t3149      granted=2026-10-23  grant=703df4f9  spent=7198f79e
CadenceTests/CadenceGuardScriptSelftestTests.swift               branch=codex/subtasks-inspector    granted=2026-10-23  grant=78e5e26e  spent=21834d4c
CadenceTests/CadenceTaskContextInheritanceTests.swift            branch=codex/subtasks-inspector    granted=2026-10-23  grant=78e5e26e  spent=21834d4c
CadenceTests/CadenceTestTargetHygieneTests.swift                 branch=codex/subtasks-inspector    granted=2026-10-23  grant=78e5e26e  spent=21834d4c
CadenceTests/iOSEditorSheetMetricsTests.swift                    branch=codex/subtasks-inspector    granted=2026-10-23  grant=78e5e26e  spent=21834d4c
Cadence/iOS/iOSTaskDetailComponents.swift                        branch=codex/ios-inline-tags       granted=2026-10-24  grant=f487409b  spent=2a834d88
```

### 2026-10-25 — [[T-6400]]: what the fence actually HOLDS, path by path, and the field that makes it expire

**The defect.** `codex-land.sh lease` answers *is this path listed*. Nobody has ever needed that
answer. The question every reader of this block is actually asking is *is this path held*, and the
block cannot answer it, because a grant is for a BRANCH and the block records no branch. A line
added for a branch that landed three days ago looks exactly like a line added for a branch that is
being written right now. So the list only ever grows, and on 2026-10-24 it cost a full round trip:
the coordinator matched five tickets against the block with fnmatch, found every path listed, and
routed all five to Codex, which handed the whole batch back. It is the sixth instance of this
document's own 2026-10-17 synthesis -- *each test answered a cheaper question than the one being
asked* -- and the first one where the cheaper question is baked into the data rather than into a
test over it.

**The repair, in two halves.** The `lease-grants` block above carries, per pattern, the branch the
grant was made for, the date it entered the fence, the commit that added it, and -- when the grant
is spent -- the commit that released it. `./scripts/codex-land.sh held <path>` reads those and
reports HELD, RESERVED, SPENT or UNFENCED; `lease --status` does it for the whole block.
`CODEX-LEASE-UNRECORDED` refuses whenever the two blocks disagree in either direction, which is
what makes it impossible to add a path to the fence again without saying who holds it.

**Why `spent=` is checked and `grant=` is not.** `grant=` is provenance a reader follows by hand.
`spent=` is the field that releases a path, so a release recorded against a commit that does not
resolve, or that is not an ancestor of `main`, is reported as HELD and not as spent. Where no
`spent=` is recorded the status is MEASURED from the branch: the files its own `--no-merges`
commits touched that match the pattern, each asked whether `main` already has that blob. A branch
that exists but has written nothing under its pattern reports RESERVED rather than SPENT -- that is
the `iOSSearchView.swift` shape of 2026-10-24, a hold on a file nobody is writing, and it is a
question for the coordinator, not something this script decides.

**The result of the audit: NOTHING in the fence is currently held.** 175 distinct patterns, every
one determined:

| grant | branch | paths | determination | evidence |
|---|---|---|---|---|
| everything in the block at `b537dd50` | not recorded | 104 | **SPENT** | the 2026-10-20 blanket release; [[T-3257]]'s audit of exactly these patterns |
| `e711077c` 10-20 | `codex/text-scale-finish` | 27 | **SPENT** | that commit *is* the landing ([[T-1364]] CLOSED) |
| `25e925dc` 10-20 | `codex/block-removal-finish` | 4 | **SPENT** | `6803ddda` 10-21 landed it; `main` has since moved `staleClaims` 10 -> 0 |
| `e5ff6599` 10-20 | `codex/block-removal-finish` | 1 | **SPENT** | same landing; `TaskBundleTests.swift` blob is in `main` |
| `04d51751` / `9e020baa` 10-21 | `codex/batch2-cleanup` | 8 | **SPENT** | `82901ff6` 10-22 ([[T-3078]] CLOSED) |
| `993cc30a` / `44e84dbe` 10-21 | `codex/t3260-source-pins` | 7 | **SPENT** | `9d26528e` ([[T-4100]] CLOSED, zero conversions); branch tip `cf9f3297` is documentation only |
| `460313ab` / `6bb56ed7` / `78e5e26e` 10-23 | `codex/subtasks-inspector` | 14 | **SPENT** | `21834d4c` 10-24 ([[T-1611]] CLOSED) |
| `703df4f9` 10-23 | `codex/agents-cap-t3149` | 9 | **SPENT** | `7198f79e` 10-23 ([[T-3149]] CLOSED) |
| `f487409b` 10-24 | `codex/ios-inline-tags` | 1 | **SPENT** | `2a834d88` 10-24 ([[T-5307]] CLOSED) |

Cross-checked against the branches rather than against the commit subjects: of the 71 post-release
patterns, four path/branch pairs differ from `main` by bytes, and all four are stale rather than
live -- `codex/continuous-quote-rail` and `codex/unified-editors` have every line their own commits
added present in `main`; `codex/tracking-ui-retirement`'s one missing manifest row names a suite
that does not exist in `main` and the manifest is a GENERATED file; `codex/block-removal-finish`'s
two missing lines are the count assertion `main` moved past at `6803ddda`. No `codex/*` worktree
holds a dirty source file -- the only modification anywhere under `~/.codex/worktrees` is
`docs/CODEX_LEDGER_INBOX.md` in `codex/branch-audit`'s.

**The 2026-10-21 `CadenceArchiveImportService.swift` contradiction, resolved.** This document was
read as fencing that path on 2026-10-21 in `44e84dbe`, i.e. AFTER the blanket release, while Codex
returned [[T-4720]] as covered BY that release. Codex is right and the reading was wrong.
`git log -S'<path>' -- docs/CODEX_WORKTREE.md` returns `44e84dbe` first, but that commit's only
occurrence of the string is **prose** -- "`Cadence/Services/CadenceArchiveImportService.swift`, was
already fenced" -- inside the grant note, not a line in the block. The fence line was added by
`840fe34f` on 2026-10-16, restating `f00429c0`'s T-3121 grant of the same day, and the path is
present in `git show b537dd50:docs/CODEX_WORKTREE.md`. It is released. **`-S` answers *did the
count of this string change here*, which is a cheaper question than *was this path fenced here*;
it does not distinguish an addition from a removal, nor a fence line from a sentence.** The test
that settles it is membership in the block AT `b537dd50`, which is what this audit used throughout
and what the `granted=` dates in `lease-grants` were derived from.

**What did NOT change.** Not one pattern was removed from the `lease` block and not one was
widened. The block still governs what **Codex** may write, exactly as the 2026-10-20 entry says,
and deleting a spent line would narrow Codex's write scope and redden `review` on any branch that
still touches it. Four lines that appeared twice (`iOSCalendarManager.swift`,
`iOSMarkdownEditor.swift`, `CalendarPageMonthSupportViews.swift`,
`CadenceCapturePaletteUITests.swift`) were collapsed to one each, which changes nothing a glob
matches; the count reads 175 rather than 179 for that reason alone.

**For whoever makes the next grant.** Add the pattern to `lease` and its row to `lease-grants` in
the same commit -- `review` refuses otherwise -- and name the branch, not the ticket. When that
branch lands, add `spent=<landing sha>` in the landing commit. Do not fence a path before the job
that needs it is running; `held` will report it RESERVED and the next reader will have to ask.

**Admission 2026-10-19 (coordinator), one line in `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift`.**
That file is leased above and stays leased. The coordinator changed exactly one assertion in it --
the inline-notice census `#expect(total == 68, ...)` to `67`, with the comment sentence the census
block's house style requires -- and nothing else in the file. **Why it could not wait for Codex:**
`d32ae3a1` (T-3171's seventh adoption slice) removed a notice call site by folding
`QuickCreateChoicePopover`'s form into the shared panel, so the census pinned a number the tree no
longer held and `main` was red on a count CI reproduces regardless of local worktrees. Agent
`dragcreate` measured it, correctly refused to touch a leased path, and requested the grant rather
than taking it. **Checked before admitting:** `codex/unified-editors`, the branch waiting to land,
never opens this file. `codex/ios-board-drop-refusal` does -- it moves the same census 67 -> 68 by
ADDING the mobile board's refused-drop notice, from a base that read 67. That branch is one commit
ahead of `main` and unlanded; its product change (`Cadence/iOS/iOSCalendarBoardView.swift`) is not
on `main`. Whoever lands it should expect a one-line conflict in this comment block and resolve it
to 68, because its notice is a real added call site on top of this 67.

**Admission 2026-10-22 (keeper), one line in `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift`.**
That file is leased above and stays leased. The keeper admitted agent `census2040` for exactly one
assertion in it -- the inline-notice census `#expect(total == 67, ...)` to `68`, with the comment
sentence the census block's house style requires -- and nothing else in the file. **Why it could not
wait for Codex:** `e56883a3` ([[T-4722]]) added a bare `CadenceInlineFailureNotice(text:
renameFailureNotice)` to the Mac `ContextSettingsRow`, so `main` was red in CI (run 39876286334) on a
count CI reproduces regardless of local worktrees. **Checked before admitting:** every `codex/*`
branch whose copy of the file differs from `main` was measured with `git diff --stat main <branch>
-- <file>`; each difference is deletions-only from `main`'s side plus the branch's older count line
(67, 68, 69 or 70), so no branch is ahead of `main` in this file. The one branch with its own
commits on it, `codex/ios-board-drop-refusal`, carries the PA-13 / T-1470 sentence that is already
on `main`. The 2026-10-19 note above that it would conflict is stale for this file.

**Admission 2026-10-23 (keeper), the census assertions in `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift`.**
That file is leased above and stays leased. The keeper (`keeper0508`) admitted agent `census0508`
for exactly the census assertions inside `onlyNoticesNoLaterAttemptClearsOfferToDismissThemselves`
-- the sweep's `hits` list, `#expect(total == 69, ...)` to `71`, `#expect(withDismissal == 7, ...)`
to `8`, the named per-file list, the counting comments those touch, and one house-style sentence per
added call site -- and nothing else in the file. **Why it could not wait for Codex:** `dad46473`
([[T-5015]]) added a bare `CadenceInlineFailureNotice(text: failureNotice)` to the Mac
`TaskInspectorStatusActionsRow`, and `65389afc` ([[T-5014]]) added a dismissable
`CadenceInlineFailureNotice(text: embeddedTaskFailureNotice) { ... }` to the Mac inspector's
`TaskDetailNotesSection`, so `main` was red in CI (run 39900552169) on a count CI reproduces
regardless of local worktrees. **Checked before admitting:** every `codex/*` branch whose copy of the
file differs from `main` was measured with `git diff --stat main <branch> -- <file>` (33 branches);
each difference is deletions from `main`'s side plus at most the branch's older count line, so no
branch is ahead of `main` in this file. The one branch with its own commit on it,
`codex/ios-board-drop-refusal` (`405806ff`), adds only its old `total == 68` line; its PA-13 sentence
is already on `main`.

**Admission 2026-10-24 (keeper), one line in `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift` and one doc comment in `Cadence/macOS/Views/EventNoteSupportViews.swift`.**
Both files are leased above and stay leased. The keeper (`keeper0602`) changed exactly the census
`#expect(total == 77, ...)` to `78` with its house-style sentence, and the one doc-comment symbol
`iOSEventNoteEditorSheet.syncNoteToNativeEvent` to `iOSEventNoteCommit.syncNoteToNativeEvent` --
nothing else in either file. **Why it could not wait for Codex:** `f7deed74` ([[T-5804]]) added a bare
`CadenceInlineFailureNotice(text: eventNoteCommitNotice)` to `iOSNotesView` and moved that function
into `iOSEventNoteCommit`, so `main` was red in CI (run 40084215147) on two counts CI reproduces
regardless of local worktrees. **Checked before admitting:** every local `codex/*` branch with its own
commits on either file (`git log main..<branch> -- <file>`): `codex/ios-board-drop-refusal` (its old
census line only, as above), and `codex/data-safety-audit-fixes` / `codex/parity-functional-batch`
(2026-10-05 / 2026-10-09, hunks in `EventNoteEditorSheet`, none near the edited comment).

**Admission 2026-10-24 (keeper `keeper1338`), the `TaskNoteLinkRouting` enum in `Cadence/macOS/Views/TaskInspectorContentSupportViews.swift`, for [[T-6092]] only.**
The file is leased above and stays leased. Agent `land6092` may change the two `listNavigation.open(...)`
calls in `TaskNoteLinkRouting` to pass `listNoteID: note.id`, and that enum's doc comment -- nothing
else in the file. If the fix needs `EventNoteSupportViews.swift` (also leased), the agent stops and
files a ticket rather than editing it. **Why it could not wait for Codex:** a decision-free, visible
note-link defect for the next RC, already written as WIP `dace8f3a`. **Checked before admitting:**
every local `codex/*` branch with its own commits on the file (`git log --no-merges main..<branch>`):
`codex/subtasks-inspector` (its copy is identical to `main`, landed as [[T-3171]]) and
`codex/data-safety-audit-fixes` (2026-10-05); no `codex/*` worktree has the file dirty.

**Admissions 2026-10-24 (keeper `keeper1408`), three narrow sub-file grants, each for one ticket only.**
Every file named stays leased; nothing else in it may be edited. **Why they could not wait for Codex:**
each is a decision-free (or owner-decided at `887b2139`) visible defect for the next RC.
**Checked before admitting:** `git log --no-merges main..<branch>` on every local `codex/*` branch --
`codex/capture-list-sections` touched `ListDetailComponents.swift` (2026-10-17), `codex/ui-refresh-reconciliation`
`CadenceApp.swift` (2026-10-16), `codex/tracking-ui-retirement` `iOSTaskDetailSheetSections.swift` (2026-10-05);
no `codex/*` worktree has any of these files dirty.
- Agent `maccmd1310` (re-addressed from the never-launched `cmdn1408`; the coordinator assigned it these tickets at `725c5279`), [[T-5302]] only: in `Cadence/macOS/Services/QuickTaskPanelController.swift`, the
  resign-key close path and the panel's open path may keep and restore the half-typed draft (cleared
  on save or Esc), per the owner's decision (b). ([[T-5953]]'s `Cadence/CadenceApp.swift` is already
  released to local agents under the 2026-10-20 rule, as that entry records.)
- Agent `maccmd1310` (re-addressed from the never-launched `search1408`), [[T-5832]] half (b) only: in `Cadence/macOS/Views/ListDetailComponents.swift`,
  the "+ Section" row's visibility condition (shown only under By List), per the owner's decision (a).
- Agent `floor1408`, [[T-6114]] only: in `Cadence/macOS/Views/TaskInspectorWorkflowSupportViews.swift`
  and `Cadence/iOS/iOSTaskDetailSheetSections.swift`, the After-count resolve call and the count
  picker's choices / the count field's clamp, so they floor at the current occurrence number through a
  shared helper in the lease-free `Cadence/Shared/CadenceTaskRecurrenceEndPresentation.swift`. The seed
  value of 10 must not change (owner decision).

### 2026-10-17 — WHY ALL SIX VERSIONS FAILED: each asked a cheaper question than the one being asked

Agent `blocktail`'s synthesis, recorded because it explains every failure above with one sentence
and predicts the next one.

**Each test answered a cheaper question than the one being asked, and read clean because of it:**

| test | the question asked | the question answered |
|---|---|---|
| ahead-of-main | did anyone change this path | is the branch ahead at all |
| `codex-land.sh review` | is this path safe | did the first check pass |
| blob vs main | did anyone change it | is it the same right now |
| modified-vs-own-base | did anyone change it | did it change since the branch began |
| symbol sampling | did anyone EDIT this | was this name ADDED |
| the agent's grep | does this test break | is the symbol mentioned |

Every one is a real check. Every one is cheaper than the question, and the gap is where it fails —
quietly, because a cheaper question returns an answer either way.

**It predicts its own successor's failure.** The date check — "is any branch touching it dated
inside this session" — answers *is it recent*, not *is it live*. A long-running branch nobody
touched today will answer wrongly. **Expect a seventh correction and do not be surprised by it.**

**The one clean signal found today**, worth more than the ladder: 24 branches report the identical
September 4 commit `1b29d07b` on `TaskCreationService.swift`, and exactly one —
`codex/capture-list-sections` — is dated today. The live branch is not merely different, it is the
only one that is not a six-week-old echo of the same commit. **Distribution is more legible than any
individual comparison**: when 24 of 25 agree exactly, the outlier is the finding.

**The practical rule for the next coordinator:** do not look for a test that settles it. Narrow with
`--no-merges`, then look at the SHAPE of what comes back. A path everyone touched identically six
weeks ago is a graveyard. A path one branch touched today, with "pending" in its commit message, is
someone's live work.

### 2026-10-17 — SIXTH refinement: symbol sampling cannot see a MODIFIED function body

A pre-check for T-3170's stale-claims pass nearly cleared `Cadence/Services/TaskCreationService.swift`
as landed. It is **live work by the second Codex agent** and must not be touched.

**How it nearly passed.** `codex/capture-list-sections` modifies that file; all four sampled
function names — `availableSections`, `normalizedSectionName`, `applyContainer`, `insertTask` —
report PRESENT on main. By the symbol test recorded above, that reads as landed.

**They are present because they already existed.** The branch CHANGED their bodies; it added no new
declarations. **Symbol sampling detects added symbols, never modified ones** — so any branch whose
work is edits rather than additions samples as landed, which is most refactoring work.

**What actually settled it, and the order to use:**
1. **Branch date** — `10-17 22:38`, i.e. today, while this session was running.
2. **Commit message** — *"T-3192 T-3195 checkpoint shared section entry and capture card; event ends
   pending"*. A branch that calls itself a checkpoint with something pending is not landed.
3. **Blob differs from main.**

Together those are conclusive where symbols were not. **For a file a live agent may be holding,
cheapest reliable check is: is any branch touching it dated inside this session?** A stale branch
cannot be — the graveyard is weeks old.

**The accumulated rule, after six corrections in one day:** no single signal answers "is this path
safe to grant". `--no-merges` narrows the candidates; symbol sampling resolves ADDITIVE branches;
date and commit message resolve live ones; the blob confirms. Every version of this test that was
recorded as sufficient has been falsified by its next real use, and this entry should be read as
likely to be too.

### 2026-10-17 — CORRECTION: the grant I praised an agent for NOT requesting was needed after all

The section below records agent `blocktail` declining to request
`CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift` because it could not reproduce the
blocker, and the coordinator endorsing that as the rarer, better instinct. **The blocker was real.
Granting it now, and correcting the praise rather than quietly adding the path.**

**Why both of us missed it.** The agent grepped for `bundle`, `Bundle` and the symbols the pass
removes. That file contains none — the grep was accurate. But `:494` asserts
`#expect(total == 69)` over a repo-wide census of `CadenceInlineFailureNotice` call sites, and this
pass removes one. Measured now: the literal says 69, the tree holds **68**.

**A census test names no symbol from the thing it counts.** No symbol grep could ever have found it,
on either side. The agent put the distinction better than the coordinator had: the honest claim was
*"I cannot find a textual reference"*, not *"I cannot reproduce it as a blocker"* — and the gap
between those is exactly the [[T-3209]] shape, **a check that comes back clean because it was asking
the wrong question.**

**What survives of the original praise:** declining to request a grant on an unreproduced claim is
still right, and the agent did come back with the error rather than the assertion, exactly as it
said it would. What does not survive is the coordinator's gloss that the heartbeat's report was
*"someone else's mistake"*. It was not a mistake. It was a real blocker found by running the thing,
which beats any amount of grepping — and the heartbeat had run it.

**GRANTED:** that path, scope the `:494` literal `69 → 68` plus its explanatory comment. The
surrounding prose already carries a [[T-1475]] history of the same number moving, so there is a
house style to follow.

### 2026-10-17 — one line in `CadenceSharedConstantReuseSweepTests.swift`, and an agent declining to ask

**GRANTED to a local agent for [[T-3170]]'s trio pass.** Prose: the file is already inside the fence,
so this admits local entry. Verified landed with `--no-merges` — one branch modified it,
`codex/parity-functional-batch`, confirmed landed earlier today.

**Scope is literally one line.** `:177` carries
`path: "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift"` inside a
`CadenceUndeclaredPlaceholderLabel` inventory of a file the trio pass deletes. Removing that row is
the entire repair.

**The part worth recording is the grant NOT requested.** A heartbeat run listed three blockers; the
agent reproduced two and could not reproduce the third — `CadenceMarkdownImageCommitSurfaceTests.swift`
contains no reference to `bundle`, `Bundle`, or any symbol the pass removes. It declined to request a
grant on an unreproduced claim, saying it would come back with the error rather than the assertion if
the run disagreed. Confirmed independently: **zero bundle references in that file.**

That is the right instinct and the rarer one. A blocker inherited from another run's report is as
unverified as any other inherited claim, and the cheap move — ask for all three, since asking is
free — would have widened the fence on someone else's mistake.

### 2026-10-18 — GRANT for [[T-3215]]: the CI crash fix, two lines, any local agent

**Published because an agent refused to act without it, correctly.** Agent `crashfix` was briefed to
fix the crash, found that `CadenceTests/CadenceCodexTaskListVirtualizationTests.swift` sits inside
the fence via `CadenceTests/CadenceCodex*.swift`, read the only prose grant on that path, and
established it fails three ways: it names **T-1475 / T-1479 / T-3211**, not T-3215; it says "same
path, same agent", meaning `parkedland`, not `crashfix`; and the granted edit is the probe re-key,
not a save/autosave change. It made no edits and took no test-host lock. Verified independently:
`rg -c '3215' docs/CODEX_WORKTREE.md` returned **0** before this section existed.

**GRANTED to any local agent, for T-3215 only, scoped to exactly two edits inside
`theProbeReadsAnEagerListAsFarLargerThanALazyOne`:**
1. Insert `context.autosaveEnabled = false` immediately after `let context = container.mainContext`
   (`:101`), before the insert loop.
2. Delete `try context.save()` (`:109`).

**Both halves are required and this is the correction that nearly did not get made.** A sibling
proposed removing the save alone. `container.mainContext.autosaveEnabled` defaults to **`true`** —
recorded at `Cadence/macOS/Views/SettingsView.swift:376` and the reason `CadenceApp.swift:15` sets
it `false` — and the test file contains **zero** occurrences of `autosaveEnabled`. So dropping the
save alone lets autosave post the same notification a runloop turn later, inside
`layoutSubtreeIfNeeded` or the probe's `RunLoop.main.run(until:)`, where it is far harder to read.

**NOT granted:** deleting or weakening the test. It is the negative control proving the probe reads
1000 for an eager `VStack` against 16 for the real page. `crashfix` verified read-only that the fix
cannot threaten it — the eager control renders `ForEach(seeded)` over an in-memory array with no
`@Query` in its view tree, so inserted-but-unsaved objects render identically.

**The stale-observer teardown is NOT in this grant and should be its own ticket.** `crashfix`
assessed it read-only and it is not the small clean change hoped for: the sibling test's `defer`
only does `window.contentView = nil; window.close()`, which drops the window's reference without
deterministically deallocating the `NSHostingView`, and the four containers are loop-locals.
`_SwiftData_SwiftUI` observers unregister on the hosting view's dealloc, deferred here to an
autorelease pool drain the test never forces. A deterministic teardown needs an explicit
`autoreleasepool` per iteration **plus** a way to assert the observer actually unregistered, and
there is no public API for that second half.

**Whoever lands this: a local pass proves nothing.** The crash does not reproduce on this Mac
(Xcode 27 / macOS 27); CI pins Xcode 26.0.1 on macOS 26.6.2. Only a green CI run confirms it.

### 2026-10-18 — the sequenced grant is PUBLISHED: `iOSCalendarManager.swift` opens for the second Codex agent

**The dependency cleared.** `f1fe7afc` landed T-1483, and the fixture door is on main at both halves
— `rg -c CadenceCalendarFixtureEvents Cadence/iOS/iOSCalendarManager.swift` = 2, and the two
`iOSCalendarView` caller guards = 2. This grant was refused twice while that work existed only on a
branch, which was the right call: the question was never whether the work existed, but whether a
second agent would be editing a file whose other version was unlanded.

**GRANTED, narrowly:** `eventRecurrenceRule` and `createEvent` only, to take defaulted recurrence
end-mode / date / count parameters, then forward the draft fields through the already-granted
`Cadence/iOS/iOSTimelineDraftCreate.swift`.

**Follow the precedent already in that file.** `createEvent`'s own comment reads *"Defaulted, so the
two existing callers are byte-for-byte unchanged."* The new parameters must do the same.

**NOT granted by this, and all three are the owner's standing decisions on [[T-3195]]:** no schema
change, no new repeat intervals beyond the five persisted cases, and no second EventKit save — the
recurrence rides the original creation commit.

**Do not touch the fixture door that just landed.** The `:101-103` fixture calls sit ahead of the
`:105` `isAuthorized` guard, and the paired `if let` cannot half-open because both providers gate on
the same `isActive()`. That property is what makes the harness safe; it is not to be refactored past.

### 2026-10-17 — `EstimatePickerControl.swift` granted; `iOSCalendarManager.swift` still REFUSED

**GRANTED:** `Cadence/Shared/Components/EstimatePickerControl.swift`, for an optional unset-value
label on `EstimatePickerPopoverContent`. Existing callers keep "None"; capture alone says "Clear
estimate". No storage semantics change. Clean in the worktree; **no `codex/*` branch has modified
it** (`--no-merges`).

Granted readily because of the shape: an OPTIONAL parameter whose default preserves every existing
caller byte-for-byte is the same discipline `createEvent` already documents — *"Defaulted, so the
two existing callers are byte-for-byte unchanged."* A shared control gaining a capture-specific
wording without a second control is the right answer.

**STILL REFUSED: `Cadence/iOS/iOSCalendarManager.swift`.** The second Codex agent asked whether the
first agent's T-1483 fixture door had landed. **It has not** — `rg CadenceCalendarFixtureEvents`
returns nothing in that file. The sequencing recorded earlier stands unchanged, and the agent said
in advance it would keep the file untouched if the answer was no, which is the correct posture.

**Already granted, no action needed:** `CadenceTests/CadenceCapturePaletteTests.swift` entered the
fence earlier today. Asking again cost nothing and is better than assuming a remembered grant still
covers a new edit — the opposite assumption is what made `63b024d6` too narrow.

### 2026-10-17 — `CadenceCodexSearchOptimizationTests.swift`: a FOURTH search path, and a lesson about where grants come from

**GRANTED to a local agent for [[T-1476]] / [[T-1473]].** Prose, not a fence line: the file is
already inside the fence via the standing `CadenceTests/CadenceCodex*.swift` glob, so what is
granted here is a LOCAL agent's entry, exactly as for the three paths in `63b024d6`.

**Why `63b024d6` missed it.** That grant was written from the parity audit's evidence rather than
from the code. The audit found the `:129` pin in `CadenceCodexFunctionalParityTests`; it never found
this one. **`:97` is `#expect(ascending.count == 14)` over twenty tied tasks — a SECOND pin on the
silent macOS cap**, the exact twin of the one the grant did name, and either defends the bug alone.

The general lesson, worth more than the path: **a grant scoped to the defects an audit happened to
list is scoped to the audit's thoroughness, not the code's.** Next time a lease is drawn from a
report, search the code for the same shape before fixing the scope.

Verified landed before granting, with `--no-merges`: one branch modified it,
`codex/search-widget-followups`, whose four sampled test functions are all present on main.

Three of the agent's four edits there are mechanical. The fourth is the pin revision — and it
reported one line it deliberately did NOT change, `:149`'s `sections: sections`, because it named
the drawn sections `sections` and the uncapped ones `indexedSections`, which keeps the existing
assertion true and reads better. Naming a line you left alone is as useful as naming the ones you
touched.

### 2026-10-17 — `CalendarPageMonthSupportViews.swift` granted, and the test needs `--no-merges`

**GRANTED to local agents for [[T-3170]].** Without it the trio pass cannot finish: `TimelineDayCanvas`
has two callers, and while `SchedulePanelShellViews.swift` was already starved (`bundles: []`,
`allBundles: []`), `CalendarPageMonthSupportViews.swift:339` still passes a real `[TaskBundle]`. So
removing those parameters from the granted canvas would break a file the agent could not touch —
and leaving them is the exact "a parameter feeding an empty dictionary reads like a parameter that
is gone" shape the ninth pass had to return for.

It also answers the month-cell question in the same file: `MonthBundleChip` at `:193` and the
`split(bundles:)` call at `:402` mean `MonthDayCell` DOES still draw Block chips. With this grant the
chip goes in the trio pass and `CadenceCalendarMonthCellPriority.split`'s `bundles:` leg orphans
cleanly, instead of costing a fourth trip.

**A FIFTH refinement to the staleness test: pass `--no-merges`.**

    git log --no-merges main..<branch> -- <path>

The agent reported "exactly one branch modified it". The coordinator found TWO and checked the
extra one rather than accepting the tidier number — `codex/parity-functional-batch`, whose only
commit touching this path is `7ba0e1b1 Merge remote-tracking branch 'origin/main'`. **A merge
commit authored nothing**; it pulled main in, and the path rode along. Without `--no-merges` a
branch appears to have touched files it never edited, which inflates the candidate set and, on a
busier repo, would eventually manufacture a false refusal.

Both branches are landed regardless — `7343bfe8` is an ancestor of HEAD and its blob for this file
is byte-identical to main's; the merge branch's sampled symbols are all present on main.

The agent applied the branch test correctly and said in terms that it was "not assuming it carries
over" from `4b4775f1`, which is why the extra branch surfaced at all.

### 2026-10-17 — a CROSS-AGENT dependency: one path granted, one REFUSED AND SEQUENCED

The second Codex agent needs two things for T-3195's event Custom repeat. One is granted, one is
not, and the refusal is the first time the staleness test has caught a **live** conflict rather than
a stale one.

**GRANTED: `Cadence/iOS/iOSTimelineDraftCreate.swift`** — clean, zero `codex/*` commits main lacks.
Scope is forwarding the draft's end-mode / date / count fields through to `createEvent`, nothing more.

**REFUSED FOR NOW: `Cadence/iOS/iOSCalendarManager.swift`.** It is already leased to the FIRST Codex
agent for T-1483's fixture door, and that work has NOT landed — `rg CadenceCalendarFixtureEvents`
returns nothing in the file yet. Worse, `git log main..codex/mobile-calendar-notes-parity --
<path>` returns a commit whose blob **DIFFERS** from main. That is the genuinely-pending case the
final-form test exists to identify, and this is the first live instance; every previous "differs"
in this document turned out to be staleness.

**Two Codex agents writing one file concurrently is the exact collision the fence exists to
prevent**, and it would be worse than a local collision because neither agent can see the other's
worktree. So this is sequenced, not refused permanently: when the first agent's branch lands, the
method scope is granted to the second on request.

**What the second agent should do meanwhile, which it already proposed itself:** continue the
card/task side without touching either file. Its instinct to ask rather than assume a shared file
was free is what surfaced this.

**Note on the request's third path:** `Cadence/iOS/iOSScheduleDraftCreation.swift` does not exist in
the tree. `createEvent` is referenced from `iOSTimelineDraftCreate.swift`, `iOSCalendarManager.swift`
and `iOSCalendarQuickCreateSheet.swift`; the agent likely means a type inside the granted file. Not
granted as named, because a grant for a path that does not exist cannot be scoped.

### LEASE WIDENED 2026-10-17 — five narrow paths the second Codex agent traced from source

All five granted. Checked with the final-form test above: **zero `codex/*` commits that main lacks
on any of them**, and all three existing files are clean in the worktree.

- `Cadence/macOS/Views/ListDetailComponents.swift` — `ListTasksView`'s bottom row, which is where
  T-3192's add-section control has to live, because the owner chose an INLINE ROW AT THE BOTTOM over
  a toolbar button.
- `Cadence/Shared/Components/CadenceSectionCreationRow.swift` (NEW) — the one shared control. The
  owner's decision was explicitly "both platforms via a shared control", so a single new file in
  `Shared/Components/` is the right shape and a second platform-local copy would not be.
- `Cadence/Shared/Components/CadenceSchedulePanel.swift` and
  `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift` (NEW) — the agent proposes the
  capture card as **a capture presentation of the existing panel, not a ninth independent form**.
  That is the right instinct and matches [[T-3171]], which has spent four slices converting surfaces
  ONTO `CadenceSchedulePanel`; adding a parallel form would spend the fifth slice undoing that.
- `Cadence/Services/TaskCreationService.swift` — to carry recurrence through the EXISTING creation
  commit rather than saving it afterwards. Granted on that reasoning specifically: a second write
  after the create is the swallowed-save shape this repo has fixed repeatedly, most recently in
  PA-13 / [[T-1470]].

**What is NOT granted by this:** new recurrence semantics, new rule cases, or any schema change. See
the spec answers recorded on [[T-3195]].

### 2026-10-17 — five more guard paths for T-3195, and a VACUOUS sample caught in the act

All five granted. They are the downstream guards of T-3195's capture-UI contract change, traced
from source by the second Codex agent rather than discovered by breaking them.

**One of them nearly slipped through on a vacuous check, which is worth recording.**
`CadencePresentedTypographyBoundaryTests.swift` had three candidate branches. Sampling their
`@Test func` names against main returned **0 of 0 present** — and 0/0 is not a clean answer, it is
*no answer*: the sample found nothing to sample, because that file's assertions are not shaped the
way the sampler assumed. Reading 0/0 as "safe" would have been the same error as a `VACUOUS-COUNT`
build read as "no warnings".

Resolved by looking at the actual difference instead. Main asserts `popoverCount == 9` and carries a
`[[T-3171]]` comment explaining the five popovers that moved to the shared schedule panel; the
branch asserts `== 14` and has no such comment. **Main is ahead; the branch is stale.** Grantable.

`CadenceChoicePickerDismissalTests.swift` resolved the ordinary way — 5 of 5 sampled functions
present on main on both candidate branches.

**Scope, as the agent proposed and on its own reasoning:** repoint
`neitherPlacementSpellsTheComposersItself` to two card calls and zero calendar quick-create while
**retaining all placement negatives**; move `CadenceInlineTagCommitSurfaceTests`' `Text(actionError)`
pin onto `failureNotice` travelling to the shared card; delete the now-unreferenced value/date tile
structs from the already-granted `iOSCreateTaskSheetSupportViews.swift` and update ONLY their
entries in the four reader tests, **retaining each reader control and non-vacuity floor**, replacing
the retired form's coverage with the shared card's picker/commit coverage. The agent stated "no
exemption additions" unprompted, which is the right instinct: the cheap way to make these green is
an allowlist entry, and that would convert a guard into a comment.

### THE STALENESS TEST, FOURTH AND ACTUAL FORM 2026-10-17 — the blob step is NOT sufficient

The "final form" recorded below is still wrong, and it would have refused a correct grant minutes
after being written. **Fourth correction in one day; read this one.**

**Where it failed.** `CadenceUITests/CadenceCapturePaletteUITests.swift`, requested by the second
Codex agent. `codex/phone-capture-hold` and `codex/phone-capture-load` BOTH show the supposedly
decisive signature — `git log main..<branch> -- <path>` non-empty AND blob DIFFERS from main. By the
rule below that is "genuinely pending work, do not grant". **Both branches landed days ago.**

**Why the blob step cannot work.** This repo lands a Codex branch by APPLYING its files, so the
branch's commits are NEVER in main's ancestry — not before landing, not after. `git log main..branch`
therefore stays non-empty for ever. And once main edits the file again, the blob differs for ever
too. So a landed-then-evolved file is indistinguishable from pending work by those two signals
alone. Every signal that looks at the BRANCH fails the same way; the question is about MAIN.

**The test that actually works — ask whether main already contains the branch's content, by name:**

    git show <branch>:<path> | grep -oE '(func|struct|enum|let|var) [A-Za-z_]+'
    # then for a handful:  rg -q "func <name>" <dir>/

Present on main → landed, grant it. Absent → genuinely pending, refuse and sequence.

Use the branch-ancestry and blob steps only to NARROW which branches are worth sampling. They can
prove a branch irrelevant (empty log = never touched the file). They cannot prove one pending.

**The scoreboard, recorded because the pattern is the lesson.** Five versions of this test in one
day: ahead-of-main, `codex-land.sh review`, blob-vs-main, modified-vs-own-base, log+blob. Every one
was written by the coordinator with confidence, and every one was falsified — three by agents, one
by the owner, this one by its own first real use. **A check that keeps returning the answer you
expect is not thereby correct**; the three earlier versions all "worked" for hours because almost
everything they were asked about was genuinely stale.

### 2026-10-17 — two test paths granted to the second Codex agent

Both granted after the test above. `CadenceCapturePaletteUITests.swift` — the two branches holding
differing blobs have all four sampled test functions present on main; landed. `CadenceComposerContainerSurfaceTests.swift` — clean, no `codex/*` commits at all.

Scope as the agent proposed it, and the proposal is right: replace the retired "New task"
navigation-bar and "Cancel" queries with the new capture-title and Cancel-capture identifiers,
**keep every real coordinate tap/hold/slide gesture and the fixture isolation**, and add
floating-card/chip assertions on phone and iPad. On the second file, repoint the stale
`fields.container = .inbox` spelling to the schedule draft's Inbox token while preserving the
missing-container, preflight and query controls. Keeping the real gestures matters: those tests
exist because a capture palette that passes a synthetic tap can still be unreachable by a thumb.

### THE LEASE-STALENESS TEST, FINAL FORM 2026-10-17 — supersedes every earlier version above

Three versions of this test were written into this file in one day, each wrong or weak, each
corrected by an agent rather than by the coordinator who wrote it. This is the one to use.

    git log main..<branch> -- <path>

- **Empty** — that branch carries no commit touching the path. It never opened the file; it differs
  from main only because its base is old. **Irrelevant. Ignore it.**
- **Non-empty** — the branch has commits on the path that main lacks by ancestry. Now compare the
  blob: identical to main's means the content was LANDED by file-application, differing means
  genuinely pending work. **Only this case can block a grant.**

One call per branch. No test-name sampling, no patch application, no inference from diff direction.

**What it replaces, and why each failed:**
1. *"Branch is ahead of main"* — every landed branch is ahead for ever, because this repo lands by
   APPLYING files and never deletes the branch. Twenty-one branches ahead; the backlog was fiction.
2. *`codex-land.sh review`* — refuses on its FIRST failing check, so an unrelated inbox-id clash
   masks whether the content landed.
3. *Blob comparison against main* — a branch differs on a file it NEVER OPENED, because main moved
   past its base. Twenty-two of twenty-three branches "differed" on a file only one had ever
   touched. This produced a wrong refusal in `67b41992`.
4. *Modified-vs-its-own-base* (`git diff --name-only $(git merge-base $b main)..$b -- <path>`) — the
   coordinator's third attempt. Better, but still answers "did this branch change the file relative
   to where it started", which a branch created before the file existed can answer misleadingly.

Credit: agent `parkedland` reached this independently, having already rejected the blob heuristic on
its own before the coordinator's correction arrived. Agent `blocktail` had separately measured six
false positives from version 4. **The coordinator wrote three wrong answers into committed
documents; the agents found all three.**

### LEASE WIDENED 2026-10-17 — eight paths for a SECOND Codex agent: T-3195 and T-3192

The owner is running two Codex agents. The first holds T-1483/T-1468/T-1471/T-1472 — calendar
fixtures and the notes editor. This widening is for the second, on the capture sheet and list
sections, chosen so the two sets are disjoint and neither can land on the other's files.

**Checked against the live tree, not assumed.** All eight are clean in the worktree right now, and
no `codex/*` branch has modified any of them. **T-1467 was considered and REJECTED for this batch**:
`TasksPanelComponents.swift` and `RightClickActionTrigger.swift` are dirty this minute, with
`parkedland` mid-landing of `heartbeat/t1479-mac-context-menu`. A path being unleased says nothing
about whether a local agent is inside it.

**The one place two Codex agents CAN collide is `docs/CODEX_LEDGER_INBOX.md`**, which is always
allowed and therefore ungoverned by the fence. Ticket ids are the live hazard there, since the
ledger is the allocator and two agents filing concurrently will both reach for the same next number.
**The second agent is therefore confined to T-1496, T-1497, T-1502, T-1505 through T-1509, and
T-1511 through T-1515** — verified free at the time of writing. The first agent uses anything else.
This is a reservation, not a guarantee: the ledger still allocates, and either agent must re-check
with `ledger-view.sh show` before quoting an id.

### LEASE WIDENED 2026-10-17 — `Cadence/iOS/iOSCalendarView.swift`, T-1483's second blocker

**Verified, not accepted.** `refreshVisibleEvents()` guards on `calendarManager.isAuthorized` at
`:436` and `refreshSelectedDayEvents()` at `:455`. Both exit BEFORE reaching the manager, so a
fixture door added inside `iOSCalendarManager.fetchEvents` can never fire — the callers short-circuit
first. Codex found this after taking the granted fix and is right that T-1483 is unfinished without
it.

Worth recording as a lesson about the original ticket: T-1483 was filed from a measurement — two
product call sites, both macOS — and that measurement was correct but INCOMPLETE. It located where
the fixture is read and never asked what stands between the caller and that read. A second gate
upstream of the one you are fixing is invisible to a search for the thing you are fixing.

**Scope, narrowly:** those two guards only, admitting the active fixture scenario. **Real-store
authorization stays in the manager** — these guards may learn about fixtures, they may not learn to
skip authorization. The two-part gate is unchanged: `CADENCE_UI_TEST_MODE=1` AND a recognised
`CADENCE_UI_TEST_SCENARIO`, either half alone answering nil. Extend the fixture tests to pin BOTH
callers, since the defect was that a caller nobody tested stood in front of a door everybody did.

File is clean in the worktree and no `codex/*` branch has modified it.

### LEASE WIDENED 2026-10-17 — two more paths for T-1471's heading jump

Codex asked rather than took, including for a file that **does not exist yet**. That is the less
obvious half and the right call: a new file feels like it belongs to nobody, but `CadenceUITests/`
is inside the fence's jurisdiction and creating a file there ungranted is the same violation as
editing one.

**Verified, not accepted:** `textView.selectedRange` is assigned at `iOSMarkdownEditor.swift:209`
and `:410`, and **`scrollRangeToVisible` appears nowhere in the file**. The selection moves and the
view does not follow — so a heading jump list would jump nowhere, and a parser-only test would pass
over it. That is precisely the failure the T-1471 brief tried to pre-empt by asking for reachability
coverage rather than parser coverage.

`codex/leased-followup-batch` had modified that file (+26 −11). It is LANDED — four of its tests
checked by name are all present on main. Checked with the branch-modification test, not the blob
comparison.

**Scope:** the explicit scroll request and what the jump needs to reach it. The selection clamping at
`:207-209` and `:410` is OFF LIMITS — the comment at `:106` records a race that "not beginning is the
stronger" guard resolves, and it is load-bearing. The new UI test must drive the T-1483 fixture
harness and must never request EventKit permission; if `CadenceUITests` cannot run in Codex's
environment it must say so rather than mark the behaviour covered.

### LEASE WIDENED 2026-10-17 — nine paths for Codex: T-1483, T-1468, T-1471 and T-1472

Three jobs, chosen so none of them touches a file the three running local agents hold
(`parkedland`, `blocktail`, `searchscope`).

**T-1483 is the one that matters most and should go first.** The calendar fixture harness has
exactly two product call sites and both are macOS, so on iOS the `calendar-hues` scenario seeds
tasks and yields NO events — found by building the app and looking at it, not by reading. The event
rail is the half of [[T-3168]] nobody has ever seen, and until iOS has a fixture door it cannot be
seen there at all, because the only alternative is real EventKit permission, which no agent may
request. Fix is the same two lines `CalendarTimelineSupport.swift` carries, ahead of the
`isAuthorized` guard in `iOSCalendarManager.fetchEvents(for:)`. The safety property is unchanged and
structural: `CADENCE_UI_TEST_MODE=1` is also a `CadenceEventKitLaunchGate` disarm signal, so a launch
that can see fixtures provably cannot reach a real store.

**T-1468** — iOS month chips show the event time, answering `nil` for an all-day event the way the
Mac's `chipTimeLabel` already does.

**T-1471 / T-1472** — the iOS note editor gets the heading outline and jump list, and
unlinked-mention discovery. One pass over the editing surface, not two. Actual backlinks already
exist on iOS and are NOT the same thing as unlinked mentions.

The nine paths above enter the fence. Codex holds none of them today, and no `codex/*` branch has
modified any of them — checked with the test that works, `git diff --name-only $(git merge-base $b
main)..$b -- <path>` per branch, rather than the blob comparison that staleness falsifies.

### COORDINATOR GRANT 2026-10-17 — the Mac timeline canvas, which unblocks the last Block surfaces

Prose grant to LOCAL agents, for [[T-3170]] only. Fence unchanged.

**Granted:** `Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift` and
`Cadence/macOS/Views/TimelineDayCanvas.swift`.

**Why this matters:** `TimelineBundleBlock.swift`, `TimelineBundleBlockSupportViews.swift` and
`TaskBundlePickerSupportViews.swift` are themselves UNLEASED and ready to delete whole, but were
unreachable — `TimelineBundleBlock` is constructed at `TimelineDayCanvasSupportLayers.swift:121` and
`TaskBundleTaskPickerPanel` at `TimelineBundleBlockSupportViews.swift:145`. Blocked by construction,
not by the lease on the files themselves. This grant is the last gate on finishing the Block removal.

**A third demonstration of the staleness trap, and the sharpest one yet.** Twenty-one branches report
BOTH canvas files as differing from main — including branches that never opened them. A branch
differs on a file it never touched, purely because its base predates main's changes to that file. So
"differs everywhere" is not weak evidence of pending work; it is evidence of NOTHING.

**The question that works:** which branches actually MODIFIED the file, i.e. is it in that branch's
own diff against its base?

    for b in codex/*; do git diff --name-only $(git merge-base $b main)..$b -- <path>; done

Answer here: `TimelineDayCanvasSupportLayers.swift` and `TimelineDayCanvas.swift` were touched by
exactly ONE branch, `codex/ui-refresh-reconciliation` — landed by this coordinator in `7343bfe8`,
and both files sit in that branch's identical-to-main set. `TimelineBundleBlock.swift` was touched by
NO branch at all.

**Use this test in preference to the blob comparison** recorded in the correction above. The blob
test answers "is this file the same", which staleness alone can falsify. This one answers "did anyone
change it", which is the question a lease is actually about.

Credit where due: agent `blocktail` prompted this by declining to assume the canvas lease was real
and asking for it to be re-checked.

### COORDINATOR GRANT 2026-10-17 — `blocktail` edits `CadenceTests/CalendarBoardDayDropCommitTests.swift`

Prose, as always for a LOCAL agent entering a path Codex holds. Fence unchanged.

The agent asked before editing rather than after, and its reading was right at every step: the file
entered the fence in the 2026-10-16 PA-13 widening, that entry reserved `CadenceTaskMutationSupport`'s
`:271-273` bundle lines for "a pass that runs AFTER this lands", and PA-13 landed in `749d67ad`.
`blocktail` is that pass.

**Verified no unlanded Codex work:** SEVENTEEN `codex/*` branches report that file as differing from
main. That is the trap described in the correction above, not evidence — every landed branch differs
for ever and differs more as main moves past it. Checked the way that actually works: main already
holds those branches' tests by name.

**Worth keeping from this pass:** it changed
`mobileDayDropRestoresEveryMutatedFieldOnlyWhenRefused` to assert the membership fields are untouched
in BOTH answers rather than only on a refusal. That is strictly stronger — it now fails if anything
writes those fields again, which is the regression T-3170 cares about.

### COORDINATOR GRANT 2026-10-17 (`parkedland`) — two leased TEST files, so two finished features can land

**Prose, deliberately, and not a fence line**, for the reason the grant further down gives: the
```lease block says what CODEX may write, and admitting a LOCAL agent runs the other way. The fence
is untouched -- 81 patterns at the moment this was written, none of them added or removed here --
and Codex's own reach is unchanged.

Two complete features were parked on `heartbeat/*` branches, each held back by exactly one leased
test file the branch was not allowed to touch. Both files are granted, for these two tickets only,
and both were edited and landed under this grant.

| ticket / branch | the one blocking path | the edit |
|---|---|---|
| [[T-1475]], `heartbeat/t1475-ios-timeline-drag` | `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift` | the bare inline-notice census at `:490`, 68 → 69 for the iOS timeline's refused move/resize notice — the edit [[T-3208]] prescribed, verbatim |
| [[T-1479]], `heartbeat/t1479-mac-context-menu` | `CadenceTests/CadenceCodexTaskListVirtualizationTests.swift` | `largeSingleGroupsMountOnlyABoundedSubsetOfNativeTaskRows`'s mounted-row probe, re-keyed off the `taskRowTitle` accessibility identifier — the first option [[T-3201]] offered |

**The evidence — and a sharper form of the check `d1162e10` corrected.** `d1162e10` is right that a
blob differing from main proves nothing: this repo lands a Codex branch by APPLYING its files and
never deletes the branch, so a landed branch differs for ever, and differs *more* as main moves past
it. Its replacement — does main contain the branch's test names? — is sound but indirect, and has to
be repeated per branch by hand. The question underneath it is answered directly, in one call per
branch, by **`git log main..<branch> -- <path>`: does any `codex/*` branch carry a COMMIT touching
this path that main does not have?**

| path | branches carrying it | blob identical to main | branches with an UNLANDED commit on it | verdict |
|---|---|---|---|---|
| `CadenceTests/CadenceCodexTaskListVirtualizationTests.swift` | 11 | **all 11** | 1 — `codex/task-list-virtualization` `9cc2438c`, whose blob **equals main's** | landed; granted |
| `CadenceTests/CadenceMarkdownImageCommitSurfaceTests.swift` | 23 | **1** (`codex/ios-board-drop-refusal`) | 1 — `codex/ios-board-drop-refusal` `405806ff`, whose blob **equals main's** | landed; granted |

The twenty-two branches that "differ" on the census file are the exact trap `d1162e10` names, and
the file says so out loud: they assert `total == 69` or `total == 67` and **lack** the `[[T-3171]]`
and `PA-13 / T-1470` comment lines main carries at `68`. They are earlier states, not later ones —
and **not one of them has a commit on the path at all**. A path with zero unlanded commits across
every branch is not holding unlanded work, whatever its blobs look like.

**For the lease-holder:** [[T-3208]] and [[T-3201]] are done and need no Codex pass. The probe
re-key is worth a look rather than a revert — it was counting `RightClickActionTrigger.RightClickActionView`,
an AppKit overlay the row carried only to duplicate its own tap, so [[T-1479]] removing that overlay
made the positive control read 0 over a lazy-mount bound that still held. It now counts the row's
own `taskRowTitle` identifier, which is on the row because a UI test needs it there, and a new
control test (`theRowIdentifierProbeStillMatchesTheIdentifierTheRowDraws`) fails loudly if the
identifier's shape ever moves out from under it.

**Extended 2026-10-17 to [[T-3211]], same path, same agent.** The re-key above raised a fair doubt
and [[T-3211]] was filed to record it: the probe read **16 rows for 200 stored and 16 for 1000**, and
16 is also exactly what a 320pt host holds, so it was not established that an EAGER list would read
differently -- which would have made `mounted < count / 2` vacuous. It is established now, and the
answer is the good one. A negative control drawing the same 1000 tasks in a deliberately eager
`VStack` reads **1000**, against the real page's **16**: SwiftUI's accessibility tree enumerates what
the list REALIZED, not what is on screen, so the bound is real. The control is landed in the same
file under this grant. Nothing was added to or removed from the ```lease block for it either.

### CORRECTION 2026-10-17 — the refusal in `67b41992` was WRONG; those branches are LANDED

`67b41992` refused a grant for `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` (for
[[T-1478]]) and flagged `Cadence/iOS/iOSCalendarBoardView.swift`, on the grounds that
`codex/calendar-day-drop-commit` and `codex/parity-functional-batch` held unlanded work there.
**They do not. Both branches landed; the refusal is void and the grants are given below.**

**The faulty inference:** that a blob differing from main's means the branch is ahead. It does not.
This repo lands a Codex branch by APPLYING its files and then never deletes the branch, so every
landed branch differs from main for ever — and keeps differing MORE as main evolves past it. The
diff direction said so plainly and was read past: `CalendarPageBoardSupportViews.swift` was
**+23 −96**, i.e. the branch has ninety-six lines FEWER than main. That is an old branch, not a
pending one.

**The check that actually settles it — use this one.** Ask whether main already contains the
branch's work, by name:

    git show <branch>:<test file> | grep -oE '@Test func [a-zA-Z]+'
    # then, for each name:  rg -q "func <name>" CadenceTests/

- `codex/calendar-day-drop-commit`: all four of its `CalendarBoardUnscheduleCommitTests` functions
  are PRESENT on main. Landed.
- `codex/parity-functional-batch`: all five sampled `CadenceCodexFunctionalParityTests` functions
  are PRESENT on main. Landed.

Patch application does not settle it either — for these branches `git apply --check` and
`git apply --reverse --check` BOTH exit 1, because main has diverged far enough that the old hunks
no longer match in either direction. An ambiguous result there is not evidence of pending work.

**GRANTED to local agents, the refusal lifted:**
- `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` — for T-1478, the Mac board's success
  reconcile.
- `Cadence/iOS/iOSCalendarBoardView.swift` — for T-3170's remaining Board work.

**Standing note for the next coordinator:** there is no twenty-one branch Codex backlog. The
branches are landed and simply never deleted, which the repo's own rules require — never reset,
delete or force-push a `codex/*` branch. Do not mistake the graveyard for a queue.

### COORDINATOR 2026-10-17 (later) — one grant, one REFUSAL, and a correction to the grant above

Four tickets were PARKED at once, every one of them on a leased path, so the lease had become the
single bottleneck. Before granting any of it the coordinator asked a question it had skipped
earlier: **does Codex actually hold UNLANDED work in these files?**

**"Ahead of main" does not answer that.** Twenty-one `codex/*` branches are ahead, because this repo
lands a Codex branch by APPLYING its files, never by merging — so a fully landed branch stays ahead
for ever. `codex-land.sh review` does not answer it either: it refuses on its FIRST failing check,
so an inbox-id clash masks whether the content already landed. The question that answers it is
whether the branch's blob for that path equals main's.

| path | branch | verdict |
|---|---|---|
| `CadenceTests/CadenceCodexFunctionalParityTests.swift` | `codex/mobile-project-deadline` | IDENTICAL to main |
| `Cadence/iOS/iOSRootView.swift` | `codex/ui-refresh-reconciliation` | IDENTICAL to main |
| `Cadence/iOS/iOSTaskViews.swift` | `codex/parity-functional-batch` | IDENTICAL to main |
| `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` | `codex/calendar-day-drop-commit` | **DIFFERS, +23 −96** |
| `Cadence/iOS/iOSCalendarBoardView.swift` | `codex/parity-functional-batch` | **DIFFERS, +147 −27** |

**GRANTED to a local agent: `Cadence/iOS/iOSRootView.swift`, for T-3170 only.** It still applies
`.iOSBundleInspectorHost()`, which is why `042a5767` had to leave that host as a documented no-op
stub instead of deleting it. Scope is that one call site and the stub's deletion. Verified identical
to main on the only branch that touches it, so nothing unlanded collides.

**REFUSED, deliberately: `Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` for [[T-1478]].**
`codex/calendar-day-drop-commit` holds a real unlanded change there — 96 lines removed, 23 added.
A local agent editing it would collide with work nobody has reviewed, which is precisely what the
lease exists to prevent. **T-1478 is not unblocked by a grant; it is blocked on landing that
branch**, which is coordinator work, not agent work. The same applies to `iOSCalendarBoardView.swift`
and `codex/parity-functional-batch` (+147 −27) for anything that reaches the iOS board next.

**Correction to the search grant above (`63b024d6`).** It justified itself with "Codex's live branch
at this moment, `codex/ios-board-drop-refusal`, touches none of these files." That checked ONE
branch, not the twenty-one that exist, and the honest basis was not established at the time. The
grant's CONCLUSION survives the proper check — all three search paths are identical to main on every
branch that touches them — but the reasoning as written was thinner than it sounded, and a grant is
a published claim. Recorded rather than quietly repaired.

### COORDINATOR GRANT 2026-10-17 — a LOCAL agent enters three leased search paths for T-1476 / T-1473

**Prose, deliberately, and not a fence line.** The ```lease block says which paths CODEX may write.
This grant runs the other way: it admits a LOCAL agent into paths Codex holds, which is recorded
beside the fence, not in it. The fence stays at 69 patterns and Codex's own reach is unchanged.

**Paths, for agent `searchscope` and its successors on these two tickets only:**
- `Cadence/macOS/Views/GlobalSearchIndexSupport.swift` — holds BOTH the unconditional
  `includingCompleted: true` and all three caps (`:186` tasks, `:218`/`:220` events, `:313` notes).
- `Cadence/macOS/Views/GlobalSearchSupportViews.swift` — for the continuation row.
- `CadenceTests/CadenceCodexFunctionalParityTests.swift` — `:129` builds 16 matching notes and
  asserts 12, which PINS the silent cap the owner decided to remove. It must be revised or it
  defends the bug. **Its ranking assertion is a real claim and must survive the revision.**

**Why a grant rather than handing this to Codex, which already holds all three:** the owner is
running batches for velocity and a round trip costs a batch slot. Codex's live branch at this
moment, `codex/ios-board-drop-refusal`, touches none of these files, so there is nothing in flight
to collide with.

**`searchscope` stopped rather than pushing, and was right to.** It found this file's own T-3099
entry, where agent `searchfix` edited a `CadenceCodex*.swift` path without a grant, and which states
that `GlobalSearchIndexSupport.swift` and `GlobalSearchSupportViews.swift` "were NOT touched; the
lease held there." Same two files, recently. The precedent is why this grant is written down instead
of assumed.

**Note for the lease-holder:** `Cadence/Shared/CadenceSearchResultCap.swift` is NOT leased and
already exposes `visibleCount` / `hiddenCount` / `continuationLabel`. Its doc comment names this
exact blocker — the Mac's cap lives inside `GlobalSearchIndexSupport`, "which is why only the mobile
surface could adopt this first." The shape of the fix is to stop the three `*Results` functions
returning pre-truncated arrays and let the presentation apply the cap, as `iOSSearchView` does.

### COORDINATOR REPAIR 2026-10-17 — one line removed from `CadenceTests/CadenceTagChipStyleTests.swift`

**This is a repair inside a leased path, not a widening, and it does not belong in the fence.** The
fence governs which paths CODEX may write; a coordinator or local agent entering a Codex path is
recorded in prose, which is what this is. Nothing was added to or removed from the ```lease block.

`042a5767` (agent `iosblockui`, T-3170's eleventh pass) deleted
`Cadence/iOS/iOSCalendarBundleDetailSheet.swift`. That file was named in this suite's
`undeclaredControls` inventory, which the test reads with `try read(path)` — so the deletion turned
`main` RED on `CadenceTagChipScaleTests`, *"Exactly one file that draws a tag chip has opted itself
into scaling"*. The whole repair is removing the one line naming the deleted file. A red `main` is
worse than a lease courtesy, so the coordinator took it rather than queueing a grant.

**`iosblockui` reported the line as `:514`; it is `:470`.** Recorded because that figure would have
sent the next reader to the wrong place, and because a line number in a handoff is a published claim.

Codex's live branch at the time, `codex/ios-board-drop-refusal`, does not touch this file, so there
was nothing to collide with. If Codex holds an unlanded edit to this suite, this one-line deletion is
the whole of the coordinator's change and should be easy to reconcile.

### LEASE WIDENED 2026-10-17 — `CadenceMarkdownImageCommitSurfaceTests.swift`, for a census PA-13 forces

Codex asked rather than took, again correctly. **Verified before granting:** that file's
`theImageInsertionNoticeCountsWhatTheDoorLostBeforeTheCommit` region ends in
`#expect(total == 67, "the inline notice has \(total) call sites, not the 67 this test was written
over")`. It is a CENSUS of `CadenceInlineFailureNotice` call sites, so PA-13 adding a refusal notice
to the iOS board moves it to 68 whether or not anyone intends to touch this file. The file's own
comments record the same thing happening twice before: T-1132 made it 67, and T-3171 made it 67
again on the Mac.

**Scope: the integer and a comment naming [[T-1470]] / PA-13 beside the other two, in the house
style those comments already set.** Not the test's logic, not its other assertions, not the
surrounding image-commit coverage. A census test is supposed to fail when the census changes; the
grant is to re-take the census, not to loosen it.

**The grant is the line in the fence above, not this paragraph.**

### LEASE WIDENED 2026-10-17 — a fourth path for PA-13, `Cadence/Shared/CadenceTaskDateEditing.swift`

Codex asked for this one by name, because the 2026-10-16 section below says in terms that no other
product path is widened. That was the right read of the grant and the right place to stop; this
section supersedes that sentence for this single file.

**The request was verified before it was granted, in the file itself.** `CadenceTaskDateEditing` is
the app-side wrapper that mutates and then reconciles OS notifications, and its own header says
every function there is "one line plus one reconcile". Two of its date functions already answer:
`setScheduledDate` is `@discardableResult ... -> Bool` with an injectable
`commit: (ModelContext) throws -> Void = { try $0.save() }`, and `clearScheduledDate` is the same
shape and returns `landed`. **`moveTaskToDate` is the single function in the file that returns
`Void` and takes no `commit:`.** Giving it the signature its two siblings already have is bringing
an outlier into line with the file's established pattern, not inventing a seam — and PA-13's whole
defect is that the iOS board has no value to refuse with, which this is upstream of.

**Scope: `moveTaskToDate` only.** Forward the `Bool` from
`CadenceTaskMutationSupport.moveTaskToDate` and accept an injectable `commit:`, matching the
siblings. **Do NOT change the reconcile policy in this file** — whether a reconcile runs, when it
runs, or on which platforms. The Mac board's missing immediate reconcile is finding PA-14, folded
into T-362 as an evidence addendum, and it is a separate decision the owner has not made. The
header's reasoning for why the reconcile lives here and not in `CadenceTaskMutationSupport` stays
as written.

**The grant is the line in the fence above, not this paragraph.**

### LEASE WIDENED 2026-10-16 — three paths for PA-13, the iOS board drop that cannot refuse

The owner read the parity audit and picked **PA-13** as the one finding Codex should fix. Codex
already holds `iOSCalendarBoardView.swift`, `iOSBoardCards.swift` and
`CalendarBoardDayColumnSupportViews.swift`. The fix cannot be made from those alone, so three more
paths enter the fence above:

- `Cadence/Shared/CadenceTaskMutationSupport.swift` — `moveTaskToDate` ends in a bare
  `try? modelContext.save()`. That swallowed save is the defect itself; the callback's `Void` return
  type is only what makes it unreportable. Granted NARROWLY: `moveTaskToDate` and whatever its new
  answer forces on its callers. **T-3170's Block removal also has work queued in this file** (the
  residual `task.bundle` nils at :271-273), deliberately held for a pass that runs AFTER this lands —
  so Codex should not take the bundle lines, and the coordinator must not schedule that pass
  concurrently.
- `CadenceTests/CalendarBoardDayDropCommitTests.swift` — holds the macOS rollback and
  result-forwarding coverage at :123 and :531. The mobile case belongs beside it, not in a new suite.
- `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift` — holds the shared commit contracts this
  path has to join.

**The grant is the three lines in the fence above, not this paragraph.** `codex-land.sh lease`
parses the fenced ```lease block and nothing else.

No other product path is widened. In particular `Cadence/iOS/iOSRootView.swift` is NOT granted: the
neighbouring finding PA-26 is blocked on T-3109/T-1469, a design question about replacing the root's
UI context without stranding retained models, and is not Codex's to answer unilaterally.

### LEASE WIDENED 2026-10-16 — one docs path, `docs/PLATFORM_PARITY_AUDIT.md`, for the platform parity audit

The owner authorized Codex's read-only macOS/iOS parity audit to write its report to a new path.
`codex/platform-parity-audit` wrote that report **before** the grant existed, so
`codex-land.sh review` refused it as outside the lease, which is the script working correctly.

**The grant is the line in the fence above, not this paragraph.** `codex-land.sh lease` parses the
fenced ```lease block and nothing else, so a widening recorded only in prose does not exist to the
tool — `840fe34f` is the commit where that was learned the expensive way. This section is the
reasoning; the fence line is the grant.

Scope is the report file alone. No product path is widened by this entry, and the audit branch
touches no `.swift` file. `docs/CODEX_LEDGER_INBOX.md` needed no grant: it is always allowed.

### LEASE WIDENED 2026-10-09 (third batch) — three paths so [[T-3085]]'s shared wording has somewhere to live

Codex asked for exactly the three paths the T-3085 instruction below already prescribes, which is the
right ask: that instruction says the sentence moves into `CadenceSavedLinkPersistence` and the pins go
in `CadenceSavedLinkPersistenceTests`, and neither is reachable from the leased mobile file. Granting
the presenter without them would strand the shared-wording half. Additive: three in, none out.

**`Cadence/Shared/CadenceSavedLinkPersistence.swift`** — for the confirmation title and sentence,
beside the existing `saveFailureNotice` / `deleteFailureNotice`. **Do not change what `delete(_:)`
does.** Its `modelContext.delete` + `commitDelete` and its `actionError` reporting stay exactly as
they are: the confirmation gates that call, it does not replace or wrap it.

**`CadenceTests/CadenceSavedLinkPersistenceTests.swift`** — for the pins. It already source-scans both
link surfaces (there is an `iOSListLinksPanel` scan around `:220-261`), so extend it rather than
starting a new suite.

**`Cadence/macOS/Views/LinksView.swift` — granted for ONE edit and nothing else.** Replace the literal
at `:82` with the shared helper. **The rendered string must be byte-identical before and after**:
today it is `"This will permanently delete \"\(link.title)\"."` under the title `"Delete Link?"`, and
macOS behaviour must not change by so much as a full stop — this grant exists so the two platforms
cannot drift on wording, not to retune the Mac's copy. Nothing else in that file moves: not the
hover-revealed trash, not `deleteLink(_:)`'s reachability from the confirm closure only, not the
card styling.

**Still out of scope, restated because this grant touches the Mac:** the link-row chrome. The owner
decided the deletion, not the styling, and mobile's plain rows are the Lists page's one deliberate
treatment. Delete-failure reporting is likewise unchanged on both platforms.


### INSTRUCTION 2026-10-09 — [[T-3085]] on a path Codex already holds: a saved link deletes with no confirmation on mobile

No new grant. `Cadence/iOS/iOSListSupportViews.swift` matches the standing
`Cadence/iOS/iOSList*.swift` glob, which is why agent `linkdelete` stopped rather than editing it —
and it stopped correctly: **both the swipe button and `delete(_:)` live inside that one file, so no
half of this change lands outside the fence.** The owner has decided it, so it comes to Codex.

**The defect, verified in source by two readers, not relayed.** macOS `LinksView.swift:80-83` presents
`Delete Link?` / *This will permanently delete "&lt;title&gt;".* and `deleteLink(_:)` is reachable only
from that confirm closure. Mobile `iOSListSupportViews.swift:692-696` calls `delete(link)` straight
out of a `.swipeActions` button, which goes through `CadenceSavedLinkPersistence.delete` —
`modelContext.delete` plus `commitDelete` — so **one gesture commits to the store and to CloudKit**.
`allowsFullSwipe: false` costs a flick a second tap but names nothing and cannot be answered "no".

**It is not undoable, checked rather than assumed.** No `holdUndo` on the saved-link path (its only
callers are `CadenceListDeleteHelpers.swift:127` and `CadenceTaskMutationSupport.swift:843`), no
toast, no Recently Deleted. Model-level undo is deliberately absent app-wide — [[T-367]] removed
`modelContext.undoManager` on purpose. The rollback inside `CadenceSavedLinkPersistence.delete` is
*failure* handling; a successful delete is final. And the direct swipe was never chosen deliberately:
the saved-link history ([[T-327]], [[T-507]], [[T-509]]) is entirely about whether a write lands or
is reported, never about whether it is confirmed.

**The design, recorded so it is not re-derived.** Follow `iOSNoteDeletionSupport.swift`'s shape: a
`View` extension over a `Binding<SavedLink?>`, the swipe sets the binding and nothing else, so exactly
one `CadenceSavedLinkPersistence.delete` call site survives behind exactly one presenter. Use
**`.alert("Delete Link?")` weight, not the full modal sheet** — a note or list delete earns the sheet
because it is a cascade with a summary; a saved link is one trivial object, and
`iOSTaskDetailSheet.swift:88` already establishes the light idiom. **It must name the link**, and the
sentence should move into `CadenceSavedLinkPersistence` beside `saveFailureNotice` /
`deleteFailureNotice` so the two platforms cannot drift on wording the way they drifted on the scheme
check in T-509. Keep `delete(_:)`'s existing `actionError` reporting — the confirmation gates it, it
does not replace it. Pins belong in `CadenceTests/CadenceSavedLinkPersistenceTests.swift`, which is
**not** leased and already source-scans both link surfaces.

**Explicitly NOT in scope: the card styling.** Codex's audit bullet welded a cosmetic difference to a
destructive one. Only the deletion half loses data. Mobile's links are plain `List` rows sharing the
Lists page's one deliberate `iOSListRowChrome()` treatment; carding them would make that panel the
only carded surface on the page. The owner decided the deletion, not the chrome.

**Worth folding in while you are there:** that panel uses raw `.swipeActions` rather than the shared
`iOSSwipeActionsModifier` / `iOSListRowSwipeActions` the same file's list rows adopted after the
"swipe did nothing on iPad" defect (`iOSListSupportViews.swift:49-55`). It is not discarded today
because the panel builds its own `List`, but a future re-host in a `ScrollView` would make the swipe
silently vanish.


### LEASE WIDENED 2026-10-09 — five wiring paths, so the approved parity fixes are not left inert

Codex asked for these by name to finish work already granted on 2026-10-08, and the ask is the right
one: four of the five exist because **a search hit that cannot be opened is half a fix**, which is
what that grant already told it. Granting the index without the destination would have shipped
exactly the inert result the grant warned against. Additive: five patterns in, none out.

**The ticket ids Codex asked for: [[T-3082]], [[T-3083]], [[T-3084]]** — filed in the same commit as
this grant, one per finding, each carrying the audit's file:line evidence and the conditions the
2026-10-08 grant attached. Codex should fold its inbox entries into those three ids and allocate no
new ones.

**Four paths for [[T-3084]], the Mac note-search fix.** `GlobalSearchSupportViews.swift` for the
ordinary-note destination and category; `macOSRootCommandActionSupport.swift` to resolve the selected
note; `EventNoteSupportViews.swift` for the kind-aware navigation request; `NotesView.swift` to select
requested ids in Daily, Weekly and Notepad. **`NotesView.swift` is the one to be careful in** — it is
the Mac's whole notes surface, and selecting a requested id must not disturb what it already does on
open. Granted for the selection path, not for a re-layout of that page.

**One path for [[T-3077]], the Completed chip.** `iOSTodayCompactViews.swift`, **for exactly one
edit**: passing `showsCompletedControl: false` from `iOSCompactTodayView.optionsBar`. The flag itself
goes in `iOSTaskViews.swift`, which Codex already holds. Do not change anything else in that file —
agent `todaytrim` landed the owner's Today header changes there in `69b9d60b` and the ledger entry
explains each one. In particular do **not** restore `eyebrowDetail:` and do **not** flip
`CadenceTaskSurfaceOptions.options(for: .today).showsCompletedToggle`, which macOS reads.

**Still NOT granted, and these are now owner-DECIDED rather than undecided** — Codex should not start
them until they are filed with paths: Focus checkmark semantics (**the owner chose mobile's immediate
complete; the Mac moves to match**), list-detail memory (**the owner chose the Mac's per-container
behaviour; mobile moves to match**), Saved Links deletion (**the owner chose the Mac's confirmation;
mobile's direct swipe-delete goes**), and the Notes label vocabulary (**Mac's naming wins**). The
month-cell priority policy and the search-truncation difference are still open questions.


### LEASE WIDENED 2026-10-08 — three paths for Codex's own parity audit, plus one instruction on a path it already holds

Codex delivered a read-only iOS/macOS parity audit against `c3d5dbdc` and asked for exact lease paths
before implementing. The owner triaged it and chose: **Codex takes all three of its high-value
functional findings.** Additive: three patterns in, none out.

**Verified before granting**, because the audit's own caveat says concurrent sidebar and Today edits
appeared during it and to recheck against current main: all three paths exist on HEAD, none was
already in the fence, and none is held by an agent in flight (`listrowheight` and `listsdoor` hold
`iOSRootSidebar.swift` and `CadenceSidebarMetrics.swift`; `todaytrim`, `sidebarspacing` and `daysnap`
have landed).

**(1) `Cadence/iOS/iOSCalendarBoardView.swift` — mobile Calendar Board event cards are inert.** Mac
cards open `CalendarEventEditPopover` (`CalendarBoardItemSupportViews.swift:186`); mobile renders a
display-only card with no activation callback (`:479`). Reuse the existing mobile event
inspector/editor route rather than building a second one, and carry read-only-calendar behaviour
across — an event on a subscribed calendar must refuse the same way it refuses on the Mac. Check the
caller as well as the card: a card that gains a callback nobody wires is not a fix.

**(2) `Cadence/iOS/iOSBoardCards.swift` — cancelled cards still look active.** The glyph recognises
cancellation but title contrast, strike-through and background attenuation check only `isDone`
(`:323`). Mac dims cancelled titles (`KanbanCardView.swift:552`) and ordinary mobile task rows
already use the shared settled-state decision — **use that same shared decision, do not add a third
spelling of "settled".** This is not the completed-section membership issue, which is already fixed;
do not re-open that.

**(3) `Cadence/macOS/Views/GlobalSearchIndexSupport.swift` — Mac search omits daily, weekly and
notepad notes.** Mac filters note candidates to `kind == .meeting` (`:259`); mobile searches every
non-blank kind (`iOSSearchView.swift:195`). **This is the one the owner cares about most**: their Mac
archive holds 97 notes including 16 legacy daily notes and 9 documents, and today none of those is
findable from the Mac. Extend the note candidates **and** the destination resolution — a hit that
cannot be opened is half a fix — preserving task-embed title resolution, tags, ranking and identity.
`iOSSearchView.swift` is **reference only and is NOT granted**: read it to match behaviour, do not
edit it.

**(4) [[T-3077]] — `Cadence/iOS/iOSTaskViews.swift`, which Codex ALREADY holds.** No new grant; this
is an instruction on an existing one. Agent `todaytrim` landed the owner's Today changes in
`69b9d60b` but could not remove the "Completed N" chip, because it is drawn unconditionally inside
`iOSTaskViewOptionsBar` (`:651-665`) in that leased file. The fix it identified, which Codex should
take: add `var showsCompletedControl = true` beside `spreads`, wrap the trailing `Button` in it, and
pass `false` from `iOSCompactTodayView.optionsBar` **only**. Do **not** flip
`CadenceTaskSurfaceOptions.options(for: .today).showsCompletedToggle` — macOS's `TasksPanel` reads
it and the owner scoped this change to the phone. Today already reads correctly either way, because
the chip and the new chevron write the same state; this removes the second control, not a bug.

**Deliberately NOT granted, because the owner has not decided them**: the Focus checkmark semantics
(Mac logs adjustable time, mobile completes immediately), list-detail per-container memory, and the
month-cell priority policy. All three are product decisions the audit itself flagged as such. The
visual batch — Kanban card geometry, list-detail gutters, markdown rhythm — is also not granted:
several of those divergences are deliberate and the audit says so.


### LEASE NARROWED 2026-10-07 — `CalendarManager.swift` comes OUT, so [[T-3032]] can be fixed

**Exactly one pattern struck: `Cadence/macOS/Services/CalendarManager.swift`. 39 -> 38.** Asserted as
a set difference rather than a line count, and rebuilt from `git show HEAD:docs/CODEX_WORKTREE.md`
rather than from a copy read earlier in the session — the discipline `4ccaf39d` adopted after an
agent nearly revoked a live grant from a stale base.

**Why it is safe to take back.** The file was granted for [[T-122]]'s annotation-only pass. That pass
has LANDED (`bc082946`), and Codex's own report says the warning it carries —
`CalendarManager.swift:110` — is one of seven actor-bound observer/KVO callbacks that **cannot be
honestly cleared within the annotation-only restriction**. So there is no further T-122 work in this
file that the current grant permits: clearing that warning needs a new owner decision about where a
callback runs, not a new lease. Revoking a grant nobody can act on is the opposite of revoking a live
one.

**Why it has to come out at all.** [[T-3032]]: `CalendarManager.isAuthorized` is a plain `var` with
no `private(set)` (`:24`), and it is the **only** guard on all six EventKit writes.
`CadenceRemindersManager` spells the same flag `private(set)` (`:39`) — the asymmetry is in the tree,
not in anyone's opinion. Four tests set `CalendarManager.shared.isAuthorized = true` on the real
singleton holding a real `EKEventStore`, and they are safe today only by accident: they hand EventKit
events from a throwaway store, which it refuses. The call they happen not to make would write to the
owner's real default calendar.

**This does not re-open T-122's eight-file grant**, which stands; only this one path moves. If Codex
needs it back for a decided callback change, the coordinator re-grants it the same way it granted it.


### LEASE WIDENED 2026-10-07 (second batch) — one path for [[T-122]], and the widget-membership sequence for [[T-168]]

Codex landed `codex/leased-followup-batch` for review and came back with exactly two asks. Both are
answered here. Additive: one pattern in, none out, 38 -> 39.

**[[T-122]] — `Cadence/macOS/Views/CalendarEventPresentationSupport.swift:285-305`, granted.** This is
the LAST of the Swift 6 warnings that can be cleared inside the annotation-only rule. It is
`CalendarEventDragPayload`, a pure string codec: `static func string(for:)` and
`allDayEventPayload(from:)` on an enum with two private `let`s and no stored state. The grant is for
an annotation, not a rewrite — **the decode must stay synchronous**, which is the same constraint the
first grant put on `TimelineDropInteractionSupport`: a drag decoder that gains a hop stops answering
in the callback that asked it.

**The other seven warnings are CORRECTLY not fixed, and that is the grant working rather than
failing.** Codex reports them as actor-bound observer and KVO callbacks that cannot be honestly
cleared within the annotation-only restriction. The first grant said in as many words that a warning
which cannot be cleared that way gets **reported in the inbox entry instead of cleared**, because the
report is worth more than the silence. It did that. Nobody should read eight-minus-one as incomplete
work; `SWIFT_VERSION` stays 5 and the ticket's standing *investigate and report, do not flip* is
intact.

**[[T-168]] — the project-membership STOP was the right call, and here is the sequence.** The grant
said to stop rather than edit `Cadence.xcodeproj/project.pbxproj` if widget-target membership needed
a hunk, and Codex stopped, made no edit and claimed no workaround. The reason the stop exists is
[[T-117]]: that file must not be written while the owner has Xcode open, and whether the coordinator
or the owner lands it is decided at the time, not in advance.

**The coordinator adds the membership, not Codex, and it is a known four-line shape.** `7d5bad39`
did exactly this for `CadenceTaskBundleMutationSupport.swift` — a `PBXFileReference`, a
`PBXBuildFile`, a group-children line and a Sources-phase line, with `pgrep -x Xcode` re-checked
immediately before the write and the file backed up by `cp` first. `Cadence/Shared/` is a
`PBXFileSystemSynchronizedRootGroup` so the app target picks a new file up by itself; the widget
extension is a second target and does not, which is the whole of the problem Codex hit.

**So the order is: Codex writes `CadenceFocusSessionSnapshot.swift` and the widget against it and
says so; the coordinator then lands the membership in the same pass that integrates the branch.** Do
not build the widget first and discover the membership last — a snapshot type the extension cannot
see compiles fine in the app and fails only in the target nobody builds by default. **No T-168 lease
path is retired by any of this**: nothing of half (a) is claimed, no session persistence exists, and
the chrome toggle is unwritten.


### LEASE WIDENED 2026-10-07 — six paths for [[T-168]], because the owner answered its three questions

The grant above withheld T-168 on the grounds that it was three product decisions and a new surface
rather than a set of dependencies. The owner has now made all three, so this publishes them together
with the paths they imply. Additive: six patterns in, none out, 32 -> 38.

**(1) The widget: yes, ONE read-only current-session widget.** Codex's own design is the one taken —
the live timer plus the subject, drawn with `Text(timerInterval:)` so the system animates the count
without waking the extension, because a WidgetKit timeline cannot tick and a reload-every-second
timeline is not an option. **No second widget and no task-list widget**: two widgets that say the
same thing was the outcome the entry told us to avoid. `CadenceWidgets/FocusSessionWidget.swift` is
new; `CadenceWidgetRefreshCenter.swift` and `CadenceTodayWidgetSupport.swift` are granted for the
registration and `instrumentedKinds` only, not for a rewrite of what the existing widgets do.

**(2) The chrome: hide the tab bar in landscape Focus, AND a tap on empty space toggles it back.**
This is the owner's refinement on the question as asked, and it is the binding half of the grant:
hiding alone is not what was asked for. In landscape Focus the four-tab bar is hidden so the timer
goes full-bleed, and a tap on empty space — not on the timer, not on the transport controls, not on
the task picker — toggles it back into view, and toggles it away again. So the bar is **recoverable
without rotating**, which is what makes hiding it safe: a hidden bar that can only be restored by
rotating the phone would strand someone in Focus. Granted: `Cadence/iOS/iOSCompactTabShell.swift`.
Every tab draws through that shell, so the hiding must be expressible as something Focus asks for
and the other three tabs cannot accidentally inherit; portrait Focus and all of iPad are unchanged.

**(3) Rotation: a running session must survive it.** `iOSRootView` replaces the compact shell with
the regular one at a size-class change, which today throws away an in-progress session, and the
owner's answer is that it must not. Focus session state moves above the shell so the swap cannot
take it. Granted: `Cadence/iOS/iOSRootView.swift`. This is the same persistence (1) needs — a widget
process cannot see in-memory state in `iOSFocusView` either — so do them as one piece of work and
not twice.

**The persistence itself is `Cadence/Shared/CadenceFocusSessionSnapshot.swift`, new, and it is the
prerequisite rather than a detail.** iOS focus state lives in `iOSFocusView`'s own
`CadenceFocusTimerState` with no shared state object, and `FocusManager` is `#if os(macOS)` only
(T-242) — do **not** make it cross-platform, that would be a second timer authority with nothing
incrementing its `elapsed`. The snapshot is a small app-group value — subject, start instant,
running/paused, and nothing more — written by the app and read by the extension. It goes in
`Shared/`, not `Services/`, for a mechanical reason: the `Cadence/` tree is a
`PBXFileSystemSynchronizedRootGroup` so a new file there self-registers, while `Cadence/Services/`
holds explicit `PBXFileReference`s and a new file there needs a project edit. `CadenceFocusHandoff`
is NOT this type and must not be made into it — it is an in-memory message carrying a
`CadenceFocusTarget` and a token, with deliberately zero macOS readers.

**Two hard stops.** There is **no `cadence://focus` route** — the owner chose the widget without one,
so tapping it opens the app and nothing registers a new deep link. And if making the snapshot
readable from the widget target turns out to need a membership edit in
`Cadence.xcodeproj/project.pbxproj`, **STOP and report instead of editing it**: that file must not be
touched while the owner has Xcode open ([[T-117]]), and whether the coordinator or the owner lands
that hunk is a decision made at the time, not in advance.

Existing widgets to match are **`CalendarSnapshotWidget` and `TodayTasksWidget`** — the two named in
T-168's original text that no longer exist, `HabitCheckInWidget` and `MilestoneMomentumWidget`, went
with the Habits/Goals retirement, and a design that matches them matches nothing.


### LEASE WIDENED 2026-10-07 — fifteen paths for [[T-3011]], [[T-1411]], [[T-1400]] and [[T-122]]

The owner granted these after Codex named each one in its batch report and the landing note above
recorded that none of them was granted by the landing. Each path was checked to exist on HEAD and to
be absent from the fence before being added, so this grant adds fifteen patterns and retires none;
the ten paths of the first 2026-10-07 grant and the four standing globs are untouched.

**Why this is a grant and not a widening by the writer.** `codex-land.sh review` refuses
`CODEX-LEASE-VIOLATION` on a path outside the fence, and the tool's own printed remedy is for the
coordinator to widen main's lease deliberately rather than for the branch to carry the widening
hunk. Codex edited none of these files before asking, which is why there is a branch to grant for
rather than one to refuse.

**[[T-3011]] — `Cadence/iOS/iOSFloatingCreateTaskButton.swift`, to wire the lifetime owner that
already landed built-and-unwired.** Replace the `@State UUID` at the drop-target modifier with the
`CadenceNewTaskDropRegistrationLifetime` that `makeRegistrationLifetime()` builds, and call
`activate()` where the registration is published — a lifetime that is never activated must stay
inert, because a discarded `@State` initial value enqueuing a `destroy` is the bug the reference
type exists to avoid. **Conditional:** [[T-3008]]'s guarantee is the thing this must not reopen, so
`CadenceNewTaskDropRegistrationTests` stays green unmodified, and the entry's own third requirement
stands — land a measurement that this bounds something, not only the wiring. `retire(_:)`'s doc
comment stops saying the cost is still paid only once production owns a lifetime.

**[[T-1411]] — `Cadence/Shared/Components/CadenceBoardMetadataChip.swift` and
`CadenceTests/CadenceTagChipStyleTests.swift`.** The patch order is the one the entry already
records and it is not negotiable, because declaring a root over an unconverted chip is the
scattering [[T-1364]]'s brief forbids: convert the chip first (environment fonts, additive glyph
growth, wrap rather than shrink-to-fit, fixed metrics unchanged), then extend the existing caller
inventory to the undeclared Calendar and macOS consumers, then declare both Lists roots, then add
exactly those two to `CadenceTypographyConversionSweepTests`. The chip is drawn on macOS too, so the
macOS rendering must be unchanged at the default text size.

**[[T-1400]] — the four iOS markdown files.** `monoFont`, the table geometry and the restyle-on-change
invalidator, scaled through `UIFontMetrics`. **Do not convert `iOSMarkdownStyler.baseFont`** — it is
`.preferredFont(forTextStyle: .body)` and has followed the reader's text size all along, which is the
finding that corrected the audit's headline; moving it to the Cadence ramp would be a regression
dressed as the fix. Table geometry derives from the same fonts rather than from a second constant,
and a restyle preserves selection and caret. The Mac half of this ticket is **not** granted: it waits
on [[T-1399]], and `Cadence/macOS/Editor/` is not in this fence.

**[[T-122]] — the eight Swift 6 files, under a condition that is the whole point of the grant.**
The owner's standing decision on this ticket is *investigate and report, do not flip*, and this grant
does not change it: `SWIFT_VERSION` stays 5 and no target flips. What is granted is clearing the one
error and the thirteen warnings the 2026-10-07 re-measure found, as preparation that is **inert under
Swift 5**. A fix qualifies only if it is a type- or annotation-level change — a `Sendable`
conformance, a `@Sendable` closure annotation, an isolation annotation that states the isolation the
code already has at runtime. A fix that moves work to a different actor or defers it does not
qualify, however quiet it makes the compiler: **no blanket `Task {}` hops and no
`nonisolated(unsafe)`**, because `FocusManager`'s observers bank synchronously before sleep and the
drag decoders in `TimelineDropInteractionSupport` must stay synchronous. Where a warning cannot be
cleared that way, Codex reports it in the inbox entry instead of clearing it — that report is worth
more than the silence. The zero-warning Swift 5 baseline must be re-measured as still zero before and
after, and the entry's own caution stands: the error may hide further debt behind it.

**[[T-168]] is NOT granted by this, and the omission is deliberate.** Half (a) wants a new widget
surface (`CadenceWidgets/FocusSessionWidget.swift`, `Cadence/Services/CadenceWidgetRefreshCenter.swift`,
`Cadence/Services/CadenceTodayWidgetSupport.swift`) and a `cadence://focus` route; the rest of half
(b) wants `iOSCompactTabShell` to let Focus hide the tab bar and `iOSRootView` to promise State
survives a size-class shell swap. Those are three product decisions and a new surface, not
dependencies — they go to the owner, and the paths stay outside the fence until they come back
answered.


### LANDED PARTIAL 2026-10-07 — `codex/typography-lifecycle-batch`, and NOTHING is retired

Agent `codexland3` landed the branch (tip `980d4b75`) in the commit carrying this note. Every one of
its ten paths was unchanged on main since the merge base `12858406`, checked blob by blob, so the
take was whole-file with no three-way merge. **No lease path is retired, deliberately:** each grant
says to retire its paths when its work lands, and none of the three code tickets did. [[T-2054]]
(the Area/Project chooser) needed no grant — `iOSListEditorViews.swift` is the standing
`iOSList*.swift` glob. [[T-168]] landed landscape content only, so its three paths stay. [[T-3011]]
landed built-but-unwired, and the Dynamic Type cluster's eight paths carry rechecks rather than
conversions, so the ten paths of the first 2026-10-07 grant stay too.

**Changed at landing, and only this:** the `retire(_:)` doc comment in
`CadenceCapturePaletteSupport.swift` keeps saying the memory cost is *still paid*, because the
branch's rewrite read as though a lifetime owner already existed and none does in production.

**Codex's requested dependencies are NOT granted by this landing** — `iOSFloatingCreateTaskButton.swift`
for T-3011's wiring, the compact-shell and root-view decisions and the three widget files for T-168,
`CadenceBoardMetadataChip.swift` / `CadenceTagChipStyleTests.swift` for [[T-1411]], four iOS editor
files for [[T-1400]], and eight Swift 6 files for [[T-122]]. Each is recorded in its ledger entry and
needs the owner's grant here before Codex edits it.

### LEASE RETIRED 2026-10-06 — the three T-3005 Kanban paths are out, because the work landed

`codex/kanban-rendering` landed at tip `05de6408` in the same commit that folded [[T-3005]]'s
pre-filed stub in place. `Cadence/macOS/Views/KanbanSupportViews.swift`,
`KanbanColumnSupportViews.swift` and `KanbanListColumnView.swift` are struck from the lease above.
**Exactly three patterns out, and the four standing globs are untouched** — asserted as a SET
equality, not a line count: what remains is exactly `Cadence/iOS/iOSList*.swift`,
`Cadence/Shared/CadenceTypography.swift`, `CadenceTests/CadenceTypographyScaleTests.swift` and
`CadenceTests/CadenceCodex*.swift`. That last one is Codex's reserved namespace and is where this
branch's `CadenceCodexKanbanRenderingTests.swift` landed, so it must survive its own landing.

**Rebuilt from `git show HEAD:docs/CODEX_WORKTREE.md`, never from a copy read earlier in the
session** — the discipline `4ccaf39d` adopted after an agent nearly revoked a live grant from a
stale base. The branch itself never touched this file (`git diff c3b659f5 05de6408` lists five
paths and this is not one), so nothing retired here was taken from a writer holding its own lease:
a writer that can edit the fence can widen it, and that hunk would have been declined had it
existed.

The `CODEX-INBOX-ID-CLASH` that `codex-land.sh review` exits 3 on was answered by replacing the
pre-filed T-3005 stub's body, not by allocating a second id — the same fold as [[T-3004]].

### LEASE RETIRED 2026-10-06 — the one T-3004 path is out, because the work landed

The heartbeat coordinator landed `codex/task-list-virtualization` (tip `1b187f9e`) and closed
[[T-3004]] in the same commit. `Cadence/macOS/Views/TasksListView.swift` is struck from the lease
above; the four standing globs are untouched. The `CODEX-INBOX-ID-CLASH` that review printed on
T-3004 was the pre-filed stub, whose body was replaced in place, not a blocker.

### LEASE RETIRED 2026-10-05 — the twenty-one T-3003 paths are out, because the work landed

`52a6b408` integrated `codex/data-safety-audit-fixes` and `d17fac9a` closed [[T-3003]] on top of it.
The eighteen production paths and the three narrowly granted guard files are struck; **the four
standing globs above are untouched**, `CadenceTests/CadenceCodex*.swift` among them — it is Codex's
reserved namespace and it is where this very branch's `CadenceCodexBackupAuditTests.swift`,
`CadenceCodexEventNoteResolutionTests.swift` and `CadenceCodexWidgetReopenTests.swift` landed, so
dropping it would strand three files that are now on main.

Asserted as a **set equality**, not a line count: the patterns remaining are exactly
`Cadence/iOS/iOSList*.swift`, `Cadence/Shared/CadenceTypography.swift`,
`CadenceTests/CadenceTypographyScaleTests.swift` and `CadenceTests/CadenceCodex*.swift`.

**Rebuilt from `git show HEAD:docs/CODEX_WORKTREE.md`, never from a copy read earlier in the
session** — a previous agent nearly revoked a live grant that way, and a lease file is exactly the
document where a stale base silently re-grants or silently revokes. The branch itself never touched
this file, so nothing here was taken from a writer holding its own lease: a writer that can edit the
fence can widen its own lease, and that hunk would have been declined had it existed.

The three conditional grants were checked as honoured before retirement, not after:
`markTodo` gained the zero-pin on its old spelling rather than only moving to `commitMarkTodo`;
the popover `SaveSurface` moved to `finishCommittedEdit()` **together with** the coverage pinning
both committing callers and the finisher's single `onChanged()`; and exactly four stale exemptions
were deleted with the detector, the "Exemptions rot" guard and an EMPTY `reportExemptions` intact.

### LEASE RETIRED 2026-10-05 — the nineteen T-1466 paths are out, because the work landed

`df2e8a5a` closed the tracking-UI retirement on top of `3c80981c`, which integrated it.

**CORRECTION, written by the same agent that got it wrong.** The commit message of `b11c3ec6`, which
made this edit, claimed `codex-land.sh review codex/tracking-ui-retirement` would report all
twenty-two files as landed and refuse a single path. That was asserted from the pre-retirement run
and NOT re-run afterwards, and it is wrong in both halves. What `review` actually reports once the
nineteen are retired is: **20 of 22 files already in main, 2 still only on the branch**, and
**`CODEX-LEASE-VIOLATION` on 20 paths**, because `review` refuses a path that is outside the lease
whether or not it has landed — so retiring a grant necessarily brings the violation back. That is the
normal steady state after every retirement, not a regression; the same is true of `36ef5e04`/`4ccaf39d`
and `189f7249`. The two files that are correctly **not** byte-identical in main are the two the
coordinator deliberately resolved differently: `CadenceTests/CadenceRealTreeSweepManifest.txt`, which
is generated and was re-derived against the integrated tree instead of taken, and
`docs/CODEX_LEDGER_INBOX.md`, where main's copy is the UNION of both sides and so is deliberately a
superset of the branch's. The `CODEX-INBOX-ID-CLASH` on T-1466 is the consequence of the id having
been filed in `0030f487` before the code, exactly as T-1465's was in `b802afc5`; it is not a blocker.
The correction is recorded here rather than left in a commit message no one re-reads, because this
file's whole value is that a later reader can believe it.

Retired in the same session that granted them, as the grant below said it would be, and because this
file's own warning is the thing [[T-2069]] and [[T-2058]] are about: *a lease granting paths nobody
is working on is a lease that will eventually be believed.*

**Nothing else was touched, and this was rebuilt on HEAD to make sure of it.** The fence was
regenerated from `git show HEAD:docs/CODEX_WORKTREE.md` rather than from the copy read at the start
of the session — the same discipline `4ccaf39d` adopted after nearly revoking a live grant that way.
The four standing globs are unchanged, `CadenceTests/CadenceCodex*.swift` among them, and **all
nineteen [[T-3003]] paths stay**: that grant (`220b0b91`, `c4eedfcb`) is for Codex's four audit
findings and is still live. 42 patterns in, 23 out, and the 23 are exactly the 4 standing globs plus
T-3003's 19.

### LEASE WIDENED 2026-10-05 — nineteen paths for [[T-1466]], the tracking-UI retirement

Written by the coordinator (agent `codex1466`) while landing `codex/tracking-ui-retirement`, which
is [[T-1466]] — the third and last Codex landing of the day. `codex-land.sh review` REFUSES
`CODEX-LEASE-VIOLATION` on **twenty** paths; the owner authorized this grant explicitly, and the
tool's own printed remedy is for the coordinator to widen main's lease deliberately rather than for
the branch to widen its own. Nineteen of the twenty are granted here. The twentieth is withheld on
purpose and is named below.

**The four live controls.** `Cadence/iOS/iOSTaskDetailSheet.swift` and
`iOSTaskDetailSheetSections.swift` hold the task inspector's unconditional Milestone row, its
`Goal` fetch, its picker state and the `task.goal` binding; `iOSTaskRowActionViews.swift` holds the
task row's Goal chip, its picker and the committing assignment path, and `iOSTaskViews.swift` is
the row call site that passes them through. iPhone and iPad share these same four files, which is
why no iPad-specific path appears.

**The drawn copy.** `Cadence/Shared/CadenceSettingsSectionCopy.swift`,
`Cadence/iOS/iOSDataResetSettingsSection.swift` and
`Cadence/macOS/Views/SettingsDataSafetySection.swift` carry the notification descriptions and the
reset / delete warnings; `Cadence/Shared/CadenceListDeletionSummary.swift` carries the deletion
counts, `CadenceDataExportPresentation.swift` the backup description, and
`CadenceArchiveImportPresentation.swift` the import preview that groups the retained tracking rows
under one **Retained legacy records** line. These are granted for *wording and grouping only* — the
warnings must keep disclosing that legacy records are retained, and the insert/match totals must
stay exact. `Cadence/Services/MarkdownNoteSupport.swift` is granted for the built-in Project Brief
template's default headings (Objective/Deliverables) ONLY; it must not rewrite a saved note or a
customized template.

**`README.md`** stops advertising the three as current features.

**Seven test files** are granted because they are the exact-count and source guards this removal
re-points rather than relaxes: `CadenceArchiveImportEntryPointTests`,
`CadenceChoicePickerDismissalTests`, `CadenceEmptyTitleFallbackSweepTests`,
`CadenceIconOnlyButtonAccessibilityTests`, `CadenceListDeletionSurfaceTests`,
`CadencePresentedTypographyBoundaryTests` and `CadenceSettingsSectionCopyTests`. The two Codex's own
broad run left red — the accessibility census (five chips to four) and the presented-workflow census
(fifteen popovers to fourteen) — are in this set; a census that moves because a control was removed
is re-pointed, and the coordinator checks the positive controls survive rather than taking the
re-point on trust. Codex's new tests need no grant: they land in `CadenceTests/CadenceCodex*.swift`,
the standing namespace.

**THE TWENTIETH PATH IS DELIBERATELY NOT GRANTED.** `CadenceTests/CadenceRealTreeSweepManifest.txt`
is generated, not authored. The coordinator re-derives it with
`./scripts/real-tree-sweep-manifest.sh --write` *after* integrating, so the three new sweep
registrations are proved by the generator against the real tree rather than trusted from a branch
that is eight commits behind main — and main's own copy has moved twice since the merge base, in
`189f7249` and `36ef5e04`. `review` will keep reporting a violation on this one path and that report
is correct. This is the third branch running it is withheld.

**`docs/CODEX_WORKTREE.md` needed no decline this time.** Unlike `codex/sidebar-drawer` and
`codex/continuous-quote-rail`, this branch does **not** add itself to the lease block — Codex states
outright that it does not widen its own lease, and the diff confirms the file is untouched. The
protocol held without the coordinator having to enforce it.

**NOTHING WAS DROPPED, and this was rebuilt on HEAD to make sure.** The four standing globs survive
— `Cadence/iOS/iOSList*.swift`, `Cadence/Shared/CadenceTypography.swift`,
`CadenceTests/CadenceTypographyScaleTests.swift` and `CadenceTests/CadenceCodex*.swift`, dropping
the last of which would make `codex-land.sh` refuse Codex's next branch for doing what it was asked
— and **all nineteen [[T-3003]] paths stay**, the grant `220b0b91`/`c4eedfcb` published while these
landings were in flight. 23 patterns in, 42 out. These nineteen retire in a follow-through commit
the moment the work lands, in this session, because *a lease granting paths nobody is working on is
a lease that will eventually be believed.*

### LEASE RETIRED 2026-10-05 — the four T-1465 editor paths are out, because the work landed

`36ef5e04` landed the continuous quote rail. `codex-land.sh review codex/continuous-quote-rail` now
reports the four editor sources as already in main, and the two paths it still refuses are the two
the coordinator deliberately resolved differently rather than taking from the branch:
`CadenceTests/CadenceRealTreeSweepManifest.txt`, which is generated and was re-derived after
integrating rather than taken, and this file, whose lease self-grant was declined for the second
branch running. The `CODEX-INBOX-ID-CLASH` on T-1465 that it also prints is the consequence of the
id having been filed in `b802afc5` before the code, not a blocker.

Retired immediately rather than left standing, because the grant below said it would be, and
because this file's own warning is the thing [[T-2069]] and [[T-2058]] are about: *a lease granting
paths nobody is working on is a lease that will eventually be believed.*

**Nothing else was touched.** The four standing globs are unchanged, `CadenceTests/CadenceCodex*.swift`
among them, and **all nineteen [[T-3003]] paths stay** — that grant landed in `220b0b91`/`c4eedfcb`
*while this landing was in flight*, so this retirement was rebuilt on HEAD rather than written from
the copy that was read before it, which would have silently revoked a live lease.

### LEASE WIDENED 2026-10-05 — four editor paths for [[T-1465]], the continuous quote rail

Written by the coordinator (agent `codexquote`) while landing `codex/continuous-quote-rail`, which
is [[T-1465]]. The owner authorized the quote-rail fix and the editor files it needs, and then
asked for the macOS check that found the second defect; Codex asked for the minimum rather than
assuming it, and the request with its scope and verification plan is `docs/CODEX_LEDGER_INBOX.md`'s
T-1465 entry.

**The four paths and why each one.** `Cadence/iOS/iOSMarkdownStylingLineSupport.swift` is where the
mobile styler hides the `>` prefix and tags the paragraph, so it is where a per-paragraph tag
becomes a run that spans its terminator; `Cadence/iOS/iOSMarkdownBlockCanvasSupport.swift` held the
18pt-per-paragraph bitmap that could not follow wrapped text, and is where the range/geometry layer
grouping same-depth runs lands; `Cadence/iOS/iOSMarkdownBlockCanvasRendering.swift` is the drawing
pass that must stroke a vector rail instead of stamping one bitmap per paragraph.
`Cadence/macOS/Editor/MarkdownEditorLayoutManager.swift` is granted **for quote gutter positioning
and full-block range recovery on partial redraw only** — it measured the hidden `>` glyphs as the
block's leading edge and put the rail outside AppKit's text-container clip. Regression tests need no
new grant: they land in `CadenceTests/CadenceCodex*.swift`, Codex's standing reserved namespace.

**`docs/CODEX_WORKTREE.md` is deliberately NOT granted, for the second branch running.** Codex's
branch again adds this file to its own lease block; that hunk is declined again and this record is
written by the coordinator in `main` instead, exactly as the T-1463/T-1464 grant above was. A writer
that holds its own lease file can widen its own lease, and this block's whole value is that one
party decides it. `codex-land.sh review codex/continuous-quote-rail` will keep reporting
`CODEX-LEASE-VIOLATION` on this one path, and that report is correct.

**`CadenceTests/CadenceRealTreeSweepManifest.txt` is NOT granted either**, for a different reason:
it is generated, not authored, and the coordinator regenerates it with
`real-tree-sweep-manifest.sh` *after* integration. The T-1463 grant above kept it outside for the
same reason and the landing was unaffected. Codex's branch carries a manifest line; the coordinator
re-derives it rather than taking it, so the registration is proved by the generator rather than
trusted from the branch.

**Nothing was dropped to make room.** The four standing globs are unchanged, and
`CadenceTests/CadenceCodex*.swift` in particular stays — it is where
`CadenceCodexQuoteRailTests.swift` lands with this very branch, and dropping it would make
`codex-land.sh` refuse Codex's next branch for doing exactly what it was asked to do.

**Retire these four when the assignment lands**, by the rule this file keeps rather than cites: *a
lease granting paths nobody is working on is a lease that will eventually be believed.*

### LEASE RETIRED 2026-10-05 — the seven T-1463 paths are out, because the work landed

`189f7249` landed the sidebar drawer. `codex-land.sh review codex/sidebar-drawer` now answers **8 of
10 files already in main, identical**, and the two it still reports as `NOT in main` are the two the
coordinator deliberately resolved differently rather than taking from the branch:
`CadenceTests/CadenceDesktopSplitLayoutTests.swift`, which was three-way merged so main's [[T-2079]]
hunk survives alongside Codex's width fixtures and is therefore *not* byte-identical to either side,
and this file, whose lease self-grant was declined. The two `CODEX-INBOX-ID-CLASH` refusals it also
prints are the shape this file already documents: an id clash on a branch in this state is a
consequence of the work having landed, not a blocker.

Retired immediately rather than left standing, because the grant below said it would be and because
this file's own warning is the thing [[T-2069]] and [[T-2058]] are about: *a lease granting paths
nobody is working on is a lease that will eventually be believed.* The four standing globs are
untouched, `CadenceTests/CadenceCodex*.swift` among them.

### LEASE WIDENED 2026-10-05 — seven paths for [[T-1463]]/[[T-1464]], the sidebar drawer

Written by the coordinator (agent `codexsidebar`) while landing `codex/sidebar-drawer`, which is
[[T-1464]] implementing [[T-1463]]. The owner granted the T-1463 dependencies directly; Codex asked
for the minimum rather than assuming it, which is the behaviour this file exists to produce, and the
request with its scope and verification plan is `docs/CODEX_LEDGER_INBOX.md`'s T-1463 entry.

**The seven paths and why each one.** `Cadence/macOS/Views/macOSRootShellViews.swift` is where the
Mac default width and the one-time `mainSidebarWidth.reset320.v1` migration live;
`Cadence/Shared/CadenceRootShellLayout.swift` is where the iPad 264pt navigation width and the
865pt docked floor are decided; `Cadence/iOS/iOSRootSidebar.swift` is the drawer itself.
`CadenceTests/CadenceRootShellLayoutTests.swift` and
`CadenceTests/CadenceDesktopSplitLayoutTests.swift` carry the literal pane expectations that a width
change necessarily re-points. `Cadence/Shared/CadenceRegularPaneLayout.swift` is granted **for its
width-rule register comment only**, and `CadenceTests/CadencePaneWidthRuleHomesTests.swift` **for the
per-file declaration inventory only** — the narrow pair Codex itself asked be conditional on the
model gaining a named drawer decision, which it did.

**`docs/CODEX_WORKTREE.md` is deliberately NOT granted.** Codex's branch adds itself to the lease
block; that hunk is declined and this record is written by the coordinator in `main` instead. A
writer that holds its own lease file can widen its own lease, and this block's whole value is that
one party decides it. `codex-land.sh review codex/sidebar-drawer` will therefore keep reporting
`CODEX-LEASE-VIOLATION` on this one path, and that report is correct: the protocol edit arrives
here, through the coordinator, which is what the owner's authorization asked for.

**Nothing was dropped to make room.** The four standing globs are unchanged, and
`CadenceTests/CadenceCodex*.swift` in particular stays — it is Codex's reserved namespace, it is
where `CadenceCodexSidebarDrawerTests.swift` lands with this very branch, and dropping it would make
`codex-land.sh` refuse Codex's next branch for doing exactly what it was asked to do (the rule
[[T-2061]] and [[T-2080]] each had to be read back out of this file).

**Retire these seven when the assignment lands**, by the rule this file keeps rather than cites: *a
lease granting paths nobody is working on is a lease that will eventually be believed.* Primary
ledger, `Cadence.xcodeproj/project.pbxproj`, the compact iPhone shell and the real-tree sweep
manifest remain outside it; the manifest is regenerated by the coordinator after integration.

### LEASE RETRACTED 2026-10-04 — the 16 T-1458 paths are back, because the work landed

`7bdb0c32` landed Codex's T-1458 work: the prepared-query search, the single-pass goal
next-action, the chunk-bounded MCP audit reader and the four widget follow-ups. `codex-land.sh
review codex/search-widget-followups` now answers **`CODEX-BRANCH-ALREADY-LANDED` — all 20 files
already in main, 20 identical, 0 where main moved past**, which is the terminal state a spent
branch is supposed to reach.

So the sixteen production paths granted on 2026-10-04 are retracted and free for any writer.
Retracted rather than left standing because this file's own warning applies: *a lease granting
paths nobody is working on is a lease that will eventually be believed*, and [[T-2069]] is the
precedent — four separate agents were blocked or forced to edit through a fence that was
protecting branches with nothing in them.

**What stays open does NOT need these paths.** [[T-1461]]'s native widget visual checks are device
work, not source edits. [[T-1458]]'s file-extraction half is still deferred and still needs an
owner decision about `project.pbxproj` target registration, not a lease. [[T-1462]], the midnight
habit-intent race, names `Cadence/Services/CadenceWidgetIntents.swift` — a path that was **never in
this grant** and is unchanged by the landing, so it would be a fresh request if Codex picks it up.

The four patterns above are untouched and still live: `iOSList*.swift` and the typography trio
remain [[T-1411]]'s standing assignment, and `CadenceTests/CadenceCodex*.swift` is a namespace
rather than a file -- dropping it would make `codex-land.sh` refuse Codex's next branch for doing
exactly what it was asked.


### LEASE GRANTED 2026-10-04 — 16 paths for T-1458, on `codex/search-widget-followups`

Codex requested the minimum production lease for the owner's search / goal-summary / MCP
audit-log / widget follow-ups, and asked that these be reserved from other writers. The ticket,
with the patch order and the verification plan, is `docs/CODEX_LEDGER_INBOX.md:227`; the worktree
is `/Users/williamwei/.codex/worktrees/9e4a/Cadence`, read at `24c671c4` with 0 dirty files.

**These are additive to the four patterns above, not a reversal of the narrowing.** The narrowing
retired the iOS task-UI fence because every branch behind it was spent ([[T-2069]]); this grant
covers a different subtree that a live branch is actually working on. None of the sixteen was held
by another writer when it was published, and none is in any running agent's scope.

**The file-extraction half is NOT granted and is deferred by agreement.** The owner's sixth
optimization recommendation would split `PersistenceController.swift`'s `StoreBackupManager`
boundary and declarations preceding `CadenceWriteService`. New files must be registered as build
inputs in `Cadence.xcodeproj/project.pbxproj` — which MCP explicitly compiles (`project.pbxproj:690`)
— and that file is not edited while the owner has Xcode open ([[T-117]]). Target registration is an
owner decision, not a lease question. Codex deferred it; the coordinator confirms the deferral.

### LEASE NARROWED 2026-10-04 — 35 patterns to 4, because every Codex branch is spent

**Measured, not read off the branch names.** `./scripts/codex-land.sh review` was run against all
seven `codex/*` branches in this repository on 2026-10-04 at `24c671c4`. **Not one of them has a
single code file that is not already in `main`:**

| branch | `review` verdict | exit |
| --- | --- | --- |
| `codex/archive-typography-20261002` | `CODEX-ONLY-THE-INBOX-IS-UNLANDED` — 30 of 31 files already in main | 3 |
| `codex/calendar-day-drop-commit` | `CODEX-ONLY-THE-INBOX-IS-UNLANDED` — 6 of 7 files already in main | 3 |
| `codex/archive-large-text-20261002` | `CODEX-BRANCH-ALREADY-LANDED` — all 18 files | 5 |
| `codex/context-budget` | `CODEX-BRANCH-ALREADY-LANDED` — all 4 files | 5 |
| `codex/save-report-closure-detector` | `CODEX-BRANCH-ALREADY-LANDED` — all 3 files | 5 |
| `codex/task-page-large-text` | `CODEX-REVIEW-VACUOUS` — 0 commits over main | 4 |
| `codex/task-page-typography-finish` | `CODEX-REVIEW-VACUOUS` — 0 commits over main | 4 |

The Codex worktree at `~/.codex/worktrees/9e4a/Cadence` was read at the same time: `git status` is
**empty**, so no path in this fence was mid-edit. Nothing was reset, deleted or force-pushed; the
branches are left exactly as Codex left them, and the two that still carry unlanded
`docs/CODEX_LEDGER_INBOX.md` entries carry ids the ledger already has formal entries for, which is
the T-1800 shape and not pending work.

**This is the rule in this file being kept rather than cited:** *a lease granting paths nobody is
working on is a lease that will eventually be believed.* It had been believed. [[T-2058]] designed
the three row indicator glyphs and wrote **no code**, on the stated evidence that
`codex/archive-typography-20261002` was "3 commits ahead of `main` and UNLANDED". The commit count
is three; the content is zero. `git log main..<branch>` answers a different question from
`codex-land.sh review`, and only the second one is the lease's question.

**What came back, and why.** Twenty-six paths whose assignment is closed in the inbox
([[T-1440]], [[T-1442]], [[T-1450]], [[T-1454]], [[T-1457]]) and whose branches `review` calls
spent — every converted iOS page surface, every shared component T-1442 closed, the three
context-budget paths, and the guards written for that closed work. Four of them were named by
T-2058 as the thing blocking it: `Cadence/iOS/iOSTaskViews.swift`,
`CadenceTests/CadenceTodayUnificationTests.swift`, `CadenceTests/CadenceSharedTaskRowJobsTests.swift`
and `CadenceTests/CadenceTagChipStyleTests.swift`.

**What stayed, and why — this is the conservative half.** [[T-1411]] is still **PARTIAL** and is
still Codex's standing first assignment under R66; [[T-1453]] says Lists is the one task page not
yet declared. So `Cadence/iOS/iOSList*.swift` stays, and with it the two files any further
conversion must edit: `Cadence/Shared/CadenceTypography.swift`, which is where the roles and the
scaling environment are decided, and `CadenceTests/CadenceTypographyScaleTests.swift`, which carries
the "exactly N declared roots" sweep that this file's own *one converter at a time* rule is about.
`CadenceTests/CadenceCodex*.swift` stays because it is Codex's reserved **namespace**, not a file:
a new conversion writes a new guard there, and dropping the glob would make `codex-land.sh` refuse
Codex's next branch with `CODEX-LEASE-VIOLATION` for doing exactly what it was asked to do.

**One edit was made inside that namespace at the same time, deliberately and under the permission
[[T-2061]] names.** `CadenceTests/CadenceCodexTaskSummaryTypographyTests.swift:74` required
`.cadenceFont(` in `CadenceTaskGroupHeading`, and [[T-2056]] deleted the count capsule that was that
file's only call of it. That is the *re-point, never weaken* case below, T-2061 asked the
coordinator to land it rather than route it to Codex, and `main` had been red on it for a day. The
check is not deleted: the heading keeps every other assertion in the loop and gains the stronger
`SectionEyebrowLabel` source read. **If Codex is mid-edit on that file when it reads this, say so
and the coordinator rebases it — the worktree was clean when this was written.**

**A SECOND edit was made inside that namespace on 2026-10-05, under the same permission and the
same rule ([[T-2080]]).** `CadenceTests/CadenceCodexWidgetFollowupTests.swift:70`'s
`codexWidgetProvidersAndViewsShareFamilyBudgets` walked five widget sources, and [[T-2078]]
(`7b686a76`) deleted two of them — `CadenceWidgets/HabitCheckInWidget.swift` and
`CadenceWidgets/MilestoneMomentumWidget.swift` — when the owner retired Habits and Goals.
`CadenceScanInstrument.sweep` *reads* every path it is handed, so this did not fail an assertion:
it threw `NSCocoaErrorDomain 260` and `main` was red on a missing file. `cutwidgets` saw it, named
it in T-2078's closure and correctly did **not** touch it, because this namespace is Codex's lease.
The coordinator landed it instead, exactly as T-2061 asked for the first one.

**Re-pointed, never weakened, and the index was the trap.** `atLeast:` moved 5 -> 3, re-derived
from the three survivors (`TodayTasksWidget.swift`, `TodayTasksWidgetView.swift`,
`CalendarSnapshotWidget.swift`) rather than relaxed to a floor — a floor would let a *second* widget
stop sharing the family budget unnoticed, which is the whole thing this guard is for. The witness
was `including: paths[2]`, i.e. the habit widget; deleting the two dead entries without re-deriving
it would have silently re-pointed the non-vacuity claim at `CalendarSnapshotWidget.swift` while
still reading like the old check. The witness is now a **named constant**, not an index, so the next
edit to that list cannot repeat it. The habit and milestone assertion blocks lost their subject and
are gone, but not silently: a doc comment on the test names each dead assertion, which widget it
died with, and where its surviving equivalent is asserted — and the one claim that had **no**
surviving assertion at all, the view-side "the family budget reaches the drawn content" half, is
added as a new `TodayTasksWidgetView` block. That file was in the sweep list all along and was never
actually read; the re-point closed that gap rather than just shrinking the array. Mutation-tested:
replacing `widgetFamily.cadenceLayout.todayTaskLimit` with the literal `8` in
`TodayTasksWidgetView.swift:88` compiled and turned the test red; restored from a `cp` backup, green.

**`CadenceWidgetFamilyLayout.habitLimit` / `.habitColumns` / `.milestoneGoalLimit` were NOT
deleted.** After T-2078 their only readers in the tree are the model assertions in
`codexWidgetFamilyBudgetsMatchTheSelectedContent`, one test above — i.e. they are dead to
production. Retiring them is an owner decision about the kept schema, not a side effect of fixing a
red run, and it is recorded in T-2080 rather than done here. **If Codex is mid-edit on
`CadenceCodexWidgetFollowupTests.swift` when it reads this, say so and the coordinator rebases it —
the worktree held no uncommitted change to that file when this was written.**

### The context-budget grant (2026-10-02), and the two things it does not permit

**LEASE ENDED 2026-10-04: [[T-1454]] landed on `main` and `codex/context-budget` reviews as
`CODEX-BRANCH-ALREADY-LANDED` (all four files). `CLAUDE.md`, `scripts/codex-inbox.sh` and
`docs/CODEX_REQUESTS.md` are out of the `lease` block above.** The section below is kept as the
record of what was asked, and its two boundaries still describe what those files are for.

`CLAUDE.md`, `scripts/codex-inbox.sh` and `docs/CODEX_REQUESTS.md` are leased to Codex for the
context-budget work Codex itself scoped. Measured at `74c1d186`: the request document is **306 KB**
with no per-request lookup, and `CLAUDE.md` repeats directory maps, build commands and incident
history that `AGENTS.md` already owns.

Two boundaries, both load-bearing:

**`scripts/codex-inbox.sh` has a selftest and it is a landing gate.** It currently offers
`report | fold R<n> | selftest`. Add `show R<n>`; do not change what `fold` or the id-clash check
mean. The selftest must be green and must gain a case for the new subcommand — a lookup that
silently returns the wrong request is worse than no lookup. `codex-inbox.sh` is `#!/bin/bash`;
`codex-land.sh` is `#!/bin/sh`; do not assume either from the extension.

**`CLAUDE.md` is startup context for every agent, so trimming it is in charter but rewriting it is
not.** Its own rule says: when adding an always-read rule, remove or link out something else. Move
duplicated material to `docs/CLAUDE_REFERENCE.md` or the scoped `AGENTS.md` and leave a link. Do not
remove a safety rule, and do not remove the first-reads ordering. If a line looks redundant but you
cannot find where it is covered, keep it and say so.

**Archiving acted-on requests is permitted only if ids and acknowledgement tracking survive byte for
byte.** The whole point of the inbox is that an id resolves to exactly one entry; an archive that
loses that is a regression, not a saving. Measure the before and after sizes and state both.

**Not granted, and not to be inferred:** `docs/TODO.md`, `AGENTS.md`, `scripts/xcb.sh`,
`scripts/agent-commit.sh`, `scripts/codex-land.sh`, `.github/`. The largest saving in this area —
never reading the 2.4 MB ledger, using `./scripts/ledger-view.sh show`/`brief` instead — is a
coordinator habit that has already been fixed in the agent brief, not a change to any file here.

### T-1980 was leased to Codex (2026-10-02), and it is a FINISH, not a start

**LEASE ENDED 2026-10-02: T-1980 landed on `main`, and its six paths are out of the `lease` block
above.** The section below is kept as the record of what was asked.

Six macOS paths are leased for [[T-1980]] only. This is the first time Codex has held anything under
`Cadence/macOS/Views/`, and the grant is narrow and temporary: it ends when T-1980 lands.

**The implementation already exists and is ~80% done.** Agent `boarddrops` built it and ran out of
budget mid-verification. The work is a patch, not a blank page, and the instruction is **finish and
verify it, do not redesign it**. If Codex believes a design decision is wrong, it says so and stops
rather than rewriting — the decisions were measured, and two of them were measured *against* the
obvious alternative.

**What is already proven:** M1, the headline mutation — both drops restored to the swallowing form
with the `commit:` seam kept — produced **31 issues across 6 tests**, linked and re-signed. The
macOS build is clean at 696 compile tasks, 0 warnings.

**What is missing, and it is the whole job:** M2 (`calendarEventID` dropped from `restore(to:)`,
expected to redden **only** the block-move calendar-link assertions) and M3
(`CadenceTaskBundleSlotSnapshot` dropping `startMin`/`durationMinutes`, expected to redden **only**
the clamp test). These are *attribution* mutations: each must redden exactly one group and leave the
rest green. That is the evidence that proved [[T-1952]] and caught that copying [[T-1580]]'s shape
unaltered would have made it worse. Also missing: a full `-only-testing:CadenceTests` run over final
bytes, and an **iOS build**, which is owed because `Cadence/Shared/CadenceTaskFieldEditCommit.swift`
is touched.

**Two design decisions not to undo.** `CadenceTaskMutationSupport.updateBundle` was deliberately not
reused: it writes `title`, clamps against its own literals, and does not clear members' calendar
links, so reusing it would have changed what the drop does while fixing what it reports. And
`CalendarBoardDayColumn.handleDrop` returned `true` unconditionally because both callbacks were
`Void`; they answer `Bool` now, and the one surviving `return true` is the hit-test deferral to a
bundle card, which is correct.

**`CadenceSaveCommitRule.reportExemptions` is empty (`[:]`) and stays empty.** Fix defects; never
widen or add an exemption.

### `CadenceSaveCommitDisciplineTests.swift` is leased for T-1990 only (2026-10-02)

**LEASE ENDED 2026-10-03: the direct-only detector ([[T-1457]]) landed on `main` from
`codex/save-report-closure-detector`, and this path is out of the `lease` block above.** [[T-1990]]
stays PARTIAL for the stored-callback transport sites; a later grant for them is a new lease.
The section below is kept as the record of what was asked.

Codex asked for this rather than assuming it, which is the behaviour the lease exists to produce.
[[T-1990]] is a change to the **detector**, and `CadenceSaveCommitRule` and its file-private parser
live inside that test file — 118 references — so the ticket is unreachable without it. Granted for
T-1990 only; it ends when T-1990 lands.

**Reserved from other writers while that lease is live.** It was clean and unheld when granted: no
in-flight agent had it, and the only uncommitted paths were `palettecopy`'s four. A coordinator
assigning work that touches this file must check the lease first rather than discovering the clash
at `agent-commit.sh`.

**`reportExemptions` is EMPTY (`[:]`) and stays empty.** [[T-1952]] emptied it by fixing the defect
and [[T-1980]] kept it empty. A detector that makes 47 sites fail and is then made tolerable by
re-populating that list would undo both. If the new rule needs an escape hatch, that is a finding to
file, not a list to refill.

**The trap, which Codex identified itself when filing the ticket:** a structural "a `Void`
declaration may not swallow" rule names **47 of 51** sites in one change, and most are the in-place
field edits the rule deliberately allows. The landable rule is the narrow one — a swallowing
declaration whose only caller is a closure argument whose parameter type returns `Bool`, the
`.dropDestination` shape where the `true` the UI reads is built one frame up in another file.

## The coordinator's side

A lease is a **two-sided** promise and the first draft of this file only wrote one side. Codex's
first assignment reported the gap before writing a line: the lease named paths, but nothing stopped
the coordinator from handing one of those same paths to a subagent an hour later, which is the
collision the worktree was built to remove, re-entering through the coordinator's own door.

So, while a lease is in force:

- **The coordinator does not assign a leased path to a subagent**, and does not edit one itself
  except to land Codex's branch. If something on a leased path needs fixing first, the lease comes
  back before the fix goes out.
- **The coordinator publishes the protocol before assigning work.** Codex branches from
  `origin/main`; a file that exists only in the shared checkout's working tree is a file Codex
  cannot read, cannot run, and is right to refuse to proceed without.
- **Shared test files count as leased paths.** `CadenceTypographyScaleTests` carries the "exactly N
  declared roots" sweep, so *every* typography conversion edits it. Two converters means two writers
  in that one file, which is [[T-1385]] exactly. One converter at a time, and right now that is
  Codex.
- **The coordinator narrows the lease when the assignment ends**, rather than letting it accumulate.
  A lease granting paths nobody is working on is a lease that will eventually be believed.

### The four paths T-1451 asked for, and the two embedded surfaces

**LEASE ENDED 2026-10-04: all four are out of the `lease` block above**, along with
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` and `CadenceTests/CadenceTodayUnificationTests.swift`
— `codex/archive-typography-20261002` reviews with every one of its code files already in `main`.
The section below is kept as the record of what was asked. Its *re-point, never delete or loosen*
direction still binds whoever edits those guards next; it is a property of the guards, not of the
lease.

Three of the four are granted above. The fourth was already granted and Codex could not see it:
`CadenceTests/CadenceSharedTaskRowJobsTests.swift` and `CadenceTests/CadenceTodayUnificationTests.swift`
entered the lease **after** `codex/task-page-typography-finish` branched from `4e6f4feb`, so the
branch's own copy of this file does not list them. Re-point `:675`'s three-read count as T-1451
proposes — the narrow permission in the section above applies to it word for word: re-point, never
delete, loosen or route around, and do not add production reads whose only purpose is to satisfy the
old count. Read the lease from `origin/main`, not from the branch, when in doubt.

`Cadence/Shared/Components/CadenceBoardColumnHeader.swift` is the one grant here that is **not**
iOS-only: `Cadence/macOS/Views/KanbanColumnSupportViews.swift` and the two Calendar views draw it
too. The constraint is the one T-1451 proposed itself — prepare it with fixed-mode preservation and
an explicit caller inventory, and do not opt the macOS or Calendar callers in. There are open
scrolling-performance tickets against the macOS Kanban board; if one of them needs this file, the
lease comes back before that fix goes out, the same way [[T-1492]] took `CadenceDatePicker.swift`.

**Both embedded surfaces: the proposal in T-1451 is accepted.** Today `.timeline` and Lists
`.documents` get explicitly fixed Cadence chrome on the embedding, matching Today's agreed Notes
boundary, and the Calendar and Notes conversions behind them stay separate work. No new lease is
needed for it: `iOSTodayView.swift`, `iOSTodaySchedulePanel.swift`, `iOSListDetailView.swift` and
`iOSListNotesView.swift` all already match `iOSToday*.swift` and `iOSList*.swift`.

`Cadence/Shared/Components/CadenceDatePicker.swift` does **not** return, and the commit that removed
it said it would. It is already a declared scaled root in the inventory at
`CadenceTests/CadenceTypographyScaleTests.swift:422`, and T-1451's own remaining patch order does not
name it, so returning it would grant a path nobody is working on — which this file's own rule says is
the kind of lease that eventually gets believed. It comes back the moment an assignment needs it; say
so rather than working around it.

### The two files loaned for T-1702 have come back — and they came back

The promise this section carried while the loan was in force, kept word for word because it is the
one being discharged:

**They return when T-1702 lands.** [[T-1492]] made the same promise about `CadenceDatePicker.swift`
and I did not keep it; [[T-1800]] records why that was defensible and it is still a promise I broke.

**T-1702 landed as `3d1f5c33` on 2026-09-30, and both files are back in the lease as of 2026-10-01.**
That is this promise kept on its own terms. [[T-1492]]'s is still outstanding and is still recorded
as outstanding in the section above; nothing here discharges it.

What changed under the loan, so Codex is not surprised by the bytes: `iOSFeatureComponents.swift`
gained `CadencePageHeaderEyebrow.ladder(eyebrow:compactEyebrow:detail:)`, three **named** rungs fed to
a `ViewThatFits` on the header line. Two things about that are load-bearing and must not be undone by
a typography pass. First, the budget is not the pane and not the column — it is **what the two chips
on the same row leave behind**, which is why the fix is a ladder and not a width rule in the layout
support. Second, **an `if` inside a `ViewThatFits` builder produces an empty candidate that fits every
width and draws nothing**, and `ViewThatFits` renders its *final* candidate whether it fits or not —
so the rungs are unconditional and ordered deliberately. Re-spelling either property is a change to
the ladder, not to a font.

`iPadTodaySupportViews.swift` is unchanged in substance.

**Open against these two files, and yours now:** [[T-1880]] — `iPadTodayTaskHeader` reads `Date()`
twice for one header, because `iOSTodayView.todayTaskColumn` passes an eyebrow built from one `Date()`
and the header takes another. It was left unfixed precisely because the file was leased. It is a real
two-reads-one-render defect, not a tidy-up: the two reads can straddle midnight.

## Do not edit `Cadence.xcodeproj/project.pbxproj`

`Cadence/` and `CadenceTests/` are `PBXFileSystemSynchronizedRootGroup`s, so a new file under either
is picked up by the app and test targets **with no project-file edit at all**. The explicit entries
still in that file exist only for sources that must also compile into a *second* target — the widget
and the MCP server, which is why `Cadence/Models/*` appears there by hand.

Nothing in the typography work needs a second target. If Codex ever believes a new file does, that
is the moment to stop and say so, because `project.pbxproj` is the single highest-collision file in
the repository and a merge there is not reviewable.

### A leased guard may be re-pointed, never weakened

**`CadenceTests/CadenceSharedBoardChromeTests.swift` left the `lease` block on 2026-10-04**, and
this rule did not leave with it. It is why the two [[T-2061]] re-points landed as re-points: a guard
whose subject moved is pointed at where the subject went, never deleted, loosened, or routed around,
and the assertions bracketing it that stop it going vacuous stay.

`CadenceTests/CadenceSharedBoardChromeTests.swift` is leased because converting
`CadenceTodayOverdueSummaryCards.swift` invalidates a source-substring assertion in it
(`:671`, `size: SectionEyebrowLabel.fontSize`), and the converter is the only party who knows what
the call becomes. A guard edited at landing by someone reading a diff is a guard being rubber-stamped.

The permission is narrow and it is a direction, not a budget. Re-point the assertion at the new
call. Do **not** delete it, loosen it to a weaker predicate, or route around it — and keep the two
assertions bracketing it, which are what stop it going vacuous: the non-vacuity check that the file
is still the heading's file, and the negative control that an 11pt eyebrow tier has not come back.
Note also that the three checks above them (`SectionEyebrowLabel.fontSize == 10` and the two
`countSize ==` identities) are **model** assertions, not source reads, and a conversion should leave
them alone.

### A new test that reads the real product tree is not green until the manifest is regenerated

`CadenceTests/CadenceRealTreeSweepManifest.txt` is the exact list of every `@Test` that sweeps the
real product tree, and two suites compare the committed file against a fresh derivation:
`CadenceTestTargetHygieneTests.theRealTreeSweepManifestIsExactlyWhatTheScanFinds` and
`CadenceGuardScriptSelftestTests.theCheapPrecheckStillAnswersWhatTheAuthoritativeScanAnswers`. A new
sweep that is not listed fails both, and neither is reachable from a scoped run of the suites a
ticket touches — which is how `codexChipAndInspectorReadTheOneLineHeightRatio` arrived at landing
with a cold green, a 193-test run and a named known red, and still reddened the full suite.

**Codex does not regenerate the manifest and the file is not leased.** Every writer in the repository
adds sweeps, the file is derived rather than typed, and a branch that regenerates it conflicts with a
main that also did. Instead: **say in the inbox entry that the ticket adds a real-tree sweep, and
name the tests.** The coordinator runs `scripts/real-tree-sweep-manifest.sh <id> --write` at landing,
where it is one derivation against one tree.

So those two suites being red on the branch is expected when a sweep was added, and is not something
to chase. Every *other* red still is.

## What Codex must not do

- **Never edit `docs/TODO.md` or `docs/TODO_DONE.md`.** Use the inbox.
- **Never force-push, rebase a shared branch, or rewrite history.**
- **Never push to `main`.** Only `codex/<topic>` branches.
- **Never run `scripts/agent-commit.sh --commits-stale`,** or "repair a stale base".
- **Never touch a path outside the lease**, even to fix something obviously broken — say so instead.
- **Never point a test at `~/Library/Containers/com.haoranwei.Cadence/Data/`**, the real app group,
  or the owner's iCloud container.
- **Never kill a process merely named `Cadence`** — the owner runs `/Applications/Cadence.app` and
  an Xcode debug build. Terminate only pids Codex launched.
- **Never erase, boot or shut down a simulator it did not create.**

## What Codex must do

- Build and test through `./scripts/xcb.sh <id> …` with `-scheme` and `-destination`, never a bare
  `xcodebuild`. `-only-testing:` takes `CadenceTests/<SuiteName>` — a **filename runs zero tests and
  exits 0**, and so does a nonexistent suite. Verify names against `./scripts/test-suite-index.sh`.
- Read the real `XCODEBUILD_EXIT=` line from the result block, never `$?` after a pipe, and check
  `swift compile tasks:` is non-vacuous — a warm run printing `VACUOUS-COUNT` carries no evidence.
- Hold the warning baseline at **zero**.
- Write one inbox entry per ticket it closes or files, in the ledger's own shape: the id, a bold
  one-line headline, and the measurement. A closure is written **as** a closure
  (`**CLOSED <date> (codex) — …`), not described as one ([[T-1335]]).
- Use only ids from the range the coordinator reserved for it, recorded at the top of the inbox.

### LEASE WIDENED 2026-10-05 — eighteen paths for [[T-3003]], Codex's four audit findings

Granted by the coordinator at the owner's explicit instruction, relayed in chat: *"please grant it
permission"*. Codex asked for this batch **before** making any production edit, which is the order
this protocol wants and the opposite of the T-1458 case where the work was blocked at handoff.

**Scope, as Codex stated it: the four audit findings only — no schema, project-file or manifest
edits.** The coordinator has NOT seen the four findings; no inbox entry existed for them when this
grant was written, so the scope recorded here is Codex's own words and not an independent reading
of it. Codex files the T-3003 inbox entry naming the four findings; if that entry turns out to need
a path outside this list, ask rather than widen.

**Checked before granting, not assumed.** The eighteen paths were diffed against both landings in
flight: zero overlap with `codex/tracking-ui-retirement` ([[T-1466]], queued), and no overlap with
the live edit set of `codex/continuous-quote-rail` ([[T-1465]], mid-landing). `CadenceCodex*` tests
and `docs/CODEX_LEDGER_INBOX.md` were already allowed and are not re-listed.

**This block is wide — eighteen production paths including `PersistenceController.swift`,
both `CalendarManager`s and `TaskWorkflowService.swift` — so it is a reservation against a
coordinator agent touching them, not only a permission for Codex.** Three of them were edited today
(`CadenceWidgetRefreshCenter.swift`, `CadenceTodayWidgetSupport.swift`,
`TaskWorkflowService.swift`) by the habits/goals retirement, so a branch based before `b802afc5`
will need a merge-base check at landing rather than a take-theirs.

**Retire it when T-3003 lands**, in the same session that lands it, as [[T-1464]]'s seven paths were
retired by `387ebca1` and the four quote paths are owed the same.

### LEASE WIDENED 2026-10-05 — one test file for [[T-3003]], and ONE assertion inside it

Granted at the owner's instruction, relayed in chat. `Cadence/macOS/Services/TaskCompletionAnimationManager.swift`
was already in the T-3003 block; this is its test half, and without it the widget fix cannot land
the reopen it needs.

**The single permitted edit.** `CadenceTests/CadenceTaskStatusLifecycleSurfaceTests.swift:759`
currently reads `expectOccurrences(of: "TaskWorkflowService.markTodo(task)", at: [path: 1])`.
It may become the committed spelling, `TaskWorkflowService.commitMarkTodo(task, in: $0)`, at 1.
**Nothing else in that test may move**: the surrounding transition counts, the direct-assignment
negatives, the funnel counts (`private func write(`, `write(.restored, to: task)` and its pair) and
the non-vacuity controls at the end all stay exactly as they are.

**One condition the request did not state, and it is required.** Two lines above, `markDone` and
`markCancelled` have already made this exact move, and each left its UNCOMMITTED spelling pinned at
zero — `expectOccurrences(of: "TaskWorkflowService.markDone(", at: [path: 0])` — so the old call
cannot come back beside the new one. `markTodo` must gain the same zero-pin
(`"TaskWorkflowService.markTodo("` at 0) in the same edit. Re-pointing the 1 without adding the 0
would leave `markTodo` the only one of the three transitions whose uncommitted spelling is
unguarded, which is a weakening wearing the shape of a re-point.

**Retire this path with the other eighteen** when T-3003 lands.

### LEASE WIDENED 2026-10-05 — a second test file for [[T-3003]], and ONE entry inside it

Granted at the owner's instruction. `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift` was
already in the T-3003 block; this is its test half, the same shape as the
`CadenceTaskStatusLifecycleSurfaceTests.swift` grant above.

**The single permitted edit.** In `CadenceTests/CadenceEditorSaveCommitSurfaceTests.swift`, the one
`SaveSurface` entry whose `path` is `Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift` and
whose `function` is `commit` may change its `successSpellings` from `["onChanged()"]` to
`["finishCommittedEdit()"]`. **Nothing else moves**: that entry keeps its commit-before-report
ordering check and its one-refresh count, and every other editor entry, every failure and
dismissal control, and the surrounding inventory stay exactly as they are.

**The condition this grant rests on.** Moving the pinned spelling to `finishCommittedEdit()` puts
the ordering guarantee behind an indirection: the entry would then prove the popover calls the
finisher, not that the user is told once after the commit lands. Codex states its new coverage pins
both committing callers and the finisher's single `onChanged()`. **The re-point is granted only
with that coverage in the same change** — without it this is a weakening wearing the shape of a
re-point, which is the same trap the lifecycle grant above names.

**Retire this path with the rest of T-3003's** when the ticket lands.

### LEASE WIDENED 2026-10-05 — the save-commit discipline suite for [[T-3003]], FOUR exemption entries only

Granted at the owner's instruction. All four production files this touches were already in the
T-3003 block; these are the exemptions that named them.

**The four permitted removals, verified present before granting.**
`CadenceSaveCommitRule.existenceExemptions` — `toggleEmbeddedTask` under
`Cadence/macOS/Views/ListNotesSupportViews.swift` (`:1896`), `NoteEditorPane.swift` (`:1897`) and
`NotePanel.swift` (`:1898`); and `CadenceSaveCommitRule.commitReachExemptions` — `setStatus` under
`Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift` (`:2096`).

**Everything else holds.** The detector itself, every other exemption entry, the six `allowed:`
call sites, and — named because it is what makes this safe — the **"Exemptions rot" guard at
`:1748`**, which is the thing that would fail if one of these four were still needed. That guard is
the evidence for a removal here; weakening or re-pointing it would remove the only check that an
exemption deletion is honest. `reportExemptions` stays **EMPTY**.

**Removing a stale exemption is strengthening, not weakening** — it is the opposite of the trap the
two grants above name. An exemption is a hole in the detector; closing four of them means four more
call sites are now policed. That is why this one carries no further condition.

**Retire this path with the rest of T-3003's** when the ticket lands.

### LEASE WIDENED 2026-10-06 — one path for [[T-3004]], macOS task-row virtualization

Granted at the owner's instruction. **One production path**, because Codex checked and said so:
`TasksListSectionView.swift` **does not exist**. `TasksListSectionView` is declared inside
`Cadence/macOS/Views/TasksListView.swift` at `:506`, and the Completed section is in the same file,
so the whole of [[T-3004]]'s production surface is that one file. Verified here before granting —
the earlier performance report cited a `TasksListSectionView.swift:530` that is not a real path.

**What the ticket is.** `TasksListView.swift:270` opens a `LazyVStack`, but `TasksListSectionView`
draws an **eager** `VStack` at `:526` with `ForEach(section.tasks)` at `:559`, and a second eager
`VStack` at `:588`. An eager stack inside a lazy one defeats the lazy one: every row body in every
expanded section is built whether or not it is on screen. The owner's Unscheduled group holds 88
tasks.

**This is corroborated, not just profiled.** [[T-2057]] measured the same shape on iOS: an eager
row stack cost **4,005 row bodies and ~11s of main thread** for one tap where a `LazyVStack` cost
**9**. That measurement is why item 1 of the performance report proceeds without waiting for the
owner's trackpad baseline, while items 2-5 wait for it.

**Regression tests go in `CadenceTests/CadenceCodex*.swift`**, already a standing glob, and the
handoff in `docs/CODEX_LEDGER_INBOX.md`, always allowed. Neither is re-listed.

**Kanban sorting is deliberately NOT in scope** — Codex asked to leave it out because it needs a
separate production path and is not free. Agreed; it was already the item its own report called a
cleanup rather than the explanation.

**What must survive, and a lazy stack is exactly what threatens it:** collapse state, drag and
drop, frozen ordering, and deep-link behaviour. A lazy stack changes *when* row bodies are built,
so anything relying on an off-screen row having been constructed fails silently rather than loudly.

**Retire this path when T-3004 lands.**

### LEASE WIDENED 2026-10-06 — three Kanban paths for [[T-3005]], one batched rendering branch

Granted at the owner's instruction. Codex asked for exactly these three and asked for the ticket id
to be assigned by the coordinator; both are here. [[T-3004]] landed as `db37c9c6` and needs no
further action.

**Scope, as Codex proposed it:** bound the mounting of horizontally offscreen list columns, bound
the mounting of vertically offscreen cards, and derive the natural/frozen display ordering once per
list-column render instead of reaching through four separate paths.

**THE SHARED-CONSUMER HAZARD, AND IT IS WIDER THAN THE REQUEST SAYS.** Codex flagged that
`KanbanColumnScroll` serves list columns, section columns, Calendar Board day columns and Calendar
Board rails. Measured here before granting, it has **six** consumers, and only two are inside this
grant:

- `Cadence/macOS/Views/KanbanColumnSupportViews.swift` — **granted**
- `Cadence/macOS/Views/KanbanListColumnView.swift` — **granted**
- `Cadence/macOS/Views/KanbanSectionColumnView.swift` — **NOT granted**
- `Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift` — **NOT granted**
- `Cadence/macOS/Views/CalendarBoardRailSupportViews.swift` — **NOT granted**
- `Cadence/iOS/iOSListSupportViews.swift` — already covered by the standing `Cadence/iOS/iOSList*.swift` glob

So a change to `KanbanColumnScroll` itself reaches **four** surfaces this branch may not edit, one
of them on iOS and one of them the Calendar Board. If the work requires touching any ungranted
consumer, that is a new request, not a widening — stop and ask. The behaviours Codex named must
survive on **every** consumer, not only Kanban: empty-space drops, minimum-height geometry,
composer placement, stable IDs, hover cleanup, frozen ordering, and the drop path's unfrozen custom
ordering unchanged.

**THE BASELINE QUESTION, ANSWERED: the owner's known-revision fullscreen physical-trackpad capture
does NOT exist and is not being produced.** The owner was asked for it and chose to move on. Codex
correctly refused to treat [[T-3004]]'s result as proof for Kanban, and asked for explicit
authorization instead.

**Authorized: a counted-mounting / comparator experiment before production changes.** Count what is
mounted, compare bounded against eager, and report the counts. That is the same evidence class that
carried [[T-2057]] — 4,005 row bodies against 9 — and it is measurement rather than a frame-rate
claim. **No trackpad-FPS improvement may be claimed from hosted row counts or accessibility
paging**, which is Codex's own stated limit and is adopted here as a condition of the grant.

**Out of scope, deliberately:** calendar snapping, header payload work, persistence debouncing, and
the undiagnosed sidebar scrolling. Those remain blocked on the baseline that does not exist.

**Retire these three paths when T-3005 lands.**

### LEASE WIDENED 2026-10-07 — the Dynamic Type cluster and [[T-3011]], ten paths

Granted at the owner's instruction, who asked for Codex to be given more work and the lease to go
with it. **No new ticket ids** — every id below already has a formal ledger entry, so Codex writes
its inbox entries under them and the coordinator folds each in at landing.

**The Dynamic Type cluster: [[T-1364]], [[T-1398]], [[T-1399]], [[T-1400]], [[T-1410]], [[T-1411]],
[[T-1414]].** This batch is Codex's for a structural reason rather than a scheduling one — the two
files the whole cluster turns on, `Cadence/Shared/CadenceTypography.swift` and
`CadenceTests/CadenceTypographyScaleTests.swift`, are already standing globs in this lease, so no
coordinator agent can touch the work at all. The eight new paths are the conversion targets the
tickets name:

- `Cadence/Shared/Components/CadenceChoicePicker.swift` and `Cadence/iOS/iOSChoicePicker.swift` —
  [[T-1410]]'s panels. Two of four are converted end to end and two stay pinned **deliberately**:
  [[T-1364]]'s rule is *convert a panel completely or leave it pinned*, and the two answers
  differing is that ticket's finding, not an inconsistency to tidy away.
- `Cadence/Shared/Components/CadenceTagChip.swift` — [[T-1414]]'s second line-height ratio.
  `CadenceTypeScale.lineHeightRatio` is 1.2 and `CadenceTagChipStyle.chipHeight(hasRemoveControl:)`
  uses its own 1.25; T-1364 states the ratio once precisely so every height computed from a font
  size reads one number.
- `Cadence/macOS/Views/SettingsAppearanceSection.swift` and `Cadence/CadenceApp.swift` — [[T-1399]],
  which was **EVALUATED and deliberately not built**: the costing found the plan wanting. Re-cost it
  before implementing rather than treating the ticket as a backlog item.
- `Cadence/iOS/iOSTaskViews.swift`, `iOSTaskRowActionViews.swift`, `iOSTaskGroupSection.swift` —
  [[T-1411]], whose constraint is the sentence to read first: **a task row is not a conversion unit,
  the page is.**

[[T-1400]] (the two markdown editors) is in the batch but its paths are **NOT granted yet** — the
macOS side is seven `Cadence/macOS/Editor/*.swift` files and the iOS side several more, and a
blanket grant there would be wider than anything measured. Ask for the specific files once the plan
names them.

**[[T-3011]] — `Cadence/Shared/CadenceCapturePaletteSupport.swift`,
`Cadence/iOS/iOSCaptureRadialMenu.swift`.** [[T-3008]] landed `ee9aad1d` today: `onDisappear` now
clears **liveness only**, because the logged pop order showed frames are republished *before*
`onDisappear` fires, so an `onAppear` re-publish would be undone by the event it exists to survive.
The deliberate cost is T-3011: a genuinely destroyed target keeps its frame for the life of the
process. **Every eviction rule considered reintroduced T-3008 somewhere** — a count bound evicts an
index's entries behind a long scroll in a pushed detail; a time bound evicts them behind a
backgrounded app. The ticket names the shape that is probably right: a reference-type `@State` whose
`deinit` unregisters, which is a destruction signal SwiftUI can actually give. **Do not weaken
T-3008's guarantee to satisfy T-3011** — `CadenceNewTaskDropRegistrationTests` replays the measured
pop order and is the control.

**Retire all ten when the work lands.** Ask before touching any path not listed; a path outside the
grant is a new request, not a widening.

### LEASE WIDENED 2026-10-07 (second grant) — [[T-168]]'s iOS Focus mode, three paths

Granted at the owner's instruction, alongside two assignments that need **no new paths at all**.

**[[T-2054]] needs nothing granted — its one remaining path is already leased.** The ticket is
PARTIAL on exactly one sentence: `iOSListEditorMode.newProject` has a single call site, so the drop
that opens `.newArea` cannot replace the Lists row without deleting the only way to make a
**project** on iPad. The remedy is the Area/Project toggle in `Cadence/iOS/iOSListEditorViews.swift`,
which matches the standing `Cadence/iOS/iOSList*.swift` glob. Agent `dropinherit` stopped there
rather than edit a leased file, which is why this is Codex's to finish. The three layers below it
are already **driven, not argued** — a real drag made a task whose stored container is the dropped
list, verified in SQLite.

**[[T-122]] needs nothing granted YET, and that is deliberate.** Rechecked 2026-08-30: *do not
flip*, and the reason is measured on both platforms — a macOS Swift 6 build costs **10 warnings
across 6 files** against a zero-warning baseline, so it fails on its own merits before iOS is even
considered. The useful work is to **name those 6 files and clear the 10 warnings**, which turns a
blocked flip into a decidable one. Measure first and request the six paths by name; a blanket grant
over whatever Swift 6 complains about would be wider than anything measured.

**[[T-168]] — iOS Focus mode: widgets and a landscape timer.** The entry is two words long ("Two
halves"), so the scoping is Codex's and should be stated in the inbox entry before implementation.
Granted:
- `Cadence/iOS/iOSFocusView.swift` — the landscape timer half.
- `Cadence/Shared/CadenceFocusPlanningSupport.swift` — the shared planning surface both halves read.
- `CadenceWidgets/CadenceWidgetsBundle.swift` — a widget is only registered by appearing in the
  bundle body; that file **is** the registration.

**New files under `CadenceWidgets/` need no project edit** — it is a
`PBXFileSystemSynchronizedRootGroup` and self-registers, confirmed by [[T-2078]] and
[[T-2083]]. Do **not** add files to `Cadence/Services/` for widget use: those are explicit
`PBXFileReference`s and would need a `project.pbxproj` edit, which [[T-117]] forbids while the
owner's Xcode is open.

**What the widget half must not repeat.** [[T-2078]] retired two widgets and the thing that would
have survived deleting the views was the **AppIntent**, not the view — an intent is extracted into
AppIntents metadata from the *compiled target*, so it keeps appearing in Shortcuts with no app
surface behind it. If a Focus widget ships an intent, it owns that intent's whole lifecycle.
Also: `CadenceWidgetGenerationLedger.instrumentedKinds` keeps retired kinds on purpose, because it
is the list `clearStoredState` sweeps — adding a kind means adding it there too.

**Retire these three when T-168 lands.** T-2054's and T-122's retirements belong to their own
grants. Ask before touching any path not listed.


## T-3031 — the Reminders launch gate needs its own exit, and the guard that forbids one

**`CadenceTests/CadenceInboxRemindersSurfaceTests.swift` — GRANTED, narrowly, for
`requestAccessAnswersFalseOnlyThroughItsOneRefusal` at `:515-533` and nothing else in the file.**

Codex found this before writing a line of it, and the finding is correct at source. The test pins
`requestAccess()` to **zero** bare `return false` and **exactly two** `refuse(recordingDenial:)`
calls. T-3031's disarmed exit has to answer `false`, so it reddens the first check as a bare return
and the second check as a third refusal. There is no third way to write it. The guard is doing its
job; it was written before a non-denial exit existed.

**The exit is not a denial and must not be recorded as one.** `refuse(recordingDenial:)` is the
*bookkeeping* path — it exists because a user said no at the TCC prompt. A process that is disarmed
by `CadenceEventKitLaunchGate.isDisarmedForThisProcess` never reached TCC and the user never
answered. Routing it through `refuse` would write a denial the user did not make, and that denial
outlives the process in the surface state. So the shape is a **third, separately named exit**, not a
third refusal and not a `recordingDenial: false` argument.

**On "I won't hide the exit in another helper to evade the guard" — right instinct, and the grant
asks for the opposite of hiding.** The comment above the test says the bookkeeping "cannot be
skipped by adding one [bare return]", and a helper whose only purpose is to launder a bare return
out of the scanned body is exactly that evasion. A helper that is *named for what it does* and
*separately pinned by count* is not: it converts an unnamed hole into a counted, named exit that a
fourth one cannot slip past. The test must be able to tell the two apart by reading the source, which
is the whole premise of this suite.

**What the edit must preserve.** Both existing authorization-refusal checks stay, with their
numbers unchanged — bare `return false` stays at **0**, `refuse(recordingDenial:` stays at **2** —
and both non-vacuity controls stay: the `RemindersAccessRequestPlan.forStatus(` requirement and the
`!body.contains("status == .notDetermined")` guard against a hand-written pre-prompt exit. The new
assertions are additive: the disarmed exit appears **exactly once**, by name, and its own body
records no denial and opens no `EKEventStore`. Update the doc comment above the test so it describes
three exits and says which one is not a refusal — a stale comment over a changed count is how the
next reader gets this wrong.

**Not granted, and not needed:** `Cadence/Services/CadenceEventKitLaunchGate.swift`. The gate side
is already complete — `isDisarmedForThisProcess` is at `:60-62` and the file's own doc already names
`RemindersManager` as the uncovered surface. Anything added there would be dead code.

**Everything else in `CadenceInboxRemindersSurfaceTests.swift` is out of scope.** The
`RemindersConnectionState.resolve` tests above `:515` and every other suite in the file are untouched
by this grant.

### T-3031, second guard in the same file — `theManagerReadsRestrictedLiveWithNoSessionFold` at `:316-330`

**GRANTED, additively, on top of the `:515-533` grant above. The file's scope is now those two
tests and nothing else in it.**

Codex measured this one on a compiling run rather than predicting it, and it is real. The assertion
at `:323` is a regular expression whose `\{\s*EKEventStore` requires `isRestricted`'s getter body to
**open immediately** with the live read. A disarm guard ahead of that read is not a different
spelling of the same shape — it is a different shape, and the regex correctly stops matching. The
guard was written when the only thing that could precede the read was nothing.

**What the edit must preserve, and why each piece is load-bearing:**

- **The live comparison itself stays byte-identical.** `EKEventStore.authorizationStatus(for: .reminder) == .restricted` is the whole point of the test: a restriction is device policy, and the manager must read it live rather than cache it. The grant moves what may come *before* that expression, never the expression.
- **The non-vacuity control stays.** `#expect(source.contains("var isRestricted: Bool"))` at `:321` is what stops the regex assertion passing because the property was deleted. Keep it.
- **`deniedInThisSession` is PROHIBITED in this getter, explicitly.** This is the sharpest part of Codex's request and it is right. The doc comment's argument is that `.restricted` has nothing for a session record to have an opinion about — unlike `isDenied`, which deliberately folds one in. A disarm guard is a new early-exit in a getter that previously had none, and the next reader's obvious move is to fold session state into it. Pin the absence now, while the reason is still written down directly above.
- **The disarm exit answers `false`, not `true`.** A disarmed process is not restricted; it simply never asked. Returning `true` would make the UI assert a device policy that may not exist.

**And the flags must stay coherent with each other under disarm.** `theManagerFoldsAllThreeFlagsIntoTheOneConnectionState` at `:338-348` is **NOT granted and must stay green unedited**: it pins `connectionState` to resolve from all three of `isAuthorized` / `isDenied` / `isRestricted`. If disarm drives all three to `false`, the fold must still land on the state that honestly describes a process that never reached TCC — not on anything that reads as authorized. If making that true requires touching the fold or the resolver, **stop and ask**; that is a product-behaviour question about what a disarmed launch shows the user, and it is not inside this grant.

**Update the doc comment above the test.** It currently says the manager "exposes the live status
directly, with no session fold". After the change that is true of the *comparison* but no longer of
the *getter*, which now has a gate in front of it. Say so, and say that the gate is a process-level
disarm and not a session record — same reason as the `:515-533` grant: a stale comment over a changed
shape is how the next reader gets this wrong.

**Still not granted:** `Cadence/Services/CadenceEventKitLaunchGate.swift` (complete already), and
every other suite and test in `CadenceInboxRemindersSurfaceTests.swift` — including the
`RemindersConnectionState.resolve` tests and the task-group-header tests above `:313`, which share
the file and have nothing to do with T-3031.

### T-3086 Mac half — one more test path, because the sweep that proves the reuse is scoped to iOS

**`CadenceTests/CadenceSharedConstantReuseSweepTests.swift` — GRANTED, narrowly, for
`CadenceNotesTabVocabularyReuseTests.theNotesTabPhrasesAreTypedOnceAndOnlyInTheSharedVocabulary`
and nothing else in the file.**

The shared type landed at `db2f214d` (`CadenceNotesTabVocabulary`, in
`Cadence/Shared/CadenceNotePlanningSupport.swift:57`). The reuse test that proves the four phrases
are typed once currently walks `Cadence/iOS` only, because when it was written the Mac was still on
the far side of the fence. Routing `NotesView.swift` through the shared type without widening that
walk would land the Mac half with **no guard against it drifting straight back** — the walk would
keep passing while `NotesView.swift` re-typed all four phrases by hand. Widen the root set to
include `Cadence/macOS`.

**The rest of the file is out of scope.** It hosts the general shared-constant sweep, whose harvest
reads `static let` / `func` / `var` declarations; these three readings are *instance* properties, so
that sweep walks past them and `CadenceNotesTabVocabularyReuseTests` exists beside it rather than
inside it. Do not fold one into the other and do not change the general sweep's harvest — that is a
much wider blast radius than this ticket, and the agent that landed the mobile half deliberately
left it alone.

**Keep the non-vacuity control.** A walk that is widened to a second root must still prove it read
that root — a scanned-file floor, or an assertion that the Mac's own file was seen. A sweep that
silently finds zero files in `Cadence/macOS` passes for the wrong reason and is worse than not
widening it.

**No rendered Mac string may change.** The vocabulary was built from the Mac's own words — tab strip
and column headings alike — so this is a de-duplication, not a copy change. `NotesPage.title` →
`label`, the four `NotesListHeader(title:)` calls → `columnTitle`.

**Do not reach for `usesFullLabels(isRegularWidth:headerWidth:)` on the Mac.** It exists for the
mobile fork, where Today's Notes inspector is regular width but bottoms out at 320pt. The Mac has
the room and uses `label` unconditionally.

**`NoteKind.meeting`'s raw value is persisted in `Note.kindRaw` and the shared type does not touch
it.** Keep it that way: the display vocabulary must not reach the persisted one.

### T-3086: the two sites the widened sweep catches — one GRANTED, one OUT OF SCOPE

Codex asked rather than assuming, and the two answers are opposite.

**`Cadence/macOS/Views/ListNotesView.swift` — GRANTED, narrowly, for the `CollapsibleNoteSection(title:)`
argument at `:279` and nothing else in the file.** That heading is a fourth hand-typed `"Event Notes"`
on a notes surface and it means the same thing the vocabulary means, so it belongs to the type. Route
it through `CadenceNotesTabVocabulary.events.columnTitle` — `columnTitle`, not `label`, because this
is a list heading above a set of notes, which is exactly what `columnTitle` was minted for. The
rendered string does not change. Nothing else in `ListNotesView.swift` moves: not
`filteredEventNotes`, not the collapse state, not `ListEventNoteSectionRows`.

**`GlobalSearchCategory` at `GlobalSearchSupportViews.swift:11` — NOT approved, and the sweep's root
set must not reach it.** Two independent reasons, either one sufficient:

1. **It cannot be done as described.** The enum is `String`-backed and its raw value *is* the display
   string. Swift requires a raw value to be a compile-time literal, so
   `case meetingNotes = CadenceNotesTabVocabulary.events.columnTitle` does not compile. A
   "display-only conversion" here is really: drop the `String` backing or add a separate display
   property, then re-point every read of `rawValue`. That is a restructuring of a search type, not a
   de-duplication of a word, and it is not what this ticket is.
2. **They are not the same thing.** `GlobalSearchCategory` is a taxonomy of eight *search result
   groups* — `Commands`, `Pages`, `Areas`, `Projects`, `Tasks`, `Calendar Events`, `Event Notes`,
   `Notes`. Seven have nothing to do with the Notes page. Binding one of the eight to the Notes tab
   vocabulary would mean renaming a Notes *tab* silently renames a *search category*, and would leave
   the enum reading its own words for seven cases and another type's for one. Two surfaces that share
   a string today are not thereby one concept.

**So: scope the sweep by its ROOT SET, not by exemptions.** Codex is right to refuse to add
exemptions — an exemption list is a place for the next drift to hide. Instead the walk covers the
surfaces that render the notes vocabulary — the Notes page on both platforms plus the one list
heading granted above — rather than all of `Cadence/macOS`. A root set states what the sweep is
*about*; an exemption list states what it has given up on.

**Keep the non-vacuity control either way.** A walk over a named root set must still prove it read
those roots — a scanned-file floor, or an assertion naming a file it must have seen. A sweep that
finds zero files passes for the wrong reason.

**Recorded so it is not re-derived:** `GlobalSearchCategory.meetingNotes`'s raw value stays
`"Event Notes"` and stays hand-typed. If the owner ever renames the Notes event tab, that string is a
deliberate second decision, not an oversight — and this paragraph is the reason it was left.

### T-3091 — ANSWERED: parity, not fullness. `Oct 14`. The Mac does not change.

Codex asked this twice because the answer was only ever written into `docs/TODO.md`, which Codex
does not read. That is the coordinator's distribution error. The answer lives here now.

**Mobile matches the Mac's actual output, unchanged.** Use
`DateFormatters.shortDateString(from:)` exactly as `Cadence/macOS/Views/ListDetailView.swift:291`
does. It renders **`Oct 14`** — `shortDate` is `MMM d` at `Cadence/Shared/DateFormatters.swift:160`.

**Do not use a fuller formatter, and do not change the Mac.** `mediumDate` (`MMM d, yyyy`, `:168`)
exists; adopting it on either platform would *break* the parity this ticket exists to create. And
Codex is right that the shared formatter must not change globally — nothing here asks for that.

**Why the ticket contradicted itself, recorded so the next reader does not re-derive it.** The entry
first said "and the full date" while also requiring Mac parity. The Mac's own output *is* `Oct 14`,
so it demanded parity and not-parity in one sentence. The owner's decision was *"add it to mobile"* —
parity. What they rejected was a phone-specific **divergent** abbreviation and the third date
vocabulary that comes with it. The phrase "the iPad and Mac keep the full date" was the
coordinator's loose wording for "the existing format" inside the option text, never a decision about
length. **Parity, not fullness.** T-3091 was corrected at `fb42ae22`.

**Codex was right to stop and ask rather than pick one reading.** A spec that requires two
incompatible things is not a thing to resolve by choosing the more plausible half.

### T-3095 — the coordinator wrote two of your files to clear a red main. Here is exactly what and why.

`Cadence/macOS/Views/LinksView.swift` and `CadenceTests/CadenceSavedLinkPersistenceTests.swift` are
yours. The coordinator edited both without a grant round-trip because main was red and the conflict
came from a branch the coordinator landed. Two lines in total.

1. **`LinksView.swift:81`** — `title: "Delete Link?"` is now
   `title: CadenceSavedLinkPersistence.deleteConfirmationTitle`.
2. **`CadenceSavedLinkPersistenceTests.swift:50`** — `#expect(mac.contains("title: \"Delete Link?\""))`
   is now `#expect(mac.contains("title: CadenceSavedLinkPersistence.deleteConfirmationTitle"))`,
   with a four-line comment above it saying why it inverted.

**Why the pin had to move rather than the product.** Your T-3085 added `deleteConfirmationTitle` to
the shared file. From that commit on, `noCallSiteRetypesASharedStringConstant` forbade the Mac from
typing `"Delete Link?"` and your `:50` required it. Both could not hold. Mobile already read the
constant (`iOSListSupportViews.swift:774`), and the identical shape is house style one file over —
`TimelineBundleBlock.swift:62` reads `TaskBundle.deleteConfirmationTitle`. **The rendered words did
not change**: the constant's value is the literal it replaced, byte for byte.

**This was the coordinator's miss, not yours.** Reviewing your branch the coordinator noticed that
the Mac still typed the title while the constant existed, wrote that the two platforms could still
drift, and then called it "worth closing, not a blocker" instead of widening the grant by one line.
Your implementation did exactly what the grant allowed.

**Nothing else in either file was touched.** Not `deleteLink(_:)`, not the hover-revealed trash, not
the card styling, and no other assertion in that suite. If you would rather spell either line
differently, say so and it is yours to change — the constraint is only that the two guards agree and
the rendered string stays `Delete Link?`.

### T-3099 — a coordinator agent edited `CadenceCodexSearchOptimizationTests.swift`. That was a lease violation. Here is exactly what and why.

`CadenceTests/CadenceCodexSearchOptimizationTests.swift` matches the standing glob
`CadenceTests/CadenceCodex*.swift` and is yours. Agent `searchfix` edited it in `4baebef0` without a
grant. Its brief told it to stop and report lease-blocked; it did not. **The coordinator is recording
this rather than letting you find a changed assertion in your own test by accident** — and is not
reverting it, because reverting would leave `main` red.

**The change is five lines, in one parity table.**
`codexPreparedQueryPreservesScoresIncludingEmptyAndPunctuation`'s case list:

- `("!!!", [], 1)` became `("!!!", [], nil)`.
- Three non-Latin rows were added (Cyrillic, and two Han rows — one matching, one not).

**Why it had to move with the product.** T-3099 fixed `CadenceSearchMatcher.normalize`, which used to
strip every character outside `[A-Za-z0-9]` — so all CJK, Cyrillic, Greek, Arabic, Hebrew and Thai
content normalized to `""` and became permanently unfindable, while a non-Latin *query* tokenized to
nothing, hit `guard !query.tokens.isEmpty else { return 1 }` and scored **every** row 1. The fix adds
`PreparedQuery.isBlank`, so a genuinely empty field still matches everything and a query that merely
has nothing searchable in it now answers `nil`. Your table is a **parity** assertion — the
`PreparedQuery` and `String` overloads agree — and that claim is untouched and still exact. The `1`
in the `"!!!"` row was incidental data recording the old behaviour, not a deliberate pin.

**The idle-browse case is preserved deliberately.** The only consumer of the flat `1` is the macOS
palette's idle list for a literally empty field, and `isBlank` keeps it. Every other caller — MCP's
`CadenceReadService` sites, `iOSSearchView` via `isSearching`, and
`CadenceCalendarEventSearchSupport.results` — gates on `!trimmed.isEmpty` before scoring and cannot
observe the change. **`GlobalSearchIndexSupport.swift` and `GlobalSearchSupportViews.swift` were NOT
touched**; the lease held there.

**If you would rather spell any of it differently, it is yours** — the only constraints are that the
parity claim stays exact and that `"!!!"` does not go back to matching every row.

### T-3147 — GRANTED: one new UI test file, to reproduce the owner's bug before anything is fixed

**`CadenceUITests/CadenceCapturePaletteUITests.swift` — GRANTED, as a NEW file. Nothing else.**

Codex asked for this and the reasoning is right, so it is recorded rather than just approved:
Device Hub's physical-input backend returns `noWindowsAvailable`, and **an AX invocation is not a
touch** — it enters through a different path than the `DragGesture` under test, so a palette that
opens under AX and not under a finger would look fixed while the owner's bug survived. A timed
hold/slide through XCTest is the only reproduction available here that exercises the real gesture.

**No lease pattern covered `CadenceUITests/` at all**, so the ask was necessary rather than
defensive. The grant is one file, by exact name.

**The four production files stay unchanged, and that is the point of this grant.** T-3147 names
three candidate causes with three different fixes — a clipped palette, a cancelled hold task, and
travel exceeding the 12pt `dragSlop` — and the ticket's own instruction is to reproduce before
changing anything. This file is how that instruction gets carried out. Do not land a production
change in the same batch; report what the reproduction shows first.

**`CadenceUITestsOnly.xcscheme` already exists and is the right vehicle** — it was added under
T-2074 precisely because `-scheme Cadence` fails on an iOS destination with
`Unable to resolve module dependency: 'AppKit'` from the macOS-only unit target, and it was proved
by running `CadenceIOSSeededStoreUITests` end to end (2 tests, 0 failures). Use it; it needs no
change, and changing it is not in this grant.

**Two things worth knowing before you write it.** `CadenceUITests` skips 14 tests behind a real
`XCTSkip`, counted and named in the T-1741 report, so a skip there is visible rather than silent.
And the iOS UI test host is sandboxed: keep every fixture under the test's own temporary directory,
and never point it at the owner's container, the real app group, or any backup directory.

**If the reproduction needs a production file to become testable** — an accessibility identifier on
the tab bar's `+`, say — **stop and ask.** That is a change to a shipping surface and it belongs in
its own grant with its own reasoning, not folded into a test file's.

### T-3170 — GRANTED: nine paths, to finish removing the Block feature

**`Cadence/macOS/Views/TimelineDropInteractionSupport.swift`,
`Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift`,
`Cadence/macOS/Services/FocusManager.swift`,
`Cadence/Shared/CadenceFocusPlanningSupport.swift`,
`Cadence/iOS/iOSCalendarBoardView.swift`,
`Cadence/iOS/iOSBoardCards.swift`,
`Cadence/iOS/iOSFocusView.swift`,
`CadenceTests/CadenceSharedConstantReuseSweepTests.swift`,
`CadenceTests/CadenceSavedLinkPersistenceTests.swift`
— GRANTED, narrowly, for the removal of `TaskBundle` and nothing else.**

The owner's instruction was *"the whole concept of bundle feels a bit unnecessary and adds confusion.
just remove it altogether."* [[T-3170]] carries the measured footprint and the staging rule.

**The set is exact, not defensive.** Agent `debundle` matched all 53 live lease patterns against the
119 Swift files naming `TaskBundle` / `bundleID` / `bundleOrder`; these nine are the intersection.
`CalendarEventPresentationSupport.swift` and `CadenceTests/CadenceCodex*.swift` are leased and were
checked and EXCLUDED — their `bundle` hits are Foundation's `Bundle`, not this feature. The other
~110 block-bearing files were never leased and need no grant.

**What these nine unblock, which is the whole reason the grant exists:** the macOS timeline's
drop-a-task-on-a-task-to-form-a-Block gesture, the iOS calendar board's Block cards, and Block Focus
mode. Left ungranted, the feature would be removed everywhere except three places where it still
looks alive, backed by a model nothing writes.

**Scope limit, and it is narrow.** Only code that exists because Blocks exist may be deleted.
`FocusManager` and `CadenceFocusPlanningSupport` keep Focus itself — `.task(id)` targets already
exist and are independent of Blocks; only the Block-shaped variant goes. Do not refactor these files
while you are in them; an unrelated change inside a grant is how a grant stops being narrow.

**`TaskBundle` STAYS in `Cadence/Services/CadenceSchema.swift` and stays a `@Model`.** This project
has no `SchemaMigrationPlan` (said outright in `CadenceStoreSupport.swift:171`,
`CadenceDataExportService.swift:17/52/825`, `Note.swift:39`), and build 22 shipped Blocks to App
Store Connect on 2026-10-13. Dropping the entity is a later build's job, once no device can hold a
record. A grant to delete UI is not a grant to touch the schema.

**Codex's own work is not disturbed by this.** Checked at grant time: its worktree is on
`codex/phone-capture-load`, last commit 2026-10-12, and no `codex/*` branch touches any of the nine.

### T-3192 — GRANTED: the two iOS list files, for one add-section row and nothing else

**`Cadence/iOS/iOSListDetailView.swift` and `Cadence/iOS/iOSListEditorViews.swift` — GRANTED,
narrowly, to adopt a shared add-section control. No other change.**

`Cadence/iOS/iOSList*.swift` is the first pattern on this lease, so the iOS half of T-3192 could not
be written at all without this. The owner asked for the control on **both** platforms through one
shared implementation, and iOS is the side that needs it most: a section currently **cannot be
created anywhere on iPhone or iPad**. The only `addSection()` in the product is the macOS Kanban
board's trailing rail (`KanbanListSectionSupportViews.swift:242`).

**Checked before granting, not assumed.** No `codex/*` branch has touched `iOS/iOSList*.swift`
since **2026-10-07** (`codex/leased-followup-batch`, `codex/typography-lifecycle-batch`); the two
newer ones that touch them, `codex/mobile-project-deadline` and `codex/parity-functional-batch`,
last committed 2026-10-09 and both already landed. Codex's active worktree is on
`codex/phone-capture-load`, which touches neither. `iOSListDetailView.swift` last changed on main in
`39bc9f21` on 2026-10-09, itself a landed Codex branch.

**Scope limit.** Add the row and wire it to the existing committed write path
(`CadenceSectionConfigMerge.addSectionConfig`, which already answers a declined/committed outcome).
Do not restructure these files, do not change their grouping or sorting, and do not touch the
typography or list-layout work the lease is protecting. An unrelated change inside a grant is how a
grant stops being narrow.

**No schema change.** `Area` / `Project` already carry `sectionNamesRaw` and `sectionConfigsRaw`,
and `AppTask` carries `sectionName`. This is a second entry point onto a path that already exists.

### T-3170 — GRANT AMENDED: one Codex test file the original grant wrongly excluded

**`CadenceTests/CadenceCodexFocusLandscapeTests.swift` — GRANTED, for one assertion. Nothing else.**

**This corrects an error in the T-3170 grant above.** That grant excluded
`CadenceTests/CadenceCodex*.swift` with the stated reason that their `bundle` hits are Foundation's
`Bundle` rather than this feature. That was checked across the Codex files **as a group** and is true
of the others — it is **not** true of this one. Line 39 asserted
`landscape.contains("bundleControls(for: bundle)")`, a `TaskBundle` pin by name. Removing Block
Focus under T-3170 necessarily makes that assertion false, so the file had to change and the
original grant left it unreachable.

**The permitted change is one assertion**, inverted to pin the removal instead of the feature:

```swift
// T-3170: Block Focus mode is gone, so the landscape layout has no block transport.
#expect(!landscape.contains("bundleControls"))
```

Every other assertion in that file — `sessionClock(fontSize: 66)`, `focusControls(for: task)`,
`taskListPane`, `.cadenceFixedTypography()`, the `timerState =` negative — stays exactly as it is.
This file is Codex's record of the Focus landscape layout and keeps that job.

**Recorded because the method failed, not just the outcome.** The exclusion was reached by matching
lease patterns against a list of files that name `TaskBundle`, then reasoning about the group. The
right check is per file: `rg -n "TaskBundle|bundleID|bundleOrder|bundleControls" <path>` and read the
hits. A group-level "these are all Foundation's Bundle" is exactly the shape of claim that is right
four times and wrong once.

**Attribution is unknown.** The edit was already in the working tree when this amendment was
written, and the agent that reported it credited the coordinator, who did not make it. It is correct
and minimal, so it stands — but it was made against a leased path with no grant in force, which is
the thing this document exists to prevent.

### 2026-10-19 — `CadenceTagChipStyleTests.swift`: ONE census line, for [[T-1477]]'s parked iOS half

**This is a local agent entering a leased path, not a widening, and it does not belong in the
fence.** The fence governs which paths CODEX may write; a coordinator or local agent entering a
Codex path is recorded in prose, which is what this is — the same shape, and the same file, as
"COORDINATOR REPAIR 2026-10-17" above. Nothing was added to or removed from the ```lease block.

**The whole change is one line.** `"Cadence/iOS/iOSStoreBackupSettingsSection.swift"` added to
`CadenceTagChipScaleTests`' `undeclaredControls` inventory, in sorted position, with a comment
naming [[T-1477]] beside the T-1841 one that is already there for the section directly above it on
the same screen. Not the sweep, not the `atLeast: 300` floor, not the declared/undeclared rule, not
the chrome families above it, not any other assertion in the suite.

**Why it cannot be deferred, and why it is not a choice.** T-1477's shared and macOS halves landed
in `66a58761`; the phone's `iOSStoreBackupSettingsSection` compiled for iOS with 0 warnings and its
scan test passed, then was parked outside the repo because it draws `iOSIconTile` and
`iOSActionButton`. That inventory is a CENSUS: the suite asserts
`Set(controlSites) == undeclaredControls.union(declaredControls)`, so the section and the line are
mutually blocking. With the file present and the line absent, `main` is RED. With the line present
and the file absent, `try read(path)` throws and `main` is RED — which is exactly how
`042a5767` turned it red in October and why the repair above was taken. A red `main` outranks a
lease courtesy, and queueing a round trip for one line costs a batch slot the owner is spending on
velocity. The ticket has been PARTIAL on this one line since 2026-10-18.

**The classification was verified in the file, not assumed.** `iOSStoreBackupSettingsSection.swift`
contains no `.cadenceScaledTypography()`, so `undeclaredControls` is its correct side of the suite's
second assertion. That is also the right answer and not merely the passing one: it is a section
inside `iOSSettingsView`, which is itself undeclared, as are `iOSDataExportSettingsSection`,
`iOSArchiveImportSettingsSection`, `iOSDataResetSettingsSection` and
`iOSUnmanagedStoreSettingsSection` — every other card on Settings → Data Safety. The environment
default is that page's answer and this card renders as the rest of the screen does.

**Nothing in flight collides.** No live Codex branch touches this file.
`codex/capture-list-sections` and `codex/mobile-calendar-notes-parity` are the two checked out in
worktrees right now and neither does. Three archived branches do —
`codex/archive-large-text-20261002` (2026-09-27), `codex/archive-typography-20261002` (2026-09-29)
and `codex/leased-followup-batch` (2026-10-07) — and all three are already represented on `main`.
If Codex holds an unlanded edit to this suite, this one added line is the whole of the change and
should reconcile trivially.

### 2026-10-19 — three EDITING surfaces granted to Codex for [[T-3238]]: one editor app-wide

The owner, after using build 23: *"on ipados, when i click on a task from today or wherever, i still
see the old task inspector... make sure there is only 1 task editor/inspector throughout the entire
app."*

**The measured inventory of every `CadenceSchedulePanel` host and how it presents** — this is the
whole diagnosis and it is not what the complaint sounds like:

| surface | presentation |
|---|---|
| `iOSCreateTaskSheet` (the `+`) | capture card |
| `iOSCalendarQuickCreateSheet` (drag-create) | capture card |
| **`iOSTaskDetailSheet`** (tapping a task) | **sheet chrome** |
| **`iOSCalendarEventEditSheet`** (tapping an event) | **sheet chrome** |

`iOSTaskDetailSheet` already holds **8** `CadenceSchedulePanel` references. **Every surface already
shares the same FORM; only the chrome differs.** So this is not an old editor — it is the right
panel in a `NavigationStack` sheet instead of a floating card. **The work is the presentation, not
the form**, exactly as it was for drag-create.

**GRANTED:** the three paths above. All clean and unleased at the time of granting, and disjoint
from both agents currently live in this checkout (`dragcreate` holds the creation surfaces,
`dragbug` holds `iOSCalendarTimelineViews.swift`).

**The question that must NOT be decided silently.** An editing surface needs what a creating one
does not: delete, completion state, and the fact that the thing is already saved. The capture
presentation may have nowhere to put them. **If so, say so and propose** — do not drop the
affordances, and do not quietly keep two chromes. That is a decision for the owner.

Do not touch `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift` — it is mid-edit here and
carries its own owner-filed ticket, [[T-3237]].

### 2026-10-19 — `iOSMarkdownEditor.swift` granted to a local agent for [[T-1481]]'s iOS half

**Unblocking a queue that has been idling on this for hours.** The hourly batch runner has reported
"nothing launched; inlinepanel2 leased" on every fire since, and the lease was the only thing in the
way.

T-1481 gives both platforms the shared panel inline in a note. The macOS half landed; the iOS half
needs the editor to apply a task-embed block and host a `UIHostingController` view inside its
`UITextView`, so that `iOSMarkdownEditingSurface` can route a card tap to `CadenceTaskInlinePanel`
rather than `iOSTaskInspectorSheet`.

**GRANTED for T-1481 only**, scoped to that embed plumbing. Verified with `--no-merges`: two branches
have modified this path, `codex/leased-followup-batch` (2026-10-07) and
`codex/mobile-calendar-notes-parity` (2026-10-17). **Both landed** — the second by this coordinator
in `f1fe7afc`, the first confirmed landed on 2026-10-18 when its four sampled test functions were all
found on main. Graveyard.

**The caution that applies here specifically:** this file carries a documented selection-clamping
race at `:207-209` and `:410`, whose comment at `:106` records why "not beginning is the stronger"
guard resolves it. Codex was granted a scroll request here on 2026-10-18 and was told the clamping
is load-bearing and off limits. **The same holds for this grant.**

### 2026-10-19 — `CalendarPageMonthSupportViews.swift` grant EXTENDED to the drag-create conversion

The 2026-10-17 grant on this path was scoped to [[T-3170]]'s trio pass. Agent `dragcreate` hit it
while converting the macOS drag-create onto the shared panel and **stopped rather than reading
"granted once" as "granted"** — the right call, and the one three agents got wrong earlier this week
in the other direction.

**EXTENDED to the drag-create conversion.** Verified again rather than carried over: with
`--no-merges`, exactly one branch has ever modified this path, `codex/ui-refresh-reconciliation`,
landed by this coordinator in `7343bfe8`. Graveyard.

**The constraint that makes this delicate, and the agent found it before asking.** This file hosts
the macOS calendar page's own day column — the exact host of drag-create — and **its two create
closures cannot take a day.** So a day changed inside the converted panel has nowhere to be written.
The agent's recommendation is right and is adopted as the scope: **gate that case through the
panel's existing `canCommit` / `failureNotice` inputs rather than reshaping the panel's contract.**
[[T-3171]] has spent six slices converting surfaces ONTO that panel; widening its contract to fit
one host would undo the programme.

If gating proves impossible without a contract change, **STOP and report** — that is a decision for
the owner, not an implementation detail.

### 2026-10-19 — GRANT: the calendar's DRAG-CREATE path, iOS and macOS, for one creation surface

**The owner's report:** *"on at least ios and possibly mac os too, the task and event creation from
the calendar view (that is, dragging to create an event or task) is still using the old task and
event creation sheet. fix that."* They are right on both platforms, and the two cases are different.

**iOS — two presentations of the SAME panel.** The `+`/capture path reaches
`iOSCreateTaskSheet.swift:71`, which applies `.capturePresentation(CadenceScheduleCaptureOptions(...))`
— the floating card. The calendar's drag-create reaches `iOSCalendarQuickCreateSheet.swift:97`,
which wraps `CadenceSchedulePanel` in a plain `NavigationStack` sheet. Same panel underneath,
different chrome, so the owner correctly reads one of them as "the old sheet". The fix is the
presentation, not the form.

**macOS — genuinely the old surface.** `QuickCreateChoicePopover.swift` contains **zero**
`CadenceSchedulePanel` references and carries its own `enum Mode { case timeBlock, calendarEvent }`.
Note `timeBlock`: **12 occurrences of Block vocabulary survived [[T-3170]]'s removal here**, in a
file no Block pass ever opened because it creates rather than displays.

**GRANTED for this work:** `Cadence/iOS/iOSCalendarQuickCreateSheet.swift` and
`Cadence/macOS/Views/QuickCreateChoicePopover.swift` (both already unleased),
plus the leased `Cadence/iOS/iOSCalendarView.swift`,
`Cadence/Shared/Components/CadenceSchedulePanel.swift`,
`Cadence/Shared/Components/CadenceScheduleCaptureCard.swift` and
`Cadence/macOS/Views/TimelineDayCanvas.swift`.

**Checked, not assumed:** every branch touching those four landed — `codex/capture-list-sections`
in `b07655ff`, `codex/mobile-calendar-notes-parity` in `f1fe7afc`, `codex/ui-refresh-reconciliation`
in `7343bfe8`, all by this coordinator. `iOSCalendarView.swift` is byte-identical to main on its
branch; the capture card differs only because main has moved PAST the branch since landing, which is
the staleness signature, not pending work.

**Scope limit:** `CadenceSchedulePanel` and the capture card may gain what the new caller needs and
nothing else. If making drag-create use the capture presentation requires reshaping the panel's own
contract, STOP and report — [[T-3171]] has spent six slices converting surfaces onto that panel and
a seventh must not bend it to fit.

### 2026-10-18 — T-3196 grant WIDENED to `taskBadgeContent` and `taskSummary`, after a correctly refused dispatch

**Agent `iosrowdue` was dispatched to finish T-3196's iOS half and wrote no UI code, correctly.** Two
claims in its brief were wrong and it checked both rather than proceeding.

**Wrong claim 1 — "the estimate chip is still on iOS rows."** It was removed in `7f9c0307` at
**16:19**. The coordinator's simulator sighting was real at 14:43 and stale by the time it was
repeated. The agent caught it by build provenance: the installed `Cadence.app` was built 15:11,
an hour before the removal landed. It also recorded a shortcut that looked conclusive and was not —
`strings` over the installed binary scored 0 for `iOSTaskRowEstimateChip` **and** 0 for four chips
visibly on screen. Timestamps answer this; symbol greps over a binary do not.

**Wrong claim 2 — "both are INSIDE `iOSTaskViews.swift`, so they are granted."** They are not. The
2026-10-16 grant is **sub-file scoped**: it names `iOSTaskRowEstimateChip` and two call sites and
then says *"Nothing else in these files — they carry the task row's whole layout."* **Being inside a
granted file is not being inside the grant.** That misreading is what stalled this ticket the first
time; `rowdue`, `iosrowchrome` and now `iosrowdue` have each stopped at the same boundary, which is
three agents paying for one unwidened grant.

**GRANTED for T-3196 only:** `taskBadgeContent` (`Cadence/iOS/iOSTaskViews.swift:402-409`) and
`taskSummary` (`:225-250`). That is the remaining work: move the due date into the vacated trailing
slot, remove the duplicate badge below the notes, and move the title-line glyphs under the notes.
Keep the notes glyph — [[T-1467]] has not built the macOS excerpt that replaces it.

**A design input the ticket was missing, supplied by the agent and settled here.** T-3196's DECIDED
bullet says the trailing slot "turns RED when overdue", which is half a spec. `:407` already reads
`tint: dueUrgency == .overdue ? Theme.red : Theme.dim`. **The trailing slot carries `Theme.dim` for
an unpassed deadline and `Theme.red` once it passes** — the same two-tint rule the badge uses today.
Without that, a non-overdue due date either vanishes or shouts.

### 2026-10-18 — T-3196 grant EXTENDED: the test that pins the chip's call sites

**The 2026-10-16 grant above named three iOS SOURCE files and no test, so the removal it authorised
was unreachable.** `CadenceTests/CadenceCodexTaskRowTypographyTests.swift:67` asserts

    #expect(row.components(separatedBy: "iOSTaskRowEstimateChip(task: task)").count - 1 == 2)

— exactly two call sites of the chip the grant says to delete. No spelling of the removal compiles
past it. Agent `rowdue` reported this on 2026-10-17 and the grant was never widened, which is why
**the estimate chip is still on iOS task rows today**: I confirmed it on the simulator just now,
`⏱ 1h` on the trailing edge of the Today row, where the owner asked for the due date.

**GRANTED, added to that section's scope:** `CadenceTests/CadenceCodexTaskRowTypographyTests.swift`,
for T-3196 only — revise `:67`'s count and the paired `estimatedMinutes > 0` branch assertions to
match the removal, and nothing else in the file.

Verified landed before granting: one branch modified it, `codex/archive-typography-20261002`
(2026-09-29), and all three sampled test functions are present on main.

**The lesson, and it is the second time today:** a grant drawn from the files a *change* touches
misses the files a *test* pins. `63b024d6` missed a second cap pin the same way. When scoping a
grant for a removal, grep for the symbol being removed across `CadenceTests/` too — the guards are
part of the work, not downstream of it.

### T-3196 / T-3197 — GRANTED: three iOS files, to remove two pieces of row and page chrome

**`Cadence/iOS/iOSTaskRowActionViews.swift`, `Cadence/iOS/iOSTaskViews.swift` and
`Cadence/iOS/iOSTodayCompactViews.swift` — GRANTED, narrowly, for two removals. Nothing else.**

The owner asked for the trailing **estimate chip** to come off task rows on every platform
([[T-3196]]), and for Today's **"Nothing planned"** empty-state card to come off ([[T-3197]]). All
three files are leased and none of the work is reachable without this.

**Exactly what may change.** `iOSTaskRowEstimateChip` (`iOSTaskRowActionViews.swift:414`) and its two
call sites (`iOSTaskViews.swift:195`, `:268`); the "Nothing planned" card in
`iOSTodayCompactViews.swift`. Nothing else in these files — they carry the task row's whole layout
and the compact Today page, and both are surfaces this lease exists to protect.

**Explicitly NOT granted, and not needed:** the `#if DEBUG` seed card at
`iOSTodayCompactViews.swift:200`. The owner asked whether it was dev-only; it is, so it stays
exactly as it is.

**The estimate is not being deleted from the product.** `AppTask.estimatedMinutes` stays, the
capture card keeps Estimate in its overflow, and `iOSFocusView.swift:373` still reads it. Do not
sweep other `estimatedMinutes` readers — the markdown embed, search results, the timeline draft and
the AI note actions each show one for their own reason and are out of scope.

**Checked before granting, per file rather than as a group** — the method correction recorded in the
T-3170 grant amendment above. `rg -n "TaskBundle|estimate" <path>` was read for each of the three,
and no `codex/*` branch has touched any of them since the branches that landed on 2026-10-09.

### T-3170 — GRANT AMENDED AGAIN: the second and last Codex test file, with the glob question settled

**`CadenceTests/CadenceCodexKanbanRenderingTests.swift` — GRANTED, for four argument labels in one
call site. Nothing else.**

`CalendarBoardDayColumn`'s Block parameters are constructed in this file at lines 36-42:
`bundles: []`, `allBundles: []`, `onDropBundleOnDay:` and `onDropTaskOnBundle:`. Removing those
parameters from the view stops this file compiling, so the ninth granted path
(`CalendarBoardDayColumnSupportViews.swift`) cannot be finished without it. Agent `blockgrant`
stopped at the boundary and reported rather than editing, which is correct.

**The permitted change is to drop those four labels from that one call site** so it matches the
view's new signature. Every other assertion in the file stays; it is Codex's record of the Kanban
rendering contract and keeps that job.

**THE GLOB QUESTION IS NOW SETTLED BY MEASUREMENT, SO NOBODY RE-DERIVES IT.** All 23
`CadenceTests/CadenceCodex*.swift` files were checked **individually** for
`TaskBundle|bundleID|bundleOrder|bundleControls|bundles:|allBundles:|onDropBundleOnDay|onDropTaskOnBundle|moveBundle|formBundle`:

- `CadenceCodexFocusLandscapeTests.swift` — 1 hit, granted in the first amendment above, already
  landed by heartbeat `hb1016` in `7c614341`.
- `CadenceCodexKanbanRenderingTests.swift` — 3 hits (`:38`, `:40`, `:41`), granted here.
- **The other 21 are clean.** Their `bundle` hits, where they have any, are Foundation's `Bundle`.

So the original exclusion was right for 21 files and wrong for 2 — which is exactly the failure mode
a glob invites, and the third time in this ticket that reasoning about a group instead of checking
per file has cost a stop-and-amend. The per-file command above is the check; it takes a second.

**Also recorded, because the next person will want it:** the macOS board column cascades into
`CalendarBoardItemSupportViews`, `CalendarPageBoardSupportViews`, `SchedulePanel`,
`SchedulePanelShellViews` and `CalendarPageMonthSupportViews`, **none of which are leased**. This
one test file was the only lock on that door.

### Lease hygiene 2026-10-16 — two dead reservations removed

`CadenceWidgets/FocusSessionWidget.swift` and `Cadence/Shared/CadenceFocusSessionSnapshot.swift`
were removed from the lease block. **Neither has ever existed**: `git log --all -- <path>` returns
zero commits for both, and no `FocusSessionSnapshot` symbol appears anywhere in the tree. They were
reservations for a Focus session widget that was never built, and they survived because a lease
pattern that matches nothing fails silently — it costs nobody anything until someone audits.

The other 51 patterns were checked the same way and all match at least one real file. Note the test
has a trap worth recording: in zsh an unquoted `$p` does **not** glob, so a naive
`ls $p` reports every pattern as stale. `eval "ls -1 $p"` is what actually answers the question —
the first run of this audit produced two false positives (`Cadence/iOS/iOSList*.swift` and
`CadenceTests/CadenceCodex*.swift`) before that was caught.

`Cadence/macOS/Views/TimelineDropInteractionSupport.swift` shows as both leased and dirty in the
shared checkout; that is the T-3170 grant above being exercised, not a violation.

### T-3121 — GRANTED to Codex: two paths, to collapse the duplicated saved-link rule

**`Cadence/Services/CadenceArchiveImportService.swift` and
`CadenceTests/CadenceArchiveImportSurfaceTests.swift` — GRANTED to Codex, narrowly, for T-3121 and
nothing else.**

Codex asked for these by name and the ask matches [[T-3121]]'s own stated scope: mark
`CadenceSavedLinkURL` `nonisolated` in the already-leased
`Cadence/Shared/CadenceSavedLinkPersistence.swift`, then replace
`CadenceArchiveImportService.importedSavedLinkURL(_:)` **and its two mirrored constants** with
`CadenceSavedLinkURL.normalized(raw) ?? ""`. The importer currently restates the scheme rule instead
of asking the type that owns it.

**On the test file, Codex scoped itself before being asked to**, and that scope is the grant:
replace only the two obsolete constant-comparison assertions in
`anImportedSavedLinkIsNormalizedLikeATypedOne`, and **preserve all six behavioural/archive probes**.
Those probes are the part that would still catch a real regression once the constants are gone.

**Checked before granting, per file.** Both paths are clean in the shared checkout and were last
touched by `9984517c` on 2026-10-15 (agent `unbundle`, the archive-import half of [[T-3170]]), which
is landed, not in flight. No local agent holds either.

**The one hazard, stated so nobody discovers it.** `CadenceArchiveImportService.swift` is the file
the Block removal passed through, and the remaining T-3170 work (the macOS board column) does not
touch it — but if a later Block pass needs it, that pass must coordinate rather than assume. The
archive-import half of T-3170 is already landed, so this should not arise.

### T-3140 — GRANTED to Codex: nine macOS/Views paths for observed-day plumbing, one held back

**GRANTED to Codex, for [[T-3140]]'s observed-day parameter chain and nothing else:**

```
Cadence/macOS/Views/CalendarPageView.swift
Cadence/macOS/Views/CalendarPageSupportViews.swift
Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift
Cadence/macOS/Views/CalendarPageComponents.swift
Cadence/macOS/Views/CalendarPageMonthSupportViews.swift
Cadence/macOS/Views/TimelineDayCanvas.swift
Cadence/macOS/Views/TimelineDayCanvasSupportLayers.swift
Cadence/macOS/Views/TimelineTaskBlock.swift
Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift
```

T-3140: the macOS calendar page observes no day change, so after midnight its due labels, urgency,
its own "today" reads and its board columns all stay on yesterday. No `cadenceTracksDayChanges`,
timer or `scenePhase` anywhere in `Calendar*.swift`. The shared helper exists —
`Cadence/Shared/CadenceDayChangeSupport.swift` — and **`cadenceTracksDayChanges(_:)` must be called
inline in `body`**, which is [[T-3124]]'s finding; do not hoist it into a stored property.

**`Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` is NOT granted yet — it is dirty in the
shared checkout right now.** Agent `blockgrant` is mid-edit on it for T-3170's ninth pass (the macOS
board column's Block card and drop arbitration). Ask again once that lands and it will be granted;
taking it now is the two-writers-one-file case this document exists to prevent.

**`Cadence/macOS/Views/TimelineBundleBlock.swift`: do NOT plumb a today-key through it. The removal
lands first.** Codex asked exactly the right question. That file is 57 `TaskBundle`/`bundle`
references deep and is being deleted entirely under T-3170 — threading an observed-day parameter
into it would be work thrown away, and a merge conflict against the deletion. Leave it reading
`today` directly until it is gone. If T-3140's chain genuinely cannot compile without it, say so and
stop rather than working around it.

**Checked per file before granting**, which is the method correction recorded in the amendments
above: all nine are clean in the shared checkout and none is held by a local agent. Two were touched
recently by landed commits — `TimelineDayCanvas.swift` by `afc57985` (2026-10-16) and
`CalendarPageMonthSupportViews.swift` by `10d47357` (2026-10-15) — so **rebase onto current
origin/main before starting**, or the chain will be written against a shape that has moved.

### 2026-10-16 — a grant in prose is not a grant: the fence is the only thing that enforces

The T-3121 (`f00429c0`) and T-3140 (`11d7f691`) grants were written as prose sections and **the
fenced ```lease block was never updated**, so `codex-land.sh lease` kept reporting 51 patterns and
omitted all eleven newly granted paths. Codex could not act on grants it had been given, and said so.
Fixed here: the eleven paths are now IN the fence.

**The distinction that caused it, recorded so it does not recur.** Two different things are both
called a "grant" in this document:

- A grant letting a LOCAL agent into a path the fence reserves for Codex. Prose is enough — local
  agents read the section and `codex-land.sh review` is not what gates them.
- A grant letting CODEX into a path outside the fence. **Prose is not enough.** The fence is the
  machine-readable list `codex-land.sh lease` parses and `codex-land.sh review` refuses against, so
  a path missing from it is a path Codex is refused, whatever the prose above says.

The second kind must edit the fence. Writing only the reasoning produces a grant that reads correctly
to a human and does not exist to the tooling — which is the failure mode this one was.

### T-3140 — the tenth path, released now that the Block removal is off it

**`Cadence/macOS/Views/CalendarPageBoardSupportViews.swift` — GRANTED to Codex, and IN THE FENCE
above**, completing the ten paths requested for T-3140's observed-day plumbing.

It was held back on 2026-10-16 because agent `blockgrant` had it dirty for T-3170's board-column
pass. That pass landed as `aea7e087` and the file is clean. Codex asked to be told rather than
assume, and left it untouched in the meantime, which is exactly right.

Same scope limit as the other nine: the observed-day parameter chain and nothing else.
`cadenceTracksDayChanges(_:)` must be called **inline in `body`** ([[T-3124]]).

### 2026-10-19 — `iOSMarkdownEditingSurface.swift` granted to a local agent for [[T-1481]]'s iOS routing

**GRANTED for T-1481 only**, scoped to the task-embed presentation site — the call that today opens
the full inspector sheet, which becomes the shared panel opened inline in the note. Nothing else in
the file: the outline, unlinked-mentions, reference-picker and scroll-request surfaces are NOT in
this grant even though they sit in the same `body`.

**Staleness, checked properly and worth recording because the first check was wrong.**
`codex/mobile-calendar-notes-parity` has a commit touching this file (`c17deac0`, T-1471/T-1472), and
a three-dot `git diff main...codex/mobile-calendar-notes-parity` shows it ADDING the outline and
unlinked-mentions sheets — which reads as pending work. It is not. Three-dot diffs merge-base to
branch, so they show what the BRANCH added, never what `main` is missing. `main` already carries
those lines. The blob comparison `git diff main:<path> <branch>:<path>` returns **empty**: the branch
holds nothing `main` lacks for this file. That is the test that answers the question a grant asks.

### 2026-10-19 — `iOSTaskRowActionViews.swift` granted to a local agent for [[T-3210]]'s iOS half

**GRANTED for T-3210 only, and ONLY within `struct iOSTaskRowContextMenu`** (lines 456–744 at
`1c3baa95`, next symbol `iOSTaskRowRecurrenceScopeDialogModifier` at 745). The work is making the four
menu actions — Duplicate, Move to List, Move Section, Repeat — invokable and readable by effect, to
match the Mac half landed in `45673bc2`. The earlier T-3196 grant on this file is **removal-only** and
does not cover this; this entry does, and does not widen that one.

**Nothing else in the file.** Two Codex branches hold REAL unlanded work here, and both were verified
by blob comparison rather than by a three-dot diff: `codex/archive-typography-20261002` differs by
132/4 and `codex/tracking-ui-retirement` by 45/4. **Both branches' only hunk on `main`'s side is lines
405–414**, inside `enum iOSTaskRecurrenceSelection` and above `iOSTaskRowSubtaskRow` (423). That range
is disjoint from 456–744, which is what makes this grant safe to give while those branches are still
out. Do not touch 405–414, `iOSTaskRowSubtaskRow`, `iOSTaskRowRepeatChip` or the estimate-chip
typography; a change there collides with one or both branches.

**SPENT 2026-10-20 (agent `n1menu`), and this is the record of what it was spent on.** [[T-3210]]'s
iOS half landed. Every hunk sits at **511-731** on `main`'s side -- inside 456-744, inside
`struct iOSTaskRowContextMenu`, and disjoint from 405-414. Re-checked at commit time with
`git diff main:<path> <branch>:<path>`, never a three-dot diff: `codex/archive-typography-20261002`
is still 132/4 and `codex/tracking-ui-retirement` still 45/4, each a single hunk headed `@@ -405,10`,
so **both branches' only hunk on `main`'s side is still 405-414** and this change does not move a
line either of them touches. `iOSTaskRowSubtaskRow`, `iOSTaskRowRepeatChip` and the estimate-chip
typography were not touched. **Nothing was added to or removed from the fenced `lease` block** -- this
section admits a LOCAL agent, which is prose-side by the rule above it, so there was no fence line
to retire. The file remains Codex's: a later agent needs a new grant, and this one is used up.

### 2026-10-19 — lease widened for `codex/unified-editors` ([[T-3238]]), three test paths, one of them contested

`codex-land.sh review` refused with `CODEX-LEASE-VIOLATION` on three paths. Decided path by path
rather than as a block, because they are not the same case.

**Granted, uncontested — both are NEW files the branch creates.** `CadenceTests/CadenceCaptureEditorTests.swift`
and `CadenceUITests/CadenceCaptureEditorUITests.swift` do not exist on `main` at all, so no other
writer holds them and widening costs nothing.

**Granted WITH A CONDITION — `CadenceTests/iOSEditorSheetMetricsTests.swift` has two writers and they
overlap.** It exists on `main` and its most recent change is `d32ae3a1` (agent `dragcreate`, T-3171),
which is 22 commits newer than this branch's base `3b4756e2`. Measured hunks: `dragcreate` edits the
`main`-side ranges 271-288, 348-355 and 377-387 (14/12); Codex edits 269-276, 388-394 and 403-410
against its own base (6/4). **271-276 is common ground, so the rebase WILL conflict there** — this is
not a hypothetical. Resolve it keeping BOTH sides; `dragcreate`'s hunks must survive the landing, and
the lander must show they did rather than assert it. This is precisely the drop the session handoff
warned about when it said the shared-card work had to be committed before this branch landed.

**Not widened by implication.** This entry covers these three paths for T-3238's landing only. It does
not grant the branch anything else, and it does not widen any earlier Codex grant.

**Also recorded for the lander: `CODEX-INBOX-ID-CLASH` on T-3238 is the protocol working, not a block.**
The coordinator PRE-FILED T-3238 as a stub (`docs/TODO.md:246`, "filed by the coordinator from the
owner's report"). At landing, REPLACE THE STUB BODY IN PLACE — one id, no second entry, per T-1458 /
T-3003 / T-3004. Never delete the entry, renumber it, or edit the check.

**Recorded at landing (agent `editorland`, 2026-10-19): the grant above was written as prose only —
the three paths were never added to the `lease` block, so `codex-land.sh review` kept refusing with
`CODEX-LEASE-VIOLATION` after the grant.** The block is this file's machine-readable half and the
prose is its reasoning; a grant that lives in one and not the other is the drift the block exists to
prevent. All three are now in the block (111 patterns). **Retire them when T-3238 is CLOSED** — they
were granted for this landing only.

**RETIRED 2026-10-19 (agent `ledgerhygiene`), the condition above having been checked rather than
assumed.** T-3238 is CLOSED: `docs/TODO.md` carries `- [T-3238] **CLOSED 2026-10-19 ...` and
`db52ebbd` (*"T-3238 CLOSED: one task editor and one event editor, with dragcreate's hunks kept
rather than merged away"*) is the commit that wrote that first line. All three paths this section
granted are therefore removed from the fenced `lease` block, which drops from 111 patterns to 108:
`CadenceTests/CadenceCaptureEditorTests.swift`, `CadenceTests/iOSEditorSheetMetricsTests.swift` and
`CadenceUITests/CadenceCaptureEditorUITests.swift`. **All three now exist on `main`** -- the two
"new file" grants are new files no longer, which is precisely why the grant was time-boxed: leaving
them in the block would hand Codex standing write access to landed test files it does not own.
**Nothing else was touched.** No other fence line was added or removed, no earlier grant was
narrowed, and the prose above is left standing as the record of why the widening happened. Codex
needs a fresh grant to write any of the three again.

**The conflict resolved, for the record.** `git merge-tree main codex/unified-editors` conflicted in
**two** files, not one. `CadenceTests/iOSEditorSheetMetricsTests.swift` conflicted exactly where the
grant predicted (main-side 271-276): `dragcreate`'s edit there is the quick-create comment and
assertions, Codex's is the two `editor` assertions two lines above, and the two edit sets are
disjoint — both were kept whole. `Cadence/Shared/Components/CadenceScheduleCaptureCard.swift`
conflicted too and the grant did not predict it: both writers rewrote the same `fields` property.
`dragcreate` added `CadenceCaptureFieldInventory.isOffered(_:by:)` and filtered through it; Codex
inlined the identical tag predicate while adding `offersTaskRepeat:` / `offersEventRepeat:`.
Resolved as `fields(for:offersTaskRepeat:offersEventRepeat:).filter { isOffered($0, by: options) }`,
which keeps both behaviours and keeps `isOffered` a live call rather than a helper only its own unit
test reaches.

### 2026-10-24 (later still) — `iOSSearchView.swift` is WITHDRAWN from the fence before it cost anything

Granted in `f487409b` for [[T-5307]], three hours ago, and withdrawn now without that job ever
starting. It blocked [[T-5013]]'s iOS half the same afternoon: `macchrome1420` wrote the change,
found the path newly fenced, and backed it out — correctly, and at a cost of real work.

**The lesson, which is the point of writing this down rather than just deleting the line:** a grant
made *in advance* of a job is a hold on a file nobody is writing. The 2026-10-24 rule above says
release a path when its branch lands; this adds the other half — **do not fence a path until the
job that needs it is actually running**, and prefer "ask if you need it" to a speculative grant.
`iOSSearchView.swift` was never core to T-5307: it came out of a broad grep for tag references, and
the inline row editor that decision chose lives in `iOSSettingsTagsSection.swift`.

T-5307's brief now tells Codex to ask for this path if its rename work genuinely needs to reach
search. Everything else granted in `f487409b` stands.


### 2026-10-24 (later) — the six paths held for `codex/subtasks-inspector` are RELEASED; that branch landed

`codex/subtasks-inspector` landed in `21834d4c` ([[T-1611]] CLOSED, [[T-3171]] PARTIAL), and
[[T-5353]] followed in `ad2d51c4`. The branch ref is not an ancestor of main because the gate
commits with one parent, so check the files, not the ref: every one of the six below has a main
commit carrying its content.

**Released to local agents, same standing as everything in the 2026-10-20 block:**

- `Cadence/macOS/Views/SchedulePanelComponents.swift` — in main at `21834d4c`
- `Cadence/macOS/Views/SchedulePanelPopoverSupportViews.swift` — `c9d7f79c`
- `Cadence/macOS/Views/TaskInspectorContentSupportViews.swift` — `21124632`
- `Cadence/macOS/Views/TaskInspectorStatusActionsRow.swift` — `dad46473`
- `Cadence/Shared/CadenceScheduleDraft.swift` — `21834d4c`
- `CadenceTests/CadenceTaskContextInheritanceTests.swift` — `ad2d51c4`

The other paths granted on 2026-10-24 (the four guard test files of `78e5e26e`, and the nine docs
and budget paths of `703df4f9` for [[T-3149]], which landed in `7198f79e`) are released on the same
reasoning: their branches are in main.

**Why this entry exists at all.** A grant made for a branch outlives that branch unless someone
retires it, and a stale hold reads exactly like a live one. Two agents lost a night to that on
2026-10-24 ([[T-5602]]). When a Codex branch lands, release its paths in the same session.


### 2026-10-24 — what the 2026-10-20 release does and does NOT cover: paths added to the fence AFTER it

**Read this before concluding a fenced path blocks you.** The 2026-10-20 release below says a local
agent may write ANY path the fenced block matches, without a per-path grant. That release was
earned by [[T-3257]]'s audit, which checked **the 137 paths the fence held on that day** and found
every one free of unlanded Codex work. It cannot speak for a path added later, because a path added
later was added precisely because Codex is about to write it.

**So the rule is:** a fenced path that was in the block on 2026-10-20 is released to local agents.
A path added to the block AFTER 2026-10-20 is held for the branch it was granted for, until that
branch lands. `git show b537dd50:docs/CODEX_WORKTREE.md` (the release commit) settles which is which —
a later revision such as `0a970443` cannot, because it already holds post-release additions ([[T-5892]]);
do not guess from the current block alone, because it does not record when a line was added.

**Measured 2026-10-24, because three agents stopped on this.** `mactask2308` ([[T-5310]], [[T-5353]])
and `iossheet2308` ([[T-5359]], [[T-5173]], [[T-5175]]) each finished sound, tested work, found their
paths in the fence, and stopped rather than widen the lease. That is the right failure direction and
neither is at fault — but three of the five paths were never blocked:

- `Cadence/macOS/Services/FocusManager.swift` — in the block before 2026-10-20. **RELEASED. T-5310 may land.**
- `Cadence/iOS/iOSTaskDetailSheet.swift` — in the block before 2026-10-20. **RELEASED. T-5359/T-5173/T-5175 may land.**
- `CadenceTests/CadenceCaptureEditorTests.swift` — **NOT** in the block on 2026-10-20 (corrected by
  [[T-5892]]; this bullet first said it was). Added `db52ebbd` (10-19), retired `1e5f555b` (10-19,
  T-3238's expired widening), absent at the release `b537dd50`, re-added `44e84dbe` (10-21) for
  `codex/t3260-source-pins` ([[T-3260]] item 8). T-5602 checked `0a970443`, which postdates the
  re-add. **Still RELEASED, same tickets — on a different basis:** that branch's one commit
  `cf9f3297` is already in main's copy of the file, `git diff main:<path> codex/t3260-source-pins:<path>`
  shows only main's later edits, and its worktree is clean, so the hold lapsed when the branch landed.
  The test is the fence AT `b537dd50`, or a landed branch — never "present in some later revision".
- `Cadence/macOS/Views/SchedulePanelComponents.swift` and `CadenceTests/CadenceTaskContextInheritanceTests.swift`
  — added `6bb56ed7` / `78e5e26e` for `codex/subtasks-inspector`. **RELEASED 2026-10-24**: agent `land1138`
  landed that branch with its three guard updates ([[T-1611]], [[T-3171]] (C)(i)), so the hold lapsed.

**[[T-5353]]'s inspector half is SUPERSEDED, not merely blocked, and should not be re-attempted.**
`codex/subtasks-inspector` deletes `taskContainerBinding` from `SchedulePanelComponents.swift`
outright, so the binding T-5353 repairs will not exist. The behaviour survives: the adopted path
commits a container change through `CadenceTaskEditDraftCommit.save`
(`Cadence/Shared/CadenceScheduleDraftTaskEditing.swift:165-179`), which calls
`CadenceTaskMutationSupport.assignContainer(task:area:project:sectionName:allTasks:)` — the same
helper `MacTaskRowContextMenu.moveToList` uses, with `allTasks` for the order. T-5353's
`TasksPanelComponents.swift` half is NOT fenced and NOT touched by that branch; it stands and should
land on its own.


### 2026-10-20 — EVERY fenced path released to LOCAL agents, on the owner's decision and [[T-3257]]'s evidence

**The owner's instruction, given 2026-10-19: Codex is finished; release the fenced paths.** This
entry is that release. A local agent may now write ANY path the fenced block matches, without
asking for a per-path grant. **The fenced block itself is deliberately UNTOUCHED** — it is the
machine-read half and it governs what CODEX may write, not what a local agent may. Emptying it
would not release anything: `scripts/codex-land.sh:62` refuses on an empty lease, because "an empty
lease reads exactly like a lease that allows everything; it allows nothing."

**The evidence, and the correction it carries.** [[T-3257]] (agent `n6fence`, read-only audit at
`88fd2e80`) found all 137 paths the 104 distinct patterns match free of unlanded Codex work. The
coordinator spot-checked its hardest case — `Cadence/iOS/iOSTaskRowActionViews.swift`, the one path
this document had explicitly flagged as still held — and T-3257 is right:

- `codex/archive-typography-20261002` (`a8a7d23a`) adds **7** lines to that file; **all 7 are in
  `main`**.
- `codex/tracking-ui-retirement` (`2532828b`) adds **0** — it is removal-only.

**The 2026-10-19 `iOSTaskRowActionViews.swift` grant section above says those two branches "hold
REAL unlanded work" and cites "differs by 132/4" and "45/4". Those numbers are DIFF SIZES, not
unlanded work.** A branch cut weeks ago differs from `main` in both directions, and the larger side
is usually `main`'s own later work reflected back. Reading a blob difference as pending work is the
same family of error as the three-dot diff this document already warns about six times — it answers
"how far apart are these?" when the question is "does `main` lack anything?". The test that answers
it is whether the lines a branch's own commit ADDED are present in `main`. They are.

**What this does NOT change.** The branches still exist and are still local-only, so they must never
be reset, deleted, rebased in place or force-pushed. Nothing here licenses that. It also says
nothing about Codex resuming: if a Codex agent starts work again, the fenced block still governs it
and a fresh conflict must be re-measured rather than assumed from this entry.

### 2026-10-20 — four paths granted to Codex for [[T-3170]]'s tail, on the owner's explicit decision

**GRANTED, scoped to T-3170's Block removal and nothing else:**

- `Cadence/macOS/Views/TimelineDayCanvasStateSupport.swift` — the retired timeline bindings
- `Cadence/macOS/Services/SchedulingService.swift` — the dead Block move chain
- `Cadence/Shared/CadenceTaskFieldEditCommit.swift` — the calendar plumbing
- `CadenceTests/CadenceCommentSymbolClaimTests.swift` — the claims those removals invalidate

They are in the FENCED block because a Codex widening recorded in prose alone does not work:
`codex-land.sh` reads the block and keeps refusing. Count 109 → 113.

**`docs/TODO.md` was REQUESTED AND REFUSED, and that is not an oversight.** Codex asked for it "for
the first-line commit attribution". `codex-land.sh` already has `docs/CODEX_LEDGER_INBOX.md` as the
always-allowed route: Codex writes its entry to the inbox and a LOCAL lander moves it into the
ledger and writes the first line naming the landing sha. Granting Codex the ledger directly would
put a second writer on the file every other agent stages whole.

**How this grant was made, because the procedure matters more than the decision.** Codex reported
its own boundary and asked for the widening. The coordinator started to make the edit and was
stopped — an agent asking another agent to widen its write scope is the permission-laundering shape
this repo refuses by rule, and the fence exists precisely so that scope is not self-served. It was
surfaced to the owner, who granted it explicitly. A grant that originates in an agent's request and
is approved by an agent is not a grant; this one is the owner's.

**Scope reminder for whoever lands it:** this does not widen T-3170 itself. Codex's own audit found
the Block UI and the archive unbundling already landed, so the remainder is the three source paths
above plus the claims test. `TaskBundle` stays in `CadenceSchema` and stays a `@Model` — build 23
shipped blocks and this project has no `SchemaMigrationPlan`.

### 2026-10-20 — 27 paths granted RETROACTIVELY for [[T-1364]], and the order that went wrong

**GRANTED on the owner's explicit decision, scoped to T-1364's text-scale role conversion:** the 25
iOS/Shared settings and calendar sources `codex/text-scale-finish` converted, plus
`CadenceTests/iOSCalendarMetricsTests.swift` and `CadenceTests/CadenceRealTreeSweepManifest.txt`.
Count 113 → 140.

**This grant is RETROACTIVE and that is the wrong order.** Codex wrote the 27 paths first and the
grant followed, which is the sequence the fence exists to prevent. It is recorded here rather than
smoothed over, because a lease that is widened to match whatever was already written is not a lease.
The owner decided it knowing that; the coordinator did not decide it.

**What made it safe to grant rather than redo, measured before asking:** none of the 27 is dirty in
the shared checkout, and no unmerged `claude/*` branch touches any of them. The collision this would
normally risk is not present. That is a fact about today, not a reason the order was fine.

**`docs/TODO.md` was NOT granted and will not be.** The branch edited it directly, which
`codex-land.sh` refuses (CODEX-LEDGER-TOUCHED), and the refusal is correct: eight unmerged branches
hold an edit to that file right now, so it is the one path where two writers always collide. Codex's
ledger edits are dropped at landing and the coordinator writes T-1364's line itself. The route for
Codex is `docs/CODEX_LEDGER_INBOX.md`, which is always allowed and needs no grant.

**For the next Codex request:** ask before writing, as `codex/block-removal-finish` did twice. That
branch stopped at its boundary, reported, and waited — it cost two round trips and no collision. This
one cost a retroactive grant.

### 2026-10-20 — `CadenceTests/TaskBundleTests.swift` granted to Codex for [[T-3170]]'s move chain

**GRANTED on the owner's decision, scoped to retiring the Block-move assertion and its adjacent
comment, and nothing else.** `TaskBundleTests.swift:343` calls `SchedulingActions.dropBundle`
directly, so deleting `dropBundle` breaks compilation — the dependency is real, not a pretext.
**The test's other calendar-link checks stay**; this grant does not cover them. Count 140 → 141.

**Verified before granting, not taken on report:** line 343 does call it; the file is outside the
fence; it is not dirty and no unmerged `claude/*` branch touches it. Six files call `dropBundle` in
all and four are already inside Codex's lease, so this is the last one in the way.

**Asked before writing, which is why this one is cheap.** `codex/block-removal-finish` has now
stopped at its boundary twice and reported rather than editing. Compare the 2026-10-20 T-1364 entry
above, where 27 paths were written first and granted afterwards. Same protocol, opposite order, and
the difference is entirely in what it cost to approve.

### 2026-10-21 — two conversion test paths granted to Codex for [[T-3260]], after a re-check that cut the ask from 13 to 2

**GRANTED, scoped to T-3260's source-pin conversion and nothing else:**

- `CadenceTests/CadencePendingChangePersistenceTests.swift` — replacing the two saved-link
  delegation pins with failure-path tests.
- `CadenceTests/MarkdownImageDropAffordanceTests.swift` — the five drag-routing pins, keeping any
  with no meaningful behavioural replacement.

**The re-check is why this entry is short, and it is the point.** Codex first reported **13** paths
outside the fence. Its worktree was **97 commits behind main**, still on `codex/block-removal-finish`
— so `T-3260` did not exist in its ledger at all, and its lease reading came from a
`docs/CODEX_WORKTREE.md` that predated three widenings. It was asked to sync and re-check rather
than being granted the 13, and the list collapsed to **2**: the completed conversion batches and the
structural pins needed nothing, and `Cadence/Shared/CadenceSavedLinkPersistence.swift` was already
fenced. Eleven paths were never needed. **A stale worktree does not merely delay a Codex agent; it
makes every lease verdict it reports unreliable in the direction of asking for too much.**

**Codex was right about the thing that mattered and stopped twice before writing.** "Not in the
fence" means it may not write, and it reported that rather than editing — the third time this branch
has done so. Compare the 2026-10-20 T-1364 entry, where 27 paths were written first and granted
afterwards.

**A counting defect this exposed, recorded rather than fixed here.** Codex reported 140 patterns and
the coordinator 141; both were wrong. `codex-land.sh lease` emits **142 pattern lines of which 138
are distinct** — `Cadence/iOS/iOSCalendarManager.swift`, `Cadence/iOS/iOSMarkdownEditor.swift`,
`Cadence/macOS/Views/CalendarPageMonthSupportViews.swift` and
`CadenceUITests/CadenceCapturePaletteUITests.swift` each appear twice. Harmless to matching, since a
duplicate glob matches the same paths, but it means no two readers agree on the fence's size.
Deduplicating is a deliberate edit to a machine-read allowlist and is left for someone to do on
purpose.

### 2026-10-21 — five conversion test paths granted to Codex for [[T-3260]]'s remaining clusters, and the one deliberately WITHHELD

**GRANTED, scoped to T-3260's source-pin conversion and nothing else:**

- `CadenceTests/MobileTaskSortStabilityTests.swift` — item (2), 6 pins.
- `CadenceTests/DataIntegrityRepairServiceTests.swift` — item (3), 2 pins.
- `CadenceTests/CadenceNoteFolderMoveCommitTests.swift` — item (4), 3 pins. Its product path,
  `Cadence/Services/CadenceArchiveImportService.swift`, was already fenced.
- `CadenceTests/CadenceEventKitLaunchGateTests.swift` — item (7), 8 pins, the second-largest
  convertible cluster.
- `CadenceTests/CadenceCaptureEditorTests.swift` — item (8).

**WITHHELD, and this is the part worth reading.** Item (1),
`CadenceTests/CadenceTaskInlinePanelControllerTests.swift`, was in the obvious batch and is NOT
granted: `.claude/worktrees/agent-ae999887112dc6790` holds it modified and uncommitted, alongside
`Cadence/Shared/CadenceTaskInlinePanelController.swift`, on a branch whose last commit is T-3076.
Its mtime is 2026-10-20 09:41, so it may well be abandoned — but "probably dead" is not a lease
verdict, and `agent-commit.sh` stages WHOLE FILES, which is the exact shape that reddened CI on
`d65d294` ([[T-1385]]). The path stays with local agents until that worktree is resolved. A stale
worktree is cheap to re-grant later and expensive to collide with now.

**Two PRODUCT paths are also withheld on purpose**, `Cadence/Shared/CadenceTaskQuerySupport.swift`
(item 2) and `Cadence/Services/PersistenceController.swift` (item 3). The brief tells Codex to
convert tests only and to STOP and file an inbox request if a product seam turns out to be needed.
This is not caution for its own sake: item (5) was parked for two passes on "needs a save-counting
seam" and item (4) on the same words, and in BOTH cases the seam already existed and no product
change was required. The default assumption for this ticket is that the seam is already there.
`PersistenceController.swift` additionally owns the store-backup boundary, which is not a file to
open for a test conversion.

**`codex/block-removal-finish` is SPENT and needs no landing.** `codex-land.sh review` reported 19
of 20 files already in main and refused on four CODEX-INBOX-ID-CLASHes (T-1364, T-3170, T-3214,
T-3246) — the pre-filed-stub shape, not a block. The one differing file,
`CadenceTests/CadenceCommentSymbolClaimTests.swift`, was checked by the staleness test in its final
form: all **4** lines the branch's own commits add are present in main, so the blob differs only
because main moved ahead. T-3170's seventeenth pass already says as much in the ledger.


**Count correction, same day.** `44e84dbe`'s commit message says this grant took the fence "143 ->
148 patterns". Both numbers are off by one: it went **142 -> 147 pattern lines, 138 -> 143
distinct**. The coordinator's regex caught a trailing element after the last glob. Codex read the
live lease on the next pass, reported 147, and was right. That is now the THIRD consecutive pair of
readers to disagree about the size of this block — see the entry above where Codex said 140 and the
coordinator 141 and the truth was 142. The four duplicate globs listed there are still duplicated.
Deduplicating a machine-read allowlist is a deliberate edit and still wants doing on purpose, but
the recurring miscount is the argument for it, not a reason to keep rounding.

### 2026-10-21 — seven paths granted to Codex for [[T-3078]], with [[T-3044]] and [[T-3250]](c) already fenced

**GRANTED, scoped to T-3078's deletion of the callerless past-due plumbing:**

- `Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift` — the three card views.
- `Cadence/Shared/CadenceTodayOverdueSummarySupport.swift` — trimmed to the two summary structs
  and `CadenceListOpenRequest`.
- `Cadence/iOS/iOSTodayTaskSections.swift`, `Cadence/iOS/iOSTodayView.swift` — `pendingListOpen`
  and its `.sheet(item:)`.
- `CadenceTests/CadenceTodaySectionMetricsTests.swift`,
  `CadenceTests/CadenceTodayOverdueSummarySurfaceTests.swift`,
  `CadenceTests/CadenceTaskInspectorHostTests.swift` — the guards that must be INVERTED, not
  merely deleted.

**Why this one is properly Codex's rather than a local agent's.** T-3078's remainder has been
blocked since 2026-10-08 by two tests that are themselves inside `CadenceTests/CadenceCodex*.swift`:
`CadenceCodexPageCompletionTypographyTests:97-98` requires `.sheet(item: $pendingListOpen)` to
present `iOSTodayOverdueListSheet(request: request)`, and `CadenceCodexTaskSummaryTypographyTests:19`
calls `CadenceOverdueSummaryMetrics.iconSide` by symbol, so deleting the type is a compile break.
Both are already fenced. The blocker and the fix live on the same side of the lease.

**`Cadence/Services/PersistenceController.swift` is WITHHELD again**, as in the 2026-10-21 T-3260
grant. T-3044's gate change (`storeFileIsNonEmpty`, `:2386-2394`) lives there, and that file owns
the store-backup boundary. Codex re-seeds the FIXTURES only; the one comparison that consumes a real
header belongs to whoever owns that boundary.

**A stale path corrected before it was granted, and a general warning with it.** T-3078's entry
names `Cadence/Shared/CadenceTodayOverdueSummaryCards.swift`; the file is at
`Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift`. The entry is from 2026-10-08 and
more of it will have drifted. This is the same failure the T-3260 grant just produced from the other
direction: that brief was written off a triage whose items (2), (3) and (4) had ALREADY been
converted on main (`0ecf9ad1`, `96648a60`, `671ac2b5`, `25716535`), and Codex correctly converted
nothing under [[T-4100]]. **A ticket's line numbers are a hypothesis about the tree, not a worklist.**
Both briefs now say so in as many words.

**Checked before granting:** no worktree holds any of the seven paths modified, and none matched the
fence already.

### 2026-10-22 — `CadenceSharedBoardChromeTests.swift` granted for [[T-3078]], on the owner's approval, AFTER the edit

**GRANTED:** `CadenceTests/CadenceSharedBoardChromeTests.swift`, scoped to T-3078's deletion.

**The order was wrong and that is recorded rather than smoothed over.** Codex edited this path before
it was fenced; `codex-land.sh review` refused with CODEX-LEASE-VIOLATION, which is the protocol
working. The owner confirms they approved the request when Codex made it, so this is a grant that
trailed its own approval, not an unapproved write — the same shape as the 2026-10-20 T-1364 entry,
and better than it, because Codex reported the path in its own hand-off instead of leaving the gate
to find it.

**The edit was FORCED, which is why it is granted rather than reverted.**
`CadenceSectionEyebrowConvergenceTests.theCountBesideAnEyebrowIsTheEyebrowsOwnSize` read
`Cadence/Shared/Components/CadenceTodayOverdueSummaryCards.swift` by name and asserted on
`CadenceTodayOverdueSummaryHeading`. T-3078 DELETES that file, so the assertion could not survive the
ticket: leaving the path alone would have left a test naming a file that no longer exists. The diff
drops the file's row from the eyebrow census and rewrites the comment to say the board column's count
is the last reader of that rule.

**What this says about scoping a deletion ticket.** A grant list built from "which files declare the
thing being deleted" is not the same as "which files NAME it". The second set is larger and only a
source scan finds it — which is the same lesson [[T-3332]] landed from the other direction hours
earlier. A future deletion brief should run the name sweep BEFORE the grant list is written, not
after the refusal.
