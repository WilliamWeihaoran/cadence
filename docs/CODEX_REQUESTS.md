# Codex requests — open asks from the coordinator

**What this file is.** A queue of *read-only* work the coordinating agent wants done but should not
spend its own tokens on: reconnaissance, premise re-verification, sizing, and diagnosis. Codex reads
this, does the work, and writes its answer **back into this file** under the request it answered.

**Why it exists.** Measured 2026-09-03: the coordinator's own context is ~61% of session spend, and
the single most repeated expense is *reading source to find out whether a ticket is still true*.
Agents have corrected a ticket's premise roughly ten times in this run. Every one of those corrections
was a read that could have happened here instead, once, before a brief was written.

## Rules

- **Read-only.** Do not change product code, tests, or `docs/TODO.md`. If a request implies a fix,
  answer the question and say what the fix would be; do not make it.
- **Measured beats reasoned, and say which.** Every claim gets a `MEASURED` or `REASONED` tag and, if
  measured, the command or the file:line that measured it. A count with no command behind it is worth
  nothing here.
- **A disproved premise is the most valuable answer you can give.** If a request rests on something
  false, say so first and stop — do not answer the question it should have asked.
- **Do not trust the ticket text.** Most of these entries quote a ticket. The point of the request is
  usually that the quote may be stale.
- Answer under the request, prefixed `ANSWER <date>:`. Leave the request text intact.

---

## R1 — Diagnose T-739: literal arithmetic disagrees with variable arithmetic in `CadenceTests`

**Priority: highest.** This one is small, weird, and undermines an assertion style used across the
suite.

`#expect(x == 0.5 * 1.6)` **fails** while `#expect(x == retired * 1.6)` **passes**, for the same
numbers, in `CadenceTests`. A standalone `swiftc -Onone` binary prints **one identical bit pattern**
for every spelling. Found while landing T-496; deliberately not guessed at.

Answer: what is actually different — constant folding at a wider precision, `CGFloat`/`Double`
bridging, the `#expect` macro's expansion changing the inferred type, or something else? Then: **how
many assertions in `CadenceTests` compare against an inline `literal * literal`?** That set is the
blast radius, and nobody has counted it.

ANSWER 2026-09-03:

```
Tree read: 58a25fe
Dirty files: 1
```

**Verdict: the macro expansion changes type inference. It is not a precision or constant-folding
difference.** `#expect(lhs == rhs)` expands through `Testing.__checkBinaryOperation<T, U>`, whose
left and right types are independent. With a `CGFloat` left side and the unannotated expression
`0.5 * 1.6` on the right, overload inference chooses `U == AnyHashable`; the product is a boxed
`Double`, and the `CGFloat` is boxed for the equality. `AnyHashable(CGFloat(0.8))` and
`AnyHashable(Double(0.8))` compare unequal even though both underlying IEEE-754 values have the
same `3fe999999999999a` bit pattern. Binding either operand as `CGFloat` keeps `U == CGFloat` and
passes.

- **MEASURED:** `-dump-macro-expansions` produced
  `Testing.__checkBinaryOperation(adopted, { $0 == $1() }, 0.5 * 1.6, ...)`.
- **MEASURED:** the installed Testing interface declares the relevant helper at
  `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/Testing.framework/Versions/A/Modules/Testing.swiftmodule/arm64-apple-macos.swiftinterface:606`
  as `__checkBinaryOperation<T, U>` with no `T == U` constraint.
- **MEASURED:** a probe with that exact generic signature inferred `T == CGFloat, U == AnyHashable`
  and returned `false` for `0.5 * 1.6`; the bound spelling inferred `U == CGFloat` and returned
  `true`. Directly invoking Testing's helper returned `failure(ExpectationFailedError(...))` for
  the literal spelling and `success()` for the bound spelling.
- **MEASURED:** `0.4 * 2` and bare `0.8` infer `U == CGFloat`, explaining why both passed in the
  original test. The integer literal can take the contextual `CGFloat` type; two floating literals
  instead form a default `Double` expression before the heterogeneous equality is settled.

30-second mechanism probe (output includes `AnyHashable ... false` and `CGFloat ... true`):

```sh
swift -module-cache-path /tmp/cadence-t739-cache -e 'import Foundation; func check<T,U>(_ lhs:T,_ op:(T,()->U)->Bool,_ rhs:@autoclosure()->U){let r=rhs();print(T.self,U.self,op(lhs,{r}))};let x:CGFloat=0.08*10;let retired:CGFloat=0.5;check(x,{$0==$1()},0.5*1.6);check(x,{$0==$1()},retired*1.6)'
```

**Blast radius:**

- **MEASURED, exact dangerous form: 0 live assertions.** SwiftSyntax parsing found no executable
  `#expect` condition containing floating-literal `*` floating-literal. The sole textual hit is the
  explanatory doc comment at `CadenceTests/CadenceSharedBoardChromeTests.swift:1427`; the live test
  at `:1446` uses the typed `retiredWeekday` spelling.
- **MEASURED, broad syntactic population: 98 assertions** contain at least one numeric
  literal-times-literal expression, comprising 116 integer/integer products and two mixed
  integer/floating products. The mixed products are
  `CadenceTests/iPadTodayPaneWidthTests.swift:97` and `:105`; neither has the failing shape because
  the integer operand accepts the surrounding `CGFloat` context.
- **REASONED:** the 116 integer products do not share T-739's risk. Integer arithmetic has no
  `CGFloat`/`Double` split, and the measured generic probe keeps the expected type. They are useful
  as the broad count requested, not candidates for a mechanical rewrite.

Cheapest disposition: narrow T-739 to a diagnosed Swift Testing type-inference trap and close it as
having no current live population. Keep the bound `CGFloat` regression witness. A future guard, if
wanted, should reject only float-literal `*` float-literal inside `#expect`, not all 98 assertions.

## R2 — Re-verify the premises of the tickets scheduled for batches M, N and O

Ten tickets have had a premise corrected by the agent working them, mid-task, at full Opus cost. These
are the next ones up. For each, say whether the quoted claim still holds at current HEAD, with the
command that shows it.

- **T-689** — "the Goals screen says *No goals yet* when every goal is completed". Still true after
  `c1b0c9b`?
- **T-690** — "a paused or cancelled project reaches **no** Settings lifecycle section on either
  platform". Count the sections; name the file:line for each platform.
- **T-691** — "`missingLinks` passes a raw list name, so an untitled list's row is a blank line".
  Still true after T-624's evidence gate landed (`892b866`)?
- **T-693** — "`CalendarEventPresentationSupport.swift:73` and `:198` display `?? ""` where iOS shows a
  fallback". Verify both line numbers and that the three other `?? ""` sites in that file really are
  search haystacks.
- **T-657** — "the detector cannot see a report handed *sideways* one frame down". How many live sites
  does that spelling actually have? T-648's three macOS copies were the only known ones and they are
  now fixed, so this may have **no population left** — which changes whether it is worth building.
- **T-664** — "the vocabulary has no spelling for *the surface filled itself in*; measured, exactly one
  live site". Is it still one?
- **T-672 / T-673 / T-674** — the icon-only-button ledger says 31 sites in 24 files, split 10/8/10 plus
  3 iOS. That was measured before batches H through L. Re-count all three.

ANSWER 2026-09-03:

```
Tree read: 58a25fe
Dirty files: 2
```

The dirty files were `Cadence.xcodeproj/project.pbxproj` (pre-existing) and this answer file. No
product Swift file was dirty, so the source readings below describe HEAD.

### T-689 — narrowed: still live on iOS, disproved on macOS

- **MEASURED:** macOS no longer says “No goals yet” in the completed-only/default-filter case.
  `GoalsView.statusFilter` defaults to `.active` at
  `Cadence/macOS/Views/GoalsView.swift:21`; `GoalStatusFilter.narrowsResults` is true for every value
  except `.all` at `Cadence/macOS/Views/GoalsSupportViews.swift:31-36`; and the empty branch passes
  that result to `goalsTitle` at `GoalsView.swift:271-289`. It therefore says “No matching goals”.
  The Roadmap twin does the same at `Cadence/macOS/Views/GoalTimelineView.swift:116-121`.
- **MEASURED:** iOS still filters to `activeGoals` at
  `Cadence/iOS/iOSFeatureViews.swift:22-24`, but its shared empty state unconditionally passes
  `isNarrowed: false` at `:210-214`. With only completed goals it still says “No goals yet”.
- **Disposition:** keep T-689, but scope it to iOS. `c1b0c9b` fixed selection consistency, not the
  remaining copy; the ticket's “both surfaces” premise is stale.

Confirm:

```sh
rg -n 'statusFilter.*\.active|narrowsResults|goalsTitle\(' Cadence/macOS/Views/GoalsView.swift Cadence/macOS/Views/GoalTimelineView.swift Cadence/macOS/Views/GoalsSupportViews.swift Cadence/iOS/iOSFeatureViews.swift
```

### T-690 — still live on both platforms

- **MEASURED:** each Settings caller still passes exactly four arrays: completed areas, archived
  areas, completed projects and archived projects. macOS is
  `Cadence/macOS/Views/SettingsView.swift:193-202`; iOS is
  `Cadence/iOS/iOSSettingsView.swift:285-294`.
- **MEASURED:** both lifecycle sections declare and draw exactly those four groups at
  `Cadence/macOS/Views/SettingsListManagementSections.swift:622-664` and
  `Cadence/iOS/iOSSettingsTemplateAndListSections.swift:252-291`.
- **MEASURED:** `Project.isDone`, `.isArchived`, and `.isActive` are exact single-status checks at
  `Cadence/Models/Project.swift:60-62`. `.paused` and `.cancelled` therefore enter none of the four
  arrays. The inline row labels also still collapse every admitted non-done project to “Archived”
  at the macOS file `:693-710` and iOS file `:319-334`.
- **Disposition:** premise unchanged; two missing project lifecycle states on each platform.

Confirm:

```sh
rg -n 'completed(Areas|Projects):|archived(Areas|Projects):|filter\(\\\.(isDone|isArchived)\)|statusLabel: project.isDone' Cadence/macOS/Views/SettingsView.swift Cadence/macOS/Views/SettingsListManagementSections.swift Cadence/iOS/iOSSettingsView.swift Cadence/iOS/iOSSettingsTemplateAndListSections.swift
```

### T-691 — still live, with a narrower reach after T-624

- **MEASURED:** `missingLinks` still hands raw `area.name` / `project.name` to `missingLink` at
  `Cadence/Shared/CadenceCalendarLinkHealth.swift:134-155`, and that helper stores it unchanged at
  `:175-197`. The dormant sibling still uses `CadenceTitleNormalization.display` at `:236-262`.
- **MEASURED:** T-624 added the `observedCalendarIDs` evidence gate at `:185-187`; it did not add a
  title fallback.
- **Reachable today, but not merely from receiving another device's unknown ID:** an untitled active
  list must point to an identifier this device previously observed and which is now absent. That
  ordinary local deletion/recreation path still yields the blank row.
- **Disposition:** keep T-691 and add the evidence-gated reproduction; its title premise is unchanged.

Confirm:

```sh
rg -n 'name: (area|project)\.name|name: CadenceTitleNormalization\.display|observedCalendarIDs\.contains' Cadence/Shared/CadenceCalendarLinkHealth.swift
```

### T-693 — two display sites still live; the claimed three haystacks no longer exist

- **MEASURED:** the exact display assignments remain at
  `Cadence/macOS/Views/CalendarEventPresentationSupport.swift:73` and `:198`, both
  `event.calendar?.title ?? ""`.
- **MEASURED:** the whole file now contains exactly those two `?? ""` spellings. There are no three
  additional search-haystack sites to classify at current HEAD; that part of the ticket is stale.
- **MEASURED:** iOS still uses `CadenceAppleCalendarNaming.unnamedCalendarTitle` at
  `Cadence/iOS/iOSBoardCards.swift:77` and `Cadence/iOS/iOSSearchView.swift:640`.
- **Disposition:** keep the two-site bug and delete the “three other sites” rider from the brief.

Confirm:

```sh
rg -n '\?\? ""|unnamedCalendarTitle' Cadence/macOS/Views/CalendarEventPresentationSupport.swift Cadence/iOS/iOSBoardCards.swift Cadence/iOS/iOSSearchView.swift
```

### T-657 — detector gap remains, current production population is zero

- **MEASURED:** the six former macOS sites now call `CadenceNoteTaskEmbedEditing`, branch on its
  Boolean answer, and call `refreshEmbeddedTask` only after success:
  `Cadence/macOS/Views/NotePanel.swift:316-335`,
  `Cadence/macOS/Views/ListNotesSupportViews.swift:372-391`, and
  `Cadence/macOS/Views/NoteEditorPane.swift:557-576`.
- **MEASURED:** `CadenceTests/CadenceNoteTaskEmbedCommitTests.swift:191-240` names all six plus the
  iOS return-shaped site and requires no `try?` in any body. No other app call combines a swallowed
  save with `refreshEmbeddedTask` one frame down.
- **Disposition:** zero live sites. T-657 is now only unpinned detector capability, not a production
  fix. Its value depends entirely on expected recurrence versus false-positive cost.

Confirm:

```sh
rg -n 'func (toggleEmbeddedSubtask|renameEmbeddedTask|refreshEmbeddedTask)|refreshEmbeddedTask\(' Cadence/macOS/Views/NotePanel.swift Cadence/macOS/Views/ListNotesSupportViews.swift Cadence/macOS/Views/NoteEditorPane.swift
```

### T-664 — no, it is no longer one; current population is zero

- **MEASURED:** the sole measured site was `TagPickerPopoverViews.restore`. It now commits through
  `CadencePendingChangePersistence.commitEdit`, returns on failure, and only then appends the tag and
  clears the query at `Cadence/macOS/Views/TagPickerPopoverViews.swift:235-254`.
- **MEASURED:** the ticket itself records the pre-fix count as one and post-fix count as zero at
  `docs/TODO.md:1395-1400`; the present source matches the latter.
- **Disposition:** like T-657, this is guard design with no live backlog. Do not schedule it as a
  user-facing bug, and measure false positives before widening the vocabulary.

Confirm:

```sh
rg -n 'private func restore|commitEdit|selectedTags\.append|query = ""|try\?' Cadence/macOS/Views/TagPickerPopoverViews.swift
```

### T-672 / T-673 / T-674 — counts unchanged

- **MEASURED from the exact current source ledger:** T-672 remains **10 sites in 10 files**; T-673
  remains **8 sites in 5 files**; T-674 remains **10 sites in 9 files**. The three T-611 iOS sites
  remain in two files. Total: **31 sites in 24 files**.
- The per-file ledger is `CadenceTests/CadenceIOSControlAccessibilityTests.swift:72-97`; its exact
  source recount and headline assertions are at `:99-159`. The category comments beside every entry
  sum to 10/8/10, including the multi-site files rather than counting paths as sites.
- **Disposition:** all three ticket premises and the 31/24 umbrella count remain current. No batch
  H-L source landing removed an entry without also updating the exact ledger.

Confirm the category ledger and its independent totals:

```sh
sed -n '72,159p' CadenceTests/CadenceIOSControlAccessibilityTests.swift
```

## R3 — Size T-616's siblings before anyone sweeps them

T-754 says **41 more sites** spell `Theme.radiusControl` (10) as a bare `cornerRadius: 10`. Verify the
count, and answer the question the T-616 decision turned on: are those 41 **one origin copied**, or
independent choices? The tell is scatter — 55 sites at exactly 7 with no 6s or 8s nearby was the
evidence that made a token descriptive rather than a new design decision. Does the same hold at 10?

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 1
```

**SPLIT T-754 BEFORE IMPLEMENTATION — the count is exactly 41, but the one-origin premise is false.**
These are clustered independent choices, not T-616's copied value, so an app-wide substitution to
the semantically named `radiusControl` would silently decide that media, columns and content cards
are controls.

- **MEASURED:** exactly **41** bare `cornerRadius: 10` arguments in **16 files**, plus the separately
  named `kanbanColumnCornerRadius: CGFloat = 10` at
  `Cadence/macOS/Views/KanbanBoardSupport.swift:18-22`.
- **MEASURED:** blame attributes the 41 current lines to **18 commits**, versus one copied origin.
- **MEASURED:** the 41 spellings separate into visibly different source roles: 7 icon wells; 14
  control/action/hover shapes; 13 form or content-card shapes; 4 Settings drop-target shapes; 2
  markdown-image paths; and 1 timeline block-style metric. The named kanban-column radius is a
  seventh role and has five readers across three files.
- **MEASURED:** nearby values are real scatter, not absence: the tree contains 87 bare 8s, 21 bare
  9s, 41 bare 10s and 26 bare 12s. The strongest same-file counterexamples are
  `Cadence/macOS/Views/HabitsFormSupportViews.swift` (10 bare 8s beside 8 bare 10s),
  `Cadence/macOS/Views/GoalTimelineView.swift` (two 9s beside six 10s),
  `Cadence/macOS/Views/SettingsSupportViews.swift` (five 8s beside five 10s), and
  `Cadence/iOS/iOSMarkdownImageLayoutInfo.swift:56-96` (8 and 10 inside one renderer).
- **MEASURED:** `Theme.radiusControl` documents its role as “small in-card controls: icon badges,
  compact buttons, inline pickers” at `Cadence/Shared/Theme.swift:466-475`. The image clips at
  `Cadence/iOS/iOSMarkdownImageLayoutInfo.swift:56,96`, the timeline style at
  `Cadence/macOS/Views/TimelineMetrics.swift:280`, the form cards at
  `Cadence/macOS/Views/HabitsFormSupportViews.swift:264-380`, and the containerless kanban-column
  highlight do not all satisfy that contract.

**Ticket edit:** retain a mechanical sub-ticket only for the icon-well and genuine control clusters.
Move cards, image clipping, timeline geometry, drop targets and `kanbanColumnCornerRadius` into
role-specific decisions; do not invent a neutral 10pt token merely to make the grep empty.

Confirm count and scatter:

```sh
rg -o -P --glob '*.swift' '\bcornerRadius:\s*10\b' Cadence | wc -l
rg --no-filename -o -P --glob '*.swift' '\bcornerRadius:\s*\K\d+(?:\.\d+)?' Cadence | sort -n | uniq -c
rg -n 'kanbanColumnCornerRadius' Cadence
```

**Not checked:** no screenshots or rendered-radius comparisons were made, so this answer classifies
source roles and provenance, not which of the independent choices looks best. No build or tests ran.

## R4 — Triage the ~20 unscheduled tickets

These are open and deliberately not in any batch, most because they need the user or look blocked:
T-16, T-17, T-18, T-55, T-115, T-122, T-168, T-274, T-447, T-481, T-491, T-511, T-531, T-551, T-554,
T-562, T-584, T-624, T-626, T-661.

For each: is it **still live**, **already overtaken by work that landed**, or **genuinely blocked and
on what**? Several were narrowed weeks ago and the code has moved a lot since. An entry that is
already dead is worth more to find than a new finding.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 2
```

**CLOSE 5, MERGE 2, KEEP/NARROW 13.** Four entries describe work already resolved, T-531's
permission gate has opened, and T-551/T-661 are not independent work. The remaining tickets are
live decisions or have a concrete external prerequisite.

| Ticket | Disposition | Current answer |
|---|---|---|
| T-16 | **KEEP — BLOCKED** | **INFERRED:** the app icon and sidebar mark still use the current `AppIcon`, but “redesign” has no acceptance criteria. Blocked on a visual brief/direction and user approval, not code. |
| T-17 | **KEEP — BLOCKED** | **MEASURED:** every target already says `TARGETED_DEVICE_FAMILY = "1,2"`; any iPhone/iPad can install. Blocked on the exact device/OS widths the user promised to name; the work is layout verification, not a project-setting change. |
| T-18 | **KEEP — LIVE** | **MEASURED:** zero `.strings`, `.xcstrings`, `.lproj`, `NSLocalizedString`, `String(localized:)`, or `LocalizedStringKey` remain the current population. The two date defects were overtaken by `c09f67d`, but Chinese localisation itself has not started and is technically unblocked. |
| T-55 | **NARROW — BLOCKED** | **MEASURED:** `docs/device-checks.md` now has only two physical-phone predicates: Notes keyboard dismissal and double-tap behavior. Simulator-capable items were overtaken. Blocked on those four phone gestures, not implementation. |
| T-115 | **KEEP — BLOCKED** | **MEASURED:** installed Xcode is still **26.6 (17F113)**, exactly the crashing toolchain already measured. Recheck only after Xcode changes. |
| T-122 | **KEEP — BLOCKED** | **MEASURED/INFERRED:** the app remains Swift 5 while MCP is Swift 6. The key-path error is fixed, but the measured 10 app warnings and T-115's iOS compiler crash still prevent a zero-warning whole-app flip; the user also explicitly decided not to flip yet. |
| T-168 | **SPLIT — BLOCKED** | **MEASURED:** there is still no focus widget or widget-readable live timer; iOS owns `CadenceFocusTimerState` in `iOSFocusView`, while `FocusManager` remains macOS-only. The view already has a regular-width horizontal layout, so narrow the second half to **iPhone landscape behavior**. Widget design/state persistence and the desired phone-landscape chrome both need product decisions. |
| T-274 | **KEEP — BLOCKED** | **MEASURED:** production only decodes an archive; no path writes it into SwiftData, and shipped copy still says Cadence cannot import it. Blocked on sync-store policy, identity mode, referential-integrity behavior, and legacy-note migration semantics. |
| T-447 | **CLOSE — OVERTAKEN** | **MEASURED:** the commit notice was observed in the intended header; all three iPad sheets presented compact, so the alleged regular rail did not exist to disagree with its header. Any question about making the regular presentation reachable belongs to T-731. |
| T-481 | **KEEP — DECISION** | **MEASURED:** current `scripts/test-suite-index.sh` output is **38 multi-suite files / 118 suites**, not TODO's 32 or `DECISIONS_PENDING`'s 33; 239 files already have one suite. The ratchet remains valid but needs a user policy choice and a generated, stale-failing allowlist. |
| T-491 | **KEEP — DECISION** | **MEASURED:** this can happen today. Four iPad page-level modifiers install the capture host inside `detail()`, and `iPadMacStyleRootShell` clips that detail at `iOSRootSidebar.swift:81-84`; the palette scrim's `ignoresSafeArea` cannot dim the sibling sidebar. Decide whether page-scoped dimming is intentional before moving the host. |
| T-511 | **KEEP — BLOCKED** | **MEASURED:** no landed evidence settles whether a real onscreen macOS editor accepts plain-text drag. Blocked on one manual drag; if it fails, register text types deliberately. |
| T-531 | **CLOSE — OVERTAKEN** | **MEASURED:** the one-time automation permission was granted on 2026-08-31 and UI tests now launch. The current residual is T-710's seeded-row timing, not authorisation. |
| T-551 | **MERGE INTO T-511** | **MEASURED:** this is evidence qualification for T-511, not separate product work: offscreen AppKit did not reproduce the claimed re-registration behavior. Preserve the caveat in T-511 and close this standalone entry. |
| T-554 | **CLOSE — OVERTAKEN** | **MEASURED:** the ticket already records the abstraction as refused and the derived sweeps as shipped. It is a closed investigation, not unscheduled work. |
| T-562 | **CLOSE — OVERTAKEN** | **MEASURED:** the entry itself is marked resolved; the launch hypothesis was disproved and the process rule shipped. T-563/T-710 own the actual residuals. |
| T-584 | **KEEP — BLOCKED** | **MEASURED:** the original “never a note” defect is disproved, but the full-screen editor still blanks the iPad. Blocked on the already-costed user choice; option 1 remains the ticket's recommendation, followed by the requested 1366/836 captures. |
| T-624 | **NARROW — BLOCKED** | **MEASURED:** `892b866` removed repair ping-pong with device-local observations. The remaining portability issue cannot falsely repair today, but a link still may not function on a peer. Blocked on a two-device identifier measurement and T-390's companion-metadata/schema decision. |
| T-626 | **KEEP — BLOCKED** | **MEASURED:** iOS still has neither `UIApplicationDelegateAdaptor` registration nor `UIBackgroundModes`; one shared plist means a casual fix changes the shipping macOS bundle. Impact on today's distributed product is zero. Blocked on iOS distribution plus a platform-specific plist/registration design. |
| T-661 | **MERGE INTO T-274** | **MEASURED:** exports still copy both `linkedCalendarID` fields, but Cadence has no importer, so the claimed in-app cross-device restore failure cannot happen today. Make “drop the field vs document it as non-portable” part of T-274's archive-contract decision; do not carry a second implementation ticket. |

Thirty-second confirmations:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Xcode.app/Contents/Info.plist
rg -n 'TARGETED_DEVICE_FAMILY|SWIFT_VERSION' Cadence.xcodeproj/project.pbxproj
rg -n '\.iOSCaptureHost\(|\.iOSFloatingCreateTaskButton\(' Cadence/iOS
rg -n 'UIApplicationDelegateAdaptor|registerForRemoteNotifications|UIBackgroundModes' Cadence CadenceTests
rg -n 'linkedCalendarID = model\.linkedCalendarID|static func decode' Cadence/Services/CadenceDataExportService.swift
./scripts/test-suite-index.sh
```

**Not checked:** no build, tests, app launch, simulator run, physical-device gesture, EventKit access,
or Swift-6 repro ran. T-115/T-122 rely on the unchanged-toolchain measurements already recorded in
the tickets; T-491 is source-confirmed but was not visually judged.

## R5 — Audit the last three batches against their own commit messages

The standing highest-value Codex task from `docs/CODEX_BRIEF.md` §1, pointed at what just landed:
batches **J, K and L** (`db1e9c6` through `67abf37`). Do the commits do what their messages claim?
Two specific things to check, because both are load-bearing and neither has an outside reader:

- **`db1e9c6` (T-621)** claims the focus-ledger reconcile is "a pure function of the counter and the
  rows" and therefore idempotent with no run-once flag. Is it? And does
  `max(counter, min(previousMinutes) + Σminutes)` really only ever raise?
- **`fba681a` (T-713)** claims intermediate names never touch a card, and that T-358's frozen snapshot
  still holds. Both are assertions about a rename's commit point; verify them against the code rather
  than the tests.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 7
```

**NARROW `db1e9c6`'s explanation; KEEP `fba681a`'s claim.** The ledger update is genuinely
idempotent and raise-only for a fixed row set, and the rename wiring does move cards only at a commit
point. The ledger comment overclaims that `min(previousMinutes)` is *exactly* the inherited legacy
total across devices.

### `db1e9c6` / T-621

- **MEASURED — PASS:** for fixed rows, let `L = min(previousMinutes) + sum(max(0, minutes))` and
  `F(counter) = max(counter, L)`. An exhaustive Swift probe over small counters/rows produced **0
  monotonicity or second-application failures**. Algebraically, `F(F(c)) = F(c)`.
- **MEASURED — PASS:** all three store-wide writes at `Cadence/Models/AppTask.swift:758-772` are
  guarded by `total > current`; banking's local repair at `:788-791` also uses `max(counter, total)`.
  The implementation cannot lower a counter. `reconciledTotal` itself depends only on rows; the
  enclosing `reconcile(in:)` fetches and mutates, so call the **target calculation** pure rather than
  the method.
- **INFERRED — CLAIM TOO STRONG, LIVE AT ROLLOUT:** “the minimum is exactly the legacy total” only
  holds if every device creates its first ledger row from the same inherited scalar. An offline Mac
  at 20 and phone at 10 can create `(previous: 20, minutes: 5)` and `(previous: 10, minutes: 7)`.
  The formula yields 22; if the 20 was the authoritative inherited total, the intended result is 32,
  and `max(25, 22)` preserves 25 rather than adding the phone's 7. The ledger never loses the visible
  counter, but it can under-reconstruct cross-device minutes during a divergent upgrade window.

**Disposition:** keep the implementation; narrow the comments/docs to state the equal-inherited-
baseline assumption. File a separate migration/rollout ticket only if exact recovery across that
window is required; neither rows nor the old scalar contain enough information to infer it later.

### `fba681a` / T-713

- **MEASURED — PASS:** `onNameChanged` calls only `applySectionEdits`
  (`KanbanSectionColumnView.swift:401-409`), and that function changes the section-config blob but
  never an `AppTask.sectionName` (`:446-467`). Intermediate names therefore do not touch cards.
- **MEASURED — PASS:** the rename card move is called from `commitSectionEdits`, after apply and
  before flush (`:513-521`). `moveCardsToStoredName` reads the destination back from the current
  container by UUID and refuses unless it matches the typed name
  (`KanbanSectionStateSupport.swift:80-95`).
- **MEASURED — PASS:** T-358's snapshot remains frozen. `editorBase` has exactly one assignment,
  when the popover opens (`KanbanSectionColumnView.swift:349`), and is never advanced. The mutable
  card location is separately tracked by `editorFiledCardName` (`:350,490`), so a second rename can
  move from the first committed name without turning the merge base into a live snapshot.

Confirming commands:

```sh
rg -n 'reconciledTotal|total > entry\.subject|max\(counter, total\)' Cadence/Models/AppTask.swift
rg -n 'editorBase\s*=|editorFiledCardName\s*=|onNameChanged|applySectionEdits|moveCardsToStoredName' Cadence/macOS/Views/KanbanSectionColumnView.swift Cadence/macOS/Views/KanbanSectionStateSupport.swift
swift -module-cache-path /tmp/cadence-r5-swift-cache -e 'let c=25; let rows=[(20,5),(10,7)]; let t=rows.map{$0.0}.min()!+rows.reduce(0){$0+max(0,$1.1)}; print(max(c,t), t)'
```

**Not checked:** no build or tests ran, and no real two-device CloudKit upgrade was driven. The
T-621 divergent-baseline case is an executable arithmetic counterexample plus an inferred reachable
sync history; T-713 is source-measured wiring, not UI observation.

## R6 — Standing: what should be here that is not?

If you notice a class of question this coordinator keeps paying to answer with its own reads, add a
request for it. The three that have recurred so far are *"is this ticket's count still right"*,
*"how big is this change really"*, and *"is this instrument measuring what it claims"*.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 13
```

**ADD R12 AND R13.** The three named questions are now covered by R4, R8, and R9. Two different
reads still recur without a standing owner: a landed batch invalidating another ticket's premise,
and correct production wiring whose removal leaves a feature inert while its helper tests stay green.

- **MEASURED:** R2/R7 found T-657's whole population had disappeared under T-648; R4 found four
  more open tickets already overtaken. R11 audits what a batch claims, but not the open tickets its
  touched symbols silently invalidate. R12 makes that a cheap changed-path/index lookup after each
  landing rather than a full rediscovery during briefing.
- **MEASURED FROM THE COORDINATOR'S FEEDBACK:** wiring and implementation are separate claims; a
  feature can be implemented correctly while deleting two registration/invocation lines makes it
  inert with every helper test passing. R13 asks only for that missing integration assertion and
  explicitly does not label correct code a live bug.

**Not checked:** R12 and R13 are request definitions, not completed audits. No code, build, or tests
were run for this answer.

---

# How to write the answer — feedback on R1 and R2, 2026-09-03

**These were good and the format is close to right.** Three things to keep, three to change. The
changes are all about the coordinator having to *read* the answer: reading R1 and R2 cost about 1.5k
tokens against the 136k–250k an agent spends discovering the same thing, and that ratio is the whole
argument for this file. It degrades if answers get long.

## Keep

- **The `Tree read: <sha>` / `Dirty files: N` header.** It made R2 trustworthy — knowing no product
  file was dirty is what let the readings be taken as describing HEAD.
- **`MEASURED` / `REASONED` on every claim, with the command or `file:line`.** R1's generic probe and
  R2's `sed`-able line numbers were both re-run here and both reproduced exactly.
- **A copy-pasteable confirm command per finding.** The 30-second probe in R1 settled it in one call.

## Change

1. **Lead with the verdict in one sentence, before any evidence.** R1's answer is excellent and the
   headline — *"macOS was already fixed; only iOS is live"* — is 60 lines in. Put the disposition
   first, then the evidence under it. A reader who trusts the tag does not need the derivation.
2. **State the disposition as an imperative, not a suggestion.** "Cheapest disposition: narrow T-739
   and close it" is right; make that the standard shape — `KEEP`, `NARROW TO <scope>`, `CLOSE — <why>`,
   or `SPLIT INTO <n>`. That is what gets transcribed into the ticket, so writing it as a ticket edit
   saves a translation step.
3. **Do not restate the request.** The question is directly above the answer. R2 re-quoted several
   ticket claims before answering them; the coordinator already has that text.

## Two things worth adding

4. **Say what you did *not* check.** R2 answered eight tickets; if any reading was partial — one
   platform, one call site, a grep rather than a parse — name it. An unmarked gap reads as coverage,
   and this project has been bitten by that exact shape more than once.
5. **If a request rests on something false, answer that and stop.** Already in the rules, and R2
   half-did it for T-689. Make it explicit: a disproved premise is a complete answer, and the
   remaining sub-questions do not need answering.

## One thing to avoid

**Do not re-derive what a previous answer established.** These accumulate; if R7 needs R1's finding,
cite `R1` rather than re-measuring. The coordinator will fold answers into tickets and delete the
request, so cite the ticket once that has happened.


---

## R7 — Does T-657 still have a population? **Answer this before anything is built for it.**

T-657 says the save-commit detector cannot see a success report handed **sideways** one frame down —
a function that mutates, swallows, and hands fresh render info to a caller that draws it. Its only
known instances were three macOS copies of `toggleEmbeddedSubtask`/`renameEmbeddedTask` in `NotePanel`,
`ListNotesSupportViews` and `NoteEditorPane`. **Those were fixed in `ab9e513` (T-648).**

So: sweep for the shape now. If the live population is **zero**, T-657 should be closed rather than
built, because a widening with no offender cannot earn its false-positive budget — and the detector
has already been widened four times this run, each time paid for by real sites it found.

Report the count and name every site. If it is zero, say so plainly; that is the valuable answer.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 7
```

**CLOSE T-657 — the live production population is zero.** R2 already measured and named the full
former population, so this answer does not spend another sweep re-deriving it.

- **MEASURED IN R2:** all six former macOS functions in `NotePanel`, `ListNotesSupportViews`, and
  `NoteEditorPane` now route through `CadenceNoteTaskEmbedEditing`, branch on its Boolean result, and
  refresh only after success. The iOS return-shaped sibling is pinned with them.
- **MEASURED IN R2:** no other app call combines a swallowed save with a sideways
  `refreshEmbeddedTask` report one frame down.

Confirm the already-recorded population:

```sh
rg -n 'func (toggleEmbeddedSubtask|renameEmbeddedTask|refreshEmbeddedTask)|refreshEmbeddedTask\(' Cadence/macOS/Views/NotePanel.swift Cadence/macOS/Views/ListNotesSupportViews.swift Cadence/macOS/Views/NoteEditorPane.swift
```

**Not checked:** no new detector implementation, mutation, build, or tests. This disposition relies
on R2's measured full-population sweep, as the coordinator's “do not re-derive” rule requests.

## R8 — Which of the four detectors is measuring something that no longer exists?

Four widenings landed this run: T-627 (four blind spots), T-636(b) (the Optional spelling), T-555
(`static func` constants), T-565 (comments naming absent symbols). Each was justified by a measured
offender population **at the time**.

For each, report the population **now**, and whether its ledger is still exact in both directions —
no offender unlisted, no listed name stale. A ledger that has gone stale is worse than no ledger: it
reads as coverage. This is the class that produced the best findings of the run, so it is also the
class most worth keeping honest.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 13
```

**KEEP all four detectors; none has a stale listed entry.** Current deferred populations are
T-627 **19**, T-636(b) **0**, T-555 **4**, and T-565 **39**. Only T-636(b) has finished paying down
its measured population; it should remain as vocabulary inside the broader save-commit detector,
not as its own ticket.

| Widening | Current population | Ledger verdict |
|---|---:|---|
| T-627, four save-commit blind spots | **19 declarations** | **MEASURED:** 9 existence + 2 direct-report + 7 commit-reach + 1 indirect-report exemptions. All 19 named declarations still exist. The ledger is exact by construction in both directions: the four full sweeps fail on an unlisted offender, and `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` recomputes each listed file and requires exact function-name equality. **14 are actionable debt**; the intentional five are three raw `TagSupport` helpers whose production callers commit, UI-test seeding with no user, and the named `CadenceWriteService.resolvedTags` false positive. |
| T-636(b), Optional success answer | **0 declarations** | **MEASURED/REUSED:** its two original direct hits, `iOSMarkdownEditingSurface.toggleEmbeddedSubtask` and `MarkdownEditorView.createInlineTag`, now commit and return `nil` on refusal; their exemption entries are gone. R2 separately measured the adjacent sideways population at zero. No standalone ledger remains, correctly. |
| T-555, `static func` string constants | **4 literal/path sites in 3 files** | **MEASURED:** all four ledger pairs still occur: two goal literals in `GoalPickerViews`, and `No lists yet` in `iOSRootSidebar` plus `iOSGoalAttachListsSheet`. The test compares computed and ledgered `CadenceLiteralSite` sets in both directions at `CadenceSharedConstantReuseSweepTests.swift:1013-1050`. T-698/T-699 remain open. |
| T-565, comments naming absent symbols | **39 claims** | **MEASURED:** 30 deliberate tombstones + 9 present-tense stale claims owned by T-716. Every one of the 39 backticked spans still appears in its named file. The sweep compares the computed sorted set to the combined ledger in both directions at `CadenceCommentSymbolClaimTests.swift:534-573`. |

**Can these happen today?** T-627's 14 actionable entries and T-555's four copy sites are current code
debt; T-565's nine stale claims currently misdirect readers, while its 30 tombstones are deliberate.
T-636(b) has no current offender, so there is no production fix to schedule for it.

Thirty-second confirmations:

```sh
sed -n '1125,1405p;1885,1908p' CadenceTests/CadenceSaveCommitDisciplineTests.swift
sed -n '120,180p;1013,1055p' CadenceTests/CadenceSharedConstantReuseSweepTests.swift
sed -n '442,575p' CadenceTests/CadenceCommentSymbolClaimTests.swift
rg -n 'No goals yet|No matching goals|No lists yet' Cadence/macOS/Views/GoalPickerViews.swift Cadence/iOS/iOSRootSidebar.swift Cadence/iOS/iOSGoalAttachListsSheet.swift
```

**Not checked:** per the brief, no detector test suite or build ran. Counts and stale-entry checks
were measured from a clean `git archive HEAD` tree; the unlisted direction is source-verified as an
exact-set assertion in each detector but was not freshly executed. In-flight working-tree changes
were excluded.

## R9 — Size the accessibility batch before it is briefed

Batch O will fix the unnamed icon-only controls, ledgered by T-637 as 31 sites in 24 files, split
T-672 (ten copies of a search-field clear button), T-673 (8 row glyphs), T-674 (10 helpers/chrome).
Measured before batches H through L.

Three questions, in order of value:
1. **Re-count all three.** Which sites have been fixed incidentally since?
2. **T-672's ten copies already differ** in font size (11/12/16), tint (`Theme.dim` vs `.opacity(0.5)`
   vs `0.55`) and — verified once — **whether they restore focus, 4 of 10 doing so**. Is that split
   still 4/10? Converging them is a design decision if they genuinely differ in behaviour, and a
   naming sweep if they do not. **That answer decides whether T-672 needs Opus or Sonnet.**
3. `ListEditorIconCell` threads `var accessibilityLabel: String? = nil` and reportedly only **1 of 2**
   call sites passes one. Confirm, because the proposed fix is a compile gate (`let`, no default)
   rather than a label per site, and that only works if the population is that small.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 13
```

**KEEP THE 31-SITE BATCH; SPLIT T-672'S VISUAL CONSOLIDATION FROM BEHAVIOR CONVERGENCE.** No site was
fixed incidentally. The clear buttons still differ materially, but a shared labelled button can
preserve each caller's existing action, keeping the implementation suitable for Sonnet; deciding
that all ten should refocus is separate work.

- **MEASURED:** T-672 remains **10 sites / 10 files**, T-673 **8 sites / 5 files**, T-674 **10 sites
  / 9 files**, plus T-611's **3 iOS sites / 2 files**. Total remains **31 sites / 24 files**. The
  exact file-and-count ledger at `CadenceIOSControlAccessibilityTests.swift:72-159` still matches
  clean HEAD; no batch H-L edit removed an offender.
- **MEASURED:** T-672 remains **4/10 explicit refocuses**. `CadenceCalendarPicker`,
  `CadenceContextPicker`, and `GoalPickerViews` set their local focus binding after clearing;
  `GlobalSearchView.clearQuery` reaches `GlobalSearchInteractionSupport.clearQuery`, whose line 31
  calls `setFocused(true)`. The other six only clear their query.
- **MEASURED:** the style split is still four variants: 12pt + `Theme.dim` (4); 16pt + dim (1);
  11pt + `Theme.dim.opacity(0.5)` (4); 11pt + `Theme.dim.opacity(0.55)` (1). This is not one
  byte-identical component waiting for substitution.
- **Disposition for T-672:** use one `CadenceSearchClearButton(action:)` for glyph, accessible name,
  hit target, and button style, while each caller supplies its current clear action. Do not make the
  shared component own focus. That is a **Sonnet** task. A follow-up that changes the six non-refocus
  paths needs a behavior decision and UI observation first.
- **MEASURED:** `ListEditorIconCell` has exactly **2 syntactic call sites** at
  `ListEditorSupportViews.swift:223,232`; only the ellipsis call passes `"More icons"`. The first
  call is inside `ForEach(offered)` and renders every selectable icon, so its missing name affects
  more than one runtime button even though it is one source site.
- **Disposition for `ListEditorIconCell`:** change `var accessibilityLabel: String? = nil` to a
  required `let accessibilityLabel: String`, remove `ListEditorOptionalControlLabel`, and pass a
  subject-bearing label at the `ForEach` call. The no-default compile gate is exactly the right fix.

Thirty-second confirmations:

```sh
sed -n '72,159p' CadenceTests/CadenceIOSControlAccessibilityTests.swift
rg -n -C 4 'xmark\.circle\.fill' Cadence/macOS
rg -n 'ListEditorIconCell\(|accessibilityLabel:' Cadence/macOS/Sheets/ListEditorSupportViews.swift
rg -n 'clearQuery|setFocused\(true\)' Cadence/macOS/Views/GlobalSearchView.swift Cadence/macOS/Views/GlobalSearchInteractionSupport.swift
```

**Not checked:** no VoiceOver announcement, keyboard-focus interaction, screenshot, build, or tests
ran. Counts and source behavior were read from a clean `git archive HEAD`; “explicit refocus” does
not claim the other six necessarily lose first responder at runtime.

## R10 — What has the repository learned that is written nowhere?

`docs/SUBAGENT_RUNBOOK.md` doubled this run, 255 → 505 lines, all of it hazards discovered the
expensive way. `AGENTS.md` is at its 199-line cap and cannot grow.

Read the last ~60 commits' messages — this repo puts reasoning there deliberately — and report **any
rule that was learned, stated once in a commit, and never written into a guide.** Those are the ones
that get rediscovered. Two known examples of the shape, both now in the runbook, as calibration: that
`SIGTERM` is not a restore, and that a `pgrep -f` inside a script matches the script itself.

Also worth reporting: anything in the runbook that is now **stale or contradicted** by later work. It
grew fast and nothing has audited it.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 13
```

**FIX THREE ACTIVE GUIDE ERRORS, THEN ADD FIVE RULES; there is no new product bug in this answer.**
The stale statements can misdirect work today. The five omissions describe implementations that are
currently correct and usually pinned locally, but their reusable lesson is absent from every agent
guide and is therefore still paid for by the next task.

### Fix now

| Disposition | Evidence | Can this happen today? |
|---|---|---|
| **FIX T-750:** change `docs/SUBAGENT_RUNBOOK.md:55-59` from a “200-line cap” checked with `wc -l` to **199 by `wc -l`**, or tell agents to use the test's split calculation. | **MEASURED:** `AgentContextBudgetTests.swift:103-107` retains the trailing empty element, so a newline-terminated 200-line file counts as 201. Commit `8c04958` records the full-suite failure this already caused. | **Yes.** `AGENTS.md` is exactly 199 lines now; one added line passes the runbook's stated check and fails the test. |
| **NARROW THE PROHIBITION:** delete `docs/SUBAGENT_RUNBOOK.md:186`'s bans on building, launching, and simulator use; retain only the bans on the shipping app, real store, process-name killing, and write-enabled MCP. | **MEASURED:** line 186 says “Never”; lines 191-228 immediately permit and prescribe private builds, launches, and simulator verification. Root `AGENTS.md` also requires `scripts/run-macos-app.sh` for a launch. | **Yes.** An agent obeying the first statement skips visual verification that the same guide explicitly permits five lines later. |
| **DELETE THE STALE READER WARNING:** replace `Cadence/Shared/AGENTS.md:56-59` with the current rule that `functionBody(named:)` balances the parameter list. | **MEASURED:** `CadenceTestTargetHygieneTests.swift:110-133` proves a defaulted closure is skipped; `docs/SUBAGENT_RUNBOOK.md:148-158` already says T-644 fixed it. | **Yes.** The nearest mandatory scoped guide still tells Shared editors that a working reader is broken and encourages obsolete workarounds. |

The runbook also states the zsh `path`/`$PATH` hazard twice, at `:37-45` and `:76-79`.
**DEDUPLICATE** the second copy when touching the file; this is reading cost, not a correctness bug.

### Add compactly

| Destination and rule | Evidence and present status |
|---|---|
| **ADD to `Cadence/Models/AGENTS.md`:** adding an `@Model` requires updating/running `CadenceFirstLaunchEmptyStoreTests`, in addition to schema, reset, export, MCP, and markdown inventories. | **MEASURED:** commit `4c4d7e0` records a new `FocusSessionLog` passing 18 scoped suites but failing merged HEAD because the schema-driven first-launch entity count was not updated. **Code is right and pinned; guidance is missing.** |
| **ADD to Shared source-scan guidance:** a detector that resolves calls by type and function name cannot distinguish overloads; publish a name as committing only when every overload agrees. | **MEASURED:** commit `793c3f6`; the invariant is implemented and tested at `CadenceSaveCommitDisciplineTests.swift:532-576,1629-1641`, but no agent guide contains it. **Code is right and pinned; guidance is missing.** |
| **ADD beside the `try? save()` rule:** to prove a refused mutation was rolled back rather than merely left pending, save the **same** `ModelContext` again, then inspect from a fresh context. | **MEASURED:** commit `34c0f4e`; `TagSupportTests.swift:499-525` explains and exercises the discriminator. A second context alone sees both states as absent. **The covered seed path is right; the general testing rule is not in a guide.** |
| **ADD to Shared component guidance:** do not hide a committing mutation in a writable `Binding` setter; for a picker that can be refused, take the current value plus an answering `select` closure, with no second writable path. | **MEASURED:** commit `23c45a9`; `CadenceChoicePickerDismissalTests.swift:32-33,79` and `CadenceChoicePicker.swift:128` pin the current component. **The known population is fixed and pinned; the cross-file detector blind spot remains a design rule.** |
| **ADD to build safety:** compile-only iOS verification uses `-destination 'generic/platform=iOS Simulator'` and requires no simulator claim or boot. | **MEASURED:** commit `56244bc`; the command and no-boot fact are in `docs/apple-release-readiness.md:93-100`, but absent from agent guides. **The release gate is right; agents touching `Cadence/iOS/` or shared UI can still spend a device claim unnecessarily.** |

One measured platform fact should remain a **ticket-local warning**, not yet become an app-wide rule:
commit `af3b80e` observed one `iOSTaskDetailSheet` failure path where a root alert dismisses the sheet,
and a nearer alert bound to the same flag loses the message. The sibling
`iOSCalendarBundleDetailSheet` was explicitly not driven, so generalising this into the iOS guide
would turn one measurement into unsupported platform coverage.

Thirty-second confirmations:

```sh
wc -l AGENTS.md docs/SUBAGENT_RUNBOOK.md
sed -n '55,59p;186,205p' docs/SUBAGENT_RUNBOOK.md
sed -n '56,59p' Cadence/Shared/AGENTS.md
sed -n '103,107p' CadenceTests/AgentContextBudgetTests.swift
rg -n -i 'same context|every overload|generic/platform=iOS Simulator|first.launch|writable binding' AGENTS.md Cadence/**/AGENTS.md docs/*AGENTS_REFERENCE.md docs/SUBAGENT_RUNBOOK.md
git show -s --format='%h%n%B' 4c4d7e0 793c3f6 34c0f4e 23c45a9 56244bc af3b80e
```

**Not checked:** no build, test, app, simulator, or mutation run. All 60 commit messages were read;
guide presence/absence and the three contradictions were measured on clean committed source. The
five additions are prioritized documentation recommendations, not claims that their current code is
uncovered.

## R11 — Standing: audit each batch as it lands

Rather than waiting to be asked, treat every pushed batch as an audit target under §1 of
`docs/CODEX_BRIEF.md`: do the commits do what their messages claim? Batches **J, K and L** are already
named in R5. **M through Q will follow.** The two claims most worth checking are always the same shape
— an idempotence argument, and a "this only ever raises / never loses" argument — because neither has
an outside reader and both are easy to believe.

## R12 — Standing: which open tickets did the last batch invalidate?

After each landed batch, intersect its changed files and named symbols with `docs/TODO.md` and the
unanswered requests here. Re-measure only those overlapping entries. Report only tickets whose
population, premise, reachability, or proposed fix changed; cite an earlier answer instead of
re-deriving it. A clean result should be one sentence.

This is not R11: R11 asks whether the new commit did what it claimed. This asks what **other work**
the commit made stale.

## R13 — Which correct features are one wiring deletion from becoming inert?

Audit recently added or moved helpers whose production reachability depends on one or two calls,
registrations, environment injections, launch hooks, command handlers, or target-membership entries.
For each, separate:

- **LIVE:** the helper has no production route today;
- **UNPINNED:** production wiring is correct, but deleting it leaves every relevant test green;
- **PINNED:** an integration/source-membership assertion names the production route and dies with it.

Start with helpers added in the last 60 commits and with the two now-unused
`SchedulingActions.createTask` overloads filed as T-759. Give the exact call count, the production
path, the test that does or does not pin it, and a 30-second confirming command. Do not recommend
changing correct production code merely because its wiring lacks a test.

ANSWER 2026-09-03:

```
Tree read: 85bdee8
Dirty files: 20
```

**KEEP T-759 AND ADD TWO WIRING TESTS; the two live features are correctly wired today.** The scoped
pass found one genuinely unreachable helper family and two one-line production connections that no
test currently names. The latter are coverage gaps, not requests to change working app code.

| State | Exact spot | Finding and suggested fix |
|---|---|---|
| **LIVE: unreachable API** | `SchedulingService.swift:13-25,135-162` | **MEASURED:** both `SchedulingActions.createTask` overloads have **0 production calls** and exactly **1 test call each**, at `TaskBundleTests.swift:347,349`. The test's comments call them timeline “entry points”, but the app's four current creation routes call the committing `insertTask`/`insertBundle` siblings instead. **KEEP T-759:** delete both overloads; remove the two dead-path invocations from `noSchedulingEntryPointEverGivesATaskACalendarEventID` and keep that invariant over actual creation routes. This is dead API/test fiction, not a user-facing failure. |
| **UNPINNED: correct launch hook** | `PersistenceController.swift:121-130` | **MEASURED:** `CadenceFocusLedger.reconcile(in:)` has exactly **1 production call**, and its Boolean is correctly included in `changedStore`. No test names either `reconciledFocusMinutes` or that production call. `CadenceFirstLaunchEmptyStoreTests.swift:48-53` claims to pin the startup sequence but lists only four older calls, and its replay at `:596-603` omits reconciliation. **INFERRED, not mutation-run:** deleting the call and its `changedStore` term leaves all direct ledger tests intact. **Fix:** add reconciliation as the fifth expected/replayed pass and assert its answer participates in `changedStore`; retain the real behavioral ledger tests. |
| **UNPINNED: correct shared-note hook** | `CadenceNotePlanningSupport.swift:158-165` | **MEASURED:** all **10 production calls** of `CadenceCoreNoteSupport.update` rely on its single `syncNoteTagsFromMarkdownCommittingInsertions` call for frontmatter-tag creation. Tests exercise the raw tag sync and the shared note update's title behavior, but no test invokes `CadenceCoreNoteSupport.update` with tag frontmatter and observes a tag; the committing helper name occurs in tests only in a historical comment. **INFERRED, not mutation-run:** deleting line 163 leaves the helper and title tests green while automatic tag creation disappears from the shared update path. **Fix:** add one behavioral test that updates a note containing `tags: [roadmap]`, then proves a fresh context reads the minted tag; add a `syncTags: false` negative only if that parameter is intentionally retained. |

**Can these happen today?** T-759 is unreachable today by definition. The focus reconcile and note
tag sync both run in production today; their behavior is correct. Their risk is a future deletion or
refactor passing the present test suite, not a current app defect.

### Looks solid

- **PINNED:** the four committing `SchedulingActions.insertTask`/`insertBundle` app calls are named
  by `CadenceFocusSessionAndBlockCommitTests` at the month grid, schedule panel, and timeline canvas.
- **PINNED:** the committing choice-picker route has an exact 37-call-site census and source checks
  that the three committing callers use the answering initializer
  (`CadenceChoicePickerDismissalTests`).
- **PINNED:** all embedded-task edit surfaces are an exact source ledger over the shared helper, with
  behavioral commit/refusal tests (`CadenceNoteTaskEmbedCommitTests`).
- **PINNED:** the sole production `CadenceTaskStatusEditing.setStatus` caller is named at
  `CadenceResidueBatchTests.swift:162`, beside behavioral status lifecycle tests.
- **PINNED:** the image-loss notice's three doors are counted and the helper is behavior-tested in
  `CadenceMarkdownImageCommitSurfaceTests`.
- **PINNED:** `CadenceDefaults`' launch argument, app-level `defaultAppStorage`, and calendar-memory
  redirect are each named by `CadenceAgentDefaultsIsolationTests`; removing wiring is not silent.
- **PINNED:** reset and export coverage for the new `FocusSessionLog` are schema-driven through
  `CadencePrivacyDataResetSurfaceTests` and `CadenceDataExportSurfaceTests`, not hand-waved lists.

Thirty-second confirmations:

```sh
rg -n 'SchedulingActions\.createTask\(' Cadence CadenceTests
rg -n 'reconciledFocusMinutes|CadenceFocusLedger\.reconcile\(in: context\)' Cadence CadenceTests
sed -n '38,75p;596,604p' CadenceTests/CadenceFirstLaunchEmptyStoreTests.swift
rg -n 'syncNoteTagsFromMarkdownCommittingInsertions|CadenceCoreNoteSupport\.update\(' Cadence CadenceTests
rg -n 'CadenceFocusLedger\.reconcile|syncNoteTagsFromMarkdownCommittingInsertions' CadenceTests
```

**Not checked:** no build, test, mutation, app, or simulator run. The pass covered non-test
type-level helper families added in the last 60 commits and their thin production routes; it did not
classify new constants, model initializers, private leaf-view functions, or pre-existing helpers.
“Would stay green” is inferred from the complete exact-name test scan and should be confirmed by the
two deletion mutations before filing the test changes as done.

---

## R14 — Six tickets are marked CLOSED and still sit in the Open section

Measured 2026-09-03 by reading Open's headlines: **T-651, T-653, T-742, T-746, T-784** all begin
`CLOSED 2026-09-03` and are still above the `## Done` divider, and **T-777 appears twice**.

This is the third time this run that the Open count has read high for this reason, and it is the
cheapest possible error to find and the most annoying to trip over — every triage, every "how many
are left", every batch composition reads a number that is wrong.

Report: the full list of ids whose Open entry begins with a closure marker, plus any id appearing
more than once anywhere in the file, plus any id in Open that also has an entry under `## Done`.
**Do not move them** — the coordinator will, because moving entries is what dropped three tickets
earlier today. Just name them.

## R15 — Classify the open list, once, so nobody re-derives it

108 open. The coordinator has now classified them by hand twice and will again. Do it once properly
and keep it current.

For each open ticket assign exactly one bucket, and give the count per bucket:
- **PRODUCT** — a user of the shipped app can hit it
- **CORRECTNESS** — data or sync can end up wrong, whether or not anyone has seen it
- **INSTRUMENT** — a test, script, detector or measurement is wrong or unpinned
- **DUPLICATION** — two spellings of one thing, dead code, or a hoist
- **ACCESSIBILITY**
- **BLOCKED** — needs the user, needs hardware, or waits on something named
- **BOOKKEEPING** — the entry itself is wrong (see R14)

Two rules that make this worth more than a tally: **name the three you would do first inside each
bucket and why**, and flag any ticket whose bucket is arguable — a ticket that could be PRODUCT or
INSTRUMENT is usually one that was filed from the wrong end.

## R16 — Which tooling tickets are already moot?

**T-657 turned out to have zero live sites** because the work that would have justified it landed
first; it was cancelled before an agent built a widening with no offenders. **T-664 the same.** That
is two out of two, checked.

There are roughly 25 more instrument/tooling tickets open. Go through them and report, for each,
whether its **population still exists at HEAD**. Specifically worth checking because each was filed
against a moving target: T-704, T-705, T-706, T-707, T-709, T-719, T-728, T-729, T-730, T-732, T-745,
T-747, T-748, T-749, T-754, T-755, T-780, T-781, T-782, T-783, T-785, T-786.

A ticket whose population is zero is worth more to find than a new finding, and this class has
already produced two.

## R17 — Audit batches M, N and O against their own commit messages

Same shape as R5, which found a real overclaim. Three claims worth checking specifically, all of
them load-bearing and none with an outside reader:

- **`fba681a`/`24e7108`** — the iOS list editor now claims a refused save restores the **child
  projects'** tasks, not just the area's. Verify against the code, not the test.
- **`481c21c`** — T-708 claims dismissal is a *parameter* rather than a policy because 43 of 49
  notice call sites sit beside the control that failed and 6 do not. Check the 49 and the split.
- **`1273ea8`/`898f0d8`** — `agent-commit.sh` claims the shared index is provably clean after a
  commit through it, and that a lost declined hunk is refused on the next commit of that path.
  Both are claims about a tool that now guards every other commit.

## R18 — Apply R13's question to the four detectors

R13 asked which correct features are one wiring deletion from becoming inert, and found three. Point
the same question at the detectors themselves: **T-627, T-636(b), T-555, T-565.**

For each: if its production-side *rule* were deleted — the exemption list, the ledger, the sweep call
— would any test go red? A detector whose own invocation is unpinned is the hollow-instrument shape
two levels down, and this repository has now found it at one level (`mutate.sh selftest`, T-719).
