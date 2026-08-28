# Cadence

A native SwiftUI productivity app for macOS, iPadOS, and iOS — tasks, notes, calendar,
goals, habits, and focus sessions in one system, with an **MCP server** that lets LLM agents
read and modify app data through a validated, audited tool surface.

<!-- SCREENSHOTS — drop images in docs/screenshots/ and uncomment:
| Today | Calendar Board | Notes |
| :---: | :---: | :---: |
| ![Today](docs/screenshots/today.png) | ![Board](docs/screenshots/board.png) | ![Notes](docs/screenshots/notes.png) |
-->

| | |
|---|---|
| **Platforms** | macOS 26.1+, iOS/iPadOS 26.2+ |
| **Language** | Swift 6 / SwiftUI, no UIKit |
| **Persistence** | SwiftData + CloudKit private-database sync |
| **Size** | ~601 Swift files, ~142k lines (~112k app, ~29k tests) |
| **Tests** | 1,579 tests across 13 suites (Swift Testing) |
| **Agent surface** | 30 MCP tools over a read/write service split |
| **Dependencies** | One: the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) |

## What Cadence Does

- Capture and organize tasks across inbox, areas, projects, sections, kanban boards, and calendar timelines.
- Schedule tasks on a day timeline and optionally mirror them to Apple Calendar.
- Write unified Markdown notes for daily, weekly, permanent, list, and event contexts.
- Track goals, habits, focus sessions, and progress signals.
- Search across tasks, notes, lists, calendar-linked event notes, and other app content.
- Use optional AI note actions with a user-provided OpenAI API key.
- Drive the app from an LLM agent through the bundled MCP server.

## Architecture Highlights

### Agent interface (`CadenceMCPServer/`, `Cadence/Services/MCPReadOnly/`)

Cadence exposes 30 tools over the Model Context Protocol — `list_tasks`, `create_task`,
`schedule_task`, `search_cadence`, `get_today_brief`, `bulk_cancel_tasks`, and so on. The design
treats an agent as an untrusted caller:

- **Read/write split.** `CadenceReadService` and `CadenceWriteService` are separate types. The read
  path cannot mutate state, and a test asserts it (`readCoreNotesStillDoesNotCreateMissingNotes`).
- **Validate before mutate.** Invalid arguments are rejected without partial writes, so a
  half-applied update is not a reachable state (`updateTaskRejectsInvalidInputWithoutPartialMutation`).
- **Audited writes.** Every successful write is recorded; invalid writes are skipped and not logged
  as successes. `get_recent_mcp_writes` exposes the log back to the agent.
- **Scoped destructive operations.** Bulk cancellation requires an explicit scope rather than
  defaulting to "everything matching" (`bulkCancelTasksRequiresSpecificScopeAndAuditsChangedTasks`).

### Optional AI actions (`Cadence/Services/AI/`)

Off by default and gated behind a user-supplied API key. Provider access sits behind an
`AIProvider` abstraction, and anything the model proposes — task drafts in particular — goes
through a review sheet before it reaches the database. The key is never logged and request bodies
are never persisted.

### One shared model layer

20 SwiftData `@Model` types (14 live; 6 retained only as migration sources) back all three
platforms. Because the store syncs through CloudKit, every to-many relationship is an optional
array — the constraint that shapes most of the data-access code.

### Testing

1,579 tests, concentrated on the logic that is painful to verify by hand: Markdown parsing and
mutation, timeline coordinate math, recurrence expansion, scheduling, and the MCP service boundary.
UI tests live in a separate target and are excluded from normal runs.

## Platform Status

- **macOS** — primary, fully featured surface. Custom sidebar, multi-column layouts, kanban boards,
  timeline scheduling, an AppKit-backed Markdown editor.
- **iOS / iPadOS** — a large, actively-developed surface (79 files) with an adaptive root shell:
  iPad sidebar at regular width, four-tab bottom bar at compact width. Covers Today, Calendar,
  Tasks, Focus, Goals, Habits, Notes, Lists, Search, and Settings. Not at full macOS parity by design.
- **Widgets** — four: today's tasks, calendar snapshot, habit check-in, and milestone momentum.
- **watchOS** — not started.

## Tech Stack

- SwiftUI and SwiftData
- CloudKit private database sync
- EventKit for Apple Calendar and Reminders integration
- WidgetKit and App Intents for widget/system surfaces
- AuthenticationServices for optional Sign in with Apple
- AppKit interop for the Markdown editor and macOS-specific panels

## Requirements

- Xcode with the macOS SDK used by the project
- macOS 26.1+ deployment target
- iOS 26.2+ deployment target for iOS builds
- An Apple developer team configured for the app entitlements if you are signing or running
  outside local debug

## Build

Open `Cadence.xcodeproj` in Xcode and run the `Cadence` scheme on macOS.

```sh
xcodebuild \
  -project Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=macOS' \
  build
```

Run tests. Scope to `CadenceTests` — an unscoped run pulls in `CadenceUITests`, which cannot
launch headless:

```sh
xcodebuild test \
  -project Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=macOS' \
  -only-testing:CadenceTests
```

## Repository Map

| Path | Contents |
|---|---|
| `Cadence/Models/` | Shared SwiftData models (100% cross-platform) |
| `Cadence/Services/` | Schema, migrations, Markdown engine, notifications, widget support, AI, MCP services |
| `Cadence/Shared/` | Design tokens, shared components, date/time helpers, presentation logic |
| `Cadence/macOS/` | Primary macOS surface — views, sheets, AppKit editor bridge, macOS-only managers |
| `Cadence/iOS/` | iOS/iPadOS surfaces and its own Markdown editor stack |
| `CadenceWidgets/` | Widget extension |
| `CadenceMCPServer/` | Native MCP server — tool definitions, router, argument parsing |
| `plugins/cadence-mcp/` | MCP plugin wrapper and smoke-test scripts |
| `CadenceTests/` | Unit tests (138 files) |
| `CadenceUITests/` | UI tests — never included in scoped runs |
| `docs/` | Privacy/support site and App Review notes |

## Implementation Notes

- SwiftData relationships that sync through CloudKit use optional to-many arrays. Read them with
  `?? []` and append by assigning a new array.
- Persisted day keys are `yyyy-MM-dd` strings. Use the shared `DateFormatters` and `TimeFormatters`
  helpers rather than constructing formatters inline.
- All colour comes from `Shared/Theme.swift` or a user-owned `colorHex`. There is one fixed dark
  palette and no theme picker.
- Notes are unified through the canonical `Note` model. Legacy note models remain in the schema
  purely as migration sources — build no UI on them.
- Calendar and Reminders access are optional. Cadence must keep working when permission is denied.
- AI features are optional and require the user to save their own OpenAI API key in Settings.

## Data and Privacy

Cadence stores user data locally with SwiftData and may sync through the user's private iCloud
database. Calendar access, Sign in with Apple, and AI actions are all optional and separately
authorized. A privacy data reset wipes every model. See `docs/privacy.html` and
`docs/app-review-notes.md`.

## Contributor Notes

Read `AGENTS.md` first, then the nearest scoped `AGENTS.md` before editing a subtree. The most
sensitive areas are the Markdown editor, calendar/timeline coordinate math, the SwiftData schema
and its migrations, and the MCP service boundary.
