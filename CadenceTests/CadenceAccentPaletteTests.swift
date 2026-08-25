import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-15: the six accents are selectable, and nothing else is.
///
/// Every assertion here is a **value** assertion where one is available, because this suite's
/// nearest neighbour — `CadenceColorPaletteTests` — exists precisely because source-scanning is
/// what catches a token being respelled and value-scanning is what catches a token no longer
/// resolving. The mechanism under test is the second kind: `Theme.blue` used to be a `static let`
/// and is now a computed read through `CadenceAccentPaletteSelection`, so the failure this suite
/// is for is "a colour stopped following the selection", not "someone typed a hex".
@MainActor
struct CadenceAccentPaletteCatalogueTests {

    @Test func thereAreThreeSetsAndTheStandardOneIsCadence() {
        #expect(CadenceAccentPalette.all.count == 3)
        #expect(CadenceAccentPalette.all.map(\.id) == ["cadence", "ember", "glacier"])
        #expect(CadenceAccentPalette.standard == CadenceAccentPalette.cadence)
        #expect(CadenceAccentPalette.all.first == CadenceAccentPalette.standard)
    }

    /// The standard set is the one the app shipped with, hue for hue.
    ///
    /// Stated as literals on purpose: three `@Model` `colorHex` defaults and every stored
    /// `colorHex` already on disk were seeded from these exact strings, so moving one silently
    /// re-colours the default every new context, goal and habit is drawn with. That is T-166's
    /// failure mode, and making the accents selectable did not make it cheaper.
    @Test func theStandardSetIsTheSixValuesTheAppShippedWith() {
        let standard = CadenceAccentPalette.standard
        #expect(standard.blueHex == "#4a9eff")
        #expect(standard.redHex == "#ff6b6b")
        #expect(standard.greenHex == "#4ecb71")
        #expect(standard.amberHex == "#ffa94d")
        #expect(standard.purpleHex == "#a78bfa")
        #expect(standard.tealHex == "#45CBC4")
    }

    @Test func everySetIsSixDistinctSixDigitHexesAndNoTwoSetsAreTheSame() {
        var seenIDs: Set<String> = []
        var seenSignatures: Set<[String]> = []

        for palette in CadenceAccentPalette.all {
            #expect(seenIDs.insert(palette.id).inserted, "duplicate palette id \(palette.id)")
            #expect(!palette.name.isEmpty)
            #expect(!palette.detail.isEmpty)

            let hexes = palette.swatchHexes
            #expect(hexes.count == 6, "\(palette.id) does not publish six hues")
            #expect(Set(hexes.map { $0.lowercased() }).count == 6, "\(palette.id) repeats a hue")

            for hex in hexes {
                #expect(
                    hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
                    "\(palette.id) publishes \(hex), which is not a six-digit hex"
                )
            }

            let signature = hexes.map { $0.lowercased() }
            #expect(seenSignatures.insert(signature).inserted, "\(palette.id) duplicates another set")
        }
    }

    /// The strip is warm through cool, and it is the six accents rather than a re-listing of them:
    /// a row that dropped a hue would still draw five circles and look fine.
    @Test func theSwatchStripIsTheSixAccentsInOneLapOfTheHueCircle() {
        for palette in CadenceAccentPalette.all {
            #expect(palette.swatchHexes == [
                palette.redHex, palette.amberHex, palette.greenHex,
                palette.tealHex, palette.blueHex, palette.purpleHex,
            ])
        }
    }

    /// Every hue has to be readable on `Theme.bg`, which is the one thing a dark-only palette can
    /// get wrong in a way no test of "is it a valid hex" would notice.
    @Test func everyHueIsLightEnoughToReadOnTheAppBackground() {
        let backgroundLuminance = t15RelativeLuminance(Theme.bg)
        #expect(backgroundLuminance < 0.02, "non-vacuity: Theme.bg is still near-black")

        for palette in CadenceAccentPalette.all {
            for hex in palette.swatchHexes {
                let ratio = t15ContrastRatio(t15RelativeLuminance(Color(hex: hex)), backgroundLuminance)
                #expect(ratio > 4.5, "\(palette.id) \(hex) reads at \(ratio):1 on Theme.bg")
            }
        }
    }

    @Test func anUnknownOrMissingIDResolvesToTheStandardSetRatherThanNothing() {
        #expect(CadenceAccentPalette.palette(id: nil) == .standard)
        #expect(CadenceAccentPalette.palette(id: "") == .standard)
        #expect(CadenceAccentPalette.palette(id: "a-set-a-later-build-offered") == .standard)
        #expect(CadenceAccentPalette.palette(id: "ember") == .ember)
        #expect(CadenceAccentPalette.palette(id: "glacier") == .glacier)
    }

    /// The `*Light` variants are still derived by blending toward white rather than hand-picked,
    /// and they are derived from the *palette's* hex rather than from a frozen one.
    @Test func theLightVariantsAreDerivedFromTheSelectedSetsOwnHexes() {
        for palette in [CadenceAccentPalette.cadence, .ember, .glacier] {
            let resolution = CadenceAccentResolution(palette)
            for (base, light) in [
                (palette.blueHex, resolution.blueLight),
                (palette.greenHex, resolution.greenLight),
                (palette.amberHex, resolution.amberLight),
            ] {
                let baseRGB = t15RGB(Color(hex: base))
                let lightRGB = t15RGB(light)
                for channel in 0..<3 {
                    // 30% of the way to white, so every channel moves up and none reaches 1.
                    #expect(lightRGB[channel] > baseRGB[channel] - 0.001)
                    #expect(abs(lightRGB[channel] - (baseRGB[channel] + (1 - baseRGB[channel]) * 0.3)) < 0.01)
                }
            }
        }
    }
}

/// The mutation this ticket is verified by: switch the active set and watch the accents move while
/// the neutrals do not.
///
/// `@MainActor` and synchronous, and both matter. Every suite that pins a literal accent value —
/// `CadenceColorPaletteValueTests` and its four neighbours — is also `@MainActor`, so a
/// main-actor test that never suspends cannot be observed mid-switch by any of them. The
/// selection is restored through `defer` and written with `persist: false`, so nothing reaches
/// `UserDefaults` and no widget reload is pushed from a test run.
@MainActor
struct CadenceAccentPaletteSwitchTests {

    /// The accents move. All six, plus the derived variants, plus the AppKit mirrors, plus every
    /// surface that reads an accent through a *stored* declaration — which is the half that broke:
    /// a `static let` initialises once, so `CadenceColorPalette.colors` read after a switch would
    /// hand back the set that happened to be active the first time a colour grid was drawn.
    ///
    /// Each of those is read **before** the switch as well as after. A read-after-only assertion
    /// passes against a `static let` whenever the test happens to be the first thing to touch it.
    @Test func switchingTheSetMovesEveryAccentAndEverythingDerivedFromOne() {
        let selection = CadenceAccentPaletteSelection.shared
        let original = selection.palette
        defer { selection.select(original, persist: false) }

        selection.select(.cadence, persist: false)

        let beforeBlue = t15RGB(Theme.blue)
        let beforeBlueHex = Theme.blueHex
        let beforeDoneFill = t15RGB(Theme.doneFill)
        let beforeHighPriority = t15RGB(Theme.priorityColor(.high))
        let beforeNSBlue = Theme.nsBlue.usingColorSpace(.sRGB)!.redComponent
        let beforeAreaDefault = CadenceColorPalette.areaDefault
        let beforeListSwatches = CadenceColorPalette.colors
        let beforeSectionSwatches = CadenceColorPalette.sectionColors
        let beforeDestinationTints = CadenceColorPalette.destinationTints
        let beforeFocusTint = CadenceFeatureDestination.focus.defaultColorHex
        let beforeCompletedAccent = t15RGB(CadenceTodayPresentationSupport.completedSectionAccent)
        let beforeStylistBlue = MarkdownStylist.blueColor.usingColorSpace(.sRGB)!.redComponent

        #expect(beforeBlueHex == CadenceAccentPalette.cadence.blueHex, "non-vacuity: started on the standard set")

        selection.select(.glacier, persist: false)

        #expect(Theme.accentPalette == .glacier)
        #expect(Theme.blueHex == CadenceAccentPalette.glacier.blueHex)
        #expect(Theme.redHex == CadenceAccentPalette.glacier.redHex)
        #expect(Theme.greenHex == CadenceAccentPalette.glacier.greenHex)
        #expect(Theme.amberHex == CadenceAccentPalette.glacier.amberHex)
        #expect(Theme.purpleHex == CadenceAccentPalette.glacier.purpleHex)
        #expect(Theme.tealHex == CadenceAccentPalette.glacier.tealHex)

        #expect(t15RGB(Theme.blue) == t15RGB(Color(hex: CadenceAccentPalette.glacier.blueHex)))
        #expect(t15RGB(Theme.blue) != beforeBlue)
        #expect(t15RGB(Theme.doneFill) != beforeDoneFill)
        #expect(t15RGB(Theme.doneFill) == t15RGB(Theme.green), "doneFill is still the green")
        #expect(t15RGB(Theme.priorityColor(.high)) != beforeHighPriority)
        #expect(t15RGB(Theme.priorityColor(.high)) == t15RGB(Theme.red))

        // The AppKit mirrors, which the markdown editor draws with and which would otherwise keep
        // painting the old palette for the life of the process.
        #expect(Theme.nsBlue.usingColorSpace(.sRGB)!.redComponent != beforeNSBlue)
        #expect(MarkdownStylist.blueColor.usingColorSpace(.sRGB)!.redComponent != beforeStylistBlue)
        #expect(MarkdownStylist.blueColor == Theme.nsBlue)

        // The stored-declaration half.
        #expect(CadenceColorPalette.areaDefault != beforeAreaDefault)
        #expect(CadenceColorPalette.areaDefault == CadenceAccentPalette.glacier.blueHex)
        #expect(CadenceColorPalette.colors != beforeListSwatches)
        #expect(CadenceColorPalette.sectionColors != beforeSectionSwatches)
        #expect(CadenceColorPalette.destinationTints != beforeDestinationTints)
        #expect(CadenceColorPalette.destinationTints.contains(CadenceAccentPalette.glacier.tealHex))
        #expect(beforeCompletedAccent != t15RGB(CadenceTodayPresentationSupport.completedSectionAccent))

        // A destination's tint follows too, and its editor still offers it — the T-245 shape
        // arriving by a different road if `destinationTints` had been left frozen.
        #expect(CadenceFeatureDestination.focus.defaultColorHex != beforeFocusTint)
        #expect(CadenceFeatureDestination.focus.defaultColorHex == CadenceAccentPalette.glacier.tealHex)
        for destination in CadenceFeatureDestination.allCases {
            #expect(
                CadenceColorPalette.offered(
                    destination.defaultColorHex,
                    from: CadenceColorPalette.destinationTints
                ) == CadenceColorPalette.destinationTints,
                "\(destination.rawValue)'s default fell out of the menu that edits it"
            )
        }
    }

    /// And the chrome does not. This is the half the ticket was narrowed to protect: every screen
    /// in the app is drawn on these, so if one of them moved the narrowing bought nothing.
    @Test func switchingTheSetMovesNoNeutralNoOverlayAndNoRadius() {
        let selection = CadenceAccentPaletteSelection.shared
        let original = selection.palette
        defer { selection.select(original, persist: false) }

        selection.select(.cadence, persist: false)

        let neutrals: [(String, Color)] = [
            ("bg", Theme.bg), ("surface", Theme.surface), ("surfaceElevated", Theme.surfaceElevated),
            ("surfaceRecessed", Theme.surfaceRecessed), ("surfaceHover", Theme.surfaceHover),
            ("surfaceHighlight", Theme.surfaceHighlight), ("borderSubtle", Theme.borderSubtle),
            ("border", Theme.border), ("borderStrong", Theme.borderStrong), ("rule", Theme.rule),
            ("text", Theme.text), ("muted", Theme.muted), ("subdued", Theme.subdued),
            ("dim", Theme.dim),
            ("markerHighlightFill", Theme.markerHighlightFill),
            ("markerHighlightBorder", Theme.markerHighlightBorder),
            ("markerHighlightText", Theme.markerHighlightText),
            ("onColor", Theme.onColor), ("onColorSecondary", Theme.onColorSecondary),
            ("onColorBorder", Theme.onColorBorder), ("onColorHandle", Theme.onColorHandle),
            ("appleSignInFill", Theme.appleSignInFill),
            ("scrim", Theme.scrim), ("selectionWash", Theme.selectionWash),
            ("subtleWash", Theme.subtleWash), ("chipShadow", Theme.chipShadow),
            ("sidePanelShadow", Theme.sidePanelShadow), ("overlayCardShadow", Theme.overlayCardShadow),
            ("cardElevationShadow", Theme.cardElevationShadow),
        ]
        let before = neutrals.map { ($0.0, t15RGBA($0.1)) }
        let beforeNSBg = Theme.nsBg
        let beforeNSText = Theme.nsText
        let beforeNeutralSwatch = TaskSectionDefaults.defaultColorHex
        let beforeScheme = Theme.preferredColorScheme
        let beforeRadii = [Theme.radiusControl, Theme.radiusCard, Theme.radiusPanel]

        #expect(before.count == 29, "non-vacuity: the neutral sweep is still the whole ramp")

        selection.select(.ember, persist: false)
        #expect(Theme.blueHex == CadenceAccentPalette.ember.blueHex, "non-vacuity: the switch happened")

        for (index, entry) in before.enumerated() {
            #expect(
                t15RGBA(neutralValue(at: index)) == entry.1,
                "Theme.\(entry.0) moved with the accent palette"
            )
        }

        #expect(Theme.nsBg == beforeNSBg)
        #expect(Theme.nsText == beforeNSText)
        #expect(TaskSectionDefaults.defaultColorHex == beforeNeutralSwatch)
        #expect(Theme.preferredColorScheme == beforeScheme)
        #expect(Theme.preferredColorScheme == .dark, "still dark-only; no light variant was added")
        #expect([Theme.radiusControl, Theme.radiusCard, Theme.radiusPanel] == beforeRadii)
    }

    /// Re-reads the neutral at `index` *after* the switch. Spelled as a function rather than a
    /// second array literal so the two sweeps cannot fall out of step with each other.
    private func neutralValue(at index: Int) -> Color {
        [
            Theme.bg, Theme.surface, Theme.surfaceElevated,
            Theme.surfaceRecessed, Theme.surfaceHover,
            Theme.surfaceHighlight, Theme.borderSubtle,
            Theme.border, Theme.borderStrong, Theme.rule,
            Theme.text, Theme.muted, Theme.subdued,
            Theme.dim,
            Theme.markerHighlightFill, Theme.markerHighlightBorder, Theme.markerHighlightText,
            Theme.onColor, Theme.onColorSecondary,
            Theme.onColorBorder, Theme.onColorHandle,
            Theme.appleSignInFill,
            Theme.scrim, Theme.selectionWash,
            Theme.subtleWash, Theme.chipShadow,
            Theme.sidePanelShadow, Theme.overlayCardShadow,
            Theme.cardElevationShadow,
        ][index]
    }

    /// Selecting the set already in force is a no-op, so a picker row can be tapped twice without
    /// pushing a widget timeline reload each time.
    @Test func selectingTheActiveSetChangesNothing() {
        let selection = CadenceAccentPaletteSelection.shared
        let original = selection.palette
        defer { selection.select(original, persist: false) }

        selection.select(.ember, persist: false)
        let resolution = selection.resolution
        selection.select(.ember, persist: false)
        #expect(selection.resolution === resolution, "a redundant selection re-resolved the palette")
    }

    /// A user-owned `colorHex` is data, not a palette value. Switching sets must not rewrite one,
    /// and must not stop offering it either.
    @Test func aStoredColourSurvivesAPaletteSwitchAndStaysSelectable() {
        let selection = CadenceAccentPaletteSelection.shared
        let original = selection.palette
        defer { selection.select(original, persist: false) }

        selection.select(.cadence, persist: false)
        let stored = Theme.blueHex
        let area = Area(name: "Docs", colorHex: stored)
        #expect(CadenceColorPalette.colors.contains(stored), "non-vacuity: it was in the menu")

        selection.select(.glacier, persist: false)

        #expect(area.colorHex == stored, "a palette switch rewrote a stored colour")
        #expect(!CadenceColorPalette.colors.contains(stored), "non-vacuity: the menu moved on")
        #expect(
            CadenceColorPalette.offeredColors(for: stored).last == stored,
            "the stored hue is no longer selectable after a switch"
        )
    }
}

/// Where the selection is written, and why the widget half of the ticket shipped.
@MainActor
struct CadenceAccentPaletteStoreTests {

    @Test func aStoredSelectionRoundTripsAndAnUnknownOneFallsBack() throws {
        let suite = "com.haoranwei.Cadence.tests.t15.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        #expect(CadenceAccentPaletteStore.loadSelected(userDefaults: defaults) == .standard)

        CadenceAccentPaletteStore.storeSelected(.glacier, userDefaults: defaults)
        #expect(defaults.string(forKey: CadenceAccentPaletteStore.defaultsKey) == "glacier")
        #expect(CadenceAccentPaletteStore.loadSelected(userDefaults: defaults) == .glacier)

        defaults.set("a-set-a-later-build-offered", forKey: CadenceAccentPaletteStore.defaultsKey)
        #expect(CadenceAccentPaletteStore.loadSelected(userDefaults: defaults) == .standard)

        CadenceAccentPaletteStore.clearSelection(userDefaults: defaults)
        #expect(defaults.string(forKey: CadenceAccentPaletteStore.defaultsKey) == nil)
        #expect(CadenceAccentPaletteStore.loadSelected(userDefaults: defaults) == .standard)
    }

    /// The widget verdict, as a value rather than as a claim in a comment.
    ///
    /// `CadenceWidgets` is a separate process that compiles `Theme.swift`, so the selection only
    /// reaches it if it is written where that process can read it. This writes a probe through
    /// the store's own default suite and reads it back through a *freshly constructed* app-group
    /// `UserDefaults` — the same suite `CadenceWidgetRefreshCenter` already crosses. It touches no
    /// key the app owns and removes its own.
    @Test func theSelectionIsWrittenWhereTheWidgetProcessCanReadIt() throws {
        let store = CadenceAccentPaletteStore.sharedDefaults()
        #expect(store != UserDefaults.standard, "the selection would not cross the process boundary")

        let group = try #require(UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier))
        let probeKey = "cadence.tests.t15.\(UUID().uuidString)"
        defer { store.removeObject(forKey: probeKey) }

        store.set("glacier", forKey: probeKey)
        #expect(group.string(forKey: probeKey) == "glacier")

        // And the key the widget would read is a plain string it can resolve without this app.
        #expect(CadenceAccentPaletteStore.defaultsKey == "cadence.appearance.accentPaletteID")
        #expect(CadenceAccentPalette.palette(id: "glacier") == .glacier)
    }
}

/// The invariant that made this ticket wider than `Theme.swift`.
///
/// An accent read into a `static let` freezes on first access and never moves again — silently,
/// with no diagnostic and no wrong colour until someone switches sets and looks at the one surface
/// that stopped following. Three declarations were in that shape before T-15 touched them
/// (`CadenceColorPalette`'s swatch arrays, `CadenceTodayPresentationSupport.completedSectionAccent`
/// and `MarkdownStylist`'s three accent `NSColor`s), which is exactly the number a per-file list
/// would have missed the fourth of.
@MainActor
struct CadenceAccentStorageSweepTests {

    private static let accentReadPattern =
        #"static\s+let\s+\w+\s*(:[^=\n]+)?=\s*Theme\.(blue|red|green|amber|purple|teal|doneFill|accents|accentPalette|nsBlue|nsRed|nsGreen)\b"#

    /// The array-literal shape, which the direct-read pattern above cannot see: the token sits on
    /// a later line than the `=`. Bounded by the closing bracket rather than by a line count, so
    /// it cannot run past the declaration it is reading and accuse the next one.
    /// `CadenceColorPalette.destinationTints` was exactly this shape.
    private static let accentArrayPattern =
        #"static\s+let\s+\w+\s*(:\s*\[String\])?\s*=\s*\[[^\]]*Theme\.(blue|red|green|amber|purple|teal)"#
    /// The same shape, aimed at the stops that are *allowed* to be stored. `ns(Bg|Surface|…)` is
    /// spelled out rather than written as an optional `ns` prefix so it cannot accidentally admit
    /// `nsBlue`, `nsRed` or `nsGreen` — the three AppKit mirrors that are accents.
    private static let neutralReadPattern =
        #"static\s+let\s+\w+\s*(:[^=\n]+)?=\s*Theme\.(bg|surface|border|text|muted|dim|rule|scrim|radius|onColor|chipShadow|sidePanelShadow|overlayCardShadow|cardElevationShadow|marker|ns(Bg|Surface|Border|Text|Muted|Dim|Rule|Marker))"#

    @Test func noStoredDeclarationAnywhereInTheAppFreezesAnAccent() throws {
        let files = try t15SwiftFiles(under: "Cadence")
        #expect(files.count > 400, "non-vacuity: walked \(files.count) files")

        var offenders: [String] = []
        var neutralReads = 0
        for path in files {
            let source = t15StrippingSwiftComments(try String(contentsOfFile: path, encoding: .utf8))
            let name = (path as NSString).lastPathComponent
            for pattern in [Self.accentReadPattern, Self.accentArrayPattern] {
                for hit in t15RegexMatches(pattern, in: source) {
                    offenders.append("\(name): \(hit.prefix(80).trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
            neutralReads += t15RegexMatches(Self.neutralReadPattern, in: source).count
        }

        #expect(offenders.isEmpty, "these freeze an accent on first access: \(offenders)")
        // Non-vacuity in the direction that matters: the sweep does find `static let` reads of
        // `Theme`, so an empty accent list is a statement about accents and not about the regex.
        #expect(neutralReads > 12, "the sweep found only \(neutralReads) stored neutral reads")
    }

    /// Self-check on both needles, so a typo in either cannot quietly pass the sweep: each must
    /// match the shape it bans and must not match the computed spelling that replaced it.
    @Test func bothNeedlesMatchTheFrozenShapeAndNotTheComputedOne() {
        let frozenDirect = "    nonisolated static let blueColor      = Theme.nsBlue"
        let computedDirect = "    nonisolated static var blueColor: NSColor  { Theme.nsBlue }"
        #expect(t15RegexMatches(Self.accentReadPattern, in: frozenDirect).count == 1)
        #expect(t15RegexMatches(Self.accentReadPattern, in: computedDirect).isEmpty)

        let frozenArray = "    static let destinationTints = [\n        Theme.redHex, Theme.blueHex,\n    ]"
        let computedArray = "    static var destinationTints: [String] { [\n        Theme.redHex,\n    ] }"
        #expect(t15RegexMatches(Self.accentArrayPattern, in: frozenArray).count == 1)
        #expect(t15RegexMatches(Self.accentArrayPattern, in: computedArray).isEmpty)

        // And a stored *neutral* array is not accused, because storing a neutral is allowed.
        let frozenNeutralArray = "    static let stops = [\n        Theme.borderSubtle,\n    ]"
        #expect(t15RegexMatches(Self.accentArrayPattern, in: frozenNeutralArray).isEmpty)
    }

    /// Positive half: the three declarations that used to be stored read as computed now, and the
    /// neutral ones beside them are deliberately still stored.
    @Test func theThreeConvertedDeclarationsAreComputedAndTheirNeutralNeighboursAreNot() throws {
        let palette = t15StrippingSwiftComments(try t15SourceFile("Cadence/Shared/CadenceColorPalette.swift"))
        #expect(palette.contains("static var areaDefault: String { Theme.blueHex }"))
        #expect(palette.contains("static var destinationTints: [String] {"))

        let today = t15StrippingSwiftComments(try t15SourceFile("Cadence/Shared/CadenceTodayPresentationSupport.swift"))
        #expect(today.contains("static var completedSectionAccent: Color { Theme.green }"))

        let stylist = t15StrippingSwiftComments(try t15SourceFile("Cadence/macOS/Editor/MarkdownEditorSupport.swift"))
        #expect(stylist.contains("static var blueColor: NSColor  { Theme.nsBlue }"))
        #expect(stylist.contains("static let bgColor        = Theme.nsBg"), "the neutrals stay stored")

        let theme = t15StrippingSwiftComments(try t15SourceFile("Cadence/Shared/Theme.swift"))
        #expect(theme.contains("static let bg = Color(hex: \"#09090b\")"), "the neutral ramp is still fixed")
        #expect(theme.contains("static var blue: Color { accents.blue }"))
        #expect(!theme.contains("static let blue ="), "an accent went back to being stored")
    }

    /// Neither new screen hand-types a colour. The macOS half is already covered by
    /// `noFileOnTheMacOSSurfaceHandTypesAColourHex`; the shared picker and the iOS section are not
    /// under that walk, and the shared picker is the file most likely to grow a literal because it
    /// is the one that draws swatches for a living.
    @Test func neitherAppearanceScreenNorTheSharedPickerSpellsAHex() throws {
        for path in [
            "Cadence/Shared/Components/CadenceAccentPalettePicker.swift",
            "Cadence/iOS/iOSAppearanceSettingsSection.swift",
            "Cadence/macOS/Views/SettingsAppearanceSection.swift",
        ] {
            let source = t15StrippingSwiftComments(try t15SourceFile(path))
            #expect(source.contains("CadenceAccentPalette"), "non-vacuity: \(path) is still the picker")
            #expect(
                t15RegexMatches("\"#[0-9A-Fa-f]{3,8}\"", in: source).isEmpty,
                "\(path) hand-types a colour"
            )
        }
    }
}

/// Reaching the picker: one category on each platform, filed once, reading one shared list.
@MainActor
struct CadenceAppearanceSettingsReachTests {

    @Test func appearanceIsASharedCategoryBothPlatformsOffer() {
        #expect(CadenceSettingsCategoryKind.allCases.contains(.appearance))
        #expect(CadenceSettingsCategoryKind.appearance.title == "Appearance")
        #expect(!CadenceSettingsCategoryKind.appearance.icon.isEmpty)

        #expect(!CadenceMobileSettingsLayout.desktopOnly.contains(.appearance))
        #expect(CadenceMobileSettingsLayout.categories.contains(.appearance))

        #expect(SettingsCategory.appearance.sharedKind == .appearance)
        #expect(SettingsCategory.appearance.title == CadenceSettingsCategoryKind.appearance.title)
    }

    /// Filed under Interface beside Navigation and Sidebar, and *not* into the group of one that
    /// holds About — which a test next door pins as `[.about]` exactly.
    @Test func appearanceIsFiledInTheInterfaceGroupOnMacOSAndTheAppGroupOnMobile() throws {
        let interface = try #require(SettingsCategoryGroup.all.first { $0.title == "Interface" })
        #expect(interface.categories.contains(.appearance))
        #expect(interface.categories == [.appearance, .navigation, .sidebar])

        let app = try #require(CadenceMobileSettingsLayout.groups.first { $0.title == "App" })
        #expect(app.kinds.contains(.appearance))
        #expect(app.kinds.first == .appearance)
    }

    /// Both screens read the same list and the same copy, which is the whole reason the picker is
    /// in `Shared/Components/` rather than written twice.
    @Test func bothAppearanceScreensRenderTheOneSharedPicker() throws {
        let macOS = try t15SourceFile("Cadence/macOS/Views/SettingsAppearanceSection.swift")
        let iOS = try t15SourceFile("Cadence/iOS/iOSAppearanceSettingsSection.swift")

        for source in [macOS, iOS] {
            #expect(source.contains("CadenceAccentPalettePicker("))
            #expect(source.contains("CadenceAccentPalettePresentation.sectionTitle"))
            #expect(!source.contains("ForEach(CadenceAccentPalette.all)"), "a second hand-written list")
        }

        #expect(!CadenceAccentPalettePresentation.sectionTitle.isEmpty)
        #expect(CadenceAccentPalettePresentation.sectionTitle == "Accents")
        // The note is the one place the app says what a palette switch does *not* touch.
        #expect(CadenceAccentPalettePresentation.note.contains("dark"))
        #expect(CadenceAccentPalettePresentation.note.contains("already chosen"))

        for palette in CadenceAccentPalette.all {
            let label = CadenceAccentPalettePresentation.accessibilityLabel(for: palette)
            #expect(label.contains(palette.name))
            #expect(label.contains(palette.detail))
        }
    }
}

// MARK: - Helpers

/// sRGB components of a `Color`, so an assertion states a rendered value rather than trusting
/// `Color`'s own `Equatable`, which compares providers and not colours.
private func t15RGB(_ color: Color) -> [Double] {
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    return [
        (srgb.redComponent * 10000).rounded() / 10000,
        (srgb.greenComponent * 10000).rounded() / 10000,
        (srgb.blueComponent * 10000).rounded() / 10000,
    ]
}

/// `t15RGB` plus alpha, for the overlay and shadow tokens, which differ only in opacity.
private func t15RGBA(_ color: Color) -> [Double] {
    let resolved = NSColor(color)
    let srgb = resolved.usingColorSpace(.sRGB) ?? resolved
    return t15RGB(color) + [(srgb.alphaComponent * 10000).rounded() / 10000]
}

private func t15RelativeLuminance(_ color: Color) -> Double {
    let rgb = t15RGB(color)
    let linear = rgb.map { channel -> Double in
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
}

private func t15ContrastRatio(_ lhs: Double, _ rhs: Double) -> Double {
    let lighter = max(lhs, rhs)
    let darker = min(lhs, rhs)
    return (lighter + 0.05) / (darker + 0.05)
}

private func t15RegexMatches(_ pattern: String, in source: String) -> [String] {
    var results: [String] = []
    var searchStart = source.startIndex
    while let match = source.range(of: pattern, options: .regularExpression, range: searchStart..<source.endIndex) {
        results.append(String(source[match]))
        searchStart = match.upperBound > match.lowerBound ? match.upperBound : source.index(after: match.lowerBound)
        if searchStart >= source.endIndex { break }
    }
    return results
}

private func t15StrippingSwiftComments(_ source: String) -> String {
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

private func t15SourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private func t15SwiftFiles(under relativeDirectory: String) throws -> [String] {
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
