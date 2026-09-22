# R64 Model And Field Inventory

```text
Tree read: d819a4c
Dirty files: 1 in the source checkout; committed snapshot used, dirty probe excluded
23 models; 256 stored declarations: 194 attributes and 62 relationship endpoints
33 to-many endpoints; all relationship endpoints optional
```

MEASURED-SOURCE, not a generated-model or live CloudKit inspection. Every model below is explicitly
listed in `Cadence/Services/CadenceSchema.swift:4`. Every listed stored declaration has an initializer
(including `nil` for optional values). There are no `@Transient`, `.unique` or `.deny` declarations
in these model files. Computed properties and non-model helper structs are not separate stored fields;
for example, `TaskSectionConfig` is serialized into its owning Area/Project strings.

Reproduce exact names, types, defaults, lines and inverse candidates with:

```sh
ruby docs/audits/2026-09-22/sync-rollback/model_inventory.rb /path/to/committed/snapshot
```

The companion is a source-shape inventory, not a general Swift parser. Its results were checked against
the current model declarations; future multiline/declaration changes require reviewing the extractor.
`L` references below are line numbers within the linked model file. A named explicit inverse can be
on the other endpoint; it need not be repeated at both ends.

## AppTask

[Cadence/Models/AppTask.swift:203](../../../../Cadence/Models/AppTask.swift#L203)

Attributes: `id: UUID` (L204); `title: String` (L205); `notes: String` (L206); `priorityRaw: String` (L207); `statusRaw: String` (L208); `dueDate: String` (L226); `scheduledDate: String` (L227); `scheduledStartMin: Int` (L228); `estimatedMinutes: Int` (L229); `actualMinutes: Int` (L230); `calendarEventID: String` (L240); `recurrenceRaw: String` (L241); `recurrenceSpawnedTaskIDRaw: String` (L242); `recurrenceSeriesIDRaw: String` (L243); `recurrenceSourceTaskIDRaw: String` (L244); `recurrenceOccurrenceIndex: Int` (L245); `recurrenceEndModeRaw: String` (L248); `recurrenceEndDate: String` (L249); `recurrenceEndCount: Int` (L250); `sectionName: String` (L251); `order: Int` (L252); `createdAt: Date` (L253); `completedAt: Date?` (L254); `bundleOrder: Int` (L261).

Relationships:

- `area: Area?` (L256) <-> `Area.tasks` (explicit inverse at one endpoint).
- `project: Project?` (L257) <-> `Project.tasks` (explicit inverse at one endpoint).
- `goal: Goal?` (L258) <-> `Goal.tasks` (explicit inverse at one endpoint).
- `context: Context?` (L259) <-> `Context.tasks` (explicit inverse at one endpoint).
- `bundle: TaskBundle?` (L260) <-> `TaskBundle.tasks` (explicit inverse at one endpoint).
- `subtasks: [Subtask]?` (L262) <-> `Subtask.parentTask` (inferred pair; generated schema not inspected).
- `tags: [Tag]?` (L263) <-> `Tag.tasks` (explicit inverse at one endpoint).
- `focusSessions: [FocusSessionLog]?` (L270) <-> `FocusSessionLog.task` (explicit inverse at one endpoint).

## TaskBundle

[Cadence/Models/AppTask.swift:511](../../../../Cadence/Models/AppTask.swift#L511)

Attributes: `id: UUID` (L512); `title: String` (L513); `dateKey: String` (L514); `startMin: Int` (L515); `durationMinutes: Int` (L516); `createdAt: Date` (L517).

Relationships:

- `tasks: [AppTask]?` (L519) <-> `AppTask.bundle` (explicit inverse at one endpoint).

## FocusSessionLog

[Cadence/Models/AppTask.swift:639](../../../../Cadence/Models/AppTask.swift#L639)

Attributes: `id: UUID` (L640); `minutes: Int` (L642); `previousMinutes: Int` (L644); `loggedAt: Date` (L645); `dayKey: String` (L648).

Relationships:

- `task: AppTask?` (L650) <-> `AppTask.focusSessions` (explicit inverse at one endpoint).
- `area: Area?` (L651) <-> `Area.focusSessions` (explicit inverse at one endpoint).
- `project: Project?` (L652) <-> `Project.focusSessions` (explicit inverse at one endpoint).

## Area

[Cadence/Models/Area.swift:5](../../../../Cadence/Models/Area.swift#L5)

Attributes: `id: UUID` (L6); `name: String` (L7); `desc: String` (L8); `statusRaw: String` (L9); `colorHex: String` (L15); `icon: String` (L16); `order: Int` (L17); `linkedCalendarID: String` (L40); `loggedMinutes: Int` (L41); `hideDueDateIfEmpty: Bool` (L42); `hideSectionDueDateIfEmpty: Bool` (L43); `sectionNamesRaw: String` (L44); `sectionConfigsRaw: String` (L45).

Relationships:

- `context: Context?` (L47) <-> `Context.areas` (explicit inverse at one endpoint).
- `tasks: [AppTask]?` (L48) <-> `AppTask.area` (explicit inverse at one endpoint).
- `projects: [Project]?` (L49) <-> `Project.area` (explicit inverse at one endpoint).
- `documents: [Document]?` (L50) <-> `Document.area` (explicit inverse at one endpoint).
- `notes: [Note]?` (L51) <-> `Note.area` (explicit inverse at one endpoint).
- `links: [SavedLink]?` (L52) <-> `SavedLink.area` (explicit inverse at one endpoint).
- `goalLinks: [GoalListLink]?` (L53) <-> `GoalListLink.area` (explicit inverse at one endpoint).
- `focusSessions: [FocusSessionLog]?` (L57) <-> `FocusSessionLog.area` (explicit inverse at one endpoint).

## Context

[Cadence/Models/Context.swift:5](../../../../Cadence/Models/Context.swift#L5)

Attributes: `id: UUID` (L6); `name: String` (L7); `colorHex: String` (L8); `icon: String` (L9); `order: Int` (L10); `isArchived: Bool` (L11).

Relationships:

- `areas: [Area]?` (L13) <-> `Area.context` (explicit inverse at one endpoint).
- `projects: [Project]?` (L14) <-> `Project.context` (explicit inverse at one endpoint).
- `pursuits: [Pursuit]?` (L15) <-> `Pursuit.context` (explicit inverse at one endpoint).
- `tasks: [AppTask]?` (L16) <-> `AppTask.context` (explicit inverse at one endpoint).
- `goals: [Goal]?` (L17) <-> `Goal.context` (explicit inverse at one endpoint).
- `habits: [Habit]?` (L18) <-> `Habit.context` (explicit inverse at one endpoint).

## DailyNote

[Cadence/Models/DailyNote.swift:5](../../../../Cadence/Models/DailyNote.swift#L5)

Attributes: `id: UUID` (L6); `date: String` (L7); `content: String` (L8); `createdAt: Date` (L9); `updatedAt: Date` (L10).

Relationships: none.

## Document

[Cadence/Models/Document.swift:5](../../../../Cadence/Models/Document.swift#L5)

Attributes: `id: UUID` (L6); `title: String` (L7); `content: String` (L8); `order: Int` (L9); `createdAt: Date` (L10); `updatedAt: Date` (L11).

Relationships:

- `area: Area?` (L13) <-> `Area.documents` (explicit inverse at one endpoint).
- `project: Project?` (L14) <-> `Project.documents` (explicit inverse at one endpoint).

## EventNote

[Cadence/Models/EventNote.swift:5](../../../../Cadence/Models/EventNote.swift#L5)

Attributes: `id: UUID` (L6); `calendarEventID: String` (L7); `calendarID: String` (L8); `title: String` (L9); `content: String` (L10); `eventDateKey: String` (L11); `eventStartMin: Int` (L12); `eventEndMin: Int` (L13); `createdAt: Date` (L14); `updatedAt: Date` (L15).

Relationships: none.

## Goal

[Cadence/Models/Goal.swift:4](../../../../Cadence/Models/Goal.swift#L4)

Attributes: `id: UUID` (L5); `title: String` (L6); `desc: String` (L7); `startDate: String` (L8); `endDate: String` (L9); `progressTypeRaw: String` (L10); `targetHours: Double` (L11); `loggedHours: Double` (L12); `colorHex: String` (L13); `icon: String` (L14); `statusRaw: String` (L15); `kindRaw: String` (L18); `order: Int` (L35); `createdAt: Date` (L36); `dependsOnGoalIDsJSON: String` (L38).

Relationships:

- `context: Context?` (L40) <-> `Context.goals` (explicit inverse at one endpoint).
- `pursuit: Pursuit?` (L41) <-> `Pursuit.goals` (explicit inverse at one endpoint).
- `parentGoal: Goal?` (L42) <-> `Goal.subGoals` (explicit inverse at one endpoint).
- `subGoals: [Goal]?` (L43) <-> `Goal.parentGoal` (explicit inverse at one endpoint).
- `tasks: [AppTask]?` (L44) <-> `AppTask.goal` (explicit inverse at one endpoint).
- `listLinks: [GoalListLink]?` (L45) <-> `GoalListLink.goal` (explicit inverse at one endpoint).
- `habits: [Habit]?` (L46) <-> `Habit.goal` (explicit inverse at one endpoint).

## GoalListLink

[Cadence/Models/GoalListLink.swift:4](../../../../Cadence/Models/GoalListLink.swift#L4)

Attributes: `id: UUID` (L5); `createdAt: Date` (L6).

Relationships:

- `goal: Goal?` (L8) <-> `Goal.listLinks` (explicit inverse at one endpoint).
- `area: Area?` (L9) <-> `Area.goalLinks` (explicit inverse at one endpoint).
- `project: Project?` (L10) <-> `Project.goalLinks` (explicit inverse at one endpoint).

## Habit

[Cadence/Models/Habit.swift:4](../../../../Cadence/Models/Habit.swift#L4)

Attributes: `id: UUID` (L5); `title: String` (L6); `icon: String` (L7); `colorHex: String` (L8); `frequencyTypeRaw: String` (L9); `frequencyDaysRaw: String` (L16); `targetCount: Int` (L17); `order: Int` (L18); `createdAt: Date` (L19); `reminderMinuteOfDay: Int?` (L42).

Relationships:

- `context: Context?` (L44) <-> `Context.habits` (explicit inverse at one endpoint).
- `pursuit: Pursuit?` (L45) <-> `Pursuit.habits` (explicit inverse at one endpoint).
- `goal: Goal?` (L46) <-> `Goal.habits` (explicit inverse at one endpoint).
- `completions: [HabitCompletion]?` (L47) <-> `HabitCompletion.habit` (explicit inverse at one endpoint).

## HabitCompletion

[Cadence/Models/HabitCompletion.swift:4](../../../../Cadence/Models/HabitCompletion.swift#L4)

Attributes: `id: UUID` (L5); `date: String` (L6); `count: Int` (L7); `createdAt: Date` (L8).

Relationships:

- `habit: Habit?` (L10) <-> `Habit.completions` (explicit inverse at one endpoint).

## LookPreference

[Cadence/Models/LookPreference.swift:80](../../../../Cadence/Models/LookPreference.swift#L80)

Attributes: `id: UUID` (L81); `accentPaletteID: String` (L87); `sidebarTabColorsRaw: String` (L92); `taskPresentationRaw: String` (L97); `createdAt: Date` (L99); `updatedAt: Date` (L101).

Relationships: none.

## MarkdownImageAsset

[Cadence/Models/MarkdownImageAsset.swift:4](../../../../Cadence/Models/MarkdownImageAsset.swift#L4)

Attributes: `id: UUID` (L5); `data: Data` (L6); `mimeType: String` (L7); `originalFilename: String` (L8); `altText: String` (L9); `pixelWidth: Int` (L10); `pixelHeight: Int` (L11); `displayWidth: Double` (L12); `createdAt: Date` (L13); `updatedAt: Date` (L14).

Relationships: none.

## Note

[Cadence/Models/Note.swift:21](../../../../Cadence/Models/Note.swift#L21)

Attributes: `id: UUID` (L22); `kindRaw: String` (L23); `title: String` (L41); `content: String` (L42); `order: Int` (L43); `createdAt: Date` (L44); `updatedAt: Date` (L45); `dateKey: String` (L47); `weekKey: String` (L48); `calendarEventID: String` (L50); `calendarID: String` (L51); `eventDateKey: String` (L52); `eventStartMin: Int` (L53); `eventEndMin: Int` (L54); `legacySourceKindRaw: String` (L56); `legacySourceID: String` (L57); `folderPath: String` (L58).

Relationships:

- `area: Area?` (L60) <-> `Area.notes` (explicit inverse at one endpoint).
- `project: Project?` (L61) <-> `Project.notes` (explicit inverse at one endpoint).
- `tags: [Tag]?` (L62) <-> `Tag.notes` (explicit inverse at one endpoint).

## PermNote

[Cadence/Models/PermNote.swift:6](../../../../Cadence/Models/PermNote.swift#L6)

Attributes: `id: UUID` (L7); `content: String` (L8); `updatedAt: Date` (L9).

Relationships: none.

## Project

[Cadence/Models/Project.swift:5](../../../../Cadence/Models/Project.swift#L5)

Attributes: `id: UUID` (L6); `name: String` (L7); `desc: String` (L8); `statusRaw: String` (L9); `colorHex: String` (L15); `icon: String` (L16); `dueDate: String` (L17); `order: Int` (L18); `linkedCalendarID: String` (L25); `loggedMinutes: Int` (L26); `hideDueDateIfEmpty: Bool` (L27); `hideSectionDueDateIfEmpty: Bool` (L28); `sectionNamesRaw: String` (L29); `sectionConfigsRaw: String` (L30).

Relationships:

- `context: Context?` (L32) <-> `Context.projects` (explicit inverse at one endpoint).
- `area: Area?` (L33) <-> `Area.projects` (explicit inverse at one endpoint).
- `tasks: [AppTask]?` (L34) <-> `AppTask.project` (explicit inverse at one endpoint).
- `documents: [Document]?` (L35) <-> `Document.project` (explicit inverse at one endpoint).
- `notes: [Note]?` (L36) <-> `Note.project` (explicit inverse at one endpoint).
- `links: [SavedLink]?` (L37) <-> `SavedLink.project` (explicit inverse at one endpoint).
- `goalLinks: [GoalListLink]?` (L38) <-> `GoalListLink.project` (explicit inverse at one endpoint).
- `focusSessions: [FocusSessionLog]?` (L42) <-> `FocusSessionLog.project` (explicit inverse at one endpoint).

## Pursuit

[Cadence/Models/Pursuit.swift:14](../../../../Cadence/Models/Pursuit.swift#L14)

Attributes: `id: UUID` (L15); `title: String` (L16); `desc: String` (L17); `icon: String` (L18); `colorHex: String` (L19); `kindRaw: String` (L20); `statusRaw: String` (L21); `order: Int` (L22); `createdAt: Date` (L23).

Relationships:

- `context: Context?` (L35) <-> `Context.pursuits` (explicit inverse at one endpoint).
- `goals: [Goal]?` (L36) <-> `Goal.pursuit` (explicit inverse at one endpoint).
- `habits: [Habit]?` (L37) <-> `Habit.pursuit` (explicit inverse at one endpoint).

## SavedLink

[Cadence/Models/SavedLink.swift:5](../../../../Cadence/Models/SavedLink.swift#L5)

Attributes: `id: UUID` (L6); `title: String` (L7); `url: String` (L8); `order: Int` (L9); `createdAt: Date` (L10).

Relationships:

- `area: Area?` (L12) <-> `Area.links` (explicit inverse at one endpoint).
- `project: Project?` (L13) <-> `Project.links` (explicit inverse at one endpoint).

## SidebarLayoutPreference

[Cadence/Models/SidebarLayoutPreference.swift:46](../../../../Cadence/Models/SidebarLayoutPreference.swift#L46)

Attributes: `id: UUID` (L47); `orderRaw: String` (L50); `hiddenRaw: String` (L52); `createdAt: Date` (L53); `updatedAt: Date` (L55).

Relationships: none.

## Subtask

[Cadence/Models/Subtask.swift:6](../../../../Cadence/Models/Subtask.swift#L6)

Attributes: `id: UUID` (L7); `title: String` (L8); `isDone: Bool` (L9); `order: Int` (L10); `createdAt: Date` (L11).

Relationships:

- `parentTask: AppTask?` (L13) <-> `AppTask.subtasks` (inferred pair; generated schema not inspected).

## Tag

[Cadence/Models/Tag.swift:4](../../../../Cadence/Models/Tag.swift#L4)

Attributes: `id: UUID` (L5); `slug: String` (L6); `name: String` (L7); `desc: String` (L8); `colorHex: String` (L9); `order: Int` (L10); `isArchived: Bool` (L11); `createdAt: Date` (L12); `updatedAt: Date` (L13).

Relationships:

- `tasks: [AppTask]?` (L15) <-> `AppTask.tags` (explicit inverse at one endpoint).
- `notes: [Note]?` (L16) <-> `Note.tags` (explicit inverse at one endpoint).

## WeeklyNote

[Cadence/Models/WeeklyNote.swift:5](../../../../Cadence/Models/WeeklyNote.swift#L5)

Attributes: `id: UUID` (L6); `weekKey: String` (L7); `content: String` (L8); `createdAt: Date` (L9); `updatedAt: Date` (L10).

Relationships: none.

## Important Interpretation

- `MarkdownImageAsset.data` uses `.externalStorage`: it is still a model attribute, not a loose
  device-local image path. CloudKit transfer/asset completeness was not measured here.
- The only pair without an explicit inverse annotation is `AppTask.subtasks` / `Subtask.parentTask`.
  Both endpoints are optional and the counterpart is unambiguous in source. Apple permits inferred
  inverses; this is not evidence of a missing inverse or reason to alter the deployed schema.
- Eligibility for sync does not prove successful export, import, conflict resolution, or visibility.
  See [coverage.md](coverage.md) for the write routes, exclusions, and new-device checks.

