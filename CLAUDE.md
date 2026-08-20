# Cadence — SwiftUI Productivity App

## Agent Docs
Coding agents should read `AGENTS.md` first. It is the compact, actively maintained working map for repo structure, scoped guide files, build commands, risk hotspots, and refactor rules — including the four **non-negotiable UI patterns** (no hardcoded colours; page headers do not describe the page you are on; one hover layer at one radius; one shared component over near-copies), the required `-only-testing:CadenceTests` scoping, and the warning baseline. This `CLAUDE.md` remains a longer product/feature reference.

> Where this file and a scoped `AGENTS.md` disagree, the scoped guide is closer to the code. Where either disagrees with the code, the code wins — say so rather than following the doc.

## What This App Is
Cadence is a personal productivity and life-management app for macOS and iOS/iPadOS. It is a GTD-style system where users organize life into **Contexts** → **Areas/Projects**, set long-term **Goals**, track daily **Habits**, manage **Tasks** with scheduling, write **Notes**, and stay focused with a **Focus timer**. Tasks can be scheduled to a timeline and synced with Apple Calendar.

## User
The user does not write code. Claude handles all implementation. When something requires a one-time GUI action in Xcode, explain the minimal steps clearly.

## Tech Stack
- SwiftUI + SwiftData (no UIKit, no third-party dependencies)
- CloudKit sync via SwiftData (`cloudKitDatabase: .private("iCloud.com.haoranwei.Cadence")`)
- Targets: macOS (fully built, primary surface), iOS/iPadOS (large, actively-developed surface — see "What's Built (iOS)"), watchOS (not started)
- Apple Calendar integration via `CalendarManager.swift` (EventKit, macOS). Apple Reminders integration via `Services/CadenceRemindersManager.swift` (EventKit reminders, both platforms).
- Bundle ID: `com.haoranwei.Cadence`
- Deployment: TestFlight for personal use

## Platform Strategy
- **macOS**: purpose-built sidebar + multi-column layout (`macOS/`). Fully featured, the primary product surface.
- **iOS + iPadOS**: large, actively-developed surface (`iOS/`, 86 files), not a stub. `iOSRootView.swift` is an adaptive root shell — a full sidebar shell on iPad regular width, a **four-tab bottom bar** on compact width — routing to real implementations of Today, Calendar, Tasks/Inbox, Focus, Goals (top-level directions plus their nested milestones), Habits, Notes (own markdown editor stack), Lists, Search, and Settings. Not guaranteed full feature parity with macOS by design — see `Cadence/iOS/AGENTS.md` and "What's Built (iOS)" below.
- **watchOS**: not started
- Use `#if os(macOS)` / `#if os(iOS)` for platform-specific branches

## Project Structure
```
Repo root:

```
Cadence/                # main app source (below)
Cadence.xcodeproj       # single project; targets: Cadence, CadenceWidgets, CadenceMCPServer, CadenceTests, CadenceUITests
CadenceWidgets/         # widget extension — compiles Models/, Theme.swift, and Cadence*WidgetSupport.swift straight in
CadenceMCPServer/       # native MCP server target (tool definitions, router, argument parsing)
plugins/cadence-mcp/    # Codex MCP plugin wrapper + smoke-test scripts
CadenceTests/           # unit tests (~140 files, flat). Always -only-testing:CadenceTests
CadenceUITests/         # UI tests; cannot launch headless — never let an unscoped test run pull these in
docs/                   # privacy/support site + App Review + release-readiness notes
```

App source. **This names families, not every file** — `macOS/Views/` alone is ~168 files.
Use the scoped `AGENTS.md` in each folder as the working map.

```
Cadence/
├── CadenceApp.swift    # App entry, ModelContainer + CloudKit setup + error recovery
├── Models/             # 100% shared. See "Data Models" below and Models/AGENTS.md
├── Services/           # 48 shared, cross-platform services (re-count when you add one):
│   │                   #   CadenceSchema / CadenceStoreSupport / PersistenceController (legacy shim)
│   │                   #   NoteMigrationService, PursuitToGoalMigration, DataIntegrityRepairService
│   │                   #   NotificationScheduling + NotificationManager (reconciliation, see "Notifications")
│   │                   #   RemindersManager (EventKit reminders, both platforms)
│   │                   #   PrivacyDataResetService (in CadencePrivacyDataResetService.swift)
│   │                   #   Cadence*WidgetSupport, CadenceWidgetIntents, CadenceWidgetRefreshCenter, CadenceDeepLink
│   │                   #   TagSupport, TaskCreationService, NoteReferenceSupport
│   ├── Markdown*Support.swift   # 27 files: ALL markdown parsing/mutation logic lives HERE, not in macOS/Editor/
│   ├── AI/             # AIActionService, AIProvider, AISettingsManager (optional, user OpenAI key)
│   └── MCPReadOnly/    # CadenceRead/WriteService, DTOs, search matcher, audit log, container factory
├── Shared/             # Cross-platform tokens, components, and presentation/query/mutation support
│   ├── Theme.swift     # The ONLY source of colour. See "Design System" below
│   ├── DateFormatters.swift, CadenceHoverStyles.swift, CadenceCardStyle.swift, CadenceDueUrgency.swift
│   ├── TaskDragPayload.swift  # the drag/drop wire format for tasks and bundles, both platforms
│   ├── Cadence*Support.swift    # Task/note/calendar/focus/settings/tracking presentation + query + mutation helpers
│   │                   # The calendar half was one 1,314-line file until T-120 split it, whole types
│   │                   # moved byte-identically, into six:
│   │                   #   CadenceCalendarPlanningSupport — the Board only: CalendarBoardRail,
│   │                   #     CalendarBoardDropTarget/DropAction/AddAction, CalendarBoardPlannerSupport,
│   │                   #     CalendarBoardSortKey
│   │                   #   CadenceCalendarModeSupport — CadenceCalendarViewMode, CadenceCalendarPresentation
│   │                   #   CadenceScheduleSupport — day-canvas hours, date bucketing, schedulable slots
│   │                   #   CadenceCalendarDayBadge — month-grid day badge (state → style)
│   │                   #   CadenceCalendarDateTitleSupport — CadenceCalendarDateTitleFormat + Support
│   │                   #   CadenceCalendarTimedGridSupport — CadenceCalendarZoom, CadenceCalendarTimelineWindow
│   ├── CalendarVisibilityPreferences (in CadenceCalendarVisibilityPreferences.swift) and
│   │                   # CalendarWorkHoursPreferences — both shared, NOT macOS-only. The file name
│   │                   # carries the Cadence prefix; the type does not.
│   └── Components/     # 20 files: CadenceBoardColumnHeader, CadenceBoardMetadataChip,
│                       # CadenceButtons, CadenceContextPicker, CadenceDatePicker,
│                       # CadenceInlineEmpty, CadenceScrollElasticity, CadenceSidebarCountLabel,
│                       # CadenceStartupIssueBanner, CadenceTagChip (also declares
│                       #   CompactTagStrip — see below), CadenceTaskDetailLineLabel,
│                       # CadenceTaskGroupHeading, CadenceValueTile, CadenceWrappingHStack,
│                       # CommitmentSharedViews (CommitmentPageHeader + CommitmentIconTile),
│                       # EmptyStateView, EstimatePickerControl (iOS chip; its popover is shared),
│                       # GoalProgressBar, HabitProgressViews (holds the 52-week HabitHeatmap),
│                       # SectionEyebrowLabel.
│                       #
│                       # This is a list of FILES, and one shared view is not one: CompactTagStrip,
│                       # the read-only compact tag strip used by task rows, board cards and note
│                       # rows on both platforms, is declared inside CadenceTagChip.swift. A
│                       # `find -name CompactTagStrip.swift` comes back empty. See
│                       # Cadence/Shared/AGENTS.md, "The File Name Is Not The Type Name".
│                       #
│                       # Check this list before writing a new shared view — the no-near-copies
│                       # rule is only as good as the inventory an agent can see. Which is why the
│                       # count is load-bearing and keeps going stale: it read 12 across `49c1797`,
│                       # `5aa11dc` and `3dd09ca`, then 15 across `7e5459c` (+3) and `cdf0896` (+2),
│                       # each of which added files here. Re-count the directory when you add to
│                       # it; a stale number reads as a complete inventory and sends the next agent
│                       # off to write a near-copy. That is not hypothetical — T-173 had to delete
│                       # a third hand-written copy of CompactTagStrip for exactly this reason.
├── iOS/                # Large adaptive iOS/iPadOS surface (86 files) — see "What's Built (iOS)"
│   ├── iOSRootView.swift        # Adaptive root shell: iPad sidebar / iPhone tab bar; deep links, widget refresh
│   ├── iOSCompactTabShell.swift # iPhone bottom bar, per-tab paths, centre capture button
│   ├── iOSTasksTabView.swift    # Tasks tab: date + greeting header, Today/All/Inbox switcher
│   └── iOSMoreTabView.swift     # More tab: Focus, Goals, Habits, Lists, Search, Settings
└── macOS/
    ├── macOSRootView.swift + Views/macOSRoot*   # Shell, command routing, overlays, lifecycle, state
    ├── CadenceCalendarPicker.swift
    ├── Views/          # ~165 files, organized as feature root + support files. Families:
    │                   #   TodayView / TodaySupportViews / NotePanel
    │                   #   TasksPanel*        — Today + All Tasks list orchestration, rows, grouping, drop
    │                   #   AllTasksListView, InboxView*, ListDetail*, ListNotes*, LinksView
    │                   #   Kanban*            — one shared KanbanCard + BoardColumnHeader + KanbanColumnScroll
    │                   #   CalendarPage*      — Timeline presentation: Week/2W/Month, infinite scroll
    │                   #   CalendarBoard*, CalendarPageBoardSupportViews — Board presentation (replaced Planning)
    │                   #   Timeline*          — day canvas, metrics, task/event/bundle blocks, drag/drop
    │                   #   SchedulePanel*     — Today's timeline shell + the task inspector's popover wrapper
    │                   #   TaskInspector*     — inspector field rows, content sections, recurrence control
    │                   #   TaskTitleEntryField*, TaskTitleInlineTagPicker, Tag*, ContainerPicker*
    │                   #   TaskSurfaceFreeze* — hover-freeze coordination for task lists
    │                   #   Goal*, Habits*, Focus*, GlobalSearch*, Sidebar*, Settings*
    │                   #   Notes*, NoteEditor*, NoteReference*, NoteActionReviewSheets, AIActionsSupportViews
    ├── Sheets/         # CreateContextSheet, CreateListSheet, CreateGoalSheet,
    │                   # CreateTaskSheet(+SupportViews — holds TildeContainerPickerRow),
    │                   # EditListSheet (declares BOTH EditAreaSheet and EditProjectSheet;
    │                   # there is no file of either name), ListEditorSupportViews
    ├── Editor/         # AppKit bridge ONLY (11 files since the T-105 split): MarkdownEditorView /
    │                   # Support / InteractionSupport / Coordinator / LayoutManager /
    │                   # TextViewDecorations / DecorationGeometry / TextEditDiff, plus
    │                   # MarkdownSlashCommandSupport, MarkdownTaskEmbedDrawingSupport,
    │                   # MarkdownKeyboardShortcutSupport. See Editor/AGENTS.md for the roles.
    └── Services/       # macOS-only managers:
                        #   CalendarManager (EventKit events). RemindersManager is NOT here —
                        #   it is cross-platform in Services/; macOS/Services holds only a
                        #   2-line tombstone comment recording the move.
                        #   PrivacyDataResetService is NOT here either, same reason and same
                        #   shape of tombstone: Services/CadencePrivacyDataResetService.swift.
                        #   (CalendarVisibilityPreferences and CalendarWorkHoursPreferences are NOT
                        #    here — both live in Shared/; see above. macOS/Services still holds a
                        #    2-line CalendarVisibilityPreferences.swift that is only a tombstone
                        #    comment recording the move, and could be deleted.)
                        #   FocusManager, SchedulingService, TaskWorkflowService, TaskCreationManager
                        #   GlobalHotKeyManager, QuickTaskPanelController, GlobalSearchManager
                        #   Hovered{Task,Editable,TaskDatePicker,KanbanColumn,Section}Manager
                        #   {Task,Section}CompletionAnimationManager, DeleteConfirmationManager
                        #   {Task,List}DeleteHelpers, TaskSubtaskEntryManager
                        #   (TaskDragPayload is NOT here either — it is nonisolated and
                        #    cross-platform in Shared/TaskDragPayload.swift, and was one file
                        #    per platform declaring the same type until they were merged.)
                        #   {List,Calendar}NavigationManager, TodayTimelineFocusManager, AppFocus
                        #   NoteExportService, PrivacyDataResetService, AppleAccountManager
                        #   CadenceAppDelegate, CadenceMCPRefreshCoordinator
```

Large macOS surfaces are intentionally split into companion support files rather than one
oversized view file. The rules that keep tripping agents up:
- `SchedulePanel*` is a risk hotspot (timeline coordinate math, drag/drop, EventKit). Generic
  task-inspector chrome belongs in `TaskInspector*SupportViews.swift`, **not** here.
- `Kanban*` components are shared by the list board, the All Tasks board, **and** the Calendar
  Board. Parameterize `KanbanCard` / `BoardColumnHeader` / `KanbanColumnScroll`; never fork them.
- Markdown behavior fixes usually belong in `Cadence/Services/Markdown*Support.swift` (which has
  test coverage); `macOS/Editor/` is only the NSTextView lifecycle, drawing, and event layer.

## Data Models
All SwiftData `@Model` classes. **Critical CloudKit rule: all to-many relationships must be optional arrays (`[Type]?`).**

`Cadence/Services/CadenceSchema.swift` is the authoritative list; the block below covers every
live model.

> **`Note` is the one live note model.** `DailyNote`, `WeeklyNote`, `PermNote`, `Document`, and
> `EventNote` are legacy migration sources only — read by `NoteMigrationService` and deleted by
> `PrivacyDataResetService`. The one extra survival is `Document`: `Area.documents` /
> `Project.documents` still exist as relationship declarations, so `ListDeleteHelpers` and
> `DataIntegrityRepairService` touch them during cascade deletes. Build no UI on any of them.

> **`Pursuit` was merged into `Goal`.** A pursuit is now just a top-level goal (`parentGoal == nil`) with `kind == .ongoing`; the goals it owned are its `subGoals` (milestones) and the habits it owned use `habit.goal`. `Cadence/Models/Pursuit.swift`, `Goal.pursuit`, `Habit.pursuit`, `Context.pursuits`, and the `Pursuit.self` schema entry survive so the one-time `PursuitToGoalMigration` can read pre-merge rows — feature code must not read or write them. Two non-migration callers are deliberate: `ListDeleteHelpers` (cascade-deletes surviving rows with their context) and `PrivacyDataResetService` (wipes them). See the removal checklist in `Cadence/Services/PursuitToGoalMigration.swift`.

> **Sections are not a model.** A kanban/list section is a `TaskSectionConfig` value
> (`uuid, name, colorHex, dueDate, isCompleted, isArchived`, defined in `AppTask.swift`)
> JSON-encoded into `Area.sectionConfigsRaw` / `Project.sectionConfigsRaw` and read back through
> the `sectionConfigs` computed property. `AppTask.sectionName` is only the string pointing at
> one. The older `sectionNamesRaw` is the pre-config fallback the getter migrates from. Always go
> through `sectionConfigs`; never hand-edit the raw strings.

```
Context:   id, name, colorHex, icon, order, isArchived
           → areas:[Area]?, projects:[Project]?, tasks:[AppTask]?, goals:[Goal]?, habits:[Habit]?

TaskBundle: id, title, dateKey(yyyy-MM-dd), startMin, durationMinutes, createdAt
           → tasks:[AppTask]? (nullify delete rule)
           computed: displayTitle, endMin, sortedTasks
           (groups multiple tasks into one timeline block)

Area:      id, name, desc, status("active"|"done"|"archived"), colorHex, icon, order, linkedCalendarID,
           loggedMinutes, hideDueDateIfEmpty,
           hideSectionDueDateIfEmpty (hides Kanban column due date UI when the column has no due date),
           sectionConfigsRaw (JSON [TaskSectionConfig]), sectionNamesRaw (legacy fallback)
           → context:Context?, tasks:[AppTask]?, projects:[Project]?, notes:[Note]?,
             links:[SavedLink]?, goalLinks:[GoalListLink]?, documents:[Document]? (legacy)
           computed: isDone, isArchived, isActive, sectionConfigs, sectionNames

Project:   id, name, desc, status("active"|"done"|"archived"|"paused"|"cancelled"), colorHex, icon,
           dueDate(yyyy-MM-dd), order, linkedCalendarID, loggedMinutes, hideDueDateIfEmpty,
           hideSectionDueDateIfEmpty, sectionConfigsRaw, sectionNamesRaw
           → context:Context?, area:Area?, tasks:[AppTask]?, notes:[Note]?, links:[SavedLink]?,
             goalLinks:[GoalListLink]?, documents:[Document]? (legacy)
           computed: isDone, isArchived, isActive, completionRate, sectionConfigs, sectionNames

Tag:       id, slug, name, desc, colorHex, order, isArchived, createdAt, updatedAt
           → tasks:[AppTask]?, notes:[Note]?   (many-to-many with both)

Goal:      id, title, desc, startDate(yyyy-MM-dd), endDate(yyyy-MM-dd),
           progressType("subtasks"|"hours"), targetHours, loggedHours,
           colorHex, icon, kind("ongoing"|"completable"|"maintenance"),
           status("active"|"done"|"paused"), order, createdAt,
           dependsOnGoalIDsJSON (persisted, ZERO readers — see the warning below)
           → context:Context?, parentGoal:Goal?, subGoals:[Goal]?, tasks:[AppTask]?,
             listLinks:[GoalListLink]?, habits:[Habit]?
           computed: progress (0.0–1.0), isTopLevel (parentGoal == nil)
           (goals nest one level deep in practice: a top-level goal is a direction —
            usually kind .ongoing, what used to be a Pursuit — and its subGoals read
            as milestones. `kind` defaults to .completable so pre-merge goals keep
            reading as milestones.)

> **`Goal.dependsOnGoalIDsJSON` is a live persisted field with no readers, and must not be
> deleted.** It stores finish-to-start dependency IDs as a JSON array of UUID strings; the only
> other mention of it in the repo is a tombstone comment at `macOS/Views/GoalsSupportViews.swift`
> recording that its JSON get/set accessor was removed for having zero readers and zero writers.
> This is the same hazard as `AppTask.calendarEventID` (see "Calendar / Events"), minus the
> readers: it is a stored SwiftData property and there is no `SchemaMigrationPlan`, so removing it
> **drops data** rather than cleaning anything up. A dead-code pass will find no references, no
> UI and no tests, and that is not evidence it is safe to remove. Either build the dependency
> feature or leave the column alone.

AppTask:   id, title, notes, priority("none"|"low"|"medium"|"high"),
           status("todo"|"inprogress"|"done"|"cancelled"),
           dueDate(yyyy-MM-dd), scheduledDate(yyyy-MM-dd), scheduledStartMin(-1=unscheduled),
           estimatedMinutes, actualMinutes, calendarEventID, order, createdAt, completedAt,
           sectionName, bundleOrder
           recurrence: recurrenceRaw("none"|"daily"|"weekly"|"monthly"|"yearly"),
                       recurrenceSeriesIDRaw, recurrenceSourceTaskIDRaw,
                       recurrenceSpawnedTaskIDRaw, recurrenceOccurrenceIndex,
                       recurrenceEndModeRaw("never"|"onDate"|"afterCount"),
                       recurrenceEndDate(yyyy-MM-dd), recurrenceEndCount
           → area:Area?, project:Project?, goal:Goal?, context:Context?, bundle:TaskBundle?,
             subtasks:[Subtask]?, tags:[Tag]?
           computed: isDone, isCancelled, isRecurring, scheduledEndMin, containerName,
                     containerColor, resolvedSectionName, shouldShowDueDateField,
                     hidesEmptyDueDateInList, sortedTags, effectiveRecurrenceEndMode,
                     recurrenceHasEnded, recurrenceOccurrenceNumber,
                     isRecurrenceSeriesMember

Subtask:   id, title, isDone, order, createdAt → parentTask:AppTask?

GoalListLink: id, createdAt → goal:Goal?, area:Area?, project:Project?
           (links a goal to a whole list; computed title/icon/colorHex/context/tasks proxy the target)

Habit:     id, title, icon, colorHex, frequencyType("daily"|"daysOfWeek"|"timesPerWeek"|"monthly"),
           frequencyDaysRaw(JSON [Int]), targetCount, order, createdAt,
           reminderMinuteOfDay(Int?, minutes-from-midnight; nil = no daily reminder set)
           → context:Context?, goal:Goal?, completions:[HabitCompletion]?
           computed: frequencyDays (JSON get/set), currentStreak

HabitCompletion: id, date(yyyy-MM-dd), count, createdAt → habit:Habit?

Note:      id, kind("daily"|"weekly"|"permanent"|"list"|"meeting"), title, content, order,
           createdAt, updatedAt, dateKey(yyyy-MM-dd), weekKey(yyyy-Www), folderPath,
           calendarEventID, calendarID, eventDateKey, eventStartMin, eventEndMin,
           legacySourceKindRaw, legacySourceID
           → area:Area?, project:Project?, tags:[Tag]?
           computed: kind, displayTitle, sortedTags
           (the single live note model — `NoteKind.meeting` keeps its raw value because it is
            persisted; only its user-facing label reads "Event Notes")

SavedLink: id, title, url, order, createdAt → area:Area?, project:Project?

MarkdownImageAsset: id, data(external storage), mimeType, originalFilename, altText,
           pixelWidth, pixelHeight, displayWidth, createdAt, updatedAt

Legacy, migration-source only (no UI): DailyNote, WeeklyNote, PermNote, Document, EventNote
```

Non-`@Model` helper types that also live in `Cadence/Models/`: `TaskSectionConfig` /
`TaskSectionDefaults` (in `AppTask.swift`), `GoalContributionSummary` (+ resolvers for goal
progress and habit momentum), `HabitInsights` (streaks, heatmap, frequency summaries).

When accessing optional relationship arrays, always use `?? []`:
```swift
area.tasks ?? []
project.tasks ?? []
context.areas ?? []
```
When appending to optional relationship arrays:
```swift
area.tasks = (area.tasks ?? []) + [newTask]
```

## Design System (Shared/Theme.swift)

**No hardcoded colours anywhere.** Every colour comes from `Theme.*` or from a user-owned
`colorHex` (list / calendar / habit / tag / section). No `Color(hex:)` literals outside
`Theme.swift`, no bare `.white` / `.black` / `.gray` — `Theme` has named tokens for exactly the
jobs call sites keep re-inventing. This includes the `CadenceWidgets` target, which has
`Theme.swift` in its Sources phase so it can comply.

One fixed near-black dark palette. There is **no theme picker and no light variant** — the old
seven-theme `ThemeManager` was removed. `Theme.preferredColorScheme` is always `.dark`.

```swift
// Neutral ramp (~4% saturation near-black, so accents carry the colour instead of the chrome)
Theme.bg               = #09090b   // app background
Theme.surfaceRecessed  = #0d0d0f   // one step BELOW bg: inset wells, unchecked checkbox interiors
Theme.surface          = #131316   // cards/surfaces
Theme.surfaceHover     = #17171a   // hover lift for a surface resting at `surface`
Theme.surfaceElevated  = #1a1a1e   // elevated surfaces (inputs, sheets)
Theme.surfaceHighlight = #1f1f23   // hover/selection inside an already-elevated surface

// Borders
Theme.borderSubtle = #26262b   // card borders, dividers
Theme.border       = #2e2e34   // hairlines drawn at partial alpha
Theme.borderStrong = #3f3f46   // hovered cards, table delimiters, code fences
Theme.rule         = #52525b   // standalone horizontal rules

// Text
Theme.text    = #ededef   // primary
Theme.muted   = #a1a1aa   // secondary
Theme.subdued = #95959e   // label half of a label/value pair, annotating captions
Theme.dim     = #71717a   // genuinely de-emphasized / disabled

// Accents (+ derived `*Light` variants blended toward white)
Theme.blue / blueLight   = #4a9eff   // primary action; Theme.blueHex is the String form
Theme.red                = #ff6b6b
Theme.green / greenLight = #4ecb71
Theme.amber / amberLight = #ffa94d
Theme.purple             = #a78bfa
Theme.doneFill           = green     // completed completion-circle; priority stops showing once done
Theme.markerHighlight{Fill,Border,Text}   // ==highlight== pen; deliberately stays warm
Theme.appleSignInFill    = .black    // brand-mandated; must not be re-tinted

// Content drawn ON a saturated fill — use these instead of .white.opacity(...)
Theme.onColor, onColorSecondary, onColorTertiary
Theme.onColorBorder, onColorBorderStrong, onColorHandle, onColorHandleActive

// Overlays and shadows
Theme.scrim, selectionWash, subtleWash
Theme.chipShadow, sidePanelShadow, overlayCardShadow, cardElevationShadow

// Corner radius scale
Theme.radiusControl = 10   // icon badges, compact buttons, inline pickers
Theme.radiusCard    = 18   // stat tiles, card-shaped rows, kanban cards
Theme.radiusPanel   = 22   // page headers, sheets, popovers, modal shells

// Enums, NOT strings
Theme.priorityColor(_ priority: TaskPriority) -> Color
Theme.statusColor(_ status: TaskStatus) -> Color

// AppKit mirrors: same Color constants resolved to sRGB NSColor for the markdown editor's
// custom drawing. Add a bridge here rather than an NSColor(hex:) literal in editor code.
Theme.nsBg, nsSurface, nsSurfaceElevated, nsSurfaceRecessed, nsSurfaceHover, nsSurfaceHighlight,
Theme.nsBorderSubtle, nsBorder, nsBorderStrong, nsRule, nsText, nsMuted, nsDim,
Theme.nsBlue, nsRed, nsGreen, nsMarkerHighlight{Fill,Border,Text}

Color(hex: "#4a9eff")  // initializer exists for USER colorHex values — not for new palette literals
```

### Other standing UI rules
- **Page headers do not describe the page you are already on, and carry no identity tile.** The
  `subtitle` parameter was deleted; the `systemImage` parameter behind the leading glyph tile is
  now deleted too, on **both** platforms and every page — **the user's call**, and it reversed a
  plan to bring macOS *into line with* iOS's tile. A rounded glyph square at the top of Today
  saying "sun" is the subtitle's mistake one row up. It is deleted rather than left unrendered
  because a parameter that still compiles and draws nothing is exactly how `subtitle` survived
  long enough to need removing three separate times; `CadencePageHeaderMetrics.tileSize` and the
  `iconSize` derived from it went with it. `CommitmentIconTile` / `iOSIconTile` are untouched —
  tiles inside rows, cards and pickers are not page identity — and `tileGlyphRatio` /
  `tileFillOpacity` stay for them.
  What the tint now colours is the **count capsule**, and only that, which is what keeps a list's
  own `colorHex` on its own page. `iOSPageHeader` had been hardcoding `Theme.blue` there and
  ignoring the `color` it was handed; both headers read the tint now.
  Search result rows, empty states, and picker rows *keep* their subtitles — those say something
  the screen does not. Since `5aa11dc` there is one header view per platform —
  `DesktopPageHeader` and `iOSPageHeader` — and `PanelHeader`, `CommitmentPageHeader` and
  `CadenceSettingsHeader` are name-only wrappers over the first, not peers of it as this line
  used to imply. Account and metric ramp: `Cadence/Shared/AGENTS.md`.
- **One hover/selection layer at one radius.** If a row already has a `rowBackground`, do not
  add a second `.background()` on another layer at a different corner radius.
- **Prefer one shared component over near-copies.** The three kanban boards and the two estimate
  pickers each drifted apart before being unified.
- **iPhone and iPad share one style.** They differ in *layout* — tab bar vs sidebar, one pane vs
  two — and must not differ in how a row, chip, header or picker looks or behaves. A change
  requested on one platform applies to both unless it is genuinely shape-specific, and the default
  implementation is a single view parameterised by size class rather than a per-platform copy.

## Shared Utilities (Shared/DateFormatters.swift)
```swift
// Static date formatters — never create DateFormatter() inline
DateFormatters.ymd           // "yyyy-MM-dd" (storage format)
DateFormatters.longDate      // "EEEE, MMMM d"
DateFormatters.monthYear     // "MMMM yyyy"
DateFormatters.shortDate     // "MMM d"
DateFormatters.fullShortDate // "MMM d, yyyy"
DateFormatters.dayOfWeek     // "EEE"
DateFormatters.dayNumber     // "d"
DateFormatters.monthAbbrev   // "MMM"

DateFormatters.todayKey()              // -> String "yyyy-MM-dd" for today
DateFormatters.dateKey(from: Date)     // -> String "yyyy-MM-dd"
DateFormatters.date(from: String)      // -> Date?
DateFormatters.shortDateString(from:)  // "yyyy-MM-dd" string -> "Jan 15"

// Time formatting for minute-based scheduling
TimeFormatters.timeString(from: Int)                   // 75 -> "1:15 AM"
TimeFormatters.timeRange(startMin: Int, endMin: Int)   // "1:15 AM – 2:15 AM"
TimeFormatters.durationLabel(actual: Int, estimated: Int)  // "45/60m"
```

## Key Patterns
- `.preferredColorScheme(.dark)` set at root — always dark
- Avoid `navigationBarLeading`/`navigationBarTrailing` — use `.automatic` or `.primaryAction`
- Avoid `.keyboardType()` — iOS only
- `@Bindable` for editing SwiftData model properties directly in views
- All dates stored as `"yyyy-MM-dd"` strings (no timezone issues)
- Minutes from midnight (`scheduledStartMin`) for time scheduling; -1 = unscheduled
- `@Query` in views that need live sorted lists; child views receive models as `let` props
- Never instantiate `DateFormatter()` inline — always use `DateFormatters.*` statics
- Drag-to-reorder in **task lists** (InboxView, ListDetailView) uses `.draggable`/`.dropDestination` (SwiftUI Transferable API) with prefixed string payloads (NOT `.onMove` — it doesn't work on macOS sidebar or plain lists)
- Drag-to-reorder in the **sidebar** uses `.onDrag`/`.onDrop` with `DropDelegate` (NOT `.draggable`/`.dropDestination` — that API installs gesture recognizers that delay tap recognition across the whole ScrollView, breaking sidebar card button clicks). The dragged ID is stored in `SidebarDragContext.shared` (a plain class, not `@State`) so it survives SwiftUI view updates between `onDrag` and `performDrop`.
- Reorder and sidebar moves use `withAnimation(.spring(...))` so order changes animate smoothly.
- Non-kanban page scroll views can use `CadenceScrollElasticity` to soften vertical rubber-banding.

## Task lists: sort, group, and row UI
**Enums**: `TaskSortField` (date, priority, **custom**) and `TaskSortDirection` live in `Models/TaskOrdering.swift`, next to the comparator, because `CadenceWidgets` and `CadenceMCPServer` compile `Models/` but not `Shared/` or `macOS/`. `TaskGroupingMode` (by date, by list, by priority, **none**) stays in `macOS/Views/TasksPanelSupport.swift` — grouping is a macOS list concern with no comparator behind it. **Custom** sort uses the shared tie-break (`task.order`, then `createdAt`, `title`, `id`). **None** grouping shows a single flat section.

**One comparator: `TaskOrdering` (`Cadence/Models/TaskOrdering.swift`).** `nonisolated` throughout, because widget timeline providers run off the main actor. It owns `precedes(_:_:field:direction:)`, `completionPrecedes` (the completed/logbook ordering), `fallbackPrecedes` (the **total** tie-break: `order` → `createdAt` → `title` → `id`), and `noDateSortKey` — the one "sorts after every real date" sentinel. The tie-break must stay total: `order` is assigned per container, so cross-list surfaces routinely compare tasks with equal `order`, and a partial order there is an unstable sort that reshuffles rows between renders. `macOS/Views/TaskSortHelpers.swift` is now only the free-function spelling (`taskSortPrecedes`, `taskPriorityRank`) macOS call sites read better with.

iOS still has its own vocabulary — `CadenceTaskSortMode` + `CadenceTaskQuerySupport.sortTasks` in `Shared/` — with no sort **direction** (priority is always high-first) and a different case set (`.listOrder` / `.priority` / `.doDate` / `.dueDate` / `.newest`). That much is still unconsolidated.

**The tie-break is not.** This file used to add "and tie-breaks on `order` alone … the remaining half of the consolidation"; that was fixed in `6277539` and every one of `sortTasks`' five branches now ends in `TaskOrdering.fallbackPrecedes`. Do not pick this up as outstanding work and do not "fix" a comparator that `TaskOrderingTests` and `MobileTaskSortStabilityTests` already pin. (The doc comment above `CadenceTaskQuerySupport.sortTasks` carried the same stale sentence for longer than this file did, directly under a first line saying the opposite; it was corrected under T-151.)

**Where controls appear:** Today’s task column (`TasksPanel`), Inbox, All Tasks **list** mode, Area/Project **Tasks** tab, and All Tasks / list-detail **Kanban**. Two of those offer **sort only**: Kanban (columns stay section-based) and now **Today** (sections are the day's four intents — see "Today view task scope"). UI uses custom “picker badge” controls (not `Menu`), consistent with All Tasks. There is **no** global task **filter** UI (do date / list / priority filters were removed).

**Drag across groups:** Dropping a task into another group/section can update the relevant attribute (e.g. do date, list, priority, kanban section) and `order`.

**`MacTaskRow` (TasksPanelComponents.swift):** Container (area/project/inbox) uses pill styling; do/due dates are smaller, lower-contrast metadata (icons + text) with hover affordances, not pills. Due date badge only renders when `!task.dueDate.isEmpty` — no empty clickable badge. Overdue tasks can show red emphasis; “over-do” (past do date) is not amber-tinted on the row. Trailing metadata is the **estimate chip**, the focus button, the due-date badge, an optional bundle badge, and a `ContainerPickerBadge(compact: true, flat: true)` list chip. Priority strip height is slightly less than the row; the focus control sits beside the title when hovered.

**The estimate chip is new, and this passage used to say the opposite.** It read "the row has **no** estimate control" and described the trailing metadata as a deliberate omission, which is what kept the gap open through two row passes while `iOSTaskRow` carried one the whole time. **The user decided the iOS row wins**, so the chip crossed over: it renders only when `estimatedMinutes > 0`, labels itself through `CadenceTaskPresentationSupport.estimateLabel`, and opens the one shared `EstimatePickerPopoverContent`. The tag strip crossed the other way round — both rows had one, at two different caps — and now reads `CadenceTaskPresentationSupport.rowTagLimit` (3, iOS's figure; macOS's `ViewThatFits` already collapses the strip when the column is genuinely narrow).

`MacTaskRowEstimateChip` is its own `View` struct for the same reason `TaskCompletionButton` and `TaskRowBackground` are — see **Performance** below. It must not read `TaskCompletionAnimationManager`, and `CadenceTodayUnificationTests` fails if either it or `MacTaskRow` starts to.

`EstimatePickerPopoverContent` (Shared/Components) is **the** estimate picker on both platforms —
a two-column roller with preset chips above it. `TaskInspectorEstimateRollerPopover` is now a
typealias for it, so macOS's inspector chip, its kanban card, its note-embed field editor and every
iOS surface all open one control. It was two for a while, and `CLAUDE.md` recorded that split as
deliberate, which is how it survived; the note is here as a warning about that pattern rather than
as a description of a difference.

**Performance:** `MacTaskRow` does NOT read `TaskCompletionAnimationManager` directly. The completion button and animated background are extracted into `TaskCompletionButton` and `TaskRowBackground` sub-view structs, each with their own `@Environment(TaskCompletionAnimationManager.self)`. This scopes SwiftUI observation so only those small sub-views re-render on animation ticks — not every visible row.

**`ContainerPickerBadge` / `TaskSectionPickerBadge` (TasksPanelSupportViews.swift):** Both popovers open with a search bar auto-focused. Search filters by `hasPrefix` (case-insensitive). Navigation: ↑↓ arrows or `Enter` to select the highlighted item. The highlighted item is tracked by `highlightIdx` (index into `flatFiltered` / `filteredSections`), resets to 0 on query change or close. List name capped at 80pt (60 compact), section name at 70pt — both truncate with `…`. Rows use dedicated `ContainerPickerRow` (in `ContainerPickerSupportViews.swift`, not in this file) / `SectionPickerRow` View structs (not `@ViewBuilder` functions) with `let isHighlighted: Bool` for reliable in-place updates. Checkmark follows `isHighlighted`, so the rows deliberately carry **no** `isSelected` property. Hover + highlight share a single `rowBackground` computed property.

Both badges also take `breadcrumbSegment: Bool`. When set, the trigger renders as one segment of the task inspector's `List › Section` breadcrumb — icon + name (list) or bare name (section), no pill, no chevron, sized to its text — instead of a chip; the popover is identical either way. A breadcrumb segment takes the inspector's own hover layer (`InspectorPickerHover`, radius 5) rather than `cadencePlain`, whose radius-10 fill would draw a chip around text that is deliberately not one. The value always shows the **real** name (`Inbox` / `Default`) — dimmer styling is what conveys "unset", so the segment and its picker never disagree.

## Today view task scope
The Today **tasks** column only includes tasks that are **do today**, **due today**, **past do** (over-do), or **past due**, plus work tied to **sections due today**. A one-time **rollover** banner can appear when there are over-do tasks from the previous day; dismissing it merges those tasks into normal grouping.

Page-level filters should carry through to the page's internal sections. In practice, the Today **Completed** section only shows tasks whose `completedAt` is **today**.

When unfinished tasks are rolled from yesterday into today, Cadence clears their old timeline slot:
- `scheduledDate` is moved to today
- `scheduledStartMin` is reset to `-1`
- any linked timed calendar event is removed first

**Today groups by intent, on every platform.** The sections are `CadenceTodayTaskGroupKind`'s four — **Overdue**, **Past Do**, **Due Today**, **Planned Today** — plus **Completed Today**, each headed by the shared `CadenceTaskGroupHeading` (eyebrow in the group's accent, count capsule in the same). They come from `CadenceTaskQuerySupport.todayGroups`, the one function both platforms call.

This passage used to read "Today's by-list organization is now explicitly grouped by **context** rather than one flat stream of lists", which described macOS only: both iOS Todays had grouped by intent all along, so the same day read as an inventory on the desktop and as a plan on the phone. **The user decided iOS's vocabulary wins** — a section on the day's page should say *why* a task is in front of you, not where it lives. macOS's `todayListSections` and `todayDateSections` (the same four buckets under the names "Past Due" and "Do Today") are deleted, and Today no longer offers a **Group** picker at all: sort and order still apply, and they apply inside each group. All Tasks (`.byDoDate`) keeps its full grouping control.

Because the group header no longer names the list, macOS's Today rows are `.standard` rather than `.todayGrouped` — the list chip and the do-date pill are the only things left that can say where a task lives and when it was meant to be done, which is exactly what the iOS Today row already showed.

**The task column heads itself with the day, on every platform.** `TASKS / Today` became
`THURSDAY, AUGUST 20 · 1 done / Today [5]` — the date as the eyebrow, `CadenceTodaySummary.line`
as the `eyebrowDetail` beside it (the half that gives way when the column is squeezed), and the
day's open count in a capsule. macOS's `TasksPanelHeader` is `iPadTodayTaskHeader`'s row now, minus
the identity tile that neither platform draws any more. The empty day says
`CadenceTodayPresentationSupport.emptyTitle` / `emptySubtitle` on both.

**Pane structure stays per-size, deliberately.** macOS keeps three panes (notes │ tasks │ schedule),
iPad two (task column + switchable Notes/Timeline inspector), iPhone one column. Only what is
*inside* the panes is shared. Do not restore a Mac-shaped three-pane layout on iPad —
`Cadence/Shared/CadenceTodayLayoutSupport.swift` records that it and its picker were deleted at the
user's direction, and `CadenceTodayLayoutSupportTests` pins `layout(...)`'s range to `.compact` and
`.twoPane`.

**Layout:** `TodayView` uses an `HSplitView` with tuned `minWidth` / `idealWidth` / `layoutPriority` so notepad and schedule get more default space than the task column (user-adjustable dividers).

## Drag-to-Reorder Payload Prefixes
`Cadence/Shared/TaskDragPayload.swift` (`nonisolated`, cross-platform) owns the task and bundle
spellings and is the only place that parses them. The full set:
- `"listTask:\(id)"` — task rows in InboxView and ListDetailView (`.draggable`/`.dropDestination`)
- `"taskBundle:\(id)"` — `TaskBundle` blocks. `TaskDragPayload.taskID(from:)` deliberately returns `nil` for one rather than handing back a bundle id to a caller that asked for a task
- `"\(id)"` (plain UUID) — tasks dragged from TasksPanel onto the timeline; accepted by `taskID(from:)` as the unprefixed legacy form
- `"allDayEvent:\(eventIdentifier)"` — all-day event chips dragged from the calendar header onto a day column timeline
- `"area:\(id)"` / `"project:\(id)"` — sidebar rows, produced by `SidebarListDragItem.providerText` (`macOS/Views/SidebarComponents.swift`)

**The prefix is an enforcement mechanism for the first four and not for the sidebar.** This section
used to open "each drag context uses a unique prefix **to prevent cross-context drops**" and name a
`SidebarAreaDropDelegate` and a `SidebarProjectDropDelegate`. There is one delegate,
`SidebarListDropDelegate`, shared by both row kinds — and its `validateDrop` returns `true`
unconditionally while `performDrop` reads `SidebarDragContext.shared.draggedListItem`. It never
looks at the payload string at all; the provider text is carried and ignored. So a new sidebar drag
source cannot rely on its prefix to reject a foreign drop. Real prefix isolation is what
`TaskDragPayload`'s consumers get.

## Task Creation
There are exactly **four** creation affordances on macOS, and which one a surface gets is decided
by whether the surface already answers "where does this go":
1. **A floating circular `+`** on every task *page* — All Tasks (list mode), Inbox, and an
   area/project's Tasks tab (`FloatingNewTaskButton`, `.floatingNewTaskButton()`). It opens the full
   `CreateTaskSheet`. There is no "New task" header pill any more; `DesktopPrimaryActionButton` was
   deleted with it.
2. **A circular `+` in Today's task-column header** (`TasksPanelHeader`), which opens the same
   `CreateTaskSheet` seeded with today's do date. Today's task column is inside an `HSplitView` and
   has no floating `+` over it, so this is the same affordance in the only place it fits. This list
   said "three" while that button existed as a `+ New Task` pill — the last survivor of the header
   pills item 1 claims are gone — so both halves were wrong at once. It is a glyph now: at the
   column's 300pt minimum the pill's ~100pt truncated the header's own date eyebrow.
3. **A column ghost row** on every board column — kanban section columns, the All Tasks board's list
   columns, and the Calendar Board's day columns. It opens the **inline composer**
   (`InlineTaskComposer`), not the sheet. The Calendar Board's day column used to insert an
   untitled "New Task" card with no prompt; it does not any more.
4. **The calendar week tab's** drag-to-create task/event popover, unchanged.

The inline composer is **one** view for all those columns, parameterised by
`InlineTaskComposerSurface` (`.column(container:sectionName:)` / `.day(dateKey:startMin:)`).
`InlineTaskComposerSupport` owns the testable half — what a surface seeds, which chips it shows,
and how the draft resolves — and creation goes through `TaskCreationService` like every other path.
Chips reuse the existing pickers (`TaskTitleEntryField` with `~`/`#`/`!`, `ContainerPickerBadge`,
`TaskSectionPickerBadge`, `TaskDateChip`, `TagPickerControl`). Enter creates and leaves the composer
open for the next card; Escape closes it. `KanbanColumnAddBehavior` is what each column declares:
`.compose(surface)` or `.presentSheet` — the Calendar Board's Unscheduled rail is the only
`.presentSheet` caller, because a backlog has neither a day nor a list to seed.

`TaskCreationManager` is an `@Observable` singleton (`TaskCreationManager.shared`) injected via `.environment`. Call `taskCreationManager.present(...)` with optional seed values (title, notes, dueDateKey, doDateKey, priority, container, sectionName) to show `CreateTaskSheet`.

The same shared sheet is used for:
- page-level creation (the floating `+`)
- the Calendar Board's Unscheduled rail
- the system-wide quick task panel (`QuickTaskPanelController`)

`CreateTaskSheet` behavior:
- Title field autofocuses on open; `Cmd+Return` creates the task
- Layout: full-width content area, chip strip at bottom: `[List] [Section?] ─── [Do Date] [Due Date] [Priority]`
- No estimate button; notes field is compact (height 40)
- Do date does **not** default to today — only pre-set if `doDateKey` is provided in the seed
- Priority chip displays short labels: **N/A / L / M / H**; picker still shows full names
- List + section can be preseeded; section picker normalizes to available sections on container change
- On success the sheet **closes immediately**; feedback is a brief global **”Task created”** toast — when closing the quick-capture panel, `presentSuccessToast()` is called after a 250ms delay so the panel fully dismisses first, then activates the main app window to make the toast visible

**Sheet-local keyboard shortcuts** (active whenever the sheet window is focused):
- `Cmd+T` — set do date to today (or cancel if already today)
- `Cmd+Shift+T` — open do date picker
- `Cmd+D` — set due date to today (or cancel if already today)
- `Cmd+Shift+D` — open due date picker
- `Cmd+P` — cycle priority (none → low → medium → high → none)
- `Cmd+Shift+=` / `Cmd+Shift+-` — nudge do date ±1 day (sets to today first if unset); **while tilde panel is open**, these cycle the highlighted list/section item instead

**Inline title shortcuts — `TaskTitleEntryField` (Views/TaskTitleEntryField.swift):**

This is now a **shared field**, not `CreateTaskSheet`-local logic. Both `CreateTaskSheet` and the
task inspector header (`SchedulePanelPopoverSupportViews.TaskDetailHeaderSection`) use it, so
behavior changes land on both. The marker parsing lives in `Shared/TaskTitleSupport.swift`.

Three triggers:
- **`~` — list.** Typing `~` at the start of the title or right after a space opens a list-search popover anchored at the `~` badge. Selecting a list sets the container, normalizes the section to one the new container actually has (`normalizeSelectedSection()` — silent, no UI), clears the query and returns focus to the title. **There is no second step.** This file previously described `~` as "list, **then** section", with the section picker opening at the same spot with "Default" pre-highlighted, and named `TildeSectionPickerRow` and `TildeSectionSearchPanel` as the types behind it. Neither type has ever existed (zero hits repo-wide) and `TaskTitleTildeMode` has exactly two cases, `.none` and `.list`. Section is chosen from the chip strip's `TaskSectionPickerBadge`, not from the title field.
- **`#` — tags.** Same trailing-marker mechanic, backed by `TaskTitleInlineTagPicker`; can create a tag inline.
- **`!` / `!!` / `!!!` — priority** (low / medium / high), leading or trailing. Rendered as a preview marker and stripped from the saved title.

Shared behavior for the popovers:
- The marker is consumed from the title while the panel is open; a highlighted badge replaces it visually in the title row
- Navigate with ↑↓ arrows or `Cmd+Shift+=/−`; `Enter` selects the highlighted item
- `Tab` closes the panel and puts the marker back in the title, returning focus there
- **Title ZStack pattern:** The `TextField` is always in the hierarchy (never removed) — hidden with `opacity(0)` + `allowsHitTesting(false)` when a shortcut panel is active. Removing and re-inserting an `NSTextField` causes macOS to select-all on re-focus. A ZStack overlay shows the title text plus the marker badge, with `.popover` attached to the badge.
- **Picker row structs:** `TildeContainerPickerRow` (`macOS/Sheets/CreateTaskSheetSupportViews.swift`, used by both `TaskTitleEntryField` and `QuickCreateChoicePopover`) and `InlineTagPickerRow` are dedicated `View` structs with `let isHighlighted: Bool` props (not `@ViewBuilder` functions). Hover and highlight backgrounds are consolidated into a single `rowBackground` computed property inside the Button label — never two separate `.background()` modifiers on different layers.
- **Popover search focus is deferred, not immediate.** Every one of these panels ends in
  `onAppear { clamp…(); DispatchQueue.main.async { isSearchFocused = true } }`. Setting the
  `@FocusState` synchronously in `onAppear` lands before the popover window is key and does
  nothing. The hop is the whole mechanism — keep it on any new panel.
  This file used to justify that with "macOS popovers are separate `NSWindow` instances, so parent
  `@FocusState` cannot reliably capture `.onKeyPress` inside the popover", and used it to explain a
  `TildeSectionSearchPanel` that does not exist. Both halves were wrong: the `~` list panel is a
  computed `some View` on `TaskTitleEntryField` bound to the **parent's** `@FocusState`
  (`isTildeSearchFocused`) and handles ↑↓/Tab/Escape/Delete `.onKeyPress` fine. A standalone struct
  with its own `@FocusState` (`TaskTitleInlineTagPicker`) is a fine choice, but it is not required.
- **ForEach identity:** Use `ForEach(Array(items.enumerated()), id: \.element.id)` with `Identifiable` items — never `ForEach(indices, id: \.self)`. Integer IDs cause SwiftUI to reuse the same view for different rows, breaking highlight state. Never put `.id(highlightIdx)` on a container VStack — it destroys/recreates the whole list on each arrow press, briefly showing double highlights.

**Timeline / calendar drag-create quick popover (`macOS/Views/QuickCreateChoicePopover.swift`):**
- The drag-to-create title popover for new scheduled tasks/events supports the same `~` list-search flow — and supports it by **near-duplicating** it: `tildeFlatContainers` / `selectTildeContainer` / `selectTildeContainerItem` are a second copy of `TaskTitleEntryField`'s, sharing only `TildeContainerPickerRow`. That is a standing violation of the "one shared component over near-copies" rule, recorded here so it is not mistaken for a deliberate split
- Selecting a list sets the container and normalizes the section silently, exactly as in `TaskTitleEntryField`. There is no section-selection step here either
- New scheduled tasks can now be created directly into the chosen list/section via `SchedulingActions.createTask(... containerSelection: sectionName: ...)`
- While dragging out a new time range, the ghost preview shows **start**, **end**, and **duration**

## Notes / Markdown

> **Under active rewrite.** The macOS Notes UI (`NotesView`, `NoteEditorPane`, `NotesListRows`,
> `NoteEditorAccessoryViews`, `AIActionsSupportViews`, `NotesListVisibilitySupport`, the markdown
> editor files, and `NoteMigrationService`) is being reworked. The points below were verified
> against `HEAD` — read the files before trusting any detail of the list/editor chrome.

- One live model: `Note`, with `NoteKind` = daily / weekly / permanent / list / meeting. The macOS Notes page has four tabs: **Daily**, **Weekly**, **Notepad** (permanent), **Event Notes** (`.meeting` — the case name is persisted in `Note.kindRaw`, so only the *label* was renamed).
- `NoteMigrationService` folds the legacy `DailyNote` / `WeeklyNote` / `PermNote` / `Document` / `EventNote` rows into `Note`, recording provenance in `legacySourceKindRaw` / `legacySourceID`.
- Notes carry `tags`, an `area`/`project`, and a `folderPath`.
- **All markdown logic lives in `Cadence/Services/Markdown*Support.swift`** (27 files, well covered by `CadenceTests/`). `macOS/Editor/` is only the AppKit bridge — and since T-121 the *iOS* styler is only the UIKit one. `iOSMarkdownStyler` was one 1,067-line file that made its own decisions about heading-marker visibility, block extents, inline exclusions, hidden marker runs and table grouping; it is now four files of pure attribute-setting over `MarkdownStyleRanges`, `MarkdownInlineMarkerRanges`, `MarkdownTableParser.tableBlock` and `MarkdownStyleSignature`. See `Cadence/iOS/AGENTS.md` for the per-file split.
- Notes support both Markdown export and rendered PDF export (`NoteExportService`)
- The notes export flow avoids direct blocking `NSSavePanel.runModal()` usage
- Notes can surface linked notes, backlinks, and embedded task references above the editor
- Wiki-style note links are supported with `[[Note Title]]`
- Task references support both `[[task:Task Title]]` and ID-backed `[[task:UUID|Task Title]]`
- Typing `/` in the editor opens a compact live slash-command picker at the insertion caret
- Slash commands cover common transforms like headings, todo/done, quote, rule, link, and task inserts
- Hidden markdown markers are skipped by caret traversal instead of behaving like visible cursor stops

## Recurrence
- `TaskRecurrenceRule`: none / daily / weekly / monthly / yearly
- **End conditions** (`TaskRecurrenceEndMode`): `never`, `onDate` (`recurrenceEndDate`), `afterCount` (`recurrenceEndCount`, counted against `recurrenceOccurrenceIndex`)
- **Edit scope** (`TaskRecurrenceEditScope`): `thisTask` vs `thisAndFuture`. This used to be a system `confirmationDialog` raised after every edit; it is now an inline **"APPLY TO"** row at the top of the recurrence picker panel (`TaskInspectorWorkflowSupportViews.swift`), so the choice is made before the edit rather than defended after it.
- Occurrences are tied together by `recurrenceSeriesIDRaw` / `recurrenceSourceTaskIDRaw`; completing one spawns the next through `TaskWorkflowService`
- If a recurring task is scheduled, the next occurrence continues through the normal scheduling path

## Task Inspector
The shared task inspector (opened from timeline blocks, calendar board cards, and task rows) is
composed from `SchedulePanelPopoverSupportViews` (stateful wrapper + header/schedule sections and
the placement breadcrumb) plus `TaskInspector*SupportViews` (field-row primitives, content
sections, recurrence). Current shape, top to bottom: title row, tags, breadcrumb, SCHEDULE,
SUBTASKS, NOTES, action buttons.
- **The header tile *is* the priority control.** It used to be a decorative container glyph with a duplicate priority control on the right — two affordances for one field. Tapping the tile opens `TaskPriorityPickerPopover`.
- **Estimate is a chip at the trailing edge of the title row** (`TaskInspectorEstimateChip`), not a row in the SCHEDULE well — an estimate is a property of the task like its priority, not a date. It is `fixedSize`, so a long title wraps instead of squeezing it, and non-focusable, so clicking it cannot pull the caret out of a title being edited. Same **two-column roller** popover, which is now literally `EstimatePickerPopoverContent` — one picker, both platforms.
- **Tags sit directly under the title**, indented to the title column, as a chip strip with a `+`. They are `task.tags` and always were — they previously sat under a heading reading NOTES, which implied tagging a task also tagged a note. (`AppTask.notes` is a `String`; there is no note object to tag.)
- **Placement is one breadcrumb line** under the tags — `China › Documents` (`TaskDetailPlacementBreadcrumb`), replacing a "PLACEMENT" well with a List row and a Section row. Each segment opens its full picker. The section segment is omitted when the container has nothing to choose between — an Inbox task reads simply `Inbox`.
- **No "Actual" row.** Logged time is measured, not typed; the focus timer accumulates it.
- Repeat is an inline row + picker panel, not a dialog (see Recurrence above).
- The Mark done / Unschedule / delete buttons carry **no group heading** — a label over two buttons at the foot of the panel names what the buttons already say.

## Calendar / Events
- The Calendar page has two **presentations** (`CadenceCalendarPresentation`): **Timeline** and **Board**. Timeline has Week / 2 Weeks / Month view modes (`CadenceCalendarViewMode`; the picker exposes Week and Month).
- **Board** is what the Planning page became — horizontally scrolling day columns flanked by two pinned rails, **Overdue** and **Unscheduled**. Planning's other three buckets (Today / This Week / Later) *are* day columns here, so they needed no equivalent; its bucketing, drag-to-reschedule, drag-back-to-unscheduled, and "N unscheduled · N overdue" summary all live on this surface now. Files: `CalendarPageBoardSupportViews`, `CalendarBoardDayColumnSupportViews`, `CalendarBoardRailSupportViews`, `CalendarBoardItemSupportViews`, plus `Shared/CadenceCalendarPlanningSupport.swift` (rails, drop targets, `CalendarBoardPlannerSupport`).
- The Board reuses the kanban `KanbanCard` / `BoardColumnHeader` / `KanbanColumnScroll` components. Parameterize them; do not fork.
- **Tasks cannot be attached to calendar events.** `AppTask.calendarEventID` exists and is still
  read, but **nothing writes it a non-empty value** — every write site clears it
  (`SchedulingService` ×7, `CalendarLinkedTaskSupport`), and no attach UI exists on either
  platform. The readers are deliberate and must stay: they clear stale identifiers
  (`CalendarLinkedTaskSupport`), delete a linked event when its task is deleted
  (`TaskDeleteHelpers`), and repair relationships (`DataIntegrityRepairService`) — all for values
  written by an earlier build that may still be on disk or in CloudKit. The field is a stored
  SwiftData property and there is no `SchemaMigrationPlan`, so removing it would drop data rather
  than clean anything up. Restoring the feature means building an event picker and deciding the
  two-way sync semantics; it is not a matter of re-adding one assignment.
- Calendar events can have linked notes; reopening the same event reopens the same linked note instead of creating duplicates
- Timeline/today schedule export uses SwiftUI-native exporter flow rather than manual AppKit save panels
- `CalendarVisibilityPreferences` controls which EventKit calendars render; `CalendarWorkHoursPreferences` sets the work-hours window the timeline emphasizes

## Tags
`Tag` (slug, name, desc, colorHex, order, isArchived) is many-to-many with both `AppTask` and
`Note`. Entry points: the `#` inline shortcut in `TaskTitleEntryField`, `TagPickerPopoverViews` /
`TagPickerSupportViews` on macOS, and a **Tags** category in Settings (`SettingsTagsSection`,
plus `iOSSettingsTagsSection`). Shared logic is in `Cadence/Services/TagSupport.swift`.

## Task Bundles
`TaskBundle` groups several tasks into a single timeline block (`dateKey`, `startMin`,
`durationMinutes`). The `tasks` relationship uses a `.nullify` delete rule — deleting a bundle
must not delete its tasks. Rendered by `TimelineBundleBlock*`; pickable in Focus
(`FocusBundleTaskSupportViews`) and assignable via `TaskBundlePickerSupportViews`.

## AI Actions
Optional and off by default. `Cadence/Services/AI/` holds `AIProvider` (user-supplied OpenAI API
key, stored via `AISettingsManager`) and `AIActionService`, which runs note-scoped actions and can
propose task drafts. Drafts go through a review sheet (`NoteActionReviewSheets`,
`AIActionsSupportViews`) before anything is written. Never log the key or persist request bodies.

## Templates
`NoteTemplate` / `NoteTemplateOverride` / `NoteTemplateLibrary` live in
`Cadence/Services/MarkdownNoteSupport.swift`. Templates are per-`NoteKind`, built-in but
user-editable — edits are stored as overrides in a single `@AppStorage` blob and can be reset.
Managed from Settings → Templates (`SettingsTemplatesSection`,
`iOSSettingsTemplateAndListSections`); applied from the note editor accessory strip.

## Apple Reminders
Separate from Calendar and separately authorized. `RemindersManager`
(`Cadence/Services/CadenceRemindersManager.swift` — prefixed file, unprefixed type;
`@Observable` singleton, **cross-platform**) reads
EventKit reminders and exposes them through the Settings → **Reminders** category —
`SettingsRemindersSection` on macOS, `iOSRemindersSettingsSection` on iOS. The pure
authorization-state and list-summary logic both read is
`Shared/CadenceRemindersPresentationSupport.swift` (`RemindersConnectionState`,
`RemindersSyncSummary`). Cadence must keep working when reminders access is not granted, and
when it is granted and later revoked while a page is open — both sections re-derive in
`.onAppear`.

This manager lived in `macOS/Services/` behind an `#if os(macOS)` for a long time despite
touching no AppKit, and `iOSSettingsCategory` classified `.reminders` as "a macOS-shell concern",
which is what kept Apple Reminders unreachable from iOS Settings. **macOS also surfaces reminders
in its Inbox (`InboxView`), and **iOS does too** since `d330f5e` —
`iOSInboxRemindersSection` is rendered from `iOSTaskCollectionPage` under the Inbox scope, gated on
the same tested `CadenceTasksPageScope.showsRemindersStrip` and drawing its tints from the same
`AppleReminderRowPresentation` macOS reads. This line said the gap was "real and still open" for
some time after it was closed, which is worth more than the correction: the section had a dedicated
call-site test (`CadenceInboxRemindersSurfaceTests`) the whole time, so the code was pinned and the
prose was not. Trust the test, not this file.

## Account, Privacy, and Data Safety
- **Sign in with Apple** is optional and entitlement-gated (`AppleAccountManager`); Settings → Account.
- **Privacy data reset** (`PrivacyDataResetService`, in `Services/CadencePrivacyDataResetService.swift`, **cross-platform**) wipes every model — including the legacy note types and `Pursuit` — and cancels pending Cadence notifications. Add new `@Model` types here whenever you add them to the schema, or a reset leaves orphans; `CadencePrivacyDataResetSurfaceTests` drives that check off `CadenceSchema`, so an omission fails the suite rather than waiting to be noticed.
  `deleteCadenceDataAndLocalArtifacts` is the full sweep **both** platforms run — store, OpenAI key, widget snapshot, pending restore, local backups — and returns `PrivacyDataResetOutcome`, whose `statusMessage` is the one sentence both surfaces show. Neither view may re-spell the sequence.
  **macOS**: Settings → Account or Settings → Data Safety, gated by a window-modal `confirmationDialog` that enumerates what goes. It additionally calls `AppleAccountManager.signOut()`, which is macOS-only.
  **iOS/iPadOS**: Settings → Data Safety (`iOSDataResetSettingsSection`). The card's button only *presents*; the destructive control lives in a modal sheet and stays disabled until `PrivacyDataResetConfirmation.authorizes(_:)` accepts the typed phrase (`DELETE`). The mechanism differs from macOS on purpose — a mobile `confirmationDialog` is a bottom action sheet, i.e. one thumb-reachable tap — and the *bar* is the same or higher. There is no Account category on iOS, so there is no account profile to clear, and the copy does not claim one.
  This service lived under `macOS/Services/` behind an `#if os(macOS)` it never needed, which is why `docs/privacy.html` and `docs/app-review-notes.md` shipped promising iOS a deletion route that did not exist. Both documents now state the routes per platform.
- `DataIntegrityRepairService` is the conservative, idempotent repair pass for stale relationships.
- `docs/privacy.html` and `docs/app-review-notes.md` are the shipped privacy/App Review material.

## MCP Surface
Two halves of one boundary. **`CadenceMCPServer/AGENTS.md` is the canonical account** — what
follows is the map, not the rules.
- `Cadence/Services/MCPReadOnly/` — `CadenceReadService` / `CadenceWriteService`, DTOs, search matcher, audit log, standalone model-container factory. Compiled into **both** the app and the server target; covered by `CadenceTests` (`CadenceReadServiceTests`, `CadenceWriteServiceTests`, `CadenceSearchMatcherTests`).
- `CadenceMCPServer/` (native server target: `main.swift`, tool definitions, router, argument parsing) and `plugins/cadence-mcp/` (plugin wrapper + `smoke-test.py`). **Nothing in either has unit coverage** — the smoke test is the only thing exercising the router.
`CadenceMCPRefreshCoordinator` (macOS Services) watches a marker file so the app reloads after an
external write.

This section used to open "do not touch them unless the task explicitly asks for MCP work", and
four other guides said the same. It was wrong, and the correction is a **procedure**: when model or
shared-service code changes, review the boundary — build `CadenceMCPServer` on **its own** scheme
into a private `-derivedDataPath` and grep the log, because that target compiles a hand-picked
subset of app source under different concurrency settings (Swift 6, no
`SWIFT_DEFAULT_ACTOR_ISOLATION`), so the `Cadence` scheme stays green while it breaks. Skipping the
boundary yields a broken target or a silently stale response schema, and the write path — gated on
`CADENCE_MCP_ENABLE_WRITES`, off by default — mutates the real app-group store from a second
process with no UI and no undo.

## Keyboard Shortcuts (macOSRootView)
Global local monitor unless noted. **Hovered task date nudge** requires the pointer over a **do** or **due** control (`HoveredTaskManager.hoveredDateKind`).

- **Cmd+Delete** — delete hovered task/editable (custom confirmation overlay)
- **Cmd+E** — open edit sheet for hovered task **or** hovered kanban **section** header
- **Cmd+T / Cmd+Shift+T** — set Do Today / open Do Date overlay for hovered task
- **Cmd+D / Cmd+Shift+D** — set Due Today / open Due Date overlay for hovered task
- **Cmd+Shift+Plus / Cmd+Shift+Minus** — nudge hovered do or due date by one calendar day (forward / back)
- **Cmd+P** — cycle hovered task priority (`none → low → medium → high → none`)
- **Cmd+Return** — toggle completion for hovered task; also creates a task in `CreateTaskSheet`
- **Cmd+/** — toggle cancellation for hovered task (same cancel/undo-cancel behavior and animations)
- **Cmd+N** — open the inline composer in the hovered kanban column (same composer its ghost row opens, not the sheet)
- **Cmd+K** — open the global command palette / search overlay
- **Cmd+O** — toggle **main** sidebar visibility (also a floating control; works in Focus mode)
- **Cmd+S** — for a hovered task, open a focused **subtasks-only** popover with the subtask field ready for typing
- **Cmd+\\** — outside Today, toggle the **right** timeline sidebar; on Today, focus and highlight the built-in timeline pane instead
- **Cmd+Z / Cmd+Shift+Z** — undo / redo; routes to SwiftData `UndoManager` **unless** an `NSTextView` or `NSTextField` is first responder, in which case the event is passed through so the text view's own undo stack handles it (covers markdown editors and notepads)

**List detail (Area/Project):** **Cmd+Shift+[ / ]** cycles tabs (Tasks, Kanban, Notes, Links, Completed) — implemented in `ListDetailView`; it does not conflict with date nudge (different chords).

## Hovered date overlay (`HoveredTaskDatePickerOverlay` in macOSRootView)
`Cmd+Shift+T` / `Cmd+Shift+D` shows an overlay with **`MonthCalendarPanel` embedded inline** (no extra click to open the calendar). Clear / Cancel / Apply use full hit targets (`contentShape`, minimum sizes).

## Global Search / Command Palette
- Triggered with **Cmd+K**
- Spotlight-style centered overlay with grouped results and arrow-key navigation
- Searches pages (including hidden sidebar tabs), contexts/areas/projects, tasks, calendar events, goals, and habits
- Includes a **Commands** section with app actions like `New Task`, `Focus`, `Today`, `All Tasks`, `Calendar`, and `Settings`
- Matching is token/prefix-weighted rather than loose substring-only search
- Selecting an area/project/task/event navigates directly to the relevant destination

## List Lifecycle
- Areas and projects can be **completed**, **archived**, or **deleted**
- Active lists appear in the sidebar; completed/archived lists are hidden from the active sidebar but remain searchable
- Lifecycle actions live in the edit sheets (`EditAreaSheet`, `EditProjectSheet`)
- A dedicated **Lists** category in Settings shows all completed and archived areas/projects with reopen / unarchive / delete actions
- Deleting a list recursively deletes its tasks, documents, links, and any nested projects in the case of an area

## Timeline / Scheduling Architecture
The scheduling UI is shared between `SchedulePanel` (today's view) and `CalendarPageView` (multi-day). Both use `TimelineDayCanvas` as the rendering and interaction engine.

The timeline/calendar stack is intentionally decomposed into a shell + support-file architecture:
- `TimelineMetrics.swift` — pixel↔minute math, snapping, `TimelineBlockFrame`, `computeTimelineBlockFrame()`
- `TimelineDayCanvas.swift` — main canvas state/orchestration: drag-to-create ghost, drop zone, selection/draft state
- `TimelineTaskBlock.swift` — draggable task block, tap-to-select, detail popover, within-canvas drag
- `TimelineEventBlock.swift` — read-only calendar event block
- `TimelineBundleBlock.swift` — `TaskBundle` block (several tasks in one slot)
- support files under `Views/` now carry overlay layers, shell composition, state helpers, and calendar viewport helpers
- the Calendar **Board** presentation does not use `TimelineDayCanvas` at all — it is a column/card surface built on the shared kanban components

Scheduling actions are in `SchedulingService.swift` (`SchedulingActions.createTask`, `SchedulingActions.dropTask`). `createTask` also has a container-aware overload used by drag-created scheduled tasks from the timeline/calendar quick popover.

**Coordinate rule:** Visual blocks and interactive hit targets must both use `.position(x:y:)` from the same `blockX/blockY` values. Never mix `.offset()` and `.padding()` for positioning in the same layer.

## What's Built (macOS)
- [x] Fully custom sidebar: **one labelled column**, top to bottom — app header, primary nav, lists, secondary nav, settings. There is no icon rail and no separate lists panel. **Only the lists region scrolls**; the two nav groups and the header are pinned, so a long list collection cannot push Settings below the fold. Nested context grouping, hover states, drag-to-reorder, active-only list visibility; **project due date** on list rows (red flag, clickable) replaces the old area/project type label where applicable
- [x] Today view: note + **scoped** task list + schedule; optional **right** timeline (**Cmd+\\**); sort/group like other lists
- [x] Row-based task lists with collapsible grouping and completed/logbook sections
- [x] Today task view grouped by list in sidebar order, with Inbox pinned first; overdue / over-do / rollover UX
- [x] Today completed section scoped to tasks completed today
- [x] All Tasks: **list** vs **kanban** modes; shared sort UI; list has grouping, kanban **sort only** (no grouping)
- [x] Inbox: unassigned tasks, capture bar, drag-to-reorder, sort/group controls
- [x] Full task creation sheet (title, notes, due date, do date, priority, container, section, subtasks); shared `TaskTitleEntryField` with inline `~` list search, `#` tags, and `!`/`!!`/`!!!` priority — the same field the task inspector header uses
- [x] Global hotkey to open task creation from anywhere in the OS
- [x] In-app Spotlight-style command palette / global search (`Cmd+K`)
- [x] Custom delete confirmation overlay
- [x] Hover-driven task shortcuts for edit/delete/do/due/priority/completion
- [x] Hover-driven subtask-entry shortcut (`Cmd+S`) that opens a subtasks-only popover
- [x] Drag-to-schedule tasks from task list to timeline
- [x] Timeline drag-to-create new tasks
- [x] Drag-created timeline/calendar previews show start, end, and duration live while dragging
- [x] Timeline drag-to-reposition existing tasks (with grab-offset preserved)
- [x] Unscheduled task drop preview on timeline (shows block before release)
- [x] Calendar page: **Timeline** presentation (Week / 2-Week / Month, infinite scroll) and **Board** presentation
- [x] **Calendar Board** — horizontally scrolling day columns with pinned **Overdue** and **Unscheduled** rails. This absorbed the deleted Planning page *and* the deleted per-list Planning tab: bucketing, drag-to-reschedule, drag-back-to-unscheduled, and the "N unscheduled · N overdue" summary all live here
- [x] Month view: header-sync race conditions and window-boundary clamping fixed (shared `CalendarMonthGridMetrics`, settle-delay-guarded scroll sync in `CalendarMonthGridInteractionSupport`)
- [x] Remembered scroll position for Today timeline and calendar
- [x] Goals view: Gantt-style timeline, 2W/Month/Quarter/Year/5Y scales; top-level goals (directions) with nested sub-goals as their milestones. The sidebar label for this surface is **Goals** (it was "Milestones" before `Pursuit` was merged into `Goal`).
- [x] Habits: list, detail, 52-week heatmap, streak tracking, create sheet
- [x] Notes page with four tabs — Daily, Weekly, Notepad, Event Notes — all backed by the one `Note` model, with Markdown export and rendered PDF export
- [x] One-time migration of legacy `DailyNote` / `WeeklyNote` / `PermNote` / `Document` / `EventNote` rows into `Note` (`NoteMigrationService`)
- [x] AI note actions behind a user-supplied OpenAI key, with a review sheet before any task draft is written
- [x] Note templates, managed in Settings and applied from the note editor
- [x] Shared markdown editor supports headings, block quotes (`>`), dividers (`---`, `***`, `___`), hidden markdown markers, ordered/unordered lists, slash commands, wiki-links, task references, and 5 nesting levels
- [x] Markdown caret movement skips hidden formatting markers rather than traversing invisible syntax
- [x] Markdown list indentation is reduced/tighter than the original editor implementation
- [x] New notes start with the note title as the first markdown heading; editing the H1 in the body syncs back to `note.title`
- [x] Notes: each selected note gets its own `NSTextView` instance (`.id(note.id)`) so undo history is isolated per note
- [x] Cmd+Z / Cmd+Shift+Z undo/redo works inside markdown editors and notepads (passes through to NSTextView's own undo stack when text field is focused)
- [x] Slash command picker opens at the insertion caret inside notes
- [x] Focus timer with log session popover (logs actual minutes, propagates to goals/areas/projects)
- [x] Area/Project detail: Tasks, Kanban, Notes, Links, Completed (`ListDetailPage`). **Planning is deleted** — `ListDetailPage.resolved(_:)` maps a persisted "Planning" value back to `.tasks` so the Settings default-page picker never lands empty
- [x] Recurring tasks: end conditions (never / on date / after N) and a `thisTask` vs `thisAndFuture` edit scope shown as an inline "APPLY TO" row rather than a system dialog
- [x] Linked notes for calendar events
- [x] Area/Project lifecycle: complete, archive, delete; completed/archived lists recoverable from Settings
- [x] Section-based kanban with editable/reorderable/archiveable columns (Cmd+E on section header; autosave section editor)
- [x] Per-list **hide column due date when empty** (`hideSectionDueDateIfEmpty` on Area/Project; create/edit list sheets)
- [x] Section-level due dates and completion
- [x] Sections due today surfaced in Today view
- [x] Apple Calendar sync (EventKit): create, update, delete, observe; event editor can **move event to another calendar**
- [x] Calendar week/2W view: all-day banner shows all-day events + unscheduled tasks as draggable chips; chips are scrollable and clickable (opens task inspector); dragging a chip onto a day column schedules it at the dropped time
- [x] Apple Reminders (EventKit reminders, separately authorized) surfaced through Settings → Reminders and the Inbox
- [x] Tags on tasks and notes, with inline `#` entry and a Settings category
- [x] Task bundles: several tasks grouped into one timeline block
- [x] Optional Sign in with Apple; privacy data reset that wipes every model
- [x] Per-calendar visibility preferences and a configurable work-hours window
- [x] Read-only/read-write MCP surface (`Services/MCPReadOnly/`, `CadenceMCPServer/`, `plugins/cadence-mcp/`)
- [x] CloudKit sync
- [x] Category-based Settings shell with **twelve** categories: Navigation, Sidebar, Templates, Contexts, Lists, Tags, Calendar, Reminders, Notifications, AI, Data Safety, Account
- [x] **One fixed dark palette.** There is no theme picker — `ThemeManager` and its seven light/dark themes were removed. `Theme.swift` is also compiled into the `CadenceWidgets` target so widgets carry no hardcoded colours
- [x] Local notification scheduling (iOS + macOS): task scheduled-start and due-date reminders, plus daily habit reminders (`Habit.reminderMinuteOfDay`). Excludes Apple Calendar/EventKit events (those already have native OS alarms). See "Notifications" below for the reconciliation-based design — this is **not** an imperative schedule-on-every-mutation system, so don't assume every task/habit mutation site needs an explicit notification hook.
- [x] Widget extensions (`CadenceWidgets` target): calendar/today/habit/milestone widgets with app-intent support and a refresh checkpoint (`CadenceWidgetRefreshCenter`) triggered on scenePhase changes — not documented further here yet; check `Cadence/Services/Cadence*WidgetSupport.swift` and `CadenceWidgets/` directly

## What's Built (iOS)
`Cadence/iOS/` is a large, actively-developed surface (86 files), not a stub. Adaptive root shell (`iOSRootView.swift`) — full sidebar shell on iPad regular width (`iPadMacStyleRootShell`), **four-tab bottom bar** on compact width (`iOSCompactRootShell`) — covering:
- [x] **iPhone tab bar**: `[ Tasks ] [ Calendar ] ( + ) [ Notes ] [ More ]`. The centre `+` is **not a tab** — it presents task capture and never renders a selected state. Each tab owns its own type-erased `NavigationPath`, so switching tabs preserves position; the selected tab and Tasks segment persist across launches (`ios.compact.selectedTab`, `ios.compact.tasksSection`). Replaced `iOSCompactHomeView`, a grid of eight tiles that was standing in for navigation the app did not have.
- [x] Tasks tab (`iOSTasksTabView`): date eyebrow + greeting, a **Today / All / Inbox** segmented switcher (the same control Calendar uses for Week/Month/Board), and a search shortcut
- [x] Today (`iPadTodayView` + compact/schedule/support variants). The compact Today has **no capture bar of its own** — the tab bar's `+` is the capture affordance
- [x] Tasks (task rows/detail, All Tasks compact view, Inbox) — both keep their own inline capture bars
- [x] Calendar (EventKit-backed via `iOSCalendarManager`): board view, month/timeline views, event edit/quick-create sheets, inspector
- [x] Focus timer
- [x] Goals (top-level directions plus their nested milestones)
- [x] Habits
- [x] Notes with its own markdown editor stack (styling, preview, slash commands, task/wiki references)
- [x] Lists (Area/Project detail, editors)
- [x] Search
- [x] Settings (overview, contexts, tags, templates + lists, calendar, notifications, reminders, **data safety** — including the account-and-data delete action the shipped privacy policy promises, behind a typed-phrase confirmation sheet). Reminders appears in **both** iOS Settings and the iOS Inbox, matching macOS.
- [x] Notification scheduling wiring (see "What's Built (macOS)" above — shared logic, not iOS-specific)
- [x] `EstimatePickerPopoverContent` in `Shared/Components` is the estimate picker for **both** platforms; `EstimatePickerControl` is the iOS chip wrapper around it

Not guaranteed to have full feature parity with macOS by design — check the actual view file before assuming a macOS feature exists on iOS.

## Notifications
Local notification scheduling (`Cadence/Services/NotificationScheduling.swift` + `NotificationManager.swift`) uses **stateless reconciliation**, not imperative schedule-on-mutation: a pure planner computes the desired notification set from current SwiftData state (tasks with a future scheduled-start/due date, habits with `reminderMinuteOfDay` set), and `NotificationManager.reconcile(tasks:habits:)` diffs that against what's actually pending and converges. This mirrors `CadenceWidgetRefreshCenter`'s existing pattern. Reconciliation runs from the `scenePhase` checkpoint in both root views (safety net) plus fast-path calls at task/habit create, complete/cancel/reopen, and delete for instant feedback. Authorization is requested from exactly one place — the Settings → Notifications section — never at cold launch. A single global `@AppStorage("notificationsEnabled")` toggle controls all reminders; there's no per-notification-type or per-item toggle beyond "task has a date" / "habit has a reminder time set."

## What's Not Built Yet
- [ ] watchOS target
- [ ] Attaching a task to an existing calendar event. This was listed as built and is not — see
      the note under "Calendar / Events". `AppTask.calendarEventID` has readers but no writer.
