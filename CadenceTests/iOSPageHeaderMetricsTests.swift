import Foundation
import Testing
@testable import Cadence

/// Six iOS views drew "eyebrow, title, maybe a count, maybe a back chevron" and had drifted into
/// six title sizes, two eyebrow sizes, two count badges and three spellings of the leading tile.
/// They are one view now, and the one difference that survived is `iOSPageHeaderRole`.
///
/// `Cadence/iOS/` is inside `#if os(iOS)` and invisible to this macOS-built target, so what these
/// pin is the thing worth pinning anyway: the ramp itself. It lives outside the platform guard for
/// exactly that reason.
struct iOSPageHeaderMetricsTests {
    private static let widths = [true, false]

    private static func metrics(_ role: iOSPageHeaderRole, _ isRegularWidth: Bool) -> iOSPageHeaderMetrics {
        iOSPageHeaderMetrics.metrics(role: role, isRegularWidth: isRegularWidth)
    }

    // MARK: - What varies

    /// The premise. A third role would mean a third answer to "how loudly does this row speak",
    /// which is where six of them came from.
    @Test func aHeaderIsTheTopOfEitherAScreenOrAColumnAndNothingElse() {
        #expect(iOSPageHeaderRole.allCases.count == 2)
    }

    /// A whole screen names itself louder than one column inside a split. This is the *only*
    /// legitimate difference between the six, and it has to actually be visible or the parameter
    /// is not earning its place.
    @Test func aPageTitleOutranksAPaneTitleAtBothWidths() {
        for isRegular in Self.widths {
            let page = Self.metrics(.page, isRegular)
            let pane = Self.metrics(.pane, isRegular)

            #expect(page.titleSize > pane.titleSize, "regular=\(isRegular)")
            #expect(page.tileSize > pane.tileSize, "regular=\(isRegular)")
        }
    }

    /// Both roles, both widths: four numbers, and the ramp never doubles back. iPad Today used to
    /// be 23pt against the phone's 26 for the same idea, so the tablet's title was *smaller* than
    /// the phone's.
    @Test func theTitleRampNeverInverts() {
        for role in iOSPageHeaderRole.allCases {
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

    // MARK: - What must not vary

    /// The drift that started this: `iOSPanelHeader` set its eyebrow at 9pt on compact width while
    /// every other header set 10. Nobody chose that. The eyebrow is `SectionEyebrowLabel`'s size,
    /// which is one size, everywhere.
    @Test func theEyebrowIsOneSizeInEveryRoleAtEveryWidth() {
        let sizes = Set(iOSPageHeaderRole.allCases.flatMap { role in
            Self.widths.map { Self.metrics(role, $0).eyebrowSize }
        })

        #expect(sizes == [10])
    }

    /// Volume varies by role; vocabulary does not. A pane header and a page header sit at the same
    /// gutter and count in the same capsule — otherwise iPad Today's column and the Inbox beside it
    /// read as two apps.
    @Test func roleChangesVolumeAndNothingElse() {
        for isRegular in Self.widths {
            let page = Self.metrics(.page, isRegular)
            let pane = Self.metrics(.pane, isRegular)

            #expect(page.horizontalPadding == pane.horizontalPadding, "regular=\(isRegular)")
            #expect(page.topPadding == pane.topPadding, "regular=\(isRegular)")
            #expect(page.bottomPadding == pane.bottomPadding, "regular=\(isRegular)")
            #expect(page.rowSpacing == pane.rowSpacing, "regular=\(isRegular)")
            #expect(page.countSize == pane.countSize, "regular=\(isRegular)")
            #expect(page.countPaddingH == pane.countPaddingH, "regular=\(isRegular)")
            #expect(page.countPaddingV == pane.countPaddingV, "regular=\(isRegular)")
        }
    }

    /// `iOSIconTile` at 32/15 and `iOSListIconBadge` at 32/14.08 were two tiles meant to be one —
    /// a tile resized without its glyph. The ratio is stated once, so it cannot happen again.
    @Test func theGlyphAlwaysScalesWithItsTile() {
        for role in iOSPageHeaderRole.allCases {
            for isRegular in Self.widths {
                let metrics = Self.metrics(role, isRegular)

                #expect(metrics.iconSize == metrics.tileSize * 0.44, "\(role.rawValue) regular=\(isRegular)")
                #expect(metrics.iconSize < metrics.tileSize, "\(role.rawValue) regular=\(isRegular)")
            }
        }
    }

    /// A header with a zero anywhere in it draws as a collapsed row rather than as an error, which
    /// is the failure mode a ramp built out of ternaries invites.
    @Test func everyMeasurementIsPositive() {
        for role in iOSPageHeaderRole.allCases {
            for isRegular in Self.widths {
                let metrics = Self.metrics(role, isRegular)

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
        for role in iOSPageHeaderRole.allCases {
            for isRegular in Self.widths {
                let metrics = Self.metrics(role, isRegular)

                #expect(metrics.titleSize > metrics.eyebrowSize, "\(role.rawValue) regular=\(isRegular)")
                #expect(metrics.titleSize > metrics.countSize, "\(role.rawValue) regular=\(isRegular)")
            }
        }
    }
}
