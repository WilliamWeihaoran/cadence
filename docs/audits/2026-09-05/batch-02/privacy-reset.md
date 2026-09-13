# Privacy Reset Completeness and Failure Boundaries

```text
Tree read: 9b31280
Dirty entries at capture: 24 (git status --short; untracked directories count as one)
Source examined: clean git archive of 9b31280; dirty work excluded
Mode: source-only audit; no app launches, builds, or tests
```

## PR-1: A Failed Key Deletion Still Produces Reset Success

**P2 / error-reporting and retained-credential defect / inferred.**

**Can this happen today?** Both platforms call the shared reset. If the existing Keychain delete operation throws while database deletion and subsequent backup deletion succeed, the reset returns a success outcome although the saved OpenAI key remains. No real Keychain failure was induced.

**Exact spots:**
- [CadencePrivacyDataResetService.swift:155](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadencePrivacyDataResetService.swift:155): `try? aiSettingsManager.removeAPIKey()`.
- [AISettingsManager.swift:63](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/AI/AISettingsManager.swift:63): deleteSecret treats unexpected OSStatus values as errors.
- [AISettingsManager.swift:153](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/AI/AISettingsManager.swift:153): removeAPIKey clears flags only after the deletion succeeds.
- [SettingsDataSafetySection.swift:361](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsDataSafetySection.swift:361): the reset explicitly promises removal of the saved OpenAI key.
- [SettingsDataSafetySection.swift:251](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsDataSafetySection.swift:251) and [iOSDataResetSettingsSection.swift:94](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSDataResetSettingsSection.swift:94): successful shared return becomes a success notice.

**Suggested fix:** Do not swallow the credential failure. Prefer a typed partial-reset result that records each artifact's outcome while still attempting the remaining cleanup steps; database deletion has already committed, so a plain all-or-nothing failure message also needs care. Keep key removal retryable and never claim it was removed unless deleteSecret succeeded. The existing `AISecretStore` protocol already supplies the test double; no real Keychain access is needed.

**Acceptance checks:** fake secret store throws on delete; the overall UI does not show unconditional success, the key remains reported as present/unknown rather than removed, later artifact cleanup follows the chosen documented policy, and retry can finish key deletion. Also cover no-key and successful deletion.

## PR-2: A Failed Database Reset Leaves Deletion Pending in the Shared Context

**P2 / failure atomicity defect / inferred.**

**Can this happen today?** A fetch of a later model type or the final save can fail after earlier model rows have already been marked deleted. The error reaches Settings, but neither the shared service nor either caller undoes that pending deletion. A later unrelated save may commit it, or another rollback may discard it. This requires a store error; it is not asserted for every reset.

**Exact spots:**
- [CadencePrivacyDataResetService.swift:88](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadencePrivacyDataResetService.swift:88): sequential fetch-and-delete passes begin.
- [CadencePrivacyDataResetService.swift:109](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadencePrivacyDataResetService.swift:109): one final save, outside a rollback boundary.
- [CadencePrivacyDataResetService.swift:164](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadencePrivacyDataResetService.swift:164): each helper fetches, then immediately marks rows deleted.
- [SettingsDataSafetySection.swift:253](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsDataSafetySection.swift:253) and [iOSDataResetSettingsSection.swift:95](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSDataResetSettingsSection.swift:95): catch only sets a status string.

**Suggested fix:** Establish an explicit database-reset transaction boundary covering **both** fetch/delete construction and final save. The existing `CadencePendingChangePersistence.commitDelete` and `commitCascade` show the rollback discipline, at [lines 121 and 148](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadencePendingChangePersistence.swift:121). Do not wrap only the final save and leave earlier fetch failure unhandled.

One conservative approach is to fetch the complete deletion set before marking any row, then use the existing delete commit helper. Otherwise catch and roll back the entire construction phase as well. Preserve the original error. Document the shared-context rollback cost to other pending edits; do not silently invent an isolated-context reset without reviewing refresh/sync behavior.

**Acceptance checks:** inject failure at a later fetch and at save; catch the reset failure, perform an unrelated save, and confirm no part of the refused reset is committed. Verify notifications/key/backups are untouched when database deletion fails. Test successful reset separately from partial artifact failure after a successful database commit.

## 30-Second Confirmation

```sh
git show 9b31280:Cadence/Services/CadencePrivacyDataResetService.swift | sed -n '84,124p'
git show 9b31280:Cadence/Services/CadencePrivacyDataResetService.swift | sed -n '150,170p'
git show 9b31280:Cadence/macOS/Views/SettingsDataSafetySection.swift | sed -n '236,258p'
git show 9b31280:Cadence/iOS/iOSDataResetSettingsSection.swift | sed -n '81,100p'
```
These commands confirm source structure; failure effects have not been executed.

## Dedup and Coverage

T-297 covers awaited notification cancellation; T-310 widget refresh; T-474 platform-specific success wording; T-575 confirmation strength; T-574 blank-key saving. None fixes the swallowed key deletion or encloses the reset's database mutation in rollback.

[CadencePrivacyDataResetSurfaceTests.swift:51](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadencePrivacyDataResetSurfaceTests.swift:51) and neighboring cases cover deletion, awaited cancellation, widget state, and shared call-site wiring. [AITests.swift:39](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/AITests.swift:39) exercises direct key removal. Those are useful but do not prove the **whole reset** reports a secret-store refusal or cleans up a partially built database delete.

## Looks Solid and Patch Order

Typed DELETE confirmation and platform-specific wording are shared. Notification cancellation is awaited before reset success. Widget state is cleared and explicitly reloaded. Both platforms call one orchestration path.

First fix PR-2's database boundary, then PR-1's artifact result reporting. Keep their fixtures separate: a database refusal and a post-commit credential refusal cannot honestly produce the same outcome.
