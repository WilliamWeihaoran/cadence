import SwiftUI

/// Which sidebar column a figure is for.
///
/// Two tiers, not one, for the reason `CadencePageHeaderSurface` has three: the platforms differ
/// in *input*, not in taste. Everything a pointer and a finger can share is shared here; the one
/// figure that genuinely cannot is `rowHeight`, and it is the only one that differs.
///
/// There is no `.compact` tier because there is no compact sidebar — the iPhone has a tab bar.
nonisolated enum CadenceSidebarSurface: String, CaseIterable, Sendable {
    /// The macOS column, driven by a pointer.
    case desktop
    /// The iPad column at regular width, driven by a finger. `iOSSidebarStyle.rail` narrows the
    /// column but does not change any figure here.
    case tablet
}

/// Every number the two sidebar columns draw a nav row and a list row with.
///
/// This exists because the two columns were each deciding for themselves and had drifted in five
/// dimensions that nobody chose: 15pt glyphs against 13, 13pt labels against 14, 10pt of
/// icon-to-label against 9, a 14pt list colour bar against 16, and a 10pt due-date caption against
/// 11. None of those was a platform judgement; they were two files. The count badge had already
/// been through this once (`CadenceSidebarCountMetrics`, 11 against 12) and is deliberately *not*
/// restated here — change it there.
///
/// It sits outside `#if os(iOS)` so the macOS-built `CadenceTests` can pin it, the same reason
/// `CadencePageHeaderMetrics` and `CadenceCompactTab` do.
nonisolated struct CadenceSidebarRowMetrics: Equatable, Sendable {
    // MARK: Nav rows

    /// **The one figure the two surfaces do not share.** 32pt is right under a pointer, which can
    /// land on a 32pt target as easily as a 44pt one; a finger cannot, and a nav row is the
    /// most-tapped control in the iPad shell. Flattening this to 32 would be a legible tidy-up and
    /// a real ergonomic regression, so it stays split and says so.
    let rowHeight: CGFloat
    let cornerRadius: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat
    let iconSlotWidth: CGFloat
    let iconSize: CGFloat
    let iconLabelSpacing: CGFloat
    let labelFontSize: CGFloat
    /// Minimum gap held between a truncating label and its count. The count wins layout priority,
    /// so this is the point at which the *label* starts truncating.
    let badgeLeadingGap: CGFloat
    /// Icon opacity for the quieter bottom nav group. Kept well clear of a disabled-looking wash —
    /// these are real destinations, just less-travelled ones.
    let secondaryIconOpacity: Double

    // MARK: Group separation

    let groupSpacing: CGFloat
    /// Gap between one context's list section and the next.
    let sectionSpacing: CGFloat

    // MARK: List rows

    /// Narrow enough to read as an edge marker rather than a swatch, and drawn *inside* the row's
    /// leading padding — outside the text column — so every list name starts on the same x
    /// whatever colour it carries.
    let listColorBarWidth: CGFloat
    let listColorBarHeight: CGFloat
    let listColorBarLeadingInset: CGFloat
    let listLabelFontSize: CGFloat
    let listDueDateIconSize: CGFloat
    let listDueDateFontSize: CGFloat
    let listDueDateSpacing: CGFloat
    let listTrailingItemSpacing: CGFloat
}

nonisolated enum CadenceSidebarMetrics {
    /// A pointer can land on a 32pt row.
    static let pointerRowHeight: CGFloat = 32
    /// A finger needs 44. See `CadenceSidebarRowMetrics.rowHeight`.
    static let touchRowHeight: CGFloat = 44

    static func metrics(for surface: CadenceSidebarSurface) -> CadenceSidebarRowMetrics {
        CadenceSidebarRowMetrics(
            rowHeight: surface == .desktop ? pointerRowHeight : touchRowHeight,
            cornerRadius: Theme.radiusControl,
            rowSpacing: 2,
            horizontalPadding: 10,
            iconSlotWidth: 20,
            iconSize: 15,
            iconLabelSpacing: 10,
            labelFontSize: 13,
            badgeLeadingGap: 8,
            secondaryIconOpacity: 0.8,
            groupSpacing: 8,
            sectionSpacing: 8,
            listColorBarWidth: 2,
            listColorBarHeight: 14,
            listColorBarLeadingInset: 3,
            listLabelFontSize: 13,
            listDueDateIconSize: 9,
            listDueDateFontSize: 10,
            listDueDateSpacing: 4,
            listTrailingItemSpacing: 8
        )
    }
}

// MARK: - Tint

/// The colour a sidebar nav glyph is drawn in.
///
/// **The glyph tint is a user choice, which is why it survives on both platforms.** The iPad
/// column used to draw every glyph in `Theme.dim`, on the argument that a column of six hues
/// encodes nothing a reader can act on and that macOS only keeps its hues because Settings →
/// Sidebar offers a per-destination colour picker there. That reasoning was sound and it is
/// overruled: the user asked for one sidebar, and the picker writes a plain preference string that
/// both platforms can read, so the tint is now the same on both whether or not iPad ever grows the
/// picker itself.
///
/// The override string is `"<destination>:<hex>,…"`, keyed by `CadenceFeatureDestination` raw
/// values — which is what `SidebarStaticDestination` writes, the two enums sharing raw values by
/// construction. Parsing it here rather than behind the macOS-only enum is what lets the iPad
/// column read the same preference instead of an approximation of it.
nonisolated enum CadenceSidebarTint {
    static func overrides(from raw: String) -> [CadenceFeatureDestination: String] {
        raw.split(separator: ",").reduce(into: [:]) { partial, pair in
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let destination = CadenceFeatureDestination(rawValue: parts[0]) else { return }
            partial[destination] = parts[1]
        }
    }

    /// The hex a destination's glyph is drawn in: the user's override if there is one, otherwise
    /// the destination's own default.
    static func hex(for destination: CadenceFeatureDestination, overridesRaw: String) -> String {
        overrides(from: overridesRaw)[destination] ?? destination.defaultColorHex
    }
}
