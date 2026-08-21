# Cadence Apple Release Readiness

Last updated: June 17, 2026

This checklist maps Cadence's current macOS app behavior to Apple's App Review, privacy, signing, sandboxing, and notarization expectations. Use it before every App Store Connect upload or direct Developer ID release.

## Release Position

- Primary channel: Mac App Store.
- Secondary channel: direct Developer ID distribution with notarization.
- Minimum macOS version: 26.1. This is intentional for the current release and limits App Store availability to Macs that can run macOS 26.1 or later.
- Public category: Productivity.
- Current monetization: none. Cadence has no in-app purchases, subscriptions, ads, paid unlocks, or external purchase links.
- Current tracking posture: no tracking, no ad network, and no third-party analytics.
- Current reviewer support docs: `docs/privacy.html`, `docs/support.html`, and `docs/app-review-notes.md`.

## App Store Review Checklist

- Safety: Cadence is a personal productivity app with user-created tasks, notes, goals, habits, links, and Calendar-linked planning data. It does not publish user-generated content to a public service.
- Performance: test the final archive for launch, settings navigation, Calendar permission denial/grant, CloudKit fallback/recovery, widget loading, deep links, and the account/data deletion flow.
- Business: keep App Store metadata clear that AI is optional and requires the user's own OpenAI API key. If paid features are added later, use Apple's in-app purchase system for App Store distribution.
- Design: verify the main macOS surfaces remain usable with keyboard navigation, resizing, dark appearance, Settings, sidebar navigation, popovers, and widgets.
- Legal/privacy: keep privacy manifests, App Store privacy labels, privacy policy, support URL, Calendar usage text, encryption declaration, and review notes in sync with shipped behavior.

## Privacy Label Source Of Truth

Use this table when filling App Store Connect privacy details. If implementation changes, update this file, `docs/privacy.html`, `docs/app-review-notes.md`, and `Cadence/PrivacyInfo.xcprivacy` together.

| Data or access | Cadence behavior | App Store label posture |
| --- | --- | --- |
| Name | Optional Sign in with Apple profile name if Apple returns it | Collected, linked to user, app functionality |
| Email address | Optional Sign in with Apple private relay or email if Apple returns it | Collected, linked to user, app functionality |
| User ID | Optional Apple user identifier for Cadence identity | Collected, linked to user, app functionality |
| User content | Tasks, notes, documents, goals, habits, saved links, tags, calendar-link metadata, and app settings | Collected, linked to user, app functionality |
| Calendar access | Apple Calendar events are shown and Cadence-created scheduled task events may be created, updated, or deleted when the user asks | Permission-gated app functionality; describe in review notes and privacy policy |
| iCloud/CloudKit | Cadence may sync app data through the user's private iCloud database | App functionality; explain in privacy policy |
| OpenAI API use | Optional AI actions send selected note content only after the user runs an AI command and saves their own API key | Disclose as optional third-party processing of selected user content |
| Diagnostics/backups | Local migration/recovery backups and local error messages remain on device | App functionality; no tracking |
| Widgets | Widgets read Cadence snapshots from the app group container | No collected data by widget extension |

Current privacy manifest requirements:

- App target declares UserDefaults reason `CA92.1`.
- App target declares file timestamp reason `C617.1`.
- Widget extension declares file timestamp reason `C617.1`.
- `NSPrivacyTracking` is false in app and widget manifests.
- Tracking domains are empty.

## Entitlement Justifications

| Entitlement or setting | Target | Reason |
| --- | --- | --- |
| App Sandbox | App and widgets | Required for Mac App Store and appropriate for local productivity data |
| Application group `group.com.haoranwei.Cadence` | App and widgets | Shares the SwiftData store and widget snapshots between app and widgets |
| iCloud container `iCloud.com.haoranwei.Cadence` | App | Syncs Cadence data through the user's private CloudKit database |
| CloudKit service | App | Supports private iCloud sync |
| APS environment | App | Allows CloudKit's silent remote notifications, which tell the app its private database changed. Registered for at launch on macOS (`CadenceRemoteNotificationRegistrar`). No alert/sound/badge payloads, no Cadence-operated sender, and no user-facing push notifications — task and habit reminders are *local* notifications through `UNUserNotificationCenter` |
| Calendar personal information | App | Reads Apple Calendar events and creates, updates, or deletes scheduled task events when requested |
| Reminders usage description (`NSRemindersFullAccessUsageDescription`) | App | Reads incomplete Apple Reminders for the Inbox and marks one complete when the user checks it off; Cadence never creates, edits, or deletes a reminder. Requested separately from Calendar access, and there is no reminders-specific App Sandbox entitlement to ship alongside it |
| Network client | App | Supports optional OpenAI API calls and CloudKit/network-backed app functionality |
| Sign in with Apple | App | Optional Cadence identity flow; local use and iCloud sync do not depend on it |
| User-selected read/write files | App build setting | Supports user-directed export/import or backup folder interactions inside the sandbox |
| Hardened Runtime | App build setting | Required for direct Developer ID distribution and appropriate for release signing |

## Third-Party SDK And Package Audit

- The app project uses Swift package dependencies for the MCP server/package graph. Before release, inspect the final archive to confirm which packages are embedded in the shipped app and widget products.
- If a commonly used third-party SDK from Apple's requirement list is added or embedded, require its privacy manifest and signature before App Store upload.
- Do not ship `CadenceMCPServer`, `plugins/cadence-mcp`, or other MCP integration artifacts inside the app bundle unless a release explicitly intends that integration and its privacy/security review is updated.

## App Store Reviewer Script

Use this as the human test script before upload and as the basis for App Review notes.

1. Launch Cadence on macOS 26.1 or later.
2. Confirm the main window opens without requiring sign-in.
3. Open Settings, Account. Verify Sign in with Apple is optional and that account deletion is available.
4. Open Settings, Data Safety. Verify privacy/support links open and Delete Account & Data is available.
5. Open Calendar settings. Deny Calendar access and verify the app remains usable; grant access and verify Calendar features can load.
6. Create a task, note, habit, goal, and saved link. Verify they remain local app content.
7. Save an OpenAI API key only on a test account if AI is being reviewed. Run an AI action from a selected note, then remove the key.
8. Add Cadence widgets and verify they show Cadence data or a clear unavailable state.
9. Delete account/data from Settings and verify local Cadence content, backups, pending restores, widget state, saved OpenAI key, and local Apple account profile are removed.

## Verification Commands

Run these checks before an App Store upload:

```sh
git diff --check
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' build
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' -only-testing:CadenceTests/AppStoreReviewReadinessTests
```

For direct distribution, also follow `docs/direct-distribution-runbook.md`.
