# Cadence App Store Submission Packet

Last updated: June 17, 2026

This is the repo-tracked source for App Store Connect submission fields and review preparation. Keep it aligned with `docs/apple-release-readiness.md`, `docs/privacy.html`, `docs/support.html`, and `docs/app-review-notes.md`.

## App Store Connect Fields

- App name: Cadence
- Bundle ID: `com.haoranwei.Cadence`
- SKU: `cadence-macos`
- Category: Productivity
- Platforms: macOS
- Minimum OS: macOS 26.1
- Version: `1.0`
- Build: current project build number
- Copyright: `© 2026 Haoran Wei` — **confirmed by the user 2026-09-05 as their legal name.** They
  also hold a Chinese name; it is deliberately **not** included, because this field names the legal
  entity that owns the app and a name absent from the Apple Developer Program account is a
  discrepancy a reviewer can query for no benefit. **One check remains:** if App Store Connect →
  Business → Legal Entity Name reads the Chinese name, use that instead — the field must match the
  account, not the person's preference.
- Keywords (Apple limit: 100 characters, comma-separated): `tasks,to-do,planner,calendar,notes,habits,goals,productivity,iCloud sync,widgets,reminders,markdown` (99 characters).
- Description (Apple limit: 4000 characters): see "App Description" below (currently ~1,900 characters). Paste it as-is or edit for tone; do not add claims not covered by "Metadata must avoid claims that are not true for the build" further down.
- Encryption: uses only exempt or standard platform encryption; `ITSAppUsesNonExemptEncryption` is false.
- Support URL: `https://williamweihaoran.github.io/cadence/support.html`
- Privacy Policy URL: `https://williamweihaoran.github.io/cadence/privacy.html`
- Sign in required: no
- Demo account required: no
- Purchases: none
- Ads/tracking: none
- User-facing push notifications: none

Not required by Apple for this submission, and intentionally left blank: Marketing URL and
Promotional Text. Their absence is not a blocker.

## App Description

Paste into App Store Connect's Description field (4000-character limit).

```
Cadence is a native macOS productivity app for planning your day, your week, and your longer-term goals in one place.

Tasks
Create tasks with due dates, tags, and projects. Organize work into projects and areas, and see what matters today on a dedicated Today view.

Calendar
Cadence shows your Apple Calendar events alongside your tasks, so you can plan around what is already on your schedule. With your permission, Cadence can also create, update, and delete calendar events; calendar access is optional and requested only when you use a calendar feature.

Reminders
Cadence can show your open Apple Reminders in its Inbox so nothing gets lost between apps. Reminders access is requested separately from Calendar access, and Cadence never creates, edits, or deletes a reminder — it can only mark one complete when you check it off.

Notes
Write notes with Markdown support, including headings, lists, checklists, tables, and links back to your tasks and events. Daily, weekly, and permanent notes give you a place for journaling, planning, and reference material.

Habits and Goals
Track recurring habits with check-ins, and set longer-term goals you can connect your tasks and progress to.

iCloud Sync
Your tasks, notes, habits, goals, and settings sync through your own private iCloud account across your Macs. Cadence does not run its own servers and does not see your data.

Widgets
Add Cadence widgets to see today's tasks, upcoming calendar events, habit check-ins, and goal milestones at a glance.

Optional AI Assistance
If you add your own OpenAI API key in Settings, Cadence can run optional AI actions on note content you select. AI is off by default and only runs when you choose to use it.

Privacy
Cadence has no ads, no third-party tracking, and no in-app purchases. Sign in with Apple is optional, and you can delete your account and all of your Cadence data at any time from Settings.
```

This deliberately says nothing about iOS/iPadOS: per `docs/apple-release-readiness.md`, the iOS
build is not distributed on any channel, and this packet's fields are macOS-only on purpose — "sync
across your Macs" is the honest claim, not "sync across your devices."

## Review Notes

Paste `docs/app-review-notes.md` into App Store Connect "Notes for Review" and update only if behavior changed for the submitted build.

Required notes:

- Calendar access is optional and permission-gated.
- Reminders access is optional and permission-gated, and is requested separately from Calendar access. Cadence reads incomplete reminders and can mark one complete; it never creates, edits, or deletes a reminder.
- Sign in with Apple is optional.
- Account/data deletion is available in Settings, Account and Settings, Data Safety.
- AI is optional, requires the user's own OpenAI API key, and sends selected note content only when the user runs an AI command.
- CloudKit sync may use the user's private iCloud database.
- Cadence has no purchases, subscriptions, ads, tracking, or user-facing push notifications. The APS entitlement it ships is for CloudKit's silent sync pushes; task and habit reminders are local notifications, requested only from Settings, Notifications.

## Privacy Details

Use `docs/apple-release-readiness.md` as the privacy-label source of truth. The current App Store Connect privacy answers should include:

- Data linked to the user for app functionality: name, email address, user ID, and other user content.
- No data used to track the user.
- No tracking domains.
- Calendar access described as permission-gated app functionality.
- Optional OpenAI processing disclosed in the privacy policy and review notes.

Do not answer "Data Not Collected" for the app target because Cadence stores and may sync user-created productivity content.

## Screenshot And Metadata Checklist

App Store Connect takes 1 to 10 macOS screenshots per localisation, at exactly one of 1280x800,
1440x900, 2560x1600, or 2880x1800 pixels, PNG or JPEG, RGB, flattened, with no alpha channel. A raw
`screencapture` of a window has transparent rounded corners and is rejected for that reason.

Candidates, and the two scripts that reproduce them, live in `docs/screenshots/`. Read
`docs/screenshots/README.md` before regenerating: it carries the launch and capture rules, including
that a locked screen makes capture impossible.

Prepare screenshots that show actual product functionality, not placeholder/sample-only screens:

- Today or timeline planning surface.
- Notes/editor surface.
- Calendar integration surface.
- A list in board (Kanban) mode, or the goals/habits surface.
- Settings privacy/data safety surface.
- Widget examples if widgets are highlighted in metadata.

The seeded content in `docs/screenshots/seed-screenshot-data.py` is written to be plausible product
data. Do not ship a capture of the UI-test fixture in `Cadence/Services/CadenceUITestSupport.swift`:
"UI Test Workspace", "Alpha Area" and "Beta Project" are exactly the placeholder-looking content
review flags.

Metadata must avoid claims that are not true for the build:

- Do not claim iOS feature parity.
- Do not claim AI runs locally.
- Do not claim Calendar access is required.
- Do not claim push notifications are a user-facing feature.
- Do not mention MCP integrations unless they are part of the shipped app experience.

## Pre-Upload Gates

- Run the verification commands in `docs/apple-release-readiness.md`.
- Confirm support/privacy URLs are publicly reachable.
- Confirm App Store Connect capabilities match entitlements: iCloud/CloudKit, Sign in with Apple, App Groups, Calendar, widgets, and remote notification capability for CloudKit sync.
- Confirm the submitted archive uses distribution signing and does not contain debug-only test frameworks.
- Confirm `CadenceMCPServer` and `plugins/cadence-mcp` are not embedded in the app archive.
