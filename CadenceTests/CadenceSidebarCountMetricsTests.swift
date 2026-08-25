import Foundation
import Testing
@testable import Cadence

/// `SidebarCountLabel` and `iOSSidebarCountLabel` were 24 lines that were character-for-character
/// identical once the names were normalised, and the single difference between them was the font
/// size: 11 on macOS against 12 on iOS. One component draws both sidebars now
/// (`CadenceSidebarCountLabel`), and the figure it draws with lives here.
///
/// `Cadence/iOS/` is invisible to this macOS-built target, so pinning the view is not on offer.
/// Pinning the number and the clamp rule is, and that is where the fork was.
struct CadenceSidebarCountMetricsTests {
    /// 12 wins. The count is the only number in the column and has to stay legible beside a 13–14pt
    /// label; the point macOS was saving bought nothing, because the label truncates against
    /// `badgeLeadingGap` either way and a fixed-size count never takes a name's width from it.
    @Test func theSidebarCountIsTwelvePointOnBothPlatforms() {
        #expect(CadenceSidebarCountMetrics.fontSize == 12)
    }

    /// A count is a bare number until it would start costing the name beside it.
    @Test func aCountUnderTheThresholdIsJustItsDigits() {
        for value in [1, 7, 42, 998, 999] {
            let count = CadenceSidebarCount(value: value, emphasis: .neutral)
            #expect(CadenceSidebarCountMetrics.displayText(for: count) == "\(value)")
        }
    }

    /// Above it, the count clamps rather than widens: a four-digit tally in a 188–200pt column
    /// would eat the list name it belongs to, and "how many over a thousand" is not actionable.
    @Test func aCountOverTheThresholdClampsInsteadOfWidening() {
        for value in [1000, 4_321, Int.max] {
            let count = CadenceSidebarCount(value: value, emphasis: .neutral)
            #expect(CadenceSidebarCountMetrics.displayText(for: count) == "999+")
        }
    }

    /// Emphasis is a colour, never a different string — the urgent count reads as the same number
    /// it would in neutral, in red.
    @Test func emphasisDoesNotChangeTheText() {
        for value in [3, 1_500] {
            let neutral = CadenceSidebarCount(value: value, emphasis: .neutral)
            let urgent = CadenceSidebarCount(value: value, emphasis: .urgent)

            #expect(
                CadenceSidebarCountMetrics.displayText(for: neutral)
                    == CadenceSidebarCountMetrics.displayText(for: urgent)
            )
        }
    }

    /// The threshold and the clamped string are one decision, so the label can never read "999+"
    /// for a count of 1000 while the rule says something else.
    @Test func theClampStringIsBuiltFromTheThreshold() {
        let atThreshold = CadenceSidebarCount(value: CadenceSidebarCountMetrics.overflowThreshold, emphasis: .neutral)
        let overThreshold = CadenceSidebarCount(value: CadenceSidebarCountMetrics.overflowThreshold + 1, emphasis: .neutral)

        #expect(CadenceSidebarCountMetrics.displayText(for: atThreshold) == "\(CadenceSidebarCountMetrics.overflowThreshold)")
        #expect(CadenceSidebarCountMetrics.displayText(for: overThreshold) == "\(CadenceSidebarCountMetrics.overflowThreshold)+")
    }
}

/// The rest of the sidebar's figures, which went through the same consolidation the count did.
///
/// The two columns had each been deciding for themselves and had drifted in five dimensions nobody
/// chose: 15pt glyphs against 13, 13pt labels against 14, 10pt of icon-to-label against 9, a 14pt
/// list colour bar against 16, and a 10pt due-date caption against 11. The user asked for one
/// sidebar, so these live in `CadenceSidebarMetrics` and both files read them.
///
/// `Cadence/iOS/` is invisible to this macOS-built target, so — exactly as above — what is pinned
/// is the value type, not the views.
struct CadenceSidebarMetricsTests {
    private let desktop = CadenceSidebarMetrics.metrics(for: .desktop)
    private let tablet = CadenceSidebarMetrics.metrics(for: .tablet)

    /// **Row height is the only figure allowed to differ, and it must.** 32pt is right under a
    /// pointer; a finger needs 44, and a nav row is the most-tapped control in the iPad shell.
    /// Flattening this would read as a tidy-up and be an ergonomic regression.
    @Test func rowHeightIsTheOnlyFigureThatDiffersBySurface() {
        #expect(desktop.rowHeight == CadenceSidebarMetrics.pointerRowHeight)
        #expect(tablet.rowHeight == CadenceSidebarMetrics.touchRowHeight)
        #expect(desktop.rowHeight != tablet.rowHeight)

        // Everything else is the same object with that one field changed. Rebuilding the desktop
        // struct out of the tablet's other nineteen figures and expecting equality is what makes a
        // *new* divergence fail here, rather than only the figures someone remembered to assert.
        #expect(
            desktop
                == CadenceSidebarRowMetrics(
                    rowHeight: desktop.rowHeight,
                    cornerRadius: tablet.cornerRadius,
                    rowSpacing: tablet.rowSpacing,
                    horizontalPadding: tablet.horizontalPadding,
                    iconSlotWidth: tablet.iconSlotWidth,
                    iconSize: tablet.iconSize,
                    iconLabelSpacing: tablet.iconLabelSpacing,
                    labelFontSize: tablet.labelFontSize,
                    badgeLeadingGap: tablet.badgeLeadingGap,
                    secondaryIconOpacity: tablet.secondaryIconOpacity,
                    groupSpacing: tablet.groupSpacing,
                    sectionSpacing: tablet.sectionSpacing,
                    listColorBarWidth: tablet.listColorBarWidth,
                    listColorBarHeight: tablet.listColorBarHeight,
                    listColorBarLeadingInset: tablet.listColorBarLeadingInset,
                    listLabelFontSize: tablet.listLabelFontSize,
                    listDueDateIconSize: tablet.listDueDateIconSize,
                    listDueDateFontSize: tablet.listDueDateFontSize,
                    listDueDateSpacing: tablet.listDueDateSpacing,
                    listTrailingItemSpacing: tablet.listTrailingItemSpacing
                )
        )
    }

    /// The five figures that were actually forked, named individually so a regression says which
    /// one came back rather than only that the structs differ.
    @Test func theFiveDriftedFiguresLandedOnTheMacOSSpelling() {
        #expect(desktop.iconSize == 15)
        #expect(desktop.labelFontSize == 13)
        #expect(desktop.iconLabelSpacing == 10)
        #expect(desktop.listColorBarHeight == 14)
        #expect(desktop.listDueDateFontSize == 10)
    }

    /// The macOS enum is the shared type's spelling, not a second set of numbers.
    @Test func theMacOSMetricsEnumForwardsToTheSharedFigures() {
        #expect(SidebarMetrics.rowHeight == desktop.rowHeight)
        #expect(SidebarMetrics.iconSize == desktop.iconSize)
        #expect(SidebarMetrics.labelFontSize == desktop.labelFontSize)
        #expect(SidebarMetrics.iconLabelSpacing == desktop.iconLabelSpacing)
        #expect(SidebarMetrics.rowCornerRadius == desktop.cornerRadius)
        #expect(SidebarMetrics.listColorBarHeight == desktop.listColorBarHeight)
        #expect(SidebarMetrics.listDueDateFontSize == desktop.listDueDateFontSize)
        #expect(SidebarMetrics.badgeLeadingGap == desktop.badgeLeadingGap)
        #expect(SidebarMetrics.groupSpacing == desktop.groupSpacing)
        #expect(SidebarMetrics.secondaryIconOpacity == desktop.secondaryIconOpacity)
    }
}

/// The glyph tint, which both columns now draw.
///
/// The iPad drew every glyph in `Theme.dim` on the argument that macOS only keeps its hues because
/// Settings → Sidebar has a colour picker there. The preference is a plain string, so the rule for
/// reading it is shared and the picker's absence on iPad stops being a reason to look different.
struct CadenceSidebarTintTests {
    @Test func anUnsetPreferenceGivesEveryDestinationItsOwnDefault() {
        for destination in CadenceFeatureDestination.allCases {
            #expect(CadenceSidebarTint.hex(for: destination, overridesRaw: "") == destination.defaultColorHex)
        }
    }

    @Test func anOverrideWinsForItsDestinationAndOnlyThatOne() {
        let raw = "today:#112233,calendar:#445566"

        #expect(CadenceSidebarTint.hex(for: .today, overridesRaw: raw) == "#112233")
        #expect(CadenceSidebarTint.hex(for: .calendar, overridesRaw: raw) == "#445566")
        #expect(CadenceSidebarTint.hex(for: .habits, overridesRaw: raw) == CadenceFeatureDestination.habits.defaultColorHex)
    }

    /// Garbage in the preference must not take a row's colour away, and an entry for a destination
    /// the sidebar no longer offers a handle for — `inbox`, since the merge — is simply ignored.
    @Test func unparseableEntriesAreDroppedRatherThanBlankingARow() {
        let raw = "nonsense,inbox:#000000,today:#112233,malformed:"

        #expect(CadenceSidebarTint.overrides(from: raw)[.today] == "#112233")
        #expect(CadenceSidebarTint.hex(for: .allTasks, overridesRaw: raw) == CadenceFeatureDestination.allTasks.defaultColorHex)
    }

    /// The macOS enum reads the same map, keyed through its own raw values. The two enums share raw
    /// values by construction, and this is what would fail if one were renamed.
    @Test func theMacOSColourMapAgreesWithTheSharedOne() {
        let raw = "today:#112233,focus:#445566"
        let macMap = SidebarStaticDestination.colorHexMap(from: raw)

        #expect(macMap[.today] == "#112233")
        #expect(macMap[.focus] == "#445566")
        #expect(SidebarStaticDestination.today.resolvedColorHex(from: raw) == "#112233")
        #expect(
            SidebarStaticDestination.habits.resolvedColorHex(from: raw)
                == CadenceFeatureDestination.habits.defaultColorHex
        )
    }
}

/// Where a destination's *default* tint comes from.
///
/// Ten of the eleven arms of `CadenceFeatureDestination.defaultColorHex` were hand-typed hex
/// literals (T-166) — a second copy of a palette `Theme` already owned, which had drifted from it
/// in three of the five hues. The observable symptom was two ambers for one destination: the
/// sidebar drew Today in `#FFB84D` while the Cmd+K palette, which derives its tint from
/// `Theme.amber`, drew the same row in `#ffa94d`.
///
/// These tests pin the **relation** — the defaults are read from `Theme`'s accent tokens — not a
/// list of expected strings, which a re-introduced literal would satisfy just as well. So there are
/// two halves: a value assertion that every default *is* a token's value, and a source assertion
/// that every arm *reads* the token. The second is the one that survives someone typing
/// `"#ffa94d"`, which the first cannot see.
struct CadenceFeatureDestinationTintTests {
    /// Value half. A default that is not one of `Theme`'s accent hexes is a hue this app's palette
    /// does not contain.
    @Test func everyDestinationDefaultIsOneOfThemesAccentHexes() {
        let accents = Set(
            [Theme.blueHex, Theme.redHex, Theme.greenHex, Theme.amberHex, Theme.purpleHex, Theme.tealHex]
                .map { $0.lowercased() }
        )
        #expect(accents.count == 6, "six accents, all distinct")

        for destination in CadenceFeatureDestination.allCases {
            #expect(
                accents.contains(destination.defaultColorHex.lowercased()),
                "\(destination.rawValue) defaults to \(destination.defaultColorHex), which is not a Theme accent"
            )
        }
    }

    /// The families are deliberate: two destinations sharing a token is how they read as related,
    /// and this is what would fail if someone "de-duplicated" the switch by giving Habits its own
    /// hue or split Notes from Search.
    @Test func theSharedHuesAreTheFamiliesThemeDocuments() {
        #expect(CadenceFeatureDestination.today.defaultColorHex == Theme.amberHex)
        #expect(CadenceFeatureDestination.habits.defaultColorHex == Theme.amberHex)
        #expect(CadenceFeatureDestination.allTasks.defaultColorHex == Theme.blueHex)
        #expect(CadenceFeatureDestination.inbox.defaultColorHex == Theme.blueHex)
        #expect(CadenceFeatureDestination.settings.defaultColorHex == Theme.blueHex)
        #expect(CadenceFeatureDestination.notes.defaultColorHex == Theme.purpleHex)
        #expect(CadenceFeatureDestination.search.defaultColorHex == Theme.purpleHex)
        #expect(CadenceFeatureDestination.lists.defaultColorHex == Theme.greenHex)
        #expect(CadenceFeatureDestination.goals.defaultColorHex == Theme.greenHex)
        #expect(CadenceFeatureDestination.calendar.defaultColorHex == Theme.redHex)
        #expect(CadenceFeatureDestination.focus.defaultColorHex == Theme.tealHex)
    }

    /// Source half — the assertion the value half cannot make. A literal whose value happens to
    /// match its token today passes `everyDestinationDefaultIsOneOfThemesAccentHexes` and still
    /// reopens the drift, because the next hue change to `Theme` will not reach it.
    @Test func noArmOfTheSwitchSpellsAHexLiteral() throws {
        let body = try tintSwitchBody()

        // Non-vacuity: the extraction found a real switch with an arm per case, so a rename or a
        // move fails this test rather than passing it against an empty string.
        #expect(!body.isEmpty)
        let arms = regexMatches("(?m)case \\.\\w+: return ", in: body)
        #expect(
            arms.count == CadenceFeatureDestination.allCases.count,
            "expected one arm per destination, read \(arms.count)"
        )
        // And the comment stripper ran: the prose explaining Calendar's red is gone, the code is not.
        #expect(!body.contains("at the user's request"))
        #expect(body.contains("case .calendar: return"))

        let literals = regexMatches(hexLiteralPattern, in: body)
        #expect(literals.isEmpty, "these arms still spell a hex instead of reading a Theme token: \(literals)")

        // Positive polarity, so the test says what the file should do rather than only what it
        // should not: every arm reads a `Theme.<name>Hex`.
        let tokenReads = regexMatches("return Theme\\.\\w+Hex\\b", in: body)
        #expect(tokenReads.count == CadenceFeatureDestination.allCases.count)
    }

    /// Self-check on the needle, so a typo in the pattern cannot quietly pass every scan built on
    /// it: it must match the literal this test bans and must not match the token that replaced it.
    @Test func theHexNeedleMatchesALiteralAndNotATokenRead() {
        let banned = "        case .today: return \"#FFB84D\""
        let wanted = "        case .today: return Theme.amberHex"

        #expect(banned.range(of: hexLiteralPattern, options: .regularExpression) != nil)
        #expect(wanted.range(of: hexLiteralPattern, options: .regularExpression) == nil)
    }

    /// `Theme` derives each accent `Color` from its own hex string, never the reverse and never
    /// from a re-typed literal. This is what makes the token trustworthy as a default: a token that
    /// does not build its own `Color` is a palette with two values for one accent, which is the
    /// shape T-166 was.
    @Test func eachThemeAccentColourIsBuiltFromItsOwnHexToken() throws {
        let theme = strippingSwiftComments(try tintSourceFile("Cadence/Shared/Theme.swift"))
        let tokens = regexMatches("static let \\w+Hex =", in: theme)
            .map { $0.replacingOccurrences(of: "static let ", with: "").replacingOccurrences(of: "Hex =", with: "") }

        #expect(Set(tokens) == ["blue", "red", "green", "amber", "purple", "teal"])

        for token in tokens {
            #expect(
                theme.contains("static let \(token) = Color(hex: \(token)Hex)"),
                "Theme.\(token) does not read Theme.\(token)Hex"
            )
        }
    }
}


/// Where the **command palette** gets a destination's tint from (T-244).
///
/// Cmd+K hand-assigned each row a `Theme` accent, and three of them named a different hue than the
/// sidebar draws the same destination in — Focus `Theme.red` against the sidebar's teal, Calendar
/// `Theme.purple` against the sidebar's red, Settings `Theme.dim` against the sidebar's blue. It
/// also never read `CadencePreferenceKeys.sidebarTabColors`, so a retinted destination kept its
/// old colour in the palette. The sidebar is the source of truth for a destination's identity
/// colour — it is where Settings → Sidebar lets the user *change* it — so the palette follows it.
///
/// **The assertions are relations, and the second is the mutation-proof one.** T-166's lesson is
/// that replacing a token with its own current value as a literal passes every value assertion; so
/// the override half feeds in hexes that are in no palette at all (`#010203`…). No hand-assigned
/// colour, `Theme` token or literal can produce those — only a read of the preference can.
@MainActor
struct GlobalSearchDestinationTintTests {

    /// A synthetic `sidebarTabColors` string covering every destination, with a hex that appears
    /// in no palette in this app. `CadenceSidebarTint.hex` is the only way a row can wear one.
    private var syntheticOverrides: [CadenceFeatureDestination: String] {
        CadenceFeatureDestination.allCases.enumerated().reduce(into: [:]) { partial, pair in
            partial[pair.element] = String(format: "#%02X0203", pair.offset + 1)
        }
    }

    private var syntheticRaw: String {
        syntheticOverrides
            .map { "\($0.key.rawValue):\($0.value)" }
            .sorted()
            .joined(separator: ",")
    }

    /// Every page row, keyed by the destination it opens. Built from the catalog rather than from
    /// a hand-written list, so a new page is covered the day it is added.
    private func pageRows(overridesRaw: String) -> [CadenceFeatureDestination: GlobalSearchResult] {
        let results = GlobalSearchDataSupport.pageResults(
            query: "",
            hiddenTabs: [],
            sidebarTabColorsRaw: overridesRaw
        )
        return GlobalSearchPageDefinition.all.reduce(into: [:]) { partial, page in
            guard let result = results.first(where: { $0.id == "page-\(page.label)" }) else { return }
            partial[page.feature] = result
        }
    }

    private func commandRows(overridesRaw: String) -> [GlobalSearchCommand: GlobalSearchResult] {
        let results = GlobalSearchDataSupport.commandResults(query: "", sidebarTabColorsRaw: overridesRaw)
        return results.reduce(into: [:]) { partial, result in
            guard case let .command(command) = result.destination else { return }
            partial[command] = result
        }
    }

    /// Non-vacuity. Every assertion below is a loop over these, and a loop over nothing passes.
    @Test func thePaletteOffersEveryPageAndCommandItsCatalogDeclares() {
        let pages = pageRows(overridesRaw: "")
        #expect(pages.count == GlobalSearchPageDefinition.all.count)
        #expect(pages.count >= 9, "read \(pages.count) page rows")
        // `item` is derived from `feature` and `pageResults` drops a row whose destination the
        // sidebar cannot route to, so this is also the guard on that `guard let`.
        for page in GlobalSearchPageDefinition.all {
            #expect(page.item != nil, "\(page.label) has no routable sidebar item")
            #expect(pages[page.feature] != nil, "\(page.label) produced no palette row")
        }

        let commands = commandRows(overridesRaw: "")
        #expect(commands.count == GlobalSearchCommandDefinition.all.count)
        #expect(commands.count >= 6, "read \(commands.count) command rows")

        // And the rows are not all one colour, so an "everything matches" pass is meaningful.
        #expect(Set(pages.values.map(\.tintHex)).count >= 3)
    }

    /// Hue half: with nothing overridden, every palette row is the colour the **sidebar** draws
    /// that destination in. This is the half that fails against `Theme.red` for Focus.
    @Test func everyPageRowUsesTheSidebarsDefaultTintForItsDestination() {
        for (destination, result) in pageRows(overridesRaw: "") {
            #expect(
                result.tintHex == destination.defaultColorHex,
                "\(destination.rawValue) page row is \(result.tintHex), sidebar draws it \(destination.defaultColorHex)"
            )
        }
    }

    /// **T-258 — glyph half.** The tint was made to follow the destination and the glyph was left
    /// stored beside it, which is how eight of nine rows kept agreeing while Notes quietly did not:
    /// the palette drew `doc.text`, the sidebar drew `note.text`.
    ///
    /// Asserted on the **row the palette actually produces**, not on the catalog entry and not by
    /// reading the source: `pageResults` is the whole pipeline, so a future definition that
    /// reintroduces a stored `icon` fails here even if the shared spelling survives somewhere
    /// unreachable in the same file.
    @Test func everyPageRowDrawsTheSidebarsGlyphForItsDestination() {
        let pages = pageRows(overridesRaw: "")
        #expect(pages.count >= 9, "non-vacuity: read \(pages.count) page rows")

        for (destination, result) in pages {
            #expect(
                result.icon == destination.systemImage,
                "\(destination.rawValue) page row draws \(result.icon), the sidebar draws \(destination.systemImage)"
            )
        }

        // The row this ticket was filed about, stated as the value a user sees rather than as a
        // relation that would also hold if both sides drifted together.
        #expect(pages[.notes]?.icon == "note.text")
        #expect(pages[.notes]?.icon != "doc.text")

        // Non-vacuity for the loop: the rows are not all one glyph, so "they all match" is not
        // nine copies of one assertion.
        #expect(Set(pages.values.map(\.icon)).count >= 5)
    }

    @Test func everyCommandRowUsesTheSidebarsDefaultTintForItsDestination() {
        for (command, result) in commandRows(overridesRaw: "") {
            #expect(
                result.tintHex == command.tintSource.defaultColorHex,
                "\(command.rawValue) command row is \(result.tintHex), not \(command.tintSource.defaultColorHex)"
            )
        }
    }

    /// The three rows the palette and the sidebar disagreed about, named so the regression has a
    /// test that says its own name. Spelled as a relation against `CadenceSidebarTint` rather than
    /// as three expected strings — a literal is exactly what this ticket was about.
    @Test func theThreeRowsThatDisagreedWithTheSidebarNowFollowIt() {
        let pages = pageRows(overridesRaw: "")
        for destination in [CadenceFeatureDestination.focus, .calendar, .settings] {
            #expect(
                pages[destination]?.tintHex == CadenceSidebarTint.hex(for: destination, overridesRaw: ""),
                "\(destination.rawValue) still names its own colour"
            )
        }
        // Non-vacuity for this trio specifically: three destinations, three different hues, so
        // "they all match" is not three copies of one assertion.
        #expect(Set([CadenceFeatureDestination.focus, .calendar, .settings].map(\.defaultColorHex)).count == 3)
    }

    /// Override half — the one no literal can pass. `#010203`-shaped hexes are in no palette, so a
    /// row wearing one proves the palette read `CadencePreferenceKeys.sidebarTabColors`.
    @Test func aRetintedDestinationIsRetintedInThePaletteToo() {
        let raw = syntheticRaw
        #expect(!raw.isEmpty)

        for (destination, result) in pageRows(overridesRaw: raw) {
            #expect(
                result.tintHex == syntheticOverrides[destination],
                "\(destination.rawValue) page row ignored the override: \(result.tintHex)"
            )
            #expect(result.tintHex != destination.defaultColorHex, "the override must actually differ")
        }

        for (command, result) in commandRows(overridesRaw: raw) {
            #expect(
                result.tintHex == syntheticOverrides[command.tintSource],
                "\(command.rawValue) command row ignored the override: \(result.tintHex)"
            )
        }
    }

    /// `toggleable` is derived from the destination now rather than typed beside it, so this pins
    /// the derivation through the behaviour it drives: a hidden row says so in its subtitle, and
    /// Inbox — a view inside Tasks, with no sidebar row and so no toggle — never can.
    @Test func aHiddenDestinationStillSaysSoInItsSubtitle() {
        let results = GlobalSearchDataSupport.pageResults(
            query: "",
            hiddenTabs: [.focus],
            sidebarTabColorsRaw: ""
        )
        let focus = results.first { $0.id == "page-Focus" }
        #expect(focus?.subtitle.contains("Hidden from sidebar") == true)

        let calendar = results.first { $0.id == "page-Calendar" }
        #expect(calendar?.subtitle.contains("Hidden from sidebar") == false)

        #expect(GlobalSearchPageDefinition.all.first { $0.feature == .inbox }?.toggleable == nil)
        #expect(GlobalSearchPageDefinition.all.first { $0.feature == .focus }?.toggleable == .focus)
    }

    /// iOS's Search page is the same surface on the other platform, and it is inside
    /// `#if os(iOS)` — invisible to this macOS-built target — so this is a source scan. It already
    /// agreed with the sidebar on *hue* (it read `destination.tint`), and silently disagreed with
    /// it for anyone who had retinted a row, because a default is not an override.
    @Test func iOSSearchResolvesItsPageTintThroughTheSharedHelperToo() throws {
        let source = strippingSwiftComments(try tintSourceFile("Cadence/iOS/iOSSearchView.swift"))

        // Non-vacuity: the file was read, and the stripper ran (the prose naming the old spelling
        // sits in a doc comment directly above the fixed line).
        #expect(source.count > 5_000, "read \(source.count) characters")
        #expect(source.contains("private var pageResults: [iOSSearchResult]"))
        #expect(!source.contains("until T-244"))

        #expect(source.contains("CadenceSidebarTint.hex(for: destination, overridesRaw: sidebarTabColorsRaw)"))
        #expect(source.contains("CadencePreferenceKeys.sidebarTabColors"))
        // The specific spelling that ignores the override, and only that — `tint:` arguments
        // elsewhere in this file are unrelated controls, so the needle is qualified.
        #expect(!source.contains("color: destination.tint"))
    }

    /// **The relation the value assertions above cannot make: one resolver, not two.**
    ///
    /// Every check in this suite is behavioural, and behaviour cannot tell `CadenceSidebarTint.hex`
    /// apart from a second copy of its body inlined here — `overrides(from:)[feature] ?? default`
    /// returns the same string for every input. That is exactly the shape T-244 was: two lists
    /// answering "what colour is this destination", agreeing until one of them was changed. The
    /// sidebar's list moved to teal and red and the palette's did not.
    ///
    /// It is also the shape T-166's mutation exposed — a token replaced by its own current value
    /// passes every value assertion. So this asserts the *call*, positively, in both surfaces.
    @Test func bothSearchSurfacesResolveADestinationsTintThroughTheOneSharedFunction() throws {
        let files = [
            "Cadence/macOS/Views/GlobalSearchSupportViews.swift",
            "Cadence/iOS/iOSSearchView.swift"
        ]

        for path in files {
            let source = strippingSwiftComments(try tintSourceFile(path))

            // Non-vacuity, per file: a scan that silently read nothing passes every assertion.
            #expect(source.count > 3_000, "\(path) read \(source.count) characters")

            let calls = regexMatches("CadenceSidebarTint\\.hex\\(for: ", in: source)
            #expect(!calls.isEmpty, "\(path) resolves a destination tint without the shared helper")

            // And no hand-typed palette literal anywhere in the file, which is what both surfaces
            // spelled before: the palette's `?? "#5AA2FF"` fallbacks and the drifted `#9E8CFF`.
            let literals = regexMatches(hexLiteralPattern, in: source)
            #expect(literals.isEmpty, "\(path) spells a hex literal: \(literals)")
        }
    }

    /// Self-check on that last needle, so a typo cannot quietly pass the scan: it must match the
    /// spelling this test bans and must not match the one that replaced it.
    @Test func theIOSNeedleMatchesTheOldSpellingAndNotTheNewOne() {
        let banned = "                color: destination.tint,"
        let wanted = "                color: Color(hex: CadenceSidebarTint.hex(for: destination, overridesRaw: sidebarTabColorsRaw)),"

        #expect(banned.contains("color: destination.tint"))
        #expect(!wanted.contains("color: destination.tint"))
    }
}


/// Every non-overlapping match of `pattern`. Spelled as a loop over `range(of:options:)` rather
/// than `ranges(of:options:)` so the scan does not depend on which Foundation overload the test
/// target resolves.
private func regexMatches(_ pattern: String, in source: String) -> [String] {
    var results: [String] = []
    var searchStart = source.startIndex
    while let match = source.range(of: pattern, options: .regularExpression, range: searchStart..<source.endIndex) {
        results.append(String(source[match]))
        searchStart = match.upperBound > match.lowerBound ? match.upperBound : source.index(after: match.lowerBound)
        if searchStart >= source.endIndex { break }
    }
    return results
}

/// `"#abc"` through `"#aabbccdd"`, quoted — the shape of a hand-typed palette literal. Deliberately
/// requires the quotes, so a `Theme.amberHex` read cannot match it and the needle is not a
/// substring of the correct post-fix text.
private let hexLiteralPattern = "\"#[0-9A-Fa-f]{3,8}\""

/// The body of `CadenceFeatureDestination.defaultColorHex`'s `switch`, comments blanked out.
private func tintSwitchBody() throws -> String {
    let source = strippingSwiftComments(try tintSourceFile("Cadence/Shared/CadenceFeatureDestination.swift"))
    guard let start = source.range(of: "var defaultColorHex: String {") else {
        Issue.record("CadenceFeatureDestination no longer declares defaultColorHex")
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

/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree), so read relative to it rather than resolving anything.
private func tintSourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks `//` and `/* */` comments so the assertions read code rather than prose — the doc comment
/// above `defaultColorHex` quotes the very literals its body must not contain.
private func strippingSwiftComments(_ source: String) -> String {
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
