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
        #expect(palette.contains("static let sectionColors"))

        let stripped = paletteStrippingSwiftComments(palette)
        #expect(stripped.count == palette.count, "the stripper blanks rather than deletes")
        // The doc comments quote the very literals the assertions below ban, so the stripper
        // running is load-bearing rather than tidy.
        #expect(palette.contains("`#6b7a99`"))
        #expect(!stripped.contains("`#6b7a99`"))
        #expect(stripped.contains("static let sectionColors"))
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
    @Test func noSwatchArrayRespellsAThemeAccent() throws {
        let accents = [
            ("blue", Theme.blueHex), ("red", Theme.redHex), ("green", Theme.greenHex),
            ("amber", Theme.amberHex), ("purple", Theme.purpleHex), ("teal", Theme.tealHex),
        ]
        let palette = paletteStrippingSwiftComments(try paletteSourceFile("Cadence/Shared/CadenceColorPalette.swift"))

        for array in ["colors", "sectionColors"] {
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

/// The `[...]` initialiser of `static let <name>`, brackets excluded.
private func paletteArrayBody(named name: String, in source: String) throws -> String {
    guard let start = source.range(of: "static let \(name) = [") else {
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
