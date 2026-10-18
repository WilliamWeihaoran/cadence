# Overnight batch plan — 2026-10-18

Supersedes the 2026-10-17 plan. **Tracked in git on purpose**: the first copy lived in
`scratchpad/` and an agent deleted it during cleanup.

## Why this one has a mechanism and the last one did not

The 2026-10-17 plan listed five batches and only batch 1 ran. The coordinator is turn-based —
it acts when invoked and stops — and nothing drove batch advancement except being poked. Nine
hours of capacity went unused because a batch-1 agent was never launched after its dependency
cleared.

**A recurring scheduled task now advances this queue.** It fires regardless of whether the owner
is present, re-reads this file, and starts the next batch whose dependencies are met. If the
scheduled task is cancelled, this plan stops — that is the single point of failure and it is
named here deliberately.

## Standing rules

- 3 agents per batch, 2–3 tickets each, grouped by file locality so siblings cannot collide.
- Commit each agent's work as soon as it is green; never hold a batch for its slowest member.
- **The usage ceiling is suspended until 2026-10-18 14:06** by the owner. After that the 80/90
  rule applies again automatically.
- The session limit has fired **three times** in this run, killing agents mid-flight each time.
  Nothing was lost because work was backed up and resumed — keep doing both.
- **Local green is NOT the finish line.** This Mac runs Xcode 27, CI pins 26.0.1, and CI was red
  for 27 pushes while every local check reported green ([[T-3215]]). CI is the gate.

## Before any batch starts

Check these, because they move:
1. `git status` — a path dirty is a path someone is inside, lease or no lease.
2. `./scripts/agent-commit.sh check` must exit 0.
3. For any leased path: `git log --no-merges main..<branch> -- <path>`, then read the SHAPE of
   what comes back. `docs/CODEX_WORKTREE.md` carries six corrections to that check and the
   reason each failed.

## Batch A — the Block tail and the board

| agent | tickets | notes |
|---|---|---|
| `staleclaims` | the 6 fixable stale claims | Reword where the symbol is stale but the substance is live. Leave `TaskCreationService.swift`'s line — a live Codex agent holds it. |
| `blockchain` | T-3214 | The Block move chain reachable only from its own tests. Decide: goes with the `@Model`, or now. Retire the 5 test call sites in the same change if now. |
| `boardreconcile` | T-1478 | PARKED no longer — `CalendarPageBoardSupportViews.swift` was granted in `d1162e10`. Land PA-13's sibling. |

## Batch B — the information gaps

| agent | tickets |
|---|---|
| `macrowinfo` | T-1467 — macOS notes excerpt AND inline subtasks with checkboxes |
| `alldaycap` | T-1474 — cap `min(T, min(cap/2, 3))`, 6 iPhone / 8 iPad, macOS adopts the shared rule, multi-day fixture pins the span rule |
| `cascade47` | T-3193 — raise the cascade threshold to 47 minutes AND measure how often it then fires |

## Batch C — the broken guards

Three repo guards were found defective on 2026-10-17, each by an agent hitting it while doing
something else. All three are filed and none is fixed.

| agent | tickets |
|---|---|
| `claimguard` | T-3209 — the comment-claim detector. **Read the rewritten ticket**: the real hole is the existence guard at `:412`, not the `^[A-Z]` anchor, and the originally-prescribed fix does not work. |
| `mutateparam` | T-3212 — `mutate.sh` cannot baseline a parameterised test; `_ran()` needles `Test <name>()` with empty args |
| `menueffect` | T-3210 — the Mac context menu is pinned by parity, not by effect; no test invokes an action against a model |

## Batch D — the iOS halves, once their leases clear

| agent | tickets |
|---|---|
| `iosrowchrome` | T-3196 / T-3197 iOS halves — **needs `CadenceTests/CadenceCodexTaskRowTypographyTests.swift`**, request the grant first |
| `inlinepanel2` | T-1481 iOS half — the shared panel inline in the note |
| `capturland` | land `codex/capture-list-sections` once its calendar dependency clears |

## Batch E — the last two, and the build

| agent | tickets |
|---|---|
| `iosbackup` | T-1477 — iOS backup and staged restore. **OWNER RULING 2026-10-18, asked before the runner could reach it: BUILD IT, but it must not touch any real store.** Disposable stores under the test's own temp directory only. The restore PATH is tested; the restore is never exercised against the owner's data, the real app group, `~/Library/Containers/com.haoranwei.Cadence/Data/`, any `Cadence Store Backups` directory, the `Recovery/` store or the legacy stores. The owner reviews before anything runs for real. **This is the one ticket in the plan where a mistake costs data rather than a red test** — if any step cannot be done against a disposable store, stop and file it rather than improvising. |
| `widgetent` | T-3152 — widget iCloud entitlement; a signing-input change wanting its own diff and a two-device run |
| `build23` | bump `CURRENT_PROJECT_VERSION` 22 → 23 and archive — **ONLY if CI is green and the T-3215 crash is diagnosed** |

## Not in any batch

- **T-3168, the rail** — needs the owner's eyes. Three independent blocks have stopped a machine
  looking: the computing agent could not navigate, iOS had no fixture door (T-1483, landing now),
  and macOS window capture needs an Accessibility grant the coordinator may not make.
- **T-3125** — research the coordinator owes the owner on where name-merging fires.
- **T-3215's crash** — agent `cicrash` has it. It gates build 23 and nothing else should touch it.

## Run log

- 2026-10-18 (batch runner): launched **Batch A** — `staleclaims`, and `boardreconcile` carrying BOTH T-1478 and T-3214. `blockchain` not launched as a separate agent: T-3214 and T-1478 edit the same leased `CalendarPageBoardSupportViews.swift` and `CalendarBoardDayDropCommitTests.swift`, so two agents would collide; folded into `boardreconcile` (T-3214 first). Third slot left empty rather than pulling Batch B forward. Note for both: `CalendarBoardDayDropCommitTests.swift` and `CadenceTaskMutationSupport.swift` are leased with no explicit grant found — agents told to stop and park if needed. CI gate for Batch E not checked this run (E not reached).
- 2026-10-18 01:25 (batch runner): **launched nothing.** Batch A (`staleclaims`, `boardreconcile`) was launched by the previous run at ~01:22, three minutes earlier, and has no commits yet; with `cicrash` on T-3215 and an unknown worker inside the iOS calendar/markdown files (all dirty at 01:12, `iOSCalendarMonthViews.swift` staged) the live count is at or over 3. Batch B not pulled forward: `alldaycap` (T-1474) would land on those dirty iOS calendar files. CI gate (E): latest CI run on `f75a5d24` in progress, previous two failed — `build23` stays blocked.
- 2026-10-18 ~02:30 (batch runner): Batch A complete (T-1478 CLOSED `2183583d`, T-3214 PARKED `885b7744` on an ungranted leased test file, stale claims 7 -> 1 in `c3c139be`); no agents live. **Launched Batch B** — `macrowinfo` (T-1467), `alldaycap` (T-1474; told to land shared rule + iOS and PARK the macOS half if its leased calendar files are ungranted), `cascade47` (T-3193). Skipped nothing in B. CI gate (E): latest CI run on `b6704d56` in progress, previous two failed — `build23` stays blocked. Untracked `CalendarPageView.swift.orig` (2026-10-16) is stale, left untouched.
- 2026-10-18 ~07:10 (batch runner): Batch B state — T-3193 CLOSED `5457df89`, T-1474 PARTIAL `d6c1c080` (macOS half parked on the `CalendarPageMonthSupportViews.swift` lease), `macrowinfo` (T-1467) still live (its full macOS test run in progress, six T-1467 paths dirty). Live count 1, so **launched two of Batch C** — `claimguard` (T-3209, both holes) and `mutateparam` (T-3212, both halves + selftest fixture); both target files unleased and clean. **Skipped `menueffect` (T-3210):** the slot cap would be exceeded, the ticket says it is only worth doing if the owner wants the menu defended by effect and no ruling is recorded, and its Mac row neighbourhood is where `macrowinfo` is working. CI gate (E): last three CI runs failed (latest on `b6704d56`) — `build23` stays blocked.
- 2026-10-18 05:30 (batch runner): Batch C state — T-3212 CLOSED `40ebe465`; `claimguard` (T-3209) still live (filed T-3224 stub, its comment-fix files dirty since 03:51); a heartbeat full `CadenceTests` run also live. Live count 2, so **launched one: `iosbackup` (T-1477, Batch E)** under the owner's disposable-stores-only ruling; its iOS settings/persistence files unleased and clean. Skipped: `menueffect` (T-3210) — still no owner ruling recorded; `iosrowchrome` (T-3196/T-3197 iOS) — needs ungranted `CadenceTests/CadenceCodex*.swift` (Codex's reserved namespace) plus leased `iOSTaskViews.swift`; `inlinepanel2` (T-1481 iOS) — needs leased `iOSMarkdownEditor.swift` and the iOS markdown files are dirty under `claimguard`; `capturland` — the `iOSCalendarManager` grant published in `e6a226b6`, but `codex/capture-list-sections` (last commit 2026-10-17 22:54) still records itself NOT READY TO LAND pending the recurrence-end API on the branch; `widgetent` (T-3152) — slot cap; `build23` — CI run on `6717a9b3` in progress, previous two failed.
- 2026-10-18 06:30 (batch runner): T-1477 PARTIAL `66a58761` (`iosbackup` done); `claimguard` (T-3209) presumed still live — its 8 files dirty since 03:43–03:51, no commit since; heartbeat `hbhead` full `CadenceTests` run live. Live count 2, so **launched one: `widgetent` (T-3152)** — entitlements file, project.pbxproj and `AppStoreReviewReadinessTests.swift` unleased and clean; told to land in its own commit, mark PARTIAL pending the owner's two-device run, and flag that build 23 should not ship it unmeasured. Skipped: `build23` — CI is green on `6717a9b3` (run `39114597872`) and T-3215's crash is diagnosed with fix `2264d690`, but `main` is 5 commits ahead of `origin/main` (incl. T-1477 product code in `66a58761`) that CI has never seen, and the runner has no push authority, so the archive would be of unproven code; `menueffect` (T-3210) — still no owner ruling; `iosrowchrome` — ungranted `CadenceTests/CadenceCodex*.swift`; `inlinepanel2` — leased `iOSMarkdownEditor.swift` and iOS markdown files dirty under `claimguard`; `capturland` — not re-checked, slot cap.
- 2026-10-18 ~11:30 (batch runner): **launched nothing — every remaining agent is gated.** T-3152 PARKED `9c0c00f5` (`widgetent` done; owner must enable iCloud on the widget extension's App ID). Live: one scoped `CommentSymbolClaim` test run (`hbclaim`, T-3209's `claimguard` neighbourhood; its iOS markdown/test files still dirty). Skipped: `build23` — `main` is now pushed (0 ahead), but CI run `39120274586` on the T-1477 product commit is still in progress, so the code to archive is not yet proven green; `menueffect` (T-3210) — still no owner ruling; `iosrowchrome` — `CadenceTests/CadenceCodex*.swift` and `iOSTaskViews.swift` / `iOSTaskRowActionViews.swift` still leased, no grant; `inlinepanel2` — `iOSMarkdownEditor.swift` / `iOSMarkdownEditingSurface.swift` still leased and the iOS markdown files dirty; `capturland` — `codex/capture-list-sections` unchanged since 2026-10-17 22:54, still not ready to land. Next run: `build23` becomes eligible once that CI run is green.
- 2026-10-18 08:28 EDT (batch runner): **launched nothing — every remaining agent is still gated.** T-3209 CLOSED `17889d38` (`claimguard` done); no agents live, tree clean apart from the stale `.orig`. Skipped: `build23` — CI run `39120274586` on `66a58761` FAILED, but only its `ledger-lag-check.sh` job (LEDGER-CLOSURE-LAGGED: the T-1477 code commit did not carry its own PARTIAL line; the ledger came one commit later in `49b486c6`); its `CadenceTests (macOS)`, iOS and MCP jobs were green, so the T-3215 crash fix looks held but is not yet a green CI run. Run `39124774496` on `17889d38` is in progress — `build23` becomes eligible only when that comes back green. `menueffect` (T-3210) — still no owner ruling; `iosrowchrome` — `CadenceTests/CadenceCodex*.swift`, `iOSTaskViews.swift`, `iOSTaskRowActionViews.swift` still leased, no grant committed since the last run; `inlinepanel2` — `iOSMarkdownEditor.swift` / `iOSMarkdownEditingSurface.swift` still leased; `capturland` — `codex/capture-list-sections` unchanged since 2026-10-17 22:54.
- 2026-10-18 (batch runner): **launched `build23` (Batch E)** — CI run `39124774496` on `17889d38` is GREEN, `main` == `origin/main`, T-3215's crash diagnosed (fix `2264d690`, now CI-proven); Xcode not open, `project.pbxproj` unleased and clean. Agent told: bump 22 -> 23, archive LOCALLY only, no upload/push, T-3152 entitlement stays out. Skipped: `menueffect` (T-3210) — still no owner ruling; `iosrowchrome` / `inlinepanel2` — no new grant in `docs/CODEX_WORKTREE.md` since `3c259097` (01:48), their files still leased; `capturland` — `codex/capture-list-sections` unchanged since 2026-10-17 22:54. After `build23`, every remaining agent waits on an owner ruling or a lease.
- 2026-10-18 ~10:30 EDT (batch runner): **launched nothing — every remaining agent is gated.** T-3228 CLOSED `76deb653` (`build23` done: bumped 22 -> 23, archived locally; push, CI and upload are the owner's); CI run `39135582428` on it in progress. No agents live, tree clean apart from the stale `.orig`, `agent-commit.sh check` exit 0. Skipped: `menueffect` (T-3210) — still no owner ruling; `iosrowchrome` (T-3196/T-3197 iOS) and `inlinepanel2` (T-1481 iOS) — no new grant in `docs/CODEX_WORKTREE.md` since `3c259097` (01:48), files still leased; `capturland` — `codex/capture-list-sections` unchanged since 2026-10-17 22:54 (`8f33d5ce`). Batches A–E are all launched or gated on an owner ruling or a lease; the queue is idle until one moves.
- 2026-10-18 (batch runner): **launched nothing — every remaining agent is still gated.** CI run `39135582428` on `76deb653` (T-3228, build 23) came back GREEN. No agents live, tree clean apart from the stale `.orig`, `agent-commit.sh check` exit 0. Skipped: `menueffect` (T-3210) — still OPEN, no owner ruling; `iosrowchrome` (T-3196/T-3197 iOS) — `iOSTaskViews.swift`, `iOSTaskRowActionViews.swift`, `CadenceTests/CadenceCodex*.swift` still leased (fnmatch), no new grant since `3c259097`; `inlinepanel2` (T-1481 iOS) — `iOSMarkdownEditor.swift` / `iOSMarkdownEditingSurface.swift` still leased; `capturland` — `codex/capture-list-sections` unchanged since `8f33d5ce` (2026-10-17 22:54). Queue idle until an owner ruling or a grant lands.
- 2026-10-18 (batch runner): **launched nothing — no gate moved.** No agents live, tree clean apart from the stale `.orig`, `agent-commit.sh check` exit 0, latest CI run `39135582428` (T-3228) green. Skipped: `menueffect` (T-3210) — still OPEN, no owner ruling; `iosrowchrome` (T-3196/T-3197 iOS) — `Cadence/iOS/iOSTaskViews.swift`, `iOSTaskRowActionViews.swift`, `CadenceTests/CadenceCodex*.swift` still leased (fnmatch), no grant since `3c259097`; `inlinepanel2` (T-1481 iOS) — `Cadence/iOS/iOSMarkdownEditor.swift` / `iOSMarkdownEditingSurface.swift` still leased; `capturland` — `codex/capture-list-sections` unchanged since `8f33d5ce` (2026-10-17 22:54). Queue idle until an owner ruling or a grant lands.
- 2026-10-18 (batch runner): **launched nothing — no gate moved.** No agents live, tree clean apart from the stale `.orig`, `agent-commit.sh check` exit 0, latest CI run `39135582428` (T-3228) green. Skipped: `menueffect` (T-3210) — still OPEN, no owner ruling; `iosrowchrome` (T-3196/T-3197 iOS) — `iOSTaskViews.swift`, `iOSTaskRowActionViews.swift`, `CadenceTests/CadenceCodex*.swift` still leased (fnmatch), no grant since `3c259097`; `inlinepanel2` (T-1481 iOS) — `iOSMarkdownEditor.swift` / `iOSMarkdownEditingSurface.swift` still leased; `capturland` — `codex/capture-list-sections` unchanged since `8f33d5ce` (2026-10-17 22:54). Queue idle until an owner ruling or a grant lands.
