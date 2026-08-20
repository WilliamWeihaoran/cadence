import SwiftUI

/// What a header row is the top of.
///
/// Six near-copies of "eyebrow, title, maybe a count, maybe a back chevron" on iOS had drifted into
/// six title sizes (17 / 18 / 21 / 23 / 26 / 30pt), two eyebrow sizes, two count badges and three
/// spellings of the identity tile; macOS had four of its own. One header view per platform states
/// that vocabulary once; this states the one difference that survives it, because a column inside a
/// split and a whole screen are not the same amount of screen and should not speak at the same
/// volume.
nonisolated enum CadencePageHeaderRole: String, CaseIterable, Sendable {
    /// The top of a whole screen — a pushed compact screen, a page filling its pane, a macOS page.
    case page
    /// The top of one column inside a split or a multi-column page, where the page has already
    /// said what it is somewhere else on screen. macOS's Today columns and iPad Today's task
    /// column are the same idea and now the same figure.
    case pane
}

/// How much screen the header has, as a device class rather than a width in points.
///
/// `.compact` and `.regular` are iOS's two size classes. `.desktop` is macOS, and it is a third
/// tier rather than an alias for `.regular` on purpose: a Mac window is wider than an iPad but its
/// type is set smaller, not larger — Apple's own large title is 26pt on macOS against 34 on iOS,
/// and Cadence's desktop body text is 13pt against the phone's 15–17 with 30–34pt controls against
/// a 44pt touch floor. Folding macOS into `.regular` would have given every desktop page a 30pt
/// title over 13pt rows.
nonisolated enum CadencePageHeaderSurface: String, CaseIterable, Sendable {
    case compact
    case regular
    case desktop
}

/// Every measurement a Cadence page header draws itself with, in one value.
///
/// The split is deliberate: **volume** varies by role (title and tile), **vocabulary** does not
/// (eyebrow, count badge, padding). `iOSPanelHeader` set its eyebrow a point smaller than everyone
/// else's at compact width, which is the kind of difference nobody chooses and nobody notices
/// until the two headers end up on the same screen.
///
/// This was `iOSPageHeaderMetrics`, and it lived in `Cadence/iOS/` deliberately **outside**
/// `#if os(iOS)` so the macOS-built test target could read it. Once macOS started drawing from it
/// as well, the `iOS` prefix was hiding a fork rather than describing one — a type named for one
/// platform that the other platform depends on is the exact shape this repo has been unpicking.
/// It is `Cadence*` in `Shared/` now. Nothing here draws.
nonisolated struct CadencePageHeaderMetrics: Equatable, Sendable {
    /// The page title. The only figure with a real spread between the roles.
    let titleSize: CGFloat
    /// The uppercase kerned line above the title — `SectionEyebrowLabel`'s size, since that is the
    /// component drawing it on both platforms.
    let eyebrowSize: CGFloat
    /// The count capsule's digits.
    let countSize: CGFloat
    let countPaddingH: CGFloat
    let countPaddingV: CGFloat
    let rowSpacing: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    /// **No page header draws an identity tile any more.** `DesktopPageHeader` and `iOSPageHeader`
    /// each led with a rounded glyph square naming the page you were already looking at; the user
    /// asked for them dropped everywhere, so the `systemImage` parameter that fed them is deleted
    /// rather than left inert — a parameter kept but not rendered is how `subtitle` survived long
    /// enough to need deleting three times. `tileSize` and the `iconSize` derived from it went with
    /// it.
    ///
    /// These two survive because tiles that are *not* page identity survive: `CommitmentIconTile`
    /// still reads both for the tiles inside rows, cards and pickers. They are stated here rather
    /// than on that view because `iOSIconTile` is the other half of the same vocabulary.
    ///
    /// One glyph-to-tile ratio for the whole app, so a tile can never be resized without its glyph.
    static let tileGlyphRatio: CGFloat = 0.44

    /// The fill behind a tile, as an opacity of its tint. One value: the three macOS tiles were at
    /// 0.12, 0.14 and 0.18, which is drift, not a ramp.
    static let tileFillOpacity: Double = 0.14

    /// The hairline around a tile, as an opacity of its tint. `iOSIconTile` stroked this and
    /// `CommitmentIconTile` did not, so the *same* tile in the *same* card had an edge on an iPad
    /// and none on a Mac — visible directly through `HabitIconTile`, which is one shared view whose
    /// only job is to pick the platform tile, at 32/56pt on macOS against 34/52pt on iOS. A 0.14
    /// fill needs the edge to read as a plate rather than a wash, and the sizes the two tiles are
    /// used at overlap almost exactly, so there was no size at which one answer was right and the
    /// other wrong. Both read it now; `bordered: false` is the opt-out for a tile that sits *inside*
    /// another plate rather than standing on the page.
    static let tileBorderOpacity: Double = 0.20

    /// A tile's corner radius and curve, the last two figures the pair disagreed on (T-178).
    ///
    /// `CommitmentIconTile` computed `min(12, size * 0.28)` and drew it `.circular`;
    /// `iOSIconTile` read `Theme.radiusControl` and drew it `.continuous`. So the *same* habit
    /// tile — `HabitIconTile` picks the platform tile and nothing else — had a 8.96pt circular
    /// corner in a 32pt macOS row against a 10pt continuous one in a 34pt iPad row, and 12pt
    /// against 10pt at the two habit heroes.
    ///
    /// **The token won over the formula**, decided off renders of all four combinations at
    /// 32/34/52/56pt rather than off the argument. Two findings from those renders:
    ///
    /// - The formula's size-relativity was mostly notional. `min(12, …)` saturates at 42.86pt, so
    ///   above that it *is* a constant, and the only sizes `CommitmentIconTile` ever evaluated it
    ///   at were 32 (8.96) and 56 (12) — its one non-habit call site passed `cornerRadius: 9`, a
    ///   third value, rather than trusting it. Two live outputs, both within 2pt of the token, in
    ///   exchange for a number that sits on no scale.
    /// - The worry that a 56pt hero would read square at radius 10 was real but belonged to the
    ///   *curve*, not the radius: 10pt `.circular` was clearly the most cornered of the four at
    ///   56pt, and 10pt `.continuous` was the second-roundest, behind 12pt `.continuous` by a
    ///   margin that needed the two side by side to see. `.continuous` is what makes the token
    ///   safe at hero size, which is why it is stated here beside the radius instead of being left
    ///   to each tile.
    static let tileCornerRadius: CGFloat = Theme.radiusControl
    static let tileCornerStyle: RoundedCornerStyle = .continuous

    /// The fill behind the count capsule, as an opacity of the tint it counts in. iOS drew 0.11
    /// and macOS 0.12 for the same capsule; neither was chosen.
    static let countFillOpacity: Double = 0.12

    /// The count capsule is where `.desktop` deliberately answers with `.compact`'s figures rather
    /// than a third set. That is not laziness about the third tier: a 12pt count in an 8/4 capsule
    /// is what macOS already drew, and it is the same *physical* size as the phone's at their own
    /// viewing distances. Only the title and the paddings needed a desktop answer of their own.
    static func metrics(role: CadencePageHeaderRole, surface: CadencePageHeaderSurface) -> CadencePageHeaderMetrics {
        CadencePageHeaderMetrics(
            titleSize: titleSize(role: role, surface: surface),
            eyebrowSize: 10,
            countSize: surface == .regular ? 13 : 12,
            countPaddingH: surface == .regular ? 10 : 8,
            countPaddingV: surface == .regular ? 6 : 4,
            rowSpacing: rowSpacing(surface: surface),
            horizontalPadding: horizontalPadding(surface: surface),
            topPadding: topPadding(surface: surface),
            bottomPadding: bottomPadding(surface: surface)
        )
    }

    /// iOS's spelling: the two size classes, as the boolean every iOS view already has to hand.
    static func metrics(role: CadencePageHeaderRole, isRegularWidth: Bool) -> CadencePageHeaderMetrics {
        metrics(role: role, surface: isRegularWidth ? .regular : .compact)
    }

    private static func titleSize(role: CadencePageHeaderRole, surface: CadencePageHeaderSurface) -> CGFloat {
        switch (role, surface) {
        case (.page, .compact): return 26
        case (.page, .regular): return 30
        // Unchanged: this is the long-standing `CadenceDesktopMetrics.pageTitleSize`, which now
        // reads back from here rather than being declared beside it.
        case (.page, .desktop): return 22
        case (.pane, .compact): return 17
        case (.pane, .regular): return 21
        // The pane/page ratio iOS settled on (0.65–0.70), applied to the desktop page title. macOS
        // drew its Today columns at the full 22 — three column headers shouting at page volume on
        // a screen with no page title above them.
        case (.pane, .desktop): return 16
        }
    }

    private static func rowSpacing(surface: CadencePageHeaderSurface) -> CGFloat {
        switch surface {
        case .compact: return 10
        case .regular: return 12
        case .desktop: return 11
        }
    }

    /// The page gutter. Desktop keeps 18 because it is not the header's alone: `DesktopControlBar`
    /// and every macOS page body sit on the same line, and a header that moved to 16 would be
    /// indented from the rows under it.
    private static func horizontalPadding(surface: CadencePageHeaderSurface) -> CGFloat {
        switch surface {
        case .compact: return 16
        case .regular: return 20
        case .desktop: return 18
        }
    }

    /// Desktop's band is taller than the tablet's rather than shorter, which is why `.desktop` is
    /// not a point on the compact→regular ramp: a pointer surface can spend height on separation
    /// that a phone cannot, and this is the rhythm the macOS pages already share.
    private static func topPadding(surface: CadencePageHeaderSurface) -> CGFloat {
        switch surface {
        case .compact: return 13
        case .regular: return 16
        case .desktop: return 18
        }
    }

    private static func bottomPadding(surface: CadencePageHeaderSurface) -> CGFloat {
        switch surface {
        case .compact: return 7
        case .regular: return 11
        case .desktop: return 12
        }
    }
}
