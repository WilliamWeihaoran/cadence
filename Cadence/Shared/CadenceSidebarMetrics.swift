import SwiftUI

/// Which sidebar column a figure is for.
///
/// Two tiers, not one, for the reason `CadencePageHeaderSurface` has three: the platforms differ
/// in *input*, not in taste. Everything a pointer and a finger can share is shared here; the two
/// figures that genuinely cannot are `rowHeight` and `listRowHeight`, and they are the only two
/// that differ.
///
/// There is no `.compact` tier because there is no compact sidebar — the iPhone has a tab bar.
nonisolated enum CadenceSidebarSurface: String, CaseIterable, Sendable {
    /// The macOS column, driven by a pointer.
    case desktop
    /// The iPad column at regular width, driven by a finger.
    case tablet
}

/// Every number the two sidebar columns draw a nav row and a list row with.
///
/// This exists because the two columns were each deciding for themselves and had drifted in five
/// dimensions that nobody chose: 15pt glyphs against 13, 13pt labels against 14, 10pt of
/// icon-to-label against 9, a list colour bar 14pt tall against 16, and a 10pt due-date caption
/// against 11. None of those was a platform judgement; they were two files.
///
/// **`sectionSpacing` left with T-3072**, for the reason the colour bar's figures left with
/// T-2084: its subject died with the drawing. It was the touch column's one gap between two
/// context sections, and a context section's spacing is `CadenceSidebarContextHeaderRhythm`'s now
/// on both platforms — a single stack spacing cannot express a gap composed of four pads applied
/// in four places, which is exactly why the touch column's headers read as belonging to nothing.
///
/// **The colour bar itself is gone (T-2084)** — the owner found a column of saturated edge markers
/// distracting and asked for the space back — so its three figures left this struct with it. A list
/// still carries a colour everywhere it is *chosen*: the list editor, the pickers, the sheets and
/// the inspector. The sidebar row simply stopped drawing one. The count badge had already
/// been through this once (`CadenceSidebarCountMetrics`, 11 against 12) and is deliberately *not*
/// restated here — change it there.
///
/// It sits outside `#if os(iOS)` so the macOS-built `CadenceTests` can pin it, the same reason
/// `CadencePageHeaderMetrics` and `CadenceCompactTab` do.
nonisolated struct CadenceSidebarRowMetrics: Equatable, Sendable {
    // MARK: Nav rows

    /// **The first of the two figures the two surfaces do not share, and the one that may not
    /// move.** 32pt is right under a pointer, which can land on a 32pt target as easily as a 44pt
    /// one; a finger cannot, and a nav row is the most-tapped control in the iPad shell.
    /// Flattening this to 32 would be a legible tidy-up and a real ergonomic regression, so it
    /// stays split and says so. The *list* rows are a separate question and T-3072 answered it
    /// separately — see `listRowHeight`; this figure still carries Today, Tasks, Calendar, Notes
    /// and every other nav destination at 44.
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

    // MARK: List rows

    /// **The second figure the two surfaces do not share, and the only one that is absent on one
    /// of them (T-3072).**
    ///
    /// `nil` on the desktop, because a macOS list row has no height to state: it is a 13pt label
    /// plus `SidebarMetrics.listRowVerticalPadding` on each edge, about 30pt, and nothing fixes
    /// it. The touch column does fix one, because a fixed frame is how it draws a tap target — so
    /// this is a figure that has to be *chosen* rather than inherited, which is why it is written
    /// down here with its argument instead of appearing as a frame in a view.
    ///
    /// **The owner asked for the Mac's ~30 and this is 36, deliberately.** *"make the spacing
    /// between lists tighter vertically (make it the same as mac os)"* — but 30 is below the 32
    /// that `rowHeight`'s own note already says a finger cannot land on, so copying the Mac
    /// exactly would trade a density complaint for a mis-tap. What a list row has that a nav
    /// glyph does not is the **other axis**: Apple's 44×44 minimum describes a discrete control a
    /// finger must land *on*, small in both directions, and this row is 244pt wide in a 264pt
    /// column with only its height in question. That asymmetry is the whole of the licence to go
    /// under 44, and it does not extend to 30: 36 clears the table's own written floor by four
    /// points rather than sitting a run of pixels under it.
    ///
    /// So eight of the fourteen points asked for, which over a ten-list column gives 80pt back to
    /// the one region in this sidebar that scrolls. If the owner wants the other six, this is the
    /// single constant to move — the argument against moving it is recorded here rather than lost,
    /// which is the point of writing it down.
    ///
    /// **Not a licence for the nav rows.** `rowHeight` stays 44 on touch and
    /// `theTouchNavRowsDidNotMove` is red the moment it does not.
    let listRowHeight: CGFloat?
    let listLabelFontSize: CGFloat
    let listDueDateIconSize: CGFloat
    let listDueDateFontSize: CGFloat
    let listDueDateSpacing: CGFloat
    let listTrailingItemSpacing: CGFloat
}

nonisolated enum CadenceSidebarMetrics {
    /// A pointer can land on a 32pt row.
    static let pointerRowHeight: CGFloat = 32
    /// A finger needs 44 for a nav row. See `CadenceSidebarRowMetrics.rowHeight`.
    static let touchRowHeight: CGFloat = 44
    /// What a touch **list** row is instead, the sidebar's second and last surface split. Why 36
    /// and not the Mac's ~30, and why a full-width row may go under 44 at all, is argued in full
    /// on `CadenceSidebarRowMetrics.listRowHeight` — that is the doc to read before changing this.
    static let touchListRowHeight: CGFloat = 36

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
            listRowHeight: surface == .desktop ? nil : touchListRowHeight,
            listLabelFontSize: 13,
            listDueDateIconSize: 9,
            listDueDateFontSize: 10,
            listDueDateSpacing: 4,
            listTrailingItemSpacing: 8
        )
    }
}

// MARK: - Context header rhythm

/// How far a context header sits from the group above it and from the lists below it, on **both**
/// columns.
///
/// **A context header belongs to the lists *under* it, so it must sit far from the group above and
/// close to its own (T-1041/T-1067).** That asymmetry was macOS's alone and nobody chose that it
/// should be: the iPad column and the iPhone Tasks index drew the same headers with 8pt above and
/// 4pt below, against the Mac's 26 and 9, so the one thing the headers are *for* — saying which
/// lists go together — was the thing the touch surfaces did least. The owner asked for the Mac's
/// treatment, which is this one, so the terms live here and both columns read them.
///
/// Each number below is **one term of a sum applied in a different place**, which is why they are
/// added up here rather than at a call site: what a reader sees is `gapAboveHeader` and
/// `gapBelowHeader`, and no single view can see either. Retune a term and the views, the model and
/// `CadenceSidebarLayoutTests` all follow.
///
/// The two columns compose the same sums out of slightly different parts, and
/// `touchHeaderBottomPadding` is the whole of the difference: macOS opens a populated context's row
/// stack with a transparent `leadingDropZoneHeight` drag target, which a reader counts as
/// whitespace; the touch column has no list drag-reorder and so draws no such control, and folds
/// that height into the header's own bottom pad instead. The *gap* is identical either way, which
/// is what `theTouchSidebarHeaderRhythmIsTheDesktopOne` holds.
///
/// It sits beside `CadenceSidebarMetrics`, outside any platform `#if`, for the same two reasons
/// that type does: `Cadence/iOS/` is behind `#if os(iOS)` while `CadenceTests` builds on macOS, and
/// a figure both columns draw should be decided once.
nonisolated enum CadenceSidebarContextHeaderRhythm {
    /// Above the header, inside the section.
    static let headerTopPadding: CGFloat = 14
    /// The section stack's own spacing: header to whatever the section draws next.
    static let headerBottomSpacing: CGFloat = 3
    /// Below the section's last row, inside the section.
    static let sectionBottomPadding: CGFloat = 8
    /// Each lists region pads every section by this on **both** edges, and stacks them at zero
    /// spacing, so two neighbours contribute it once each to the gap between them.
    static let sectionOuterVerticalPadding: CGFloat = 2
    /// The "drop above the first row" target that opens every populated context's row stack on
    /// macOS. A control, but a transparent one, so a reader counts its height as whitespace.
    static let leadingDropZoneHeight: CGFloat = 4
    /// Between two list rows of one context. Not surface-split: `rowSpacing` is one of the figures
    /// the two columns already agree on.
    static let rowSpacing: CGFloat = CadenceSidebarMetrics.metrics(for: .desktop).rowSpacing

    /// From the previous context's last list row to this context's header.
    static let gapAboveHeader: CGFloat =
        sectionBottomPadding + sectionOuterVerticalPadding * 2 + headerTopPadding

    /// From the header to the first list row it labels.
    static let gapBelowHeader: CGFloat =
        headerBottomSpacing + leadingDropZoneHeight + rowSpacing

    /// From the header to the "Add first list" button of a context that has none. No drop zone is
    /// drawn there, so this is the bare stack spacing and is deliberately *not* the number the
    /// relationship is pinned on: an empty context has no lists for its header to belong to.
    static let gapBelowHeaderInEmptyContext: CGFloat = headerBottomSpacing

    /// The touch column's spelling of everything between the header's baseline box and its first
    /// row **except** the row stack's own spacing — `headerBottomSpacing` plus the drop zone that
    /// column does not draw. Stated as the remainder of `gapBelowHeader` rather than as `3 + 4` so
    /// the two columns cannot come to show different gaps while both look correct in isolation.
    static let touchHeaderBottomPadding: CGFloat = gapBelowHeader - rowSpacing
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
