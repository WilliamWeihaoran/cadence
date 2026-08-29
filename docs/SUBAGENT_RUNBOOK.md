# Subagent verification runbook

Coordinator briefs point here instead of restating this. Read it once; it replaces ~600 words of
per-agent boilerplate.

- **Work in an isolated copy.** `rsync -a --exclude .git <repo>/ /private/tmp/cadence-<tag>/`, work
  there, never edit the user's repo, never commit. The coordinator diffs your tree against **current
  HEAD** and lands it.
- **Scoped runs only.** Run `-only-testing:CadenceTests/<YourSuite>` for failing-first and every
  mutation. Do **not** run the full `CadenceTests` suite — the coordinator runs one integration pass
  for the whole batch, so a full run from you costs six minutes and duplicates it.
- **One script holds the lock.** Put `acquire`, a foreground `xcodebuild`, and `release` (via
  `trap ... EXIT`) in one script and launch it with `nohup ... &`. Acquiring in one shell and
  backgrounding xcodebuild in another releases the lease immediately.
- **Evidence that counts:** run new tests against unmodified source first and confirm they fail. If
  a test cannot compile against unmodified source, say so and use a branch mutation instead — do not
  fake it. Report which tests each mutation killed **by name**; that is what shows the kill is
  attributable to your tests rather than collateral damage.
- **Tests go in the right `struct`.** `scripts/test-suite-index.sh <name>` tells you which suite
  actually declares a test, so scope a run to what the source says rather than to where you meant to
  type it. It attributes by suite **extent**, so a test appended past the last suite's closing brace
  reads as `<file scope>` — the bucket that should always be empty, and is now held empty by
  `CadenceTestTargetHygieneTests.noTestInTheTargetIsDeclaredOutsideEverySuite`. The residual case
  it cannot see is a test declared inside the wrong *sibling* suite of a multi-suite file; that one
  is still a read, not a guard (T-465). Name uniqueness across suites is enforced by
  `CadenceTestTargetHygieneTests.everyTestFunctionNameInTheTargetIsUniqueAcrossSuites`, so
  `grep -c '✔ Test <name>()' == 1` is a property of the target now, not a manual check.
- **Any source scan needs a non-vacuity assertion** that it actually read the files it claims to,
  and any *sweep* goes through `CadenceScanInstrument` — its initializer runs the detector against a
  positive and a negative fixture, so a blinded detector cannot reach a sweep at all, and its
  `atLeast:`/`including:` arguments make the walk's non-vacuity a compile requirement.
- **Never hand back a rewritten `docs/TODO.md` or `docs/TODO_DONE.md`.** Report your ticket changes
  as a **delta** in your final message -- which ids you closed, with the closure text, and which you
  filed -- and leave both files at the revision you started from. These two files append quietly
  instead of conflicting loudly: two agents each rsync a copy, each edits its own, and whichever
  lands second silently reverts the first. That has cost real time three separate times (once
  duplicating the whole file, 34 ids over). It is also why your new-ticket ids are **suggestions**:
  the coordinator allocates the real ones, because ids you pick in isolation collide with ids
  another agent picked in parallel.
- **Never** launch or build the Cadence app, kill a process named `Cadence`, use a simulator, touch
  the real app-group store, or set `CADENCE_MCP_ENABLE_WRITES`.
- **Delete your DerivedData when you finish** (~1.7 GB) and release the lock.
- See also the lock path, stale-owner, `sleep`, compile-error-count and vacuous-warning rules above.
