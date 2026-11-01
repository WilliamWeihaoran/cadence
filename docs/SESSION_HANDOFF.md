# Session Handoff

Written 2026-10-27 at `c258c14f`; section 2 rewritten 2026-10-29 at `e5a1da4b`. **This file is
point-in-time state and nothing else.** Every general rule — build and test, the Codex lease, the
commit gates, safety, how the owner wants work reported — lives once in
[docs/AGENT_BRIEF.md](AGENT_BRIEF.md), which is the first thing to read. Then this, then
[AGENTS.md](../AGENTS.md) for the directory map and the UI patterns.

If a rule and this file disagree, the brief wins; this one is a snapshot and snapshots rot.

---

## 1. What Cadence is, and where it lives

**Cadence** is a native SwiftUI + SwiftData productivity app: macOS primary, large iOS/iPadOS
surface, CloudKit `.private("iCloud.com.haoranwei.Cadence")`, widgets, EventKit, and an MCP server
boundary. The owner does not write code — work is done by agents and verified against the tree,
never against an agent's report.

**Build 25 shipped 2026-10-27 to internal TestFlight, macOS and iOS.** The RC is an internal
TestFlight build, not an App Store submission. `a749c0c2` (2026-10-26) bumped
`CURRENT_PROJECT_VERSION` 24 -> 25 on the app and widget targets; the test bundles still read 24
and the MCP server 1, and none of those ships. **The next upload needs a build number above 25.**
The upload itself is the owner's (Xcode Organizer); nothing in the tree records it, so the
shipped date is the owner's word, not a commit.

**Zero ledger entries are RC-blocking** (`a49454de` gave every active entry an RC-TRIAGE verdict;
`ledger-view.sh untriaged` lists those filed since). **POST-RC is now the live queue.** A
defect the owner reports from the TestFlight build outranks anything an agent would pick itself:
T-7550 (a finger could not scroll the iOS Today timeline) is the example, reported from build 25
and CLOSED the same day, seen on screen.

The repo lives at `~/Developer/Cadence` (moved off the iCloud-synced Desktop in T-3245). The old
path outside `docs/audits/` and `docs/TODO.md` is stale — and the shared checkout's own
`core.hooksPath` still points at it (T-4900).

## 2. Current state

- `main` and CI: `git fetch -q && git rev-list --count origin/main..main` for your unpushed count;
  `gh run list --branch main --workflow CI -L 5` for CI (a docs-only commit gets no CI run).
- Worktrees and local branches are many (`git worktree list`, `git for-each-ref refs/heads`). Before
  trusting a branch, check it has a remote counterpart: `git show-ref --verify refs/remotes/origin/<b>`.
- **Anything dirty in `git status` is a sibling's**, as are `scratchpad/<agent>/` dirs at the
  repo root; leave them. Work is scheduled by the `cadence-keeper` routine, which reserves an id
  range per agent; take ids only from a range you were given. The open reservations, and which
  agent holds each (match a dirty path to it with `head` on the tickets it names):

  ```sh
  git show HEAD:docs/TODO.md | sed -nE 's/^- \[(T-[0-9]+)\] \*\*OPEN[^)]*\) -- (ids T-[0-9.T-]+ reserved( for agent `[^`]+`)?).*/\1 \2/p'
  ```
- `T-8201` is a standing owner ruling: macOS and iOS are one app; a difference must name the
  hardware or input that forces it. Read it before any platform-specific change.

### Open work

`./scripts/ledger-view.sh brief` is the live list (139 active entries at `e5a1da4b`); an entry's
own lead token is the only authority, read with `head T-NNNN`. Grouped by who can move it:

**Owner calls.** Rebuilt 2026-10-31 by `ownercalls2221` at `06d7bd13`; today's and a sample of older
citations re-read on HEAD, none yet fixed. Each line: the question, then what an agent applies on "yes".

*Wording*
- `T-9571` Title Case in-panel headings? Yes: "Task Notes", "Edit Tag", "Unlinked Mentions" (the last needs a `CadenceUITests` run).
- `T-9572` Missing-access alert reuses the Settings card's per-platform sentence? Yes: one string, from `CadenceCalendarAccessNotice.detail(on:)`.
- `T-9627` Drop "Set this tab's color and visibility." from the sidebar tab editor? Yes: the header is glyph + name.
- `T-7210` Retitle the AI row "Selected note content"? Yes: "The note you run it on" + one shared detail, both platforms.
- `T-7209`(b) Delete Account copy lists everything it deletes? Yes: full list, both platforms.
- `T-7291` One word set for the AI review sheets? Yes: the Mac's ("Close", "Append to Note", "AI Task Drafts").
- `T-7085` A board's new column is "New Column"? Yes: "New Column"/"Add column" on Kanban; "section" stays on Tasks.
- `T-6984` iOS Search's "More" chip becomes "Pages"? Yes: chip matches its section.
- `T-7941` Replace the iCloud card's developer copy? Yes: two plain sentences in `CadenceSyncHealth.resolve`.
- `T-8012` Focus picker drops "Best matches / 18"? Yes: real count; "Best matches" only while searching.
- `T-8534` Note row menus say "Delete Note"? Yes: one shared label.
- `T-8563` One spelling for each of the five list-surface word pairs? Yes: the Mac's, as shared constants.
- `T-8586` One empty-note placeholder? Yes: one sentence (verbs may differ by input), template row on iOS too.
- `T-8723` Month event chips spell time the Mac's way ("9 AM", "ends 5 PM")? Yes: one shared helper.
- `T-8645` Retire the iPhone More "Progress" eyebrow over a lone Focus row? Yes: drop single-row eyebrows.
- `T-8542` Show a template's description in the iOS new-note menu? Yes: subtitle there; no: placeholder "Short description".
- `T-8526`, `T-8763` One list subtitle and one task subtitle in Search and Cmd+K? Yes: the Mac's fact sets via one helper.

*Look*
- `T-9601` `.cadencePlain` takes the plate's shape (circle/capsule) on ~9 round plates? Yes: shaped wash; no: those go `.plain`.
- `T-9603`, `T-9626` Plates that brighten themselves drop the blue wash (Focus picker/sidebar, add-card row, Cmd+K Completed)? Yes: `.plain`, own hover.
- `T-9625` One Mac Settings switch style? Yes: regular size, system accent (drop `.small`/`Theme.blue` in the tab editor).
- `T-8243` iOS calendar chips get the Mac's due tint and `CalendarChipDueMarker`? Yes: port both.
- `T-8104` Unset New Task date chips show words, Do uses the sun? Yes: worded chips; flag stays on Priority.
- `T-8044` Timed Month task chips show start time and sort first? Yes: event-chip time slot, both platforms.
- `T-8001` Mac Today all-day band aligns to the block column? Yes: band follows the blocks.
- `T-8941` Mac Today keeps its Timeline at the minimum window? Yes: lower a pane minimum by 4pt.
- `T-8535` A list's Task Notes row draws the Mac's anatomy on iOS? Yes: one row.
- `T-8587` Linked-note sheet uses a generic bar title? Yes: "Note", Done trailing.
- `T-7257` Mac Links tab swaps "Saved Links" for iOS's "Add Link" button? Yes.
- `T-7943` First-run iPad Lists shows one empty state? Yes: the chooser's; detail column blank.
- `T-7421`(3) XL widget columns truncate a name above a minimum width instead of dropping it? Yes.

*Behaviour or scope*
- `T-9613` iOS Week all-day task chip opens the task, like the event chip, the Mac and `T-8725`'s ruling? Yes: opens the inspector.
- `T-8395` Note and Focus embed circles join the 1.2s deferred completion? Yes: both platforms.
- `T-8101` Mac list picker checks the task's current list? Yes: check and highlight open on it.
- `T-8107` Row-menu Do/Due submenus show the current date? Yes: "Due Date: Fri, Oct 31" + checked row.
- `T-7985` Drop Group: By List from the Mac Inbox? Yes: None / Date / Priority only.
- `T-7981` Rollover banner gets "Not now"? Yes: dismiss for today, rows return to their groups.
- `T-7874` iOS Save forms keep a draft across background-kill? Yes: per-sheet draft offered back; no: keep as is.
- `T-8103`(b) Mac New Task scrim click keeps the draft? Yes: keep, as quick capture does.
- `T-7290` Cmd+Return creates in the Mac AI draft sheet? Yes: bind Cmd+Return (plain Return stays in fields).
- `T-7259` Saved links editable? Yes: edit via the prefilled add form; reorder waits.
- `T-7260` A Mac list drop onto another context re-files it? Yes: re-file; no: refuse the drop.
- `T-7074` iOS Settings shows one Week / Month / Board "Calendar view" row? Yes.
- `T-7203` Adopt View-menu option (a), keep Cmd+O for the sidebar? Yes.
- `T-7182`(a) Bundle-retirement hazard: leave a member alone if its schedule changed since joining? Yes.
- `T-8981` Delete Account also deletes `Cadence Store Backups`? Yes: delete them too.
- `T-8564` iOS column swipe-delete confirms like the Mac? Yes.
- `T-8565` iOS list Kanban gets Show Archived? Yes.
- `T-8562`, `T-8584` One list-editor field set; one note toolbar and `/` command set? Yes: one shared list each.

*Needs the owner present (a look, an account, or hardware)*
- `T-8724` Month-grid cell anatomy: held for a side-by-side owner look at both grids.
- `T-9614` iOS board card lift: square corners? Yes: add a `.contextMenuPreview` rounded shape; no: close.
- `T-8186`, `T-9571`(c), `T-2020` Go-ahead for `CadenceUITests` runs that drive the screen?
- `T-7681` App Review screenshots: which 6.9-inch iPhone / 13-inch iPad device?
- `T-3226`, `T-1117`, `T-1163` Test-account restore; one calendar id across devices; Mac 24-hour time.
- `T-1424`, `T-7170`, `T-4900`, `T-16` ASC privacy answers; ad-hoc profile; `core.hooksPath`; logo art.

Parked past the RC with an owner ruling or an owner-only remainder (`head` each): `T-3297`(D),
`T-3118`, `T-3152`, `T-1920`, `T-2049`, `T-5523`, `T-1469`, `T-122`, `T-4501`. Decided 2026-10-31,
now agent work: `T-8162`-`T-8164`, `T-8553`, `T-8573`, `T-8644`, `T-8701`, `T-8702`, `T-8725`,
`T-8731`, `T-8732`, `T-8734`, `T-8736`-`T-8738`, `T-8765`, `T-8851`. Parked as accessibility-only: `T-7090`, `T-8646`, `T-8647`,
`T-8741`, `T-8924`. Closed: `T-1840`, `T-7751`, `T-7931`.

**On-screen checks that need an ATTENDED session.** Scheduled runs cannot drive the simulator,
and no run can show a macOS frame while the owner's Cadence runs (`T-3259`), so these landed from
source and wait for someone who can.

| Ticket | What it is |
|---|---|
| `T-7613` | iPad: swipe on a lifted block's edge band scrolls, hold-then-drag still resizes. |
| `T-8242`, `T-7872`, `T-7881`, `T-7951` | iOS: done-task look; background flush; commit ceiling; iCloud button wrap. |
| `T-7921`, `T-8204` | Half-typed `#tag` not minted (iOS and Mac); time the shortened completion animation. |
| `T-7163`, `T-7125`, `T-7195`, `T-7285`, `T-7315`, `T-7421` | Widget layout fixes, small and large tiles, not seen on a home screen. |
| `T-7151`, `T-6700`, `T-6711`, `T-1463` | iPad Templates two-column pane; root-shell top reserve; two iPad sightings. |
| `T-3325` | iPad Month deep link unseen: two SpringBoard alerts were blocking `Cadence-iPadPro11`. |
| `T-8211`, `T-8121`, `T-8081`, `T-8071` | Mac, blocked on `T-3259`: New Task panel; picker fixes; card menu; Kanban moves. |
| `T-8051`, `T-8031`, `T-8001`, `T-7991` | Mac, blocked on `T-3259`: note links; Focus chip; Today all-day band; Tasks pills. |
| `T-7911`, `T-7861`, `T-7831` | Mac, blocked on `T-3259`: sidebar list reorder; quit-time title and editor flush. |
| `T-3259` (+ `T-3160`, `T-3167`, `T-3253`) | No way to show a macOS frame while the owner's Cadence runs; those wait on it. |

**Agent-actionable.** "In flight" means a reservation names a live agent; check it before taking one.

| Ticket | What it is |
|---|---|
| `T-8186` | Re-measure the board list-picker clearance; needs a `CadenceUITests` run, so the owner's go-ahead. |
| `T-7170` | `xcb.sh export-archive` never run with `release-testing`/ad-hoc; needs an ad-hoc profile from the portal (owner's). |
| `T-4900`, `T-3260` | Stale `core.hooksPath` (owner-run config); 337 view-body pins. |

Rechecked 2026-10-30 by keeper `keeper0007` at `c8e2323c`: every other row this table carried
(`T-8142`, `T-8143`, `T-8160`, `T-8180`, `T-8184`, `T-8185`, `T-8187`, `T-8188`, `T-8200`,
`T-8203`, `T-7710`) is CLOSED, and `T-8182`/`T-8183` are PARTIALs whose remainder is an on-screen
check. `T-8851` (iOS all-day draft block jumps to the first hour) is an owner call under `T-8201`.
Almost all of the 190-odd active entries are owner calls or attended-simulator sightings.

The rest of the active list is SHIP-NOTE PARTIALs whose remainder is parked past the RC, or
long-lived owner questions; `ledger-view.sh head` says which.

**Closed since the last handoff** (a brief that still lists one is older than the tree): `T-7641`,
`T-2087`, `T-6821`, `T-6541`, `T-6410`, `T-3264`.

---

## 3. Known reds that are NOT yours

- None open at this writing: CI on `main` is green and no flake is ticketed as live.
- **A red in a tree-walking suite is evidence**, not the old nested-worktree symptom:
  `CadenceSourceScan.isForeignTree` (`CadenceTests/CadenceSourceScanSupport.swift`; T-3241, renamed
  and widened to scratch trees in T-3333) prunes any nested checkout. Do not "fix" one by editing
  `AGENTS.md`.
- Anything in `git status` before you started is somebody else's (see section 2).

---

## 4. The two things that bite hardest in a shared checkout

Both are stated in full in [docs/AGENT_BRIEF.md](AGENT_BRIEF.md); they are named here only because
most incidents are one of them.

- **A grant is sub-file scoped** (the Codex lease). Ask `./scripts/codex-land.sh held <path>`.
- **`agent-commit.sh` stages whole files.** If it refuses because a sibling staged a path, wait or
  use the `<path>=<content-file>` form. Never reset a sibling's work, and never `--commits-stale`.

Several sessions write this checkout at once, so re-read state rather than trusting a reading from
earlier in your own turn.
