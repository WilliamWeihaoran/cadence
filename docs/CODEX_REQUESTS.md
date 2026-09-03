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

ANSWER 2026-09-04 (current snapshot):

```text
Tree read: a3068e3
Dirty files: 29
```

**T-672 is source-correct and pinned; T-673 fixed the product but left one committed detector stale.**

| Commit | Claim audit | Can this happen today? |
|---|---|---|
| `7e58fc6` / T-672 | **MEASURED:** all 11 search-clear call sites now use `CadenceSearchFieldClearButton`; the component requires a glyph size and focus binding, clears before its callback, restores focus, and owns one help/accessibility string (`CadenceSearchFieldClearButton.swift:36-69`). `CadenceSearchFieldClearButtonTests.swift:81-204` pins the 11-site ledger and the helper contract. The commit's build and mutation-run claims were **not independently rerun**. | **No live defect found.** The production wiring and source pins agree on this tree. |
| `a3068e3` / T-673 | **MEASURED:** the eight named row remove/complete glyphs now expose the affected row through `.accessibilityValue`; the exact population is pinned at `CadenceRowSubjectAccessibilityTests.swift:28-189`. **Also measured:** `CadenceIOSControlAccessibilityTests.swift:225-237` still expects `TasksPanelSupportViews.swift` to contain unnamed icon-only buttons, while T-673 removed that file's last two such glyphs. | **The accessibility product bug is fixed. The stale committed test is live today:** a full committed-source unit run should fail until that old expectation is updated. This is the collateral T-789 predicted, not an inferred UI regression. |

Suggested fix for the T-673 residue: update/rename the broad icon-only detector in the same closure
commit, remove `TasksPanelSupportViews.swift` from its expected unnamed population, and keep the new
row-subject suite as the semantic pin. Do not change the now-correct product labels.

Thirty-second confirmation:

```sh
rg -n 'CadenceSearchFieldClearButton\(' Cadence --glob '*.swift'
sed -n '225,237p' CadenceTests/CadenceIOSControlAccessibilityTests.swift
rg -n 'accessibility(Label|Value)' Cadence/macOS/Views/TasksPanelSupportViews.swift
```

**Looks solid:** both commits use exact source populations rather than example-only tests. T-672's
component contract is especially strong: removing focus restoration or one production call is a
named failure, not merely a visual regression.

**Not checked:** no build, test, mutation, VoiceOver, or runtime interaction was run. Product and
test-source claims above are clean-tree source measurements; execution claims remain unverified.

## R12 — Standing: which open tickets did the last batch invalidate?

After each landed batch, intersect its changed files and named symbols with `docs/TODO.md` and the
unanswered requests here. Re-measure only those overlapping entries. Report only tickets whose
population, premise, reachability, or proposed fix changed; cite an earlier answer instead of
re-deriving it. A clean result should be one sentence.

This is not R11: R11 asks whether the new commit did what it claimed. This asks what **other work**
the commit made stale.

ANSWER 2026-09-04 (current snapshot):

```text
Tree read: a3068e3
Dirty files: 29
```

Three open-ticket descriptions changed; the rest of the overlapping population did not.

| Ticket | What changed |
|---|---|
| **T-673** | **MEASURED:** implementation is now committed at `a3068e3`, but clean-HEAD `docs/TODO.md:1467-1482` still presents it as open. Its closure ledger has not landed. |
| **T-789** | **MEASURED:** its predicted collateral failure is now present: the old detector still expects two unnamed controls in `TasksPanelSupportViews.swift`, while T-673 named them. This is no longer prospective cleanup; it belongs in the T-673 closure. |
| **T-791** | **MEASURED:** the instruction to do a source-rule shape check *before* T-673 closes was missed. Reword it as a retrospective T-673 check plus the still-prospective T-674 check. |

**Unchanged:** T-674 still describes ten sites in nine files on clean HEAD; T-790's proposed work is
unaffected. The dirty checkout appears to contain later coordinator work, but it was deliberately
excluded from this committed-tree audit.

Thirty-second confirmation:

```sh
git show --stat --oneline a3068e3
sed -n '1467,1490p' docs/TODO.md
sed -n '225,237p' CadenceTests/CadenceIOSControlAccessibilityTests.swift
```

**Not checked:** no build or tests. This answer only intersects clean-HEAD changed files/symbols with
the committed TODO text.

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

ANSWER 2026-09-03:

```
Tree read: 7be904a
Dirty files: 38
```

**MOVE SIX CLOSED ENTRIES, DEDUPLICATE T-777, AND DO NOT CHASE AN OPEN/DONE OVERLAP.**

- **MEASURED — strict `CLOSED` population while still Open:** T-651, T-653, T-742, T-746, the first
  T-777 entry, and T-784. T-562 uses `RESOLVED` rather than `CLOSED`; its remaining body is struck
  historical context, so R15 separately classifies it as BOOKKEEPING rather than pretending it is
  live. T-704 merely uses the word “closed” in its explanation and is not closure-marked.
- **MEASURED — duplicate id:** T-777 is the only repeated entry header in the whole file, with two
  entries. **DEDUPLICATE** by retaining the live residue once and moving the closed history with the
  completed entry; do not discard either piece of reasoning.
- **MEASURED — Open also present under Done:** none. There is no cross-section duplicate to repair.

Can this happen today? **Yes.** Any Open count taken from entry headers reads six completed entries
as work, and any id-set count collapses the two T-777 entries differently from an entry count.

Thirty-second confirmation:

```sh
git show HEAD:docs/TODO.md | awk '/^## Done/{exit} /^- \[T-[0-9]+\]/{print}'
git show HEAD:docs/TODO.md | awk 'match($0,/^- \[T-[0-9]+\]/){id=substr($0,RSTART+3,RLENGTH-4); print id}' | sort | uniq -cd
```

**Not checked:** no entries were moved, no build or tests ran, and the dirty working copy of
`docs/TODO.md` was not used as evidence. This answer reads the committed tree so a coordinator can
apply the moves without accidentally incorporating another agent's in-flight ledger edits.

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

ANSWER 2026-09-03:

```
Tree read: 7be904a
Dirty files: 38
```

**CLASSIFY THE 105 ENTRIES ACTUALLY IN OPEN, NOT THE STALE 108 IN THE REQUEST.** Counts below are
entry counts and sum to 105. T-777 is deliberately represented twice as `closed` and `live`; that is
the duplicate R14 asks the coordinator to repair.

| Bucket | Count | Entries |
|---|---:|---|
| **PRODUCT** | 28 | T-771, T-768, T-741, T-714, T-689, T-690, T-777 (live), T-691, T-168, T-16, T-17, T-18, T-274, T-491, T-681, T-619, T-642, T-688, T-696, T-697, T-692, T-693, T-694, T-729, T-731, T-736, T-738, T-752 |
| **CORRECTNESS** | 12 | T-760, T-761, T-614, T-623, T-624, T-654, T-762, T-661, T-743, T-744, T-745, T-737 |
| **INSTRUMENT** | 28 | T-739, T-716, T-717, T-718, T-780, T-781, T-782, T-481, T-710, T-551, T-669, T-670, T-657, T-664, T-678, T-704, T-705, T-709, T-728, T-730, T-732, T-747, T-751, T-755, T-748, T-749, T-786, T-785 |
| **DUPLICATION** | 14 | T-759, T-740, T-765, T-720, T-698, T-699, T-680, T-612, T-665, T-675, T-695, T-703, T-754, T-783 |
| **ACCESSIBILITY** | 3 | T-672, T-673, T-674 |
| **BLOCKED** | 8 | T-122, T-115, T-55, T-511, T-584, T-626, T-706, T-707 |
| **BOOKKEEPING** | 12 | T-777 (closed copy), T-447, T-531, T-554, T-562, T-651, T-653, T-722, T-723, T-742, T-746, T-784 |

### First three per bucket

- **PRODUCT:** **DO T-642** first because a refused detail-sheet mutation ejects the user from the
  sheet today; **DO T-689** next because a valid completed-only goal population is presented as no
  goals; **DO T-736** next because ordinary column renaming visibly empties the column while typing.
- **CORRECTNESS:** **DO T-623** first because a local-replica-only hard delete can leave CloudKit
  children; **DO T-624** next because a device-local EventKit id is synced as cross-device data;
  **DO T-760** next because the iOS two-task block path still commits through a swallowed save.
- **INSTRUMENT:** **DO T-780** first because the commit guard is optional prose; **DO T-781** next
  because an indefinitely uncommitted declined hunk has only a manual status command; **DO T-786**
  next because the mutation runner cannot verify 52 display-named tests it can already enumerate.
- **DUPLICATION:** **DO T-759** first because two production overloads have zero production callers;
  **DO T-765** next because the shared snapshot already owns both handwritten undo sequences;
  **DO T-754** next as the largest mechanical set, 41 literals plus one named 10pt constant.
- **ACCESSIBILITY:** **DO T-674** first for ten icon-only commands, then **T-673** for eight row
  actions whose subject is unnamed, then **T-672** for ten unlabeled search-clear controls. That
  order follows consequence: ambiguous commands before a familiar text-field affordance.
- **BLOCKED:** **DO T-626** first when an iOS device is available because silent CloudKit delivery
  affects sync correctness; **DO T-584** when the user chooses the iPad notes behavior; **RECHECK
  T-115** only after Xcode changes, because the current Swift frontend is the blocker, not Cadence.
- **BOOKKEEPING:** **MOVE T-531** first because the one-time authorization has already been granted
  and root guidance says UI tests run; **MOVE T-722** and **T-723** next because both entries contain
  successful simulator observations and their discovered defects were separately fixed.

### Arguable boundaries

- **T-761** is CORRECTNESS rather than PRODUCT because the decisive defect is a refused persistence
  operation; the silence is its visible symptom. **T-738** is PRODUCT rather than CORRECTNESS because
  the extra CloudKit writes are churn, not wrong stored state.
- **T-670** is INSTRUMENT rather than DUPLICATION because its actionable complaint is that the sweep
  cannot reach two spellings. **T-729** is PRODUCT rather than INSTRUMENT because the derivation in
  the shipped layout is wrong even though the present overhang is harmless.
- **T-745** is CORRECTNESS rather than INSTRUMENT because preference-domain divergence changes what
  state services read. **T-730** is INSTRUMENT rather than BLOCKED because sanctioned screenshot
  fallbacks exist; the missing harness/documented route is the work.
- **T-672** could be DUPLICATION, but the missing accessible name is the user cost. **T-447** and
  **T-531** could be called BLOCKED if their historical prose is read in isolation; their own later
  measurements and current root guide make the entries themselves stale, so BOOKKEEPING is sharper.
- **T-732** could be BOOKKEEPING because the device-check premise is false; it remains INSTRUMENT
  because the live task is to re-triage and execute the now-available simulator check.

Thirty-second confirmation:

```sh
git show HEAD:docs/TODO.md | awk '/^## Done/{exit} /^- \[T-[0-9]+\]/{print}' | wc -l
git show HEAD:docs/TODO.md | awk '/^## Done/{exit} match($0,/^- \[T-[0-9]+\]/){print substr($0,RSTART+3,RLENGTH-4)}' | sort | uniq -cd
```

**Not checked:** no ticket was moved or rewritten, and no build, test, app, simulator, or mutation
ran. Classification is reasoned from every committed Open entry; counts and duplicate identity are
measured. Re-run the tally after R14's moves because the resulting active-work count will be lower.

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

ANSWER 2026-09-03:

```
Tree read: 7be904a
Dirty files: 38
```

**CLOSE T-719, T-755, AND T-782; KEEP THE OTHER 19, WITH T-704 CONDITIONAL.** “Live” below means the
ticket's source or environmental population still exists at committed HEAD, not that its proposed
fix is necessarily the right one.

| Ticket | Population at HEAD | Disposition and evidence |
|---|---|---|
| T-704 | **ZERO NOW; CAUSE UNSETTLED** | **KEEP CONDITIONALLY.** The app-container temp tree currently has 0 `inMemory_store_ckAssets` directories, and `CadenceTestStoreSupport.swift:30-36` supplies `.none`. That is a point-in-time absence, not the before/after run the ticket requires. Close only after the next formerly leaking suite leaves the count unchanged. |
| T-705 | **LIVE** | **KEEP.** `scripts/xcb.sh:135-150` only reports; it has no prune mode. Five shared Cadence DerivedData entries exist now, four without `info.plist`, so the unattributable population remains. |
| T-706 | **LIVE** | **KEEP/BLOCK.** `/private/tmp/cadence-uitest-auth` still exists and measures 1.4 GB. Deletion still needs the user's confirmation. |
| T-707 | **LIVE** | **KEEP/BLOCK.** `.github/workflows/ci.yml:171-176` still gates iOS on manual `workflow_dispatch && run_ios`, and the file still declares itself a proposal. |
| T-709 | **LIVE GAP, ZERO OFFENDERS** | **KEEP.** `CadenceBuildInvocationHygieneTests.swift:281-293` still admits only `.md` and `.sh`; the live `.yml` workflow remains outside the walk. Its current commands use `xcb.sh`, so there is no current bad invocation. |
| T-719 | **ZERO / ALREADY DONE** | **MOVE/CLOSE.** It is already under Done, and `CadenceGuardScriptSelftestTests.swift:53-63` invokes both selftests. The R16 input list itself is stale. |
| T-728 | **LIVE** | **KEEP.** `collapsedRailLabelSlotHeight` is still 96 at `CadenceRegularPaneLayout.swift:777`; tests mention the measured 88pt in prose but no assertion measures the label against the slot. |
| T-729 | **LIVE** | **KEEP.** `CalendarBoardRailSupportViews.swift:133-138` still uses `labelSize` as the rotated slot width rather than line height. |
| T-730 | **LIVE** | **KEEP.** `scripts/run-macos-app.sh:37-41` still refuses while `/Applications/Cadence.app` is running; no screenshot harness has replaced that route. |
| T-732 | **LIVE** | **KEEP.** `docs/device-checks.md:15-18` still says a simulator cannot present the software keyboard, while the ticket records the contrary observation. The stale premise remains shipped guidance. |
| T-745 | **LIVE** | **KEEP.** There are 19 non-comment `UserDefaults.standard` references outside `CadenceDefaults.swift`, including service and per-list preference paths. |
| T-747 | **LIVE** | **KEEP.** `scripts/xcb.sh:176` still assigns one `${TMPDIR}cadence-xcb-$ID.log`; there is no per-invocation suffix or latest symlink. |
| T-748 | **LIVE** | **KEEP.** `test-host-lock.sh:194-200` can acquire and record `$PPID` without first proving that parent still lives. Queue pruning checks the waiter process, not the abandoned caller. |
| T-749 | **LIVE** | **KEEP.** `simulator-claim.sh:210-240` still races every waiter through device `mkdir`s followed by `sleep 5`; there is no FIFO ticket queue. |
| T-754 | **LIVE** | **KEEP.** Code-only review still finds 41 bare 10pt corner-radius sites plus `kanbanColumnCornerRadius = 10` at `KanbanBoardSupport.swift:20`: 42 sites total. |
| T-755 | **ZERO** | **CLOSE AS MOOT.** The only tempting `elevationRadius: 7` remains at `WidgetChrome.swift:98`, but the shipped detector at `CadenceRadiusControlCompactSweepTests.swift:46-52` explicitly excludes it and documents why. There is no faulty detector or unrecorded offender to fix today. |
| T-780 | **LIVE** | **KEEP/BLOCK ON USER POLICY.** Root guidance requires `agent-commit.sh`, but no `core.hooksPath`/pre-commit mechanism exists and bare `git commit` remains possible. |
| T-781 | **LIVE** | **KEEP.** `agent-commit.sh status` appears only in the script and runbook; neither `xcb.sh` nor another automatic path invokes it. |
| T-782 | **ZERO** | **CLOSE AS MOOT/PREVENTIVE.** The only test-host shell-outs are the two calls in `CadenceGuardScriptSelftestTests.swift:53-63`; both target scripts now probe working tools, and `mutate.sh:98-123` redirects `TMPPREFIX`. The hazard is documented in the runbook. No current third script has the defect. |
| T-783 | **LIVE** | **KEEP.** The seven named untrimmed `name` ternaries remain at `GoalsSupportViews.swift:434`, `TaskBundlePickerSupportViews.swift:320`, `CadenceSearchCandidateSupport.swift:60`, `GoalListLinkHelpers.swift:103`, `iOSCalendarEventEditSheet.swift:395`, `iOSRootSidebar.swift:776`, and `iOSColumnWindDownSupport.swift:50`. |
| T-785 | **LIVE** | **KEEP.** `CadenceEmptyTitleFallbackSweepTests.swift:399` still exempts all of `MarkdownNoteSupport.swift`; `CadenceDeleteConfirmationCommitTests.swift:165` still reads the entire task-mutation file. |
| T-786 | **LIVE** | **KEEP.** `mutate.sh:147,440-480` still expects function names in failure/presence logs and never consumes `test-suite-index.sh --labels`. The index currently reports exactly 52 display-named tests. |

Can this happen today? The 18 unconditional LIVE rows are reachable from current source or current
disk state. T-709 has no current bad YAML command, T-704 has no current residue, and T-755/T-782
have no current offender; keep severity separate from those population facts.

Thirty-second confirmations:

```sh
find "$HOME/Library/Containers/com.haoranwei.Cadence/Data/tmp" -type d -name inMemory_store_ckAssets | wc -l
./scripts/xcb.sh audit
du -sh /private/tmp/cadence-uitest-auth
rg -n 'LOG=|hasSuffix\("\.md"\)|hasSuffix\("\.sh"\)|workflow_dispatch|run_ios' scripts/xcb.sh CadenceTests/CadenceBuildInvocationHygieneTests.swift .github/workflows/ci.yml
rg -n 'UserDefaults\.standard' Cadence --glob '*.swift'
./scripts/test-suite-index.sh | rg 'logs as' | wc -l
```

**Not checked:** no build, test, mutation, cleanup, hook installation, app, or simulator run. The
external directory sizes/counts are measured current state; the source populations are measured on
committed HEAD. T-704 remains intentionally inconclusive because its decisive before/after run was
outside this read-only request.

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

ANSWER 2026-09-03:

```
Tree read: 7be904a
Dirty files: 38
```

**PASS ALL THREE CLAIMS, WITH ONE COMMIT-ATTRIBUTION CORRECTION.**

| Claim | Verdict | Evidence and reachability |
|---|---|---|
| iOS list-editor refusal restores child-project tasks | **PASS — MEASURED FROM PRODUCTION CODE.** `CadenceTaskMutationSupport.inheritedContextTargets(area:)` at `CadenceTaskMutationSupport.swift:421-428` includes direct area tasks and every child project's tasks where the child has no context. `iOSListEditorViews.swift:459-476` snapshots that exact set before changing the area and passes `undo.restore` to the throwing commit. A refusal can happen today on any area-context edit with an inheriting child project. **Attribution correction:** this landed in `24e7108`; `fba681a` is the macOS kanban-column rename commit and does not carry this iOS fix. |
| 43 bare notices / 6 dismissable notices | **PASS — MEASURED SOURCE CENSUS.** There are exactly 49 production `CadenceInlineFailureNotice(text:)` calls. Six pass a dismissal closure, all in five markdown editor files: two in `iOSMarkdownEditingSurface.swift:168,174`, then `MarkdownEditorView.swift:136`, `NotePanel.swift:107`, `NoteEditorPane.swift:298`, and `ListNotesSupportViews.swift:166`. The other 43 are bare. Tracing their state inputs finds a retry/control path that clears each notice before or after the next attempt; no seventh typing-only surface was found. The policy distinction is reachable today: typing does not trigger those six owners' retry controls. |
| private commit index is repaired; declined hunk is refused next time | **PASS — MEASURED SOURCE AND EXECUTABLE SELFTEST WIRING.** `agent-commit.sh:343-386` commits a private tree, resets the named paths in the shared index against the new HEAD, and refuses residue. Its mode 2 at `:453-477` checks both the repaired result and the unrepaired positive control. The declined ledger is written at `:354-370`, read before the next same-path commit at `:259-283`, and mode 3 at `:478-505` proves refusal, quoted lost content, successful reintegration, and record clearing. `CadenceGuardScriptSelftestTests.swift:34-63,97-119` requires both refusal names and runs the selftest. This protects commits made through the helper today; T-780 correctly remains open because a bare commit bypasses it. |

Thirty-second confirmations:

```sh
git show --stat --oneline fba681a 24e7108 481c21c 1273ea8 898f0d8
git grep -h 'CadenceInlineFailureNotice(text:' HEAD -- 'Cadence/**/*.swift' | wc -l
git grep -h 'CadenceInlineFailureNotice(text:' HEAD -- 'Cadence/**/*.swift' | grep -E '\) \{' | wc -l
sed -n '421,428p' Cadence/Shared/CadenceTaskMutationSupport.swift
sed -n '459,476p' Cadence/iOS/iOSListEditorViews.swift
./scripts/agent-commit.sh selftest
```

### Looks solid

- The iOS fix names the mutation's own target-set helper instead of re-deriving a sibling array, and
  `CadenceContextlessListSurfaceTests.swift:640-704` separately exercises the child-project restore.
- The six dismissal sites are individually ledgered, not just counted, in
  `CadenceMarkdownImageCommitSurfaceTests.swift:325-379`; swapping one of the six would fail.
- The commit helper's positive control demonstrates the exact dirty-index failure without the
  repair, and the Swift test requires every refusal to appear in both script body and selftest.

**Not checked:** no build, test, selftest, commit, app, or simulator ran in this audit. “PASS” for the
shell behavior is based on reading both implementation and executable selftest assertions; run the
provided selftest command before changing the helper. The 43 retry-owner classification is source
tracing, not observed UI interaction.

## R18 — Apply R13's question to the four detectors

R13 asked which correct features are one wiring deletion from becoming inert, and found three. Point
the same question at the detectors themselves: **T-627, T-636(b), T-555, T-565.**

For each: if its production-side *rule* were deleted — the exemption list, the ledger, the sweep call
— would any test go red? A detector whose own invocation is unpinned is the hollow-instrument shape
two levels down, and this repository has now found it at one level (`mutate.sh selftest`, T-719).

ANSWER 2026-09-03:

```
Tree read: 7be904a
Dirty files: 38
```

**PIN THE FOUR REAL-TREE INVOCATIONS. The detector internals and ledgers are strong; the existence
of each app-wide sweep test is not required anywhere else.**

| Detector | Delete/empty rule data | Delete the real-tree sweep test | Disposition |
|---|---|---|---|
| **T-627 save-commit widening** | **RED.** The four exemption dictionaries at `CadenceSaveCommitDisciplineTests.swift:1125,1220,1330,1885` are consumed by the sweeps at `:83-160`, and `everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule` at `:1050-1074` checks live load-bearing entries. Gap fixtures beginning at `:421` separately pin widened parsing and call reach. | **GREEN INFERRED.** Remove the four `@Test` functions at `:83-160` and the fixture/exemption tests still exercise only synthetic or named sites. No outside suite requires those four test names or an app-wide `saveCommitSweep` call. | **ADD one external wiring assertion** naming all four sweep functions and requiring each body to call `saveCommitSweep`; mutation-delete one function to prove it. |
| **T-636(b) Optional success answer** | **RED.** Deleting the Optional branch in `successReport`/`persistedReport` at `:2191-2239` kills the positive fixture `returningSomethingOtherThanNilIsASuccessReportFromADeclarationThatAnswersAnOptional` at `:755-796`; its nil, Void, and closure-return negatives pin scope. | **GREEN INFERRED.** The app-wide enforcement is only the report sweep at `:105-118`. Remove that test and the Optional fixtures stay green while no product file is scanned for the rule. | **EXTEND the same external wiring assertion** to require `noSwallowedSaveIsFollowedByADismissOrACompletionHandler` and its `reportInstrument` + `saveCommitSweep` calls. |
| **T-555 shared `static func` string ledger** | **RED.** Emptying `cadenceStaticFuncConstantLedger` at `CadenceSharedConstantReuseSweepTests.swift:124` exposes its four sites to `noCallSiteRetypesASharedStringConstant` at `:316-348`; stale/missing entries are also checked bidirectionally at `:1023-1064`. Detector fixtures pin constant-vs-template parsing. | **GREEN INFERRED.** Remove the `noCallSiteRetypesASharedStringConstant` test and the exact-ledger test can still prove four known entries while no test rejects a fifth product offender. No external suite requires the sweep function. | **PIN the sweep function externally**, including the call to `cadenceSharedConstantOffenders` and subtraction of `cadenceStaticFuncConstantLedger`. |
| **T-565 comment-symbol claim ledger** | **RED.** Emptying `ledger` at `CadenceCommentSymbolClaimTests.swift:519` fails the fixed 30/9 shape at `:522-532` and the exact set equality at `:535-573`. Partition, exclusion, and positive/negative fixtures separately pin the reader. | **GREEN INFERRED.** Remove `everyQualifiedSymbolClaimInACommentResolvesOrIsLedgered` and the ledger remains internally well formed but no longer compared with the repository. No outside suite requires that test or its `instrument.sweep`. | **PIN the sweep function externally**, requiring both the all-source walk and `found == Self.ledger`; mutation-delete the test to verify the pin. |

Can this happen today? **The detectors are active and correct today.** The risk is a future one-test
deletion or merge resolution leaving all neighboring fixture tests green. Deleting only a ledger or
parser branch is already caught; deleting the app-wide invocation is the common unpinned edge.

The cheapest shared fix is a small `CadenceDetectorWiringTests` source-membership suite with four
exact required test names and one required call signature per body. Do not duplicate detector logic
there. Its job is only to make deletion of the original wiring red; the original suites remain the
behavioral authority.

Thirty-second confirmation:

```sh
rg -n 'noSwallowedSaveCommitsAnInsertOrADelete|noSwallowedSaveIsFollowedByADismissOrACompletionHandler|noCallSiteRetypesASharedStringConstant|everyQualifiedSymbolClaimInACommentResolvesOrIsLedgered' CadenceTests
rg -n 'existenceExemptions|reportExemptions|commitReachExemptions|cadenceStaticFuncConstantLedger|static var ledger' CadenceTests/CadenceSaveCommitDisciplineTests.swift CadenceTests/CadenceSharedConstantReuseSweepTests.swift CadenceTests/CadenceCommentSymbolClaimTests.swift
```

**Not checked:** no deletion mutation, build, or tests ran. Ledger/parser RED verdicts are measured
from direct dependency and exact-set assertions; whole-sweep GREEN verdicts are inferred from the
complete exact-name search and must be mutation-confirmed before filing the wiring ticket as done.

---

## Note on R14–R18 (coordinator, 2026-09-04)

All five answered well and three changed what happens next. **R16 is the highest-value one**: it
found three tickets whose population is zero (T-719 already Done, T-755, T-782) and refused to round
T-704 to zero when only a point-in-time absence was measured. That refusal is worth more than the
three closures. **R18** produced a ticket nobody had thought of — the detectors' own app-wide
invocations are unpinned — and correctly separated the MEASURED red verdicts from the INFERRED green
ones. **R17**'s attribution correction (`fba681a` is the kanban commit, not the iOS fix) is the kind
of thing only an outside reader catches.

Answer format is now right; no further guidance needed. Keep the `Tree read:` header, the
disposition-as-a-ticket-edit verdict, and the `Not checked:` close. The one habit to keep pressing:
when the request's own premise is stale, say so in the first line and re-derive, as R15 did with
"105, not the stale 108."

**R14's moves are deferred, not dropped.** Batch O is mid-flight and four agents hold ledger edits;
the moves land in the next between-batch window.

---

## R19 — Generalise R18: which app-wide sweeps are unpinned?

R18 checked four detectors and found all four have the same hole — delete the one `@Test` that walks
the real tree and every neighbouring fixture stays green. Four out of four is not a sample, it is a
shape.

Do the whole set. Enumerate every test in `CadenceTests` that **walks real source files** (reads
`Cadence/`, iterates a file list, or calls a sweep/instrument helper over the tree) as opposed to
operating on a synthetic fixture string. For each, report:

- the suite and test name,
- what its population is at HEAD (how many offenders it currently rejects — 0 is fine and important),
- whether **any other test** would go red if that single `@Test` function were deleted.

The third column is the one that matters. Report the unpinned ones as a list a single ticket can be
written against, and say how many of the total are already pinned — if it turns out most are, R18's
four are an anomaly and the shared-suite fix is wrong.

ANSWER 2026-09-04:

```
Tree read: d2c4593
Dirty files: 38
```

**FILE ONE SHARED MANIFEST TICKET FOR ALL 216 REAL-PRODUCT-TREE TESTS. ZERO OF 216 ARE PINNED.**

Operational definition: this includes an `@Test` that directly or transitively enumerates Swift
files under `Cadence`, `CadenceWidgets`, or `CadenceMCPServer`, or derives a real production file
set and iterates it. It excludes fixed-file source assertions and synthetic fixture-only tests.
`AgentContextBudgetTests` was deliberately removed from the mechanical candidate set because it
walks `AGENTS.md`, not product source.

- **MEASURED inventory:** 216 test functions in 84 suites. Each row below has **0 current rejected
  deviations** according to its exact empty/ledger/equality assertion at HEAD.
- **REASONED deletion result:** **NO** for every row below. An exact-name search found no second
  executable assertion requiring any one function to exist. The apparent cross-references are
  comments, detector fixtures, or tests of production behavior; deleting the named `@Test` changes
  none of those inputs. This was not mutation-run, so keep confidence separate from severity.
- **Already pinned:** **0 / 216**. R18's four are representative, not anomalous. A shared exact
  manifest checked by `CadenceTestTargetHygieneTests` is the right shape; adding another fixture
  beside each sweep still leaves deletion green.

The complete unpinned population, with `population = 0; pinned = NO` applying to every name:

```text
AINoteActionReviewTests: theWriteIsReachableOnlyThroughTheReviewGate; nothingInTheAIPathLogsOrPersistsARequest; theSourceScanActuallyReachesTheFilesItAssertsAbout
CadenceAccentStorageSweepTests: noStoredDeclarationAnywhereInTheAppFreezesAnAccent
CadenceAppleCalendarNamingTests: onlyTheDeclarationTypesTheAppleCalendarLiteral
CadenceAreaPickerConsolidationTests: noAreaPickerDerivesItsOwnList; theAreaPickerReadsTheSharedList; theAreaPickerSupportIsNotASecondCopyOfTheContextPicker
CadenceBundleInspectorHostTests: theBundlePanelIsDrawnOnlyBehindTheGuardedWrapper; everyPaneThatPresentsTheBundlePanelGoesThroughTheGuardedWrapper; exactlyOneBundleHostIsInstalledAndItIsAboveBothShells; theBundleHostAsksTheOneSharedRuleAboutTheTwoFactsItCanSee; theSourceScanIsNotVacuousInBundleInspectorHost
CadenceCancelledTaskReachabilityTests: theSourceScanIsNotVacuousInCancelledTaskReachability
CadenceChoicePickerDismissalTests: everyChoicePopoverCallSiteIsCountedAndOnlyTheCommittingOnesAnswer; nochoicePopoverIsHandedAselectionBindingThatCommits
CadenceSeedColourSourceTests: noFileOnTheMacOSSurfaceHandTypesAColourHex
CadenceColumnWindDownSurfaceTests: iOSWindsDownAColumnThroughTheSharedServiceFromOnePlaceOnly; theSourceScanActuallyReadsTheseFilesInColumnWindDownSurface
CadenceCommentSymbolClaimTests: thePartitionCoversEveryCharacterExactlyOnce; everyQualifiedSymbolClaimInACommentResolvesOrIsLedgered
CadenceContainerPickerConsolidationTests: noCallSitePreFiltersTheListsItHandsTheContainerPicker; noAppSurfaceReSpellsTheTaskToSelectionGetterTheComposerSupportDeclares; noAppSurfaceReDerivesTheContainerTokenPrefixArithmetic; noAppSurfaceHandsAListControlAnArrayItHasAlreadyNarrowed; noSurfaceThatReadsASharedPickerListNarrowsTheArrayItReadsItFrom
CadenceContextPickerConsolidationTests: noContextPickerDerivesItsOwnList; everyContextPickerReadsTheSharedList
CadenceContextlessListSurfaceTests: everyPlaceThatDerivesListsFromAContextIsOnTheLedger; theListEditorContextRowIsDeclaredInExactlyOnePlace
CadenceControlAccessibilityLabelTests: noControlInTheAppGainsATooltipWithoutAnAccessibleName; theUnnamedTooltipLedgerStatesHowManySitesEachFileStillHas; noVisibleToggleInTheAppIsLeftWithoutAnAccessibleName; noSharedOrDesktopAccessibilityHintNamesATouchGesture; theGestureHintDetectorSeparatesATouchOnlySurfaceFromASharedOne; noAccessibilityLabelInTheAppSpellsItsOwnFallbackForAnEmptyTitle
CadenceDataExportSurfaceTests: neitherPlatformReSpellsTheExport; theSourceScanActuallyReachesBothPlatformsSourceInDataExportSurface
CadenceDeletedSelectionGuardTests: theSelectionGuardSourceScanIsNotVacuous
CadenceEditorSaveCommitSurfaceTests: everyRollbackCallSiteInTheAppIsADeleteCommit
CadenceEmptyStateAuditTests: noEmptyStateSentenceIsSpelledInTwoFiles; theEmptyStateComponentSetIsDerivedFromTheDeclarations; everyEmptyStateShapedViewIsOneTheSweepReads; everyCopyBearingArgumentOfAnEmptyStateComponentIsReadable; noEmptyStateCallSiteRetypesTheSharedCopy; noMacReachableCopyAsksForATouchGesture
CadenceEmptyTitleFallbackSweepTests: noSurfaceHandSpellsAnEmptyTitleFallback; noSurfaceHandSpellsAnEmptyTitleFallbackAgainstAConstant; noSurfaceTestsATrimmedTitleAndThenReturnsTheUntrimmedOne; everyTitlePromptInTheAppIsANounPhrase; noGoalPickerCallSiteRepeatsTheEmptyTextDefault
CadenceFirstLaunchEmptyStoreTests: noUnpromptedCodePathSeedsTheDefaultTags
CadenceGlobalUndoSurfaceTests: noAppSourceHandsAnUndoManagerToAnything
CadenceGoalListLinkSurfaceTests: onlyTheSharedHelperConstructsALink; theSourceScanActuallyReachesBothPlatformsSourceInGoalListLinkSurface
CadenceHabitCompletionDuplicateTests: onlyTheHabitCompletionStoreConstructsAHabitCompletion; nothingUnderCadenceEverWritesAHabitDayQuantityAboveOne
CadenceIOSControlAccessibilityTests: noIconOnlyButtonInTheAppIsLeftWithoutAnAccessibleName; theUnnamedIconButtonLedgerStatesHowManySitesEachFileStillHas; theIconOnlyRuleReachesTheDesktopTreeAndNotOnlyTheTouchTree; theTooltipSweepFindsNothingOnATreeThatCannotDrawTooltips
CadenceInMemoryStoreHygieneTests: noInMemoryStoreInTheRepositoryLeavesCloudKitMirroringOn; theRepositoryDeclaresExactlyThreeInMemoryStores
CadenceInPlaceEditFlushCommitTests: everyProductCallerOfMoveToContainerGuardsOnTheAnswer; themoveAnswerIsDiscardedAtFiveTestCallSitesAndNowhereElse
CadenceInboxRemindersSurfaceTests: markingAReminderCompleteIsReachableFromBothPlatforms; nothingButTheManagerResolvesAConnectionStateFromTheFlags; theSourceScanActuallyReachesBothPlatformsSourceInInboxRemindersSurface
CadenceKanbanColumnLifecycleSurfaceTests: theSourceScanActuallyReadsTheseFilesAndThePatternsWork
CadenceLaunchWiringTests: exactlyOneProductionCallSiteRegistersForSilentPush; onlyTheRegistrarAsksAppKitToRegister; coldLaunchStillAsksForNoNotificationPermission
CadenceListDeletionSurfaceTests: iOSCallsTheSharedCascadesFromOnePlaceOnly; bothPlatformsReadTheSameCascadeSentence; theSourceScanActuallyReadsTheseFilesInListDeletionSurface
CadenceListWindDownSurfaceTests: noIOSSurfaceWindsAListDownByHand; theSourceScanActuallyReadsTheseFilesInListWindDownSurface
CadenceMarkdownImageCommitSurfaceTests: onlyTheMarkdownEditingSurfacesOfferToDismissTheirFailureNotice
CadenceMarkdownImageInsertionScopeTests: everyOutOfStoreEditorHostPassesTheFlagAndNoOtherHostNeedsTo
CadenceMarkdownSourceInventoryTests: everyStoredStringOnEveryModelIsClassified; theModelScanActuallyReadTheModelSources
SharedComponentsPlatformFenceTests: sharedComponentsFolderHoldsNoWholeFilePlatformFence
TodayAndInboxNamingTests: noLiveSourceSpellsARetiredIPadName; nothingOutsideTheTwoPaneTodayHostBuildsATwoPaneOnlyView; everyIPadPrefixedTypeIsBuiltOnlyFromAWidthGatedHost; noAgentFacingDocSpellsARetiredIPadName
NoteEditorSheetHeaderTests: noEditorSheetSurfaceSpellsTheHostGutterRampItself; noCallSiteHandsTheSharedHeaderAWidth; nothingInTheAppRewritesTheHorizontalSizeClassBetweenTheSheetAndItsHeader
CadenceNoteDeletionSurfaceTests: theIOSDeleteIsRequestedByRowsAndPerformedOnlyByTheModifier; theSourceScanActuallyReadsTheseFilesInNoteDeletionSurface
CadenceNoteFolderSurfaceTests: onlyTheSharedFilingHelperWritesAFolderPath; theIOSListDetailNotesTabIsTheFolderColumn; neitherPlatformDeclaresItsOwnCopyOfTheConvention; theSourceScanActuallyReachesBothPlatformsSourceInNoteFolderSurface
CadenceNoteReferencePanelSurfaceTests: backlinksAreResolvedInExactlyThreePlaces; iOSNeverDerivesReferencesItself; theSourceScanActuallyReachesBothPlatformsSourceInNoteReferencePanelSurface
CadenceNoteTitleSyncSurfaceTests: bothCommitPathsCallTheOneRule; neitherPlatformKeepsItsOwnCopyOfTheRule; noIOSSurfaceWritesANoteBodyWithoutTheSharedCommit; theSourceScanActuallyReachesBothPlatformsSourceInNoteTitleSyncSurface
CadenceNotesEditorPreferencesTests: theOnlyCodeMentionOfTheRetiredNotesTabKeyIsItsRetirement
CadenceNotesListSupportTests: theFoldHasExactlyOneOwner; neitherPlatformDeclaresItsOwnCopy; noHandTypedLetterspacingIsLeftInTheApp
CadenceNotificationsEnabledToggleTests: neitherPlatformDeclaresItsOwnCopyOfTheToggleReaction
CadenceNotificationsAuthorizationLifecycleTests: theLifecycleHookIsOneTypeRatherThanOnePerPermission
CadencePageHeaderMetricsTests: noTileCallSitePassesItsOwnCorner
CadencePaneWidthRuleHomesTests: theWidthRuleIsDeclaredOnlyInItsRegisteredHomes; theInventoryIsStillTwentyFourDeclarationsAcrossFiveFiles; theRegisterNamesEveryFileTheScanFinds; theSourceScanActuallyReachesTheFilesItIsCounting
CadencePressFeedbackSurfaceTests: noIOSSurfaceWearsTheHoverWash; theSharedPickersKeepOneUnfencedStyle
CadencePrivacyDataResetSurfaceTests: neitherPlatformReSpellsTheResetSequence; bothResetSurfacesReachTheOneConfirmationGate; theSourceScanActuallyReachesBothPlatformsSourceInPrivacyDataResetSurface
CadenceRadiusControlCompactSweepTests: noFileOutsideThemeSpellsALiteralCornerRadiusOfSeven; noCallSiteOutsideThemeSpellsRadiusControlMinusThree
CadenceRecurrenceEndSurfaceTests: nothingOutsideTheWorkflowAndTheModelWritesTheEndFieldsDirectly; noSurfaceTypesARecurrenceScopeSentenceOutAgain; theCalendarRecurrenceScopeIsDeclaredOnceAndOutsideEveryPlatformFence; theSourceScanActuallyReachesBothPlatformsSourceInRecurrenceEndSurface
CadenceSyncSurfaceTests: bothPlatformsResolveTheOneSyncVerdict; onlyOneFileInTheAppTalksToCloudKitDirectly; theSourceScanActuallyReachesBothSettingsSurfaces
CadenceRetiredCopyTests: noRetiredCopyIsStillDrawnAnywhereInTheApp; theRetiredCopySweepReachesEverySurfaceOfTheApp
CadenceRootSelectionLaunchContractTests: theMacRootOwnsNoSceneRestoredState
CadenceSaveCommitDisciplineTests: noSwallowedSaveCommitsAnInsertOrADelete; noSwallowedSaveIsFollowedByADismissOrACompletionHandler; noSuccessReportFollowsACommitSwallowedOneFrameDown; noInsertIsLeftPendingWithNoCommitAnywhereInItsDeclaration; theSaveCommitSweepReachesEverySurfaceOfTheApp; everySaveCommitExemptionStillNamesAFunctionThatBreaksTheRule
CadenceSettingsSectionCopyTests: theFixedGlyphSettingsEmptyRowIsDeletedRatherThanLeftUnused; theMacWorkHoursSentenceNamesEverySurfaceThatDrawsTheBand
CadenceSharedBoardChromeTests: theForkedColumnHeaderSpellingsAreGone; theForkedChipSpellingsAreGone; theForkedInlineEmptySpellingsAreGone; theSourceScanActuallyReachesBothPlatformsSourceInSharedBoardChrome; theUnifiedComponentsAreNoLongerInThePrefixStrippedIntersection
CadenceSectionEyebrowConvergenceTests: noSurfaceHandRollsTheSharedEyebrow
CadenceCalendarWeekdayHeaderConvergenceTests: theOnlyTwoWeekdayLabelsInTheAppReadTheSharedMetric; theMonthGridsWeekdayRowHasNoSizeKnobLeft
CadenceCompactEyebrowConvergenceTests: noSurfaceHandRollsTheCompactEyebrow; theConvertedCompactSitesCallTheSharedLabel; theEyebrowDocOnlyNamesMetricsTypesThatExist
CadenceSharedConstantReuseSweepTests: noCallSiteRetypesASharedStringConstant; theSharedConstantSweepReachesEverySurfaceOfTheApp; theHarvestReadsTheSharedConstantsTheSweepWasBuiltFrom; theHarvestDropsGlyphNamesAndKeepsDottedDefaultsKeys; everyUntitledPlaceholderHasOneDeclarationTheSweepCanSee; noSourceFileBuildsAPlaceholderLabelByInterpolation; everyPlaceholderLabelInTheAppIsDeclaredOrRecorded; everyUndeclaredPlaceholderLabelIsStillUndeclaredAndStillTyped; theSharedConstantDetectorSeparatesACallSiteFromProse; theHarvestReadsAConstantSpelledAsAStaticFuncAndNotATemplate; bothNewReadersSurviveEveryFileInTheProduct; everyStaticFuncConstantOffenderIsLedgeredAndEveryLedgerEntryIsStillReal; theComputedVarHalfHarvestsTheBuildIdentityKeysAndNothingElse; theComputedVarReaderSurvivesEverySwiftFileInTheRepository; everySharedLiteralExemptionIsStillLoadBearing
CadenceSharedTaskRowJobsTests: thereIsOneReadOnlyTagStripAndItIsShared; theMacOSOnlyDetailLineSpellingIsGone; theSourceScanActuallyReachesBothPlatformsSourceInSharedTaskRowJobs; neitherUnifiedJobIsForkedAcrossPlatformsAgain
CadenceStrokeBorderSweepTests: everyRemainingShapeStrokeCallIsOneOfTheTwoDocumentedExceptions
CadenceTargetSourceMembershipTests: mcpSourcesOnlyCallTopLevelFunctionsThatTargetCompiles; widgetSourcesOnlyCallTopLevelFunctionsThatTargetCompiles
CadenceTaskInspectorHostTests: theInspectorPanelIsDrawnOnlyBehindTheGuardedWrapper; everySurfaceThatPresentsTheInspectorGoesThroughTheGuardedWrapper; theHostIsInstalledAboveBothShellsAndInsideTheOneSheetThatCarriesAPage; theSourceScanIsNotVacuousInTaskInspectorHost
CadenceTaskStatusLifecycleSurfaceTests: theSourceScanIsNotVacuousInTaskStatusLifecycleSurface
CadenceTaskSurfaceOptionsTests: onlyTheSharedHelperSpellsTheOverflowLine
CadenceDesktopEmptyStateConvergenceTests: theMacsSecondEmptyStateViewIsDeleted; theEmptyStateSweepReachesTheFilesItClaimsTo
CadenceTestTargetHygieneTests: noSwiftPathInTheRepositoryIsADirectory
CadenceTodayOverdueSummarySurfaceTests: bothIOSWidthsDrawTheCardsFromTheOneList; theIOSTapTargetPresentsRatherThanReachingForANavigationManager; neitherPlatformRespellsTheHeadings
CadenceTodayRolloverSurfaceTests: neitherPlatformRespellsTheKeyOrTheCopy
CadenceTodayUnificationTests: todayNoLongerHeadsAGroupWithTheNameOfThePage; theRetiredMacOSTodayGroupingsAreGone; eachPlatformsTodayDrawsItsOwnPlatformsGroupHeading; todaysRowsAreTheSharedInteractiveRowAtThePanelsOwnInsets; theTimelinePaneNamesItselfOnceAndTheOtherHostsStillNameThemselves; theSourceScanActuallyReachesBothPlatformsSourceInTodayUnification; theTasksPanelNoLongerCarriesAModeWithOneCase; theDropCoordinatorKeepsOnlyTheHalfItsCallersUse
CadenceTodayListGroupingTests: macOSTodayLeadsItsSortWithTheSharedRank
CadenceCalendarZoomTests: theZoomKeyIsSpelledOnceInShippingSource
CrossPlatformParityTests: everyMemberOfTheWidgetDateVocabularyIsReachedFromSomewhere
DateFormatterSupportTests: everyDateFormatterInTheAppIsDeclaredInTheFormatterFile
MarkdownHeadingRampTests: nothingButTheRampDeclaresARamp; theRampHasExactlyThreeReaders; theScannerIsReadingRealSourceInMarkdownHeadingRamp
NoteExportSurfaceTests: theExportVocabularyIsDeclaredOnceAndOutsideThePlatformGuard; theIOSExportControlIsOneViewWithThreeCallSites; theScannerIsReadingRealSourceInNoteExportSurface; noExportSwallowsTheWriteThatProducesTheFile
SettingsCoverageCategoryRemovalTests: theParityManifestAndItsChromeAreGone
MacSettingsAboutAndHabitMetricsTests: bothAboutScreensReadTheSharedIdentityAndTheSharedRow; macOSDataSafetyKeepsThePrivacyParagraphAndNotTheLinks; theSourceScanIsNotVacuousInMacSettingsAboutAndHabitMetrics
SettingsSharedVocabularyTests: theSettingsStatusBadgeAndItsWrapperAreGone; noSettingsPaneStillDrawsAMenuPicker; bothWorkHoursPickersPresentTheSharedChoiceList; theSourceScanIsNotVacuousInSettingsSharedVocabulary
SettingsSevenPaneVocabularyTests: theFifthPrivateSettingsRowIsRetiredRatherThanRelocated; noSettingsPaneKeepsAPrivateInsetWell; noSettingsPanePaintsUnderTheSystemSeparatorAtAnyLineBreak
TaskOrderingTests: theNoDateSentinelLiteralIsSpelledOnceInProductionSource
WidgetSupportTests: theTitleTrimRuleIsDeclaredOnceInAFileTheWidgetTargetCompiles
```

Can this happen today? **Yes.** Deleting any one of these functions removes its production-tree
contract while the remaining 4,225 indexed tests retain no exact requirement for that function.

Thirty-second confirmation:

```sh
./scripts/test-suite-index.sh | wc -l
rg -l 'CadenceSourceScan\.swiftFiles|\.sweep\(|enumerator\(atPath:' CadenceTests --glob '*.swift'
```

**Not checked:** no `@Test` was deleted, no mutation, build, or test ran. The inventory and
cross-reference search are measured from committed source; the all-green-after-deletion column is
reasoned and should be proved once by the manifest ticket's mutation test.

## R20 — What actually blocks the App Store submission?

This is the question the user asks most and the one I answer least precisely, because I answer it
from `docs/apple-release-readiness.md` rather than from state.

Audit that document against the repository and the project file. For each gate it names, report
**MET / NOT MET / NOT CHECKABLE FROM THE REPO**, with the file and line that settles it. Cover at
minimum: bundle id and version/build strings, entitlements and capabilities actually in the target,
the CloudKit container identifier and whether anything in the repo records a Production deployment,
`ITSAppUsesNonExemptEncryption`, category/copyright/marketing keys, privacy-manifest requirements,
the privacy-policy and support URLs, icon and screenshot asset presence, hardened runtime and
sandbox settings, and the minimum deployment targets against the SDK.

Two things I specifically want distinguished, because I keep conflating them:

- gates that are **code or configuration** and can be fixed by an agent, and
- gates that are **the user's account, a web page, or a Apple-side action** and cannot.

Anything in the second group, name the exact action the user must take, in one line each. If the
readiness doc claims something is done that the repo contradicts, that contradiction is the most
valuable finding in this request.

ANSWER 2026-09-04:

```
Tree read: d2c4593
Dirty files: 38
```

**THE BINARY CONFIGURATION IS MOSTLY READY; THE SUBMISSION IS NOT PROVABLY READY. FIX ONE STALE
RELEASE COMMAND, COMPLETE THE METADATA PACKET, THEN HAVE THE USER PERFORM THE APPLE-SIDE GATES.**

Apple's current rules still require Xcode 26 and an iOS 26 SDK for iOS submissions, at least one
screenshot, required version metadata, and a public privacy-policy URL. CloudKit production schema
deployment remains a separate console action; a production APS entitlement does not prove it.

| Gate | Verdict | Repository evidence and owner |
|---|---|---|
| App bundle id | **MET** | Release has `PRODUCT_BUNDLE_IDENTIFIER = com.haoranwei.Cadence` at `Cadence.xcodeproj/project.pbxproj:788`; packet agrees at `docs/app-store-submission-packet.md:10`. **Agent-verifiable.** |
| Version/build | **MET** | Release is `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 16` at `project.pbxproj:769,787`; packet names 1.0 at `:15-16`. **Agent-verifiable.** |
| App entitlements/capabilities | **MET IN SOURCE** | Sign in with Apple, production-substituted APS, CloudKit, app group, sandbox, network client and Calendar are at `Cadence/Cadence.entitlements:5-28`; Release enables Calendar and user-selected read/write files at `project.pbxproj:775-776`. Reminders correctly has usage text rather than a nonexistent sandbox entitlement. **Agent-verifiable; profile match is Apple-side.** |
| Widget entitlements | **MET IN SOURCE** | App group and sandbox are at `CadenceWidgets/CadenceWidgets.entitlements:5-10`; Release points at that file and enables sandbox at `project.pbxproj:1099-1103`. **Agent-verifiable; profile match is Apple-side.** |
| iCloud identifier | **MET IN SOURCE** | `iCloud.com.haoranwei.Cadence` and `CloudKit` are explicit at `Cadence/Cadence.entitlements:11-17`. |
| CloudKit schema deployed to Production | **NOT CHECKABLE FROM THE REPO** | No deployment receipt, `cktool` export, or console-state record exists. `APS_ENVIRONMENT = production` at `project.pbxproj:764` controls push signing, not CloudKit schema deployment. **User/Apple-side.** |
| Encryption declaration | **MET** | `ITSAppUsesNonExemptEncryption = false` is in `Cadence/Info.plist:18-19` and duplicated into Release at `project.pbxproj:780`; packet agrees at `docs/app-store-submission-packet.md:17`. |
| Category | **MET IN SOURCE** | `LSApplicationCategoryType = public.app-category.productivity` at `Cadence/Info.plist:20-21`; packet says Productivity at `docs/app-store-submission-packet.md:12`. App Store Connect equality is not repo-checkable. |
| Description, keywords, copyright | **NOT CHECKABLE FROM THE REPO; PACKET INCOMPLETE** | Apple requires all three for the version. The packet's field list at `docs/app-store-submission-packet.md:7-24` contains none of them. **Agent can draft and add them; user must enter/confirm them in App Store Connect.** |
| Marketing URL/promotional text | **MET AS OPTIONAL / ABSENT** | Apple marks Marketing URL and promotional text optional. Their absence is not a blocker; do not invent a required plist key. |
| Privacy manifests | **MET IN SOURCE** | App declares no tracking plus `CA92.1` UserDefaults and `C617.1` file timestamp at `Cadence/PrivacyInfo.xcprivacy:5-78`; widget declares no tracking and `C617.1` at `CadenceWidgets/PrivacyInfo.xcprivacy:5-20`. The synchronized target group excludes only the files listed at `project.pbxproj:194-208`, not either manifest. Final archive aggregation remains an archive check. |
| Privacy labels | **NOT CHECKABLE FROM THE REPO** | The intended answers are documented at `docs/apple-release-readiness.md:26-48`, but App Store Connect state is external. **User/Apple-side.** |
| Privacy/support pages | **MET AS LOCAL CONTENT; PUBLIC GATE NOT CHECKABLE** | URLs are recorded at `docs/app-store-submission-packet.md:18-19`, with local pages at `docs/privacy.html` and `docs/support.html`. The repo does not prove GitHub Pages deployment or current public reachability. |
| App icon | **MET IN SOURCE** | Release selects `AppIcon` at `project.pbxproj:765,779`; `Cadence/Assets.xcassets/AppIcon.appiconset/Contents.json` names a complete macOS set and all 10 files are present. |
| App Store screenshots | **NOT MET IN THE REPO / CONNECT UNKNOWN** | The only PNGs are app icons; there is no submission screenshot set despite `docs/app-store-submission-packet.md:52-61` saying to prepare one. Apple currently requires 1-10 screenshots. **Agent can capture them; user must approve/upload them.** |
| Sandbox / hardened runtime | **MET** | Release sets both `ENABLE_APP_SANDBOX = YES` and `ENABLE_HARDENED_RUNTIME = YES` at `project.pbxproj:771-772`; widget sandbox is `YES` at `:1103`. |
| Deployment targets and SDK | **MET LOCALLY** | macOS 26.1 and iOS 26.2 are at `project.pbxproj:783,786`; installed macOS/iOS SDKs both report 26.5, satisfying Apple's current Xcode 26/SDK 26 floor. iOS is not this submission channel. |
| Final archive, distribution signing, embedded contents | **NOT CHECKABLE FROM THE REPO** | Packet requires distribution signing and exclusion of test/MCP artifacts at `docs/app-store-submission-packet.md:76-77`, but no inspected `.xcarchive` exists in the repo. **Agent can inspect an archive after the user/account can sign it.** |
| Release verification command | **NOT MET** | `docs/apple-release-readiness.md:94` still runs a bare test command, while its own `:103-109` says tests must hold the host lock and root `AGENTS.md` now requires `scripts/xcb.sh`. **Agent-fixable documentation contradiction.** |

### User/Apple-side actions

1. **Deploy CloudKit:** CloudKit Console → `iCloud.com.haoranwei.Cadence` → Production → Deploy Schema Changes; then verify the production schema.
2. **Match capabilities:** Certificates, Identifiers & Profiles/App Store Connect must enable iCloud/CloudKit, Sign in with Apple, App Groups, Calendar and remote notifications for `com.haoranwei.Cadence`; regenerate the distribution profile if changed.
3. **Complete metadata:** enter description, keywords, copyright, age-rating answers, category, support URL, privacy URL and privacy labels; choose version 1.0 build 16.
4. **Publish/verify URLs:** make both GitHub Pages URLs public and confirm the support page exposes usable contact information.
5. **Upload screenshots:** approve and upload at least one current macOS screenshot; the packet's five-angle set is the better minimum.
6. **Clear account gates:** accept current agreements, confirm Developer Program membership/roles, tax/banking where applicable, DSA trader status and distribution availability.
7. **Archive and submit:** create a Release archive with distribution signing, inspect entitlements/privacy report/embedded frameworks, upload it, attach build 16, add review notes, then submit.

Can this block submission today? **Yes.** Missing App Store Connect metadata/screenshots, an
undeployed CloudKit production schema, or an unsigned/unuploaded archive blocks the button even
though source configuration is correct. Apple documents the current gates in [required version
properties](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information),
[screenshot requirements](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots),
[SDK requirements](https://developer.apple.com/news/upcoming-requirements/), and [CloudKit schema
deployment](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema).

Thirty-second confirmation:

```sh
rg -n 'PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|CURRENT_PROJECT_VERSION|ENABLE_APP_SANDBOX|ENABLE_HARDENED_RUNTIME|ENABLE_USER_SELECTED_FILES|APS_ENVIRONMENT' Cadence.xcodeproj/project.pbxproj
plutil -p Cadence/Info.plist Cadence/Cadence.entitlements Cadence/PrivacyInfo.xcprivacy
find . -type f \( -iname '*screenshot*' -o -iname '*.png' \) -not -path './.git/*'
xcrun --sdk macosx --show-sdk-version; xcrun --sdk iphoneos --show-sdk-version
```

**Not checked:** no build, test, archive, signing, upload, URL request, App Store Connect account,
provisioning profile, agreements, privacy labels, screenshot well, or CloudKit Console state was
opened. MET IN SOURCE does not mean the external capability or submitted archive matches it.

## R21 — Are the 28 PRODUCT tickets reachable in a shipped build?

R16's question, pointed at R15's PRODUCT bucket. Two out of two and three out of twenty-two say this
class pays.

For each of the 28: does its described failure still exist at HEAD in code that a **user of the
released macOS app** reaches? Not "does the ticket describe something plausible" — does the call
path still exist, and is it behind any flag, debug guard, `#if DEBUG`, or platform condition that
excludes it from a Release build.

Three sub-answers worth separating:
- **LIVE ON macOS** — a released-build user can hit it.
- **LIVE ON iOS ONLY** — real, but on a surface that is not yet distributed, so it is not a v1
  blocker even if the ticket is correct.
- **ZERO** — the code changed underneath it.

Rank the LIVE ON macOS ones by how likely an ordinary first session hits them. That ranking is what
I will build the next batch from, so it is the deliverable, not the tally.

ANSWER 2026-09-04:

```
Tree read: d2c4593
Dirty files: 38
```

**RECLASSIFY THE STALE PRODUCT BUCKET: 15 LIVE ON macOS, 6 LIVE ON iOS ONLY, 7 ZERO.** None of
the 15 macOS paths is behind `DEBUG` or a release-excluding platform guard. Six are real work but
live wholly under `#if os(iOS)`; iOS is explicitly not distributed in
`docs/apple-release-readiness.md:11`.

| Ticket | Release reach | Settling code |
|---|---|---|
| T-771 | **LIVE ON macOS** | macOS reads `CadenceSidebarLists.ungroupedTitle = "Other"` (`CadenceSidebarListsSupport.swift:110`, `ContainerPickerSupportViews.swift:98`) while Create Goal still spells `Section("No Context")` (`CreateGoalSheet.swift:178`). |
| T-768 | **LIVE ON macOS** | The two event-card delete paths still call `CalendarManager.deleteEvent` at `CalendarBoardItemSupportViews.swift:225` and `TimelineEventBlock.swift:320`; the typed `presentRefusable` path exists separately at `DeleteConfirmationManager.swift:62`. |
| T-741 | **LIVE ON macOS** | The shared list/permanent title sync and the legacy `# Untitled` repair cycle remain documented and implemented at `CadenceNoteFolderSupport.swift:237` and `NoteMigrationService.swift:484`. Existing pre-T-733 data is required. |
| T-714 | **LIVE ON macOS** | Column edits still apply at `KanbanSectionColumnView.swift:446`, while the commit/refusal surface starts at `:493`; dismiss-without-another-control remains a release path. |
| T-689 | **ZERO** | iOS now computes `allComplete` and calls `goalsTitle(...allComplete:)` at `iOSFeatureViews.swift:222`; macOS's filtered/all states do not reproduce the old claim. The Open entry already says CLOSED. |
| T-690 | **ZERO** | Both settings roots now pass paused/cancelled projects (`SettingsView.swift:199-200`, `iOSSettingsView.swift:291-292`) and both lifecycle sections draw them. Entry already says CLOSED. |
| T-777 | **ZERO** | Both Calendar panes use `connectOfferTitle` (`SettingsListManagementSections.swift:214`, `iOSCalendarSettingsSection.swift:203`). Both duplicate Open entries are stale/closed. |
| T-691 | **ZERO** | `CadenceCalendarLinkHealth.missingLink` now normalizes the display title at `CadenceCalendarLinkHealth.swift:181-198`; entry already says CLOSED. |
| T-168 | **LIVE ON iOS ONLY** | The running focus implementation is `iOSFocusView.swift`; the missing persistent widget state and landscape-specific surface do not affect the shipped Mac target. |
| T-16 | **LIVE ON macOS** | `AppIcon` ships in the asset catalog and the sidebar reads it at `SidebarSupportViews.swift:74`. This is a visible design backlog, not a correctness defect. |
| T-17 | **ZERO** | The claimed device-list restriction does not exist: `TARGETED_DEVICE_FAMILY = "1,2"` at `project.pbxproj:757,799`; the entry itself says no project edit is needed and awaits a user-defined device audit. |
| T-18 | **LIVE ON macOS** | There are no `.strings`, `.xcstrings`, or `.lproj` resources and user-facing Mac copy remains English literals. This is a shipped localization absence, not a latent crash. |
| T-274 | **LIVE ON macOS** | Export/decode exists (`CadenceDataExportService.swift`), but no production import/restore surface consumes a decoded `CadenceArchive`; a Mac user needing restore has no route. |
| T-491 | **LIVE ON iOS ONLY** | The capture palette host/scrim is in `iOSCaptureRadialMenu.swift` and iPad root layout; no Mac call path. |
| T-681 | **LIVE ON macOS** | `TasksPanelSectionViews.swift:137` still applies List-only row chrome beneath a `LazyVStack` host. The path renders in Release but the stated impact remains harmless/invisible. |
| T-619 | **LIVE ON iOS ONLY** | The defect is disagreement between iOS's grid and macOS `CalendarVisualStyle` (`TimelineMetrics.swift:299`). The shipped Mac has only its own internally consistent ladder. |
| T-642 | **LIVE ON iOS ONLY** | The root alert/detail-sheet interaction is entirely under `Cadence/iOS/`; the recorded simulator failure is real but not a macOS v1 blocker. |
| T-688 | **LIVE ON macOS** | The iOS goal-chip half is iOS-only, but Mac quick-create still persists/displays the fallback `"New Task"` at `TimelineDayCanvas.swift:283`. |
| T-696 | **LIVE ON macOS** | Mac Settings still draws the unconditional work-hours sentence at `SettingsCalendarWorkHoursSection.swift:65`, while weekend suppression remains shared behavior. |
| T-697 | **LIVE ON iOS ONLY** | The undisclosed ready-slot and initial-hour effects are consumed by `iOSTodaySchedulePanel` and `iOSCalendarTimelineViews`; the Mac subtitle does describe its shipped effect. |
| T-692 | **LIVE ON macOS** | `CadenceCalendarPicker.swift` still groups/falls back differently from Settings' `unnamedAccountTitle` use at `SettingsListManagementSections.swift:525`. Requires an unnamed EventKit source. |
| T-693 | **ZERO** | Both Mac display constructors now use `unnamedCalendarTitle` at `CalendarEventPresentationSupport.swift:73,198`; entry already says CLOSED. |
| T-694 | **ZERO** | Notifications and Calendar now split offer/denied titles (`SettingsNotificationsSection.swift:54`, `SettingsListManagementSections.swift:214`); entry says FULLY CLOSED. |
| T-729 | **LIVE ON macOS** | The collapsed rail still frames its rotated label with `labelSize` at `CalendarBoardRailSupportViews.swift:133-138`. Release-reachable, presently described as harmless. |
| T-731 | **LIVE ON iOS ONLY** | The regular-width branches remain in iOS editor sheets (`iOSCalendarEventEditSheet.swift:235`, `iOSEventNoteEditorSheet.swift:81`) behind iOS size class. |
| T-736 | **LIVE ON macOS** | The editor still calls `applySectionEdits` per name change (`KanbanSectionColumnView.swift:404-408`) while card movement waits for commit at `:510-516`; the transient empty column remains. |
| T-738 | **LIVE ON macOS** | The same per-keystroke `applySectionEdits` writes the merged section config at `KanbanSectionColumnView.swift:446-464`; no release/debug gate intervenes. |
| T-752 | **LIVE ON macOS** | The one shared directional notice remains at `CadenceNoteActionSupport.swift:94` and list deletion forwards it at `CadenceListDeletionSummary.swift:137`; the opposite-direction case requires the T-623 orphan/fetch condition. |

### macOS first-session likelihood

1. **T-16** — the icon/sidebar mark is visible on launch.
2. **T-18** — every non-English user sees the English-only surface immediately.
3. **T-681** — Today renders the no-op modifiers in the default surface, though no pixel changes.
4. **T-729** — opening Calendar with a collapsed rail reaches the wrong derivation; current overhang is slight.
5. **T-736** — renaming a kanban column visibly empties it while typing.
6. **T-738** — the same ordinary rename writes once per keystroke; visible impact is nil, sync churn is inferred.
7. **T-771** — needs an unowned list plus sidebar/goal-attach use.
8. **T-696** — needs opening Calendar work-hours settings; the sentence is wrong on weekends.
9. **T-688** — needs a blank-title task through Calendar quick create.
10. **T-274** — only encountered when the user tries to restore an export.
11. **T-692** — needs an unnamed EventKit account/source.
12. **T-741** — needs legacy pre-T-733 note content and an edit.
13. **T-768** — needs deleting an EventKit item and the EventKit write refusing.
14. **T-714** — needs dismissing a column rename without another commit trigger and a save refusal.
15. **T-752** — needs an incomplete delete-impact fetch/orphan condition; it is a constraint, not an ordinary-screen defect.

Can this happen today? **Yes for all 15 macOS rows**, but only T-16/T-18 are unconditional visible
first-session exposure. T-681/T-729 are live code whose own tickets call the impact harmless;
severity must not be inferred from reachability.

Thirty-second confirmation:

```sh
rg -n 'ungroupedTitle|No Context|connectOfferTitle|unnamedCalendarTitle|pausedProjects|cancelledProjects|applySectionEdits|listRowBackground|unknownImpactNotice' Cadence
find Cadence -type f \( -name '*.strings' -o -name '*.xcstrings' \) -o -type d -name '*.lproj'
```

**Not checked:** no Release build, app, simulator, first-session drive, EventKit refusal, CloudKit
traffic capture, or mutation ran. LIVE/ZERO is measured from current call paths and guards; the
ordered likelihood list is reasoned from prerequisites.

## R22 — Crash and data-loss census in production code

Nothing in this repository has ever swept for this and the App Store is the wrong place to find out.

In `Cadence/` (excluding tests), census every: `try!`, `fatalError`, `preconditionFailure`,
`assertionFailure` outside `#if DEBUG`, force unwrap `!` on an optional that is not a compile-time
constant, array subscript by computed index, and `Array(...)[0]`/`.first!`/`.last!`.

For each site: can a **user action or a synced record** produce the failing input? A force unwrap of
a literal-backed `URL(string:)` is fine and should be reported as such, in a separate group, so the
list of real ones stays short. A force unwrap of something read from SwiftData, from a CloudKit
record, from `UserDefaults`, from EventKit, or from a file the user chose is a crash with a user in
front of it.

Rank by that reachability, not by count. If the answer is that all of them are literal-backed and
safe, say so plainly — that is a good outcome and I will not file a ticket.

ANSWER 2026-09-04:

```text
Tree read: d2c4593
Dirty files: 38
```

**Verdict: no user- or sync-reachable crash/data-loss site was found. Do not file a product bug
from this census.** The only release trap is the last-resort persistence bootstrap `fatalError`;
it requires the CloudKit store, disk recovery store, and in-memory container construction all to
fail. That is an infrastructure hardening opportunity, not an input-shaped live bug.

### Reachability-ranked census

| Reachability | Construct | Measured sites | User/sync can supply the failing input? | Disposition |
|---|---:|---:|---|---|
| Release, environmental only | `fatalError` | `PersistenceController.swift:189` | **No.** It is reached only after three container constructions fail, including the in-memory fallback. | Keep out of the product-bug queue; consider replacing the trap with a terminal recovery UI before submission. |
| Test/programmatic-construction only | `fatalError` | `PersistenceController.swift:27`; `iOSMarkdownTextView.swift:45`; `macOSRootShellViews.swift:180` | **No current production path.** The first belongs to `makeTestContainer`; the other two are `init(coder:)` traps on views constructed programmatically. | No change. |
| Release-inert assertions | `assertionFailure` | `iOSBundleInspectorHost.swift:48`; `iOSTaskInspectorHost.swift:47` | A missing environment host can reach the call, but optimized Release builds remove the assertion; the action then does nothing rather than crash or lose data. | Keep the assertions; UI-host wiring is a separate reachability concern. |
| Static regular expressions | `try!` | **19** | **No.** Every pattern is a source literal or literal composition, never markdown, SwiftData, CloudKit, defaults, EventKit, or file content. | No change. |
| Guarded/OS-contract unwraps | ordinary `!` | **8 non-URL sites** | **No failing input found.** Three are guard/contract-backed; five add bounded day/month offsets to internally constructed dates. | No product ticket. Optional cleanup can remove punctuation risk without changing behavior. |
| Literal/typed URL construction | ordinary `!` | **8 URL sites** | **No.** Seven are fixed schemes/paths or UUID interpolation; the calendar variant receives canonical date keys from its production callers. | Safe literal-backed group; no change. |
| Computed array access | subscript expressions | **89 expressions on 83 lines in 36 files** | **No failing input found.** Each is range-derived, index-guarded, clamped after a non-empty guard, or indexes arrays built in lockstep. Synced collection sizes can change values, but not violate those local invariants. | No product ticket. |
| — | `preconditionFailure` | **0** | — | — |
| — | `Array(...)[0]` / `.last!` | **0** | — | — |
| OS-contract collection | `.first!` | **1**, included in the eight non-URL unwraps | **No.** `PersistenceController.swift:351` uses the first application-support URL only after its app-group URL fallback is absent. | Low-value defensive cleanup only. |

### Exact non-subscript sites

The 19 source-controlled regexes are at:

```text
Cadence/Services/MarkdownTypingTransformSupport.swift:4
Cadence/Services/MarkdownQuoteSupport.swift:11
Cadence/Services/MarkdownImageAssetService.swift:145,148
Cadence/Services/MarkdownLinkSupport.swift:16
Cadence/Services/MarkdownChecklistSupport.swift:45,50
Cadence/Services/MarkdownListSupport.swift:68,69
Cadence/macOS/Editor/MarkdownEditorSupport.swift:232-241
```

The eight non-URL force unwraps are:

```text
Cadence/Services/AI/AISettingsManager.swift:117
  storedModel! is dominated by storedModel?.isEmpty == false.
Cadence/Services/PersistenceController.swift:351
  .first! relies on FileManager's applicationSupportDirectory contract.
Cadence/Shared/Components/CadenceWrappingHStack.swift:54
  width! is dominated by width?.isFinite == true.
Cadence/macOS/Views/CalendarMonthGridSupport.swift:200,208
Cadence/macOS/Views/CalendarPageComponents.swift:100
Cadence/macOS/Views/CalendarPageSupportViews.swift:251
Cadence/macOS/Views/CalendarTimelineViewportSupportViews.swift:56
  Calendar additions use finite loop/page offsets and internally normalized month/day anchors.
```

The separately safe URL group is:

```text
Cadence/Services/AI/AIProvider.swift:102
Cadence/Services/CadenceDeepLink.swift:71,73,75,77,79,80
Cadence/macOS/Views/SettingsListManagementSections.swift:237
```

### Computed-array appendix

**MEASURED:** a parser-free lexical sweep began with 1,538 bracket candidates, removed type syntax,
attributes, literals, and dictionary accesses, then reviewed all 89 remaining array expressions.
This is the complete reviewed file/line ledger; repeated expressions on one line appear once here.

```text
Models: Area.swift:163-167; HabitInsights.swift:24; Project.swift:164-168
Services: MCPReadOnly/CadenceReadDTOs.swift:76; MarkdownChecklistSupport.swift:76,79;
  MarkdownNoteSupport.swift:360,361,376,397,435,442; MarkdownPreviewParser.swift:67;
  MarkdownTableEditSupport.swift:83,215,217,247,260;
  MarkdownTableLayoutSupport.swift:85,98,110,113,126
Shared: CadenceFlowLayoutSupport.swift:91-93; CadenceFocusBundleSupport.swift:247;
  CadenceMarkdownPresentationSupport.swift:65; CadenceOrderReassignment.swift:71,76;
  CadenceScheduleSupport.swift:261,582; Components/CadenceDatePicker.swift:129;
  Components/EstimatePickerControl.swift:312
iOS: iOSListEditorViews.swift:355; iOSMarkdownPreview.swift:199; iOSSearchView.swift:534
macOS: CadenceCalendarPicker.swift:129,181; Editor/MarkdownSlashCommandSupport.swift:154,304,570;
  Editor/MarkdownTaskEmbedDrawingSupport.swift:207,210,227,230,241,243,365;
  Sheets/CreateTaskSheet.swift:182; Views/CadenceContextPicker.swift:170,196;
  Views/CalendarMonthGridSupport.swift:113,212; Views/CalendarPageComponents.swift:211,212;
  Views/CalendarPageMonthGridSupport.swift:75,111,112; Views/ContainerPickerSupportViews.swift:122;
  Views/GlobalSearchOverlayStateSupport.swift:22,24; Views/GlobalSearchSupportViews.swift:146,158;
  Views/GoalPickerViews.swift:189,215; Views/HabitsFormSupportViews.swift:206;
  Views/KanbanCardSupportViews.swift:254; Views/TasksPanelSupportViews.swift:290;
  Views/TildeContainerPicker.swift:281; Views/TimelineMetricsSupport.swift:161,162,166,171,173
```

Can this happen today? **The production persistence trap can happen only under a catastrophic local
store/bootstrap failure; none of the surveyed traps or subscripts can be driven to failure by a
user action or synced record on the current call paths.** That conclusion is REASONED from the
MEASURED census and the local guards, not crash telemetry.

Thirty-second confirmation:

```sh
rg -n 'try!|fatalError\(|preconditionFailure\(|assertionFailure\(' Cadence --glob '*.swift'
rg -n '\.first!|\.last!|Array\([^)]*\)\[[[:space:]]*0[[:space:]]*\]' Cadence --glob '*.swift'
```

**Looks solid:** the picker, markdown-table, layout, search, and calendar-grid accesses consistently
derive indices from `.indices`, explicit bounds, non-empty guards, or arrays produced together. In
particular, `MarkdownTableEditSupport.swift` validates row/column addresses before all five edits,
and all three `MarkdownSlashCommandSupport.swift` commit paths use `indices.contains` immediately
before indexing.

**Not checked:** no build, tests, app run, sanitizer, fuzz input, crash telemetry, or SwiftSyntax AST
pass. The array count is a reviewed lexical census; operator overloads and code generated outside
the committed Swift sources are outside it.

## R23 — The whole icon-only-control census, not three tickets' worth

T-672, T-673 and T-674 were each filed from a partial look and each named its own count (10, 8, 10).
Batch O is fixing those 28. I do not know whether 28 is the population or the part somebody noticed.

Census every control in `Cadence/` that presents **only** an icon — `Button`, `Label` with an empty
title, `Image` inside a tap gesture, toolbar items, context-menu rows, swipe actions — and report
which have an accessibility label, which inherit a usable one from a `Label("text", systemImage:)`,
and which have none. Split by platform directory.

Then: subtract the 28 that T-672/673/674 name. **How many are left?** If the remainder is small, I
will fold it into the same batch. If it is 60, the three tickets are the wrong shape and I need one
sweep test instead, and I would rather learn that before four agents finish.

ANSWER 2026-09-04:

```text
Tree read: d2c4593
Dirty files: 38
```

**Answer: four unnamed source sites remain after subtracting Batch O's 28. Three are the already
owned iOS sites in T-611. Only one is new.** Keep T-672/T-673/T-674 as shaped; fold the new macOS
site into T-674 and widen the source test so this control shape cannot remain invisible.

### Whole-app source census

| Tree | Explicitly named bare-icon `Button` | Self-naming `Label(text, systemImage:)` | Unnamed bare-icon `Button` | Unnamed icon tap gesture | Unnamed total |
|---|---:|---:|---:|---:|---:|
| `Cadence/Shared` | 2 | 0 | 0 | 0 | 0 |
| `Cadence/iOS` | 23 | 51 | 3 | 0 | 3 |
| `Cadence/macOS` | 30 | 6 | 28 | **1** | **29** |
| `Cadence/Models` + `Cadence/Services` | 0 | 0 | 0 | 0 | 0 |
| **Total** | **55** | **57** | **31** | **1** | **32** |

These are **source-site counts**, matching the ticket/test convention. A `ForEach` site can create
many runtime controls. Toolbars, context menus, and swipe actions are included in the `Button`
walk; 57 context/menu/action rows use a non-empty `Label` and therefore carry their own usable
text. No `Label("", systemImage:)` exists.

### The subtraction

```text
32 unnamed icon-only source sites
- 28 macOS Button sites owned by T-672/T-673/T-674
=  4 remaining

3 = Cadence/iOS/iOSMarkdownPreview.swift:328,371 and
    Cadence/iOS/iOSTaskDetailSheet.swift:244, already owned by T-611
1 = Cadence/macOS/Sheets/CreateContextSheet.swift:126-135, newly uncovered
```

#### [P2, MEASURED] The icon palette is a control, but neither named nor seen by the control test

`IconGrid` renders each offered system image in a `ZStack` and changes `selected` from
`.onTapGesture` at `CreateContextSheet.swift:126-135`. There is no accessibility label, button
trait, accessibility action, or `Button`. Keyboard and assistive-technology users therefore do not
receive the control semantics that the adjacent visual grid presents. The current detector in
`CadenceIOSControlAccessibilityTests.swift:84-116` intentionally recognizes only a `Button` whose
label is a bare `Image`, so it reports the committed 31-site ledger while this site remains live.

Can this happen today? **Yes.** Open context creation/editing on macOS and reach the icon grid. The
cells are pointer-tappable in Release. No unusual persisted or synced state is required.

**Suggested fix:** in T-674, make each icon cell a plain-style `Button`, give it a stable label such
as `"Select \(humanizedIconName) icon"`, expose selected state, and preserve the existing fixed
frame/visual treatment. Extend `CadenceIOSControlAccessibilityTests` (or a sibling source rule) to
recognize icon-only `.onTapGesture` controls until the conversion lands; the durable preference is
to ban that shape and require semantic `Button`s.

Thirty-second confirmation:

```sh
rg -n 'knownUnnamedIconButtonSites|actual.values.reduce|desktop.values.reduce' CadenceTests/CadenceIOSControlAccessibilityTests.swift
rg -n -B 10 -A 2 '\.onTapGesture' Cadence/macOS/Sheets/CreateContextSheet.swift
rg -n 'Label\(""[[:space:]]*,[[:space:]]*systemImage:' Cadence --glob '*.swift'
```

**Looks solid:** the existing exact ledger is unusually useful: it pins all 31 unnamed bare-image
buttons by file and count, proves the 3/28 iOS/macOS split, and explicitly excludes self-naming
`Label` rows. The 55 named bare-image buttons use the established `.cadenceControlLabel` or
`.accessibilityLabel` pattern rather than relying on a glyph name.

**Not checked:** no build, tests, VoiceOver session, keyboard traversal, Accessibility Inspector,
or runtime toolbar/menu expansion. Classification is source-measured; the quality of each of the
112 existing names was not linguistically reviewed in this request.

## R24 — What does the iOS surface have that nothing can catch?

The macOS test target never compiles `Cadence/iOS/`. That means every iOS-only file is unpinned by
construction, and I have been treating "the suite is green" as covering the whole app.

Quantify it. How many Swift files and how many lines live in `Cadence/iOS/` that the macOS test
target does not compile? Of the shared code in `Cadence/Shared/` and `Cadence/Models/` that iOS
depends on, how much is exercised only through macOS call sites?

Then the useful half: name the **iOS-only behaviours that have a macOS twin**, where a test written
against the shared layer would cover both. Those are the cheap wins. And name the iOS-only
behaviours with no macOS twin at all — those are the genuinely uncovered ones, and I want to know
whether that list is five things or fifty before deciding whether iOS ships in v1.

ANSWER 2026-09-04:

```text
Tree read: d2c4593
Dirty files: 38
```

**Premise correction:** the macOS product build does not exclude every file under `Cadence/iOS`.
The synchronized target includes the folder (`project.pbxproj:194-209,220-227`), and platform fences
do the exclusion. **100 of 105 Swift files, containing 39,742 of 40,487 lines, are wholly wrapped in
`#if os(iOS)` and therefore absent from the macOS module.** Five metric/copy files are deliberately
platform-neutral and do compile for macOS:

```text
Cadence/iOS/iOSSchedulePanelCopy.swift                  23 lines
Cadence/iOS/iOSTaskInspectorMetrics.swift              110 lines
Cadence/iOS/iOSTaskCollectionMetrics.swift             153 lines
Cadence/iOS/iOSCalendarMetrics.swift                   297 lines
Cadence/iOS/iOSEditorSheetMetrics.swift                162 lines
                                                       ---------
                                                       745 lines
```

So the useful release number is **100 files / 39,742 lines unavailable to a macOS build or macOS
test**, not 105 / 40,487.

### Shared-code test proxy

It is not possible to state how many shared lines are *executed* from a source-only audit. Compiling
a file is not executing it, and identifier mention is not line coverage. The following is a
MEASURED static ownership proxy over all 173 Swift files / 32,522 lines in `Cadence/Shared` and
`Cadence/Models`: declared types were matched against comment/string-stripped iOS, macOS, and test
sources.

| iOS-dependent shared/model group | Files | Lines | What the number proves |
|---|---:|---:|---|
| Direct type reference from `CadenceTests` | 117 | 26,557 | At least one declaration in each file is named by a unit-test source. It does **not** prove whole-file execution. |
| macOS reference, no direct test reference | **23** | **3,003** | iOS depends on it and macOS can exercise it indirectly, but no test names its declarations. This is the closest defensible source proxy for “only through macOS call sites.” |
| iOS reference, no macOS or direct test reference | **7** | **1,133** | Neither the macOS surface nor a direct unit-test reference reaches the declared type. Highest-value shared-layer gap. |
| No iOS type reference found by this proxy | 26 | 1,829 | Outside the iOS-dependent denominator; may contain free functions or indirect dependencies the type-name proxy cannot attribute. |

The seven strongest cheap-test candidates are exact:

```text
Cadence/Shared/CadenceCapturePaletteSupport.swift          424
Cadence/Shared/CadenceDetailPanelPresentation.swift         93
Cadence/Shared/CadenceNoteDateNavigation.swift              87
Cadence/Shared/CadenceProjectPickerSupport.swift            32
Cadence/Shared/CadenceSwipeActionSupport.swift              263
Cadence/Shared/CadenceTaskStatusEditing.swift               173
Cadence/Shared/Components/CadenceWrappingHStack.swift        61
                                                           ----
                                                          1,133 lines
```

The 23 macOS-proxy/no-direct-test files are:

```text
CadenceBundleTaskRowSupport.swift; CadenceCalendarEventStyle.swift;
CadenceCalendarModeSupport.swift; CadenceCloudAccountProbe.swift; CadenceColorPalette.swift;
CadenceDeepLinkResolutionSupport.swift; CadenceMarkdownImageInsertionNotice.swift;
CadenceTaskRecurrenceEndPresentation.swift; CadenceTodayOverdueSummarySupport.swift;
CalendarRecurrenceEditScope.swift; Components/CadenceAccentPalettePicker.swift;
Components/CadenceBoardColumnHeader.swift; Components/CadenceBoardMetadataChip.swift;
Components/CadenceDatePicker.swift; Components/CadenceInlineEmpty.swift;
Components/CadenceInlineFailureNotice.swift; Components/CadenceTaskDetailLineLabel.swift;
Components/CadenceTodayOverdueSummaryCards.swift; Components/CadenceTodayRolloverBanner.swift;
Components/EmptyStateView.swift; Components/GoalProgressBar.swift;
Components/HabitProgressViews.swift; GoalPresentationPalette.swift
```

### iOS behaviours with a macOS twin

These are **behaviour families**, not file counts. Their UI composition is platform-specific, but
their decisions can be pinned once in the shared layer and consumed by both surfaces.

| Family | iOS witness | Shared seam / cheap test target |
|---|---|---|
| Task compose, placement, tags, priority, subtasks | `iOSCalendarQuickCreateSheet.swift:16-124`; `iOSTaskDetailSheet.swift:5-86` | `CadenceTaskComposerSupport`, `CadenceTaskPlanningSupport`, `CadenceTaskFieldEditCommit` |
| Complete, cancel, reopen, settle and recurrence spawn/end | `iOSFocusView.swift:658`; `iOSTaskRowActionViews.swift:608-806` | `CadenceTaskStatusEditing`, `CadenceTaskRecurrenceWorkflowSupport`, `CadenceTaskRecurrenceEndPresentation` |
| Area/project/list editing, section merge and wind-down | `iOSListEditorViews.swift:353-382`; `iOSColumnWindDownSupport.swift:10-185` | `CadenceSectionEditingSupport`, `CadenceSectionConfigMerge`, list-deletion planning |
| Sorting, grouping, Today rollover and overdue presentation | `iOSTaskCollectionViews.swift:11`; `iOSTodayCompactViews.swift:1` | task query/presentation, `CadenceTodayRolloverSupport`, `CadenceTodayOverdueSummarySupport` |
| Notes, folders, references, exports and markdown transformations | `iOSListNotesView.swift:24-55`; `iOSNoteExportMenu.swift:55-77` | note planning/folder/reference/export services and markdown parsers |
| Calendar dates, grids, planning, links and recurrence scope | `iOSCalendarMonthViews.swift:13-81`; `iOSCalendarEventEditSheet.swift:16-141` | calendar date/grid/planning/link support and `CalendarRecurrenceEditScope` |
| Goals, habits, milestones and progress | `iOSTrackingEditorComponents.swift:4-167`; `iOSFeatureDetailViews.swift:1` | goal/habit mutation, presentation and contribution summaries |
| Reminder/notification reconciliation | `iOSInboxRemindersSection.swift:27-150`; `iOSNotificationsSettingsSection.swift:5` | reminder presentation and habit-notification reconciliation |
| Cloud account/sync/store-recovery decisions | `iOSSettingsOverviewSections.swift:4-78` | `CadenceCloudAccountProbe`, `CadenceSyncHealth`, persistence recovery verdicts |
| Deep-link destination and root selection | `iOSRootView.swift:231-306` | `CadenceDeepLinkResolutionSupport`, feature destination and shell navigation bridge |
| Settings/defaults and export/review presentation | `iOSSettingsComponents.swift:4-116`; `iOSDataExportSettingsSection.swift:22-74` | settings copy/preferences, data-export presentation, App Store review readiness |

The cheap-win list is therefore **11 families**, led by the seven shared files with no macOS/test
reference and the 23 shared files with only a macOS proxy. A test should target the named shared
decision, not screenshot the two UIs and call that behavioral coverage.

### Genuinely iOS-only behaviour

There are **10 meaningful platform-only families**, not fifty unrelated features:

1. UIKit markdown editing, text storage/layout, keyboard selection, canvas drawing, and mobile
   accessory strips (`iOSMarkdownEditor.swift:5-191`, `iOSMarkdownTextView.swift:4`,
   `iOSMarkdownBlockCanvasRendering.swift:32-92`).
2. Compact per-tab `NavigationStack` state, the More tab, and width-transition handoff
   (`iOSRootView.swift:36-64,198-207`, `iOSMoreTabView.swift:14-37`).
3. iPad regular-width split/detail composition and size-class presentation branches
   (`iOSFeatureComponents.swift:163-282`, `iOSListViews.swift:10-50`).
4. Touch capture radial menu, hold/release selection, scrim, and floating-create interaction
   (`iOSCaptureRadialMenu.swift:231-315,415`).
5. Custom swipe tray, full-swipe threshold, and gesture arbitration (`iOSSwipeActionRow.swift:12-96`).
6. Touch board paging, drag/drop and press feedback (`iOSCalendarBoardView.swift:6-46,256-269`,
   `iOSBoardCards.swift:227-371`).
7. Mobile focus-session screen and landscape/compact timer composition (`iOSFocusView.swift:84-153`).
8. Photos/file export and share-controller presentation (`iOSNoteExportMenu.swift:55-77`,
   `iOSDataExportSettingsSection.swift:22-74`).
9. iOS sheet/cover/inspector environment ownership (`iOSBundleInspectorHost.swift:34-87`,
   `iOSTaskInspectorHost.swift:34-66`).
10. The UIKit/EventKit authorization and write adapter itself (`iOSCalendarManager.swift:7-51,176-261`).
    Calendar policy has a macOS twin, but this implementation does not; extract a protocol before
    claiming one test covers both adapters.

Can this happen today? **Yes.** Any defect confined to those 100 fenced files can ship while every
macOS unit test remains green, because the compiler never type-checks that code for the tested
destination. The five neutral metric files are the narrow exception.

**Recommended release action:** add an iOS Simulator build gate first; it cheaply catches all
39,742 lines for compilation. Then add an iOS test host/UI smoke target for the 10 platform-only
families. In parallel, write ordinary shared unit tests for the seven no-proxy files, beginning with
`CadenceTaskStatusEditing` and `CadenceSwipeActionSupport`; follow with the 23 macOS-proxy files.

Thirty-second confirmation:

```sh
find Cadence/iOS -name '*.swift' -print0 | xargs -0 wc -l
rg -L '^#if os\(iOS\)' Cadence/iOS --glob '*.swift'
sed -n '194,227p' Cadence.xcodeproj/project.pbxproj
```

**Looks solid:** 117 iOS-dependent shared/model files already have direct test references, including
the central task mutation/planning/query, recurrence workflow, note planning/folder, calendar
planning/link, reminder reconciliation, and sync-health seams. The codebase has already done much
of the expensive extraction work; the missing value is targeted pinning and an iOS compile/runtime
lane.

**Not checked:** no macOS or iOS build, test, simulator, runtime coverage, linker map, or Xcode
scheme inspection beyond committed project membership. The 117/23/7 split is a static declaration-
reference proxy and must not be represented as executed-line coverage.

---

## Note on R19–R24 (coordinator, 2026-09-04)

Four of the six changed the plan. **R20** is now the ship checklist — it replaced a document I had
been quoting with a state audit, and the split between agent-fixable and Apple-side is exactly the
line I kept blurring. **R21** shrank the product backlog instead of growing it: 7 of 28 have no
population and 6 are iOS-only. **R19** is the most alarming result of the run — 0 of 216, where I had
assumed R18's four were unlucky. **R22 found nothing, and that is a good answer**; the 89-subscript
census reviewed individually rather than counted is why I believe it.

**R24's premise correction was right and mine was wrong.** The macOS target does not exclude
`Cadence/iOS/`; platform fences do. Keep correcting the request's premise in the first line.

**Decided since:** v1 ships **English-only**. T-18 is deferred as scope, not overlooked. Do not
re-file it, and do not count missing localization as a finding in anything below.

The next six are all pre-ship risk. The app **has never been used by anyone**, so code-derived
answers about what a first run looks like are the only evidence that exists.

## R25 — What does a brand-new user actually see, screen by screen?

Nobody has ever run this app with an empty store and no permissions granted. Every quality judgement
we have is from tests and from source. Before screenshots are captured and a build is submitted, I
want the first run derived from code.

Walk the launch path from `PersistenceController` and the root shells. Report, in order: what the
window shows at first paint with zero tasks, zero lists, zero goals and no calendar access; which
empty states appear and what each one says verbatim; whether anything is seeded (tags, default
lists, a sample task); what the sidebar contains; and where the first call to action is, if there is
one.

Then the question I care most about: **is there any point in that sequence where the app looks
broken rather than empty?** A blank pane with no explanation, a section header over nothing, a
control that does nothing until data exists, a spinner with no terminal state. Name each with
`file:line` and say what a first-time user would conclude.

If the first run is genuinely clean, say so plainly — I will trust that more than a list of nitpicks.

ANSWER 2026-09-04:

```text
Tree read: a3068e3
Dirty files: 29
```

**The ordinary minimum-window first run is coherent and empty, not broken. One wide-window error
path can produce a permanent spinner.**

### What appears, in order

1. `CadenceApp` constructs the shared `PersistenceController` and `NotificationManager`, but does
   not request a permission (`CadenceApp.swift:20-28`). Startup maintenance repairs/migrates the
   store; it does not seed a sample task, list, goal, habit, or default tag
   (`PersistenceController.swift:64-107`).
2. The macOS root selects Today by default (`macOSRootView.swift:20-22`;
   `macOSRootStateSupport.swift:10-13`). At the 960pt window floor with the stored 264pt sidebar,
   the detail is 696pt and uses the two-pane **tasks + timeline** layout; Notes appears only once the
   detail reaches 1,094pt (`CadenceRegularPaneLayout.swift:617-642`).
3. The sidebar contains Today, Tasks, Calendar and Notes in its primary navigation; Goals and Habits
   below; Settings and Focus in the footer. With no contexts/lists, its middle list region is simply
   empty (`SidebarView.swift:55-77,181-208`). It has no orphaned section header.
4. Today shows a `Today` header with count 0 and a visible `+` whose accessible name is `New task`
   (`TasksPanelSupportViews.swift:36-74`). The empty state says **“Nothing planned”** and
   **“Add a task with +, or schedule one from Inbox.”**
   (`CadenceTodayPresentationSupport.swift:81-86`; `TasksPanel.swift:320-339`). This is the first
   call to action. The adjacent timeline has a `Timeline` header and empty hour grid, which remains
   usable for scheduling (`SchedulePanelShellViews.swift:23-35`; `SchedulePanel.swift:105-143`).
5. On a wide window, mounting `NotePanel` creates today's note, this week's note and the stable
   `Notepad` record if absent (`CadenceNotePlanningSupport.swift:123-131`;
   `NoteMigrationService.swift:421-463`). These are infrastructure records with empty content, not
   sample data.

### Live risky spot

**P2, MEASURED source / INFERRED runtime:** `NotePanel.swift:80-99,113` draws an unlabelled
`ProgressView` whenever any active-tab note is nil. `loadOrCreateCoreNotes` swallows all three
creation/fetch failures with `try?` and carries no error state or retry
(`CadenceNotePlanningSupport.swift:123-131`). **Can this happen today? Yes**, on a wide first run if
the shared store refuses a fetch/save. The user sees an indefinitely spinning note pane and will
reasonably conclude Cadence is stuck. No matching open TODO was found.

**Suggested fix:** make `loadOrCreateCoreNotes` throwing (or return a typed result), keep loading,
loaded and failed states distinct in `NotePanel`, and show `CadenceInlineFailureNotice` with Retry.
Because these helpers insert and save, preserve the pending-change discipline while propagating the
failure; do not replace the swallowed errors with another `try?` one frame up.

Thirty-second confirmation:

```sh
sed -n '80,115p' Cadence/macOS/Views/NotePanel.swift
sed -n '123,131p' Cadence/Shared/CadenceNotePlanningSupport.swift
sed -n '320,340p' Cadence/macOS/Views/TasksPanel.swift
```

**Looks solid:** the default-width shell gives an empty user a named destination, a concrete next
action, and a functional planning surface. It neither invents sample work nor asks for Calendar at
launch.

**Not checked:** no app launch, screenshot, build, test, accessibility session, or deliberately
failing store. Window composition and failure reachability are derived from clean source.

## R26 — The permission prompts, in order, with their explanations

Cadence asks for Calendar, Reminders, Notifications, and iCloud. App Review rejects apps that prompt
without context, and users deny prompts they don't understand. Neither failure is visible in a test.

For each permission: where is it requested (`file:line`), **what triggers the request** — launch, a
user action, or a view appearing — what usage-description string does `Info.plist` supply, and is
there any in-app explanation shown *before* the system prompt.

Then the half nobody checks: **what happens on denial.** For each, trace the denied path. Does the
feature degrade with an explanation, fail silently, show an error that blames the user, or leave a
control that appears functional and does nothing? A silently dead control after a denied prompt is
the most common reason a first session ends badly.

Flag any permission requested at launch rather than at point of use. That is both a review risk and
the single biggest cause of blanket denials.

ANSWER 2026-09-04:

```text
Tree read: a3068e3
Dirty files: 29
```

**No user-visible permission is requested at launch. Calendar quick-create has one live denied-state
dead control; the other permission surfaces degrade explicitly.**

| Capability | Trigger and pre-prompt explanation | System usage string | Denial path |
|---|---|---|---|
| Calendar | **User action.** macOS Settings (`SettingsListManagementSections.swift:207-237`), iOS Settings (`iOSCalendarSettingsSection.swift:192-239`), iOS Search (`iOSSearchView.swift:465-500`) and iOS quick-create (`iOSCalendarQuickCreateSheet.swift:340-357`) ask only after the user presses Allow. Each shows an explanation first. | `Info.plist:22-23`: “Cadence uses Calendar to show events and to create, update, or delete calendar events when you ask it to.” | Settings and Search switch to explanatory denied copy and Open Settings. **Quick-create does not; finding below.** |
| Reminders | **User action** from the macOS/iOS Reminders settings or Inbox connection card. The shared state supplies the explanation and chooses Request, Open Settings, or no action (`CadenceRemindersPresentationSupport.swift:74-163`); the actual EventKit request is `CadenceRemindersManager.swift:130-166`. | `Info.plist:24-25`: “Cadence uses Reminders to show your active reminders in Inbox and mark them complete when you check them off.” | Denied offers Open Reminders Settings; restricted explains that device policy blocks access and deliberately offers no dead action. No silent failure found. |
| Notifications | **User action** in Settings. Both surfaces explain which task/due/habit alerts are local before calling the sole authorization method (`CadenceSettingsSectionCopy.swift:166-192`; `NotificationManager.swift:52-60`; `iOSNotificationsSettingsSection.swift:62-113`). | None is required or supplied; local-notification authorization has no Info.plist usage-description key. | A denial leaves the explanatory access card; iOS immediately opens app Settings after the denied answer. That is abrupt but explicit, not silent. |
| iCloud | **Not a TCC permission prompt.** The CloudKit-backed store is selected during persistence setup (`PersistenceController.swift:143-161`). Settings probes account status on appearance or explicit refresh (`CadenceCloudAccountProbe.swift:19-50`). | No usage-description string exists or is required for the user's iCloud account state. | Signed-out/restricted/error states are rendered as sync/account status. There is no app-controlled Allow button that could become inert. |

`CadenceAppDelegate.swift:27-34` does register for silent remote notifications at launch, but that API
does **not** display the local-notification permission prompt and does not contradict the result above.

### Finding

**P1 first-session trap, MEASURED:** `iOSCalendarQuickCreateSheet.swift:342-357` branches only on
`!calendarManager.isAuthorized`. After the first request is denied, it continues to show
**“Allow Calendar Access”**. A second press calls `requestAccess()` again; EventKit cannot re-present
the system prompt, the function answers false, and `normalizeCalendarSelection()` changes no visible
state. **Can this happen today? Yes:** deny Calendar from this sheet once and the only offered control
is silently dead. The correct pattern already exists twelve lines of logic away in iOS Calendar
Settings (`iOSCalendarSettingsSection.swift:207-222`) and in Search: branch on `isDenied`, explain the
state, and offer Open Settings. No matching open TODO was found.

**Suggested fix:** make quick-create consume the same shared Calendar authorization presentation
state as Settings/Search. For `.notDetermined`, show Allow; for `.denied`, show platform-specific
copy plus Open Settings; for `.restricted`, explain and expose no action. Pin the state-to-action
mapping in a pure shared test, then source-pin the sheet to that mapping.

Thirty-second confirmation:

```sh
sed -n '340,358p' Cadence/iOS/iOSCalendarQuickCreateSheet.swift
sed -n '207,222p' Cadence/iOS/iOSCalendarSettingsSection.swift
rg -n 'requestAuthorization\(|requestFullAccess|requestAccess\(' Cadence --glob '*.swift'
```

**Looks solid:** Calendar and Reminders usage descriptions accurately name both reads and writes;
none of the four capabilities surprises the user with a launch-time system prompt; Reminders has a
particularly complete four-state presentation model.

**Not checked:** no permission dialogs were driven on device/simulator, no App Review submission was
performed, and no build/tests ran. Request and denied paths are clean-source control-flow readings.

## R27 — Audit the English, because English is all v1 ships

The user has decided v1 is English-only. That raises the bar on the English: it is the whole
interface, not one localization among several.

Census every user-facing string in `Cadence/` — labels, buttons, headers, empty states, alerts,
notice text, menu items, tooltips, notification bodies. Report:

- **Terminology collisions.** The same concept spelled two ways. We have already been bitten by
  "Block" vs "Task Bundle" and by "Other" vs "No Context". Find the rest by concept, not by string.
- **Case inconsistency.** Sentence case vs Title Case on comparable controls, in the same surface.
- **Page headers that describe the page the user is already on.** This is a standing repo rule in
  `CLAUDE.md`; report violations even though a sweep supposedly covers it, because I want to know
  whether the sweep is complete.
- **Copy that blames the user, or that states a failure without a next action.**
- **Actual errors** — typos, wrong articles, broken interpolation, a sentence that reads wrong when
  its count is 1.

Rank by how many surfaces each problem touches. A single wrong word in ten places outranks ten
one-off awkward sentences.

ANSWER 2026-09-04:

```text
Tree read: a3068e3
Dirty files: 29
```

The lexical census found **2,428 candidate user-facing constructor/modifier lines** (`Text`,
`Button`, `Label`, `Toggle`, fields, menus, help and accessibility labels), followed by targeted
reads of shared copy enums, alert/notice text and notification bodies. That is a source census, not
a claim that every string literal is visible: interpolation, wrappers and dead branches require the
concept-level review below.

### Findings, ranked by spread

1. **P1 — “Block” has drifted back to “Bundle” across 9 files / 11 live UI literals (MEASURED).**
   `TaskBundle.defaultDisplayTitle` says Block and current iOS block creation/detail agrees, but
   Focus and macOS creation/edit/delete still say `Bundle`, `Bundle tasks`, `Bundle Focus`,
   `Log Bundle Session`, `Bundle title`, `Delete Bundle?`, and `Delete Bundle`
   (`CadenceFocusBundleSupport.swift:163`; `iOSFocusView.swift:500`;
   `FocusChromeSupportViews.swift:120`; `FocusBundleTaskSupportViews.swift:20`;
   `FocusLogSessionPopovers.swift:163`; `FocusSidebarSupportViews.swift:155`;
   `QuickCreateChoicePopover.swift:248,355`; `TimelineBundleBlock.swift:62`;
   `TimelineBundleBlockSupportViews.swift:71,203`). **Can this happen today? Yes**, through ordinary
   Block creation, editing and Focus. T-567 is closed and only centralized the untitled fallback;
   it does not cover this live vocabulary collision.

2. **P2 — four count strings are grammatically wrong at 1 (MEASURED).** “1 selected tasks” at
   `FocusLogSessionPopovers.swift:166`, “1 tasks” at `FocusSidebarSupportViews.swift:156`,
   “Collapsed, 1 notes” at `CadenceNotesListSupport.swift:692`, and “1 milestones / 1 habits” at
   `iOSFeatureViews.swift:184-190`. **Can this happen today? Yes** with one selected task, one Block
   member, one note in a collapsed group, or a goal with one child/habit.

3. **P2 — Markdown control capitalization differs across the two editor surfaces (MEASURED).** iOS
   keyboard/accessory commands say `Bulleted List`, `Numbered List`, `Code Block`, `Note Link`, and
   `Task Reference` (`iOSMarkdownTextView.swift:58-72`;
   `iOSMarkdownAccessoryViews.swift:530-546`), while macOS VoiceOver says `Bulleted list`,
   `Numbered list`, `Code block`, `Note link`, and `Task reference`
   (`MarkdownEditorView.swift:329-363`). The shared slash-command vocabulary already exists in
   `MarkdownSlashCommandCoreSupport.swift:34-50`; use it as the correct pattern.

4. **P3 — Reminders' pre-consent heading blames the state before the user has chosen (MEASURED).**
   `.notDetermined` says **“Reminders access required”** at
   `CadenceRemindersPresentationSupport.swift:91-97`, while Calendar and Notifications correctly
   distinguish a neutral `Connect ...` offer from an after-denial `... access required` warning.
   **Can this happen today? Yes**, on the first visit to Reminders settings. It is not a dead control,
   but it is the one remaining demand-shaped permission introduction.

5. **Already filed, do not duplicate:** T-771 owns `Other` versus `No Context` versus actual
   `Context` terminology. Its population remains live on this tree.

### Suggested fixes

- Add shared, user-facing Block vocabulary beside `TaskBundle.defaultDisplayTitle`, migrate only
  product words (leave Settings' technical `Bundle ID` alone), and source-scan for UI string
  literals containing Bundle outside an explicit exemption.
- Add a tiny shared pluralization helper for count+noun and use it for all four measured sites;
  test 0, 1 and 2.
- Make the Markdown core own sentence-case accessibility titles and have both toolbar adapters read
  them. Do not create a second case table.
- Give Reminders the Calendar/Notifications two-title state model: `Connect Reminders` before the
  prompt, `Reminders access required` only after denial.

Thirty-second confirmation:

```sh
rg -n '"[^"]*Bundle[^"]*"' Cadence --glob '*.swift'
rg -n 'selected tasks|\) tasks|\) notes|milestones /|milestones.*habits' Cadence --glob '*.swift'
rg -n 'PageHeader\([^\n]*subtitle:' Cadence --glob '*.swift'
```

**Looks solid:** the page-header rule currently has **zero** direct `PageHeader(... subtitle:)`
violations. Save/delete failure copy generally uses object-specific shared notices and does not
blame the user. No additional spelling typo survived the candidate review beyond the count grammar
above.

**Not checked:** no runtime localization extraction, screenshot OCR, VoiceOver reading, build, or
tests. Strings assembled indirectly by arbitrary functions can evade a constructor-based census;
the concrete findings are measured at their source sites.

## R28 — The widget extension nobody has audited

`CadenceWidgets` ships inside the submitted binary and has never been reviewed. It reads the shared
store through the app group, which means it can be wrong in ways the app is not.

Report: which widget families and sizes are declared; what each timeline provider returns for
`placeholder`, `snapshot` and `timeline`; how often it refreshes and whether that budget is
realistic; what it shows when the app group store is empty, unreadable, or the user has never opened
the app; and whether anything in the widget can write, rather than read.

Two specific risks worth naming if present: a placeholder that shows real user data (it renders in
contexts the user may not expect), and a timeline that never reloads after the app changes data.

ANSWER 2026-09-04:

```text
Tree read: a3068e3
Dirty files: 29
```

**Four widget families ship. Their data/privacy and write boundaries are sound; Milestone Momentum
alone can carry yesterday's labels past midnight.**

| Family | Sizes | Provider behavior | Scheduled refresh |
|---|---|---|---|
| Today Tasks | small, medium, large, extra large (`TodayTasksWidget.swift:160-171`) | Placeholder is synthetic tasks; snapshot reads the current store; timeline emits one current entry (`:15-43,46-125,128-140`). | ready 15m, empty 30m, unavailable 5m, capped at next day +60s (`CadenceTodayWidgetSupport.swift:135-154`). |
| Habit Check-In | small, medium, large (`HabitCheckInWidget.swift:103-114`) | Placeholder is eight hardcoded habits; snapshot/timeline read current store (`:14-40,43-79`). | ready 20m, empty 45m, unavailable 5m, capped at next day +60s (`CadenceHabitWidgetSupport.swift:116-134`). |
| Calendar Snapshot | small, medium, large, extra large (`CalendarSnapshotWidget.swift:89-100`) | Placeholder is synthetic; snapshot/timeline read a 14-day current-store window (`:13-39,42-84`). | ready 20m, empty 45m, unavailable 5m, capped at next day +60s (`CadenceCalendarWidgetSupport.swift:126-144`). |
| Milestone Momentum | small, medium, large, extra large (`MilestoneMomentumWidget.swift:102-113`) | Placeholder is four hardcoded goals; snapshot/timeline read up to five current goals (`:13-39,42-73`). | ready 30m, empty 60m, unavailable 5m, **no day-boundary cap** (`CadenceMilestoneWidgetSupport.swift:118-129`). |

All four open the app-group store read-only with CloudKit disabled in the widget process and map any
open/fetch failure to a typed unavailable snapshot. Empty and unavailable states are explicit:

- Today: “Nothing planned today” / “Widget needs Cadence”
  (`TodayTasksWidgetView.swift:409-427`).
- Habits: “No habits due today” / “Habit widget needs Cadence”
  (`HabitCheckInWidget.swift:295-310`).
- Calendar: “Schedule is clear” / “Calendar widget needs Cadence”
  (`CalendarSnapshotWidget.swift:352-367`).
- Milestones: “No active milestones” / “Milestone widget needs Cadence”
  (`MilestoneMomentumWidget.swift:388-403`).

The unavailable message tells the user to open Cadence once; the never-opened and unreadable-store
cases therefore do not render a blank widget. **No placeholder reads user data.**

### Writes and reloads

Today completion and Habit check-in are the only widget UI writes
(`TodayTasksWidgetView.swift:432`; `HabitCheckInWidget.swift:241`). Their intents use writable shared
containers, propagate save errors, publish the external-write marker and force a widget reload
(`CadenceWidgetIntents.swift:26-49,57-100,183-247`). Calendar and Milestones are read-only links.

The app asks WidgetKit to reload whenever its scene leaves active
(`iOSRootView.swift:159-172`; `macOSRootView.swift:324-329`), while privacy reset, palette changes and
widget writes force reloads. Therefore the requested “timeline never reloads after the app changes
data” failure is **not present**. WidgetKit still controls the actual delivery time, as intended.

### Finding

**P2, MEASURED:** Milestone Momentum is the only date-sensitive provider whose reload calculation
does not cap at the next day. Its cards carry `nextActionDueDate` and `dueTodayLabel`, yet a ready
entry created at 23:50 may remain for about 20 minutes after midnight; an empty one for about 50.
**Can this happen today? Yes**, without any unusual state. The three sibling support types already
contain the correct `min(fallback, nextStartOfDay + 60s)` pattern. No matching TODO was found.

**Suggested fix:** reuse a shared widget reload policy that accepts ready/empty intervals and always
applies the day-boundary cap. Add a pure date test at 23:50 proving all four families request a
reload at 00:01 rather than after their fallback interval.

Thirty-second confirmation:

```sh
sed -n '118,129p' Cadence/Services/CadenceMilestoneWidgetSupport.swift
sed -n '126,144p' Cadence/Services/CadenceCalendarWidgetSupport.swift
rg -n 'reloadAllWidgets' Cadence CadenceWidgets --glob '*.swift'
```

**Looks solid:** every family has synthetic gallery data, explicit empty/unavailable rendering,
bounded retry, and a deep link. Interactive writes use the same recurrence/habit helpers as the app
and force refresh only after a successful change.

**Not checked:** no widget gallery, timeline execution, app-group corruption, build, tests, or real
WidgetKit scheduling. Refresh timing and state behavior are source-measured policy.

## R29 — Does the MCP boundary still compile, and has it drifted?

`CadenceMCPServer` uses an **explicit Sources list**, which means the app scheme cannot see it break.
It has been outside every green run this entire project. That is the same hollow-instrument shape as
R19, one target over.

Report: whether the target's Sources list still matches the files on disk; whether anything it reads
has drifted from the current SwiftData models — a renamed property, a changed optionality, a model
it does not know about; and whether it is included in the submitted app bundle or genuinely
separate. If it ships inside the app, its correctness is a review concern; if it does not, say so
and I will stop treating it as one.

State plainly whether you can determine it compiles without building it, and do not guess.

ANSWER 2026-09-04:

```text
Tree read: a3068e3
Dirty files: 29
```

**Static membership and schema checks pass. I cannot determine that the target compiles without
building it, and I did not build it.**

### Measured static result

- `CadenceMCPServer` is a standalone command-line target (`project.pbxproj:454-471`). The Cadence app
  embeds and depends on `CadenceWidgets`, not the MCP executable (`project.pbxproj:120-128`). **It is
  genuinely separate and is not an App Review binary concern.**
- Its explicit Sources phase contains **43 unique Swift entries**, all 43 paths exist, and all four
  files under `CadenceMCPServer/` are present (`project.pbxproj:604-652`). There are no orphaned MCP
  server source files or missing listed files.
- The model tree declares **21 `@Model` types**. `CadenceSchema.schema` contains all 21 exactly once
  (`CadenceSchema.swift:4-26`), and every declaring model file is in the MCP Sources phase.
- MCP read-only and read-write containers both construct against that exact shared schema
  (`CadenceModelContainerFactory.swift:68-102`). There is no second MCP-owned schema to drift.
- The tool surface still names tasks, Blocks, contexts, containers, tags, all note/document kinds,
  goals, habits and links, plus write tools for task lifecycle and core-note append
  (`CadenceMCPToolDefinitions.swift:61-224`). No current model family is silently absent from the
  compiled source inventory.
- Neither `7e58fc6` nor `a3068e3` changed a model property or MCP source. A targeted reference read
  found no renamed-property or optionality mismatch in the current MCP DTO/service code.

That last point is **source-measured but not compiler-measured**. It cannot catch a Swift type-check,
actor-isolation, extension-membership, linker or deployment-setting failure. A source list that
looks complete is necessary evidence, not a compile result.

### Existing work

Do not file a duplicate. T-435 already records the honest closure: CI must build
`-scheme CadenceMCPServer` directly (`docs/TODO.md:4753-4759`). Its source guard was strengthened,
but the direct CI lane remains open. The current audit changes neither its premise nor its fix.

Thirty-second static confirmation:

```sh
sed -n '604,652p' Cadence.xcodeproj/project.pbxproj
find CadenceMCPServer -name '*.swift' -print | sort
sed -n '4,26p' Cadence/Services/CadenceSchema.swift
```

Compiler confirmation, deliberately **not run** here:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Cadence.xcodeproj -scheme CadenceMCPServer \
  -derivedDataPath /tmp/cadence-mcp-verify build
```

**Looks solid:** sharing `CadenceSchema.schema` between app and MCP container construction removes
the most dangerous drift class, and the explicit target currently includes every model declaration.
The server's separation from the submitted app means an MCP-only defect does not block App Store
review, though it still blocks an honest MCP release.

**Not checked:** compilation, linking, execution, store opening, tool round trips, build warnings, or
the commit message's earlier MCP-build claim.

## R30 — Contrast and Dynamic Type against the theme tokens

Every colour in this app comes from `Theme.swift` by repo rule, which makes contrast checkable
arithmetically rather than by eye — a rare case where a read-only audit can settle an accessibility
question properly.

Compute the WCAG contrast ratio for every foreground/background token pair the app actually uses, in
both light and dark. Report pairs below 4.5:1 for body text and below 3:1 for large text and control
glyphs, with the token names and where the pair is used. Secondary and dimmed text is where this
usually fails, and `Theme.dim` on a tinted background is the specific case I would check first.

Separately: does any user-facing text use a fixed point size instead of a Dynamic Type text style?
List those sites. A fixed 12pt label is unreadable to a user who has raised their system text size,
and it is invisible to every test we have.

ANSWER 2026-09-04:

```text
Tree read: a3068e3
Dirty files: 29
```

**Premise correction:** Cadence has no light appearance. `Theme.preferredColorScheme` is fixed to
`.dark`, and the source explicitly says there is one neutral ramp (`Theme.swift:8-15,245-259,378-379`).
There is therefore no honest light-mode result to report. Source also cannot prove every inherited,
opacity-composited or user-owned `colorHex` pair, but the named direct token families already expose
three systemic failures.

Ratios below are WCAG relative-luminance calculations from the committed sRGB hex values.

### Neutral foregrounds

| Foreground | `bg` | `surface` | `surfaceElevated` | `surfaceHighlight` | Result |
|---|---:|---:|---:|---:|---|
| `text` | 17.02 | 15.86 | 14.84 | 14.05 | Pass |
| `muted` | 7.76 | 7.24 | 6.77 | 6.41 | Pass |
| `subdued` | 6.70 | 6.24 | 5.84 | 5.53 | Pass |
| `dim` | **4.12** | **3.84** | **3.59** | **3.40** | **Fails 4.5 for body text everywhere**; full-strength only passes the 3.0 large-text/control floor. |

`Theme.dim.opacity(0.85)` falls to 3.26/3.11/2.96 on bg/surface/elevated; at 0.82 it is
3.11/2.98/2.84, and at 0.76 or below it is under 3 even on bg. The app has **32 direct dim-opacity
foreground sites**. Reachable failures include active task secondary text
(`iOSTaskViews.swift:209-214`), Add Subtask (`CreateTaskSheet.swift:210-219`), row remove glyphs
(`CreateTaskSheet.swift:188-203`; `TasksPanelSupportViews.swift:108,126`), Focus separators
(`FocusChromeSupportViews.swift:53-57`), habit completion glyphs
(`HabitsSupportViews.swift:89`; `iOSFeatureDetailViews.swift:445`) and the shared empty-state glyph
(`EmptyStateView.swift:17-19`). Disabled-only controls are WCAG-exempt and were not used to make the
finding.

### Foregrounds on colored fills

`Theme.onColor` is white at 26 foreground sites; `onColorSecondary` is white at 75% at one direct
site (`Theme.swift:404-416`). Opaque white contrast against every selectable accent is:

| Palette | blue | red | green | amber | purple | teal |
|---|---:|---:|---:|---:|---:|---:|
| Cadence | **2.75** | **2.78** | **2.08** | **1.90** | **2.72** | **1.98** |
| Ember | 3.23 | 3.05 | **2.11** | **2.38** | **2.64** | **2.44** |
| Glacier | **2.21** | **2.50** | **2.00** | **1.54** | **2.73** | **1.75** |

Every value fails 4.5 for ordinary text; all but Ember blue/red also fail 3.0 for large text and
control glyphs. The 75% secondary token is necessarily worse. **Can this happen today? Yes:** the
pair is visible on the iOS floating create button (`iOSFloatingCreateTaskButton.swift:46-52`), the
macOS Today add button (`TasksPanelSupportViews.swift:61-70`), 11pt red Delete buttons
(`SettingsSupportViews.swift:213-220,418-425`), tag/context chips
(`TaskTitleEntryField.swift:222-227,270-275`) and 10pt calendar chips
(`CalendarPageMonthSupportViews.swift:193-203,512-520`). User-selected colors make a constant-white
foreground still less defensible because their contrast is unbounded.

The marker pair is worse: `markerHighlightText #fff4c2` on `markerHighlightFill #f6c343` is
**1.48:1** (`Theme.swift:314-316`; `MarkdownEditorSupport.swift:219-221`). Highlighted Markdown text
is therefore a live body-text failure.

### Dynamic Type

This is systemic, not a handful of labels. **MEASURED:** `Cadence/` contains **1,257**
`.font(.system(size: ...))` modifiers across **180 Swift files**, **zero** Dynamic Type style font
modifiers (`.body`, `.headline`, `.caption`, etc.), and no `@ScaledMetric`, `UIFontMetrics` or
`.dynamicTypeSize` adoption. A structural classification found at least **891 user-facing
Text/Button/Label/field sites in 175 files**; the remainder are mostly icon geometry. Listing 891
lines inline would make this handoff materially harder to use, so the exhaustive line ledger is the
first confirming command below. The highest concentrations are:

```text
26  Cadence/macOS/Views/GoalsSupportViews.swift
25  Cadence/macOS/Views/SettingsSectionViews.swift
25  Cadence/iOS/iOSMarkdownPreview.swift
24  Cadence/macOS/Views/SettingsSupportViews.swift
24  Cadence/macOS/Views/QuickCreateChoiceSupportViews.swift
21  Cadence/macOS/Views/TasksPanelSupportViews.swift
19  Cadence/macOS/Views/KanbanColumnSupportViews.swift
18  Cadence/iOS/iOSSettingsTemplateAndListSections.swift
18  Cadence/iOS/iOSFeatureDetailViews.swift
17  Cadence/macOS/Views/HabitsSupportViews.swift
17  Cadence/iOS/iOSTodaySchedulePanel.swift
17  Cadence/iOS/iOSCalendarSettingsSection.swift
16  Cadence/macOS/Views/SettingsListManagementSections.swift
16  Cadence/macOS/Views/FocusLogSessionPopovers.swift
16  Cadence/iOS/iOSCalendarTimelineViews.swift
```

**Can this happen today? Yes.** On iOS, raising the system content-size category does not turn these
fixed points into semantic Dynamic Type styles. This is an app-wide accessibility architecture gap,
not a one-screen defect.

### Suggested fix and order

1. Replace `onColor` with a contrast-resolving foreground. App-owned bright accents can use a dark
   foreground; user-owned colors need black/white selection from measured luminance. Pin every
   palette stop at 4.5 for text and 3.0 for glyphs.
2. Change marker-highlight text to a dark token that reaches 4.5 against the yellow fill.
3. Reserve `dim` for disabled/decorative content. Promote readable captions to `subdued` or `muted`
   and remove alpha from semantic text/control glyphs.
4. Introduce a small semantic typography layer backed by Dynamic Type styles, then migrate by shared
   components first: settings fields/cards, page/pane headers, task rows, editor accessories, and
   only then leaf views. Use `@ScaledMetric(relativeTo:)` where fixed geometry must track text.

Thirty-second confirmation:

```sh
rg -n '\.font\(\.system\(size:' Cadence --glob '*.swift'
rg -n '\.font\(\.(body|headline|caption|footnote)|@ScaledMetric|\.dynamicTypeSize' Cadence --glob '*.swift'
rg -n 'foregroundStyle\(Theme\.(onColor|dim)' Cadence --glob '*.swift'
```

**Looks solid:** `text`, `muted` and `subdued` all clear 4.5 on every neutral surface stop, often by
a wide margin. App accent colors used *as foregrounds on the dark neutral ramp* are also strong; the
failure is specifically the reversed white-on-bright-fill contract and over-dimmed content.

**Not checked:** no Accessibility Inspector, Increase Contrast mode, screenshot sampling,
user-selected color corpus, build, tests, or visual Dynamic Type run. Ratios are measured; actual
pair reachability is source-derived where cited and cannot account for arbitrary SwiftUI compositing.

<!-- FOLDED-THROUGH: R24 -->
