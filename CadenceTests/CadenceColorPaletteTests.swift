import Foundation
import Testing
@testable import Cadence

/// Where the app's *swatch* palettes come from, and which of their entries are `Theme`'s.
///
/// T-166 found `CadenceFeatureDestination.defaultColorHex` spelling its own amber, blue and purple
/// and all three drifted from the `Theme` values they were copies of. T-246 is the same shape in
/// three more places, and the reason it is worth pinning rather than merely fixing is that **none
/// of the three was visibly wrong**: every literal matched its token exactly. A value assertion
/// passes before and after, so the tests that matter here are the source-scanning ones, and the
/// mutation that proves them is replacing a token with its own current value.
///
/// The scope line is drawn twice, deliberately:
/// - `Theme` is not asked to carry these palettes. It holds six accents, several semantically
///   spoken for, and a twelve-swatch menu cannot be built from six without collisions. A swatch
///   menu is the "or from a user-owned `colorHex`" half of the no-hardcoded-colour rule.
/// - `TagSupport.colorOptions` is a different palette with a different job and is out of scope,
///   as `CadenceColorPalette`'s own doc comment says.
@MainActor
struct CadenceColorPaletteValueTests {
    /// The list/goal/habit palette, resolved. Twelve hues, and the exact strings matter because
    /// they are what a stored `colorHex` is compared against.
    @Test func theListPaletteResolvesToItsTwelveHues() {
        #expect(CadenceColorPalette.colors == [
            "#4a9eff", "#6366f1", "#a78bfa", "#e879f9", "#f472b6", "#ff6b6b",
            "#ffa94d", "#fbbf24", "#4ecb71", "#14b8a6", "#06b6d4", "#6b7a99",
        ])
    }

    /// Exactly **five** of the twelve are `Theme` accents — blue, purple, red, amber, green, in
    /// palette order. Naming the count is what would fail if someone "unified" the palette by
    /// pushing a sixth swatch onto a `Theme` token, which would be a change of appearance wearing
    /// a refactor's clothes. (Only *three* of the five were literals T-246 converted: blue and
    /// green already read `areaDefault` / `projectDefault`. Five accents, three substitutions —
    /// the two counts are different questions and this test asks the first.)
    @Test func fiveOfTheTwelveSwatchesAreThemeAccentsAndTheOtherSevenAreNot() {
        let accents = Set(
            [Theme.blueHex, Theme.redHex, Theme.greenHex, Theme.amberHex, Theme.purpleHex, Theme.tealHex]
                .map { $0.lowercased() }
        )
        #expect(accents.count == 6, "six accents, all distinct")

        let shared = CadenceColorPalette.colors.filter { accents.contains($0.lowercased()) }
        #expect(shared == [Theme.blueHex, Theme.purpleHex, Theme.redHex, Theme.amberHex, Theme.greenHex])
        #expect(shared.count == 5)
        #expect(CadenceColorPalette.colors.count - shared.count == 7)

        // Teal is `Theme`'s sixth accent and is deliberately *not* in this palette — `#14b8a6` is
        // a different teal. That is T-245's finding, and it is not this ticket's to change.
        #expect(!CadenceColorPalette.colors.contains(where: { $0.caseInsensitiveCompare(Theme.tealHex) == .orderedSame }))
    }

    /// The section palette moved from `macOS/Views/KanbanBoardSupport.swift` to `Shared/`
    /// **byte-identically**. This is the whole claim: same eight values, same order.
    @Test func theSectionPaletteIsTheSameEightValuesTheKanbanFileHeld() {
        #expect(CadenceColorPalette.sectionColors == [
            "#6b7a99", "#4a9eff", "#4ecb71", "#f59e0b", "#ef4444", "#a855f7", "#14b8a6", "#f97316",
        ])
    }

    /// Three of the eight are tokens now. The default is first and comes from `TaskSectionDefaults`
    /// so the grid cannot stop offering the colour every new section starts on.
    @Test func theSectionPaletteAlwaysOffersTheColourANewSectionStartsOn() {
        #expect(CadenceColorPalette.sectionColors.first == TaskSectionDefaults.defaultColorHex)
        #expect(CadenceColorPalette.sectionColors.contains(Theme.blueHex))
        #expect(CadenceColorPalette.sectionColors.contains(Theme.greenHex))
    }

    /// The list-editor sheet's per-type default is the model default, not a second spelling of it.
    @Test func theCreateListSheetSeedsFromThePaletteDefaults() {
        #expect(CreateListSheet.ListType.area.defaultColor == CadenceColorPalette.areaDefault)
        #expect(CreateListSheet.ListType.project.defaultColor == CadenceColorPalette.projectDefault)
        // And those resolve to what they always resolved to.
        #expect(CreateListSheet.ListType.area.defaultColor == "#4a9eff")
        #expect(CreateListSheet.ListType.project.defaultColor == "#4ecb71")
    }
}

/// The "keep the stored value" rule, which the kanban column editor did not have.
///
/// A swatch grid that renders a fixed set and marks one selected by equality shows *nothing*
/// selected for a section wearing a hue it does not offer, and the next tap silently replaces it.
/// `CadenceColorPalette.offeredColors(for:)` has guarded the list palette against that since it was
/// consolidated; `offeredSectionColors(for:)` is the same guard for sections, and it is not
/// theoretical — iOS's `iOSSectionColorPicker` offers a *different* set for this same field.
@MainActor
struct CadenceSectionPaletteOfferingTests {
    @Test func anOfferedColourAlreadyInThePaletteAddsNothing() {
        #expect(CadenceColorPalette.offeredSectionColors(for: "#a855f7") == CadenceColorPalette.sectionColors)
        #expect(CadenceColorPalette.offeredSectionColors(for: "") == CadenceColorPalette.sectionColors)
        #expect(CadenceColorPalette.offeredSectionColors(for: "   ") == CadenceColorPalette.sectionColors)
    }

    /// The case-insensitive half. The old comparison was `editorColorHex == hex`, so a stored
    /// `#F59E0B` failed to match the `#f59e0b` sitting right beside it in the grid.
    @Test func casingDoesNotMakeASecondSwatch() {
        #expect(CadenceColorPalette.offeredSectionColors(for: "#F59E0B") == CadenceColorPalette.sectionColors)
        #expect(CadenceColorPalette.matches("#f59e0b", "#F59E0B"))
    }

    /// A hue this palette does not contain — `#e671b8` is in `TagSupport.colorOptions`, which is
    /// what iOS offers for this same field, so this is the real cross-platform case.
    @Test func aStoredHueThePaletteDoesNotOfferIsAppendedRatherThanDropped() {
        let offered = CadenceColorPalette.offeredSectionColors(for: "#e671b8")
        #expect(offered.count == CadenceColorPalette.sectionColors.count + 1)
        #expect(offered.last == "#e671b8")
        #expect(Array(offered.dropLast()) == CadenceColorPalette.sectionColors)
        #expect(TagSupport.colorOptions.contains("#e671b8"), "the fixture is a hue iOS really offers")
    }

    /// Both palettes share the rule, so the list grid did not lose it when the helper was factored.
    @Test func theListPaletteKeepsTheSameRule() {
        #expect(CadenceColorPalette.offeredColors(for: Theme.tealHex).last == Theme.tealHex)
        #expect(CadenceColorPalette.offeredColors(for: "#4A9EFF") == CadenceColorPalette.colors)
    }
}

/// Source half — the assertions no value test can make.
///
/// A literal whose value happens to match its token today passes every test above and still
/// reopens the drift, because the next hue change to `Theme` will not reach it. That is the exact
/// regression T-166 shipped, and it is the mutation these tests are written to fail against.
@MainActor
struct CadenceColorPaletteSourceTests {
    /// Non-vacuity for the whole file. Every "contains no literal" assertion below passes against
    /// an empty string, which is what a path mismatch on an isolated build tree produces.
    @Test func theScannerReadsRealFilesAndStripsComments() throws {
        let palette = try paletteSourceFile("Cadence/Shared/CadenceColorPalette.swift")
        #expect(palette.count > 2000, "read \(palette.count) characters")
        #expect(palette.contains("enum CadenceColorPalette {"))
        #expect(palette.contains("static var sectionColors"))

        let stripped = paletteStrippingSwiftComments(palette)
        #expect(stripped.count == palette.count, "the stripper blanks rather than deletes")
        // The doc comments quote the very literals the assertions below ban, so the stripper
        // running is load-bearing rather than tidy.
        #expect(palette.contains("`#6b7a99`"))
        #expect(!stripped.contains("`#6b7a99`"))
        #expect(stripped.contains("static var sectionColors"))
    }

    /// Self-check on the needle: it must match the literal these tests ban and must not match the
    /// token read that replaced it, so a typo in the pattern cannot quietly pass every scan.
    @Test func theHexNeedleMatchesALiteralAndNotATokenRead() {
        // `##"..."##`, because a `#"..."#` raw string is terminated by the `"#` inside
        // `"#4ecb71"` itself — the needle and its delimiter are the same two characters.
        let banned = ##"        case .project: return "#4ecb71""##
        let wanted = "        case .project: return CadenceColorPalette.projectDefault"

        #expect(banned.range(of: paletteHexLiteralPattern, options: .regularExpression) != nil)
        #expect(wanted.range(of: paletteHexLiteralPattern, options: .regularExpression) == nil)
        // And it does not match a bare `#` that is not a colour, e.g. a `#expect` or a `#if`.
        #expect("#if os(macOS)".range(of: paletteHexLiteralPattern, options: .regularExpression) == nil)
    }

    /// No swatch array in this app may spell a hex that `Theme` already publishes as an accent.
    ///
    /// Positive polarity beside it: the four that *are* accents read their tokens by name, so the
    /// test says what the file should do and not only what it should not.
    /// Stated against `CadenceAccentPalette.standard` rather than the *active* `Theme` accents,
    /// and that is a sharpening rather than a loosening. The accents are selectable (T-15), so
    /// `Theme.amberHex` is whatever set happens to be in force when the test runs — needles that
    /// move are needles that can wander off the literals the source actually contains, in either
    /// direction. The source was written against the standard set; that is the set it must not
    /// re-type. A palette *other* than the standard one sharing a hue with one of the twelve
    /// swatch literals is a coincidence, not a token being respelled, which is why this does not
    /// sweep `CadenceAccentPalette.all`.
    @Test func noSwatchArrayRespellsAThemeAccent() throws {
        let standard = CadenceAccentPalette.standard
        let accents = [
            ("blue", standard.blueHex), ("red", standard.redHex), ("green", standard.greenHex),
            ("amber", standard.amberHex), ("purple", standard.purpleHex), ("teal", standard.tealHex),
        ]
        let palette = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/Shared/CadenceColorPalette.swift"))

        for array in ["colors", "sectionColors", "destinationTints"] {
            let body = try paletteArrayBody(named: array, in: palette)
            #expect(!body.isEmpty, "\(array) body did not extract")
            for (name, hex) in accents {
                #expect(
                    !body.localizedCaseInsensitiveContains("\"\(hex)\""),
                    "\(array) respells Theme.\(name)Hex (\(hex)) instead of reading the token"
                )
            }
        }

        let colorsBody = try paletteArrayBody(named: "colors", in: palette)
        #expect(colorsBody.contains("areaDefault"))
        #expect(colorsBody.contains("projectDefault"))
        #expect(colorsBody.contains("Theme.purpleHex"))
        #expect(colorsBody.contains("Theme.redHex"))
        #expect(colorsBody.contains("Theme.amberHex"))

        let sectionBody = try paletteArrayBody(named: "sectionColors", in: palette)
        #expect(sectionBody.contains("TaskSectionDefaults.defaultColorHex"))
        #expect(sectionBody.contains("Theme.blueHex"))
        #expect(sectionBody.contains("Theme.greenHex"))
        // Five hues `Theme` does not carry stay literals here, on purpose — see the declaration.
        #expect(palettteRegexMatches(paletteHexLiteralPattern, in: sectionBody).count == 5)
    }

    /// The list-editor sheet's per-type default reads the palette. Both arms — an arm that still
    /// spells its own hex beside one that does not is how `#4ecb71` outlived `projectDefault`
    /// being pointed at `Theme.greenHex` in the first place.
    @Test func neitherArmOfTheListSheetDefaultSpellsAHex() throws {
        let sheet = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Sheets/CreateListSheet.swift"))
        let body = try paletteBracedBody(after: "var defaultColor: String {", in: sheet)

        #expect(!body.isEmpty)
        let arms = palettteRegexMatches(#"case \.\w+:\s+return "#, in: body)
        #expect(arms.count == 2, "expected one arm per list type, read \(arms.count)")

        let literals = palettteRegexMatches(paletteHexLiteralPattern, in: body)
        #expect(literals.isEmpty, "these arms still spell a hex: \(literals)")
        #expect(palettteRegexMatches(#"return CadenceColorPalette\.\w+Default\b"#, in: body).count == 2)

        // And the whole file, not just the switch: the `@State` seed was a third copy of `#4a9eff`.
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: sheet).isEmpty,
            "CreateListSheet still hand-types a colour somewhere outside the switch"
        )
    }

    /// The section palette does not live in a macOS view file any more, and nothing re-declares it.
    @Test func theKanbanFileNoLongerOwnsAPalette() throws {
        let kanban = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/KanbanBoardSupport.swift"))

        // Non-vacuity: this is still the file it was, with its other constants intact.
        #expect(kanban.contains("let kanbanSectionDragPrefix"))
        #expect(kanban.contains("let kanbanColumnWidth"))

        #expect(!kanban.contains("kanbanSectionColorOptions"))
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: kanban).isEmpty,
            "KanbanBoardSupport spells a colour again"
        )
    }

    /// The column editor is handed the *offered* palette, not the raw array, so a stored hue the
    /// grid does not contain still reads as selected.
    @Test func theColumnEditorAsksForTheOfferedSectionPalette() throws {
        let column = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        #expect(column.contains("editorColorOptions: CadenceColorPalette.offeredSectionColors(for: editorColorHex)"))

        let grid = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/KanbanColumnSupportViews.swift"))
        #expect(grid.contains("ForEach(editorColorOptions"), "non-vacuity: this is still the swatch row")
        #expect(grid.contains("CadenceColorPalette.matches(hex, editorColorHex)"))
        #expect(!grid.contains("editorColorHex == hex"), "case-sensitive comparison is back")
    }
}

// MARK: - Scanning helpers

/// Every non-overlapping match of `pattern`. A loop over `range(of:options:)` rather than
/// `ranges(of:options:)` so the scan does not depend on which Foundation overload resolves.
private func palettteRegexMatches(_ pattern: String, in source: String) -> [String] {
    var results: [String] = []
    var searchStart = source.startIndex
    while let match = source.range(of: pattern, options: .regularExpression, range: searchStart..<source.endIndex) {
        results.append(String(source[match]))
        searchStart = match.upperBound > match.lowerBound ? match.upperBound : source.index(after: match.lowerBound)
        if searchStart >= source.endIndex { break }
    }
    return results
}

/// `"#abc"` through `"#aabbccdd"`, quoted — the shape of a hand-typed palette literal. The quotes
/// are required so a `Theme.amberHex` read cannot match, i.e. the needle is not a substring of the
/// correct post-fix text.
private let paletteHexLiteralPattern = "\"#[0-9A-Fa-f]{3,8}\""

/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree), so read relative to it rather than resolving anything.
private func paletteSourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` and `/* */` comments so the assertions read code rather than prose — every doc
/// comment here quotes the literals its declaration must not contain.
private func paletteStrippingSwiftComments(_ source: String) -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}

/// The `[...]` literal of `<name>`, brackets excluded — stored or computed.
///
/// The computed spelling is not cosmetic and the helper had to learn it: the swatch arrays read
/// `Theme` accents, the accents became selectable (T-15), and a `static let` would have frozen
/// each array on whichever palette was active the first time a colour grid was drawn.
private func paletteArrayBody(named name: String, in source: String) throws -> String {
    let openings = ["static let \(name) = [", "static var \(name): [String] { ["]
    guard let start = openings.lazy.compactMap({ source.range(of: $0) }).first else {
        Issue.record("CadenceColorPalette no longer declares \(name) as an array literal")
        return ""
    }
    guard let end = source.range(of: "]", range: start.upperBound..<source.endIndex) else { return "" }
    return String(source[start.upperBound..<end.lowerBound])
}

/// The brace-balanced body that opens with `header`, braces excluded.
private func paletteBracedBody(after header: String, in source: String) throws -> String {
    guard let start = source.range(of: header) else {
        Issue.record("no declaration matching \(header)")
        return ""
    }
    var depth = 1
    var index = start.upperBound
    while index < source.endIndex, depth > 0 {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" { depth -= 1 }
        index = source.index(after: index)
    }
    return String(source[start.upperBound..<index])
}

// MARK: - T-245 / T-261: two menus pointed at the wrong palette

/// The sidebar tint editor's menu.
///
/// T-245: `SidebarTabEditorSheet` rendered `ColorGrid`, i.e. the twelve-hue **list** palette, for a
/// field that is not a list colour. `Theme.tealHex` is not among the twelve, so Focus — whose
/// default tint *is* teal — drew a thirteenth swatch beside the palette's own `#14b8a6`.
///
/// The decision this pins: a destination tint is **app chrome**, not user-owned data, and every
/// `CadenceFeatureDestination.defaultColorHex` arm already reads a `Theme` accent by name (T-166).
/// So this one menu is legitimately built from `Theme`'s six accents, while `colors` and
/// `sectionColors` may not be — they are menus of user-owned `colorHex` values, which is the
/// "or from a user-owned `colorHex`" half of the no-hardcoded-colour rule. No `Theme` accent was
/// added to make this fit; T-166 rejected that and so does this.
@MainActor
struct CadenceDestinationTintPaletteTests {
    @Test func theDestinationTintMenuIsExactlyThemesSixAccents() {
        #expect(CadenceColorPalette.destinationTints == [
            "#ff6b6b", "#ffa94d", "#4ecb71", "#45CBC4", "#4a9eff", "#a78bfa",
        ])

        let accents = [Theme.redHex, Theme.amberHex, Theme.greenHex, Theme.tealHex, Theme.blueHex, Theme.purpleHex]
        #expect(CadenceColorPalette.destinationTints == accents)
        #expect(Set(accents.map { $0.lowercased() }).count == 6, "six accents, all distinct")
    }

    /// **The relation the ticket is actually about**, and the one a value list cannot state: the
    /// menu that edits a destination's tint must offer every tint the app assigns by default.
    ///
    /// A menu that does not is worse than untidy. `offered(_:from:)` appends the stored value, so
    /// an unoffered default is reachable *only while it is already selected* — one tap on any other
    /// hue and it leaves the grid for good, with no reset control anywhere in Settings.
    @Test func everyDestinationDefaultIsOfferedByTheMenuThatEditsIt() {
        for destination in CadenceFeatureDestination.allCases {
            let hex = destination.defaultColorHex
            #expect(
                CadenceColorPalette.offered(hex, from: CadenceColorPalette.destinationTints)
                    == CadenceColorPalette.destinationTints,
                "\(destination.rawValue)'s default \(hex) is outside the menu that edits it"
            )
        }
        #expect(CadenceFeatureDestination.allCases.count == 11, "non-vacuity: the loop ran")

        // And the same check over the six rows Settings → Sidebar actually draws an editor for.
        for destination in SidebarStaticDestination.allCases {
            #expect(CadenceColorPalette.destinationTints.contains { CadenceColorPalette.matches($0, destination.defaultColorHex) })
        }
        #expect(SidebarStaticDestination.allCases.count == 6, "non-vacuity: the loop ran")
    }

    /// The defect, stated as the failure of that same relation against the palette that used to be
    /// wired up. Focus is the only destination the list palette misses, and `#14b8a6` sitting in
    /// the twelve is why the extra swatch read as a *second teal* rather than as a stray hue.
    @Test func theListPaletteFailsThatRelationForFocusWhichIsWhatTwoTealsMeant() {
        let focusTint = CadenceFeatureDestination.focus.defaultColorHex
        #expect(CadenceColorPalette.matches(focusTint, Theme.tealHex))

        let viaListPalette = CadenceColorPalette.offeredColors(for: focusTint)
        #expect(viaListPalette.count == CadenceColorPalette.colors.count + 1, "the thirteenth swatch")
        #expect(viaListPalette.last == focusTint)

        #expect(CadenceColorPalette.colors.contains("#14b8a6"), "the palette's own teal")
        #expect(!CadenceColorPalette.matches("#14b8a6", Theme.tealHex), "two teals, one decision")

        // Every other destination default is in the twelve, so Focus really is the whole of it.
        let misses = CadenceFeatureDestination.allCases.filter { destination in
            !CadenceColorPalette.colors.contains { CadenceColorPalette.matches($0, destination.defaultColorHex) }
        }
        #expect(misses == [.focus])
    }

    /// Source half. The array must read the six tokens by name and spell no hex — the T-166 shape,
    /// where a literal equal to its own token passes every value assertion above and still reopens
    /// the drift, because the next hue change to `Theme` will not reach it.
    @Test func theDestinationTintArrayReadsThemeTokensAndSpellsNoHex() throws {
        let palette = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/Shared/CadenceColorPalette.swift"))
        let body = try paletteArrayBody(named: "destinationTints", in: palette)

        #expect(!body.isEmpty, "destinationTints body did not extract")
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: body).isEmpty,
            "destinationTints hand-types a colour: \(palettteRegexMatches(paletteHexLiteralPattern, in: body))"
        )
        for token in ["Theme.redHex", "Theme.amberHex", "Theme.greenHex", "Theme.tealHex", "Theme.blueHex", "Theme.purpleHex"] {
            #expect(body.contains(token), "destinationTints no longer reads \(token)")
        }
    }

    /// Call site. `ColorGrid` is parameterised rather than forked, and the sidebar editor is the
    /// one caller that passes a palette — the bug was the *absence* of that argument, so its bare
    /// spelling is banned by name.
    @Test func theSidebarTabEditorAsksForTheDestinationTintMenu() throws {
        let settings = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/SettingsSupportViews.swift"))
        #expect(settings.contains("struct SidebarTabEditorSheet"), "non-vacuity: still the file with the editor")

        #expect(settings.contains("ColorGrid(selected: $tintHex, palette: CadenceColorPalette.destinationTints)"))
        #expect(!settings.contains("ColorGrid(selected: $tintHex)"), "the sidebar editor is back on the list palette")
        // The context editor in the same file keeps the list palette, and says so by omission.
        #expect(settings.contains("ColorGrid(selected: $editColor)"))

        let grid = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Sheets/CreateContextSheet.swift"))
        #expect(grid.contains("struct ColorGrid: View"), "non-vacuity: still the file with the grid")
        #expect(grid.contains("var palette: [String] = CadenceColorPalette.colors"))
        #expect(grid.contains("ForEach(CadenceColorPalette.offered(selected, from: palette)"))
    }
}

/// T-261 — one swatch menu for one field, across two platforms.
///
/// `TaskSectionConfig.colorHex` is edited from exactly two places: the Mac's kanban column editor
/// and iOS's `iOSSectionColorPicker`. They offered different sets — eight against nine, overlapping
/// in one — so a column tinted on the phone opened on the Mac wearing a hue the Mac could not
/// offer. `CadenceColorPalette.sectionColors` wins; iOS's borrowed `TagSupport.colorOptions` loses.
@MainActor
struct CadenceSectionPaletteConvergenceTests {
    /// The relation, not a value list: both editors of one field name **the same function**, so a
    /// hue decision cannot be made on one platform only.
    @Test func bothPlatformsOfferOneMenuForASectionsColour() throws {
        let mac = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/KanbanSectionColumnView.swift"))
        let ios = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/iOS/iOSListEditorViews.swift"))

        #expect(mac.contains("struct ListSectionKanbanColumn"), "non-vacuity: still the Mac column")
        #expect(ios.contains("struct iOSSectionColorPicker"), "non-vacuity: still the iOS picker")

        let menu = "CadenceColorPalette.offeredSectionColors(for:"
        #expect(mac.contains(menu))
        #expect(ios.contains(menu))
    }

    /// The borrowing stops. `TagSupport.colorOptions` is a separate palette with a separate job,
    /// and three of the eight hues it lent (`#ffb84d`, `#5aa2ff`, `#9e8cff`) are the pre-T-166
    /// drifted near-copies of `Theme`'s amber, blue and purple — adopting iOS's set would have
    /// re-imported the very literals T-166 deleted for having drifted.
    ///
    /// Comment-stripping is load-bearing in **both** directions here, which is why it is proved
    /// rather than assumed: the picker's doc comment names `TagSupport.colorOptions` to explain
    /// what it stopped doing, so an unstripped negative would fail on correct code.
    @Test func theIOSSectionPickerNoLongerBorrowsTheTagPalette() throws {
        let raw = try paletteSourceFile("Cadence/iOS/iOSListEditorViews.swift")
        let stripped = paletteStrippingSwiftComments(raw)

        #expect(raw.contains("TagSupport.colorOptions"), "the prose still explains the borrowing")
        #expect(!stripped.contains("TagSupport.colorOptions"), "the code still borrows the tag palette")

        #expect(stripped.contains("ForEach(CadenceColorPalette.offeredSectionColors(for: selectedHex)"))
        #expect(stripped.contains("CadenceColorPalette.matches(option, selectedHex)"))
        #expect(!stripped.contains("selectedHex.caseInsensitiveCompare(option)"), "a second spelling of matches")

        // The tag palette itself is untouched — separate palette, separate job, out of scope.
        #expect(TagSupport.colorOptions.count == 8)
        #expect(TagSupport.colorOptions.contains("#ffb84d"))
        #expect(TagSupport.colorOptions.contains("#5aa2ff"))
        #expect(TagSupport.colorOptions.contains("#9e8cff"))
        for drifted in ["#ffb84d", "#5aa2ff", "#9e8cff"] {
            #expect(
                !CadenceColorPalette.sectionColors.contains { CadenceColorPalette.matches($0, drifted) },
                "the section menu picked up a drifted near-copy of a Theme accent"
            )
        }
    }

    /// Nothing already stored is dropped by either menu, on either platform. The corpus is every
    /// hue **both** old menus could have written, plus a hue neither could, plus a casing variant.
    @Test func noStoredHexIsDroppedByEitherNewMenu() {
        let iOSOldSectionMenu = [TaskSectionDefaults.defaultColorHex] + TagSupport.colorOptions
        let corpus = iOSOldSectionMenu
            + CadenceColorPalette.sectionColors
            + CadenceColorPalette.colors
            + CadenceColorPalette.destinationTints
            + ["#F59E0B", "#45cbc4", "#123456"]
        #expect(corpus.count == 38, "non-vacuity: the corpus is the size it looks")

        for stored in corpus {
            let sectionMenu = CadenceColorPalette.offeredSectionColors(for: stored)
            #expect(
                sectionMenu.contains { CadenceColorPalette.matches($0, stored) },
                "a section wearing \(stored) shows nothing selected, so the next tap replaces it"
            )

            let tintMenu = CadenceColorPalette.offered(stored, from: CadenceColorPalette.destinationTints)
            #expect(
                tintMenu.contains { CadenceColorPalette.matches($0, stored) },
                "a destination tinted \(stored) shows nothing selected, so the next tap replaces it"
            )
        }
    }
}

// MARK: - T-262: the last five hand-typed seeds on the macOS surface

/// The `@State` colour seeds that sat beside a model default and re-typed its hex.
///
/// Five of them, in four files, and **every one was correct by value** — `#4a9eff` really is
/// `Theme.blueHex` and `#6b7a99` really is `TaskSectionDefaults.defaultColorHex`. That is the whole
/// hazard and the reason these outlived both T-166 and T-246: a value assertion passes before and
/// after, the app looks right, and the copy simply stops tracking the token the next time a hue
/// moves. T-166 is what that looks like once it has happened — the sidebar drew Today in `#FFB84D`
/// while the command palette drew the same destination in `Theme`'s `#ffa94d`.
///
/// So the assertions below are source-scanning, and the mutation that proves them is re-typing a
/// literal that equals its own token.
///
/// Two adjacent things are deliberately **not** in scope, and both are argued in T-262 itself:
/// - `Cadence/Models/*.swift`'s `colorHex` defaults cannot read `Theme` at all —
///   `CadenceMCPServer` compiles `Models/` and not `Theme.swift`. They stay literals, which is
///   precisely why the seeds that mirror them must not be a second copy;
///   `theSeedsMirrorModelDefaultsThatCannotReadTheToken` is the guard that replaces the read.
/// - `Services/CadenceUITestSupport.swift` and `iOS/iOSSampleDataSupport.swift` seed *fixture*
///   rows. They are data a test or a demo writes, not palette decisions the product renders.
@MainActor
struct CadenceSeedColourSourceTests {
    /// A new context's seed. One literal, and it was the file's only one.
    @Test func theCreateContextSheetSeedsFromTheAccentRatherThanItsValue() throws {
        let sheet = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Sheets/CreateContextSheet.swift"))
        #expect(sheet.contains("struct CreateContextSheet: View"), "non-vacuity: still the sheet")

        #expect(sheet.contains("@State private var selectedColor = Theme.blueHex"))
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: sheet).isEmpty,
            "CreateContextSheet hand-types a colour: \(palettteRegexMatches(paletteHexLiteralPattern, in: sheet))"
        )
    }

    /// The goal sheet held the same value **twice** — the property initialiser and the `init` seed
    /// that overwrites it when editing. Both arms, for the reason `CreateListSheet`'s two switch
    /// arms are both asserted: one arm still spelling its own hex beside one that does not is how
    /// `#4ecb71` outlived `projectDefault` being pointed at `Theme.greenHex`.
    @Test func theCreateGoalSheetSeedsBothOfItsColourStatesFromTheAccent() throws {
        let sheet = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Sheets/CreateGoalSheet.swift"))
        #expect(sheet.contains("struct CreateGoalSheet: View"), "non-vacuity: still the sheet")

        #expect(sheet.contains("@State private var selectedColor = Theme.blueHex"))
        #expect(sheet.contains("_selectedColor = State(initialValue: goal?.colorHex ?? Theme.blueHex)"))
        #expect(palettteRegexMatches(#"Theme\.blueHex"#, in: sheet).count == 2, "both seeds, not one")
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: sheet).isEmpty,
            "CreateGoalSheet hand-types a colour: \(palettteRegexMatches(paletteHexLiteralPattern, in: sheet))"
        )
    }

    /// A new habit's seed.
    @Test func theCreateHabitSheetSeedsFromTheAccentRatherThanItsValue() throws {
        let sheet = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/HabitsFormSheets.swift"))
        #expect(sheet.contains("struct CreateHabitSheet: View"), "non-vacuity: still the sheet")

        #expect(sheet.contains("@State private var selectedColor = Theme.blueHex"))
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: sheet).isEmpty,
            "HabitsFormSheets hand-types a colour: \(palettteRegexMatches(paletteHexLiteralPattern, in: sheet))"
        )
    }

    /// The odd one out: not an accent but the app's single neutral, on the "Unassigned" habit
    /// group's icon tile.
    ///
    /// It reads `TaskSectionDefaults.defaultColorHex` — a constant named for kanban sections —
    /// and that is a decision rather than an accident. `#6b7a99` is one value with one home, and
    /// that home has to be `Models/` because `CadenceMCPServer` compiles `Models/` and not
    /// `Theme.swift`; `Area`/`Project` container fallbacks, `Tag`'s default, `GoalListLink`'s
    /// fallback and the last swatch of the list palette are all the same grey. A new
    /// `Theme.neutralHex` beside it would be a **second spelling of a hex the app already
    /// publishes**, which is the drift T-166 deleted rather than the fix for it.
    @Test func theUnassignedHabitGroupReadsTheAppsOneNeutral() throws {
        let view = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/macOS/Views/HabitsView.swift"))
        #expect(view.contains("title: \"Unassigned\""), "non-vacuity: still the group this is about")

        #expect(view.contains("colorHex: TaskSectionDefaults.defaultColorHex,"))
        #expect(
            palettteRegexMatches(paletteHexLiteralPattern, in: view).isEmpty,
            "HabitsView hand-types a colour: \(palettteRegexMatches(paletteHexLiteralPattern, in: view))"
        )

        // And `Theme` did not grow a second name for that grey to make the read read nicer.
        let theme = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/Shared/Theme.swift"))
        // `static var blueHex` since T-15 made the accents selectable; the neutral ramp is what
        // this test is about and it is still `static let`, so anchor on that half.
        #expect(theme.contains("static let bg = Color(hex:"), "non-vacuity: still Theme")
        #expect(
            !theme.localizedCaseInsensitiveContains("\"\(TaskSectionDefaults.defaultColorHex)\""),
            "Theme now spells the neutral too, so there are two homes for one hex"
        )
    }

    /// The invariant behind the four file-scoped tests, over the **whole** macOS surface rather
    /// than the four files that happened to be wrong.
    ///
    /// A per-file list only pins the sites a ticket already found; the next `@State` seed goes into
    /// a fifth file. After T-262 there is no colour literal anywhere under `Cadence/macOS/`, which
    /// is an invariant with no allowlist to keep honest — `Theme.swift` and the swatch arrays in
    /// `CadenceColorPalette.swift` both live under `Cadence/Shared/`, so nothing here needs an
    /// exception carved for it.
    @Test func noFileOnTheMacOSSurfaceHandTypesAColourHex() throws {
        let files = try paletteSwiftFiles(under: "Cadence/macOS")
        #expect(files.count > 180, "non-vacuity: walked \(files.count) files")
        #expect(
            files.contains { $0.hasSuffix("Cadence/macOS/Views/HabitsView.swift") },
            "non-vacuity: the walk reached a file known to have held a literal"
        )

        var offenders: [String] = []
        for path in files {
            let source = paletteStrippingSwiftComments(try String(contentsOfFile: path, encoding: .utf8))
            for literal in palettteRegexMatches(paletteHexLiteralPattern, in: source) {
                offenders.append("\((path as NSString).lastPathComponent): \(literal)")
            }
        }
        #expect(offenders.isEmpty, "colour literals under Cadence/macOS: \(offenders)")
    }

    /// Value half: a pure substitution, so nothing on screen moved. Stated against the literals the
    /// four files used to spell, because "the seed equals the token" is trivially true of any token.
    @Test func theTokensResolveToTheValuesTheLiteralsSpelled() {
        // The blue is stated against the *standard* palette, because that is the only set a
        // compile-time literal in `Models/` can mirror once the accents are selectable (T-15).
        #expect(CadenceAccentPalette.standard.blueHex == "#4a9eff")
        #expect(TaskSectionDefaults.defaultColorHex == "#6b7a99")
        // And the swatch default still reads whatever is *active*, not a frozen copy of it.
        #expect(CadenceColorPalette.areaDefault == Theme.blueHex)
    }

    /// Why the seeds had to move and the models could not: the model defaults are the copies that
    /// *cannot* read the token, so this test is the enforcement that a token read would have been.
    ///
    /// Change `Theme.blueHex` and three `@Model` defaults silently stop matching the colour every
    /// new context, goal and habit is drawn with in every picker. That is T-166's failure mode with
    /// the compiler unable to help, which is exactly when a test has to.
    @Test func theSeedsMirrorModelDefaultsThatCannotReadTheToken() throws {
        // Against `CadenceAccentPalette.standard`, not the active accent set: a literal in a
        // `@Model` cannot follow a runtime selection, so the standard palette is the only thing it
        // can be required to mirror. Change the standard blue and these four still fail, which is
        // the whole job this test was written to do.
        let standardBlue = CadenceAccentPalette.standard.blueHex
        for model in ["Context", "Goal", "Habit", "Area"] {
            let source = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/Models/\(model).swift"))
            #expect(source.contains("@Model"), "non-vacuity: \(model).swift is still a model")
            #expect(
                source.localizedCaseInsensitiveContains("var colorHex: String = \"\(standardBlue)\""),
                "\(model).colorHex's default has drifted from the standard palette's blue (\(standardBlue))"
            )
        }

        let task = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/Models/AppTask.swift"))
        #expect(
            task.contains("static let defaultColorHex = \"\(TaskSectionDefaults.defaultColorHex)\""),
            "the neutral moved without this test being told"
        )
    }
}

/// Every `.swift` file under a repo-relative directory, as absolute paths.
private func paletteSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(relativeDirectory)

    guard let walker = FileManager.default.enumerator(atPath: root.path) else {
        Issue.record("could not walk \(relativeDirectory)")
        return []
    }
    return walker.compactMap { entry in
        guard let name = entry as? String, name.hasSuffix(".swift") else { return nil }
        return root.appendingPathComponent(name).path
    }
    .sorted()
}
