import SwiftUI

/// What a header row is the top of — and, after this sweep, the only thing about an iOS page
/// header that legitimately varies.
///
/// Six near-copies of "eyebrow, title, maybe a count, maybe a back chevron" had drifted into six
/// title sizes (17 / 18 / 21 / 23 / 26 / 30pt), two eyebrow sizes, two count badges and three
/// spellings of the identity tile. `iOSPageHeader` states that vocabulary once; this states the
/// one difference that survives it, because a column inside a split and a whole screen are not the
/// same amount of screen and should not speak at the same volume.
///
/// Deliberately **outside** `#if os(iOS)`, unlike every other file in this folder: a type ramp is a
/// decision, and the macOS-built test target has to be able to read it. Nothing here draws.
nonisolated enum iOSPageHeaderRole: String, CaseIterable, Sendable {
    /// The top of a whole screen — a pushed compact screen, or a page filling its pane.
    case page
    /// The top of one column inside a split or a multi-column page, where the page has already
    /// said what it is somewhere else on screen.
    case pane
}

/// Every measurement `iOSPageHeader` draws itself with, in one value.
///
/// The split is deliberate: **volume** varies by role (title and tile), **vocabulary** does not
/// (eyebrow, count badge, padding). `iOSPanelHeader` set its eyebrow a point smaller than everyone
/// else's at compact width, which is the kind of difference nobody chooses and nobody notices
/// until the two headers end up on the same screen.
nonisolated struct iOSPageHeaderMetrics: Equatable, Sendable {
    /// The page title. The only figure with a real spread between the roles.
    let titleSize: CGFloat
    /// The uppercase kerned line above the title — `SectionEyebrowLabel`'s size, since that is the
    /// component drawing it.
    let eyebrowSize: CGFloat
    /// The trailing count capsule's digits.
    let countSize: CGFloat
    let countPaddingH: CGFloat
    let countPaddingV: CGFloat
    /// The identity tile the row leads with, when it has one.
    let tileSize: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    /// The glyph inside the identity tile, as one ratio of the tile. Stated here rather than passed
    /// so a tile can never be resized without its glyph — which is exactly how `iOSIconTile` at
    /// 32/15 and `iOSListIconBadge` at 32/14.08 became two tiles that were meant to be one.
    var iconSize: CGFloat { tileSize * 0.44 }

    static func metrics(role: iOSPageHeaderRole, isRegularWidth: Bool) -> iOSPageHeaderMetrics {
        iOSPageHeaderMetrics(
            titleSize: titleSize(role: role, isRegularWidth: isRegularWidth),
            eyebrowSize: 10,
            countSize: isRegularWidth ? 13 : 12,
            countPaddingH: isRegularWidth ? 10 : 8,
            countPaddingV: isRegularWidth ? 6 : 4,
            tileSize: tileSize(role: role, isRegularWidth: isRegularWidth),
            rowSpacing: isRegularWidth ? 12 : 10,
            horizontalPadding: isRegularWidth ? 20 : 16,
            topPadding: isRegularWidth ? 16 : 13,
            bottomPadding: isRegularWidth ? 11 : 7
        )
    }

    private static func titleSize(role: iOSPageHeaderRole, isRegularWidth: Bool) -> CGFloat {
        switch role {
        case .page: return isRegularWidth ? 30 : 26
        case .pane: return isRegularWidth ? 21 : 17
        }
    }

    private static func tileSize(role: iOSPageHeaderRole, isRegularWidth: Bool) -> CGFloat {
        switch role {
        case .page: return isRegularWidth ? 36 : 32
        case .pane: return isRegularWidth ? 32 : 28
        }
    }
}
