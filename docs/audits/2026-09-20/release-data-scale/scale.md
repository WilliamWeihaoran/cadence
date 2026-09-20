# R54: scaling from hundreds to thousands

```text
Tree read: 1857938
Dirty files: 0 at source snapshot
Profiling / seeded 10,000-record run: not performed
Cost analysis: source-derived, not elapsed-time or memory measurements
```

## Counts are not a performance diagnosis

**MEASURED, reproducible:** run `ruby docs/audits/2026-09-20/release-data-scale/inventory.rb`.

| Spelling | Raw occurrences in product Swift | Excluding full-line // comments |
| --- | ---: | ---: |
| `@Query` | 259 | 214 |
| `FetchDescriptor(...)` construction-shaped text | 76 | 75 |
| `fetchLimit =` | 6 | 4 |
| `@AppStorage(...)` | 84 | 75 |

The request's eight `fetchLimit` mentions include prose; the four actual assignments are all `1`:
`PursuitToGoalMigration.swift:60`, `MarkdownTaskEmbedSupport.swift:442`,
`MCPReadOnly/CadenceReadService.swift:1030`, `Shared/CadenceDeepLinkResolutionSupport.swift:132`.
They are existence/detail probes, not arbitrary list truncation. These lexical counts span both
platforms and a separate executable; **they do not mean 214 live queries execute on every screen**.
They do not measure SwiftData faulting, caching or SQL cost.

## What to measure first

All cost/priority judgments below are **REASONED** from the cited source. “At 10k” means a fixture
worth profiling, not an established cliff. Record mix, graph shape, text/image bytes, hardware and
warm/cold caches matter more than a single total count.

### 1. P2 optimization: one tag-table fetch per tagged note during startup

**MEASURED-SOURCE; reachable today:**
[PersistenceController.swift:147](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/PersistenceController.swift:147)
calls the synchronous full-note tag pass.
[TagSupport.swift:255](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/TagSupport.swift:255)
fetches all notes and resolves each one's markdown tags. Each nonempty resolution fetches the
entire tag table and rebuilds a slug index (`:204,211`). Empty tag names return before that fetch.
The app target uses default MainActor isolation (`project.pbxproj:830`); maintenance runs during
container initialization, before the ordinary UI is ready.

**Cost:** K tagged notes and T tags entail K explicit fetch calls and O(K*T) tag-index work, plus
markdown parsing. For a 10,000-total-row fixture with 8,000 tagged notes and 500 tags, that is
8,000 tag fetch calls and roughly four million tag visits just for this repeated resolution.
It is **not** proof of 8,000 disk reads; Core Data may cache them. With a tiny tag vocabulary the
growth is near linear; with K and T both growing it can approach quadratic.

**Suggested fix:** add a pass-local resolver/index built once, updating it when a missing tag is
inserted; preserve the existing single-note resolver for interactive edits. Do not drop markdown
parsing or change tag semantics to make a benchmark pass. Suggested test: instrument actual fetch
requests through a narrow seam, assert bounded tag fetch count for multiple tagged notes, and
compare output/idempotence against the current resolver. Existing importer `DestinationIndex`
(`CadenceArchiveImportService.swift:1101`) is the correct fetch-once precedent. No matching
startup repeated-tag-fetch ticket was found in TODO.

```sh
sed -n '204,223p' Cadence/Services/TagSupport.swift
sed -n '245,266p' Cadence/Services/TagSupport.swift
rg -n 'syncAllNoteTagsFromMarkdown' Cadence/Services/PersistenceController.swift
```

### 2. Main-thread archive generation, preview and import

**MEASURED-SOURCE:** export is called synchronously before opening the save UI at
[SettingsDataSafetySection.swift:193](/Users/williamwei/Desktop/Projects/Cadence/Cadence/macOS/Views/SettingsDataSafetySection.swift:193)
and `iOSDataExportSettingsSection.swift:97`. `CadenceDataExportService.swift:109` materializes all
archive tables; embedded image bytes go into JSON. `CadenceArchiveImportFlow` reads, plans and
confirms synchronously (`Shared/CadenceArchiveImportPresentation.swift:480,508,516`), constructing a
destination index before import. Creating a private `ModelContext` protects rollback, **not** the
UI executor from synchronous work. A helper marked `nonisolated` does not dispatch that work.

**Cost/risk:** O(total records + payload bytes), with multiple graph/DTO/encoded-data copies and
base64 image expansion. A few hundred large images can dominate 10,000 short task rows; there is
no honest row-count-only memory threshold. This can block UI before a progress indicator paints
or terminate under memory pressure. Neither failure was reproduced here.

**Suggested fix:** own a dedicated context inside a worker/model actor, transfer only Sendable
DTOs/results, show progress/cancellation around defined commit boundaries, and bound/stream bytes
if measured memory warrants it. Never send live SwiftData models across actors. Preserve the
importer's all-or-nothing first commit and committed-with-warning second stage (T-1111); naive
per-row saves would turn a performance change into a partial-restore change.

### 3. Widget graph work, especially overlapping goals

**MEASURED-SOURCE:**
[CadenceMilestoneWidgetSupport.swift:154](/Users/williamwei/Desktop/Projects/Cadence/Cadence/Services/CadenceMilestoneWidgetSupport.swift:154)
resolves every active goal before selecting the small visible pool. Each summary recursively
walks contributing tasks/subgoals/linked lists (`Models/GoalContributionSummary.swift:79,146`).
Separate goals can revisit the same linked list; nested goals revisit subtrees. Habit momentum
adds completion-history work. The existing decoration cache avoids recomputing summaries inside
the comparator (`CadenceMilestoneWidgetSupport.swift:168`) but does not memoize across goals.

**Cost/risk:** O(G*T) for G goals all referencing T tasks, potentially worse constants for deep
subtrees and completion history. A 10k-total fixture with 100 goals and 8,000 shared tasks creates
about 800,000 task contributions before repeated summary/filter work. A normal shallow, mostly
disjoint graph is substantially cheaper. Widget deadline/memory failure is a **risk**, not an
observed timeout and not proof of main-app UI starvation.

**MEASURED-SOURCE:** Calendar widget fetches every task at
`CadenceCalendarWidgetSupport.swift:50`, filters open rows and scans them twice per displayed day
(`:66,67`), then selects upcoming work. With a fixed day window this is linear, not quadratic.
Today already narrows candidates in the store (`CadenceTodayWidgetSupport.swift:204`), although
counts and ordering still require more than the three displayed rows. Providers open a local
container per snapshot (`TodayTasksWidget.swift:127`); cold-store overhead also needs measuring.

**Suggested fix:** profile graph overlaps first; cache subtree/contribution facts within a single
snapshot, preserving per-goal deduplication and cycle guards. For Calendar, push the stable
open-status predicate and accumulate date counts in one pass. Do not add a blind `fetchLimit`:
it would make totals/ranking wrong. `WidgetSupportTests.swift:784` pins carried decorations,
not a runtime budget.

### 4. Search recomputation and intentional result caps

**MEASURED-SOURCE:** macOS queries complete source arrays at `GlobalSearchView.swift:20`, rebuilds
computed sections at `:49`, and sorts/scans tasks before capping them to 14 search hits
(`GlobalSearchIndexSupport.swift:156,186`). iOS scans notes' searchable content
(`iOSSearchView.swift:196`) and renders a section prefix of 24 (`:531`). There is no demonstrated
database-level silent query truncation. Small visible result counts do not bound matching work.

**REASONED:** note-body normalization and repeated O(N log N) sorting on UI execution paths can
make searching thousands of long notes visibly slower. Existing macOS query scheduling should
not be confused with background indexing: delaying work does not change where it executes.
The hit caps are existing UI behavior, not a new 10k corruption finding. For indistinguishable
matching titles, refining the query may not reach a hidden hit; pagination/show-more would be a
separate product improvement, not proof that `@Query` lost it.

**Suggested fix:** cache normalized search DTOs with explicit invalidation, compute off the UI
actor only after safe snapshotting, and preserve `CadenceSearchMatcher`'s identity tie-breaker.
Benchmark query latency and UI responsiveness separately. Existing ranking tests in
`CadenceSearchMatcherTests.swift:172,198` prove deterministic order, not speed.

### 5. MCP pages still pay for their candidate set

**MEASURED-SOURCE:** `CadenceReadService` is MainActor-isolated (`:114`) inside the separate MCP
process. `todayBrief` fetches active tasks once (`:174`) and filters/sorts each section; list
operations retain computed ordering and in-memory pagination. Store predicates and container
edges already narrow candidates, so “every read fetches everything” is stale. `fetchedRowCount`
at `:132` provides a useful existing measurement hook.

**REASONED:** repeated 50-row pages over M matching rows repeatedly pay O(M log M) sorting and
materialization. This can delay MCP responses; it is **not** the Mac app's main thread because
the server is a separate executable. Offset pagination over changing data can repeat/skip rows
between calls even with a deterministic comparator. Nothing here establishes snapshot isolation
across requests.

**Suggested fix:** reuse an immutable candidate/DTO snapshot for a paging session if profiling
warrants it, with an explicit invalidation/version contract. Do not replace the comparator with
an inequivalent `SortDescriptor` or apply a limit before sorting. X-09 is an accepted constraint;
`CadenceReadServiceTests.swift:380,980` already assert paging metadata and store-level filtering.

## What CloudKit changes

**DOCUMENTED:** fetches read the currently local store, not a synchronous server query; exports
and imports are framework-scheduled. [Apple TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer?changes=_4).
**Correction:** “the whole store at once” is not an established atomic import guarantee. Apple
also documents relationship changes arriving nonatomically/out of order.
[Apple CloudKit model constraints](https://developer.apple.com/documentation/CoreData/creating-a-core-data-model-for-cloudkit?changes=_6_5%2C_6_5).

**REASONED:** initial sync can repeatedly invalidate visible queries while the replica grows,
amplifying repeated UI scans; relationships can fault as they arrive. It does not make local
sorting/payload processing cheaper. Startup maintenance does not automatically run again for
every imported batch, so do not multiply its full cost by a made-up batch count. A fresh empty
replica can initially be cheaper than a fully populated cold launch. Actual UI starvation from
import was not measured.

**DOCUMENTED:** sustained writes may trigger sync throttling that can last hours; the framework
recovers when throttles expire. [Apple TN3164, throttles](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer?changes=_9).
**REASONED:** a large archive import or repair that changes many rows can worsen sync delay.
An absent remote row then is not automatically a lost row. App UI, widget timelines and cloud
convergence need separate measurements.

## Smallest useful follow-up experiment

**REASONED plan, not executed:** use disposable, deterministic stores at 264, 1k, 5k and 10k total
rows. Keep a realistic mix, plus independent stress fixtures for long notes, image bytes, shared
goal-task graphs and many tagged notes. Measure cold launch/maintenance wall time, main-thread
long tasks, peak resident memory, search p50/p95, archive operations, each widget snapshot and MCP
first/last-page latency. Preserve output IDs/counts against the small-fixture reference.

First test the tag pass and archive UI work; then widgets/search; then a disposable two-device
initial sync with the same fixtures. Report time-to-first-usable-screen separately from time-to-
convergence. Proposed sizes are measurement checkpoints, **not** predicted failure thresholds.
No “breaks at N records” claim is justified by a read-only scan.
