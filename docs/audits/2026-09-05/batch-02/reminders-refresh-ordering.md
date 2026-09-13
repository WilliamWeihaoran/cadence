# Reminders Refresh Ordering

```text
Tree read: 9b31280
Dirty entries at capture: 24 (git status --short; untracked directories count as one)
Source examined: clean git archive of 9b31280; dirty work excluded
Mode: source-only audit; no app launches, builds, or tests
```

## RM-1: Late Fetch Results Can Replace a Newer Reminder State

**P2 / asynchronous freshness risk / inferred, no EventKit race reproduced.**

**Can this happen today?** A Reminders grant is active and two reloads overlap, or a reload is in flight when completion succeeds. Authorization refresh and EKEventStoreChanged both call reload. The callback always assigns its captured items, with no request generation, cancellation, or fresh authorization check.

**Exact spots:**
- [CadenceRemindersManager.swift:184](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceRemindersManager.swift:184): reload checks authorization only before starting.
- [CadenceRemindersManager.swift:196](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceRemindersManager.swift:196): asynchronous fetch constructs a captured result.
- [CadenceRemindersManager.swift:200](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceRemindersManager.swift:200): queued publication unconditionally replaces reminders and clears isLoading.
- [CadenceRemindersManager.swift:242](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceRemindersManager.swift:242): successful completion removes the local row but does not invalidate an older fetch.
- [CadenceRemindersManager.swift:112](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceRemindersManager.swift:112): loss of authorization clears the array but leaves already-issued callbacks able to publish.
- [CadenceRemindersManager.swift:278](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceRemindersManager.swift:278): the store-change observer can launch further reloads.

Two meaningful interleavings:
1. Fetch A captures older rows; fetch B captures newer rows and publishes first; A publishes last and restores the older array.
2. Fetch A captures an incomplete reminder; completion succeeds and removes it; A then republishes it.

**Inferred consequences:** stale or apparently resurrected rows, and isLoading becoming false while a newer fetch remains in flight. The assignment after authorization loss can also refill internal state; **do not claim it exposes denied data on screen**, because the shared connectionState can hide reminder rows. A later EventKit notification may correct any stale result, but the source does not guarantee that another one will arrive after the late publish.

## 30-Second Confirmation

```sh
git show 9b31280:Cadence/Services/CadenceRemindersManager.swift | sed -n '95,114p'
git show 9b31280:Cadence/Services/CadenceRemindersManager.swift | sed -n '177,204p'
git show 9b31280:Cadence/Services/CadenceRemindersManager.swift | sed -n '239,252p'
git show 9b31280:Cadence/Services/CadenceRemindersManager.swift | sed -n '278,296p'
```
These reveal an unguarded publisher, not the actual order EventKit used on a device.

## Suggested Fix

Keep a monotonically increasing request generation on the manager. Capture it for each reload and accept the callback only if that generation is still current and publication remains authorized. Invalidate pending generations when authorization is lost and when a completion changes the authoritative local state, not only on the next reload. Ensure stale callbacks cannot clear the loading state for the current request.

Cancellation of an old EventKit fetch may reduce work, but cancellation alone should not be the correctness check: guard at publication. If completion invalidates an in-flight reload, explicitly decide whether to launch a new one or keep the already-correct local removal; do not leave isLoading stuck.

**Existing correct local pattern:** authorization clearing is already centralized in refreshAuthorizationState, successful completion already removes the confirmed row, and callbacks already dispatch publication to main. Extend those boundaries with freshness ownership. No existing reusable request-generation helper was found that this report can honestly recommend copying.

## Acceptance Checks, Not Run

Use an injectable fetch callback rather than requiring a real Reminders grant:
- Start A then B; deliver B then A; B stays visible.
- Start A; complete row X; deliver A containing X; X stays absent.
- Start A; revoke/refresh authorization; deliver A; the array remains cleared.
- An old callback cannot end the current request's loading indicator.
- A current empty result still clears the list.
- Completion failure continues to use the existing reconcile policy.

## Dedup and Test Gap

T-254/T-265/T-268 concern permission folding and completion reconciliation; T-373 concerns total ordering. Sorting a stale snapshot correctly does not make it fresh. No out-of-order reload ticket was found in TODO, TODO_DONE, or the searched hand-off documents.

[CadenceInboxRemindersSurfaceTests.swift:786](/Users/williamwei/Desktop/Projects/Cadence/CadenceTests/CadenceInboxRemindersSurfaceTests.swift:786) and neighboring tests validate reconcile selection and that the manager performs it. The reconcile ledger counts calls; it does not control callback order. Preserve those tests and add delayed-delivery coverage rather than replacing them with more counters.

## Looks Solid and Patch Order

Both platforms share one manager. Permission state has a shared resolver, successful completion is conditional on EventKit save, and sorting has an identifier tie-break. These are independent strengths, not evidence against the callback race.

First add an injectable callback source and the A/B discriminator, then gate publication and invalidate on state-changing operations. Keep permission wording and platform layouts unchanged.
