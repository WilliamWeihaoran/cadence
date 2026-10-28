# Cadence App Store Submission Packet

Last updated: October 28, 2026 (T-7681: the App Store Connect fields now cover iOS/iPadOS beside
macOS, and both descriptions drop the retired habits and goals features). October 20, 2026: every field below was re-checked against the tree that day; what was
measured rather than re-read is named in "Checked against the tree" at the foot of this file.

This is the repo-tracked source for App Store Connect submission fields and review preparation. Keep it aligned with `docs/apple-release-readiness.md`, `docs/privacy.html`, `docs/support.html`, and `docs/app-review-notes.md`.

**Build state at the last check (2026-10-22, read from the tree; superseded 2026-10-28 —
`CURRENT_PROJECT_VERSION` is now 25 on the app and widget targets, build 25 having gone to internal
TestFlight on 2026-10-27).** `MARKETING_VERSION = 1.0`
and `CURRENT_PROJECT_VERSION = 24` on all eight configurations of the shipping targets
(`961971ec`, Build 24, shipped 2026-10-21 on macOS and iOS; `CadenceMCPServer` keeps its own
`CURRENT_PROJECT_VERSION = 1` and is not archived). **The widget extension now carries the app's
iCloud container** (T-3152, `fde4dffc`, after the owner added the iCloud capability to the
`com.haoranwei.Cadence.CadenceWidgets` App ID): `plutil -p CadenceWidgets/CadenceWidgets.entitlements`
lists `icloud-container-identifiers` = `iCloud.com.haoranwei.Cadence`, `icloud-services` =
`CloudKit`, the app sandbox and the `group.com.haoranwei.Cadence` app group, and no push key in
either spelling, which `AppStoreReviewReadinessTests.widgetEntitlementsIncludeSandbox` asserts. The
file is committed and clean; the 2026-10-20 uncommitted edits are gone. Do not add Push
Notifications to the widget target: Xcode writes both push spellings into the one shared file when
it does. The consequence to know at review time is only sync latency — the extension's containers
still do not mirror (T-3227), so a widget write reaches another device when the app next runs an
export pass — and nothing about it is user-facing or reviewable.

## App Store Connect Fields

**One app record, two platforms (T-7681).** iOS/iPadOS became a v1 channel on 2026-10-25
(T-6410), and the project ships it under the same identity as the Mac: the `Cadence` target sets
`PRODUCT_BUNDLE_IDENTIFIER = com.haoranwei.Cadence` with no per-SDK override, and the widget
extension `com.haoranwei.Cadence.CadenceWidgets` likewise, so the iOS build is a second platform on
the existing record (universal purchase), not a second app. App Store Connect keeps a separate
version page per platform; the fields below are split the same way.

Shared by both platforms:

- App name: Cadence
- Bundle ID: `com.haoranwei.Cadence` (macOS and iOS/iPadOS; widget extension
  `com.haoranwei.Cadence.CadenceWidgets` on both)
- SKU: `cadence-macos` — fixed when the record was created and not editable afterwards. The name
  predates iOS and is harmless; if the record shows a different SKU, the record wins.
- Category: Productivity (`INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.productivity`)
- Platforms: macOS, iOS (iPhone and iPad)
- Copyright: `© 2026 Haoran Wei` — **confirmed by the user 2026-09-05 as their legal name.** They
  also hold a Chinese name; it is deliberately **not** included, because this field names the legal
  entity that owns the app and a name absent from the Apple Developer Program account is a
  discrepancy a reviewer can query for no benefit. **One check remains:** if App Store Connect →
  Business → Legal Entity Name reads the Chinese name, use that instead — the field must match the
  account, not the person's preference.
- Encryption: uses only exempt or standard platform encryption; `ITSAppUsesNonExemptEncryption` is false.
- Support URL: `https://williamweihaoran.github.io/cadence/support.html`
- Privacy Policy URL: `https://williamweihaoran.github.io/cadence/privacy.html`
- Sign in required: no
- Demo account required: no
- Purchases: none
- Ads/tracking: none
- User-facing push notifications: none
- Keywords (Apple limit: 100 characters, comma-separated; the same string on both version pages): `tasks,to-do,planner,calendar,notes,productivity,iCloud sync,widgets,reminders,markdown` (86 characters). `habits,goals` came out with the screens they named (T-2076, T-5002); the room is free for the owner to spend.

macOS version page:

- Minimum OS: macOS 26.1 (`MACOSX_DEPLOYMENT_TARGET`; read from the build, not typed)
- Version: `1.0`
- Build: current project build number — `CURRENT_PROJECT_VERSION`, 25 on the app and widget
  targets at the last check (2026-10-28).
- Description (Apple limit: 4000 characters): see "App Description (macOS)" below (currently ~1,700 characters). Paste it as-is or edit for tone; do not add claims not covered by "Metadata must avoid claims that are not true for the build" further down.
- Screenshots: macOS set, per "Screenshot And Metadata Checklist" below.

iOS version page (iPhone and iPad):

- Minimum OS: iOS/iPadOS 26.1 (`IPHONEOS_DEPLOYMENT_TARGET`; read from the build, not typed)
- Devices: iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). iPhone runs portrait only; iPad
  supports all four orientations (`INFOPLIST_KEY_UISupportedInterfaceOrientations` and its
  `_iPad` variant).
- Version: `1.0`, the same `MARKETING_VERSION` as the Mac.
- Build: the same `CURRENT_PROJECT_VERSION`, uploaded as its own iOS archive.
- Description (Apple limit: 4000 characters): see "App Description (iOS/iPadOS)" below. Same rule
  as the Mac: no claims beyond "Metadata must avoid claims that are not true for the build".
- Screenshots: an iPhone set and an iPad set. **None exist yet** — the other half of T-7681, which
  needs an attended session with a simulator. See "Screenshot And Metadata Checklist".
- Availability on Apple silicon Macs and Apple Vision Pro: the project sets neither
  `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` nor `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD`, so Xcode's
  defaults apply. With a native Mac app on the same record, decide both in App Store Connect →
  Pricing and Availability rather than by inference; this packet does not assume either answer.

Not required by Apple for this submission, and intentionally left blank: Marketing URL and
Promotional Text. Their absence is not a blocker.

## App Description (macOS)

Paste into the macOS version page's Description field (4000-character limit).

```
Cadence is a native macOS productivity app for planning your day, your week, and the work ahead in one place.

Tasks
Create tasks with due dates, tags, and projects. Organize work into projects and areas, and see what matters today on a dedicated Today view.

Calendar
Cadence shows your Apple Calendar events alongside your tasks, so you can plan around what is already on your schedule. With your permission, Cadence can also create, update, and delete calendar events; calendar access is optional and requested only when you use a calendar feature.

Reminders
Cadence can show your open Apple Reminders in its Inbox so nothing gets lost between apps. Reminders access is requested separately from Calendar access, and Cadence never creates, edits, or deletes a reminder — it can only mark one complete when you check it off.

Notes
Write notes with Markdown support, including headings, lists, checklists, tables, and links back to your tasks and events. Daily, weekly, and permanent notes give you a place for journaling, planning, and reference material.

iCloud Sync
Your tasks, notes, and lists sync through your own private iCloud account across your Macs. Cadence does not run its own servers and does not see your data.

Widgets
Add Cadence widgets to see today's tasks and upcoming calendar events at a glance.

Optional AI Assistance
If you add your own OpenAI API key in Settings, Cadence can run optional AI actions on note content you select. AI is off by default and only runs when you choose to use it.

Privacy
Cadence has no ads, no third-party tracking, and no in-app purchases. Sign in with Apple is optional, and you can delete your account and all of your Cadence data at any time from Settings.
```

This copy is the Mac's alone and says nothing about iPhone or iPad; the iOS version page takes its
own text, below. "Across your Macs" was written when the Mac was the only channel; it is still true,
and with iOS on the same record and the same private CloudKit database it could now honestly be
widened — a copy decision for the owner, not a correction.

## App Description (iOS/iPadOS)

Paste into the iOS version page's Description field (4000-character limit). It differs from the
Mac copy where the platforms differ: no Sign in with Apple (macOS-only; iPhone and iPad have no
Cadence account and no Settings > Account), and deletion is of data, from Settings > Data Safety.
It claims no feature the iOS build lacks and does not claim parity with the Mac.

```
Cadence is a productivity app for iPhone and iPad for planning your day, your week, and the work ahead in one place.

Tasks
Create tasks with due dates, tags, and projects. Organize work into projects and areas, and see what matters today on a dedicated Today view.

Calendar
Cadence shows your Apple Calendar events alongside your tasks, so you can plan around what is already on your schedule. With your permission, Cadence can also create, update, and delete calendar events; calendar access is optional and requested only when you use a calendar feature.

Reminders
Cadence can show your open Apple Reminders in its Inbox so nothing gets lost between apps. Reminders access is requested separately from Calendar access, and Cadence never creates, edits, or deletes a reminder — it can only mark one complete when you check it off.

Notes
Write notes with Markdown support, including headings, lists, checklists, tables, and links back to your tasks and events. Daily, weekly, and permanent notes give you a place for journaling, planning, and reference material.

iCloud Sync
Your tasks, notes, and lists sync through your own private iCloud account across your iPhone, iPad, and Mac. Cadence does not run its own servers and does not see your data.

Widgets
Add Cadence widgets to your Home Screen to see today's tasks and upcoming calendar events at a glance.

Optional AI Assistance
If you add your own OpenAI API key in Settings, Cadence can run optional AI actions on note content you select. AI is off by default and only runs when you choose to use it.

Privacy
Cadence has no ads, no third-party tracking, no in-app purchases, and no account to create. You can delete all of your Cadence data at any time from Settings.
```

## Review Notes

Paste `docs/app-review-notes.md` into App Store Connect "Notes for Review" and update only if behavior changed for the submitted build.

Required notes:

- Calendar access is optional and permission-gated.
- Reminders access is optional and permission-gated, and is requested separately from Calendar access. Cadence reads incomplete reminders and can mark one complete; it never creates, edits, or deletes a reminder.
- Sign in with Apple is optional.
- Account/data deletion is available in Settings, Account and Settings, Data Safety.
- AI is optional, requires the user's own OpenAI API key, and sends the selected note — title, full text and list name — only when the user runs an AI command, with `store: false` so OpenAI does not retain it.
- CloudKit sync may use the user's private iCloud database.
- Cadence has no purchases, subscriptions, ads, tracking, or user-facing push notifications. The APS entitlement it ships is for CloudKit's silent sync pushes; task reminders are local notifications, requested only from Settings, Notifications (habit reminders were retired with the habits screens; `NotificationPlan` has no habit channel).

## Privacy Details

Use `docs/apple-release-readiness.md` as the privacy-label source of truth. The current App Store Connect privacy answers should include:

- **Other user content, linked to the user, app functionality.** This is the only collected row, and it is earned by the optional AI action transmitting a note's title, body and list name to OpenAI — not by storage (T-1311).
- **Name, email address and user ID are `Not Collected`.** Sign in with Apple writes them to local `UserDefaults` and nothing transmits them; the readiness doc names the evidence and the two things only the owner can confirm. The app's privacy manifest agrees since T-1323 — it declares `NSPrivacyCollectedDataTypeOtherUserContent` and nothing else. **Answering these three as not collected in App Store Connect is still a separate owner action**; the manifest is not read to produce the product page.
- No data used to track the user.
- No tracking domains.
- Calendar access described as permission-gated app functionality: EventKit reads and writes stay on the device and in the user's own Apple Calendar.
- Optional OpenAI processing disclosed in the privacy policy and review notes, including that `/v1/responses` retains the request by default and that Cadence opts out of that default with `store: false` on every request (T-1322).

Do not answer "Data Not Collected" for the app target — not because Cadence stores productivity content (storing is not collecting, and the user's private CloudKit database is not developer-accessible), but because the optional AI action really does transmit note content to a third party.

## Screenshot And Metadata Checklist

App Store Connect takes 1 to 10 macOS screenshots per localisation, at exactly one of 1280x800,
1440x900, 2560x1600, or 2880x1800 pixels, PNG or JPEG, RGB, flattened, with no alpha channel. A raw
`screencapture` of a window has transparent rounded corners and is rejected for that reason.

**iPhone and iPad (T-7681, not yet produced).** The iOS version page needs its own iPhone set and,
because the app runs on iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), an iPad set. Apple's required
display classes are the largest ones — 6.9-inch iPhone (1320x2868 or 1290x2796 portrait) or 6.5-inch
(1284x2778 or 1242x2688), and 13-inch iPad (2064x2752 or 2048x2732) — and smaller classes are scaled
from those. Those figures are Apple's published specification as last read, not re-checked against a
live App Store Connect session; confirm them on the upload page. **The two standing simulators are
neither size:** `Cadence-iPhone15` is a 6.1-inch 1179x2556 device and `Cadence-iPadPro11` an
11-inch one, so captures from them do not fill the required sets, and `docs/AGENT_BRIEF.md`
forbids agents creating another simulator. Which device produces the submission sets is the owner's
call; record it under T-7681. iPhone captures are portrait only, since the iPhone build supports
no other orientation.

Candidates, and the two scripts that reproduce them, live in `docs/screenshots/`. Read
`docs/screenshots/README.md` before regenerating: it carries the launch and capture rules, including
that a locked screen makes capture impossible.

Prepare screenshots that show actual product functionality, not placeholder/sample-only screens:

- Today or timeline planning surface.
- Notes/editor surface.
- Calendar integration surface.
- A list in board (Kanban) mode.
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
- Confirm App Store Connect capabilities match entitlements: iCloud/CloudKit, Sign in with Apple, App Groups, Calendar, widgets, and remote notification capability for CloudKit sync. The widget extension carries App Group, sandbox and the app's iCloud/CloudKit container and no push entitlement, per the T-3152 note at the top of this file. Match the capability list to the entitlements files as they are; do not change the entitlements to match the list.
- Confirm the submitted archive uses distribution signing and does not contain debug-only test frameworks.
- Confirm `CadenceMCPServer` and `plugins/cadence-mcp` are not embedded in the app archive.

## Checked Against The Tree

Re-checked 2026-10-20 by reading the project and the entitlements, not by re-reading this file:

- `MACOSX_DEPLOYMENT_TARGET = 26.1`, `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 24`
  (re-read 2026-10-22). Re-read 2026-10-28 for T-7681: `CURRENT_PROJECT_VERSION = 25` on both
  configurations of `Cadence` and `CadenceWidgets` (the test targets stay at 24 and ship nothing);
  `IPHONEOS_DEPLOYMENT_TARGET = 26.1` and `TARGETED_DEVICE_FAMILY = "1,2"` on the app;
  `PRODUCT_BUNDLE_IDENTIFIER = com.haoranwei.Cadence` with no `[sdk=…]` override, so one
  identifier covers both platforms; `CadenceWidgetsBundle` registers two widgets (Today Tasks,
  Calendar), which is why neither description claims habit or goal widgets.
- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` on both app configurations.
- `Cadence/PrivacyInfo.xcprivacy` declares `NSPrivacyCollectedDataTypeOtherUserContent` and no
  other collected type, which is what the "Privacy Details" section above claims it does.
- `CadenceWidgets/CadenceWidgets.entitlements` (re-read with `plutil -p` 2026-10-22, committed
  and clean) carries `iCloud.com.haoranwei.Cadence` with CloudKit, sandbox and the app group, and
  no push key — see the T-3152 note at the top.
- The four companion documents this file points at all exist: `docs/apple-release-readiness.md`,
  `docs/privacy.html`, `docs/support.html`, `docs/app-review-notes.md`.

**Not verified here, and still the owner's:** whether App Store Connect → Business → Legal Entity
Name matches the Copyright field above, whether the support and privacy URLs are publicly
reachable, and anything that needs an archive or an App Store Connect session.
