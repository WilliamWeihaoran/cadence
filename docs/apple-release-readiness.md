# Cadence Apple Release Readiness

Last updated: October 27, 2026. The CloudKit schema obligation, the widget entitlement row and
the version numbers were re-measured against HEAD that day; see "Checked Against The Tree" at the
foot, which carries both readings and says which of the older ones were wrong. The document's
**rewrite** for iOS becoming a shipping channel is a separate, larger job and is T-6410, which the
owner has placed after the RC; this pass corrected facts and changed no scope.

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

**The axis is transmission, not storage (T-1311), and here is Apple's sentence rather than a paraphrase of it (T-1323).** From *App privacy details on the App Store* (`https://developer.apple.com/app-store/app-privacy-details/`, the "Data collection" section, read 2026-09-27):

> "Collect" refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time.

That is the only definition Apple publishes; *Describing data use in privacy manifests* supplies no second one and links back to this page for `NSPrivacyCollectedDataTypeLinked`, so the manifest's `NSPrivacyCollectedDataTypes` rows and the App Store Connect answers are decided by the same sentence. The same page applies the test to a named row instead of leaving it abstract — Payment Info: *"If your app uses a payment service, the payment information is entered outside your app, and you as the developer never have access to the payment information, it is not collected and does not need to be disclosed."* Writing something to disk is not collection, and neither is writing it to the user's **own private** CloudKit database, which the developer cannot read. Every row below was re-derived on that axis; the two it moved, it moved in opposite directions.

| Data or access | What actually leaves the device | App Store label posture |
| --- | --- | --- |
| Name | Nothing. Sign in with Apple's `givenName`/`familyName` are written to local `UserDefaults` by `AppleAccountDefaultsStorage` (`macOS/Services/AppleAccountManager.swift`) and read from nowhere else. There is no Cadence backend, no upload, and no CloudKit record for the profile | **Not collected.** Apple's own collection during the sign-in flow is Apple's, not the developer's |
| Email address | Nothing. Same local-defaults store, whether Apple returns a real address or a private relay one | **Not collected**, same reasoning |
| User ID | Nothing. The Apple user identifier is the key of that same local profile. It is not in `CadenceSchema`, so it does not even sync | **Not collected**, same reasoning |
| User content | The **optional AI action**, and only that: note title, the owning list's name, and the note's full trimmed body, to OpenAI. The body goes whole and unstripped, so everything the user typed into it goes with it — YAML frontmatter, inline `#tags`, and `[[task:UUID\|Title]]` embeds, which carry the embedded task's title and its Cadence record UUID. The **records** — `Tag`, task, goal, habit, link rows and settings — stay on device or in the user's private CloudKit database, as does any note never run through an AI action | **Collected: Other User Content, app functionality.** This one row carries the whole label, and it is earned by the transfer below rather than by storage. Do not delete it when "simplifying" |
| Calendar access | Nothing. EventKit reads happen on device; writes go to the user's own Apple Calendar | Permission-gated app functionality, not collection; describe in review notes and privacy policy |
| iCloud/CloudKit | App data, to the user's **private** database. Not a Cadence-operated service and not developer-readable | App functionality; explain in privacy policy. Not developer collection on the evidence in this repository — see the caveat below |
| Diagnostics/backups | Nothing. Migration/recovery backups and error text are local files and local strings | App functionality; no tracking |
| Widgets | Nothing. The extension reads the local app-group container; CloudKit is off in the widget process (`TodayTasksWidget`) | No collected data by the widget extension, and its manifest declares none |
| MCP server | Store content, to whatever MCP client the user installed — but `CadenceMCPServer` is **not embedded in the submitted app** (pinned by `appTargetDoesNotEmbedMCPServerOrMCPPackage`), so it is outside this label | Out of scope for the app's label while that stays true |

### The one transfer of user content, named against the code

Read before answering the User Content question, because it is the only thing in Cadence that transmits anything **of the user's** anywhere. It is not the only thing that opens a connection: **Test Connection** in Settings > AI is a second live request to the same endpoint with the same key, carrying two fixed English literals and nothing of the user's. It is named in the last bullet below rather than left out, because "Cadence contacts OpenAI only when you run an AI action" was false on its face wherever it was written (T-3036).

- **Trigger.** The user saves their own OpenAI API key and runs Summarize or Extract Tasks on a note. Nothing else in the app reaches the network at all (`URLSession` appears in `Cadence/Services/AI/` and nowhere else in `Cadence/`, `CadenceWidgets/` or `CadenceMCPServer/`), and nothing but this action and Test Connection reaches it with a request of any kind.
- **Fields.** `AIActionService.noteContext` builds `AITextNoteContext(title:content:containerName:)` — the note's display title, its **full** trimmed body, and the owning area or project's name. `AIProvider.prompt(for:)` renders all three into the request's `input`. It is the whole note, not a highlighted selection.
- **Destination.** `POST https://api.openai.com/v1/responses`, `Authorization: Bearer <the user's key>`. No Cadence identity, no Apple user identifier and no device identifier is attached.
- **Linked or not.** The request carries no Cadence account field, but the key is the user's own OpenAI credential, so the content is associated with an account the user holds. Answer **linked** — that is the conservative side and it is true of the provider's copy.
- **Retention. Cadence opts out of it (T-1322).** `OpenAIResponseRequest.store` is `false` and is always encoded, so every AI request tells OpenAI not to keep the response object. The default matters because it is *not* the one this endpoint takes on its own: OpenAI's published OpenAPI schema for `CreateResponse` (`openai/openai-openapi`, `openapi.yaml`, read 2026-09-21) gives `store` `default: true` and the description *"If set to true, response data will be stored for at least 30 days"* — and the stored object includes the input, i.e. the note. `/v1/chat/completions` defaults the other way in the same file, which is why the endpoint choice alone had decided this. Zero Data Retention would reach the same place but is an org-level control needing OpenAI's prior approval, so it is not a route Cadence can take for a user. **What opting out does not reach**, and the docs are read rather than assumed on both: API inputs and outputs are not used to train models unless the account opts in, and abuse-monitoring logs are kept up to about 30 days whatever `store` says. **The cost, stated because a reviewer will ask**: an unstored request does not appear in the user's own OpenAI dashboard logs, which was their only route to auditing what Cadence sent — so the Settings > AI card and `docs/privacy.html` now say what is sent and that it is not retained. The user's own OpenAI agreement governs, not this document.

- **The second request, and why it moves no answer (T-3036).** `AISettingsManager.testConnection()` (`Cadence/Services/AI/AISettingsManager.swift`) builds the real provider from the stored key and awaits `summarizeNote(AITextNoteContext(title: "Connection Test", content: "Reply with a short confirmation."))` — a full `POST https://api.openai.com/v1/responses` with `Authorization: Bearer <the user's key>`, down the same `send` path, from a button on each platform (`macOS/Views/SettingsSectionViews.swift`, `iOS/iOSSettingsTemplateAndListSections.swift`), both `.disabled(!hasAPIKey || isTestingConnection)`. The body is those two English literals, a `Container: None` line, and the fixed Summarize instructions: no note, no title of the user's, no container, no identifier. **So the User Content row above is still earned by the AI action alone and is still the only row** — what changed is the prose, which used to say OpenAI is contacted *only* when an AI action runs. `docs/privacy.html` and `CadenceAISettingsCopy.keyPrivacyDisclosure` now name both situations.

### What this does not settle, and must not be claimed

- The three identity rows are decided from **source**: no upload path exists in this tree. Nobody has inspected a distribution archive or a network capture, so read them as "no transmitting code exists" rather than as a certified binary.
- **The manifest now agrees with this table (T-1323).** `Cadence/PrivacyInfo.xcprivacy` declares exactly one collected type, `NSPrivacyCollectedDataTypeOtherUserContent`; the `Name`, `EmailAddress` and `UserID` rows were removed because none of them meets the transmission test quoted above. Pinned by `appPrivacyManifestDeclaresExpectedDataAndAPIs()` — an exact set, so re-adding a row fails — and by `theOnlyOutboundNetworkSurfaceIsTheAIProvider()`, which holds the premise that `URLSession` reaches only `Cadence/Services/AI/` — swept over `Cadence/`, `CadenceWidgets/` **and** `CadenceMCPServer/` since T-3038, each with its own non-vacuity floor, because the bullet's neighbours are the widget and MCP rows and the sweep used to walk only the first of the three. Both are in `CadenceTests/AppStoreReviewReadinessTests.swift`.
- **One manifest ships on both platforms, and that is a project fact rather than a choice.** `Cadence` is a single app target with `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, and `Cadence/` is a synchronized root group whose only membership exceptions are `Info.plist` and the `AGENTS.md` files — so this one file lands in the iOS bundle too. `AppleAccountProfile` is inside `#if os(macOS)` and does not exist on iOS at all, so the old rows were a claim iOS could not even have made. There is no per-platform manifest to diverge into, and after the removal there is no reason to want one.
- **The App Store Connect answers are a separate surface and did not move with the manifest.** The manifest feeds a privacy *report* the developer reads — *"Refer to this report when you provide your app's privacy details in App Store Connect"* — and no upload validation exists for `NSPrivacyCollectedDataTypes`. Answering Name, Email Address and User ID as not collected in App Store Connect is an **owner action**, and until it is done the product page and the bundle disagree in the direction this ticket did not choose.
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
| CloudKit service | App | Supports private iCloud sync. **Production schema deployed 2026-09-05** — promoted from Development in the CloudKit Console, confirmed by the console's own "Schema promoted to production" notice and by Indexes/Record Types/Security Roles dropping their "Modified" markers. A record type in Production can be deprecated but **never removed**, which is why this repo has no `SchemaMigrationPlan`: adding a new `@Model` is safe *for the local store*, changing a stored property on a synced one is not — and neither is safe for **sync** until the deploy below lands. One deliberate accident rode along — `CD_Exam`, a record type with no model behind it, present in Development from before this repository's history. Keeping it was the user's decision on 2026-09-05: it is inert, and the alternative was resetting the Development environment, which would have destroyed real task data that a development-signed build had put there. **A new `@Model` owes a second deploy, and nothing in the build will say so (T-1290).** SwiftData creates a record type in Development automatically as a debug build runs and in Production never — press *Deploy Schema Changes* again, or TestFlight and App Store builds talk to a schema that has no `CD_<NewModel>` — and the damage is **not** confined to that one type, which is what this sentence used to claim (R49, below). **DEPLOYED AND VERIFIED 2026-10-02 by the owner, in the CloudKit Console, against Production — this paragraph's "owed now" list was already two-thirds stale when it was read, and the way it was stale is the part worth keeping.** Measured from the Console: `CD_SidebarLayoutPreference` and `CD_LookPreference` were **already in Production** and did not appear in the deployment diff at all; the only record type owed was `CD_NoteTemplatePreference`, which deployed as *Create 1 record type, create 13 indexes, modify `_world`/`_icloud`/`_creator`*. **But the field was a separate and nearly missed obligation, and this paragraph's own reasoning is what hid it.** It argued the field "costs nothing extra here only because `CD_LookPreference` is undeployed in its entirety, so the column ships with the type on its first deploy" — and that premise was false: the type was already live, so `calendarPresentationRaw` was a new field on a **deployed** type, which R49 reads as the same mismatch as a missing type. **It was absent from Production AND from Development, so it could not appear in any diff** — Development had 13 fields on `CD_LookPreference`, Production had 13, and the model has seven stored properties (`id`, `accentPaletteID`, `sidebarTabColorsRaw`, `taskPresentationRaw`, `calendarPresentationRaw`, `createdAt`, `updatedAt`). SwiftData materialises a CloudKit column only when a **debug** build runs and mirrors that entity, and no debug build had run since T-1347 added the property on 2026-09-27; the shipping app talks to Production and teaches Development nothing. The owner ran a debug build, set a work-hours window, watched Development go to **14 fields**, deployed again, and **confirmed Production at 14 fields**. **The lesson to carry, which is not the one this paragraph originally taught:** a missing field is invisible to the deployment diff in exactly the case where it is most dangerous — a new optional property on a live type, defaulting to empty, that no debug build has exercised. **Do not read an empty or short diff as "nothing owed"; count the model's stored properties against the Production record type's fields.** Historical list follows, now discharged in full: `CD_SidebarLayoutPreference` (T-1274, added 2026-09-18), **`CD_LookPreference`** (T-1307, added 2026-09-20 — the synced accent palette, sidebar tints and task-surface sort settings), **`CD_NoteTemplatePreference`** (T-1346, added 2026-09-27 — the customised note templates the owner writes in Settings), and **one new field on `CD_LookPreference`, `calendarPresentationRaw`** (T-1347, the work-hours window). One press covers all four. The field is not a smaller obligation than the types: R49 reads TN3164 as making a missing *field* the same mismatch as a missing record type. (This sentence used to go on to say the field cost nothing extra *because* `CD_LookPreference` was undeployed in its entirety. That premise was false — the type was already live — and it is cut rather than left standing, because it is the exact reasoning the paragraph above records as having nearly hidden the obligation.) **Press it before distributing a build that contains either, and verify the schema after.** The cost is NOT confined to the missing type: Codex R49 (2026-09-20) reads Apple's TN3164 as documenting that a missing Production schema — a record type *or a field* — can fail mirroring initialisation and abort exports for the **whole store**, so "nothing syncs at all" does not rule out a missing deploy; it is one of the first things to suspect. That is documented framework behaviour rather than a failure measured on these devices, and it is why adding the property to an already-deployed model would not have been safer — a new field is the same mismatch as a new type. Locally nothing breaks either way: each type reaches the app as zero rows, the same shape as "nothing has synced yet", and both features fall back to the device-local defaults they mirror. **Do not "fix" a red sync test by taking a model back out of `CadenceSchema`** — for a type already in use that risks local migration failure and leaves rows the app can no longer reach, which is bad enough on its own; that it also *deletes* the CloudKit records is **not** established, and this cell's old flat "destroys data" overstated it. For a new type it is still the wrong shape (R49) |
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

## Checked Against The Tree

Re-checked 2026-10-20 by reading the tree rather than this file. Two of these are the checks most
likely to be wrong at the moment a build is cut, so they are written as measurements with a date on
them rather than as standing claims.

- **No new CloudKit schema obligation since the 2026-10-02 deploy.** The deploy that discharged
  `CD_NoteTemplatePreference` and `calendarPresentationRaw` was 2026-10-02. Every commit touching
  `Cadence/Models/` since then was read: four commits, none of them adding a `var`, an `@Attribute`
  or an `@Relationship` to a `@Model`. So nothing is owed, measured the way the paragraph above
  says to measure it — against the model's stored properties, not against a deployment diff.
  **This goes stale the moment someone adds a stored property.** Redo it, do not re-read it.
  **Redone 2026-10-27 at `d77ecc2b`, and still nothing is owed.** Measured as a diff of the tree
  against the 2026-10-02 deploy rather than by re-reading the bullet above: `@Model` declarations
  across `Cadence/` are identical at both ends (24 of them), `Cadence/Services/CadenceSchema.swift`
  is byte-identical, and the only `var` added under `Cadence/Models/` in the whole range is
  `honorsDirection`, a computed property on an enum — not a stored property and not on a `@Model`.
  Five commits touched `Cadence/Models/` after the 2026-10-20 reading and none of them moved the
  schema. This matters for an internal TestFlight RC specifically, because a TestFlight build
  talks to **Production**: redo it again the day a stored property lands, which is the only event
  that can change the answer.
- **The widget extension now DOES carry the app's iCloud container** *(re-measured 2026-10-27;
  this bullet said the opposite until then, and the opposite was true when it was written)*.
  `CadenceWidgets/CadenceWidgets.entitlements` holds `com.apple.developer.icloud-services`
  (`CloudKit`) with container `iCloud.com.haoranwei.Cadence`, beside the App Group and the sandbox
  flag, and carries neither push spelling. That is T-3152 landing: the owner's developer-portal
  step was taken, and it is visible from here without a portal session — all four cached Team
  Store (distribution) profiles, Mac and iOS, app and widget, carry
  `com.apple.developer.icloud-container-identifiers` = `iCloud.com.haoranwei.Cadence` with
  `icloud-services` `*`. So the capability costs an archive nothing (T-7100 confirmed the same
  thing from inside both real archives). Two things this does **not** change: the extension's
  containers still do not mirror, which is T-3227 and still open, so a widget write reaches other
  devices only when the app next runs an export pass; and the "iCloud container" row in the table
  above still says "App", which is now understating the tree rather than describing it. The four
  cached **development** profiles carry no container — that is a local signed-build question, not
  a distribution one, and Xcode regenerates them.
- The app's privacy manifest declares `NSPrivacyCollectedDataTypeOtherUserContent` and no other
  collected type, which is what the privacy-label table above claims.
- `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` on both app configurations;
  `MACOSX_DEPLOYMENT_TARGET = 26.1`; `MARKETING_VERSION = 1.0`; **`CURRENT_PROJECT_VERSION = 25`**
on the two shipping targets (re-read per target 2026-10-27; it said 23 here until then, and T-7100
bumped 24 → 25 on 2026-10-26. `CadenceTests`/`CadenceUITests` still read 24 and `CadenceMCPServer`
reads 1 — none of the three ships, so a whole-file grep of this key legitimately finds three
different values and is not the check to write).

**The 2026-10-20 "do not archive" warning that stood here is DISCHARGED** (re-checked 2026-10-27).
It said the shared checkout held uncommitted widget-entitlement changes that did not match what
T-3152 decided — an empty `icloud-container-identifiers` array plus both push spellings, which
`AppStoreReviewReadinessTests.widgetEntitlementsIncludeSandbox` asserts are absent. None of that
is true of the tree any more: the committed `CadenceWidgets/CadenceWidgets.entitlements` holds the
**named** container with CloudKit and **no** push key of either spelling, and
`git status` shows the file clean. The condition the warning named no longer exists, so the
warning is removed rather than left to stop an archive on a premise that has expired.

**Not verified here:** nobody ran the verification commands above as part of this check, and
nothing in a document can establish that they were run. Anything needing an archive, a signed
build, a second device or an App Store Connect session is unverified and is the owner's.
