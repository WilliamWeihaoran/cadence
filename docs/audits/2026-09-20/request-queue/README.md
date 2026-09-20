# R41-R50 research handoff

```text
Tree read: 231a7a8
Dirty files at initial snapshot: 0
Source baseline: agent-scratch.sh archive of 231a7a8
Later concurrent work: 16 status entries / 19 individual paths, before this report was written
Product/test/TODO edits by this audit: none
App builds, CadenceTests, UI tests, app/simulator launches: none
Executed: history replay, standalone Foundation/SwiftSyntax probes, two shell fixture selftests
```

All source line references below are to **231a7a8**, not to a moving checkout. A later agent began
editing the schema, app wiring, exports, tests, commit helper and icon assets while this audit ran.
Those changes are not credited as landed fixes. See R43 in `docs/CODEX_REQUESTS.md` for the paths.

`MEASURED` means the stated command/probe ran or the cited source/history was inspected.
`REASONED` means the consequence or proposed remedy is inferred. Source inspection is not a
runtime measurement. This is a bounded investigation, **not a certification of every guard or
every assertion**. R42's exhaustive guard-by-guard classification and R46's complete mutation
matrix remain open. R50 covers integration machinery in the range, not every changed UI behavior.

## Priorities

1. Before the cross-device TestFlight experiment, verify/deploy the complete Production schema.
   R49 explains why unrelated content failing to sync does not exonerate an undeployed type.
2. Add failing fixtures for the defaults-routing and radius scan gaps, then improve the readers.
   These are test-instrument defects, not evidence of a currently shipping unrouted preference.
3. Narrow the message-file ownership check's substring ambiguity; retain its real collision guard.
4. Decide how legitimately reopened/in-progress tickets are represented to the history-wide CI gate.
5. Correct the checkable comments and the optional-archive parser; do not change product behavior
   merely to make those comments true.

## R41: Actual removal-guard cost

**MEASURED:** `scripts/agent-commit.sh:1847` uses line membership:
`grep -F -x -v -f <new> <old> | grep -c .`. It does not count diff deletions. Blank lines do not
count; removing one occurrence of a line still present elsewhere does not count. A rewrite whose
old text exists elsewhere can evade it. The premise "any rewrite" is therefore too broad.

Run from the repository root:

```sh
ruby docs/audits/2026-09-20/request-queue/history-removals.rb 231a7a8
```

| Population | Measured result |
| --- | ---: |
| Reachable commits | 1,152 |
| Merge commits excluded | 12 |
| Non-merge commits with binary replacements/deletions excluded | 3 |
| Evaluated non-merge commits, including root | 1,137 |
| Would require a removal acknowledgement | 950 / 1,137 = 83.55% |
| Most recent 100 evaluated commits | 82 / 100 |

This replays the current line-membership rule against each commit's parent, with renames treated
as delete/add, not the historical version of the entire commit helper. New paths are skipped, as
they have no HEAD lines to remove; that also covers newly added binary assets. It does not claim those
commits actually encountered this refusal or passed its earlier guards. Across all 1,152 commits,
the exclusions bound the fraction at 950/1,152 to 965/1,152, about **82.47%-83.77%**.

**Not measurable from this history:** which of the 950 removed *unseen sibling work*. The final
commit tree does not preserve the submitting agent's trusted starting SHA, what it had read, or
whether a deletion was intended. Authors/Co-Authored-By trailers are not per-hunk ownership. No
true-positive numerator or rate is established; the recorded past incidents are not a complete
ground-truth sample. Calling all 950 false positives would be equally unjustified.

**REASONED recommendation:** keep the acknowledgement policy until a narrower rule has been
replayed with provenance. Record a trusted base SHA when allocating each agent's scratch, then
three-way compare base/HEAD/proposal per path. Escalate removals of incoming HEAD changes, plus
the existing ledger invariants. Merely checking whether the working path is behind HEAD misses
a stale reconstructed `path=content` supplied from elsewhere; the current
`REBUILD-BEHIND-HEAD` checks at `scripts/agent-commit.sh:1041` address that separate entry point.
Even a trusted-base rule does not catch deletion of old-but-important code, an intentional but
incorrect edit, or a duplicate-line semantic loss. It is a concurrency guard, not code review.

## R42/R46: Demonstrated scan gaps

### G1: Defaults routing is still sensitive to whitespace (P2, guard defect)

**MEASURED:** `CadenceTests/CadenceDefaultsRoutingSweepTests.swift:111` lists six literal strings;
the instrument at `:384` applies `codeOnly` and then `contains`. On code without strings/comments,
the supplied probe reads those exact six literals and measures:

```text
let d = UserDefaults.standard                 => true
let d = UserDefaults\n    .standard            => false
let d: UserDefaults = .standard               => true
let d: UserDefaults =\n    .standard            => false
let d = CadenceDefaults.store                 => false
```

**Reachability:** ordinary Swift wrapping can introduce this today. This is not a claim that the
current app contains a bad wrapped read. The known positional `.standard` limitation is already
documented at `:83`; these whitespace cases need no alias or type inference and are cheaper to fix.
The literals were introduced in `924fab8`; this gap was born with that detector, not killed by a
later refactor. Existing controls at `:204` exercise only single-line spellings.

**Suggested fix:** recognize token sequences independent of trivia, retaining the router and
target-membership exemptions. Keep the `CadenceAccentPalette.standard` negative control. Add the
two wrapped fixtures and a double-space variant before implementation. A raw global `.standard`
ban would incorrectly flag other types; semantic aliases still require type resolution.

### G2: Radius scan misses its advertised typed declaration (P3, guard defect)

**MEASURED:** `CadenceTests/CadenceRadiusControlSweepTests.swift:98` has a pattern requiring the
number immediately after `:`/`=`. `:106` splits the source into lines before matching it:

```text
cornerRadius: 10                       => 1
cornerRadius:\n    10                  => 0
let cornerRadius: CGFloat = 10         => 0
cornerRadius: Theme.radiusControl      => 0
```

**Reachability:** both missed forms are ordinary code. The source search found no current live
instance of these exact forms under `Cadence/`; this is missing protection, not a discovered UI
radius regression. The header at `:94` explicitly promises typed declarations. `git show
b0b2eef:CadenceTests/CadenceRadiusControlSweepTests.swift` already has both the promise and the
same per-line pattern. **Born incomplete in `b0b2eef`; not introduced by T-1297.** `6f2bca5`
correctly fixed exemption anchoring but did not fix the detector's grammar.

**Suggested fix:** collect literal matches on tokens/declarations, then map each match to its
source line and enclosing declaration. Preserve T-1297's declaration-based exemptions and its
unrelated-sibling control. Add fixtures for a wrapped call, a typed constant, comments between
tokens, and a numeric near-miss. Do not revert to fixed line-number exemptions.

Reproduce G1/G2 against the chosen source root (the runner reads patterns from that root):

```sh
swift -module-cache-path /tmp/cadence-rq-probe-cache \
  docs/audits/2026-09-20/request-queue/text-probes.swift "$PWD"
git blame -L 94,112 -- CadenceTests/CadenceRadiusControlSweepTests.swift
git blame -L 110,118 -- CadenceTests/CadenceDefaultsRoutingSweepTests.swift
```

### Remaining source-guard triage

The generated `source-candidates.tsv` provides file, assertion line, test name, syntactic shape and
expression. **MEASURED:** SwiftSyntax parsed 323 top-level Swift files in `CadenceTests`; 189 files
had one of the documented source-reader markers; the selected shapes produced **5,625 candidate
assertions in 1,702 test functions**. These are **not 5,625 source guards**. A file may mix data
tests and source tests; indirect/differently named readers can be absent. No assertion-level
data-flow classification or exhaustive manual review was done. The scanner itself states this
limit rather than certifying its own completeness.

| Rank | Guard and source | Ordinary change it cannot reliably distinguish | Disposition |
| --- | --- | --- | --- |
| High | Defaults routing, `CadenceDefaultsRoutingSweepTests.swift:111` | Wrapped member/default argument | G1, measured matcher gap |
| High | Rollback census, `CadenceEditorSaveCommitSurfaceTests.swift:1049` | `rollback ()`, or implicit receiver inside `extension ModelContext` | REASONED gap in this separate census; T-1301 fixes the save-rule reader, not this regex |
| High | Raw text mutation, `MarkdownTableMobileEditingTests.swift:614` | `.replace(range,` followed by `withText:` on another line | REASONED: `.*` explicitly excludes newline; require a multiline fixture |
| High | Commit-result order, `CadenceSourceScanSupport.swift:665` | A nested closure or string contains `catch`/report text; lexical order is not execution order | REASONED; replace high-risk call-site proofs with injected failures |
| Medium | Choice-picker wiring, `CadenceChoicePickerDismissalTests.swift:82` | Equivalent binding initialization/API extraction; inert required text can remain in another branch | REASONED; types and behavioral commit-result checks are stronger |
| Medium | Radius tokens, `CadenceRadiusControlSweepTests.swift:98` | Typed declaration/wrapped literal | G2, measured matcher gap |
| Medium | Accessibility wiring, `CadenceIconOnlyColorSwatchAccessibilityTests.swift:150` | Required label text remains on an unused control while the visible control changes | REASONED; source presence is not rendered accessibility coverage |
| Medium | Allocation helper, `CadenceOrderAllocationTests.swift:154` | Helper name remains in a dead branch while the real assignment changes | REASONED; existing behavioral `nextOrder` tests protect the helper, not all private callers |
| Lower | Retired copy, `CadenceRetiredCopyTests.swift:178` | Equivalent text split across interpolations/concatenation | REASONED; localized output/surface tests, not more forbidden substrings |

These are ranked reader limitations, not nine new production bugs or nine demonstrated whole-suite
survivors. Whole-suite mutation outcomes were not measured. T-1308 already files the renumber/undo
false positive (`CadenceSaveCommitDisciplineTests.swift:2237`); do not re-file it.

**Compiler substitutions:** remove `@discardableResult` from meaningful command results and retain
the zero-warning gate (explicit `_ =` still defeats that warning); use separate draft versus
committing initializer types; keep unsafe mutation APIs inaccessible to views/targets and expose
throwing commit helpers. The compiler enforces access, actor isolation, argument types and unused
results, not that the caller never uses `try?`, that a label is visible, or that a catch restores the
right fields. Use injected commit failures for the latter. SwiftSyntax eliminates spelling drift;
it is not a substitute for data-flow or behavioral tests.

### Guard verification limits

**MEASURED on the then-clean checkout:** `scripts/ledger-lag-check.sh selftest` reported
**20 passed, 0 failed**; `scripts/xcb.sh selftest` reported **45 passed, 0 failed**, including an
absent simulator, OS-qualified selection, an unknown suite, real warnings, and vacuous counts.
Neither launches Xcode builds or a simulator. `scripts/ledger-lag-check.sh` at HEAD reported
`1152 commits, 744 ledger entries, 285 examined, 0 findings`, exit 0.

An attempted `agent-commit.sh selftest` later read a **concurrently edited** script, reached its
new T-1305 fixture and was interrupted. It is **not** evidence about `231a7a8`, not a passed
selftest, and not a product regression report. No whole-suite `mutate.sh` run was made.

Fourteen `scripts/*.sh` files were inventoried. No claim is made that every refusal, canary,
exemption and cross-script interaction has been exercised. The remaining matrix needs, per
guard, a current positive witness, nearest valid negative witness, disabled-guard mutation and
its owning CI/test entry point. A list of refusal names alone cannot close R46.

## R47: Framework-boundary tests to compare

**MEASURED configuration correction:** `.github/scripts/assert-toolchain.sh:20,57,82` requires
major **26** and chooses an installed matching Xcode; it does **not** pin 26.0.1. The workflows use
`macos-latest`. Local `Xcode.app/Contents/Info.plist` reports 27.0. No live CI runner or second
toolchain was queried. Record OS build, SDK, Xcode build, architecture, locale and timezone in any
comparison; a framework observation is not attributable to the Xcode version alone.

**No new 26/27 flip was measured.** These are the highest-value unresolved comparisons:

| Priority | Assertion/observation at 231a7a8 | Why it needs both environments; do not weaken blindly |
| --- | --- | --- |
| 1 | `CadenceSubtaskInverseParityTests.swift:409,425,442` | Immediate back-population of either inverse before save/fetch. Explicitly a framework sentinel, not an app implementation test. |
| 1 | `CadenceTaskInspectorHostTests.swift:123,134`; `CadenceBundleInspectorHostTests.swift:91` | Pins which lifecycle signal fires before/after save, beyond the combined app-level close predicate. Preserve the close invariant even if observation timing changes. |
| 1 | `CadenceListCascadeRollbackTests.swift:80,123`; `CadencePendingChangePersistenceTests.swift:134` | Pending deletion/rollback behavior and relationship visibility. Separate fresh-context stored rows from retained instances. |
| 1 | `CadenceHabitCompletionDuplicateTests.swift:362` | Captured-array restoration after refused uncheck; check that explicit restore does not duplicate the relationship on either runtime. This is repository behavior worth keeping strict. |
| 2 | `DateFormatterSupportTests.swift:44` | `yyyy-MM-dd` parser acceptance of slash separators, overpadded components and short years. Foundation parsing policy, unlike the app's canonical-output requirement, may change. |
| 2 | `MarkdownEditorImageRelayoutTests.swift:217,321` | Native text layout, drawing and a 0.5pt containment tolerance. Measure in both environments; keep containment instead of pinning one absolute glyph height. |
| 2 | `DateFormatterSupportTests.swift:386,436` | System-font widths against fixed rail budgets. A font/OS metric change can cross the threshold even with identical Swift code. |
| 3 | `CadenceTimeZoneIndependenceTests.swift:443` | Los Angeles 23/25-hour dates depend on calendar/timezone data. Named-zone fixtures are already stronger than ambient time. No reason found to predict a flip for these dates. |
| 3 | `CadenceSourceScanSupport.swift:64,313`; `MarkdownTableMobileEditingTests.swift:619` | Foundation regex behavior underlies the scans. The demonstrated wrapping gaps are regex design bugs, not evidence of an ICU/Xcode difference. |

**Looks solid:** the revised rollback test at
`CadenceEditorSaveCommitSurfaceTests.swift:109` bounds the pre-fetch observation and still asserts
stored recovery/unrelated-edit loss. `MarkdownEditorImageRelayoutTests.swift:217` asserts containment
with tolerance. The time formatter tests explicitly specify hour-cycle locales. A textual search
for executable `Date.FormatStyle`/`.formatted(` assertions in `CadenceTests` found no direct cases;
the matches were comments. Many layout suites test Cadence's pure arithmetic, not SwiftUI's
rounding; do not call all of them framework pins.

**Suggested verification:** run these suites through `xcb.sh`, separately on each host under its
test-host lock, at one fixed commit. Capture the environment and assertion values, not just red/green.
No source-only method can honestly tell which unexecuted assertion *will* flip.

## R48: Checkable comment claims

| Claim | Evidence against current source | Class and narrow fix |
| --- | --- | --- |
| `CadenceTaskDateEditing.swift:15`: mutation support is pure, nothing reaches beyond SwiftData | `CadenceTaskMutationSupport.swift:804` schedules notification cancellation. `git show b2a0f53:Cadence/Shared/CadenceTaskMutationSupport.swift` already has that call when the header was introduced. | **MEASURED, born false in b2a0f53.** Limit the claim to date-edit primitives; preserve the reason notifications cannot be pulled into the headless target. |
| `CadenceTaskDateEditing.swift:17`: NotificationManager reads `UserDefaults.standard` | `NotificationManager.swift:83` reads `CadenceDefaults.store`; git history dates that change to `924fab8`. | **MEASURED, aged false.** Name the router, not a former direct store. |
| `CadenceRadiusControlSweepTests.swift:94`: typed radius constants are counted | G2's executed control misses `let cornerRadius: CGFloat = 10`. Same discrepancy in `b0b2eef`. | **MEASURED, born false.** Repair the detector and fixtures, not only the claim. |
| `.github/workflows/docs.yml:75`: exactly one workflow/check per push | A mixed change to `docs/TODO.md` and `Cadence/Models/AppTask.swift` satisfies both filters. Same filters and claim introduced by `64adece`. | **MEASURED source + REASONED event result, born false.** Say coverage overlaps or give the ledger one event owner. |
| `CadenceSaveCommitDisciplineTests.swift:2250`: renumber detector is sound | T-1308 already records a restore helper flagged as an uncommitted reorder. | **Already filed; extends T-1308 only.** No new ticket or independent full mutation claim here. |

The workflow conclusion uses GitHub's documented rules: `paths` needs one matching changed path;
`paths-ignore` skips only when all changed paths match. No live Actions execution was performed.
[GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).

**True with a changed/limited rationale:** snapshot-based edit undo is still correct even where
SwiftData now restores a retained object immediately: unrelated pending work is the decisive
objection (`CadencePendingChangePersistence.swift:94`). The explicit target membership claims for
DateFormatters and the exclusion of CadenceListDeleteHelpers were checked against
`project.pbxproj:650,707`; do not turn the shorthand "Shared is not compiled" into a claim that no
individual Shared file is listed. This is a targeted semantic-claim survey, not every comment.

## R49: Production schema failure is not type-isolated

**DOCUMENTED, not a live Cadence experiment:** Apple says an incompletely mirrored model can stop
`NSPersistentCloudKitContainer` synchronization. TN3164 shows a missing Production field causing
delegate initialization failure and subsequent store export requests to abort. It also identifies
an undeployed schema as a likely explanation when debug sync works but TestFlight sync does not.
Thus **"everything fails, so it cannot be SidebarLayoutPreference's schema" is an invalid diagnostic**.
[Apple TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer).

At the lower API layer, atomic `CKModifyRecordsOperation` changes fail together within one record
zone; record types are not the isolation boundary. This supports rejecting a per-type guarantee,
but does not establish SwiftData's exact batching/retry implementation.
[Apple isAtomic](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/isatomic).

**REASONED for Cadence:** `CadenceSchema.swift:27` includes the new entity in the same schema opened
by `PersistenceController.swift:198`. An undeployed type therefore has credible store-wide impact.
The exact error code, retry delay, partial exports, import progress and recovery timing on the
owner's three devices are **unmeasured**. Local fetch success proves none of them. A missing remote
type is not a thrown local fetch; zero local rows simply means no local rows.

**Release order:** initialize/verify all intended Development record types, review and deploy the
schema, verify Production types/fields, then distribute the build that depends on them. Deployment
copies schema, not Development user records, and Production schema evolution is additive.
[Apple deployment guide](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
Do not remove a previously shipped model from the runtime schema as an ad hoc feature flag.
Holding an *unreleased* model/build until schema deployment is reasonable; reverting the schema of
devices that may already store that model needs a separate migration review.

**Before interpreting the experiment:** record the deployed schema and signed build environment;
inspect system logs for the missing type/field and mirroring initialization/export failure; create
one ordinary task and change one preference in each direction. Do not erase local stores to make
the diagnostic simpler. No account, database or deployment was accessed by this audit.

**New working-tree caveat:** an uncommitted `LookPreference` model and schema entry appeared during
the audit. If shipped, include it in the deployment inventory too. `daf65e7` records T-1307's new
preference policy, but a decision commit is not proof that its implementation or schema is deployed.

## R50: Range-level machinery findings

**MEASURED scope:** `git rev-list --count 674181e^..e78be39` is **37 commits**, not roughly 24;
the aggregate diff touches **161 files**, 7,321 insertions and 1,055 deletions. The review focused
on the changed guard machinery, rollback contract and schema/release interaction. It is not an
exhaustive regression review of all 161 files.

### G3: Message-file ownership accepts a sibling with an overlapping id (P2, guard gap)

**MEASURED:** `scripts/agent-commit.sh:879` accepts any basename containing the id as a substring.
The probe executes that exact zsh comparison: **both `sync` and `async` accept `msg-async.txt`**.
Introduced in `9a9a4cf`. Ordinary agent names can overlap; no malicious agent is needed. This does
not prove an actual wrong-message commit happened in this range. Current selftest witnesses use
non-overlapping names, so proving the original collision is refused does not prove exclusive
ownership. **Suggested fix:** an unambiguous exact naming contract, such as `msg-<whole-id>.txt`
or an enforced unique per-agent directory, plus overlapping-id positive/negative fixtures.
Do not relax rejection of a genuinely shared message path.

### G4: An empty optional archive makes the history parser skip the log (P3, latent script bug)

**MEASURED:** `scripts/ledger-lag-check.sh:122` tolerates missing `TODO_DONE.md` by making an empty
file. Its awk reader at `:186` uses `FNR == 1 { part++ }`, which cannot advance over an empty file.
The log is then read as the archive. Executing the extracted **current awk program** with identical
closed-ticket/history fixtures and only the archive changed gives:

```text
nonempty archive: exit 0; 1 commit, 1 entry, 1 examined, 0 findings
empty archive:    exit 4; 0 commits, 1 entry, 0 examined, 0 findings
```

Born in `64adece`. Current HEAD has a nonempty archive, so this is **not causing a live CI failure**.
The floors fail closed, which is good, but incorrectly blame insufficient history. The selftest
does not cover the supported missing/empty-archive branch. **Suggested fix:** dispatch by `FILENAME`
against explicitly passed paths, not by the count of nonempty input files. Test both empty and
absent archives with known closed entries in TODO; retain all three vacuity floors.

### G5: The history-wide gate forbids legitimate reopening (policy decision, not a new bug)

**MEASURED:** with an existing code commit left untouched, changing its sole ticket from CLOSED
to genuinely reopened changes the fixture from exit 0 to exit 3. This is the stated CI rule, not
an accidental parser error. It conflicts with treating the commit helper's warning at
`scripts/agent-commit.sh:1837` ("legitimately still open ... nothing needs doing") as permission to
push. R50's original range also filed **T-1303** for duplicate-id closure semantics; do not re-file it.

**Suggested decision:** require distinct follow-up tickets for reopened work, or represent an
explicit reviewed exception tied to commit+ticket and a reason. Do not silence it with a random
closed ticket in the subject. Historical subjects cannot be repaired cheaply after publication;
"rename the commit" is not a general cure. Add integration fixtures for partial implementations,
follow-up tickets and reopened work after deciding the intended policy. Extends T-1298/T-1300.

G3-G5 controls, using no real repository writes or commits:

```sh
ruby docs/audits/2026-09-20/request-queue/guard-probes.rb "$PWD"
```

The duplicate-workflow claim is covered under R48. **Looks solid:** both ledger jobs fetch full
history; current HEAD passes the actual ledger gate; `xcb` resolves missing simulator names before
building and has executable positive/negative controls; mutation plans baseline each distinct
suite; the new core-note accessors use pending-insert undo. T-1305's torn-read problem is already
filed and has active uncommitted work, not an unreported defect to reopen here.

## Reproduce the candidate inventory

The TSV is generated, not manually adjudicated. To regenerate against a source root:

```sh
HOST=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host
swift -module-cache-path /tmp/cadence-rq-probe-cache \
  -I "$HOST" -L "$HOST" -Xlinker -rpath -Xlinker "$HOST" \
  docs/audits/2026-09-20/request-queue/source-candidates.swift "$PWD" \
  /tmp/cadence-source-candidates.tsv
```

Use `scripts/agent-scratch.sh new <unique-id>` for a stable current-HEAD source root, then release
it with the matching script. Do not reuse the audit's deleted temporary snapshot path. No claim
here depends on a successful app build, live CloudKit account or completed two-toolchain run.

### Closing verification

HEAD was still `231a7a8` at the closing check. `git diff --check` and
`scripts/agent-commit.sh check` both exited 0. Every R41-R50 section has exactly one new answer.
Further concurrent changes now include `Cadence/Models/AGENTS.md`,
`CadenceTests/CadenceGuardScriptSelftestTests.swift`, `CadenceTests/CadenceLookPreferenceTests.swift`,
`docs/TODO.md`, `docs/apple-release-readiness.md` and `scripts/ledger-lag-check.sh`.
The latter's diff addresses T-1303's duplicate-id case; it still has the empty-file `FNR` dispatch
at this check. These are not this audit's edits and are not certified or reverted here.
