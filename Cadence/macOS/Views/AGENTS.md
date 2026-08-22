# macOS Views Guide

Feature views in this folder are actively refactored into thin roots plus support files. Prefer following the existing split rather than creating another giant view.

## Current Split Pattern

- `FeatureView.swift` - feature root, query/state ownership, orchestration, routing.
- `FeatureSupportViews.swift` - reusable rows, panels, small visual components.
- `FeatureStateSupport.swift` / `FeatureDataSupport.swift` - derived state, sorting, grouping, query shaping.
- `FeatureInteractionSupport.swift` - drag/drop, keyboard, hover, gesture behavior.
- `FeatureShellViews.swift` - layout composition shared across related surfaces.

## Important Feature Families

- `TasksPanel*` - Today/all-task list orchestration, task rows, completion animation scoping, grouping/sorting.
- `SchedulePanel*`, `Timeline*`, `CalendarPage*` - timeline rendering, schedule state, drag-to-create, event/task block layout.
- `Kanban*` - list/all-task kanban boards, card state, section support. `KanbanCard` and `KanbanColumnScroll` (both declared here, both macOS-only) and `CadenceBoardColumnHeader` (in `Shared/Components/`, and read by iOS's list kanban, Calendar Board and month agenda too) are shared with the Calendar Board — parameterize them, never fork them. There is no type named `BoardColumnHeader`.
- `CalendarBoard*`, `CalendarPageBoardSupportViews` - the Calendar page's Board mode: day columns plus the pinned Overdue/Unscheduled rails that replaced the Planning page. Rails, drop targets, and window math live in `Shared/CadenceCalendarPlanningSupport.swift`.
- `ListDetail*`, `ListNotes*`, `LinksView` - area/project detail tabs (Tasks, Kanban, Notes, Links, Completed — Planning is gone from `ListDetailPage`, and `resolved(_:)` maps stale saved values back to `.tasks`).
- `TaskInspector*`, `SchedulePanelPopoverSupportViews` - the task inspector. Generic field-row primitives, content sections, and the recurrence control live in `TaskInspector*`; only the stateful popover wrapper and the inspector's own header/schedule sections and placement breadcrumb live under `SchedulePanel*`. Do not park shared primitives in `SchedulePanel*`.
- `Notes*`, `NoteEditorPane`, `NoteEditor*`, `NoteReferenceSupportViews`, `NoteActionReviewSheets`, `AIActionsSupportViews` - the Notes surface and its AI actions. Under active rewrite; read the file before trusting any description of it.
- `TaskSurfaceFreeze*` - shared hover-freeze models/coordinator used by Today, Inbox, and list-detail task surfaces.
- `TaskTitleEntryField*`, `TaskTitleInlineTagPicker`, `Tag*`, `ContainerPickerSupportViews` - the
  shared title field with inline `~` list search and `#` tag entry, plus the pickers behind it.
  `~` picks a **list only**: selecting one normalizes the section silently and returns focus to the
  title. This line used to read "`~` list/section search", and `CLAUDE.md` described a second
  section-picking step in detail; there is no such step and never was. Section is chosen from
  `TaskSectionPickerBadge` in the chip strip.
- `Focus*` - focus timer, task/bundle picker, log-session popovers, focus sidebar.
- `QuickCreateChoice*` - drag-to-create task/event/bundle popover and support views. It carries a
  second, near-duplicate copy of `TaskTitleEntryField`'s `~` list flow (`tildeFlatContainers`,
  `selectTildeContainer`, `selectTildeContainerItem`), sharing only `TildeContainerPickerRow`. A
  fix to one has to be made twice until they are unified.
- `Settings*` - settings shell and category sections.
- `GlobalSearch*` - command palette state, indexing, interaction, and shell views.
- `Habit*`, `Goal*` - long-running progress surfaces. Pursuits were merged into `Goal`; top-level goals are directions and their sub-goals are milestones. Neither owns its own chrome any more:
  the habit detail's tile, card, heatmap and 7-day strip are all
  `Shared/Components/HabitProgressViews.swift`, and `GoalListLink` writes go through
  `Shared/GoalListLinkHelpers.swift` (`attachList` / `detachGoalListLink` / `toggleGoalListLink`).
  Until `23eb847` three files wrote links by hand — `GoalAttachWorkSheet` here and
  `Sheets/CreateGoalSheet` held the **four** `insert(GoalListLink(...))` sites between them, and
  `GoalAttachWorkSheet` and `GoalsView` the bare `delete`s. (`GoalInspectorView` only ever *read*
  links and took an `onDetachList` closure; it is not one of the offenders.) Do not add a fifth
  insert.
- `SettingsAboutSection.swift` - the About category's build card (`Version`, `Build`, `Bundle ID`,
  over the shared `CadenceAppBuildIdentity`, declared in `Shared/AppStoreReviewReadiness.swift` —
  the file name is not the type name — and the shared `CadenceSettingsInfoRow` promoted out of iOS)
  **plus the Privacy Policy and Support links**, from the shared `CadenceAppReferenceLink.all` in
  that same file. This bullet said the opposite until T-220 closed, and so did the file's own doc
  comment: the links used to sit on Data Safety "beside the paragraph and the delete control they
  belong with", which was a description of an accident. They sat there because the privacy
  *paragraph* did; a Support page is not a data-safety control, and a harmless link a tab-stop from
  an irreversible delete reads as one more thing that might erase something — the argument that
  already keeps `.about` out of the Account & Safety rail group. The paragraph stayed, and
  `SettingsReviewLinksSection` is now `SettingsPrivacyStatementSection` so the name does not promise
  links it no longer has. Chrome is per-platform (`SettingsActionButton` here, a 44pt-target `Link`
  on iOS); the *list* is not, and `MacSettingsAboutAndHabitMetricsTests` pins both About screens to
  it and both view files to zero hand-typed link titles.

The globs above are the whole family, singular where it looks plural. This list previously said
`FocusView*`, `Goals*` and `Habits*`, each of which matches about two files of nine — a glob that
silently returns a fraction of a family reads like a complete answer, which is how support files
get re-created instead of found. `HabitListSupport.swift`, `FocusLogSessionPopovers.swift` and
`GoalTimeline*` are the ones the plural spellings dropped.

## View Refactor Rules

- Prefer dedicated `struct SomeSubview: View` over long private computed `some View` blocks.
- Pass explicit bindings, data, and callbacks into subviews. Do not pass entire managers unless the subview truly owns that behavior.
- Keep row rendering stable; avoid `ForEach(indices, id: \.self)` for filtered/reordered data when row identity matters.
- Preserve shared hover behavior. For task/event/bundle hover states, keep original colors and lift/brighten rather than graying them.
- Preserve grouped task list identity during hover. In `TasksPanel`, do not freeze flat/date/priority section snapshots on hover; swapping those section trees can cause visible refresh jitter in views like Today grouped by priority. List-group snapshots are the intended hover-freeze path.
- Avoid nested card-on-card visual structures unless the existing feature already uses that pattern.
- When moving view types, keep names unchanged if other files reference them.

## Before Finishing

- Search for moved type names to make sure references still resolve.
- Run `git diff --check`.
- Build the macOS scheme.
