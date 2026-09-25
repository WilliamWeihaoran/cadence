# MCP, Widgets, and Startup: R58, R59, R62

```text
Tree read: c8735e4
Dirty files: 23 at capture
Source: clean committed snapshot; working edits excluded, especially the in-flight MCP changes
Mode: source inspection and public-document research; no builds, tests, benchmarks, or app launches
MEASURED-SOURCE = code directly inspected; REASONED = inferred impact or proposed design
REPO-RECORDED = someone else's measurement in the ledger, not rerun here
Freshness check: HEAD advanced to 7b5897d while this report was written; MCP delta reviewed below
```

## R58: MCP Trust Boundary

**MEASURED-SOURCE premise correction: 14 write tools, not nine.** In addition to the request's
nine, `schedule_task`, `complete_task`, `reopen_task`, `cancel_task`, and `bulk_cancel_tasks` are
reachable in `CadenceMCPServer/CadenceMCPToolRouter.swift:191` through `:335`.

**Close-out delta, MEASURED-SOURCE at 7b5897d:** `create_goal` and `create_habit` landed during this
audit, bringing the current total to **16 write tools**. Both new router arms call
`requireWriteService`; they broaden create authority without introducing a per-client approval
boundary. All line references below remain pinned to c8735e4. The latest diff was inspected with
`git show 7b5897d -- CadenceMCPServer/CadenceMCPToolRouter.swift`; its reported build/mutation
results were not rerun by this audit.

### Enforced Boundary

| Layer | Evidence | What it does and does not enforce |
| --- | --- | --- |
| Transport | `CadenceMCPServer/main.swift:48` | Stdio, not a network listener. The local launcher owns the connection. |
| Default mode | `Cadence/Services/MCPReadOnly/CadenceModelContainerFactory.swift:68` | Read-only container disallows saves and disables CloudKit for this process. |
| Write enable | Factory `:63,106,151`; router `:13,20,347` | Environment opt-in; write tools hidden when disabled, and dispatch independently refuses them. All 14 write cases require the write service. |
| Store selection | Factory `:110,121` | Normally the app-group store; launcher can configure an override. Tool arguments cannot choose an arbitrary file path. |
| Write startup | Factory `:80,90`; `main.swift:8` | Writable local container, with maintenance before the first tool call. Opting into writes is not a promise that only explicit tool calls will mutate. |
| Mutation validation | `CadenceWriteService.swift:1218,1394` | Validates arguments and entity rules, not the human's intent. No per-client entity scope or per-operation approval in this server. |
| Commit and audit | Write service `:1565,1583`; `CadenceMCPAuditLog.swift:24` | Commit, notify, then audit. Audit failure is caught and written to stderr; tool success does not prove a durable log entry. Log contains summaries, not before-images for undo. |

Factory/write/log paths are under `Cadence/Services/MCPReadOnly/`. The directory name is historical,
not an access-control boundary. **REASONED:** read-only default protects against accidental writes
by a cooperative host. An environment flag is not authorization against a malicious launcher that
already has this user's store access. No OAuth omission is automatically a stdio vulnerability.

### Damage, Reachability, Recovery

All rows below are **REASONED reachable consequences**, not exploit reproductions.

1. **Confidentiality:** authorized read tools return private note/task content to the client.
   A client can transmit it elsewhere; the server does not itself need an exfiltration tool.
   Once disclosed, restoring the store cannot reverse disclosure. Read-only mode does not address this.
2. **Overwriting task content:** `CadenceWriteService.swift:1252` updates title/notes. With writes
   enabled a confused client can replace useful text. Current audit summaries cannot reconstruct
   the previous text; recovery requires an independent backup or another retained copy.
3. **Broad lifecycle changes:** `:1319` completes through recurrence behavior; `:1394` bulk-cancels
   explicit IDs or a prefix. The prefix has a minimum length (`:1419`) but no affected-row cap
   (`:1423`). Valid input can target many tasks. Reopening is not a general transactional undo
   of every consequence, particularly spawned recurrence state.
4. **Organization and visibility:** update context/container/columns can move or hide work.
   Field reversal is possible when prior values are known. Column validation protects structural
   rules, including the protected Inbox, but cannot tell an accidental plan from an intended one.
5. **Pollution/resource growth:** creation and append tools can add unwanted rows/text over repeated
   calls. No raw store-reset, arbitrary shell execution, or general delete tool was found in this
   dispatch surface. Do not describe it as unrestricted remote code execution.

**Prompt injection:** returned note text is data, but an LLM client may interpret it as instructions
and call writes. The server sees syntactically valid calls, not their cause. There is no review gate
here that distinguishes a direct owner request from an instruction embedded in a note. A prompt
warning helps a cooperative model but is not the enforcement boundary.

**Suggested work, in order:**
1. Keep default read-only and document that enabling writes grants store-wide authority. Have the
   trusted launcher/client enforce tool allowlists and human approval outside model-controlled text.
2. Require an affected-count/diff preview for bulk lifecycle and content replacement, bound batch
   size, and require renewed confirmation if the target set changed. Do not let the LLM approve itself.
3. Design narrowly scoped before-images/undo receipts if recovery is a product goal. Existing
   `CadencePendingChangePersistence` handles a failed commit; it does not undo a successful bad request.
4. Surface audit degradation in results or an operator-visible channel; bound log growth and avoid
   logging complete private content. Verify validation/disabled-dispatch with refusal witnesses.

These are threat-model/design improvements, not a claimed unauthenticated Internet exploit.

### Sandbox and Distribution

**MEASURED-SOURCE:** `Cadence.xcodeproj/project.pbxproj:1054,1077` configures the separate command-line
target with `SKIP_INSTALL=YES` and no target-level sandbox/entitlements setting. App and widget
settings are separate. This does not prove the entitlements of a shipped signed binary, nor that
the server is bundled in an App Store archive. Inspect the actual archive and signature before
making a distribution claim.

**DOCUMENTED:** sandboxing restricts resources; it is not per-note or per-tool consent. An embedded
command-line child needs the appropriate sandbox arrangement. A separately launched binary does
not acquire the GUI app's entitlements merely by knowing its app-group identifier.
[Apple sandbox guidance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).
macOS 27 also documents tighter cross-team app-container access, so "any same-user executable can
always read the store" is too broad. [macOS release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).

**REASONED review question:** if distributing the helper through the Mac App Store, verify actual
sandboxing, self-contained packaging, and any background-process consent against section 2.4.5.
Do not assume a developer-side stdio integration demonstrates a review-compliant shipped helper.
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

Confirm without launching:
```sh
git show c8735e4:CadenceMCPServer/CadenceMCPToolRouter.swift | sed -n '185,365p'
git show c8735e4:Cadence/Services/MCPReadOnly/CadenceWriteService.swift | sed -n '1394,1438p;1565,1600p'
git show c8735e4:Cadence.xcodeproj/project.pbxproj | sed -n '1048,1100p'
```

**Looks solid:** disabled dispatch is checked independently of tool discovery; default storage is
read-only; write operations use the shared mutation rules and notify after commit. Preserve these.

## R59: Widget Budgets

**Premise correction:** Today fetches a filtered population, not every task. It is still uncapped.
Widgets open the local store read-only with `.none` for CloudKit; this is not a widget-initiated
whole-store CloudKit download. A replica's current incompleteness and its eventual size are separate.

### Actual Work

| Provider / helper | MEASURED-SOURCE work before rendering |
| --- | --- |
| Today | `CadenceWidgets/TodayTasksWidget.swift:128`; `Cadence/Services/CadenceTodayWidgetSupport.swift:205`: unfinished, uncancelled tasks with date fields. Ranking/counting precedes the visible prefix (`:69`). |
| Calendar | `CadenceWidgets/CalendarSnapshotWidget.swift:72`; `Cadence/Services/CadenceCalendarWidgetSupport.swift:50`: full task fetch, then date-bucket filters (`:64`), overdue/upcoming derivations. |
| Habits | `CadenceWidgets/HabitCheckInWidget.swift:66`; `Cadence/Services/CadenceHabitWidgetSupport.swift:61`: full habits, due/completion relationship work, visible limit 8 only after deriving the population. |
| Milestones | `CadenceWidgets/MilestoneMomentumWidget.swift:61`; `Cadence/Services/CadenceMilestoneWidgetSupport.swift:57`: all goals, contribution traversal and ranking (`:79`), visible limit 5 afterwards. |

The full schema being registered does **not** mean every note or image blob is eagerly loaded.
Relationship fanout, history length, store coldness and contention matter independently of root counts.

**Which budget binds first? Unknown without measurement.** A low-refresh allowance limits freshness,
not necessarily provider execution. Cold disk opening, traversal CPU, and resident memory can each
dominate a different fixture. No universal 30MB/30-second limit is asserted here. Apple's roughly
40-70 daily refreshes for frequently viewed widgets is guidance, not a guaranteed allowance.
`.after(date)` requests a timeline opportunity; it does not guarantee delivery at that time.
[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

### What the User Sees

**MEASURED-SOURCE:** caught open/fetch failures become `.unavailable`, not an intentionally blank
widget: Today catch at `TodayTasksWidget.swift:140`, Calendar `:83`, Habit `:77`, Milestone `:72`.
Their view branches render an unavailable state. `CadenceTodayWidgetSupport.swift:239` supplies
reload policy, including a five-minute request for unavailable data and day-boundary handling.

**REASONED:** process termination before completion cannot reach those catches. WidgetKit may retain
an older entry or show a system placeholder/fallback; the exact outcome is OS/state dependent and
unmeasured here. A stale-looking-successful widget and a requested refresh that arrives late are
the silent cases. In the inspected providers/helpers there is no durable duration/memory/last-success
instrument that distinguishes them. Platform diagnostic logs are not an in-app user explanation.

**Suggested order:**
1. Measure container opening, fetch, relationship derivation and total timeline completion separately
   on device. Record last successful generation and source snapshot time, not just next requested date.
2. Start with Calendar's broad task fetch and milestone relationship fanout. Use equivalent store
   predicates or shared derivations where semantics allow; do **not** put `fetchLimit=5` before global
   ranking/counting and silently change results.
3. Only if measured provider cost warrants it, add a versioned, atomic app-group snapshot written by
   the app. Include store identity/generation, timestamp, explicit empty/unavailable states and last-good
   fallback. Invalidate for app/MCP/widget writes, sync imports, day rollover and privacy reset. A cache
   without those owners can make stale data permanent.

**Acceptance plan, unrun:** disk-backed 264/1k/5k/10k total-row cohorts; vary task-date density, goal
fanout, and habit completion history separately. Measure cold/warm p50/p95, peak resident memory,
completion and OS termination logs on the target devices. Include partial-replica and read-failure
fixtures. Reuse one seeded dataset for R62; do not conflate widget refresh delivery with app launch.

Confirm:
```sh
git show c8735e4:Cadence/Services/CadenceTodayWidgetSupport.swift | sed -n '205,265p'
git show c8735e4:Cadence/Services/CadenceCalendarWidgetSupport.swift | sed -n '45,100p'
git grep -n 'cloudKitDatabase\|allowsSave\|unavailable' c8735e4 -- CadenceWidgets
```

**Looks solid:** explicit unavailable states, a read-only container, shared reload policy, and
visible limits after correct ranking. The missing evidence is measured operating headroom, not a
reproduced budget overrun.

## R62: Remaining Startup Cost

**MEASURED-SOURCE:** the initializer runs synchronously through preflight, container opening and
maintenance before returning the app container (`Cadence/Services/PersistenceController.swift:37`).
Maintenance uses a separate startup `ModelContext` (`:98`), not the eventual UI context. This is
not a background worker merely because its context is separate.

| Pass / entry | Reads and traversal | Mutation, repetition, failure |
| --- | --- | --- |
| Legacy-store/backup/restore preflight, PersistenceController `:58` | Store directories/files, backup copies and pending restore | Before container opening; depends on file size, not just row count. Preflight failure chooses recovery; refused pending restore retains the original store and reports it. |
| ModelContainer, `:89` | Schema/store opening, CloudKit configuration | Distinct from migration/Swift loops; not measured by an in-memory maintenance benchmark. |
| Pursuit migration, `:203`; `PursuitToGoalMigration.swift:40` | Completion flag plus one-row survivor probe, or full Pursuit fetch and child goal/habit relationships | Creates Goals and reparents, saves before deleting Pursuits, then saves again. Completion flag only after success. Probe remains necessary after restore/foreign arrivals. Fetch/save failures return false; not every failure is surfaced by the outer startup issue. |
| Note migration, `:226`; `NoteMigrationService.swift:284,292` | Five one-row legacy probes; only if needed, full Note identity map and legacy rows | Inserts migrated notes; app passes saveChanges:false. Failure wrapper records the migration failure. Every launch, no permanent empty latch. |
| Markdown/tag sync, `:227`; `TagSupport.syncAllNoteTagsFromMarkdown` | Note table, one Tag index, markdown/frontmatter bytes and note-tag relationships | Can mint tags/edit relationships; save deferred. Runs each launch. T-1314 already removed per-note full Tag fetches. |
| Integrity repair, `:234`; `DataIntegrityRepairService.swift:268` | Twelve tables: Context, Area, Project, AppTask, Goal, Habit, Note, Document, SavedLink, GoalListLink, HabitCompletion, FocusSessionLog | Dedup/reparent/fork collapse; relationship walks depend on duplicate density. Save deferred; wrapper records failure. Every launch. |
| Focus reconciliation, `:245`; `Models/AppTask.swift:770` | FocusSessionLog table, groups resolved subjects and computes counters | Raises counters only. Fetch failure and no changes both return false; not a complete failure telemetry surface. Every launch. |
| Final maintenance save, `:250` | Pending startup-context changes | Only if a pass reported changes and context.hasChanges. Failure produces maintenanceSaveFailed startup issue (`:254`). |

Unqualified service paths above are under `Cadence/Services/`. View composition, initial queries,
image decoding and first frame follow this work and are **not included** in the table's pass timings.
Initial CloudKit import is asynchronous; startup does not wait for an atomic fully synced store.
Maintenance is not rerun for every arriving batch. Late legacy-note latency is already T-1352.

### Measurements Already Paid For

**REPO-RECORDED, T-1329, not rerun:** the N=4,000 synthetic fixture contains **15,967 total rows**,
not 4,000 total rows. Reported healing medians were about 2.01s in passes plus 1.54s save, 3.55s
combined; clean pass about 1.61s. The large-fixture pass medians were approximately 0.0006s Pursuit,
0.1892s note migration, 0.9465s tags, 0.7871s integrity, 0.0822s focus, then the save.
These in-memory fixture numbers are not cold-device launch predictions or measurements of the
owner's 264-row store. Duplicate-repair work need not remain linear as duplicate density changes.

**REPO-RECORDED, T-1341:** the no-legacy Note scan was subsequently eliminated by the five probes.
At 1k/2k/4k Notes the reported old 0.0245/0.0481/0.0939s became roughly 0.0008/0.0007/0.0008s.
The legacy-present branch still does real migration work. Do not propose T-1341 again.

### Ranked Recommendations

1. **Measure disk/preflight/container/first-frame costs before another optimization.** They were
   outside T-1329. Add opt-in stage signposts and counts without note content, and retain refusals
   separately from a no-op result. The latter matters for Pursuit and focus failures above.
2. **Measure tag bytes and repair duplicate/fanout density.** They dominate the recorded pass time.
   A one-launch shared snapshot may remove repeat Note/Focus fetches, but earlier passes mutate those
   populations; ownership must update that snapshot or invalidate it. A stale shared array is not an
   optimization with equivalent semantics.
3. **Keep cheap probes and ordering.** Pursuit conversion must precede downstream ownership work;
   note migration precedes tag parsing; dedup precedes focus counter reconciliation. T-1341's live
   existence probes are the correct pattern, unlike a never-run-again UserDefaults latch.
4. **Do not move all repair to a worker speculatively.** A worker needs its own context, stable IDs,
   defined UI visibility during migration, serialization against other writers and failure recovery.
   It cannot make sync complete or make a partial prior run impossible. Preservation of the original
   store/backup remains a separate requirement.

**Minimal next fixture plan, unrun:** define 264, 1k, 5k and 10k **total rows**, publish the per-type
breakdown; separately vary frontmatter bytes/tags, child fanout, duplicate density, legacy rows and
image bytes. Measure a clean second launch as well as a healing first launch; use disk-backed stores
for end-to-end cost. Capture stage p50/p95 and first usable frame independently. T-1314's checked-in
index-build and semantic-equivalence tests are useful correctness oracles; the historical disposable
timing harness is not assumed to be a maintained benchmark target.

**Patch order:** instrumentation, establish expensive population, optimize one pass with output
equivalence, then consider deferral only if measured launch benefit exceeds its consistency cost.
No new performance severity or launch-time threshold is claimed from source alone.

Confirm:
```sh
git show c8735e4:Cadence/Services/PersistenceController.swift | sed -n '37,103p;197,260p'
git show c8735e4:Cadence/Services/NoteMigrationService.swift | sed -n '264,321p'
git show c8735e4:docs/TODO.md | rg -n '^\s*- \[T-(1314|1329|1341|1352)\]'
```

**Looks solid:** no unprompted default-tag seeding, a dedicated startup context, one shared Tag
index per sweep, live legacy-row probes, change-sensitive final save and original-store-preserving
recovery. These are constraints to retain, not obstacles to remove for a faster benchmark.
