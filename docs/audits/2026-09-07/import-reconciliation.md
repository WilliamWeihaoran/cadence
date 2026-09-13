# Post-import Reconciliation Audit

```text
Tree read: 4ad2178
Dirty files at initial capture: 22; excluded via clean git archive
Mode: source/history plus independent arithmetic; no builds, tests, app, or simulator
```

## ROI-03: Import Changes Tasks and Habits Without Updating Pending Reminders

**P2 / missing post-commit behavior / REASONED.** Extends the fast-path contract already established by T-306/T-312 for other writers; this new importer is a distinct entry point. No import-specific notification ticket found.

**Can this happen today?** With notifications enabled and authorized, import an archive in overwrite mode which marks a task done or changes its reminder time. If the app remains active, its old pending OS reminder can still fire until another reconciliation trigger. A newly imported scheduled task or habit likewise receives no immediate scheduling call. This is a bounded foreground gap, not "notifications never work after import."

**Evidence:** [CadenceArchiveImportPresentation.swift:404](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Shared/CadenceArchiveImportPresentation.swift:404) imports and sets a status string, with no post-save effects callback. The service also has no notification or external-write hook. [macOSRootView.swift:324](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/macOSRootView.swift:324) reconciles on leaving active; [iOSRootView.swift:170](/Users/williamwei/Desktop/Projects/Cadence/Cadence/iOS/iOSRootView.swift:170) does so on scene transitions. Neither is a data-change observer. The external-write path at [macOSRootView.swift:262](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/macOSRootView.swift:262) refreshes and reconciles, but the importer does not post that marker. `NotificationManager` deliberately allows foreground banners.

**MEASURED source scan:** importer contains zero `scheduleReconcile`, `NotificationManager`, or `postExternalWrite` calls; flow contains no corresponding post-commit trigger. This is negative source evidence, not an observed OS delivery.

```sh
git show 4ad2178:Cadence/Shared/CadenceArchiveImportPresentation.swift | sed -n '395,413p'
git show 4ad2178:Cadence/macOS/macOSRootView.swift | sed -n '310,334p'
git show 4ad2178:Cadence/iOS/iOSRootView.swift | sed -n '170,187p'
git show 4ad2178:Cadence/Services/CadenceArchiveImportService.swift | rg -n 'scheduleReconcile|NotificationManager|postExternalWrite'
# Last command currently has no match (exit 1).
```

**Suggested fix:** give the shared UI import flow a narrow injectable post-commit effect and invoke the existing `HabitNotificationReconcileSupport.scheduleReconcile` over a fresh context from the same container. Its fetch-failure handling already avoids treating a failed read as an empty store. Keep OS work outside the nonisolated import engine; do not request permission automatically. Trigger from the persisted outcome, including ROI-01's committed-with-migration-warning case, not only complete success. Do not reuse a stale app-context fetch or cancel every request before proving the desired state can be read.

**Acceptance checks:** verify the effect is called once after a committed import, including migration warning, and never after cancel/validation/first-save failure. Cover done-task cancellation, changed due time, and a new habit. Pin both platform mounts to the shared flow. OS delivery itself requires an authorized-device run; use an injected scheduler for unit coverage so tests do not touch real pending requests.

## ROI-04: Merge Imports Focus Sessions but Leaves Their Cached Totals Behind

**P2 / derived-state consistency / REASONED.** Extends T-621/T-742's focus-ledger invariant to the new importer. Not the earlier timer-continuity finding or the already-decided habit-day merge ambiguity.

**Can this happen today?** Import a valid newer archive into a device which already has the same task but lacks a later focus session. Default merge keeps the existing task row, adds the new session row, and never reconciles the task's `actualMinutes`. The same applies to Area/Project `loggedMinutes`. It can remain visibly low until startup maintenance or another bank operation for that subject repairs it.

**Concrete setup:** destination task has `actualMinutes = 10` and session R1 `(previousMinutes: 0, minutes: 10)`. Archive contains that task, R1, and new session R2 `(previousMinutes: 10, minutes: 20)`. Merge skips the matched task/R1 but inserts R2. Stored counter stays **10**, while the repository's ledger rule yields **30**. All IDs, references, and values are valid; this needs no edited/malformed archive.

**Evidence:**

- [CadenceArchiveImportService.swift:837](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceArchiveImportService.swift:837) skips matched rows in merge; missing session rows are inserted and wired at 788.
- [AppTask.swift:229](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Models/AppTask.swift:229) stores actual minutes as a scalar; [AppTask.swift:737](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Models/AppTask.swift:737) defines the ledger total and [line 767](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Models/AppTask.swift:767) reconciles it upward.
- Only production call found to store-wide `CadenceFocusLedger.reconcile` is [PersistenceController.swift:150](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:150), at startup. Import calls note migration, not this reconciler.
- [FocusSessionSupport.swift:11](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/FocusSessionSupport.swift:11) renders the scalar, not a fresh ledger sum.

**MEASURED arithmetic, not SwiftData execution:** the example's scalar is 10, `min(previousMinutes) + sum(nonnegative minutes)` is 30, and the existing raise-only policy selects 30.

```sh
git show 4ad2178:Cadence/Services/CadenceArchiveImportService.swift | sed -n '825,854p'
git show 4ad2178:Cadence/Models/AppTask.swift | sed -n '735,741p;767,800p'
git grep -n 'CadenceFocusLedger.reconcile' 4ad2178 -- Cadence
ruby -e 'rows=[[0,10],[10,20]]; total=rows.map(&:first).min+rows.map{|r|[r.last,0].max}.reduce(:+); puts [10,total,[10,total].max].inspect'
# Arithmetic witness: [10, 30, 30]. Not an app test.
```

**Suggested fix:** reconcile affected focus subjects after wiring imported logs and persist the raised totals in the import transaction, or provide an explicit committed post-import reconciliation result. Reuse the existing rule; never lower counters on a partial replica and never sum session rows a second time into the current counter. Existing `reconcile` swallows fetch failure, so blindly calling it is not enough to guarantee the final status: use already available indexed rows or a throwing/injectable read when the import promises consistency.

The merge copy says existing rows are left exactly as they are. Clarify that derived focus totals may rise when previously missing session records are restored; this is the current ledger policy, not permission to overwrite titles, dates, or other user fields in merge mode.

**Acceptance checks:** the 10 -> 30 example through the real importer, then read a second context; reimport is still 30; task/project/area variants; an existing counter higher than the partial ledger is not lowered; unrelated task title is preserved. Also test overwrite importing an older scalar while newer destination logs survive: whichever policy is chosen must keep the displayed total and retained history coherent.

## Looks Solid

**REASONED:** the notification reconciler uses full fetched state and skips failed fetches; scene transitions provide eventual recovery for notification changes. Focus banking already self-heals its subject and startup runs the raise-only reconciler. These are existing solutions to wire into the new path, not reasons to introduce another scheduler or ledger representation.
