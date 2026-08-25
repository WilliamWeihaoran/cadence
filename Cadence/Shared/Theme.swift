import Observation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// One selectable set of the six accents — and **only** the six accents.
///
/// The near-black neutral ramp (`Theme.bg`, the `surface*` stops, the `border*` stops, the text
/// ramp, the marker-highlight pen, the on-colour foregrounds, the scrims and the shadows) is not
/// here and does not vary. That is the whole shape of the decision behind this type: the chrome
/// that appears on every screen keeps fixed values and therefore cannot regress, while the accents
/// carry the personality. There is no light variant either — `Theme.preferredColorScheme` is still
/// a hardcoded `.dark` — so nothing in the app has to grow a second reasoning path.
///
/// **Hex-string-first, in both directions.** A palette publishes six `String`s and every `Color`
/// is derived from them, because an app-defined *default* offered to the user (a sidebar glyph
/// tint, a model `colorHex` seed) is a palette decision that happens to be spelled as a string.
/// `CadenceColorPalette.destinationTints` and `CadenceFeatureDestination.defaultColorHex` read the
/// strings; deriving a `Color` first and a string from it is how three hues drifted in T-166.
///
/// **User-owned `colorHex` values are untouched by a palette change.** A list, tag, habit or
/// section stores the hex it was given; switching palettes changes what a *new* one is seeded with
/// and what the swatch menus offer, and rewrites nothing already saved. `CadenceColorPalette`'s
/// `offered(_:from:)` rule is what keeps a stored hue selectable after its palette stops offering
/// it — the same rule that already covered trimming a swatch array.
nonisolated struct CadenceAccentPalette: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// One line under the name in the picker. Says what the set *is*, not what picking it does.
    let detail: String

    let blueHex: String
    let redHex: String
    let greenHex: String
    let amberHex: String
    let purpleHex: String
    let tealHex: String

    /// The six, warm through cool — the same lap `CadenceColorPalette.destinationTints` reads in,
    /// so a swatch row here and the sidebar tint editor order their hues the same way.
    var swatchHexes: [String] { [redHex, amberHex, greenHex, tealHex, blueHex, purpleHex] }
}

nonisolated extension CadenceAccentPalette {
    /// The set the app shipped with, and the one every compile-time literal mirrors.
    ///
    /// Three `@Model` `colorHex` defaults and `TaskSectionDefaults.defaultColorHex` are literals
    /// in `Models/` — `CadenceMCPServer` compiles that folder and not this file — so they can only
    /// ever mirror *one* palette. This is that palette, which is why `standard` exists as a name
    /// separate from "whatever is active": a test that pins a literal has to state which set it is
    /// pinning it against.
    static let cadence = CadenceAccentPalette(
        id: "cadence",
        name: "Cadence",
        detail: "The original set. An even spread at medium saturation.",
        blueHex: "#4a9eff",
        redHex: "#ff6b6b",
        greenHex: "#4ecb71",
        amberHex: "#ffa94d",
        purpleHex: "#a78bfa",
        tealHex: "#45CBC4"
    )

    /// Warmer and higher-chroma: every hue pushed toward the fire side of itself.
    ///
    /// The six keep their jobs — red is still danger, green is still done, amber is still today,
    /// teal is still Focus — because the app assigns meaning by *name*, not by hue, and a set that
    /// re-sorted those meanings would not be a palette, it would be a different app. What moves is
    /// temperature: the blue loses its cyan lean, the green goes olive, the amber goes orange.
    static let ember = CadenceAccentPalette(
        id: "ember",
        name: "Ember",
        detail: "Warm and high-chroma. Every hue pushed toward the fire side of itself.",
        blueHex: "#5b8def",
        redHex: "#ff5a5f",
        greenHex: "#86c26a",
        amberHex: "#f2903d",
        purpleHex: "#c084fc",
        tealHex: "#3fb8a5"
    )

    /// Cooler and brighter, for more separation between the six on a near-black background.
    ///
    /// The counterweight to `ember`, chosen over a third *warm* variant on purpose: two sets that
    /// differ only in how warm they are read as one set drawn twice at a 15pt glyph, which is the
    /// size most of these are actually seen at.
    static let glacier = CadenceAccentPalette(
        id: "glacier",
        name: "Glacier",
        detail: "Cool and bright. More separation between the six on near-black.",
        blueHex: "#55b6ff",
        redHex: "#ff7a8a",
        greenHex: "#3ecf8e",
        amberHex: "#ffc857",
        purpleHex: "#9d8dff",
        tealHex: "#4fd6e0"
    )

    /// Three, in picker order. Two or three is the whole brief — a dozen near-identical dark sets
    /// is a menu nobody can tell apart, and every one added is six more hues to keep legible
    /// against `Theme.bg` and distinguishable from each other at glyph size.
    static let all: [CadenceAccentPalette] = [cadence, ember, glacier]

    /// The palette an unset or unrecognised selection resolves to.
    static let standard = cadence

    /// Never `nil`, never throws: an id written by a build that offered a set this one does not
    /// resolves to `standard` rather than leaving the app with no accents.
    static func palette(id: String?) -> CadenceAccentPalette {
        guard let id, let match = all.first(where: { $0.id == id }) else { return standard }
        return match
    }
}

/// One palette, resolved once into the values call sites actually read.
///
/// A reference type on purpose. `Theme.blue` is read from 431 places, most of them inside a
/// SwiftUI `body`, and the pre-selection spelling was a `static let` — a single global load. The
/// resolution has to be at least that cheap, so the accessors return a stored `let` off one
/// already-retained object rather than re-running `Color(hex:)`'s `Scanner` per read. The three
/// `NSColor` mirrors are here for the same reason and a stronger one: `NSColor(Color)` conversion
/// happens per glyph range in the markdown editor's drawing passes.
nonisolated final class CadenceAccentResolution: @unchecked Sendable {
    let palette: CadenceAccentPalette

    let blue: Color
    let blueLight: Color
    let red: Color
    let green: Color
    let greenLight: Color
    let amber: Color
    let amberLight: Color
    let purple: Color
    let teal: Color

    #if canImport(AppKit)
    let nsBlue: NSColor
    let nsRed: NSColor
    let nsGreen: NSColor
    #endif

    init(_ palette: CadenceAccentPalette) {
        self.palette = palette

        let blue = Color(hex: palette.blueHex)
        let red = Color(hex: palette.redHex)
        let green = Color(hex: palette.greenHex)
        let amber = Color(hex: palette.amberHex)

        self.blue = blue
        self.blueLight = cadenceLightened(palette.blueHex)
        self.red = red
        self.green = green
        self.greenLight = cadenceLightened(palette.greenHex)
        self.amber = amber
        self.amberLight = cadenceLightened(palette.amberHex)
        self.purple = Color(hex: palette.purpleHex)
        self.teal = Color(hex: palette.tealHex)

        #if canImport(AppKit)
        self.nsBlue = cadenceSRGBColor(blue)
        self.nsRed = cadenceSRGBColor(red)
        self.nsGreen = cadenceSRGBColor(green)
        #endif
    }
}

/// Where the selection is written, and the one reason widgets get this for free.
///
/// The key lives in the **app group** suite, not `.standard`, because `CadenceWidgets` is a
/// separate process that compiles this same file. `CadenceWidgetRefreshCenter` already crosses
/// that boundary through the same suite, so a widget picks the palette up on its next timeline
/// reload with no new plumbing — which is why the widget half of this ticket shipped rather than
/// being deferred.
nonisolated enum CadenceAccentPaletteStore {
    static let defaultsKey = "cadence.appearance.accentPaletteID"

    static func loadSelected(userDefaults: UserDefaults? = nil) -> CadenceAccentPalette {
        CadenceAccentPalette.palette(id: sharedDefaults(userDefaults).string(forKey: defaultsKey))
    }

    static func storeSelected(_ palette: CadenceAccentPalette, userDefaults: UserDefaults? = nil) {
        sharedDefaults(userDefaults).set(palette.id, forKey: defaultsKey)
    }

    static func clearSelection(userDefaults: UserDefaults? = nil) {
        sharedDefaults(userDefaults).removeObject(forKey: defaultsKey)
    }

    static func sharedDefaults(_ defaults: UserDefaults? = nil) -> UserDefaults {
        if let defaults { return defaults }
        if let shared = UserDefaults(suiteName: CadenceStoreSupport.appGroupIdentifier) { return shared }
        return .standard
    }
}

/// The active accent set, and the only thing in the app that can change it.
///
/// `@Observable` is doing real work here rather than decorating a singleton. `Theme.blue` is a
/// static read from 256 files that observe nothing, so a palette change would otherwise repaint
/// nothing until each view happened to be invalidated for some other reason. Because every accent
/// accessor funnels through `resolution`, and SwiftUI evaluates a `body` inside an observation
/// tracking scope, a view that reads `Theme.blue` *anywhere* in its body registers a dependency on
/// this property and is invalidated when it changes. That is the whole live-repaint mechanism; the
/// alternative was `.id(paletteID)` on the root, which repaints by throwing away every piece of
/// `@State` in the app, including the Settings screen the user is standing on.
///
/// The AppKit markdown editor is the one surface this does not reach — it draws through
/// `MarkdownStylist`, not through a SwiftUI body — so it repaints on its next restyle rather than
/// instantly. Its three accent colours are computed rather than stored precisely so that restyle
/// is correct; see `MarkdownEditorSupport`.
@Observable
nonisolated final class CadenceAccentPaletteSelection: @unchecked Sendable {
    static let shared = CadenceAccentPaletteSelection()

    private(set) var resolution: CadenceAccentResolution

    var palette: CadenceAccentPalette { resolution.palette }

    init(palette: CadenceAccentPalette? = nil, userDefaults: UserDefaults? = nil) {
        let resolved = palette ?? CadenceAccentPaletteStore.loadSelected(userDefaults: userDefaults)
        self.resolution = CadenceAccentResolution(resolved)
    }

    /// Idempotent: selecting the set already active writes nothing and reloads nothing, so a
    /// picker row can be tapped twice without pushing a widget timeline reload each time.
    func select(_ palette: CadenceAccentPalette, persist: Bool = true, userDefaults: UserDefaults? = nil) {
        guard palette != resolution.palette else { return }
        resolution = CadenceAccentResolution(palette)
        guard persist else { return }
        CadenceAccentPaletteStore.storeSelected(palette, userDefaults: userDefaults)
        CadenceWidgetRefreshCenter.reloadAllWidgets(force: true)
    }
}


/// Cadence's fixed dark neutral ramp, plus the six selectable accents.
///
/// **The neutrals are `static let` and the accents are computed, and the split is the design.**
/// Everything from `bg` through the text ramp, the marker pen, the on-colour foregrounds, the
/// scrims, the shadows and the radius scale is a fixed value that no selection can move, so the
/// chrome on every screen cannot regress. The six accents and their `*Light` and `*Hex` relatives
/// resolve from `CadenceAccentPaletteSelection.shared` instead — see `CadenceAccentPalette`.
///
/// This is not the return of `ThemeManager`. That system offered seven whole light-and-dark
/// themes, was removed, and was not asked for back; `preferredColorScheme` is still a hardcoded
/// `.dark` and there is still exactly one neutral ramp.
///
/// A stored `static let` that reads an accent is a bug, in this file or any other: it freezes on
/// first access and never moves again. `CadenceColorPalette`'s swatch arrays,
/// `CadenceTodayPresentationSupport.completedSectionAccent` and `MarkdownStylist`'s three accent
/// `NSColor`s are all computed for that reason.
nonisolated struct Theme {
    // Near-black neutral. The previous stops sat around hue 225 at ~19% saturation, so the
    // blue cast compounded on every elevated surface and the chrome ended up carrying more
    // color than the content. These sit at ~4% saturation so the accents do that job instead.
    static let bg = Color(hex: "#09090b")
    static let surface = Color(hex: "#131316")
    static let surfaceElevated = Color(hex: "#1a1a1e")
    static let borderSubtle = Color(hex: "#26262b")

    static let text = Color(hex: "#ededef")
    static let muted = Color(hex: "#a1a1aa")
    /// Supporting text one stop below `muted`: the label half of a label/value pair, and captions
    /// that annotate the thing above them rather than say anything on their own. It exists because
    /// `muted` and `dim` are two stops too far apart to express "quieter than secondary, but still
    /// ordinary reading text" — `dim` is reserved for genuinely de-emphasized or disabled content
    /// and lands 9pt captions near 0.42 effective white on `bg`, which is too faint to read on a
    /// device. Sits between the two, nearer `muted`.
    static let subdued = Color(hex: "#95959e")
    static let dim = Color(hex: "#71717a")

    // MARK: - Extended neutral ramp
    // Stops that sit *between* (or just below) the four surface values above. They exist for
    // jobs the four-stop ramp cannot express — a recessed well below `bg`, a hover lift between
    // `surface` and `surfaceElevated`, and borders that must stay visible when drawn at partial
    // alpha. Introduced so the AppKit markdown editor could stop carrying its own private hex
    // literals; they follow the same ~4% saturation near-black ramp as the stops above.

    /// Recessed well one step *below* `bg` (unchecked checkbox interiors, inset wells).
    static let surfaceRecessed = Color(hex: "#0d0d0f")
    /// Hover lift for a surface whose resting fill is `surface`.
    static let surfaceHover = Color(hex: "#17171a")
    /// Hover/selection highlight behind content nested inside an already-elevated surface.
    static let surfaceHighlight = Color(hex: "#1f1f23")
    /// One step above `borderSubtle`, for hairlines that are drawn at partial alpha and would
    /// otherwise disappear.
    static let border = Color(hex: "#2e2e34")
    /// Emphasized border: hovered cards, table delimiters, code fences.
    static let borderStrong = Color(hex: "#3f3f46")
    /// Standalone horizontal rules, which carry no other affordance to lean on.
    static let rule = Color(hex: "#52525b")

    // MARK: - Marker highlight
    // The `==highlight==` marker pen in the markdown editors. Semantic, not palette — it has to
    // read as a physical highlighter, so it deliberately keeps its warm hue through the neutral
    // repaint rather than resolving to `amber`.

    static let markerHighlightFill = Color(hex: "#f6c343")
    static let markerHighlightBorder = Color(hex: "#ffd66b")
    static let markerHighlightText = Color(hex: "#fff4c2")

    // MARK: - Accents
    //
    // Every accent is declared hex-string-first, and the `Color` is derived from it.
    //
    // The string is not a convenience: an app-defined *default* offered to the user — a sidebar
    // glyph tint, a model `colorHex` seed — is a palette decision that happens to be spelled as a
    // string, and the only way it can come from the palette rather than from a second hand-typed
    // literal is for the palette to publish the string. `blueHex` and `tealHex` were the only two
    // that did, so `CadenceFeatureDestination.defaultColorHex` spelled its own amber, blue and
    // purple and all three drifted (T-166): the sidebar drew Today in `#FFB84D` while the command
    // palette drew the same destination in this file's `#ffa94d`. Derive the `Color` from the
    // string, never the other way round, and never re-type a value that is already here.
    //
    // These are `static var` rather than `static let` because the six are selectable (T-15). The
    // values themselves live in `CadenceAccentPalette`; nothing below re-spells a hex. A read is
    // one property load off the already-resolved `CadenceAccentResolution` — see its declaration
    // for why that matters at 431 call sites.

    /// The active accent set, resolved. Read `Theme.blue` and friends rather than this; it is
    /// exposed so a picker can show what is currently selected without a second source of truth.
    static var accents: CadenceAccentResolution { CadenceAccentPaletteSelection.shared.resolution }

    /// Which of `CadenceAccentPalette.all` is active.
    static var accentPalette: CadenceAccentPalette { accents.palette }

    /// Single source of truth for the accent hex — also used where a *string* color is
    /// required (model `colorHex` fallbacks) so the literal is not duplicated.
    static var blueHex: String { accents.palette.blueHex }

    static var blue: Color { accents.blue }
    static var blueLight: Color { accents.blueLight }

    static var redHex: String { accents.palette.redHex }
    static var red: Color { accents.red }

    static var greenHex: String { accents.palette.greenHex }
    static var green: Color { accents.green }
    static var greenLight: Color { accents.greenLight }

    static var amberHex: String { accents.palette.amberHex }
    static var amber: Color { accents.amber }
    static var amberLight: Color { accents.amberLight }

    static var purpleHex: String { accents.palette.purpleHex }
    static var purple: Color { accents.purple }

    /// Added for Focus, and the only accent added since the palette was fixed.
    ///
    /// The sidebar tints are a *family* system, not one hue per destination: amber is today and
    /// habits, blue is tasks and settings, purple is notes and search, green is lists and goals.
    /// Sharing a hue is how two related destinations read as related. What broke was Focus and
    /// Calendar landing on the same red when Calendar was retinted — those two are not a family,
    /// so the shared hue said something untrue. Every existing accent was already spoken for, so
    /// Focus needed a sixth rather than a seat in someone else's family. Teal is far enough from
    /// all five to be told apart at a 15pt glyph, and carries no meaning of its own — a timer is
    /// not success, warning or danger. Every selectable palette keeps that assignment: a set that
    /// re-sorted which hue means what would not be a palette.
    static var tealHex: String { accents.palette.tealHex }
    static var teal: Color { accents.teal }

    /// The palette is fixed dark; there is no light variant or user selection anymore.
    static let preferredColorScheme: ColorScheme = .dark

    static func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high:   return red
        case .medium: return amber
        case .low:    return blue
        case .none:   return dim
        }
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .done:       return green
        case .cancelled:  return dim
        case .inProgress: return blue
        case .todo:       return muted
        }
    }

    /// Fill for a completed completion-circle (task rows, kanban cards, timeline blocks, task
    /// inspector). When checked, every priority converges to this same green + a white
    /// checkmark — priority stops being shown once a task is done.
    static var doneFill: Color { green }

    // MARK: - Foreground on colored fills
    // For content drawn ON TOP of a saturated fill (calendar event blocks, a selected day
    // cell, an accent-filled button) the foreground is deliberately near-white rather than
    // `text` — it has to hold up against an arbitrary user-chosen hue, not against `bg`.
    // These replace scattered `.white` / `.white.opacity(...)` literals so the tiers are
    // named and consistent instead of each call site inventing its own alpha.

    /// Primary content on a colored fill: titles, button labels.
    static let onColor = Color.white
    /// Secondary content on a colored fill: time ranges, subtitles, calendar names.
    static let onColorSecondary = Color.white.opacity(0.75)
    /// Tertiary content on a colored fill: incidental glyphs.
    static let onColorTertiary = Color.white.opacity(0.6)

    /// Hairline outline drawn ON a colored fill, where `borderSubtle` would read as a dark
    /// gap instead of an edge (task-count bubbles on a selected day cell, hatching over a
    /// completed timeline block).
    static let onColorBorder = Color.white.opacity(0.14)
    /// Emphasized variant of `onColorBorder` for selected/active colored fills.
    static let onColorBorderStrong = Color.white.opacity(0.32)

    /// Resting grab handle drawn on a colored timeline block (resize affordances on task,
    /// event, and bundle blocks). Deliberately faint until the block is hovered/selected.
    static let onColorHandle = Color.white.opacity(0.16)
    /// `onColorHandle` while the block is hovered, selected, or actively being resized.
    static let onColorHandleActive = Color.white.opacity(0.42)

    /// Brand-mandated fill for the "Sign in with Apple" button. Not a palette color — Apple's
    /// Sign in with Apple guidelines only permit black / white / outline treatments, so this
    /// deliberately sits outside the neutral ramp and must not be re-tinted with the palette.
    static let appleSignInFill = Color.black

    // MARK: - Overlays
    // Washes and scrims expressed as white/black alpha. Previously hand-tuned per call site
    // against the old blue-tinted background; centralized so a palette change moves them all.

    /// Full-screen dimming behind a modal, sheet, or command palette.
    static let scrim = Color.black.opacity(0.34)
    /// Selected-state wash on top of a colored surface (e.g. today's cell in the month grid).
    static let selectionWash = Color.white.opacity(0.18)
    /// Barely-there lift used to separate a nested region from the surface beneath it.
    static let subtleWash = Color.white.opacity(0.035)

    // MARK: - Shadow presets
    // Named to replace one-off `Color.black.opacity(...)` shadow values scattered across
    // surfaces. Radius/offset stay call-site-specific since elevation depth genuinely varies;
    // these only centralize the color/opacity for jobs that are doing the same kind of lift.

    /// Hairline shadow for small chips/pills (calendar day-cell chips, all-day banner chips).
    static let chipShadow = Color.black.opacity(0.06)
    /// Shadow for an edge-attached floating panel with no dimming scrim behind it
    /// (e.g. Today's right-hand timeline sidebar).
    static let sidePanelShadow = Color.black.opacity(0.18)
    /// Shadow for centered modal cards, popovers, toasts, and overlay shells presented
    /// above a dimming scrim.
    static let overlayCardShadow = Color.black.opacity(0.3)
    /// Soft lift for in-flow content cards that replaces a hard border with gentle elevation.
    /// Paired with `radiusCard`. NOTE: task rows/kanban cards moved back to a flat,
    /// divider-separated style per the current design spec — this token is now only for
    /// surfaces that are still deliberately card-shaped (e.g. stat tiles, popovers).
    static let cardElevationShadow = Color.black.opacity(0.22)

    // MARK: - Corner radius scale
    // A shared radius scale so card-like surfaces read as one family instead of each
    // picking its own value (previously scattered 8/10/12/14/16 with no clear pattern).

    /// Small in-card controls: icon badges, compact buttons, inline pickers.
    static let radiusControl: CGFloat = 10
    /// Standard content cards: stat tiles, list rows that are still card-shaped, kanban cards.
    static let radiusCard: CGFloat = 18
    /// Large surfaces: page headers, sheets, popovers, modal shells.
    static let radiusPanel: CGFloat = 22

}

// MARK: - Derived variants
//
// The design spec defines only the base hues; the lightened accent variants (still referenced by
// existing call sites for hover/pressed/emphasis states) are derived by blending a fixed fraction
// toward white, rather than hand-picking arbitrary hex values with no spec to match against.
//
// File-scope rather than `private static` on `Theme`, because `CadenceAccentResolution` is what
// calls them now and a type-private member is not reachable from a sibling type in the same file.

fileprivate nonisolated func cadenceLightened(_ hex: String, by amount: Double = 0.3) -> Color {
    cadenceBlended(hex, toward: (1, 1, 1), amount: amount)
}

fileprivate nonisolated func cadenceBlended(_ hex: String, toward target: (r: Double, g: Double, b: Double), amount: Double) -> Color {
    let c = cadenceHexComponents(hex)
    return Color(
        .sRGB,
        red: c.r + (target.r - c.r) * amount,
        green: c.g + (target.g - c.g) * amount,
        blue: c.b + (target.b - c.b) * amount,
        opacity: 1
    )
}

fileprivate nonisolated func cadenceHexComponents(_ hex: String) -> (r: Double, g: Double, b: Double) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    return (
        Double((int >> 16) & 0xFF) / 255,
        Double((int >> 8) & 0xFF) / 255,
        Double(int & 0xFF) / 255
    )
}

#if canImport(AppKit)
/// A palette `Color` resolved into a concrete sRGB `NSColor` for AppKit drawing.
fileprivate nonisolated func cadenceSRGBColor(_ color: Color) -> NSColor {
    let resolved = NSColor(color)
    return resolved.usingColorSpace(.sRGB) ?? resolved
}
#endif

#if canImport(AppKit)
// MARK: - AppKit bridges
//
// The markdown editor is AppKit (NSTextView + a custom NSLayoutManager doing its own drawing),
// so it cannot read SwiftUI `Color`. It used to carry its own hand-tuned `NSColor(hex:)` literals,
// which silently drifted from the palette above whenever the palette changed. These bridges
// resolve the *same* `Color` constants declared in this file into concrete sRGB `NSColor`s, so a
// palette value is still defined in exactly one place and the two can never diverge.
nonisolated extension Theme {
    /// Resolves a palette `Color` into a concrete sRGB `NSColor` suitable for AppKit drawing
    /// (`setFill()`, `setStroke()`, `backgroundColor`, `withAlphaComponent(_:)`, PDF rendering).
    private static func nsColor(_ color: Color) -> NSColor {
        cadenceSRGBColor(color)
    }

    static let nsBg = nsColor(bg)
    static let nsSurface = nsColor(surface)
    static let nsSurfaceElevated = nsColor(surfaceElevated)
    static let nsBorderSubtle = nsColor(borderSubtle)

    static let nsSurfaceRecessed = nsColor(surfaceRecessed)
    static let nsSurfaceHover = nsColor(surfaceHover)
    static let nsSurfaceHighlight = nsColor(surfaceHighlight)
    static let nsBorder = nsColor(border)
    static let nsBorderStrong = nsColor(borderStrong)
    static let nsRule = nsColor(rule)

    static let nsMarkerHighlightFill = nsColor(markerHighlightFill)
    static let nsMarkerHighlightBorder = nsColor(markerHighlightBorder)
    static let nsMarkerHighlightText = nsColor(markerHighlightText)

    static let nsText = nsColor(text)
    static let nsMuted = nsColor(muted)
    static let nsDim = nsColor(dim)

    // The three accent mirrors are computed, and the sixteen neutral ones above are not: a stored
    // `static let` initialises once and would keep drawing the palette that happened to be active
    // the first time the markdown editor laid out a line. Resolved eagerly per palette in
    // `CadenceAccentResolution`, so a read here is still a stored-property load and not an
    // `NSColor(Color)` conversion.
    static var nsBlue: NSColor { accents.nsBlue }
    static var nsRed: NSColor { accents.nsRed }
    static var nsGreen: NSColor { accents.nsGreen }
}
#endif

nonisolated extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
