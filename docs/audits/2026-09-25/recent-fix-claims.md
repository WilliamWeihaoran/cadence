# R61: recent fix claims against the current source

```text
Tree read: c8735e4
Dirty files: 0
Source: committed snapshot created by scripts/agent-scratch.sh
Method: source, commit diffs, test bodies, and existing ledger evidence
Not run: builds, tests, mutations, app launches, provider requests, device sync
```

The dirty count is at capture, not at report delivery. Unrelated MCP, test and script changes
appeared afterwards and were excluded. References below
are repository-relative file:line at the captured commit. `MEASURED-SOURCE` means the text
was inspected, not that its runtime behavior was reproduced. `REASONED` marks conclusions
about hypothetical regressions or unexecuted cases. Historical test results in commits
were not rerun or credited as measurements from this audit.

## Bottom line

**MEASURED-SOURCE:** the eight requested commits still have their intended production
wiring. No new destructive regression was identified in the bounded paths below. Two
small regression-protection gaps deserve follow-up; neither is a present production
failure. A third observation extends the existing framework-test work, not a new bug.
The later T-1327, T-1348 and T-1349 fixes were included, so their old findings are not
re-filed. Existing T-1336 remains the place for unresolved held-reference rollback behavior.

## Claim matrix

All source verdicts and descriptions of existing test bodies are **MEASURED-SOURCE**.
The last column is **REASONED** unless explicitly identified as an artifact check.

| Commit / claim | Current source verdict | Existing witness, read only | Unpinned case / smallest next action |
| --- | --- | --- | --- |
| `af329dc`: a context must not delete tasks merely assigned to its goals | Holds. `Cadence/Services/CadenceListDeleteHelpers.swift:74` collects area, project and context tasks; `:115` severs surviving task/habit goal references. `Cadence/Shared/CadenceListDeletionSummary.swift:262` counts the same task set. | `CadenceTests/ListDeleteHelpersTests.swift:279` covers foreign and unfiled tasks plus a foreign habit; `CadenceTests/CadenceListDeletionSurfaceTests.swift:157` excludes a goal-only foreign task from the count. | No new ownership fix. Refusal-visible graph behavior belongs to T-1336, not a reopening of T-1312. |
| `f2acbff`: direct goal delete and context delete intentionally differ on foreign child goals | Holds. Context uses `context.goals` at `Cadence/Services/CadenceListDeleteHelpers.swift:51`; direct goal delete walks `GoalAssignmentRules.deletionCascade` at `Cadence/Shared/TrackingDeleteHelpers.swift:70`. | `CadenceTests/ListDeleteHelpersTests.swift:364` keeps/promotes a foreign milestone; `CadenceTests/TrackingDeleteHelpersTests.swift:247` deletes it with its parent but preserves its work. | Do not add a context filter to direct goal deletion or a subtree walk to context deletion. These would undo a decided policy. |
| Goal confirmation/refusal follow-up | T-1327 now shares the recursive count. macOS `Cadence/macOS/Sheets/CreateGoalSheet.swift:379` uses the shared message and `:389` reports refusal through the confirmation; iOS `Cadence/iOS/iOSFeatureViews.swift:116` catches before clearing selection. Context callers use `commitCascade`: `Cadence/macOS/Views/SettingsView.swift:428`, `Cadence/iOS/iOSListDeletionSupport.swift:121`. | `CadenceTests/TrackingDeleteHelpersTests.swift:83`, `:122`, `:191` cover recursive counts and Mac wiring; `:501` and `:569` check the persisted refusal graph and absence of pending edits. `CadenceTests/CadenceDeferredReminderCancellationTests.swift:73`, `:106`, `:141`, `:168` cover refusal and successful cancellation release. | Already-materialized UI references on both runtime/toolchain combinations remain T-1336. Fresh-context graph assertions do not settle that question. No new cascade-cancellation ticket: T-1348 moved release below the commit in `Cadence/Shared/CadencePendingChangePersistence.swift:218`. |
| `76b90c6`: committed reset cannot become a generic deletion failure during cleanup | Holds. `Cadence/Services/CadencePrivacyDataResetService.swift:290` is the only throwing step in the whole-reset body; `:337` and `:342` independently catch the two backup removals; `:299` forwards both warning fields. Both settings surfaces use the outcome. Mac signs out only after the awaited reset at `Cadence/macOS/Views/SettingsDataSafetySection.swift:261`; `AppleAccountManager.signOut` is nonthrowing at `Cadence/macOS/Services/AppleAccountManager.swift:194`. | `CadenceTests/CadencePrivacyDataResetSurfaceTests.swift:596`, `:629`, `:666` cover precommit refusal; `:859` guards the throwing-phase split; `:888` proves the second cleanup is attempted after the first refuses; `:923` checks warning sentences; `:410` checks platform message selection. | **R61-A below:** backup-warning forwarding itself is not pinned like the key-warning forwarding. Keep production code; add the missing guard. |
| `475045e` + `69544c8`: launch preserves its error while tolerating framework differences | Catch and message wiring hold: `Cadence/Services/PersistenceController.swift:110`, `:113`, `:147`, `:163`. Standard underlying errors and reflected optional errors are considered; plain description is the fallback. A specific cause is not guaranteed on every framework. | `CadenceTests/CadenceStartupRecoveryReasonTests.swift:159` strictly covers the standard underlying-error channel; `:180` covers banner/health propagation; `:207` guards init wiring. Framework-dependent cases at `:106` and `:140` were relaxed. | **R61-B:** add an SDK-independent reflected-wrapper fixture. **R61-C:** remove the unsupported aggregate all-or-none assumption while retaining strict application invariants. |
| `475045e`: startup tag sweep reuses one index without changing resolution semantics | Holds: `Cadence/Services/TagSupport.swift:303` builds once and `:305` passes the index into each resolution. `PersistenceController.swift:227` uses `saveChanges: false` and owns the final maintenance save. | `CadenceTests/TagSupportTests.swift:560` counts index creation; `:592` and `:628` distinguish use of the handed index from an extra fetch; `:655` compares tag membership; `:710` compares exact order assignment for a fixed call sequence; `:739` and `:757` cover unreadable/empty input. | No new action. Unordered note fetches make an exact cross-store order comparison inappropriate; the separate deterministic order test is the correct pattern. T-1329/T-1341 own later startup measurements/optimization. |
| `ee2e4c6`: iOS has its own push entitlement file and both app configurations select it | Holds in source: `Cadence/Cadence-iOS.entitlements:16`, `Cadence/Cadence.entitlements:18`, `Cadence.xcodeproj/project.pbxproj:760` and `:802`. | `CadenceTests/AppStoreReviewReadinessTests.swift:574` checks platform keys, two conditional assignments, and equality of the remaining entitlement dictionaries. | Artifact-only: distribution-signed entitlement/profile contents, token registration, and an edit arriving on an already-open second device. Source counts cannot certify these. Existing T-1309 release follow-up, not a new defect. |
| `b687056`: both privacy manifests declare both defaults domains | Holds: `Cadence/PrivacyInfo.xcprivacy:67`, `CadenceWidgets/PrivacyInfo.xcprivacy:18`. Both list `CA92.1` and `1C8F.1`. | `CadenceTests/AppStoreReviewReadinessTests.swift:31` and `:47` require the two reasons and reject values outside the declared approved set. | Artifact-only: inspect the app and embedded widget manifests in the actual submission archive. This pass does not revalidate Apple's policy or App Review acceptance. T-1323 identity-row policy is separate and still not resolved by these reasons. |
| `e7d83bb`: both note actions explicitly request `store: false` | Holds: `Cadence/Services/AI/AIProvider.swift:149` and `:153` call the tested factories; `:169` encodes the DTO; `:232` defaults the field to false and `:240` includes the key. UI disclosure: `Cadence/Shared/CadenceSettingsSectionCopy.swift:157`; longer claim: `docs/privacy.html:48`. | `CadenceTests/AITests.swift:99` checks encoded factories for both actions; `:115` checks omission defaults; `:130` checks input fields. | These are factory/encoder tests, not transport captures of the two async methods. A low-priority strengthening is to inject the existing URLSession parameter (`AIProvider.swift:101`) with a local URLProtocol stub and inspect both actual requests. No live API key/network needed. The flag proves what Cadence asks, not provider-side deletion or absence of all retention. T-1322 already records that boundary. |

## R61-A: the backup warning can fall between two independently correct tests

**P3, missing regression coverage; extends T-1313. MEASURED-SOURCE:**
`CadencePrivacyDataResetService.swift:302` currently forwards
`retainedBackupReason: backups.retainedBackupReason` correctly.
`CadencePrivacyDataResetSurfaceTests.swift:800` explicitly checks the equivalent retained-key
forwarding, but not this backup field. The cleanup test at `:888` calls `removeStoredBackups`
directly; the sentence test at `:923` constructs `PrivacyDataResetOutcome` directly. Neither
traverses the whole-reset return expression. The backup parameter defaults to nil at
`CadencePrivacyDataResetService.swift:51`, so dropping the argument is a plausible compiling edit.

**Can this happen today?** No lost warning was found in current wiring. The underlying failure
case is reachable today when database deletion succeeds and a local backup removal refuses.
**REASONED:** removing only the forwarding argument would silence that warning while the
identified cleanup and sentence tests still exercise their own correct halves. This mutation
was not applied, compiled, or run; no claim that the entire suite survives it is made.

**Smallest suggested fix:** extend the existing `theWholeResetCarriesTheRetainedKeyIntoItsOutcome`
source guard to pin backup-warning forwarding inside that same function body. Use its existing
comment-stripped/function-scoped pattern. Add a negative fixture with the argument omitted;
eventually confirm that one-line mutation is killed. Do not call the destructive whole-reset
entry point against the real backups directory. No production refactor is needed.

**30-second confirmation (source, not a runtime reproduction):**

```sh
rg -n 'retainedBackupReason|retainedAPIKeyReason:' Cadence/Services/CadencePrivacyDataResetService.swift CadenceTests/CadencePrivacyDataResetSurfaceTests.swift
sed -n '800,846p' CadenceTests/CadencePrivacyDataResetSurfaceTests.swift
```

## R61-B: the reflected-error branch has no strict synthetic witness

**P3, missing regression coverage; extends T-1319. MEASURED-SOURCE:** the real-store test at
`CadenceStartupRecoveryReasonTests.swift:106` only independently inspects
`NSError.userInfo[NSUnderlyingErrorKey]` at `:112`. The production reflection path at
`PersistenceController.swift:163` is the separate mechanism this change added. The exact-value
synthetic test at `CadenceStartupRecoveryReasonTests.swift:159` uses NSError's standard key,
not a Swift error wrapping an optional child discoverable only through Mirror.

**Can this happen today?** No extractor regression was found. A failed primary-store open
reaches this code today; whether the framework supplies a reflected cause is runtime-dependent.
**REASONED:** removing only the Mirror candidate append can fall back to the outer description
without violating the real-store test when userInfo is empty, while the standard-key fixture
still passes. The aggregate fallback test also accepts that loss. This is an unexecuted
mutation candidate, not a measured surviving mutation.

**Smallest suggested fix:** add a private Swift `LocalizedError` fixture with a deliberately
generic `errorDescription` and an optional stored `Error` child with a different description.
First assert the fixture's NSError userInfo has no standard underlying-error key; then require
`storeFailureReason` to equal the child description. Also cover a nil child and the plain
fallback. This pins Cadence's own reflection algorithm without pinning SwiftData's layout.
Keep the existing exact NSError test and init/banner wiring guards. No production change needed.

**30-second confirmation:**

```sh
sed -n '144,175p' Cadence/Services/PersistenceController.swift
sed -n '106,176p' CadenceTests/CadenceStartupRecoveryReasonTests.swift
rg -n 'storeFailureReason|nestedFailureDescription|unwrappedError' CadenceTests
```

## R61-C: all-or-none diagnostics is still an unproven framework constraint

**P3, test-design risk; extends T-1318, alongside R61-B. MEASURED-SOURCE:**
`CadenceStartupRecoveryReasonTests.swift:140` accepts three distinct messages or one identical
message, but rejects two. **REASONED:** a runtime exposing a specific cause for only one of the
three failures would make a correctly operating extractor produce two messages. Nothing in the
app's contract requires all three framework errors to have equally informative internals.
No such runtime result was observed in this audit; do not describe this as current CI breakage.

**Suggested change:** replace the aggregate cardinality oracle with per-error requirements:
nonempty result, recovery prefix preserved, and propagation of the reason the extractor returns.
Put strict extraction correctness in R61-B's deterministic fixtures and the existing NSError
fixtures. An independently observed framework cause can strengthen an individual runtime check;
absence of that cause must not weaken the deterministic tests. Do not preemptively relax other
T-1318 assertions. The same `sed` command above shows the complete cardinality predicate.

## Specific counterevidence and order

- **MEASURED-SOURCE:** the deletion helper and confirmation count both lost the same erroneous
  task leg; the foreign-goal policy has tests in both directions. This is not unfinished parity work.
- **MEASURED-SOURCE:** reset backup cleanup uses two separate do/catch blocks and a behavioral
  witness for attempting the second step. Mac sign-out and backup-list refresh add no new throw
  after commit, and the platform message selection already has a guard.
- **MEASURED-SOURCE:** T-1348's cancellation queue releases only after `commitDelete` returns;
  T-1349 now checks app-level graph readers in a fresh context. The remaining held-reference
  question is deliberately not answered by those tests.
- **MEASURED-SOURCE:** the tag tests use an intentionally stale/empty handed index to detect
  bypassing it. That is stronger than counting factory calls alone and is an existing pattern
  worth reusing for the missing handoff tests.

**Recommended order (REASONED):** R61-A's narrow guard first; R61-B's reflected fixture next;
R61-C's oracle adjustment with that fixture in place; optional AI transport witness last.
Run those targeted tests and the proposed mutations in an implementation task, not this audit.
Keep signed-archive/device checks and T-1336's two-runtime experiment separate. Do not reopen
the eight production fixes or invent replacement ledger IDs merely to record this verification.

Ledger deduplication: inspected T-1310 through T-1329 as relevant, plus T-1336, T-1348 and
T-1349 evidence and the previous R64/R65 reports. R61-A/B/C are report-local labels, not newly
allocated TODO tickets. No product source, tests, or authoritative ledger was edited.
