# CI parity — what differs between GitHub CI and this Mac

Every brief says *local green is necessary, not sufficient* and names no mechanism, so nobody can
act on it. This file is the mechanism. Read it when a CI run is red and your local run was green,
or before pushing `main`.

Written 2026-10-21 by agent `ciparity` from the CI run history and the tree. **The build is not
broken:** the seven CI runs since `39298796244` (2026-10-19 17:59) are all green. This is what
diverges, not an outage.

## The two environments, measured

| | CI (`runs-on: macos-latest`) | this Mac |
| --- | --- | --- |
| image | `macos-26-arm64` / `20261013.0424.1` | — |
| Xcode | **26.0.1** | **27.1** (27A9275) |
| Swift | 6.2 (`swiftlang-6.2.0.19.9`) | 6.4 (`swiftlang-6.4.0.34.1`) |
| SDK / target | macOS 26.0, `arm64-apple-macosx26.0` | macOS 27 |
| kernel | Darwin 25.6.0 | Darwin 27.0.0 |
| cores | 3 | 11 (M3 Pro) |
| time zone | **UTC** | America/New_York |
| tree under test | `actions/checkout` of the pushed tip of `main` | a worktree or `git archive` at *your* base |
| test scope | all of `CadenceTests`, serial, every push | usually `-only-testing:` a few suites |
| UI tests | never (T-531) | local only |
| iOS simulator tests | the three `deliberatelyIOSOnlyTestFiles` suites, 22 tests, on an iPhone 17 / iOS 26.5 simulator under the newest image Xcode that lists one (picked each run: 26.6 in [[T-6821]]'s runs, 26.4.1 in run 40650042891) -- [[T-6821]] | any suite, on `Cadence-iPhone15` |

Two details people get wrong. The image carries `Xcode_26.0.1` *through* `Xcode_26.6` and defaults
to 26.6; `.github/scripts/assert-toolchain.sh` pins the exact minor **26.0** since [[T-4742]] (it
used to take the first lexical `Xcode_26*.app`, which happened to be the oldest), so CI runs
26.0.1 and an image that drops 26.0.x goes red at *Assert toolchain* rather than moving silently. And the runner's local clock is
UTC — its `xcb.sh` log stamp `20261018-033216` sits against the `03:32:16Z` step timestamp.

**Correction, measured 2026-10-28 on hosted run 40628569258 ([[T-6821]]), filed as [[T-7661]]:** the
pin above holds for bare `xcodebuild` calls only. `scripts/xcb.sh` defaults `XCODEBUILD` to
`/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild`, and on the image `Xcode.app ->
Xcode_26.6.app`; that binary evidently does not follow `xcode-select`, since both `xcb.sh` compile
logs read (`ci-ios`, and `ci-tests` on run 40629814847) name `Xcode_26.6.app` in its log and never `Xcode_26.0.1.app`. Every
CI compile before T-7661's fix was therefore 26.6. **Fixed by T-7661:** `xcb.sh` now resolves an
unset `XCODEBUILD` to `$DEVELOPER_DIR/usr/bin/xcodebuild`, else `$(xcode-select -p)/usr/bin/xcodebuild`,
else the old `/Applications/Xcode.app` path, so its compiles follow `assert-toolchain.sh`'s pin; the
iOS-simulator step still sets both variables to the Xcode it picks. Pinned by `xcb.sh selftest`
section 19 and `CadenceGuardScriptSelftestTests`. On this Mac `xcode-select -p` is
`/Applications/Xcode.app/Contents/Developer`, so nothing changes locally.

**iOS simulator tests in CI ([[T-6821]]).** The image installs iOS Simulator runtimes 26.2, 26.4.1
and 26.5 only. Xcode 26.0.1 and 26.1.1 list no eligible iOS Simulator destination (and with
`IPHONEOS_DEPLOYMENT_TARGET = 26.1` a 26.0 runtime fetched by `-downloadPlatform` would be below the
deployment target -- reasoned, not run); 26.2
through 26.6 list 33. So `ios-build`'s last step picks the newest image Xcode listing an iPhone at
iOS >= the deployment target, REBUILDS under it (`build-for-testing`, one arch, its own DerivedData,
log gated by `check-log.sh`) and runs the iOS-only suites `test-without-building`. Measured on
runs 40629814847 and 40632388234: rebuild 342 / 381 s (1282 compile tasks, 0 warnings), test 263 /
336 s for 22 tests that take ~3 s (the rest is simulator boot and host launch), step 627 / 734 s.
`ios-build` went to ~22.5 min against ~23 min for `macos-tests`, so the critical path is about even.

**The iOS build is an exception to the pin ([[T-7841]], 2026-10-28).** Once T-7661 put `xcb.sh` on
26.0.1, `Build iOS surface` could not build at all: actool's asset-catalog compile needs a simulator
runtime matching the iphonesimulator SDK, and run 40644521083 failed with *No simulator runtime
version from ["23C54", "23E254a", "23F77"] available to use with iphonesimulator SDK version
23A339* -- 26.0.1's SDK has no runtime on this image (26.2, 26.4.1, 26.5 only). So `ios-build` now
runs T-6821's picker in its own step, `Pick the iOS Xcode`, BEFORE its first compile, and exports
`DEVELOPER_DIR`/`XCODEBUILD` through `$GITHUB_ENV`: both of its compiles run under the newest image
Xcode with an eligible iPhone runtime -- picked per run, not fixed: [[T-6821]]'s runs got 26.6, but
first green run 40650042891 found 26.6 and 26.5 listing no eligible iPhone and took 26.4.1 (iPhone 17,
iOS 26.5). Before T-7661 that job compiled under `/Applications/Xcode.app` (26.6), so either way it was
never 26.0.1. `assert-toolchain.sh` is unchanged and still runs first in that job, so an image
without 26.0.x is still red there; the macOS jobs (`macos-tests`, `mcp-server`) stay on 26.0.1. The
consequence to keep in mind: **shared Swift is gated by 26.0.1 on the macOS leg, but `#if os(iOS)`
code is compiled only by the newer Xcode.** The alternative that keeps iOS on the pin,
`xcodebuild -downloadPlatform iOS` under 26.0.1 (a 26.0 runtime, several GB per run), was not
measured.

The same run's other red, `CadenceTests (macOS)`, was a real 26.0.1-only diagnostic of mode A below:
*ambiguous use of operator '/'* at `CadenceAccentPaletteTests.swift:538` for
`(srgb.redComponent * 10000).rounded() / 10000` inside a `[Double]` literal -- CGFloat or Double.
Xcode 27 accepts it. Fixed by converting to `Double` before the arithmetic. Any `CGFloat`
expression landing in a `Double` context is the shape to watch.

## What actually went red

31 failing CI runs between `83479456` (2026-10-14 16:10) and `66a58761` (2026-10-18 10:41), while
every local full run read green — e.g. `e7a5ede6`: 6107 tests, 0 warnings here, red there.

**26 of those 31 were one cause** ([[T-3215]]): eleven Swift 6 warnings reading *main
actor-isolated conformance of `AppTask`/`Habit`/`Goal` to `CadenceDeleteSurvivorMember` cannot be
used in nonisolated context*, from `Cadence/Shared/CadenceTaskMutationSupport.swift`. They failed
`CadenceTests (macOS)` **and** `Build iOS surface` together, because `check-log.sh` gates the
warning count at zero. Fixed in `aa71f408` by spelling the three conformances
`nonisolated extension`. That single fact is worth more than the rest of this section.

The other five: four source-scan/geometry tests in the first red (`83479456`), a host-zone clock
scan in two of the last three ([[T-3225]]), a SIGTRAP'd test host ([[T-3218]]), and three
`ledger-lag` reds that have nothing to do with the toolchain at all.

## The failure modes, and the check for each

**A. A diagnostic Xcode 26 emits and Xcode 27 does not.** 26 of 31. The counters are *not* the
divergence: `scripts/xcb.sh:475-476` and `.github/scripts/check-log.sh` gate the same two patterns
(`\.swift:N:C: warning:` and `macro expansion …: warning:`). The *compiler* differs. **Live?** The
instance is dead — `CadenceDeleteSurvivorMember` is the tree's only `nonisolated protocol` and all
three conformances are `nonisolated`. The class is live and **not checkable here at all**: this Mac
has one Xcode, and that is decided rather than pending -- [[T-3277]] option (c), owner ruling
2026-10-26: no second Xcode beside 27; **CI is the gate, so push small** (one landing per push), so
a red names its commit and is cheap to bisect. The one shape seen so far, an orphaned attribute,
is linted locally by `CadenceOrphanedAttributeLintTests`. Nearest local check for the rest, which
is a smell test and not a proof:

```bash
rg -n '^\s*(public )?nonisolated protocol ' --glob '*.swift'   # every conformance must say nonisolated
```

**B. A whole-suite guard red over a tree no local run held.** The assertion lives in a file the
change never opened, so a `-only-testing:` run over a branch's own suites is green over a red tree
([[T-3264]]); and CI tests the *merged tip* while each agent tested its own base. This is what
broke `83479456` (comment-claim, typography and animation sweeps) and `e6a226b6`
(`noSourceFileSpellsAClockWithoutAskingTheHourCycle`, whose offender arrived in a different
agent's `f1fe7afc`). **Live? Yes — this is the mode that recurs.** Check: run the census suites
against *what you are about to push*, not against your branch's own suites. One shape of it is
now gated ([[T-3264]]): `agent-commit.sh` refuses `TEST-NAME-SHARED` when a commit staging a
`CadenceTests/*.swift` leaves a `@Test` name declared twice (the `830a428d` / [[T-6650]] red),
reading the private index with `test-suite-index.sh --shared-names` in a few seconds. The other
three measured shapes (a source spelling asserted by a suite in a file the change never opened)
are not gated -- no build-free check can tell which assertion an edit moves -- but every one of them
quoted the changed file's repo path, so `./scripts/test-suite-index.sh --readers <changed
product files>` prints the `-only-testing:` arguments that would have caught each ([[T-7710]]).
Add them to your scoped run. It cannot see a directory walk or an assembled path, so the census
suites still need the full run before you push `main`.

**C. Host time zone.** CI is UTC, this Mac is America/New_York, and a test reading
`Calendar.current` can only pass on one of them ([[T-3225]]). **Live? Guarded.** The guard runs
locally, so this one is cheap to settle:

```bash
scripts/xcb.sh <id> test -scheme Cadence -destination 'platform=macOS' -only-testing:CadenceTests/CadenceTimeZoneIndependenceTests
```

**D. A 3-core headless runner.** `theProbeReadsAnEagerListAsFarLargerThanALazyOne` did not fail an
assertion — its test host took SIGTRAP ~0.4 s in, on a SwiftData save notification. [[T-3215]]
removed the trigger; [[T-3218]] is the durable fix and is **OPEN**. **Live? Yes. No local check.**

**E. Jobs with no local caller.** Five CI jobs run things no `xcb.sh` run makes. All but
`push-attribution` are runnable here — see the list below. Three of the 35 reds in this window were
`ledger-lag`, a pure repo-process gate.

**F. `.github/` encodes an unpinned runner.** `ci.yml` pins no image while `assert-toolchain.sh`
refuses any major but 26, so the day `macos-latest` moves to a macOS 27 image, CI goes red for a
reason not in this repository. Filed as [[T-3273]]; not fired.

## Run these before pushing `main`

Each is cheap, needs no test host, and covers a job this Mac otherwise never exercises.

```bash
./scripts/ledger-lag-check.sh origin/main   # or the sha you will push — NOT bare HEAD
zsh -f ./scripts/ci-run-coverage.sh selftest
zsh -f ./scripts/test-host-lock.sh selftest # spawns and pkills fake hosts — not while a run is live
./scripts/xcb.sh <id> build -scheme CadenceMCPServer -destination 'platform=macOS'
```

Never pipe them: `$?` after a pipe is `tail`'s, not the gate's. And `ledger-lag-check.sh` takes a
rev and defaults to `HEAD` — measured 2026-10-21, bare it exits 3 on a branch-only WIP commit this
worktree carries while `origin/main` exits 0 ([[T-3272]]).

## What cannot be checked here at all

Say so rather than implying coverage you do not have.

- **Any Xcode 26 diagnostic.** One toolchain is installed. No local run, however full, can predict
  a warning or error that only Swift 6.2 emits. This is the gap that cost 26 red runs, and the only
  instrument for it is a CI run.
- **Runner-timing and layout behaviour** — SwiftUI realization counts, the T-3218 trap, anything
  that depends on three cores and no window-server session.
- **`push-attribution`**, which reads `github.event.before..after`. That grouping exists only
  inside the push event; no later reading reconstructs it.
- **`CadenceUITests`**, on the CI side (T-531). Local-only, so CI cannot confirm a UI flow either.

## What this reading could not determine

`gh run view --log-failed` returns the failed *steps* only, and the per-test assertion text lives in
the uploaded `test-log` and `xcresult` artifacts, which expire. The four tests red at `83479456`
are named above from their result lines; **why** each failed was not recoverable from the run logs.
