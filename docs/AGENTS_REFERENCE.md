# Cadence Root Agent Reference

This is the former long root `AGENTS.md`, preserved so no operational detail is lost while the
active `../AGENTS.md` stays compact. Do not load this whole file by default; search it for the
specific runbook detail you need.

## Project Snapshot, and the runner refusals behind the build rules

The live `../AGENTS.md` carries the snapshot, the build and test commands, the scoped-guide
list, the directory map, the four non-negotiable patterns and the risk hotspots. This file
carried a copy of all six until 2026-10-20; the copy was the version displaced in 2026-08-31
and had drifted — stale file counts, a scoped-guide list one guide short, and a refactor
section that said of itself that nothing routed to it. The copies are deleted rather than
refreshed: a second spelling of an always-read guide is the thing that makes the guide stop
being authoritative. What follows is what the guide never carried.

An unscoped `test` run pulls in `CadenceUITests`, which cannot launch headless and aborts the
whole run. The failure reads like a broken suite rather than a harness problem — do not
conclude "tests can't run here" from it.

### The two runner refusals of T-2049, and why neither reads the way the ticket first wrote it

T-2049 named two sentences that both kill a run before any test body. One has stopped happening
altogether; the other is a prompt waiting for an answer, not a broken machine. Read them apart,
and do not carry either ticket summary forward without re-measuring — both aged badly inside
48 hours.

**`The test runner hung before establishing connection` — NO LONGER REPRODUCES.** It took every
agent's runs, unit and UI alike, from 2026-10-03 20:43 EDT. It then cleared on its own: re-measured
2026-10-04 10:30–11:25, a full `CadenceTests` run executed **5,538 tests in 468 suites**, and five
runs across four agents reached test bodies that morning. Re-checked 2026-10-06 while three sibling
runs were live at load average 52 — one of them had produced **3,482 result lines** with zero
occurrences of the sentence and zero automation timeouts.
**Both remedies the original entry predicted are ruled out by measurement:** `kern.boottime` still
reads Sep 16 (the Mac never rebooted) and `testmanagerd` is still **pid 88831 from Sep 30** (it was
never restarted) — it was alive straight through the incident and is alive now. So if you ever meet
this sentence again, **re-run first**; do not escalate it to the owner on the first hit. *Why* it
recovered is not established, and nobody should assert a cause for it.

**`Timed out while enabling automation mode` — it is a PROMPT, not a broken machine, and the
answer is the owner's.** Reproduced 2026-10-04 morning with the screen unlocked and
`DevToolsSecurity -status` reading *"Developer mode is currently enabled"*: `automationmode-writer`
asks for the device owner's Touch ID / password via LocalAuthentication policy 2, and unattended it
times out after ~70s having run 0 tests.

**But do not copy forward "UI tests cannot run here" from that — they ran the same evening.** Agent
`escape2` executed five `CadenceUITests` sessions between **19:12 and 20:02 on 2026-10-04** with
**zero** automation timeouts and zero hung-runner lines, and real bodies ran:
`CadenceInspectorHeaderPanelPlacementUITests.testEscapeClosesEachInspectorChildPanelAndLeavesTheInspectorOpen`
failed at 19:26 (29.4 s) and 19:36 (51.4 s), then **passed** at 19:39 (26.8 s) and 20:02 (26.6 s),
alongside `testEveryInspectorPanelOpensClearOfTheRowsItIsOpenedFrom` (34.4 s). So the grant *was*
obtained that evening and the suite is live.

**The grant is per-SESSION, which is what reconciles the two readings.**
`/var/db/com.apple.dt.automationmode/automation-enabled` is absent again as of 2026-10-06, while
the parent directory's mtime is **2026-10-04 20:02** — the exact minute `escape2`'s last UI run
ended. It is written while a session holds automation and does not survive it. So a cold UI run
raises the prompt again every time; it is not a one-time switch, and `DevToolsSecurity -enable`
does **not** stand in for it. **Writing the authorization database is a system security change and
the owner's** — it cost agent `escapefix` a whole ticket and cost `calcrash` two runs. Budget for
the prompt: if nobody is at the machine, a UI run will burn ~70 s and report 0 tests.

**The `log show` health probe self-matches — do not trust a bare one.** `/usr/bin/log` logs its own
invocation *including its `--predicate` argument*, so
`log show --predicate 'eventMessage CONTAINS "Finished enabling Automation Mode"'` matches the
command lines of previous probes. Measured 2026-10-06: a bare 24h count returned **3 "requests" and
3 "completions"**, and all six were `log[…] log run noninteractively … args: '/usr/bin/log' 'show'
…` lines from three earlier probe runs at 01:13, 02:23 and 12:05 — **zero real events**. The same
24h window with `AND process != "log"` appended returns **0 lines**. This matters beyond noise:
because a probe session runs both predicates, both counters rise together, so an
`outstanding = requests - completions` reading is dragged back towards 0 by the act of probing and
will read *healthy* over a genuinely unanswered request. **Always append `AND process != "log"`**
(or scope to `process == "automationmode-writer" OR process == "testmanagerd"`). **Corrected 2026-10-07 (T-2070, agent `envguard`): `scripts/xcb.sh` no longer prints that
predicate.** The scoped probe is `./scripts/xcb.sh check-automation` — one `log show` over
`(process == "testmanagerd" OR process == "automationmode-writer") AND process != "log"`,
answering both counters over one window in 2.3s, with any line carrying `--predicate` dropped
as a second defence. It exits 13 while a prompt stands, `xcb.sh`'s preflight refuses `test`
actions on that reading, and both the automation-mode and hung-runner refusals now name it
instead of a bare `log show`. Re-measured on the way in: 10 requests unscoped, 1 scoped.

**Writing a test that reads source files as text? Read "Source-Scanning Tests: The Two Ways They Go
Wrong" in `Cadence/Shared/AGENTS.md` first.** Those tests caught several real regressions in one day
and produced every defective assertion a verifier found in the same day; the substring trap,
comment-stripping, non-vacuity, and "mutate what you claim to pin" are all written up there, once.

**Warning baseline: 0 on macOS, 0 on iOS.** It was three until `651694b` (`MarkdownLinkSupport`
was itself a main-actor isolation warning and went with the `nonisolated` pass), then two —
`SchedulingService` and `SettingsNotificationsSection` — until T-96 cleared both. Neither was a
bug: the first was a `guard let task` whose body had been emptied when the three scheduling
assignments moved into `TaskCreationDraft`, the second an `await MainActor.run` wrapper that was
already on the main actor and discarded `NSWorkspace.open`'s `Bool`. The baseline is now zero, so
**any** warning is a regression introduced by the change in hand.

**The baseline covers all three targets, and that takes two builds, not three.** It used to be
measured only on `Cadence`, and `CadenceMCPServer` sat at two warnings underneath it unnoticed,
because the run that checked that scheme read its *exit status* and never grepped its output. Exit 0
says nothing about warnings. Grep the log, and grep it with **no path filter**: a main-actor
isolation regression this session surfaced under synthesized macro paths and slipped past a
`grep "/Cadence/"` entirely.

**A `CadenceWidgets`-scheme run is not a widget-only measurement, and it is not an extra one
either.** The app target *depends on* the extension (`PBXTargetDependency` + an Embed App Extensions
phase), so `-scheme Cadence` builds `CadenceWidgets` first and embeds the `.appex`; the widgets
scheme in turn lists both `Cadence.app` and the appex in its build action. Measured cold, in
separate private DerivedData paths, the two schemes ran the **identical** task histogram — 615 tasks
in target `Cadence` (534 `SwiftCompile`) and 115 in `CadenceWidgets` (56 `SwiftCompile`), 0 warnings,
0 errors either way. So a green `Cadence` scheme already proves the widget target, and a widgets-scheme
run costs a second full app build to prove nothing new. `CadenceMCPServer` is the genuinely separate
one: it builds its own target plus 20 SPM dependency targets and **neither** app target.

## Red Runs That Are Not Regressions

Six causes make `xcodebuild` fail on sources that are fine, and **every one is misattributed by
default** — no line of output ever says "another agent is running". Read the tell before you debug a
line of Swift; the whole discriminator is two greps and, once, `xcresulttool`.

| Tell | Cause | Confirm, then |
|---|---|---|
| Log stuck at `Command line invocation`, `xcodebuild` pinned at 0.0% CPU | project-file lock (T-117) | `sample <pid> 5` shows `_blockOnAccessClaim`. Wait; quit Xcode. |
| Hundreds of `error:` lines, all `external macro implementation type … could not be found` / `swift-plugin-server could not be loaded: Resource temporarily unavailable` — also `build.db is locked`, `unable to spawn swift-frontend` | concurrent `xcodebuild` invocations. A private `-derivedDataPath` does **not** prevent this, and neither does `test-host-lock.sh`: the lock serialises the *test host*, and this is a compile-phase failure that plain `build` runs hit too (T-209) | `grep "error:" log \| grep -Evc "macro\|plugin"` → `0`, i.e. not one error names your code. Re-run. |
| Four-figure failure count, 0 compile errors, most failures at `0.000 seconds` | a second macOS test host on the one app-group container (T-236) | `grep -oE "My Mac - Cadence \([0-9]+\)" log \| sort -u` → more than one PID; a healthy run prints exactly one. Take `scripts/test-host-lock.sh`, re-run. |
| A handful of `0.000 seconds` failures scattered over suites your change cannot reach, 0 compile errors, one host PID | the test runner exited early; the harness failed whatever was in flight (T-238) | `xcrun xcresulttool get test-results summary --path <derivedDataPath>/Logs/Test/Test-Cadence-*.xcresult`, then read `result`, `statistics`, `topInsights`, `testFailures`. The reason — "The test runner exited with code 0 before finishing running tests" — exists **only** in the `.xcresult`; the xcodebuild log cannot show it. Re-run, `-parallel-testing-enabled NO` to confirm. |
| `builtin-productPackagingUtility` dies with `Entitlements file "Cadence.entitlements" was modified during the build`, **0 Swift files compiled**, and what reaches you is T-552's *"executed 0 tests"* | a metadata-only touch of `Cadence/Cadence.entitlements` (ctime moves, mtime does not, `git status` stays clean) has poisoned that private DerivedData **permanently** (T-2046) | `xcb.sh` names it `ENTITLEMENTS-POISONED-DD` and writes `.cadence-entitlements-poisoned` into the tree. **THE RULE: a DerivedData is disposable the moment this fires** — it compiled nothing and ran nothing, deleting the generated `.xcent` does not clear it, and the next run into a marked tree is refused (exit 14). `./scripts/xcb.sh release-dd <dd>`, then a fresh build. Never `CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION`. |
| Exit 65 with **zero** result lines after ~445 s (or ~70 s for a UI run), the log naming `Timed out while enabling automation mode` or `The test runner hung before establishing connection` | an **unanswered "Enable UI Automation" prompt** on this Mac. It is not UI-only: it wedges UNIT runs behind it, and one of them once cost 3h11m and seven dead runs (T-2070, T-2067, T-2049) | `./scripts/xcb.sh check-automation` — exit 13 means one is standing, and **only the owner, at the keyboard, can answer it**. The preflight refuses `test` actions on that reading. Never `DevToolsSecurity -enable`, a daemon kill, or an authorization-database write. |

**The CAN half, which has now been discovered twice** (T-986, then T-1153). The App-Sandboxed
`CadenceTests` host **can** spawn `/bin/zsh <script>`, at any depth, against a script already on
disk — that single fact is what makes every guard-script selftest wireable into a test run at all,
and both times it was found the finding read as a surprise. It can also exec a repository script
directly and run Xcode's own `xcodebuild`. What it cannot do is exec a **setuid** binary (`/bin/ps`,
`/usr/bin/top` — EPERM at `posix_spawn`), exec a file **it wrote itself** (even a byte-identical
copy of `/bin/ls`), write outside its own container, or read the process list at all: `/usr/bin/pgrep`
spawns and runs and then exits 3 saying *"Cannot get process list"*, which is worse than a refusal
because a caller piping it into `wc -l` reads a plausible `0`. The `/usr/bin` **xcrun shims**
(`git`, `python3`, `xcodebuild`) spawn and then refuse with *"cannot be used within an App Sandbox"*
— a different failure with a different fix. Every sentence in this paragraph is measured by
`CadenceTestHostSandboxCapabilityTests`; none of it may be restated anywhere without naming it
(T-1153, enforced by `CadenceTestHostEnvironmentPinTests`).

Two things the table does not cover: failures inside `CadenceUITests` mean the run was not scoped
(above), and a mutation that failed to compile also exits 65 — but that one names your file. The
evidence for each row is in `docs/TODO.md` under its id; the detail on T-236 and T-117 is in the
bullets below. Do not re-derive either here.

## The Rationale Behind The Non-Negotiable Patterns

`../AGENTS.md` states the patterns. These are the measurements and incidents behind the ones
whose argument did not fit there. The subagent-facing half of this material — isolating a tree,
the test-host lock, mutation runs, committing out of a shared checkout — is in
`docs/SUBAGENT_RUNBOOK_REFERENCE.md` and is not repeated here.

The four UI patterns themselves — no hardcoded colours, page headers that do not describe the
page, one hover layer at one radius, one shared component over near-copies — are stated in
`../AGENTS.md` and argued in `docs/SHARED_AGENTS_REFERENCE.md` ("Theme Is The Only Source Of
Colour", "One Page Header Per Platform", "The Primary Task Row: What Is Shared, And What Is
Earned"), which is the file closest to the components they govern. They were restated here in
full until 2026-10-20, and the copy had already drifted on the page-header wrapper list.

- **Build into a private `-derivedDataPath` whenever another build may be running.** The shared
  DerivedData is a single mutable directory: a clean build deletes `Build/Products/`, and anything
  launched from there dies in `libsecinit` before `main()` with an `EXC_BREAKPOINT` that looks like
  an app crash and is not. It also produces `build.db is locked` failures that look like flaky tests.
  Every failure mode it causes is **misattributed by default** — it never says "another build is
  running", it says whatever the half-deleted directory happened to look like when you read it. On
  2026-08-18 it reported unresolvable swift-nio modules (`DequeModule`, `Atomics`) from a corrupt
  `SourcePackages`, which read as a broken checkout and briefly made a correct agent report look
  wrong. Rule: a build failure you cannot explain is a private-`derivedDataPath` re-run before it is
  a finding. Note `-derivedDataPath` requires `-scheme`; it is rejected with `-target` alone.
  **It isolates the build, not the test host's container.** A macOS `xcodebuild test` run launches
  `Cadence.app`, which uses the one app-group container at `~/Library/Containers/com.haoranwei.Cadence/Data/`
  no matter where DerivedData points — so two simultaneous macOS test runs corrupt each other. Check
  for another run first and wait it out; the tell is in the table above, the measurement in
  `docs/TODO.md` T-236.
  **Match the pattern carefully.** `pgrep -f "xcodebuild test"` matches *any* process whose command
  line contains that string — including the shell running your own wait loop, so
  `until ! pgrep -f "xcodebuild test"; do sleep 10; done` never exits, and a plain
  `grep xcodebuild` over `ps aux` reports your own grep as a hit. Match the binary path —
  `pgrep -f '^/Applications/.*/xcodebuild( .*)? test(-without-building)?( |$)'` — **anchored**, and with
  the action read as a whole token — or capture the PID when you launch
  and wait on that. **The token half is T-1162 and it is not cosmetic either**: `xcb.sh` appends the
  action LAST, so the anchored-but-adjacent form `'^/Applications/.*/xcodebuild test'` matched no test
  run this repository makes (measured 2026-09-12: `status` printed `live test hosts: 0` against a live
  one, while the calibrated pattern printed `1` in the same second). And the token is what keeps
  `-only-testing:CadenceTests` and `build-for-testing` out, both of which carry the letters. The anchor is not cosmetic: `pgrep -f` matches the *whole command line*, so the
  unanchored form counts every agent shell whose own text contains the literal, which includes the
  wait loops written to avoid contention. That inverts the belt into a deadlock — each waiting agent
  sees the others waiting and counts them as running hosts. Measured: one agent held the lock 23
  minutes with **zero** real hosts on the machine, and a `pgrep -f` returning 2 where only one process
  was xcodebuild. To count actual test hosts rather than build processes, `pgrep -x Cadence`.
  **Mechanised 2026-08-30 (T-86).** The prose rule left three of this repository's own runbook
  commands sitting on the default path: `README.md`'s build and test, `docs/apple-release-readiness.md`'s
  two verification commands, and `docs/direct-distribution-runbook.md`'s `archive` — five invocations
  that anyone following the docs would copy. They are fixed, and
  `CadenceTests/CadenceBuildInvocationHygieneTests` now fails on any `xcodebuild` in a markdown code
  fence or a shell script that names a build action without `-derivedDataPath`, or that points one at
  the shared root. Two measurements sit behind it. A read-only `xcodebuild -showBuildSettings` with
  no flag **also** creates the shared entry and resolves packages into it, so "it was only a query"
  is not a defence. And the entry is keyed to the **project path**, so a scratch tree gets its own
  while an unflagged run from the repository root shares the one Xcode uses — that sharing is the
  T-86 mechanism, one `build` away. `./scripts/xcb.sh audit` lists them: 14 entries, ~1.8 GB, all
  but one orphaned by scratch trees that no longer exist. Prefer `scripts/xcb.sh <id> build|test`,
  which supplies the private path, refuses a shared one, and takes the test-host lock for `test`.
- **A bare `xcodebuild` pinned at 0% CPU is a project-file lock, not a broken build.** `docs/TODO.md`
  T-117, confirmed twice by `sample`: `NSFileCoordinator` serializes reads of
  `Cadence.xcodeproj`/`project.pbxproj`, and a run can block in `_blockOnAccessClaim` behind another
  claimant — a concurrent `xcodebuild`, or the user's Xcode if it has the project open. It produces
  **no diagnostic**: the run just sits at the "Command line invocation" line forever, which reads
  exactly like a broken checkout. The tell: `ps -eo pid,etime,%cpu,command | grep xcodebuild` for a
  real `xcodebuild` binary (not a wrapper shell — same anchoring caveat as above) idle at 0.0% CPU
  for several minutes *and* its log not advancing past that first line; a genuinely slow build's CPU
  is bursty, never pinned at zero, and its log keeps moving. If both hold, `sample <pid> 5` should
  show `NSFileCoordinator`/`_blockOnAccessClaim` on the stack. Rule: quit Xcode before a batch of
  agent builds where you can, and treat total silence at "Command line invocation" as this rather
  than as a checkout worth debugging.
  **Re-checked 2026-08-24 under 14 concurrently-building agents: not reproduced.** Every apparently
  stalled process was a `test-host-lock.sh acquire` wait, not a bare hang, and the user's Xcode
  was not even running — one of the two confirmed claimants was simply absent. Two processes
  stranded the same night (an `xcodebuild test` at 3h14m against a ~15-minute suite, and a runner
  script at 4h30m) were killed before anyone captured a `sample`, so neither is attributable to this
  by evidence — do not count either as a third confirmation. The runner script in particular matches
  `58e20a4`'s "launch a background job and return" failure (four other agents confirmed the same
  night) far better than a project-file deadlock: a wrapper script outliving its launching agent,
  with nothing left to read its `DONE` file, is that failure's shape.
  **You cannot detect the claimant in advance, and `lsof` is the wrong instrument.** A coordinated
  access claim is not an open file descriptor: `lsof Cadence.xcodeproj/project.pbxproj` returns
  nothing while a real `xcodebuild` is mid-run against it (measured 2026-08-30), so a preflight
  written that way reports "clear" every time and is worse than none. The only observable is the
  stalled process's own stack. `scripts/xcb.sh` therefore watches its child's log size and CPU and
  runs `sample` itself when both stand still for `CADENCE_STALL_SECONDS` (default 180), printing
  either "T-117 CONFIRMED: blocked in NSFileCoordinator" or the top frames of whatever else it is
  stuck in. The deadlock cannot be prevented from outside the process; it can only be named, and
  naming it is the difference between a two-minute wait and twenty minutes of debugging Swift.
- **The simulator and macOS-app rules are in `docs/AGENT_BRIEF.md`, under Safety. What is here is
  the two leaks that produced them**, both of which the user had to clear by hand, and the
  measurements are the part a rule cannot carry.
  *Simulators:* agents kept running `simctl create` and naming devices after themselves
  (`Cadence-T195-Agent`, `…-iPad`, …). A created device **persists in the pool with all its data**
  after `simctl shutdown`, so shutting it down is not cleanup — the Devices directory went 3.8 GB →
  7.7 GB in one batch, and enough booted devices push the load average past 40 and kill other agents
  on a 600 s watchdog. Share one existing **stock** device, boot it only if
  `xcrun simctl list devices booted` is empty, and never `erase`, `shutdown` or `delete` it: another
  agent is probably mid-run on it.
  **Claim that shared device before you install to it** — `./scripts/simulator-claim.sh` is the
  simulator's `test-host-lock.sh`. A bundle id is unique per device, and Cadence's store lives in the
  **app-group** container, which on a simulator is one *device-wide* directory
  (`.../Devices/<udid>/data/Containers/Shared/AppGroup/<uuid>/Library/Application Support/Cadence/`)
  that survives reinstall — so two agents on one device are one `install` replacing the other's build
  and two writers on one SQLite file. That is T-225. `claim <id>` is an atomic per-device `mkdir` on a
  45-minute lease and blocks rather than creating a device; `install` / `launch` refuse without one;
  `launch` redirects the store to a per-agent id via `SIMCTL_CHILD_CADENCE_UI_TEST_STORE_ID`, exactly
  as `run-macos-app.sh` does on the Mac, so the shared app-group store is never opened at all.
  Device-touching commands report unless given `--apply`, and there is no `create`, `erase`,
  `shutdown`, `delete` or `privacy` subcommand by construction. Pair `claim <id>` with a trapped
  `release <id>` in the same turn — `release` frees only a claim recording your own id and leaves the
  device booted and untouched.
  **On a shared device, an app vanishing to the Home screen is an *external* termination until the
  log says otherwise.** `xcrun simctl privacy <udid> grant|revoke|reset <service> <bundle-id>` kills
  a *running* app by design — tccd logs
  `Terminating com.haoranwei.Cadence[<pid>] because access to the kTCCServiceReminders service
  changed` and launchd_sim logs `exited with exit reason (namespace: 11 code: 0x0) - OS_REASON_TCC`.
  It writes **nothing** to `~/Library/Logs/DiagnosticReports`, raises no exception, and truncates
  the app's own log mid-sentence, so it reads exactly like a `SIGKILL`-shaped SwiftUI crash. Another
  agent running it lands on *your* session with no warning. That misread cost T-267 a top-priority
  crash ticket against a date picker that was never at fault. One command settles it before you
  start bisecting a view:
  `xcrun simctl spawn <udid> log show --last 5m --style compact --predicate 'process == "tccd" OR process == "launchd_sim"' | grep -E "Terminating|OS_REASON"`.
  The `sender_pid` on the preceding `TCCAccessSetInternal` is CoreSimulatorBridge when a host
  `simctl` call caused it. `frontboard(10) code:force-quit` and `runningboard(15)` (an
  `installcoordinationd` reinstall) are the other two external kills that look like crashes here.
  **`control action=detach` ignores its own `udid` argument and closes every agent's simulator
  panel, not just the caller's** (docs/TODO.md T-179) — a bug in the simulator tooling itself, not
  in this repo, so there is no code fix available here. On a device several agents share, treat
  `detach` as global: either skip it and let the panel be closed by something else, or only call it
  when you have reason to believe no other agent is attached. There is nothing to reclaim afterward
  — no device or app state changes, and every closed panel can just re-`attach`.
  *The macOS app:* launching it is legitimate — macOS is the primary surface and some things can only
  be confirmed by looking. Launching the **shipping configuration** is not: it opens the user's real
  CloudKit-backed app-group store as a *second writer* while their own copy may be running, and such
  instances have hung and needed a force-quit, one of them for 15 hours. Use
  `./scripts/run-macos-app.sh start <path/to/Cadence.app> <id>`, which sets
  `CADENCE_LOCAL_STORE_ONLY=1` (no CloudKit, and `CadenceAppDelegate` skips
  `registerForRemoteNotifications()`) and `CADENCE_UI_TEST_STORE_ID=<id>` (store redirected to
  `$TMPDIR/CadenceUITestStores/<id>/`), refuses to start if the user's own Cadence is running, and
  records the PID. **Pair every `start` with a `stop <id>` in the same turn** — `stop` is idempotent,
  escalates to `kill -9` if the app hangs, and removes the private store.
  `./scripts/agent-cleanup.sh` reports these leaks and `--apply` reclaims them; a `SubagentStop` hook
  runs it automatically. It deliberately spares scratch directories touched in the last 30 minutes
  and **never** touches a `Build/Products/Debug/Cadence.app` process while any `xcodebuild` is alive,
  because that path also matches xcodebuild's own **test host** and killing it mid-suite reads as a
  flaky test. Treat the hook as a safety net, not a licence to skip your own cleanup.
- **One directory per agent, and clean only inside it.** The scratchpad root is shared. Make
  **one** directory of your own under it — the session scratchpad path plus your PID, e.g.
  `.../scratchpad/agent-$$/` — put both your isolated source tree and your `-derivedDataPath`
  *inside* it, and let your `rm -rf` name that directory and nothing else. This said "use a
  PID-unique `-derivedDataPath`", and two agents read it as a unique *filename* under the shared
  root, then deleted each other's DerivedData mid-run with `rm -rf` on sibling paths — a
  unique name is not isolation if the cleanup step can still reach a sibling. Cleanup is also not
  optional: the scratchpad reached **64 GB** in one session and filled the user's disk. Delete your
  directory when you are done, and only yours.
- **Isolating a tree is `./scripts/agent-scratch.sh new <id>`, and this bullet used to say the
  opposite.** It carried a `rsync -a --exclude .git` recipe on T-237's claim that
  `git archive HEAD` ran at ~5 KB/s here. T-237 was re-measured on 2026-08-30 at **0.06s** and
  closed as not reproducible, and the `rsync` route is now the one with the measured failure:
  it copies 8963 files / 464 MB including **any other agent's in-flight edits**, so the tree you
  verify is not HEAD. The archive is 910 files / 14 MB and *is* HEAD. The recipe, the naming
  rule and the `release` refusal that stops you deleting the only copy of unlanded work are in
  `docs/SUBAGENT_RUNBOOK_REFERENCE.md`, "The opening rules, and the incidents behind them".
- **Poll for your own background results; never wait for a notification.** Completion notifications
  are delivered to the **main session**, not to subagents — so a subagent that "waits for the
  notification" simply ends its turn, and the task stops there with its work half done. Two agents
  stalled this way in one night, each having already written its code. Launch long work in the
  background and poll a marker file with a bounded loop:

  ```
  i=0; until [[ -f "$D/all.done" ]] || (( i >= 180 )); do sleep 10; (( i++ )); done
  cat "$D"/*.exit
  ```

  **Launch and wait in the SAME call.** The failure is not forgetting to poll — it is launching the
  background job in one call and *returning*, expecting to be told when it finishes. Four agents
  stalled that way in one night, each with its code already written. The launch and the wait belong
  in one invocation:

  ```
  "$D/run.sh" "$D" > "$D/runner.log" 2>&1 &
  i=0; until [[ -f "$D/DONE" ]] || (( i >= 180 )); do sleep 10; (( i++ )); done
  cat "$D"/*.exit
  ```

  Have the runner `touch "$D/DONE"` as its last line — a marker is what makes a single bounded wait
  possible. The same applies to `test-host-lock.sh acquire`, which **blocks**: put the acquire, the
  build and the release in one invocation and the queue wait costs you nothing extra.

  **The loop must be inside ONE tool call.** Polling with one call per check is the single most
  expensive mistake available here: an agent doing that made **1113 tool calls** in 68 minutes and
  still ended stalled, having produced nothing the ticket asked for. The loop above is one call that
  waits up to 30 minutes. The same applies to the lock — acquire, build and release in one
  invocation with a `trap`, not by re-checking from separate calls.

  Related: run a long build in the background against a log you poll rather than in the foreground —
  a 10-minute tool timeout will not survive a cold build of this project, and an agent was killed by
  exactly that. And acquire the test-host lock and run the build **in the same shell invocation**,
  because each command runs in a separate process (which is why the lock is a lease, not a liveness
  check).
- **Check the log says which tree it built.** An isolated tree can be deleted out from under a
  running build (see above); the failed `cd` then falls through to the live repo and the run reports
  **exit 0 against the wrong sources**. This happened on 2026-08-18 and was caught only by grepping
  the log for the path xcodebuild echoes. Confirm your isolated path appears in the log before
  trusting the result. `build.db is locked` and `unable to spawn swift-frontend` on a fresh private
  path are a *different* failure — concurrent invocations rather than the wrong tree, row two of
  "Red Runs That Are Not Regressions" above, and they clear on re-run.
- **Drag-and-drop CAN be driven on the iOS simulator.** This was recorded as impossible for a long
  time and the record was wrong; every "drag is verified by inference" caveat in this repo's history
  predates the recipe below. `UIDragInteraction`'s lift recognizer needs the touch **stationary for
  ~350ms before any movement** — measured, `itemsForBeginning` fires 326–349ms after `touchesBegan`.
  A `swipe`, or a `touch_path` that starts moving immediately, never lifts. 300ms also fails: the
  first move lands just before the threshold and breaks the recognizer's slop. Use:

  ```
  touch_path points:
    {x: srcX, y: srcY, dt_ms: 0}       // down
    {x: srcX, y: srcY, dt_ms: 600}     // stationary dwell — this is the lift
    ...steps of 10–30pt, dt_ms: 50...  // travel
    {x: dstX, y: dstY, dt_ms: 400}     // settle on the target
  ```

  `dt_ms` on point *N* is the dwell **before** moving to *N*. Coordinates are **points** (the
  `launch` reply states the device's, e.g. 420×912), **not screenshot pixels** — mixing them up is
  what produced the "tab bar swallows taps" folklore: a touch beginning within 4pt of an edge is
  synthesised as the OS home/app-switcher gesture, and an *incomplete* one leaves the app's window
  ~35pt short, so every bottom-anchored control moves up and taps aimed from an old screenshot miss.
  Nothing is swallowed. Only a relaunch clears it, so keep every point ≥8pt from all four edges.
  Proven end-to-end against real Cadence: a Calendar Board card dragged between day columns, with
  the resulting SwiftData change surviving a relaunch.
- **macOS UI *can* be screenshot- and event-verified from the agent shell.** Also long recorded as
  blocked on an ungranted accessibility permission, also wrong: `AXIsProcessTrusted`,
  `CGPreflightPostEventAccess`, `CGPreflightListenEventAccess` and `CGPreflightScreenCaptureAccess`
  all return true, System Events reads window geometry, and `screencapture -x` works. The symptom
  behind the old note is real but misdiagnosed — `count of windows` on an app with no open window
  returns 0 and indexing it errors `-1719 Invalid index`, which reads like a permission denial.
  **One genuine constraint remains:** posting `CGEvent`s drives the user's *physical* cursor, so a
  scripted macOS drag fights them for the pointer and can drop something somewhere unintended. Safe
  only when the machine is known idle; screenshots and reads are safe any time.
- **Verify and commit with nothing live in the tree.** `docs/AGENT_BRIEF.md` has the commit rules
  and `docs/SUBAGENT_RUNBOOK_REFERENCE.md` has what `agent-commit.sh` does about each measured
  failure. This bullet is the half neither carries: what you commit must be the bytes you *tested*,
  and the two ways of losing that are independent of the index:
  - *The file list.* `git add <paths>` adds your paths **to whatever is already staged**, so another
    agent's `git mv` or `git rm` sitting in the index rides along. `c9d2d78` swept in a staged
    deletion of two view files whose callers were not yet committed, so **HEAD did not build for
    iOS** until the next commit — and no check caught it, because isolating with `git archive HEAD`
    reproduces HEAD's *tree*, not its index, so the deleted files were present everywhere you
    looked. `git commit --only <paths>` takes the paths and ignores the index, and fixes this half.
  - *The file contents.* `--only` does **not** fix the other half, and this guide claimed it did.
    `5aa11dc` used `--only` and still left HEAD unbuildable for three commits: the subset was
    verified and passed, a live agent then edited two of those files, and `--only` faithfully
    committed bytes that had never been compiled. A passing verification is a statement about a
    moment, not about a path list.

  So: get the tree quiet before you verify — other agents' in-flight files reverted, their new files
  out of the way — and commit immediately after, with `--only` naming your paths. If you cannot
  quiet the tree, checksum the exact files you tested (`shasum` them into your scratchpad) and
  confirm the digests are unchanged at commit time; re-verify if any moved. Also read
  `git status --porcelain` for staged entries you did not stage. Two failure modes here were mine
  rather than the tooling's, and both are cheap to repeat: classifying files by a filename pattern
  (`*Tag*`) that neither affected file matched, and treating a subset test as durable while agents
  were still writing.
- Keep SwiftUI view roots thin. Prefer dedicated subview structs and support files over long computed `some View` fragments.
- Preserve shared hover behavior. Do not turn task/event/bundle hover states gray; preserve original color and use brightness/lift style treatments from shared hover helpers.
- Avoid broad refactors in markdown editor files unless you are intentionally working on editor behavior.
- **Review the MCP boundary when model or shared-service code changes.** The rule is in
  `../AGENTS.md`; the account is `CadenceMCPServer/AGENTS.md` and `docs/MCP_AGENTS_REFERENCE.md`,
  "Why the prohibition was wrong". It is not restated here, which is what that section asks.

## Why `parallelizable = "NO"` stays (moved out of AGENTS.md, 2026-08-31)

The original 2026-08-28 reason — "it spawns 2 test hosts" — is **stale**. Re-measured twice on
2026-08-31 against Xcode 26.6: it spawns **one** host and parallelises in-process.

The ban stays for two other reasons that are still true:

- Parallel still fails one test **deterministically** — a store assertion across a 60ms suspension in
  a `@MainActor` suite.
- It buys only **1.27x** wall clock for roughly **9x** the CPU.

It also changes the log format from `✘ Test name()` to `Test case 'Suite/name()' failed`, so any
failure grep written for the serial format silently matches nothing — a green-looking run that
counted zero results. Do not re-enable it per-invocation.

## Why the strict compile-error pattern (moved out of AGENTS.md, 2026-08-31)

Use `grep -cE '\.swift:[0-9]+:[0-9]+: error:'`, never `grep -c 'error:'`.

A failing test whose message merely contains the word "error" — e.g. `Caught error: .notFound(...)`
from a source scan — matches the loose pattern. A genuine mutation kill then reads as a build break
and gets thrown away.

The direction of the bias matters: the loose pattern only ever **over**-counts, so it never launders
a bad result into a good one. It discards good evidence instead, which is quieter and easier to miss
than a false green.

Companion rule, same section: a crashed `swift-frontend` emits **no** `error:` lines at all, so a
strict count of 0 does not mean success. Also grep for `please submit a bug report`.

## Why the test host is pinned to UTC (moved out of AGENTS.md, 2026-09-08)

[[T-1116]]. A full `CadenceTests` run went red on 2026-09-08 with no code change: the Mac's zone had
become `America/Los_Angeles`, and the failing test had been authored at `+0800`. The finding worth
keeping is not that test — it is that *a green run had been carrying an unstated dependency on where
the machine was sitting*, and nothing in the repository said so.

**The mechanism.** `Cadence.xcscheme`'s `<TestAction>` had no `<EnvironmentVariables>` of its own and
carried `shouldUseLaunchSchemeArgsEnv = "YES"`, so it inherited the Launch action's environment,
which pinned nothing but `OS_ACTIVITY_MODE`. It now has its own block with `TZ=UTC` and stops
inheriting. **Not** the LaunchAction, which was the shorter edit: that would also pin the app a human
runs from Xcode to UTC, so every date on screen in a debugging session would be hours off the wall
clock — a change to the product surface made in service of the test suite. Not inheriting costs the
Launch action's `OS_ACTIVITY_MODE=disable` and its three CoreData logging arguments, so those are
re-spelled in the `TestAction`; `CadenceTimeZoneIndependenceTests` asserts all of it.

**Measured, and both halves matter.** `TZ` in a process's environment *does* reach Foundation —
`TZ=UTC` yields a `TimeZone.current` whose identifier is spelled **`GMT`**, which is why every
assertion about the pin reads the *offset* rather than the identifier. But a **shell-level** `TZ=`
does not reach the spawned macOS test host: two full runs under `TZ=Asia/Shanghai` and
`TZ=America/Los_Angeles` produced byte-identical failures. So the scheme is the only place the host
can be pinned from, and a test inside the host is the only place that can confirm it landed. Do not
try to vary a zone by exporting one; pass a `Calendar`.

**Pinning alone would have hidden the bug it came from.** A suite read only in UTC can never catch
"this breaks west of UTC". So the zone-sensitive shared date surfaces are exercised in three stated
zones — UTC, `Asia/Tokyo` (positive, no DST) and `America/Los_Angeles` (negative, with DST, where two
days a year are 23 and 25 hours long) — through `CadenceTestTimeZones`.

**And the rule that keeps it from coming back.** `CadenceTimeZoneIndependenceTests` fails any `@Test`
whose body both reads the ambient zone and derives a calendar day from it. The conjunction is the
rule, not a ban on `Calendar.current`: measured over 315 files on 2026-09-08, the ambient needles
alone appear in 50 tests across 14 files — most adding an hour to a timed event, where the answer is
the same everywhere — while ambient *and* a day-boundary derivation is 22 across 11. Bare `Date()` is
a weaker, separate finding (a clock race, which the pin does not fix) and is ledgered per file rather
than banned. `WeekKeyResolutionTests` is exempt by file: its subject *is* the parameterless helpers'
device-zone default, so it cannot state a zone instead.

**What the pin does not reach, which is the rest of the same dependency (2026-09-25).** The two pins
arrive by two channels, and neither channel is general. `TZ` is an environment variable;
`-AppleLocale en_US` is an argument-domain overlay on **one key**. System Settings' Language & Region
pane writes its switches into the **global** domain, where an argument-domain pin cannot reach them:
`AppleFirstWeekday` moves `Calendar.current.firstWeekday` to 2 on a Mac set to Monday,
`AppleICUForce24HourTime` moves the hour cycle under the locale that is pinned,
`AppleICUDateFormatStrings` re-templates `DateFormatter`'s styles, `AppleICUNumberSymbols` the
separators. So **a green run additionally requires that the Mac has no Language & Region override
set** — and the test best placed to notice, `theTestHostRunsInTheClockTheSchemePins`, used to report
such a failure as a dropped scheme argument, which is a diagnosis that cannot be true of a switch the
scheme has no way to set. `CadenceTestHostEnvironmentPinTests` now refuses by name instead, and there
is no fix beyond the refusal: the answer for a test that turns on one of these is to state its own
calendar or locale, exactly as `CadenceTestTimeZones` and `CadenceTestClocks` do.

### The loose `warning:` reading, measured (T-1147, 2026-09-12)

`xcb.sh` counted warnings with `grep -c 'warning:'` — the loose pattern its own neighbouring line
banned for errors. Measured over three real logs: a plain `build` (669 `SwiftCompile` tasks) emits
**no** `warning:` line at all; `build-for-testing` over the same tree (345 more tasks) matches
exactly **one**, `appintentsmetadataprocessor … warning: Metadata extraction skipped. No
AppIntents.framework dependency found.` The phantom is tied to the **test bundle**, not to how full
the build is.

The effect was an inverted baseline: every honest cold run reported `warnings: 1` against a stated
baseline of zero, while a vacuous incremental run that recompiled nothing reported a reassuring `0`.
The counter is now anchored (`\.swift:N:M: warning:`), tool notices are reported on their own line
so a future real `ld:` or `actool: warning:` is not lost, and a run that compiled zero Swift files
prints `!! VACUOUS-COUNT` rather than certifying a zero it cannot support.

### The cost of that anchor, and the second pattern (T-1516, 2026-09-29)

Anchoring on `.swift:` is right and was not widened. Its cost is a whole category: a warning raised
inside a **macro expansion** is attributed to the expansion buffer rather than to a file, so its
primary line carries no `.swift:N:C:` prefix at all and could not match. It was swept into the loose
count and printed under a `tool notices:` banner whose own words — *"not a compiler diagnostic"* —
were false about it. `#expect` is in ~5,200 tests here, so the blind spot was the whole suite, and
it failed in the direction that reports success: fourteen real warnings, `warnings: 0`.

Reproduced and captured 2026-09-29. Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app
target plus the `InferIsolatedConformances` upcoming feature, a synthesised `Equatable` conformance
is main-actor isolated while the `#expect` expansion using it is not, so `#expect(a == b)` over an
app-target enum raises `#IsolatedConformances` **inside the expansion**. One `build-for-testing`
log: 3 such diagnostics, `\.swift:N:C: warning:` = **0**, `xcb.sh` exit **0**, `check-log.sh` exit
**0**. With the second pattern: `warnings: 3`, exit **9** and exit **1**.

**Two spellings exist, and only one was in the ticket.** A freestanding macro names itself `#expect`;
an attached one names itself `@ObservationTracked` (from `@Observable`). The ticket proposed
`macro expansion [A-Za-z#]+:`, which sees the first and misses every `@Model` / `@Observable` /
`@Test` diagnostic in the project. The shipped pattern is
`macro expansion [^ :]+:[0-9]+:[0-9]+: warning:` — name-agnostic, still anchored on the literal
`macro expansion ` prefix, and spelled in the POSIX-ERE/ICU intersection because
`CadenceBuildInvocationHygieneTests` lifts it out of the script and runs it with
`NSRegularExpression`. Continuation lines of the same diagnostic (`` `- warning: ``) carry no
`name:LINE:COL:` and are deliberately not matched, so the count stays one per diagnostic.

The same second pattern is in `.github/scripts/check-log.sh` and `scripts/mutate.sh` (where it only
reports — `mutate.sh` sets `CADENCE_ALLOW_WARNINGS=1` on purpose). `xcb.sh` prints
`MACRO-EXPANSION-WARNING` when the second count is non-zero, because a reader who sees `warnings: 3`
and greps the log for `\.swift.*warning:` finds nothing.

## Why the pre-commit hook ships inert (moved out of AGENTS.md, 2026-09-19)

`.githooks/pre-commit` refuses a bare `git commit`, which is the point of it: this repository's
index is shared between agents, so `scripts/agent-commit.sh` is the only safe way in (T-679). But
`core.hooksPath` is *repository configuration*, not an agent's to set — arming the hook would also
refuse the repository owner's own commits, and that is their call to make, not an agent's (T-780).

So it ships inert, and arming it would not even change an agent's path: `agent-commit.sh` commits by
plumbing (`git hash-object` / `write-tree` / `commit-tree`), and git runs no hooks for plumbing
commands. The hook is a guard for a human typing `git commit`, not a mechanism any agent relies on.

The rule that stays in the root guide is therefore just the prohibition: never run
`git config core.hooksPath`, and never teach a script to.

## The `try? save()` rule (moved out of AGENTS.md, 2026-09-25)

Moved out by T-1344, which found root `AGENTS.md` at exactly the 199-line cap with no room
for another route. This was the largest single block of rationale in that file — 26 lines of a
199-line index — and it is a rule for one surface (persistence call sites) rather than one every
agent needs before starting. The guide keeps the rule and the four names; the argument for each
half, and why it matters, is below, verbatim as it stood in the guide.

`try? modelContext.save()` is allowed **only** when the save commits nothing but in-place field
edits to objects the store already holds, and nothing after it tells the user it worked. A site
breaks the rule if any of four halves is true:

1. **Existence** — the function inserts or deletes, **in its own frame or one below**: a pending
   change travels up through every frame *handed* a `ModelContext` and stops at the first that was not.
2. **Report** — something **anywhere in the swallowed commit's own block** says it worked: `dismiss…()`,
   `is/show<X> = false`, `editing/selected/pending<X> = nil`, `presentedX = …`, `onSave(…)`, an
   `@AppStorage` write, a write through **any `@Binding`** (the surface stays open and fills itself
   in — T-664, scalars too since T-997), **the answer itself** (`return true` from a `-> Bool`,
   non-`nil` from a `-> X?`), or **a rearrangement the user can see** (T-614). **A reorder surface
   answering `Bool` is never `@discardableResult`** (T-996). A "swallowed commit" is `try?` on a
   `save()` **or** a `Cadence*Persistence` helper — the commit surface, not the method name —
   **one frame down included**.
3. **Commit reach** — the function inserts **or deletes** and reaches no commit at all. A declaration
   **handed** a `ModelContext` is exempt by rule; one that reached for an ambient context must commit.
4. **The callee's undo** (T-1299) — `try?` over **any** helper that changes existence and reaches a raw
   `save()`; safe only if it changes no existence or commits through `CadencePendingChangePersistence`.

In `extension ModelContext` the receiver is `self` and is left off (T-1301): `save()`, `insert(` and
`delete(` count in every half above, and the declaration counts as **handed** its context for half 3.
All four are fixed the same way: commit through `CadencePendingChangePersistence` (`commitInsert` / `commitDelete` / `commitEdit(in:undo:)`), `throws`, take `commit:`, and name the failure on screen.
Why it matters: one `ModelContext` app-wide, so a swallowed failure leaves the change *pending*, for
the next unrelated `save()` to take or `rollback()` to discard. Enforced by `CadenceSaveCommitDisciplineTests`.

## Telling a queued run from a wedged one (moved out of AGENTS.md, 2026-10-06)

`./scripts/xcb.sh run-state [<id>…]` (T-2071). With an id it answers about that run; with **no id** it
sweeps every run in `$TMPDIR` from the last 6 hours and **exits non-zero on a wedge or an abandoned
run**, so a scheduled caller goes red without anyone watching (T-1920).

Seven verdicts, and the exit code for each:

| verdict | exit | what it means |
| --- | --- | --- |
| `RUNNING` | 0 | the xcb log **grew** between two reads |
| `QUEUED` | 10 | named, xcodebuild never launched — still waiting on the test-host lock |
| `WEDGED` | 11 | silent, zero result lines, **and** an xctest session that connected and never `requested serialized transport` (T-2067) |
| `FINISHED` | 12 | xcodebuild's terminal banner, and nothing still writing |
| `STALLED` | 13 | silent, and the T-2067 signature does **not** apply — re-read, do not kill |
| `ABANDONED` | 14 | a log that exists, stopped, and whose owner pid is gone |
| `NO-LOG` | 15 | nothing to read: never claimed, or named and never written |

`QUEUED` costs nothing: `xcb.sh` names `cadence-xcb-<id>.<ts>-<pid>.log` at the top of the script and
the redirect that creates the file does not happen until after `test-host-lock.sh acquire` returns, so
a queued run is a **dangling symlink with a live pid in its name**, and the verdict prints the lock
line beside it. Only a run that has *started* pays for sampling.

**The three signals agents reach for first are all wrong here, and each was measured.**

- A `> full.log` redirect is **not** the test log. Against one live, healthy, passing run it held 727
  bytes and 0 result lines while xcb's own log held 1,237,974 bytes and 3,135.
- **Elapsed time does not discriminate.** The full suite legitimately runs 19+ minutes.
- **CPU is a trap, not merely useless.** A wedged `xcodebuild` measured 12s of CPU across 35 minutes —
  but a **healthy** one measured 9.29s across 9:48, because `xcodebuild` is a parent and its children
  do the work. Low parent CPU is normal.

**Silence needs two windows.** Measured 2026-10-06 against a live healthy run: the xcb log sat at
exactly 707008 bytes for 75+ consecutive seconds inside `theTestHostLocksOwnGuardsStillFire()`, which
spawns real processes and real sleeps and prints nothing. So a run that grew in the first window
(`CADENCE_RUNSTATE_SAMPLE`, 30s) is answered at once, and only a run that did **not** pays for a
confirming second window (`CADENCE_RUNSTATE_SAMPLE_LONG`, 150s). `STALLED` exists so that a silent run
without T-2067's signature is never asserted to be a hang.

`scripts/xcb.sh selftest` section 13 induces QUEUED, RUNNING, WEDGED and ABANDONED against real
`xcb.sh <id> test` invocations on the production path.

## Did the heartbeat land anything? Read marks that ADVANCE (T-1920, 2026-10-06)

`./scripts/heartbeat-progress.sh report [<window-minutes>]` — default 60; exit **0 ADVANCING**,
**1 SILENT**, **3 NO-MARKS**. It reads three things on this Mac's disk, each of which only moves when
work actually landed:

| mark | where it is | what moves it |
| --- | --- | --- |
| `HEAD` | this checkout | a commit |
| `LAST-GREEN` | `$TMPDIR/cadence-xcb-last-green.<hash of tree root>` | a full green `-only-testing:CadenceTests` macOS run |
| `XCB-LOG` | the newest `$TMPDIR/cadence-xcb-*.log` | any xcb run writing |

**It does not read the scheduled task's run list, and that is the whole design.** T-1920 nominated a
liveness tell from that list — status `running`, `last_activity_at` seconds after `started_at`,
`now - last_activity_at` in hours — then refuted it, replaced it, and refuted the replacement. Three
readings, all wrong the same way: **a run list of two timestamps and a status string cannot separate
`waiting`, `wedged` and `slow`**, because a usage-limit wait produces exactly the hang's shape. The
entry's own closing instruction is not to build a fourth tell from those three fields.

So this answers **progress**, not liveness. `ADVANCING` is sound in one direction and that is the
useful one. `SILENT` says *no work landed* and deliberately does **not** say why — a heartbeat waiting
out a usage limit is silent and healthy. That non-claim is pinned as a string
(`NOT A LIVENESS VERDICT`) by `CadenceGuardScriptSelftestTests.heartbeatProgressVerdicts`, and the
selftest fails if the output ever says *hung* or *wedged*, because a SILENT verdict that quietly
starts asserting a hang is the fourth wrong reading written on top of the third.

It is still worth having, because the thing T-1920 wanted visible was never a hang in the abstract:
it was *the heartbeat ran for over 26 hours and committed nothing*. That is a SILENT verdict, it is
measurable without inferring anything, and the non-zero exit means nobody has to be watching.

`NO-MARKS` is separate from `SILENT` on purpose: a machine that has never run the heartbeat has
nothing that *could* have advanced, and reporting that as "no progress" is the same mistake as
reading a queue as a death.

Seams, reusing `xcb.sh`'s own names so there is no second spelling to drift: `CADENCE_TREE_ROOT`,
`CADENCE_XCB_STATE_DIR`, `TMPDIR`, plus `CADENCE_HBP_NOW` to substitute the clock.

**Still owed and not in reach of this checkout:** stopping a stuck run, and adding
`./scripts/ci-run-coverage.sh report` (T-1640's instrument, still called by nothing) to section 1 of
`~/.claude/scheduled-tasks/cadence-heartbeat-resume/SKILL.md`. Both edit the owner's file outside this
repository.

## The iOS compile-task count is an ARCH count, not a floor (T-1703, 2026-10-06)

Briefs have been quoting **"~1,390 swift compile tasks"** as the cold-iOS non-vacuity floor, and an
agent who built for a concrete simulator saw **695** and flagged it as a possibly failed build. Both
numbers are right and neither is a floor. Measured on this tree, all three through `scripts/xcb.sh`
with private DerivedData:

| destination                                       | `SwiftCompile` tasks | architectures      |
|---------------------------------------------------|----------------------|--------------------|
| `platform=macOS`                                  | **691**              | arm64              |
| `platform=iOS Simulator,id=<udid>` (concrete)     | **691**              | arm64              |
| `generic/platform=iOS Simulator`                  | **1382**             | arm64 **+** x86_64 |

`xcb.sh` counts one task per file per architecture. A **generic** simulator destination resolves to
every valid simulator arch and so compiles the whole target twice; a **concrete** simulator (and a
macOS build) compiles it once. 1382 = 2 x 691 exactly, and the 1,390/695 pair quoted from T-1492 is
the same 2x relationship measured 2026-09-30, when the target held 695 files rather than 691. So the
absolute number tracks the repository's file count and rots on every file added or removed; only the
**ratio** is stable.

Two consequences, and the second is the dangerous one:

1. **~695 on a concrete iOS destination is NON-vacuous.** A brief that quotes 1,390 without naming
   the destination shape has agents distrusting good runs, which is what prompted this entry.
2. **The count cannot tell a macOS build from an iOS one.** The macOS arm64 slice and the iOS
   arm64 slice compiled a **byte-identical list of 691 file names** — target membership picks the
   files and `#if os(iOS)` lives *inside* them, so no file is platform-excluded. Only the
   `-destination` argument and the `Debug-iphonesimulator` products path say which platform a log
   is. T-1781's rule above ("a macOS build is blind to `#if os(iOS)`") is unchanged by this; what
   changes is that you cannot verify you took the iOS build by reading its task count.

Evidence: `cadence-xcb-suitehygiene-ios-concrete.20261006-155435-58449.log` (concrete, `Cadence-iPhone15`
by id, `XCODEBUILD_EXIT=0`, 0 warnings, 691 tasks) beside three independent sibling runs of
`generic/platform=iOS Simulator` the same afternoon (`t1-ios`, `t2-ios`, `app2-ios`), each 1382 tasks
split 691 arm64 / 691 x86_64.

## Model inventory and shared value types

Displaced from `Cadence/Models/AGENTS.md` for T-3149 (2026-10-23). The guide keeps the operational rules.

`CadenceSchema.swift` is the authoritative list. Live models:

- `Context` - top-level grouping.
- `Area` / `Project` - list containers; both own tasks and list metadata.
- `AppTask` / `Subtask` - schedulable work and nested checklist items. `AppTask` also carries the full recurrence field set and `bundle`/`bundleOrder`/`tags`.
- `TaskBundle` - several tasks grouped into one timeline block (declared in `AppTask.swift`). `tasks` uses a `.nullify` delete rule; verify bundle/task deletion order carefully.
- `Tag` - cross-cutting label, many-to-many with both `AppTask` and `Note`.
- `Goal`, `GoalListLink`, `Habit`, `HabitCompletion` - long-running progress and recurring behavior. `Goal` nests via `parentGoal`/`subGoals`: a top-level goal is a direction (usually `kind == .ongoing`), its sub-goals read as milestones.
  **`GoalListLink` has no write path in the app** — [[T-2079]] retired `attachList` /
  `detachGoalListLink` / `toggleGoalListLink`; only the archive importer constructs one, never a
  hand-rolled `insert(GoalListLink(...))`. Readers still filter `isDeleted`: a pre-commit edit is
  what Xcode 26's `rollback()` undoes late ([[T-1321]]). What a duplicate link does and does *not* break:
  `docs/MODELS_AGENTS_REFERENCE.md`, "The one write path for a goal list link"; the
  substring-grep trap is in `Cadence/Shared/AGENTS.md`.
- `Note` - the single live note model (see `Cadence/Models/AGENTS.md`).
- `SavedLink`, `MarkdownImageAsset` - list bookmarks and editor image assets.
- `SidebarLayoutPreference` - the sidebar's visible rows and their order, **synced** (T-1274: the
  owner chose across devices). Two comma-separated `CadenceFeatureDestination` raw-value strings,
  not a to-many. Read and written only through `Shared/CadenceSidebarLayoutPreferenceStore.swift`,
  which owns the duplicate rule (**newest `updatedAt` wins**, `id` breaks a tie, losers are left
  alone rather than deleted), the device-local fallback, and the one-visible-row floor. A
  destination the stored strings never name keeps its declared slot and stays visible, so a future
  enum case needs no migration; an unrecognised token is dropped on read.
- `LookPreference` - the **synced** accent palette, sidebar tints, each surface's sort, grouping
  and show-completed (T-1307, [[T-1288]]), and since [[T-1347]] the work-hours window in a second
  pair map, `calendarPresentationRaw`. Read only via `CadenceLookPreferenceStore`: the record is
  truth across devices, the local defaults its **mirrors** — how the widget reads the accent.
- `NoteTemplatePreference` - the **synced** note-template overrides ([[T-1346]]: the owner decided a
  template they wrote is content, like a note). One JSON map — the same string `NoteTemplateLibrary`
  has always written to the `noteTemplateOverrides` default, which is now this record's mirror.
  Read and written only through `CadenceNoteTemplatePreferenceStore` /
  `CadenceNoteTemplatePreferenceSync`, which own the duplicate rule (newest `updatedAt` wins, `id`
  breaks a tie), the canonical spelling of an override map, and the **one-shot first-run merge**
  that carries a device's pre-sync templates into the shared row without overwriting another
  device's. Steady state is whole-map last-writer-wins; a reset travels as `{}`, which is a value
  here and not an absence. `overridesRaw` is markdown-bearing and is in
  `CadenceMarkdownSourceInventory`.

Non-`@Model` types that live in this folder: `TaskSectionConfig` / `TaskSectionDefaults`
(in `AppTask.swift`) and `GoalContributionSummary`. Two more *files* here declare no type at all —
`GoalPresentation.swift` (an `extension Goal`) and `HabitInsights.swift` (an `extension Habit`,
listed here as a type for a long time; there is no `HabitInsights` symbol to reference) — and two
this list omitted for a long time carry rules of their own:

- **`ModelEnums.swift`** — the ten data enums (`TaskPriority`, `TaskStatus`,
  `TaskRecurrenceRule`, `TaskRecurrenceEndMode`, `ProjectStatus`, `AreaStatus`, `GoalStatus`,
  `GoalKind`, `GoalProgressType`, `HabitFrequency`). Every one is `nonisolated`, and a new one
  must be too: a status enum written without it builds fine in the app and breaks `CadenceWidgets`
  and `CadenceMCPServer`, the second as an error rather than a warning.
  `CadenceTests/NonisolatedValueTypeTests` is the guard.
- **`TaskOrdering.swift`** — `TaskSortField`, `TaskSortDirection`, and `TaskOrdering`, the app's
  one task comparator. It lives here rather than in `Shared/` or `macOS/` because the widget and
  MCP targets order tasks and compile only `Models/`. **The tie-break must stay total**
  (`fallbackPrecedes`: `order` → `createdAt` → `title` → `id`), which `TaskOrderingTests` pins by
  sorting a tie-heavy set from two permutations and requiring byte-identical output. And **the raw
  values are persisted** in `@AppStorage` and per-list `UserDefaults` keys — renaming a case is
  fine, changing a raw value silently resets every saved sort preference. Why a partial order
  reshuffles rows between renders, and what `SWIFT_DEFAULT_ACTOR_ISOLATION` does to a bare value
  type: `docs/MODELS_AGENTS_REFERENCE.md`, "Why the enums and the comparator live here".


## MCP arm and source membership history

Displaced from `CadenceMCPServer/AGENTS.md` for T-3149 (2026-10-23). The guide keeps the operational rules.

  **Four of those arms carry a refusal, a removal or a lifting condition whose SHAPE is what the
  next arm-shaped question gets measured against, and not one is re-decidable from a summary**:
  `create_goal`/`create_habit` **removed** rather than left advertised and refusing ([[T-2077]],
  0.13.0 -> 0.14.0, `list_goals`/`get_goal`/`list_habits` untouched); `create_list_note` lifted by
  splitting a FILE rather than by changing a rule, and still taking no **body**; `create_tag`
  refused twice before `TagSupport.creationDecision(for:in:)` existed to be asked ([[T-1406]]);
  and the four block arms, refused for seven sittings and then **removed outright, read arms
  included** ([[T-3170]], 0.15.0 -> 0.16.0: the startup pass deletes the rows). All four in full:
  `docs/MCP_AGENTS_REFERENCE.md`, "What the create and update arms cover", "Why one kind had
  no constructor" and "Why deletion is refused".
- **Eleven `Cadence/Shared/` files are in the Sources phase, and none of them earns its place for
  the obvious reason.** Each earns it by one rule a hand-rolled copy would re-break — a rename that
  would otherwise strand every card on a name no column has, T-509's case-insensitive scheme rule
  — never by the feature it arrived with. Adding another is still not casual: one more path by
  which an app-side edit breaks a target no scheme builds — and `CadenceListNoteFiling` cost a
  file **split** rather than a file ([[T-1122]]). **A file stops earning it, too, and then it
  goes**: `CadenceTrackingMutationSupport`, `GoalAssignmentRules` and `CadencePluralization` lost
  their last caller here when [[T-2077]] removed `create_goal`/`create_habit`, and [[T-3010]] took
  all three out of the phase while leaving them on disk for the app. Sweep when an arm is retired,
  not only when one is added. **The eleventh, `CadenceTaskBundleMutationSupport`, is the second
  that cost a split — of the *declaration*** ([[T-1122]]). What each is for:
  `docs/MCP_AGENTS_REFERENCE.md`, "Why eleven shared files joined the Sources phase" and "Why
  the tracking helpers cost four files".
