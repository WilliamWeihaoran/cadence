import Foundation

/// The swatch palette offered wherever a user picks a `colorHex` for a **list, goal or habit**.
///
/// This existed three times: `ColorGrid.colors` (macOS, `#if os(macOS)`), `iOSListPalette.colors`
/// (a deliberate iOS mirror of it, added precisely because `ColorGrid` could not be reached), and
/// `iOSTrackingColorGrid.colors` — which had already drifted to a *different eight colours*, so a
/// goal or habit could be tinted `#38d5c7` or `#94a3b8` while no list could, and lists offered five
/// hues that goals did not. One palette, no `#if`, so the next surface that needs swatches has
/// somewhere to get them.
///
/// `TagSupport.colorOptions` is deliberately **not** folded in here. Tags are a different palette
/// with a different job, and it is already shared.
enum CadenceColorPalette {
    /// `Area.colorHex`'s model default. Named rather than respelled at each seeding site.
    static let areaDefault = Theme.blueHex

    /// `Project.colorHex`'s model default.
    static let projectDefault = "#4ecb71"

    /// One lap of the hue circle, warm through cool, ending on a neutral. Twelve reads as a 6×2 or
    /// 4×3 grid on macOS and wraps cleanly into a strip on iOS.
    static let colors = [
        areaDefault, "#6366f1", "#a78bfa", "#e879f9", "#f472b6", "#ff6b6b",
        "#ffa94d", "#fbbf24", projectDefault, "#14b8a6", "#06b6d4", "#6b7a99",
    ]

    /// The palette, plus `selected` when the palette no longer contains it.
    ///
    /// Trimming or changing the palette must never silently re-colour something already saved. A
    /// stored hex that is not offered is appended, so its owner still shows a selected swatch and
    /// keeps its colour; it drops out of the grid the moment the user picks something else. This
    /// is what makes consolidating the three palettes safe — a goal sitting on one of the retired
    /// tracking-only hues keeps it.
    static func offeredColors(for selected: String) -> [String] {
        let stored = selected.trimmingCharacters(in: .whitespaces)
        guard !stored.isEmpty, !colors.contains(where: { matches($0, stored) }) else {
            return colors
        }
        return colors + [stored]
    }

    /// Hex comparison is case-insensitive: stored values predate any casing convention, so
    /// `#4A9EFF` and `#4a9eff` are the same swatch and must not both render as selected.
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }
}
