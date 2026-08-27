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
- **Tests go in the right `struct`**, and on a green log `grep -c '✔ Test <name>()'` must be exactly
  **1** per new name. A name shared with another suite makes mutation evidence ambiguous.
- **Any source scan needs a non-vacuity assertion** that it actually read the files it claims to.
- **Never** launch or build the Cadence app, kill a process named `Cadence`, use a simulator, touch
  the real app-group store, or set `CADENCE_MCP_ENABLE_WRITES`.
- **Delete your DerivedData when you finish** (~1.7 GB) and release the lock.
- See also the lock path, stale-owner, `sleep`, compile-error-count and vacuous-warning rules above.
