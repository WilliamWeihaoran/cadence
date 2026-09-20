# R51: privacy manifest and entitlement audit

```text
Tree read: 1857938
Dirty files: 0 at source snapshot
Confidence: direct source mismatches verified; binary behavior and App Review unmeasured
```

## P1 release fix: shared UserDefaults reasons are missing

**MEASURED-SOURCE; reachable today.** The app declares only `CA92.1` for UserDefaults at
[PrivacyInfo.xcprivacy:64](/Users/williamwei/Desktop/Projects/Cadence/Cadence/PrivacyInfo.xcprivacy:64).
The widget declares no UserDefaults category at
[its manifest:11](/Users/williamwei/Desktop/Projects/Cadence/CadenceWidgets/PrivacyInfo.xcprivacy:11).
Both compile and use app-group defaults: palette reads at
[Theme.swift:180](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/Theme.swift:180) and
completion/reload state at
[CadenceWidgetRefreshCenter.swift:120](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceWidgetRefreshCenter.swift:120).
The widget's explicit source membership is in `Cadence.xcodeproj/project.pbxproj:714,719`.

**DOCUMENTED:** `CA92.1` covers app-only preferences; `1C8F.1` covers preferences shared within
an App Group. [Apple's approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc).

**Suggested fix:** retain app-only coverage, add `1C8F.1` to the app, and add UserDefaults coverage
to the widget for its group access. Account for the widget's `.standard` fallback when selecting
its complete reason set. Update
[AppStoreReviewReadinessTests.swift:16](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/AppStoreReviewReadinessTests.swift:16)
and `:25`: they currently require exactly the incomplete app reason and an empty widget category.
This is a declaration defect **and** a test that enforces it, not missing coverage alone.

Confirm:

```sh
rg -n 'CA92|1C8F|CategoryUserDefaults' Cadence/PrivacyInfo.xcprivacy CadenceWidgets/PrivacyInfo.xcprivacy
rg -n 'suiteName|sharedDefaults' Cadence/Shared/Theme.swift Cadence/Services/CadenceWidgetRefreshCenter.swift
sed -n '1,29p' CadenceTests/AppStoreReviewReadinessTests.swift
```

## Required-reason sweep

**MEASURED-SOURCE:** `inventory.rb` scans all three product source trees. The historical “37
AppStorage places” is stale: there are 75 occurrences after excluding full-line comments. This
counts source spellings, not 75 executed reads or 75 distinct keys.

| Category | Source observation | Assessment |
| --- | --- | --- |
| UserDefaults | `CadenceDefaults.store`, SwiftUI `@AppStorage`, shared palette and widget state | App-only reason fits own-domain use; shared reason missing as above. |
| File timestamps | `PersistenceController.swift:706,716` reads backup-folder creation dates; `macOS/Services/CadenceMCPRefreshCoordinator.swift:27` reads the app-group marker's modification date | `C617.1` matches these container-local uses. `attributesOfItem` at `PersistenceController.swift:1142` reads item size, not filesystem free space. No direct widget timestamp API found; do not invent a widget use from SwiftData alone. |
| System boot time | No direct `systemUptime` or `mach_absolute_time` hit | No source basis to add a reason. Not a binary-negative guarantee. |
| Disk space | No listed capacity/system-size/statfs/statvfs call found | File size is not available disk space. No source basis to add this category. |
| Active keyboards | No `activeInputModes` hit | Text editing or displaying a keyboard alone does not demonstrate this API use. |

The API inventory and container-metadata reason are checked against
[Apple's category list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
**REASONED boundary:** SwiftUI storage wrappers perform the app's preferences use; linking
SwiftData, EventKit or WidgetKit does not establish that Cadence itself reads every internal OS
signal those frameworks might use. Closed Apple framework internals were not inspected.

**MEASURED-SOURCE:** the app and widget have no package product dependencies; only
`CadenceMCPServer` links MCP (`project.pbxproj:426,490,513`). The resolved graph pins NIO 2.99.0,
but a package in `Package.resolved` is not evidence that it ships in `Cadence.app`. No app copy
phase embeds the MCP server. **REASONED:** NIO is outside the submitted app/widget graph here;
recheck actual archive contents. This audit did not fetch or certify NIO's implementation or a
separately distributed server binary. If packaging changes, inspect each linked SDK's actual
required-API use and manifest instead of adding speculative categories to Cadence.

Apple requires declarations in the responsible executable/library bundle and does not let an SDK
rely on its host's manifest. The published required-reason upload rule lists iOS/iPadOS and other
mobile platforms; do not turn that into an independently established macOS rejection prediction.
[Apple required-reason policy](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api?language=objc).

## Privacy labels: storage is not automatically collection

**DOCUMENTED:** Apple's label concerns off-device transmission permitting developer/partner access
beyond servicing the request. Local processing is not collection; Apple-only collection is not
the developer's disclosure. Optional functionality alone does not satisfy all optional-disclosure
conditions. Generic free text uses Other User Content.
[Apple privacy-label definitions](https://developer.apple.com/app-store/app-privacy-details/).

**MEASURED-SOURCE:** the blanket “collected, linked” identity claims in
[apple-release-readiness.md:32](/Users/williamwei/Desktop/Projects/Cadence/docs/apple-release-readiness.md:32)
are not justified by this data flow: `AppleAccountManager.swift:31,55` saves profile fields into
local defaults; its implementation is macOS-only. No profile upload to a Cadence backend or
archive field for that profile was found. **REASONED:** reclassify those claims from demonstrated
collection to owner verification; local identity storage alone does not warrant them. Private
CloudKit sync likewise does not by itself prove that the developer collects every stored field.
Verify actual access/retention practices rather than treating “private” as a blanket exemption.

**MEASURED-SOURCE:** optional AI sends the selected **note**, not merely highlighted text: title,
container name and the full trimmed body at
[AIActionService.swift:82](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/AI/AIActionService.swift:82)
and [AIProvider.swift:179](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/AI/AIProvider.swift:179),
to `/v1/responses` (`:102,150`). No explicit retention control appears in the request DTO at `:190`.
**REASONED:** keep Other User Content under review for this genuine third-party transfer; establish
provider retention and identity linkage before finalizing the label. A user-supplied API key or
button press is not proof of no collection. Do not remove that label just because CloudKit is
private. Account identity is not automatically transmitted with this prompt.

**MEASURED-SOURCE:** widgets read the local app-group store, with CloudKit disabled, rather than
fetching remote data (`TodayTasksWidget.swift:127`). The readiness table's “snapshots” is a
presentation description, not a separate persisted snapshot database. Calendar/reminder access
is permission-gated; a local read alone is not label collection. The independently installed MCP
server can expose store content to its caller; do not equate local IPC with proved cloud retention,
or claim privacy clearance for an external AI client the repository does not control.

## Entitlements: one platform discrepancy to verify

**MEASURED-SOURCE:** one shared entitlements file contains
`com.apple.developer.aps-environment` (`Cadence.entitlements:10`), and no `aps-environment` key.
iOS registers for remote notifications (`iOS/iOSAppDelegate.swift:33` includes failure handling).
**DOCUMENTED:** iOS uses `aps-environment`; the prefixed key is macOS's.
[Apple APNs entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment?changes=_7).
**P1 verification candidate, not a proved shipping failure:** inspect the signed iOS archive and
its provisioning profile. Xcode can synthesize entitlements; source plist absence does not prove
signed-binary absence. If missing, use platform-correct entitlement configuration and add an
artifact check. Setting the value to `production` on the wrong key would not fix it.

**MEASURED-SOURCE inventory:** CloudKit container/service, app group, sandbox, outbound network
and Calendar have live consumers. Sign in with Apple is used on macOS but unused on the current
iOS surface, although both use the same file. Scope it by platform if unnecessary. User-selected
file access is configured via `ENABLE_USER_SELECTED_FILES = readwrite` (`project.pbxproj:808`),
so its absence from the checked-in plist is **not** a missing-entitlement finding.
[Apple user-selected-file entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write).
Calendar and Reminders purpose strings are both configured at `project.pbxproj:813`; do not invent
a separate Reminders entitlement merely because only the Calendar sandbox key is named.
Widgets use their app-group entitlement and intentionally do not own CloudKit synchronization.

## Release evidence still owed

**REASONED checklist:** on the exact iOS and macOS release archives, inspect embedded manifests,
Xcode's aggregated privacy report, executable/SDK membership, generated Info.plist and signed
entitlements (`codesign -d --entitlements :- <actual-app-path>`). Review real App Store Connect
answers against the verified data flows. Upload validation/App Review can settle Apple's response
to that artifact, not prove undocumented data retention or absence of every runtime use. No
submission, profile, private account or signed archive was accessed in this audit.
