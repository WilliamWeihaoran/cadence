# Cadence Apple Release Readiness

Last updated: September 21, 2026

This checklist maps Cadence's current macOS app behavior to Apple's App Review, privacy, signing, sandboxing, and notarization expectations. Use it before every App Store Connect upload or direct Developer ID release.

## Release Position

- Primary channel: Mac App Store.
- Secondary channel: direct Developer ID distribution with notarization.
- iOS/iPadOS: built, not distributed. `Cadence/iOS/` is a large real surface rather than a stub and the project builds `iphoneos iphonesimulator macosx`, but no iOS build is submitted to any channel today, and the App Store Connect fields in `docs/app-store-submission-packet.md` are macOS-only on purpose. The iOS build is in the verification commands below regardless, because the macOS test target never compiles `Cadence/iOS/`: without it, a break in half of this repository survives every check the release process runs. Revisit the whole document, not just this bullet, the day iOS becomes a channel.
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

Use this table when filling App Store Connect privacy details. If implementation changes, update this file, `docs/app-store-submission-packet.md`, `docs/privacy.html`, `docs/app-review-notes.md`, `Cadence/PrivacyInfo.xcprivacy`, and `CadenceWidgets/PrivacyInfo.xcprivacy` together.

**The axis is transmission, not storage (T-1311).** Apple defines *collect* as transmitting data off the device in a way that lets you or your third-party partners access it for longer than the time needed to service the request in real time. Writing something to disk is not collection, and neither is writing it to the user's **own private** CloudKit database, which the developer cannot read. Every row below was re-derived on that axis; the two it moved, it moved in opposite directions.

| Data or access | What actually leaves the device | App Store label posture |
| --- | --- | --- |
| Name | Nothing. Sign in with Apple's `givenName`/`familyName` are written to local `UserDefaults` by `AppleAccountDefaultsStorage` (`macOS/Services/AppleAccountManager.swift`) and read from nowhere else. There is no Cadence backend, no upload, and no CloudKit record for the profile | **Not collected.** Apple's own collection during the sign-in flow is Apple's, not the developer's |
| Email address | Nothing. Same local-defaults store, whether Apple returns a real address or a private relay one | **Not collected**, same reasoning |
| User ID | Nothing. The Apple user identifier is the key of that same local profile. It is not in `CadenceSchema`, so it does not even sync | **Not collected**, same reasoning |
| User content | The **optional AI action**, and only that: note title, the owning list's name, and the note's full trimmed body, to OpenAI. Everything else — tasks, goals, habits, links, tags, settings — stays on device or in the user's private CloudKit database | **Collected: Other User Content, app functionality.** This one row carries the whole label, and it is earned by the transfer below rather than by storage. Do not delete it when "simplifying" |
| Calendar access | Nothing. EventKit reads happen on device; writes go to the user's own Apple Calendar | Permission-gated app functionality, not collection; describe in review notes and privacy policy |
| iCloud/CloudKit | App data, to the user's **private** database. Not a Cadence-operated service and not developer-readable | App functionality; explain in privacy policy. Not developer collection on the evidence in this repository — see the caveat below |
| Diagnostics/backups | Nothing. Migration/recovery backups and error text are local files and local strings | App functionality; no tracking |
| Widgets | Nothing. The extension reads the local app-group container; CloudKit is off in the widget process (`TodayTasksWidget`) | No collected data by the widget extension, and its manifest declares none |
| MCP server | Store content, to whatever MCP client the user installed — but `CadenceMCPServer` is **not embedded in the submitted app** (pinned by `appTargetDoesNotEmbedMCPServerOrMCPPackage`), so it is outside this label | Out of scope for the app's label while that stays true |

### The one transfer, named against the code

Read before answering the User Content question, because it is the only thing in Cadence that transmits anything anywhere:

- **Trigger.** The user saves their own OpenAI API key and runs Summarize or Extract Tasks on a note. Nothing else in the app reaches the network (`URLSession` appears in `Cadence/Services/AI/` and nowhere else in `Cadence/`).
- **Fields.** `AIActionService.noteContext` builds `AITextNoteContext(title:content:containerName:)` — the note's display title, its **full** trimmed body, and the owning area or project's name. `AIProvider.prompt(for:)` renders all three into the request's `input`. It is the whole note, not a highlighted selection.
- **Destination.** `POST https://api.openai.com/v1/responses`, `Authorization: Bearer <the user's key>`. No Cadence identity, no Apple user identifier and no device identifier is attached.
- **Linked or not.** The request carries no Cadence account field, but the key is the user's own OpenAI credential, so the content is associated with an account the user holds. Answer **linked** — that is the conservative side and it is true of the provider's copy.
- **Retention, read 2026-09-21 from OpenAI's own data-controls guide.** API inputs and outputs are not used to train models unless the account opts in; abuse-monitoring logs are kept up to about 30 days. Separately, `/v1/responses` **stores the response object — input included — by default**, for at least 30 days, unless the request sets `store: false` or the organisation has Zero Data Retention (which needs OpenAI's prior approval). **`OpenAIResponseRequest` has no `store` field**, so Cadence takes that default today (T-1322). The user's own OpenAI agreement governs, not this document.

### What this does not settle, and must not be claimed

- The three identity rows are decided from **source**: no upload path exists in this tree. Nobody has inspected a distribution archive or a network capture, so read them as "no transmitting code exists" rather than as a certified binary.
- `Cadence/PrivacyInfo.xcprivacy` still lists `NSPrivacyCollectedDataTypeName`, `…EmailAddress` and `…UserID` under `NSPrivacyCollectedDataTypes`, which now disagrees with this table. Over-declaring is not a rejection, but it is a public claim about this app that the code does not support. Aligning the manifest is the owner's call and is filed as T-1323.
- "Private CloudKit is not developer collection" is Apple's definition applied to this repository, not a statement about Apple's review outcome. Do not treat "private" as a blanket exemption for anything that later gains a shared or public database.

Current privacy manifest requirements:

- App target declares UserDefaults reasons `CA92.1` **and** `1C8F.1`.
- Widget extension declares UserDefaults reasons `CA92.1` **and** `1C8F.1`.
- Both binaries owe both: `1C8F.1` for the app-group suite (`Shared/Theme.swift`, `Services/CadenceWidgetRefreshCenter.swift` — the widget target compiles both), `CA92.1` for each binary's own domain, which is the `.standard` fallback those two helpers end in and, in the app, every `@AppStorage` and `CadenceDefaults.store` (T-1310).
- App target declares file timestamp reason `C617.1`.
- Widget extension declares file timestamp reason `C617.1`.
- `NSPrivacyTracking` is false in app and widget manifests.
- Tracking domains are empty.
- Pinned by `AppStoreReviewReadinessTests`, which asserts the required reasons as a floor and Apple's published approved list as a ceiling. Whether the archive Xcode actually submits carries these manifests is answered only by a real submission.

## Entitlement Justifications

| Entitlement or setting | Target | Reason |
| --- | --- | --- |
| App Sandbox | App and widgets | Required for Mac App Store and appropriate for local productivity data |
| Application group `group.com.haoranwei.Cadence` | App and widgets | Shares the SwiftData store and widget snapshots between app and widgets |
| iCloud container `iCloud.com.haoranwei.Cadence` | App | Syncs Cadence data through the user's private CloudKit database |
| CloudKit service | App | Supports private iCloud sync. **Production schema deployed 2026-09-05** — promoted from Development in the CloudKit Console, confirmed by the console's own "Schema promoted to production" notice and by Indexes/Record Types/Security Roles dropping their "Modified" markers. A record type in Production can be deprecated but **never removed**, which is why this repo has no `SchemaMigrationPlan`: adding a new `@Model` is safe *for the local store*, changing a stored property on a synced one is not — and neither is safe for **sync** until the deploy below lands. One deliberate accident rode along — `CD_Exam`, a record type with no model behind it, present in Development from before this repository's history. Keeping it was the user's decision on 2026-09-05: it is inert, and the alternative was resetting the Development environment, which would have destroyed real task data that a development-signed build had put there. **A new `@Model` owes a second deploy, and nothing in the build will say so (T-1290).** SwiftData creates a record type in Development automatically as a debug build runs and in Production never — press *Deploy Schema Changes* again, or TestFlight and App Store builds talk to a schema that has no `CD_<NewModel>` — and the damage is **not** confined to that one type, which is what this sentence used to claim (R49, below). **Owed now: `CD_SidebarLayoutPreference`** (T-1274, added 2026-09-18) and **`CD_LookPreference`** (T-1307, added 2026-09-20 — the synced accent palette, sidebar tints and task-surface sort settings). One press covers both. **Press it before distributing a build that contains either, and verify the schema after.** The cost is NOT confined to the missing type: Codex R49 (2026-09-20) reads Apple's TN3164 as documenting that a missing Production schema — a record type *or a field* — can fail mirroring initialisation and abort exports for the **whole store**, so "nothing syncs at all" does not rule out a missing deploy; it is one of the first things to suspect. That is documented framework behaviour rather than a failure measured on these devices, and it is why adding the property to an already-deployed model would not have been safer — a new field is the same mismatch as a new type. Locally nothing breaks either way: each type reaches the app as zero rows, the same shape as "nothing has synced yet", and both features fall back to the device-local defaults they mirror. **Do not "fix" a red sync test by taking a model back out of `CadenceSchema`** — for a type already in use that risks local migration failure and leaves rows the app can no longer reach, which is bad enough on its own; that it also *deletes* the CloudKit records is **not** established, and this cell's old flat "destroys data" overstated it. For a new type it is still the wrong shape (R49) |
| APS environment | App | Allows CloudKit's silent remote notifications, which tell the app its private database changed. Registered for at launch on both platforms (`CadenceRemoteNotificationRegistrar`, called once per platform from the app delegate; iOS gained its delegate in T-626 and the `remote-notification` background mode with it). **The key is spelled per platform and therefore lives in two files** (T-1309): `com.apple.developer.aps-environment` in `Cadence/Cadence.entitlements` for macOS, bare `aps-environment` in `Cadence/Cadence-iOS.entitlements` for iOS/iPadOS via `CODE_SIGN_ENTITLEMENTS[sdk=iphone*]`. One shared file could only ever carry one spelling, and until T-1309 it carried macOS's, so signed iOS builds had no push entitlement at all. A registration the system refuses is no longer silent: it degrades the Settings > iCloud Sync card on both platforms. No alert/sound/badge payloads, no Cadence-operated sender, and no user-facing push notifications — task and habit reminders are *local* notifications through `UNUserNotificationCenter` |
| Calendar personal information | App | Reads Apple Calendar events and creates, updates, or deletes calendar events when requested; these writes are independent of Cadence tasks, which do not attach to a calendar event |
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
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' -derivedDataPath /tmp/cadence-release-$$ build
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project Cadence.xcodeproj -scheme Cadence -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/cadence-release-ios-$$ build
./scripts/test-host-lock.sh acquire 5400 || exit 1
trap './scripts/test-host-lock.sh release' EXIT INT TERM
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project Cadence.xcodeproj -scheme Cadence -destination 'platform=macOS' -derivedDataPath /tmp/cadence-release-$$ -only-testing:CadenceTests/AppStoreReviewReadinessTests
```

The third command is the one that ships nothing. It compiles `Cadence/iOS/` and it is here because
nothing else in this checklist does: the macOS build and the macOS test target both skip that tree
entirely, so an iOS-only compile break is invisible to a release that runs only the other two. It
needs no simulator — `generic/platform=iOS Simulator` builds for the simulator SDK without booting
a device — and `AppStoreReviewReadinessTests` fails if this document stops carrying it.

The `-derivedDataPath` is required, not decorative: the default path is the one Xcode and any
running debug build share, and a build into it deletes `Build/Products/` under them. The two
`build` actions need nothing further; **the `test` action must take `scripts/test-host-lock.sh`**
whenever anything else on the machine may be running a macOS test, because the private path
isolates the build and not the app-group container a test host writes to. Bare `xcodebuild` with a
private path is deliberate here rather than `scripts/xcb.sh`: this is the invocation someone copies
into a release checklist, and it is pinned by `CadenceBuildInvocationHygieneTests`.

For direct distribution, also follow `docs/direct-distribution-runbook.md`.
