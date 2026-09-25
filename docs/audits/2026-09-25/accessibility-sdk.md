# Text Scaling and SDK Boundaries: R57, R60

```text
Tree read: c8735e4
Dirty files: 23 at capture
Source: clean committed snapshot; excluded in-flight changes to framework-sensitive tests
Mode: source inventory and Apple documentation research, 2026-09-25
No build, tests, accessibility audit, simulator, or second-toolchain run
MEASURED-SOURCE / DOCUMENTED / REASONED are separate from severity
```

## R57: Text Scaling

**MEASURED-SOURCE premise correction:** the exact raw patterns now return 1,294 `.system(size:`
occurrences, **1,160 with numeric literals**, zero `ScaledMetric`, zero `dynamicTypeSize`, and 145
`.accessibilityLabel` modifier occurrences under `Cadence/`. The request's 253 label count uses a
different/older population. No direct `.font(.body)`-style call matches the inventory's narrow
semantic-style pattern. Counts include strings/comments and are not an AST count of visible text.
[Reproducible script and full metadata](queue_inventory.rb).

**REASONED:** there is a large real scaling gap, but "every text anywhere is fixed" overstates this
scan. Native controls may inherit system typography without spelling either searched pattern.
Labels count naming sites, not usable VoiceOver navigation or Dynamic Type support.

### Requirement Versus Quality

**DOCUMENTED:** Apple recommends supporting substantially enlarged text, ideally at least 200%,
with readable layouts and scaled meaningful icons. Semantic text styles are the default starting
point, not a requirement to erase a custom type scale.
[Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility),
[Typography HIG](https://developer.apple.com/design/human-interface-guidelines/typography).

The **App Store Larger Text accessibility label** has concrete evaluation criteria: test common
tasks at larger sizes without unusable clipping/overlap. A custom text-size mechanism can qualify;
using Dynamic Type APIs alone does not establish qualification. This is a requirement for making
that support claim, not evidence that every fixed font automatically causes rejection.
[Apple's Larger Text evaluation](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria).

I found no blanket rule in the App Review Guidelines that makes every `.system(size:)` call an
automatic rejection. General usability and accurate representations still apply. This report is
not legal advice or a guarantee of approval. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

### Migration Shape

**REASONED recommendation: a mix, by role and surface, not 1,160 substitutions.**

1. Define semantic typography roles around existing shared metrics: row title, secondary metadata,
   field value, section label, calendar label. Use native semantic styles where their hierarchy fits.
2. For intentional custom baselines, scale relative to an appropriate text style through
   environment-aware view properties/modifiers (`@ScaledMetric` where supported). A static global
   `Theme` number cannot observe each view's text-size environment. Keep colors in Theme; avoid a
   second disconnected set of font literals masquerading as tokens.
3. Native text editors need their own font/layout update path, not only a SwiftUI `.font` modifier.
   UIKit custom fonts can use UIFontMetrics; do not assume iOS Dynamic Type automatically supplies
   a system-wide Mac app text-zoom policy. Define and verify Mac behavior separately.
4. Change vertical layout with the typography: minimum rather than rigid heights, wrapping for
   important content, and stacked value/control layouts at accessibility sizes. Keep hit targets
   usable and preserve access to full content through detail surfaces.

### Likely First Failures, Not Reproduced Failures

| Source hotspot | Why naive scaling is risky | Existing tests to extend / expectation |
| --- | --- | --- |
| `Cadence/iOS/iOSCalendarChromeViews.swift:29`; `iOSCalendarMonthAgendaViews.swift:520,550` | 44pt chrome and bounded month-cell rows; badges/title fonts grow inside fixed geometry | `iOSCalendarMetricsTests`, `CalendarBoardCompactLayoutTests`: metrics can pass while glyphs overlap. Add largest-size rendering checks, not just new constants. |
| `Cadence/iOS/iOSCalendarMetrics.swift:49`; `Cadence/macOS/Views/TimelineMetrics.swift:22,51,55` | Points/minute, positions and block heights form one coordinate system | `TimelineMetricsTests`: if changing hourHeight, update drawing, hit testing and drag conversions together. Enlarging only text does not require changing time math; offer an accessible agenda/detail route. |
| `Cadence/macOS/Views/TimelineTaskBlock.swift:242`; `TimelineTaskBlockSupportViews.swift:187,249` | One/two-line labels, minimumScaleFactor and short fixed-duration blocks fight enlarged text | Test short events at large sizes; shrinking text back to fit defeats the feature. Full text must remain reachable. |
| `CadenceTests/CadenceTaskComposerLayoutTests.swift:22,59` and the production layout it exercises | Keyboard-visible budget and value-tile font-height arithmetic assume baseline sizes | These assertions require a size-aware model if metrics change. If only rendered fonts change, tests may stay green while the composer clips. |
| `CadenceTests/DateFormatterSupportTests.swift:386,436` | System-font widths compared to fixed calendar rail budgets | Larger labels can exceed widths. Preserve text containment as the invariant; baseline font metrics are not a cross-size guarantee. |

**REASONED device impact:** iPhone 15 at 393x852 has the tightest width and keyboard budget; large
sizes need vertical reflow and full-screen/scrolling forms. iPad has room until split/inspector modes
narrow the pane; test its narrowest supported pane, not only full-screen portrait. The owner's
full-screen Mac still has bounded sidebar, rail and inspector widths. More total screen area does
not fix those local constraints.

The radius sweeps do **not necessarily go red** when fonts change: typography and corner radius
are different invariants. Literal font/height assertions may need updating; untouched baseline
metric tests can instead remain green and miss the regression. No unrun test is reported as failing.

### Cheap Partial and Acceptance

**Recommendation:** ship one complete readable workflow first: task title/body/detail and its create
form, plus settings. Include its navigation, controls, error messages and completion path. Then rows
and inspector; then calendar agenda. This is better than no scaling when the whole selected workflow
remains usable. A random handful of enlarged labels inside rigid controls is not that partial.

Keep dense calendar time geometry stable initially and provide a genuinely readable agenda/details
path; do not claim Larger Text support for all common tasks before testing them. The native editor
font bridge needs an explicit decision rather than being silently excluded.

VoiceOver also needs sensible reading order, grouping, roles, selected/expanded state, focus after
navigation/mutation, meaningful values and non-drag actions. Label sweeps cannot establish those.
Apple's audit tools help find clipping/traits but do not certify a complete experience.
[Accessibility audit guidance](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app).

**Suggested patch order:** role inventory and one environment-driven token adapter; one complete
workflow; layout/keyboard tests at default and largest supported sizes; VoiceOver traversal; expand
to row/calendar surfaces. Verify actual rendered text at the three requested device configurations,
with long content and the keyboard. No screenshots or runtime audit were taken for this answer.

**Looks solid:** shared calendar/task metrics and the existing label sweeps provide central adoption
points. Keep those names and their non-vacuity checks; add size-sensitive behavior rather than replacing
them with a fresh global typography framework.

## R60: What Apple Documents About 26 to 27

**Conclusion:** none of the exact empirical assertion values listed by T-1318 is established as
changed, or guaranteed stable, by the public documents checked. There are documented nearby changes;
they must not be substituted for evidence about these particular assertions. The request's "nine"
groups several source locations into seven behavior families below.

### Documented Changes and Stable Contract

**DOCUMENTED:** iOS/macOS 27 fix a SwiftData `@Query` deadlock involving background-context saves
and ModelActor scheduling (178113288). That is not a statement about rollback reference visibility
or synchronous inverse population.
[iOS/iPadOS 27 notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes),
[macOS 27 notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).

AppKit 27 changes NSTextView selection handling to NSTextSelectionManager, with a compatibility path
for mouseDown overrides; it also has text-field clipping and focus fixes. Those are relevant to
editor testing, but not a promised new attachment-fragment tolerance or system-font width. The
same macOS notes distinguish runtime behavior from some changes gated on the linked SDK.

Xcode 27 supplies Swift 6.4 and the 27 SDKs; its documented compiler/tooling and deprecation changes
do not specify these storage/layout observation values.
[Xcode 27 notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes).

**DOCUMENTED contract, not an observation sequence:** rollback discards pending inserts/deletes and
restores changed models to their last committed values. Do not relabel restoration itself as
undefined just because timing/reference behavior differs in recorded tests.
[ModelContext.rollback](https://developer.apple.com/documentation/swiftdata/modelcontext/rollback()).
The earlier [R65 source/release-note report](../2026-09-22/sync-rollback/rollback.md) reviewed the six
major 26/27 OS/Xcode notes; this pass fetched current 27 Markdown directly from Apple, including
the SwiftData and AppKit sections. Absence from these notes is a bounded negative, not an API-diff
proof covering every symbol, minor release, or Apple implementation detail.

### Exact Test Map

All test paths below are under `CadenceTests/`, **at c8735e4**. Local working edits are excluded.

| Family / source | Classification | Keep strict / measure separately |
| --- | --- | --- |
| `CadenceSubtaskInverseParityTests.swift:409,425,442` | **REPO-RECORDED difference nearby; exact assertions need both environments** | Correct persisted ownership and no duplicate/order corruption / immediate inverse-array contents before save/fetch |
| `CadenceTaskInspectorHostTests.swift:123,134`, `CadenceBundleInspectorHostTests.swift:91` | **Empirical**; no matching documented lifecycle-signal order change found | Inspector closes for invalid/deleted subject / which signal arrives first |
| `CadenceListCascadeRollbackTests.swift:80,123`, `CadencePendingChangePersistenceTests.swift:134` | **Documented rollback contract; empirical reference visibility** | Original data and unrelated pending work preserved / already-held reference, live relationship, same-context fetch, fresh-context fetch observations |
| `CadenceHabitCompletionDuplicateTests.swift:362` | **Empirical** captured-array restoration | Refused uncheck retains completion and correct displayed state / whether a previously captured array reflects restoration |
| `DateFormatterSupportTests.swift:44` | **Empirical** parser leniency | App accepts/rejects and emits canonical keys as specified / Foundation accepting noncanonical input |
| `MarkdownEditorImageRelayoutTests.swift:217,321` | **Empirical** native layout/tolerance | No image/prose overlap and correct resize relayout / exact framework fragment rounding |
| `DateFormatterSupportTests.swift:386,436` | **Empirical** font widths | Readable, contained rail labels / exact glyph advance within a fixed baseline budget |

No row warrants preemptively weakening the product invariant. R61 separately identifies a diagnostic
oracle that is too broad and a missing strict synthetic error fixture; consume that existing answer
rather than file it again.

### Is Another Toolchain Worth It?

**REASONED:** first harvest the existing CI-26 and local-27 observations at **one identical commit**.
Record Xcode build, SDK, runtime OS build, architecture, locale, timezone and storage configuration.
CI selects major 26, not a verified fixed minor. A second Xcode on the same Mac does not recreate
an older SwiftData/AppKit runtime; for these behaviors a runtime matrix matters as much as a compiler.

Cheapest useful probes are small existing suites, not two full app test runs: inverse assignment
before save, after save, after same-context fetch and fresh-context fetch; rollback of insert/edit/delete
with held references; editor attachment geometry before/after resize with no keystroke. Log observed
values alongside strict app invariants. Preserve the test-host lock on each host and TZ=UTC policy.

Only buy the second installation/runtime when that controlled comparison leaves a real unsupported
configuration unanswered. Public release notes do not settle the current candidates by themselves.
**No cross-toolchain execution or complete installed-SDK binary/API diff was performed here.**

Confirm source boundary:
```sh
git show c8735e4:docs/TODO.md | rg -n '^\s*- \[T-(1279|1296|1318)\]'
git show c8735e4:CadenceTests/DateFormatterSupportTests.swift | sed -n '35,58p;380,450p'
git show c8735e4:.github/scripts/assert-toolchain.sh
```
