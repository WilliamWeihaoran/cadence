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
- `Kanban*` - list/all-task kanban boards, card state, section support.
- `ListDetail*`, `ListPlanningView`, `ListNotesView`, `LinksView` - area/project detail tabs.
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
