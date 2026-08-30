# Cadence

Cadence is a native SwiftUI productivity app for planning work across tasks, notes, calendars, goals, habits, and focus sessions. The macOS app is the primary product surface today, with a large iOS/iPadOS surface built on the same models.

## What Cadence Does

- Capture and organize tasks across inbox, areas, projects, sections, kanban boards, and calendar timelines.
- Schedule tasks on a day timeline, and create Apple Calendar events alongside them. Scheduling a task does not create an event for it — the two are independent.
- Write unified markdown notes for daily, weekly, permanent, list, and meeting contexts.
- Track goals, habits, focus sessions, and progress signals.
- Search across tasks, notes, lists, calendar-linked meeting notes, and other app content.
- Use optional AI actions with a user-provided OpenAI API key. Requests go to OpenAI's API; nothing runs on device.
- Expose read/write automation surfaces through the bundled Cadence MCP integration.

## Platform Status

- macOS: primary, fully featured app surface.
- iOS/iPadOS: a large, actively-developed surface (79 files) with an adaptive root shell — an iPad sidebar layout at regular width, a tab bar at compact width — covering Today, Calendar, Tasks, Focus, Goals, Habits, Notes, Lists, Search, and Settings. Not at full feature parity with macOS by design.
- Widgets: Today task widget support is included.

## Tech Stack

- SwiftUI and SwiftData
- CloudKit private database sync
- EventKit for Apple Calendar integration
- WidgetKit and App Intents for widget/system surfaces
- AuthenticationServices for optional Sign in with Apple identity
- AppKit interop for the markdown editor and macOS-specific panels

## Requirements

- Xcode with the macOS SDK used by the project
- macOS 26.1+ deployment target
- iOS 26.2+ deployment target for iOS builds
- An Apple developer team configured for the app entitlements if you are signing/running outside local debug

## Build

Open `Cadence.xcodeproj` in Xcode and run the `Cadence` scheme on macOS.

Command-line build:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-build-$$ \
  build
```

Run tests:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  test \
  -project Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/cadence-test-$$ \
  -only-testing:CadenceTests
```

`-derivedDataPath` is not optional here. Without it every invocation — including read-only ones
like `-showBuildSettings` — writes into the shared `~/Library/Developer/Xcode/DerivedData` entry
that Xcode uses for this project, and a build there deletes `Build/Products/` under anything
already running from it.

## Repository Map

- `Cadence/` - main app source.
- `Cadence/Models/` - shared SwiftData models.
- `Cadence/Services/` - shared app services, schema, migration, note/search support, widget support, and MCP-facing services.
- `Cadence/Shared/` - design tokens, common components, date/time helpers, and shared logic.
- `Cadence/macOS/` - primary macOS app surface.
- `Cadence/macOS/Editor/` - AppKit-backed markdown editor.
- `Cadence/macOS/Services/` - macOS-only managers for calendar, focus, hotkeys, scheduling, hover state, and deletion.
- `Cadence/macOS/Views/` - macOS feature screens and support views.
- `Cadence/iOS/` - iOS/iPadOS feature surfaces.
- `CadenceWidgets/` - widget extension.
- `CadenceMCPServer/` - native MCP server target.
- `plugins/cadence-mcp/` - Codex MCP plugin wrapper and smoke test scripts.
- `CadenceTests/` and `CadenceUITests/` - test targets.
- `docs/` - support, privacy, and App Review notes.

## Important Implementation Notes

- SwiftData relationships that sync through CloudKit use optional to-many arrays. Read them with `?? []` and append by assigning a new array.
- Persisted day keys use `yyyy-MM-dd` strings. Use the shared `DateFormatters` and `TimeFormatters` helpers instead of ad hoc formatters.
- Notes are unified through the canonical `Note` model. Legacy note models remain in the schema as migration sources.
- Task detail notes remain plain `AppTask.notes`.
- Calendar integration is optional. Cadence should continue working when Calendar permission is not granted.
- AI features are optional and require the user to save their own OpenAI API key in Settings.

## Data And Privacy

Cadence stores user data locally with SwiftData and may sync through the user's private iCloud database. Calendar access, Sign in with Apple, and AI actions are optional. See `docs/privacy.html` and `docs/app-review-notes.md` for the current privacy and App Review notes.

## Contributor Notes

Coding agents should read `AGENTS.md` first, then the nearest scoped `AGENTS.md` before editing a subtree. The most sensitive areas are the markdown editor, calendar/timeline math, SwiftData schema and migrations, and MCP service boundaries.
