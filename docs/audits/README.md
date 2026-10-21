# Audit Index

47 tracked files in six dated folders, 2026-09-05 to 2026-09-25. This index exists so the folder
can be answered without opening it: what each report audited, the one thing a reader would come
back for, whether anything still resolves to it, and who.

**Audits are never edited after their date.** Each one names a pinned tree sha and states what it
measured versus what it inferred; rewriting a September finding to match October's code destroys
the only thing a dated record is for. Their report-local finding ids (`AK-1`, `ROI-03`, `PR-2` …)
are addresses other files cite — see the Cited-by column — so they are not renumbered either.
Paths inside the reports still say `~/Desktop/Projects/Cadence`; the repo moved to
`~/Developer/Cadence` on 2026-10-19 (`T-3245`) and these two folders were deliberately left stale.

**SPENT is about this index, not about deletion.** SPENT means every finding landed or was
rejected under a CLOSED ledger entry and nothing outside `docs/audits/` resolves to the file any
more, so a reader can skip it. It is not permission to delete. `T-1226` committed this directory
precisely *because* 17 ledger citations rested on files that existed on one disk only; deleting a
SPENT audit re-creates that fault. Nothing here is deleted without the owner saying so.

**How the column was decided.** Against the ledger and the tree, not against the audit's own
conclusion — an audit saying "fixed" is a claim from September. Every ticket an audit feeds was
read with `./scripts/ledger-view.sh head T-NNNN`; every citation was found with
`grep -rno '[./a-z]*audits/20[0-9-]*/[A-Za-z0-9._/-]*'` over `*.swift`, `*.md`, `*.sh`, `*.rb`,
`*.yml`, `*.json`, excluding `.codex-build` and `.claude/worktrees`. LIVE means product code, a
test, a script, an OPEN/PARTIAL entry, or an inline answer still standing in
`docs/CODEX_REQUESTS.md` points at it.

## 2026-09-05 — five-area source audit (tree `4799e3c`)

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-05/README.md) | Batch index, evidence policy, patch order | Five reports; "measured" means a command ran, never that the app reproduced anything | SPENT | nothing |
| [`appkit-behavior.md`](2026-09-05/appkit-behavior.md) | Right-click overlays, custom `NSView` census | **AK-1**: two `hitTest(_:)` overrides name `point` and never read it — they answer "is this a right-click", which is true for every view in the window, so a sibling row can be answered for | **LIVE** | `CadenceTests/CadenceRightClickTriggerHitTestTests.swift:22` cites it **by finding id**; `T-1096` (DONE) |
| [`first-run-creation.md`](2026-09-05/first-run-creation.md) | Empty-store entry points | **FR-1**: a fresh macOS sidebar has no first-list entry point; the correct optional-context sheet exists but is unreachable | SPENT | `T-1113` (CLOSED) |
| [`recovery-export.md`](2026-09-05/recovery-export.md) | Store recovery and its copy | **RE-1** candidate fallback ends before export is attempted; **RE-2** terminal copy calls a recovery store a backup | SPENT | `T-1097` (DONE), `T-1099` (CLOSED) |
| [`grouping-spacing.md`](2026-09-05/grouping-spacing.md) | Settings/sheet grouping gaps | **SP-1**: one equal-gap design candidate, no confirmed rendering defect — explicitly *do not* reopen T-1041 | SPENT | `T-1107` (CLOSED) |
| [`commit-ledger.md`](2026-09-05/commit-ledger.md) | Commit ids versus ledger entries | **CL-1**: six modern commits have no entry in either ledger; the large legacy gap is known and must not be mass-backfilled | SPENT | `T-1106` (CLOSED) |
| [`commit-ledger-inventory.json`](2026-09-05/commit-ledger-inventory.json), [`ledger-inventory.rb`](2026-09-05/ledger-inventory.rb) | CL-1's generated data and its reader | Reproduces the six-entry gap against `4799e3c` | SPENT | only other audits (`2026-09-06`, `2026-09-25`) |

### 2026-09-05/batch-02 — five failure-path audits (tree `9b31280`, finished 2026-09-06)

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-05/batch-02/README.md) | Batch index | Six findings, all *inferred* from source; none is a runtime reproduction | SPENT | nothing |
| [`backup-replacement.md`](2026-09-05/batch-02/backup-replacement.md) | Multi-file store replacement | **BR-1**: a failed rollback is followed by deleting the displaced originals | SPENT | `T-1100` (CLOSED) |
| [`privacy-reset.md`](2026-09-05/batch-02/privacy-reset.md) | Destructive reset boundary | **PR-1** Keychain deletion failure is swallowed; **PR-2** a database failure can leave a partial delete pending | SPENT | `T-1101`, `T-1102` (both CLOSED) |
| [`focus-continuity.md`](2026-09-05/batch-02/focus-continuity.md) | Focus timer ownership | **FC-1**: Mac banks elapsed time from view ticks, and the only producer sits inside a conditional screen | SPENT | `T-1103` (CLOSED) |
| [`image-import-transaction.md`](2026-09-05/batch-02/image-import-transaction.md) | iOS photo import | **IM-1**: pending image rows are created across photo-loading suspension points | SPENT | `T-1104` (CLOSED) |
| [`reminders-refresh-ordering.md`](2026-09-05/batch-02/reminders-refresh-ordering.md) | EventKit refresh callbacks | **RM-1**: an older fetch can overwrite newer state or a successful completion | SPENT | `T-1105` (CLOSED) |

## 2026-09-06 — request-queue follow-up (tree `5aac94d`)

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`request-follow-up.md`](2026-09-06/request-follow-up.md) | R31–R33/R37/R38 re-reading: stale claims, manifest, ledger ids, contrast arithmetic | **T-1043 was allocated twice, to unrelated work** — one copy closes an editor image fix, the other opens a calendar-link test gap. Also: the App Store copy overpromises settings sync, and the old accent-contrast numbers measured white-on-fill, not accent-on-page, so most of that population was a wrong diagnosis rather than a defect | SPENT | `T-1098`, `T-1107`, `T-1108` (all CLOSED) |
| [`grouping-candidates.json`](2026-09-06/grouping-candidates.json), [`request-ledger-inventory.json`](2026-09-06/request-ledger-inventory.json) | Generated spacing and ledger-id candidate sets | Lexical candidate lists, not proof of a painted gap or a real collision | SPENT | only `request-follow-up.md` |

## 2026-09-07 — import and restore (tree `4ad2178`)

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-07/README.md) | Batch index, patch order | Five issues, all **reasoned**, none reproduced in a running app | SPENT | `docs/CODEX_TODO.md:84` names the directory as historical record; `T-1178` (CLOSED) |
| [`import-recovery.md`](2026-09-07/import-recovery.md) | Restore failure boundaries | **ROI-01**: import reports undifferentiated failure *after* rows have committed, so a post-commit migration failure reads as a refused import | SPENT | `T-1111` (CLOSED) |
| [`import-graph.md`](2026-09-07/import-graph.md) | Imported goal graph validation | **ROI-02**: import accepts parent-goal cycles with no Goals-page root, including cycles completed through destination rows | SPENT | `T-1109` (CLOSED) |
| [`import-reconciliation.md`](2026-09-07/import-reconciliation.md) | Post-import reconciliation | **ROI-03** import does not reconcile pending reminders; **ROI-04** imported focus logs and stored totals can disagree | SPENT | `T-1112`, `T-1114` (both CLOSED) |
| [`recent-fix-claims.md`](2026-09-07/recent-fix-claims.md) | Re-checking `a7184f2` and `7ae1c61` | Main fixes are present; **ROI-05** is the narrower iOS case where a new tag survives behind "Nothing was changed" | SPENT | `T-1110` (CLOSED) |

## 2026-09-20 — two batches (trees `1857938` and `231a7a8`)

### release-data-scale — R51–R54

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-20/release-data-scale/README.md) | Batch index, duplicate check, suggested order | Four research reports; the user's store was never opened and no performance benchmark was run | SPENT | nothing |
| [`privacy.md`](2026-09-20/release-data-scale/privacy.md) | R51 — privacy manifest and entitlements | Shared `UserDefaults` declarations are missing **and the tests pin the wrong declarations**, so the guard could not have caught it | **LIVE** | `T-1310` (CLOSED); `docs/CODEX_REQUESTS.md:3537` |
| [`data-loss.md`](2026-09-20/release-data-scale/data-loss.md) | R52 — nine destructive/loss paths ranked | Context deletion crosses a task's container boundary through its goal; post-commit reset cleanup still throws undifferentiated failure | **LIVE** | `docs/CODEX_REQUESTS.md:3591` — no ledger entry of its own |
| [`model-release.md`](2026-09-20/release-data-scale/model-release.md) | R53 — schema deploy ordering | Deploy additive schema *before* the dependent build; server deployment and local model migration are different things with different older-client behaviour | **LIVE** | `docs/CODEX_REQUESTS.md:3646` — no ledger entry of its own |
| [`scale.md`](2026-09-20/release-data-scale/scale.md) | R54 — startup and archive cost | Startup fetches the whole tag table **once per tagged note**; archive work is synchronous on UI paths. No measured failure threshold | **LIVE** | `docs/CODEX_REQUESTS.md:3694` |
| [`inventory.rb`](2026-09-20/release-data-scale/inventory.rb) | Reproducible lexical inventory | Deliberately lexical: no claim about conditional compilation or runtime reachability | SPENT | its own README and `scale.md` |

### request-queue — R41–R50

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-20/request-queue/README.md) | R41–R50 in one document | **R41**: the removal guard counts *line membership*, not diff deletions, and replaying it over history would demand an acknowledgement on 950/1,137 commits (83.55%). **R49**: an undeployed Production schema can abort mirroring for *every* record type, so "everything fails to sync" does not exonerate one type. Also two guard gaps (whitespace-sensitive defaults routing, message-file ownership accepting a sibling with an overlapping id) and five comment claims that were born or aged false | **LIVE** | `docs/CODEX_REQUESTS.md` ×7 (R41, R42/R46, R47, R48, R49, R50, limits); `T-1294`, `T-1318`, `T-3122` (all CLOSED) |
| [`source-candidates.tsv`](2026-09-20/request-queue/source-candidates.tsv) | 968 KB of selected assertions and their sites | The largest generated artefact here; named as a prose-only occurrence in the `CADENCE_UI_TEST_STORE_ID` census | **LIVE** | `T-3015` (**PARTIAL**, open); `docs/CODEX_REQUESTS.md:3098` |
| [`source-candidates.swift`](2026-09-20/request-queue/source-candidates.swift), [`text-probes.swift`](2026-09-20/request-queue/text-probes.swift) | The two script-style Swift probes | **Do not move or merge these.** They are the worked example behind `agent-commit.sh`'s per-file parse gate: alone they parse clean, batched into one `swiftc` they raise eight *statements are not allowed at the top level* errors — which is why the gate is one invocation per file | **LIVE** | `scripts/agent-commit.sh:1877` |
| [`guard-probes.rb`](2026-09-20/request-queue/guard-probes.rb), [`history-removals.rb`](2026-09-20/request-queue/history-removals.rb) | Executable probes behind R41 and the guard gaps | `history-removals.rb <sha>` reproduces the 83.55% figure | SPENT | only `request-queue/README.md` |

## 2026-09-22 — sync coverage and rollback, R64/R65 (tree `d819a4c`)

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-22/sync-rollback/README.md) | Batch index | Source eligibility is not device proof; no runtime CloudKit result is claimed | SPENT | nothing |
| [`coverage.md`](2026-09-22/sync-rollback/coverage.md) | R64 — what syncs and what does not | All 23 model types are present, and **custom note templates are the one real gap** against "all data should sync": every other device-local thing has a reason (window geometry is about a device, the OpenAI key is a `ThisDeviceOnly` boundary, EventKit ids differ per account) but a template the user *wrote* is the same kind of thing as a note | **LIVE** | `Cadence/Models/NoteTemplatePreference.swift:7` — the model's doc comment rests on it; `T-1346` (CLOSED) |
| [`model-fields.md`](2026-09-22/sync-rollback/model-fields.md) | Complete model/field inventory | 256 stored declarations including all 62 relationship endpoints | **LIVE** | `docs/CODEX_REQUESTS.md:4231` |
| [`rollback.md`](2026-09-22/sync-rollback/rollback.md) | R65 — rollback and restoration | Restoration is documented, a 26→27 semantic change is **not** established by the reviewed notes, and edit-free source is not proof of immediate UI recovery | **LIVE** | `docs/CODEX_REQUESTS.md`; `T-1349` (CLOSED) |
| [`model_inventory.rb`](2026-09-22/sync-rollback/model_inventory.rb) | Read-only inventory emitting exact defaults | Re-run against any committed snapshot | **LIVE** | `docs/CODEX_REQUESTS.md:4232` |

## 2026-09-25 — queue research handoff (tree `c8735e4`)

| Report | Subject | Headline finding | State | Cited by |
| --- | --- | --- | --- | --- |
| [`README.md`](2026-09-25/README.md) | Batch index + an "evidence still needed" table | Answered is not runtime-certified; the table names ten bounded verifications still owed | **LIVE** | `docs/CODEX_REQUESTS.md` |
| [`queue-reconciliation.md`](2026-09-25/queue-reconciliation.md) | R32–R35, R37–R38 re-reading | Updated counts and closures; **no duplicate tickets** — the first-list, grouping, routing and hit-test work had already been repaired. It also caught `Cadence/Services/AGENTS.md` telling every agent the archive was "Export only" for 19 days after the importer shipped | **LIVE** | `docs/CODEX_REQUESTS.md` ×6 (R32–R38 anchors); `T-1136`, `T-1361` (both CLOSED) |
| [`naming-screen.md`](2026-09-25/naming-screen.md) | R55/R56 — product name and icon assets | **All eight candidate names conflicted, and the selected folded-D artwork is not in the repo** — commit `1107671e` added only the concept directory's README, so no render clearance can be invented | **LIVE** | `T-16` (**OPEN** — still blocked on exactly this); `docs/CODEX_REQUESTS.md:3773,3832` |
| [`accessibility-sdk.md`](2026-09-25/accessibility-sdk.md) | R57/R60 — text scaling, 26→27 SDK | A staged text-scaling plan, and an exact line between documented Apple contracts and unmeasured framework observations | **LIVE** | `T-1364` (CLOSED 2026-10-20); `docs/CODEX_REQUESTS.md:3889,4000` |
| [`mcp-widget-startup.md`](2026-09-25/mcp-widget-startup.md) | R58/R59/R62 — MCP authority, widgets, startup | MCP write authority is **store-wide once enabled**; real widget failure paths are enumerated; startup targets remain unmeasured | **LIVE** | `T-1365`, `T-1366` (both CLOSED); `docs/CODEX_REQUESTS.md:3931,3966,4104` |
| [`recent-fix-claims.md`](2026-09-25/recent-fix-claims.md) | R61 — re-checking recent fix claims | Three focused coverage/oracle recommendations; **no new demonstrated destructive regression** | **LIVE** | `docs/CODEX_REQUESTS.md:4041` — no ledger entry of its own |
| [`queue-inventory.json`](2026-09-25/queue-inventory.json), [`queue_inventory.rb`](2026-09-25/queue_inventory.rb) | 1.2 MB generated dataset and its reader | Lexical history differences, repeated-id candidates, native-view declarations, font and spacing counts | SPENT | only `queue-reconciliation.md` |

## Reading one without opening it

- A report's own front matter block gives the pinned tree sha, the dirty-file count and what was
  **not** run. Every report states it explicitly; none claims a build, test or app launch.
- `MEASURED` / `MEASURED-SOURCE` means a command ran or source was inspected. `MEASURED-PROBE`
  means the probe executed. `DOCUMENTED` means an Apple primary source. `REASONED` / `inferred`
  means a consequence, not a reproduced incident. No audit in this folder reproduced a runtime bug.
- Report-local ids (`AK-1`, `ROI-03`, `G3`, …) are **not** T-numbers and allocate none.
- To check a finding against today's tree, `rg` the symbol it names rather than trusting the
  report's line numbers — references are anchored to the pinned sha and have drifted.
