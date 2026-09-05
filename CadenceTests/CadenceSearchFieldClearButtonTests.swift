import Foundation
import Testing
@testable import Cadence

/// **One clear button for every search field in the app** (T-672).
///
/// The ticket arrived as an accessibility finding — ten `xmark.circle.fill` glyphs in ten pickers,
/// none of them named — and the defect underneath it is duplication: eleven hand-spelled copies of
/// one control, drifted apart in tint, glyph weight, and whether clearing the field left it
/// focused. `CadenceSearchFieldClearButton` is the one copy.
///
/// **These pin the call sites, not the component.** A suite that only asserted the component names
/// itself would stay green while a twelfth field spelled the button by hand and announced nothing,
/// which is precisely the state T-672 found the app in. So the sweep below reads every file the app
/// compiles and asserts that the *only* place the control is spelled out is the component's own
/// file, and the ledger after it names all eleven fields that call it.
///
/// Same limit as the accessibility suites: these assert a name is **set**, in the shape SwiftUI
/// reads it from. Nothing here launches the app, so what VoiceOver announces is not a fact this
/// target has measured.
struct CadenceSearchFieldClearButtonTests {

    private static let componentPath = "Cadence/Shared/Components/CadenceSearchFieldClearButton.swift"

    /// **The eleven search fields, and the glyph size each states.**
    ///
    /// The size is the one difference between the copies that was chosen rather than drifted: in
    /// nine of the eleven rows the clear glyph is drawn at exactly the size of the row's own
    /// leading `magnifyingglass`, so it is the field's scale and not decoration. The two that
    /// differ are the two whose leading glyph is *emphasised*: Cmd+K draws an 18pt `command` over
    /// a 22pt field and clears at 16, and the focus picker draws a 13pt semibold magnifier and
    /// clears at 12.
    ///
    /// Ten of these are the ticket's ledger. The eleventh, `FocusPickerSupportViews.swift`, was in
    /// no accessibility ledger at all — it already carried `.cadenceControlLabel("Clear search")`,
    /// so no naming rule could see it — and it is here because T-672 is a duplication ticket: the
    /// one named copy is still a copy.
    private static let callSites: [String: Int] = [
        "Cadence/macOS/CadenceCalendarPicker.swift": 12,
        "Cadence/macOS/Views/CadenceContextPicker.swift": 12,
        "Cadence/macOS/Views/FocusPickerSupportViews.swift": 12,
        "Cadence/macOS/Views/GlobalSearchSupportViews.swift": 16,
        "Cadence/macOS/Views/GoalPickerViews.swift": 12,
        "Cadence/macOS/Views/GoalTimelineSupportViews.swift": 12,
        "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift": 11,
        // T-790's shared row: the four pickers that used to spell this button themselves --
        // ContainerPickerSupportViews, TaskTitleInlineTagPicker, TasksPanelSupportViews and
        // TildeContainerPicker -- now hand their field to `CadenceSearchFieldRow`, which draws the
        // chrome once. They are no longer call sites; this is.
        "Cadence/Shared/Components/CadenceSearchFieldRow.swift": 11,
    ]

    // MARK: - The rule, over every file the app compiles

    /// The sweep's result is stated as an equality rather than as "no offenders", because the one
    /// path it *must* contain is the non-vacuity claim: a detector that had gone blind would report
    /// the empty set, and an absence check would read that as good news.
    @Test func theOnlySpelledOutSearchClearButtonInTheAppIsTheSharedComponent() throws {
        let offenders = try Self.handSpelledClearButtonInstrument().sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            // 566 files at the time of writing; the floor only rules out a walk that found one
            // folder and called it the app.
            atLeast: 400,
            // A witness from the tree the ticket was about, and one this walk must reach: it held
            // a hand-spelled copy until this change.
            including: "Cadence/macOS/Views/TasksPanelSupportViews.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            offenders == [Self.componentPath],
            """
            \(offenders) spells a search field's clear button by hand. Draw \
            CadenceSearchFieldClearButton(text:glyphSize:focus:) instead — it states the accessible \
            name and restores focus to the field (T-672).
            """
        )
    }

    /// The ledger's *numbers*, both directions: a field that stops calling the component fails, and
    /// so does a stale entry for a field that no longer exists.
    @Test func everySearchFieldInTheAppClearsItselfThroughTheSharedComponent() throws {
        var actual: [String: Int] = [:]
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence") {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let calls = CadenceSourceScan.matchCount(#"CadenceSearchFieldClearButton\("#, in: source)
            if calls > 0 { actual[path] = calls }
        }

        #expect(
            actual == Self.callSites.mapValues { _ in 1 },
            "measured: \(actual.sorted { $0.key < $1.key })"
        )
        // The headline, so this suite and the ticket cannot disagree. It was 11 -- ten from
        // T-672's ledger plus the eleventh copy no naming rule could see. T-790 then folded four of
        // those into one shared row, so eight files spell the button and one of them is the shared
        // row itself. **A falling count here is the shared component doing its job**; a rising one
        // is a new hand-spelled copy.
        #expect(actual.values.reduce(0, +) == 8)
        #expect(actual.count == 8)
    }

    /// The size each call site states, which is the decision the ledger's comment explains. Stated
    /// as values because nothing else in the tree can: `glyphSize` takes no default, so the
    /// compiler proves a size is *passed* and only this proves it is the row's own.
    @Test func everySearchFieldStatesTheGlyphSizeItsRowDraws() throws {
        var actual: [String: Int] = [:]
        for (path, _) in Self.callSites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let sizes = CadenceSourceScan.captures(
                #"CadenceSearchFieldClearButton\((?:[^()]|\([^()]*\))*?glyphSize:\s*(\d+)"#,
                in: source
            ).map(\.text)
            #expect(sizes.count == 1, "\(path) states \(sizes.count) glyph sizes, not one")
            if let only = sizes.first, let value = Int(only) { actual[path] = value }
        }
        #expect(actual == Self.callSites)

        // And the parameter really has no default to fall back on — the T-674 shape, so the twelfth
        // field states its own scale rather than inheriting a number that is wrong half the time.
        let component = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile(Self.componentPath)
        )
        #expect(component.contains("let glyphSize: CGFloat\n"))
        #expect(component.contains("glyphSize: CGFloat =") == false, "glyphSize gained a default")
    }

    // MARK: - What the one copy decides

    /// The origin of the ticket: the control states a name, and states it once for every field.
    @Test func theSharedClearButtonNamesItselfAndTooltipsItselfFromOneString() throws {
        let source = try CadenceSourceScan.sourceFile(Self.componentPath)
        let code = CadenceSourceScan.strippingComments(source)
        #expect(code.contains("struct CadenceSearchFieldClearButton: View"), "non-vacuity: wrong file read")
        #expect(code != source, "non-vacuity: the stripper blanked nothing")
        #expect(code.count == source.count, "the stripper must keep the source's length")

        #expect(code.contains(#"static let accessibleName = "Clear search""#))
        #expect(code.contains(".accessibilityLabel(Self.accessibleName)"))
        #expect(code.contains(".help(Self.accessibleName)"))
        // The name is the control's, not a call site's: no caller can pass a different one, and
        // none can omit it.
        #expect(code.contains("accessibleName:") == false, "the name became a parameter")
    }

    /// **Focus is the behavioural decision T-672 made**, so it is pinned rather than left to the
    /// four sites that happened to have it. Clicking a SwiftUI `Button` takes key focus off the
    /// `TextField` beside it, so a clear button that does not put it back leaves the user typing
    /// into nothing; seven of the eleven copies did exactly that. The button always restores it,
    /// and `focus` is required so a call site cannot quietly opt out.
    @Test func theSharedClearButtonAlwaysPutsFocusBackInTheFieldItCleared() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile(Self.componentPath)
        )
        guard let body = CadenceSourceScan.declarationBody("var body: some View", in: code) else {
            Issue.record("no body on CadenceSearchFieldClearButton")
            return
        }
        #expect(body.contains(#"text = """#), "the button stopped emptying the field")
        #expect(body.contains("focus.wrappedValue = true"), "the button stopped restoring focus")

        #expect(code.contains("var focus: FocusState<Bool>.Binding"))
        #expect(code.contains("FocusState<Bool>.Binding?") == false, "focus became optional")
        #expect(code.contains("FocusState<Bool>.Binding =") == false, "focus gained a default")
    }

    /// The two fields that had **no** `@FocusState` at all before T-672, and so could not have
    /// restored focus even if their copy had tried. Converging on "always restore" is what made
    /// them grow one; a `.focused` binding deleted here would leave the component setting focus on
    /// a state nothing is bound to, which no compiler and no sweep above would notice.
    @Test func theTwoFieldsThatGainedAFocusStateStillBindIt() throws {
        for (path, declaration) in [
            ("Cadence/macOS/Views/GoalTimelineSupportViews.swift", "struct GoalTimelineFilterPopover: View"),
            ("Cadence/macOS/Views/TaskBundlePickerSupportViews.swift", "struct TaskBundleTaskPickerPanel: View"),
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            guard let body = CadenceSourceScan.declarationBody(declaration, in: code) else {
                Issue.record("no \(declaration) in \(path)")
                continue
            }
            #expect(body.contains("@FocusState private var isSearchFocused: Bool"), "\(path)")
            #expect(body.contains(".focused($isSearchFocused)"), "\(path) never binds its focus state")
            #expect(body.contains("focus: $isSearchFocused"), "\(path) never hands it to the button")
        }
    }

    /// Tint, the third thing the copies disagreed about: five drew `Theme.dim`, five
    /// `Theme.dim.opacity(0.5)` and one `0.55`. The named ramp wins — it is the plurality, it is
    /// what the `magnifyingglass` at the other end of every one of those rows already draws, and
    /// `Cadence/Shared/AGENTS.md` asks for a named ramp over a one-off opacity.
    @Test func theSharedClearButtonDrawsTheNamedDimRampRatherThanAnOpacityOfIt() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile(Self.componentPath)
        )
        #expect(code.contains(".foregroundStyle(Theme.dim)"))
        #expect(CadenceSourceScan.matchCount(#"\.opacity\("#, in: code) == 0)
        // And no call site drew its own tint back on top of the component's.
        for path in Self.callSites.keys {
            let site = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount(
                    #"CadenceSearchFieldClearButton\((?:[^()]|\([^()]*\))*?(tint|foregroundStyle)"#,
                    in: site
                ) == 0,
                "\(path) passes a tint to the clear button"
            )
        }
    }

    // MARK: - The detector

    /// Fires on a `Button` whose whole label is the `xmark.circle.fill` glyph **and** whose action
    /// empties a string — the search field's clear button, spelled out.
    ///
    /// The emptying assignment is what separates it from the other three controls in the app that
    /// draw the same glyph: the tag filter bar's `selectedSlugs.removeAll()`, the embed editor's
    /// `clearScheduledTime(…)`, and a cancelled task's completion circle, which is not a button at
    /// all. None of those is a search field and none should become one.
    ///
    /// The second alternative is Cmd+K's shape, `Button(action: clear)`, whose action is a named
    /// function and so states no assignment anywhere near the glyph. It is deliberately looser than
    /// the first; a future non-search `xmark.circle.fill` written that way would be reported here,
    /// and the report tells the author what to do about it.
    ///
    /// What it cannot see, stated rather than discovered later: an action that wraps the assignment
    /// in a closure of its own — `Button { withAnimation { query = "" } }` — falls outside the
    /// brace-free window the first alternative matches on.
    private static func handSpelledClearButtonInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "search field clear button spelled by hand",
            fires: """
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.cadencePlain)
            }
            """,
            // The nearest control that must be left alone: same glyph, same `isEmpty` guard, same
            // button style — and it clears a *selection*, not a query.
            andNotOn: """
            if !selectedSlugs.isEmpty {
                Button {
                    selectedSlugs.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.cadencePlain)
                .cadenceControlLabel("Clear tag filters")
            }
            """,
            by: { handSpelledClearButtonCount(in: $0) > 0 }
        )
    }

    private static func handSpelledClearButtonCount(in source: String) -> Int {
        let assigning = #"Button\s*\{[^{}]*=\s*""[^{}]*\}\s*label:\s*\{\s*Image\(systemName:\s*"xmark\.circle\.fill""#
        let named = #"Button\(action:\s*\w+\)\s*\{\s*Image\(systemName:\s*"xmark\.circle\.fill""#
        return CadenceSourceScan.matchCount(assigning, in: source)
            + CadenceSourceScan.matchCount(named, in: source)
    }

    /// The detector against the shapes a plausible mistake would blur, as literals rather than as
    /// files: a fixture read out of the tree can be retuned by the same edit that breaks the rule.
    @Test func theHandSpelledClearButtonDetectorSeparatesAQueryFromEverythingElse() throws {
        let instrument = try Self.handSpelledClearButtonInstrument()

        // Cmd+K's shape, the one alternative the first pattern cannot see.
        #expect(instrument.fires(on: """
        if !draftQuery.isEmpty {
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
        }
        """))

        // The multi-line action the four focus-restoring copies used.
        #expect(instrument.fires(on: """
        Button {
            searchQuery = ""
            isSearchFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
        }
        """))

        // A call to the shared component is not a hand-spelled copy.
        #expect(instrument.fires(on: """
        CadenceSearchFieldClearButton(text: $searchQuery, glyphSize: 11, focus: $isSearchFocused)
        """) == false)

        // A different glyph clearing the same query is a different control; this rule is about the
        // one the app draws eleven times.
        #expect(instrument.fires(on: """
        Button { searchQuery = "" } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        """) == false)

        // The completion circle a cancelled task draws — the same glyph, no button around it.
        #expect(instrument.fires(on: """
        Image(systemName: task.isCancelled ? "xmark.circle.fill" : "circle")
            .foregroundStyle(Theme.dim)
        """) == false)
    }
}
