import Foundation
import Testing
@testable import Cadence

/// **The control-accessibility rules the tooltip sweep cannot reach** (T-611, widened by T-637,
/// renamed by T-678).
///
/// `CadenceControlAccessibilityLabelTests` carries the app's widest rule, and it keys on
/// `.help(…)`. That modifier does not exist on iOS, so that sweep is *structurally* blind to
/// `Cadence/iOS/`: it reports zero offenders there and would do so if every button on the phone
/// were unnamed. `theTooltipSweepFindsNothingOnATreeThatCannotDrawTooltips` below states that as a
/// measurement rather than leaving it as an assumption.
///
/// **The icon-only rule below is app-wide** — T-611 seeded it here because that was the tree with
/// no rule at all, and scoped it to `Cadence/iOS/` for a reason that has since expired: T-610 was
/// rewriting `knownUnnamedTooltipSites` over the same file set at the time, and two exact ledgers
/// over one moving file set means every tooltip fix has to edit both. T-610 settled at one entry,
/// so T-637 widened the sweep to `Cadence/`, and **T-678 renamed the suite to match** once the two
/// widenings stopped colliding — the file kept its iOS-only name for one batch on purpose, stated
/// in its own header rather than left silent, and this is that rename landing. A `.help` tooltip is
/// a pointer affordance; it is not an accessible name, which is why the same control can be clean
/// under one rule and an offender under the other.
///
/// Its own file rather than a section of the other one, because these two suites are edited by
/// different tickets at the same time and share nothing but the reading helpers.
///
/// Same limit as the other suite, and it is the point: these assert that a *name is set*, in the
/// shape SwiftUI reads it from. They do not assert what VoiceOver announces — nothing in this
/// target launches the app, so an announcement is not a fact any test here has measured.
///
/// **Deliberately not `@MainActor`.** Everything below is source text and `nonisolated` values.
struct CadenceIconOnlyButtonAccessibilityTests {

    /// **The sites this rule has not reached yet, by file and count, with the ticket that owns each.**
    ///
    /// A `Button` whose entire label is a bare `Image` has no visible text for VoiceOver to fall
    /// back on, so it must state a name. Seeded by T-611 over `Cadence/iOS/`; widened to the whole
    /// app by T-637, which measured **31 sites in 24 files** — 28 of them macOS, and 22 of the 24
    /// files. The macOS remainder is largely the *same controls* `knownUnnamedTooltipSites` tracked
    /// until T-610 emptied it: they gained a `.help` string and are still nameless as bare glyphs.
    ///
    /// Exact, like the tooltip ledger and for the same reason: a new one fails, and so does a stale
    /// entry, so fixing one means deleting its line in the same change. The number is meant to go
    /// down.
    ///
    /// **T-637 ledgered rather than fixed**, deliberately: the 31 are spread over 24 files that
    /// three agents were editing in the same batch, and a widening that lands with an exact ledger
    /// is a complete deliverable on its own. The three follow-ups are grouped by *fix shape*, not
    /// by folder, because the same shape repeats across folders:
    ///
    /// - **T-672 — the search field's clear button, ten near-copies (10 sites, 10 files). CLOSED.**
    ///   The identical `if !query.isEmpty { Button { query = "" } label: { Image("xmark.circle.fill") } }`
    ///   in ten pickers, now one `CadenceSearchFieldClearButton` that names itself — a duplication
    ///   finding that a naming rule found, so it was fixed as one. An *eleventh* copy was in the
    ///   tree and not in this ledger: `FocusPickerSupportViews`' clear button already carried
    ///   `.cadenceControlLabel("Clear search")`, so no naming rule could see it, and leaving it
    ///   hand-spelled would have left the near-copy this ticket exists to remove. It migrated too.
    ///   `CadenceSearchFieldClearButtonTests` pins the call sites, which is what a rule on the
    ///   component alone would miss.
    /// - **T-673 — a row's own glyph never says which row (8 sites, 5 files).** Six `xmark`
    ///   removals (a subtask, a picked task, a detached goal link) and two completion circles. The
    ///   T-594 shape: the action is guessable from the glyph and the *subject* is not, so the name
    ///   has to carry the item.
    /// - **T-674 — icon-only helpers and chrome, 10 sites in 9 files. CLOSED.** Steppers, timeline
    ///   navigation, and four private `iconButton`-shaped helpers that took a symbol and no name.
    ///   Four helpers (`stepButton`, `timelineNavButton`, `actionButton`, `focusRowIconButton`) and
    ///   `ListEditorIconCell` now take the name as a `let` with no default — T-611's compile gate,
    ///   not a label at each call site, so the next caller fails to build rather than fails a
    ///   sweep. `TimelineZoomControl`'s two inline buttons and the picker's back chevron carry
    ///   `.cadenceControlLabel(…)` directly, having no shared helper to carry it for them.
    ///
    /// The three iOS entries stay with **T-611**, which filed them.
    ///
    /// **`Cadence/iOS/iOSTaskRowActionViews.swift` is absent, and that is the finding T-611 did not
    /// expect.** The ticket read "1 accessibility label across 25 buttons"; 24 of those 25 are
    /// context-menu items spelled `Label(text, systemImage:)`, which name themselves. The file has
    /// **no** icon-only button at all. Its real gap was the opposite shape — a chip that draws a
    /// *value* and never says which field the value belongs to — and no rule about button labels can
    /// see that one, which is why `iOSTaskAttributeChip.field` is a required initialiser parameter
    /// rather than a third sweep here. `aMenuItemSpelledAsALabelIsNotAnIconOnlyButton` pins that
    /// distinction on a literal, so the count above cannot be inflated by self-naming labels.
    private static let knownUnnamedIconButtonSites: [String: Int] = [
        "Cadence/iOS/iOSMarkdownPreview.swift": 2,                          // T-611
        "Cadence/iOS/iOSTaskDetailSheet.swift": 1,                          // T-611
        "Cadence/macOS/Sheets/CreateTaskSheet.swift": 1,                    // T-673
        "Cadence/macOS/Views/GoalsSupportViews.swift": 2,                   // T-673 (detach ×2)
        "Cadence/macOS/Views/HabitsSupportViews.swift": 1,                  // T-673 (done circle)
        "Cadence/macOS/Views/QuickCreateChoiceSupportViews.swift": 2,       // T-673 (remove ×2)
        "Cadence/macOS/Views/TasksPanelSupportViews.swift": 2,              // T-673 ×2
    ]

    @Test func noIconOnlyButtonInTheAppIsLeftWithoutAnAccessibleName() throws {
        let offenders = try unnamedIconButtonInstrument().sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            // 565 files at the time of writing; the floor only rules out a walk that found one
            // folder and called it the app.
            atLeast: 400,
            // A *macOS* witness, and that is T-637's widening stated as a compile-checked
            // argument: under T-611's `Cadence/iOS` walk this path is not in the list at all and
            // the sweep throws `walkMissedItsWitness` before it counts anything.
            including: "Cadence/macOS/Views/TasksPanelSupportViews.swift",
            read: CadenceSourceScan.sourceFile
        )

        let unexpected = Set(offenders).subtracting(Self.knownUnnamedIconButtonSites.keys)
        #expect(
            unexpected.isEmpty,
            """
            \(unexpected.sorted()) draws a Button whose whole label is an Image and states no \
            name. Add .accessibilityLabel(…) (T-611/T-637).
            """
        )
        let fixed = Set(Self.knownUnnamedIconButtonSites.keys).subtracting(offenders)
        #expect(
            fixed.isEmpty,
            "\(fixed.sorted()) no longer has an unnamed icon-only button — delete its line from knownUnnamedIconButtonSites"
        )
    }

    /// The ledger's *numbers*, not only its paths — a file with two that loses one is still an
    /// offender, so path-level equality above would not notice the one.
    @Test func theUnnamedIconButtonLedgerStatesHowManySitesEachFileStillHas() throws {
        var actual: [String: Int] = [:]
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let count = Self.unnamedIconButtonCount(in: try CadenceSourceScan.sourceFile(path))
            if count > 0 { actual[path] = count }
        }
        #expect(actual == Self.knownUnnamedIconButtonSites, "measured: \(actual.sorted { $0.key < $1.key })")
        // The headline, so the report and the ledger cannot disagree: T-637 measured 31 in 24,
        // T-672 closed 10 of them in 10 files, and T-674 closed a further 10 sites in 9 files —
        // all nine left the ledger outright, T-674's population having no site shared with T-672.
        #expect(actual.values.reduce(0, +) == 11)
        #expect(actual.count == 7)
        // And the file the ticket was filed about is clean — see the ledger's own note.
        #expect(actual["Cadence/iOS/iOSTaskRowActionViews.swift"] == nil)
    }

    /// **The split T-637 widened into, as a number rather than a claim.**
    ///
    /// The whole deliverable of that ticket is *reach*: T-611's sweep read 105 files and found 3,
    /// and the same detector over 565 finds 31. Both halves are asserted, because either one alone
    /// would survive the widening being reverted — the iOS total is unchanged by it, and a bare
    /// app-wide total does not say the extra 28 are somewhere new.
    @Test func theIconOnlyRuleReachesTheDesktopTreeAndNotOnlyTheTouchTree() throws {
        let ledger = Self.knownUnnamedIconButtonSites
        let touch = ledger.filter { $0.key.hasPrefix("Cadence/iOS/") }
        let desktop = ledger.filter { $0.key.hasPrefix("Cadence/macOS/") }

        // T-611's population, unchanged: 3 sites in 2 files.
        #expect(touch.values.reduce(0, +) == 3)
        #expect(touch.count == 2)
        // T-637's: 28 sites in 22 files that the iOS-scoped walk could not see, less T-672's 10
        // and T-674's 10.
        #expect(desktop.values.reduce(0, +) == 8)
        #expect(desktop.count == 5)
        // Nothing else — `Cadence/Shared/`, `Models/` and `Services/` are swept and clean, which
        // is a measurement of those trees, not an exclusion of them.
        #expect(touch.count + desktop.count == ledger.count)

        // And the walk really does hand the sweep all three trees, not just the two with offenders.
        let walked = Set(try CadenceSourceScan.swiftFiles(under: "Cadence"))
        for witness in [
            "Cadence/iOS/iOSTaskRowActionViews.swift",
            "Cadence/macOS/Views/TasksPanelSupportViews.swift",
            "Cadence/Shared/CadenceRootShellLayout.swift",
            "Cadence/Services/CadenceSchema.swift",
        ] {
            #expect(walked.contains(witness), "the app-wide walk missed \(witness)")
        }
    }

    /// **A `Label(_:systemImage:)` names itself, and the count above must not be inflated by one.**
    ///
    /// Pinned on a literal rather than on a file, because the file that taught T-611 this
    /// (`iOSTaskRowActionViews.swift`) can lose its menu at any time and take the evidence with it.
    /// The mistake it guards is a real one: "1 accessibility label across 25 buttons" was the
    /// original T-611 report, and 24 of the 25 were self-naming menu items.
    @Test func aMenuItemSpelledAsALabelIsNotAnIconOnlyButton() throws {
        let instrument = try unnamedIconButtonInstrument()

        #expect(
            instrument.fires(on: """
            Button(role: .destructive) {
                delete()
            } label: {
                Label("Delete task", systemImage: "trash")
            }
            """) == false,
            "a Label(_:systemImage:) menu item is being counted as an unnamed icon-only button"
        )
        // The same call with the label swapped for a bare glyph *is* one, so the negative above is
        // about `Label` and not about the surrounding shape.
        #expect(
            instrument.fires(on: """
            Button(role: .destructive) {
                delete()
            } label: {
                Image(systemName: "trash")
            }
            """),
            "non-vacuity: the detector does not fire on the bare-glyph twin either"
        )
    }

    /// **The tooltip sweep really is blind here**, which is the whole reason this rule exists.
    /// Stated rather than assumed: it reads all 105 iOS files and reports nothing, because none of
    /// them can carry the `.help` it keys on.
    @Test func theTooltipSweepFindsNothingOnATreeThatCannotDrawTooltips() throws {
        var tooltipOffenders = 0
        var iconOffenders = 0
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/iOS") {
            let source = try CadenceSourceScan.sourceFile(path)
            tooltipOffenders += CadenceControlAccessibilityLabelTests.unnamedTooltipCount(in: source)
            iconOffenders += Self.unnamedIconButtonCount(in: source)
        }
        #expect(tooltipOffenders == 0)
        #expect(iconOffenders > 0, "non-vacuity: neither rule read anything")
    }

    /// The detector, against the tree on both sides, plus the two shapes it must not confuse: a
    /// `Button` with a visible title, and one already named.
    @Test func theIconOnlyButtonDetectorSeesABareGlyphAndLeavesALabelledOneAlone() throws {
        let instrument = try unnamedIconButtonInstrument()

        let offending = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheet.swift")
        #expect(instrument.fires(on: offending), "the detector cannot see an unnamed icon-only button")

        // T-637's half: the same detector, on a file T-611's walk never handed it.
        let desktop = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift")
        #expect(instrument.fires(on: desktop), "the detector cannot see the desktop tree's bare glyphs")

        let clean = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift")
        #expect(clean.contains("Button {"), "non-vacuity: the row's buttons are gone")
        #expect(instrument.fires(on: clean) == false, "a Label(_:systemImage:) reads as unnamed")

        // A glyph beside text is not an icon-only control — there is something for VoiceOver to
        // read — and neither is a `Button` handed its own title.
        #expect(
            instrument.fires(on: """
            Button(action: action) {
                HStack {
                    Image(systemName: systemName)
                    Text(title)
                }
            }
            """) == false,
            "the detector fires on a button that draws its own text"
        )
    }

    /// **A tooltip is not a name, stated as a fixture** — which is the premise T-637 rests on.
    ///
    /// The ledger's claim is that most of the 28 macOS sites are controls `knownUnnamedTooltipSites`
    /// released: they took a `.help(…)` and are clean under *that* rule while still announcing
    /// nothing as a bare glyph. If this detector treated `.help` as a name, widening it would have
    /// found almost none of them and the empty result would have read as good news.
    @Test func aTooltipIsNotAnAccessibleNameForABareGlyph() throws {
        let instrument = try unnamedIconButtonInstrument()

        #expect(
            instrument.fires(on: """
            Button(action: action) {
                Image(systemName: "trash")
            }
            .buttonStyle(.cadencePlain)
            .help("Delete task")
            """),
            "a `.help` tooltip is being accepted as an accessible name"
        )
        // `.cadenceControlLabel` is the modifier that sets *both* from one string, so it — and only
        // it — clears the control.
        #expect(
            instrument.fires(on: """
            Button(action: action) {
                Image(systemName: "trash")
            }
            .buttonStyle(.cadencePlain)
            .cadenceControlLabel("Delete task")
            """) == false,
            "the shared name-and-tooltip modifier reads as unnamed"
        )
    }

    /// **The chip cannot be drawn without naming its field, and that is a compile failure rather
    /// than a rule (T-611).**
    ///
    /// The scan above is blind to this defect and always would be: every one of these chips draws
    /// visible text, so a label-shaped rule reads them as named. What they never said is *which
    /// field* the text is a value of — "Tomorrow" on the do chip and "Tomorrow" on the due chip
    /// announce identically. macOS's row hit the same wall in T-594, which is why it pins its six
    /// controls by name and value here instead of leaving them to a sweep.
    ///
    /// iOS gets the stronger version, because it has one shared component where macOS had six
    /// separate call sites: `field` is a `let` with no default, so the eighth chip does not fail a
    /// test, it fails to build.
    @Test func theSharedIOSChipCannotBeBuiltWithoutNamingItsField() throws {
        let component = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailComponents.swift")
        )
        #expect(component.contains("struct iOSTaskAttributeChip: View"), "non-vacuity: wrong file read")

        // A `let` with no initialiser: the memberwise initialiser therefore requires it.
        #expect(component.contains("let field: String"))
        #expect(!component.contains("var field: String"), "the field name gained a default")
        #expect(component.contains(".accessibilityLabel(field)"))
        #expect(component.contains(".accessibilityValue(title)"))
        // The hint stays. It says what activating does; it never said what the control is.
        #expect(component.contains(#".accessibilityHint("Opens a picker")"#))
    }

    /// The words themselves, and that every chip takes one of the shared ones.
    ///
    /// Value assertions rather than a scan, for T-594's reason: what is wrong with these controls
    /// is not visible in the shape of the call, only in which string it passes. Sweeping the call
    /// sites for `field:` would pass on `field: "Date"` typed twice, differently.
    @Test func everyChipOnTheIOSTaskRowNamesItsFieldFromTheSharedWords() throws {
        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskRowActionViews.swift")
        )
        #expect(row.contains("struct iOSTaskRowDateChip: View"), "non-vacuity: wrong file read")

        for word in [
            "CadenceTaskControlAccessibility.list",
            "CadenceTaskControlAccessibility.recurrence",
            "CadenceTaskControlAccessibility.milestone",
            "CadenceTaskControlAccessibility.estimate",
        ] {
            #expect(row.contains("field: \(word)"), "\(word) is not on the row")
        }
        // The two date chips are one component, so the name comes off the field enum.
        #expect(row.contains("field: field.accessibilityLabel"))
        #expect(row.contains("case .doDate: return CadenceTaskControlAccessibility.doDate"))
        #expect(row.contains("case .dueDate: return CadenceTaskControlAccessibility.dueDate"))

        // Five chips, and the five names above are five. That the *sixth* would also have to name
        // itself is the initialiser's job, not this test's — see
        // `theSharedIOSChipCannotBeBuiltWithoutNamingItsField`.
        #expect(CadenceSourceScan.matchCount(#"iOSTaskAttributeChip\("#, in: row) == 5)

        // The three new words, and that they are the words the app already uses out loud.
        #expect(CadenceTaskControlAccessibility.recurrence == "Repeat")
        #expect(CadenceTaskControlAccessibility.milestone == "Milestone")
        #expect(CadenceTaskControlAccessibility.section == "Section")
        #expect(CadenceTitleNormalization.defaultMilestoneTitle.contains(CadenceTaskControlAccessibility.milestone))
    }

    /// **The iOS completion circle now reads the shared answer**, which is the same one macOS's
    /// does — and it is keyed on what a tap *does*, not on the state the row is in.
    ///
    /// It had a name already, so neither sweep in this file would ever have flagged it. What it had
    /// was a second spelling: `isFinishedTask ? "Mark task todo" : "Complete task"`, written out in
    /// `iOSTaskViews.swift`, against `CadenceTaskCompletionState.accessibilityActionLabel`'s
    /// "Reopen task" one file over. Two platforms, one control, two announcements.
    @Test func theIOSCompletionCircleTakesTheSharedActionLabel() throws {
        let row = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift")
        )
        #expect(row.contains("private var completionButton: some View"), "non-vacuity: wrong file read")

        #expect(row.contains(".accessibilityLabel(glyph.state.accessibilityActionLabel)"))
        #expect(
            !row.contains(#""Mark task todo""#),
            "the row is spelling the completion circle's name for itself again"
        )
        // iOS resolves the glyph with neither pending flag, so its circle only ever reaches three
        // of the five states — and all three are answered by the shared property.
        #expect(row.contains("CadenceTaskCompletionGlyph.resolve(task: task)"))
        for state in [CadenceTaskCompletionState.todo, .done, .cancelled] {
            #expect(!state.accessibilityActionLabel.isEmpty, "\(state)")
        }
    }

    private func unnamedIconButtonInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "icon-only button with no accessible name",
            fires: """
            Button {
                toggle()
            } label: {
                Image(systemName: systemName)
                    .font(.system(size: 12))
            }
            .buttonStyle(.cadencePlain)
            """,
            andNotOn: """
            Button {
                toggle()
            } label: {
                Image(systemName: systemName)
                    .font(.system(size: 12))
            }
            .buttonStyle(.cadencePlain)
            .accessibilityLabel(name)
            """,
            by: { Self.unnamedIconButtonCount(in: $0) > 0 }
        )
    }

    /// How many `Button`s in the file draw nothing but an `Image` and state no name.
    ///
    /// Reads `codeOnly` rather than `strippingComments`: this walks braces, and a `{` inside a
    /// comment or a string literal moves the depth count. No assertion below spells a quoted
    /// needle, which is the one thing `codeOnly` cannot answer.
    ///
    /// It errs towards silence in three places, deliberately — a rule that over-fires gets a
    /// ledger entry added instead of a label. A label attached further down the chain than
    /// `chainWindow`, a label body that opens with anything other than `Image(`, and a `Button`
    /// with an explicit title argument are all read as named.
    static func unnamedIconButtonCount(in source: String) -> Int {
        guard source.contains("Button") else { return 0 }
        let code = CadenceSourceScan.codeOnly(source)
        var count = 0
        var cursor = code.startIndex

        while let hit = code.range(of: "Button", range: cursor..<code.endIndex) {
            cursor = hit.upperBound
            // A word boundary in front, so `CadenceButton(` and `PlainButtonStyle` are not this.
            if hit.lowerBound > code.startIndex {
                let previous = code[code.index(before: hit.lowerBound)]
                if previous.isLetter || previous.isNumber || previous == "_" { continue }
            }
            guard let label = iconOnlyLabel(after: hit.upperBound, in: code) else { continue }
            if !namesItself(label.body, chainAfter: label.end, in: code) { count += 1 }
        }
        return count
    }

    /// The `Button`'s label closure, when the whole of it is an `Image`.
    private static func iconOnlyLabel(
        after start: String.Index,
        in code: String
    ) -> (body: String, end: String.Index)? {
        var index = skippingWhitespace(from: start, in: code)
        guard index < code.endIndex else { return nil }

        var candidate: (body: String, end: String.Index)?
        if code[index] == "(" {
            guard let arguments = span(from: index, open: "(", close: ")", in: code) else { return nil }
            index = skippingWhitespace(from: code.index(after: arguments.end), in: code)
            guard index < code.endIndex, code[index] == "{" else { return nil }
            guard let first = span(from: index, open: "{", close: "}", in: code) else { return nil }
            if follows("label:", after: first.end, in: code) {
                candidate = span(from: code.index(after: first.end), open: "{", close: "}", in: code)
            } else if arguments.body.contains("action:") || arguments.body.contains("role:") {
                // A `Button` given an explicit title draws text; only these two forms are icon-only.
                candidate = first
            }
        } else if code[index] == "{" {
            guard let first = span(from: index, open: "{", close: "}", in: code) else { return nil }
            guard follows("label:", after: first.end, in: code) else { return nil }
            candidate = span(from: code.index(after: first.end), open: "{", close: "}", in: code)
        }

        guard let label = candidate else { return nil }
        let trimmed = label.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Image(") else { return nil }
        return label
    }

    /// How far past the label's closing brace a `.accessibilityLabel` still counts as the same
    /// modifier chain: to the first line that is neither blank nor a continuation.
    private static func namesItself(
        _ label: String,
        chainAfter end: String.Index,
        in code: String
    ) -> Bool {
        var chain = label
        let tail = code[code.index(after: end)...].prefix(1_200)
        for line in tail.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.isEmpty || trimmed.hasPrefix(".") || trimmed.hasPrefix(")") else { break }
            chain += "\n" + trimmed
        }
        return chain.contains(".accessibilityLabel(")
            || chain.contains(".cadenceControlLabel(")
            || chain.contains("accessibilityLabel:")
    }

    private static func follows(_ needle: String, after index: String.Index, in code: String) -> Bool {
        let start = code.index(after: index)
        guard start < code.endIndex else { return false }
        return String(code[start...].prefix(40)).contains(needle)
    }

    private static func skippingWhitespace(from start: String.Index, in code: String) -> String.Index {
        var index = start
        while index < code.endIndex, code[index] == " " || code[index] == "\n" || code[index] == "\t" {
            index = code.index(after: index)
        }
        return index
    }

    /// The balanced span opening at the first `open` at or after `start`, as its inner text and the
    /// index of its closing delimiter.
    private static func span(
        from start: String.Index,
        open opening: Character,
        close closing: Character,
        in code: String
    ) -> (body: String, end: String.Index)? {
        guard let openIndex = code[start...].firstIndex(of: opening) else { return nil }
        var depth = 0
        var index = openIndex
        while index < code.endIndex {
            if code[index] == opening {
                depth += 1
            } else if code[index] == closing {
                depth -= 1
                if depth == 0 {
                    return (String(code[code.index(after: openIndex)..<index]), index)
                }
            }
            index = code.index(after: index)
        }
        return nil
    }
}
