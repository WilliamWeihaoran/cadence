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
- `Kanban*` - list/all-task kanban boards, card state, section support. `KanbanCard`, `BoardColumnHeader` and `KanbanColumnScroll` are shared with the Calendar Board — parameterize them, never fork them.
- `CalendarBoard*`, `CalendarPageBoardSupportViews` - the Calendar page's Board mode: day columns plus the pinned Overdue/Unscheduled rails that replaced the Planning page. Rails, drop targets, and window math live in `Shared/CadenceCalendarPlanningSupport.swift`.
- `ListDetail*`, `ListNotes*`, `LinksView` - area/project detail tabs (Tasks, Kanban, Notes, Links, Completed — Planning is gone from `ListDetailPage`, and `resolved(_:)` maps stale saved values back to `.tasks`).
- `TaskInspector*`, `SchedulePanelPopoverSupportViews` - the task inspector. Generic field-row primitives, content sections, and the recurrence control live in `TaskInspector*`; only the stateful popover wrapper and the inspector's own header/schedule/placement sections live under `SchedulePanel*`. Do not park shared primitives in `SchedulePanel*`.
- `Notes*`, `NoteEditorPane`, `NoteEditor*`, `NoteReferenceSupportViews`, `NoteActionReviewSheets`, `AIActionsSupportViews` - the Notes surface and its AI actions. Under active rewrite; read the file before trusting any description of it.
- `TaskSurfaceFreeze*` - shared hover-freeze models/coordinator used by Today, Inbox, and list-detail task surfaces.
- `TaskTitleEntryField*`, `TaskTitleInlineTagPicker`, `Tag*`, `ContainerPickerSupportViews` - the shared title field with inline `~` list/section search and `#` tag entry, plus the pickers behind it.
- `FocusView*` - focus timer, task/bundle picker, log-session popovers, focus sidebar.
- `QuickCreateChoice*` - drag-to-create task/event/bundle popover and support views.
- `Settings*` - settings shell and category sections.
- `GlobalSearch*` - command palette state, indexing, interaction, and shell views.
- `Habits*`, `Goals*` - long-running progress surfaces. Pursuits were merged into `Goal`; top-level goals are directions and their sub-goals are milestones.

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
