import Foundation
import Testing
@testable import Cadence

/// Six iOS views and four macOS ones drew "eyebrow, title, maybe a count, maybe a tile" and had
/// drifted into a dozen title sizes, two eyebrow sizes, three count badges and four spellings of
/// the leading tile. They are one view per platform now, and the two differences that survived are
/// `CadencePageHeaderRole` and `CadencePageHeaderSurface`.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what these
/// pin is the thing worth pinning anyway: the ramp itself. It lives in `Shared/` outside any
/// platform guard for exactly that reason.
struct CadencePageHeaderMetricsTests {
    private static let widths = [true, false]
    private static let surfaces = CadencePageHeaderSurface.allCases

    private static func metrics(_ role: CadencePageHeaderRole, _ isRegularWidth: Bool) -> CadencePageHeaderMetrics {
        CadencePageHeaderMetrics.metrics(role: role, isRegularWidth: isRegularWidth)
    }

    private static func metrics(_ role: CadencePageHeaderRole, _ surface: CadencePageHeaderSurface) -> CadencePageHeaderMetrics {
        CadencePageHeaderMetrics.metrics(role: role, surface: surface)
    }

    // MARK: - What varies

    /// The premise. A third role would mean a third answer to "how loudly does this row speak",
    /// which is where ten of them came from.
    @Test func aHeaderIsTheTopOfEitherAScreenOrAColumnAndNothingElse() {
        #expect(CadencePageHeaderRole.allCases.count == 2)
    }

    /// A whole screen names itself louder than one column inside a split. This is the *only*
    /// legitimate difference between the ten, and it has to actually be visible or the parameter
    /// is not earning its place. macOS is in here now: its Today columns drew at the full page
    /// size, so three column headings shouted at Inbox volume on the one page with no page title.
    @Test func aPageTitleOutranksAPaneTitleOnEverySurface() {
        for surface in Self.surfaces {
            let page = Self.metrics(.page, surface)
            let pane = Self.metrics(.pane, surface)

            #expect(page.titleSize > pane.titleSize, "\(surface.rawValue)")
            #expect(page.tileSize > pane.tileSize, "\(surface.rawValue)")
        }
    }

    /// Both roles, both iOS widths: four numbers, and the ramp never doubles back. iPad Today used
    /// to be 23pt against the phone's 26 for the same idea, so the tablet's title was *smaller*
    /// than the phone's.
    @Test func theTitleRampNeverInverts() {
        for role in CadencePageHeaderRole.allCases {
            let regular = Self.metrics(role, true)
            let compact = Self.metrics(role, false)

            #expect(regular.titleSize > compact.titleSize, "\(role.rawValue)")
            #expect(regular.tileSize > compact.tileSize, "\(role.rawValue)")
            #expect(regular.countSize >= compact.countSize, "\(role.rawValue)")
            #expect(regular.horizontalPadding >= compact.horizontalPadding, "\(role.rawValue)")
            #expect(regular.topPadding >= compact.topPadding, "\(role.rawValue)")
            #expect(regular.bottomPadding >= compact.bottomPadding, "\(role.rawValue)")
        }
    }

    /// The two iOS size classes are one ramp; `.desktop` is deliberately **not** a point on it, so
    /// it is spelled as its own surface rather than reached by passing `isRegularWidth: true`.
    @Test func theTwoWidthClassesAreTheIOSSurfacesAndNeitherIsDesktop() {
        for role in CadencePageHeaderRole.allCases {
            #expect(Self.metrics(role, true) == Self.metrics(role, .regular), "\(role.rawValue)")
            #expect(Self.metrics(role, false) == Self.metrics(role, .compact), "\(role.rawValue)")
            #expect(Self.metrics(role, .desktop) != Self.metrics(role, .regular), "\(role.rawValue)")
        }
    }

    // MARK: - The earned macOS difference

    /// A Mac window is wider than an iPad and its type is set *smaller*, not larger — Apple's own
    /// large title is 26pt on macOS against 34 on iOS, and Cadence's desktop body text is 13pt
    /// against the phone's 15–17. Folding macOS into `.regular` would have put a 30pt title over
    /// 13pt rows. This is the difference `.desktop` exists to keep, so it is pinned rather than
    /// left to be "fixed" by the next convergence sweep.
    @Test func macOSSetsTypeBelowTheTabletForTheSameRole() {
        for role in CadencePageHeaderRole.allCases {
            #expect(Self.metrics(role, .desktop).titleSize < Self.metrics(role, .regular).titleSize, "\(role.rawValue)")
        }
    }

    /// The desktop figures themselves. 22 is what every macOS page header has always been; 16 is
    /// the pane/page ratio iOS settled on, applied to it.
    @Test func theDesktopTitleRampIsTwentyTwoOverSixteen() {
        #expect(Self.metrics(.page, .desktop).titleSize == 22)
        #expect(Self.metrics(.pane, .desktop).titleSize == 16)
    }

    /// The desktop gutter is not the header's alone: `DesktopControlBar` and every macOS page body
    /// sit on the same line, so a header that moved to iOS's 16 would be indented from the rows
    /// under it. `CadenceDesktopMetrics` reads these back from here rather than restating them, so
    /// this pins that the two cannot drift apart again.
    @Test func theDesktopPageMetricsAreTheOnesTheRestOfTheMacPageAlignsTo() {
        let desktop = Self.metrics(.page, .desktop)

        #expect(desktop.horizontalPadding == CadenceDesktopMetrics.pageHorizontalPadding)
        #expect(desktop.topPadding == CadenceDesktopMetrics.pageHeaderTopPadding)
        #expect(desktop.bottomPadding == CadenceDesktopMetrics.pageHeaderBottomPadding)
        #expect(desktop.titleSize == CadenceDesktopMetrics.pageTitleSize)
    }

    // MARK: - What must not vary

    /// The drift that started this: `iOSPanelHeader` set its eyebrow at 9pt on compact width while
    /// every other header set 10. Nobody chose that. The eyebrow is `SectionEyebrowLabel`'s size,
    /// which is one size, everywhere — including on macOS, which draws the same component.
    @Test func theEyebrowIsOneSizeInEveryRoleOnEverySurface() {
        let sizes = Set(CadencePageHeaderRole.allCases.flatMap { role in
            Self.surfaces.map { Self.metrics(role, $0).eyebrowSize }
        })

        #expect(sizes == [10])
    }

    /// Volume varies by role; vocabulary does not. A pane header and a page header sit at the same
    /// gutter and count in the same capsule — otherwise Today's columns and the Inbox beside them
    /// read as two apps.
    @Test func roleChangesVolumeAndNothingElse() {
        for surface in Self.surfaces {
            let page = Self.metrics(.page, surface)
            let pane = Self.metrics(.pane, surface)

            #expect(page.horizontalPadding == pane.horizontalPadding, "\(surface.rawValue)")
            #expect(page.topPadding == pane.topPadding, "\(surface.rawValue)")
            #expect(page.bottomPadding == pane.bottomPadding, "\(surface.rawValue)")
            #expect(page.rowSpacing == pane.rowSpacing, "\(surface.rawValue)")
            #expect(page.countSize == pane.countSize, "\(surface.rawValue)")
            #expect(page.countPaddingH == pane.countPaddingH, "\(surface.rawValue)")
            #expect(page.countPaddingV == pane.countPaddingV, "\(surface.rawValue)")
        }
    }

    /// `iOSIconTile` at 32/15, `iOSListIconBadge` at 32/14.08, `DesktopPageHeader` at 32/15,
    /// `CommitmentIconTile` at 32/13 and `CadenceSettingsHeader` at 42/17 were five tiles meant to
    /// be one — tiles resized without their glyphs. The ratio is stated once, so it cannot happen
    /// again, and `CommitmentIconTile` now defaults its glyph from it.
    @Test func theGlyphAlwaysScalesWithItsTile() {
        for role in CadencePageHeaderRole.allCases {
            for surface in Self.surfaces {
                let metrics = Self.metrics(role, surface)

                #expect(metrics.iconSize == metrics.tileSize * CadencePageHeaderMetrics.tileGlyphRatio, "\(role.rawValue) \(surface.rawValue)")
                #expect(metrics.iconSize < metrics.tileSize, "\(role.rawValue) \(surface.rawValue)")
            }
        }
    }

    /// A header with a zero anywhere in it draws as a collapsed row rather than as an error, which
    /// is the failure mode a ramp built out of ternaries invites.
    @Test func everyMeasurementIsPositive() {
        for role in CadencePageHeaderRole.allCases {
            for surface in Self.surfaces {
                let metrics = Self.metrics(role, surface)

                #expect(metrics.titleSize > 0)
                #expect(metrics.eyebrowSize > 0)
                #expect(metrics.countSize > 0)
                #expect(metrics.tileSize > 0)
                #expect(metrics.rowSpacing > 0)
                #expect(metrics.horizontalPadding > 0)
                #expect(metrics.topPadding > 0)
                #expect(metrics.bottomPadding > 0)
            }
        }
    }

    /// The eyebrow is the quiet half of the pair and the title the loud one, at every step. A ramp
    /// that closed that gap would be a header whose label competed with its name.
    @Test func theTitleAlwaysOutranksItsEyebrowAndItsCount() {
        for role in CadencePageHeaderRole.allCases {
            for surface in Self.surfaces {
                let metrics = Self.metrics(role, surface)

                #expect(metrics.titleSize > metrics.eyebrowSize, "\(role.rawValue) \(surface.rawValue)")
                #expect(metrics.titleSize > metrics.countSize, "\(role.rawValue) \(surface.rawValue)")
            }
        }
    }

    /// One tile fill and one count fill across both platforms. macOS drew its header tile at 0.12,
    /// `CommitmentIconTile` at 0.14 and the settings tile at 0.18; the count capsule was 0.11 on
    /// iOS and 0.12 on macOS. None of those five was a decision.
    @Test func theTileAndCountFillsAreOneValueEach() {
        #expect(CadencePageHeaderMetrics.tileFillOpacity == 0.14)
        #expect(CadencePageHeaderMetrics.countFillOpacity == 0.12)
    }
}
