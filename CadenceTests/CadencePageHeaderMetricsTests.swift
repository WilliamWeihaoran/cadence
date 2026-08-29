import Foundation
import SwiftUI
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
    /// again, and `CommitmentIconTile` defaults its glyph from it.
    ///
    /// **Two of those five were page headers, and page headers no longer draw a tile at all** —
    /// the user asked for the identity tile dropped everywhere, so `tileSize` and the `iconSize`
    /// derived from it are gone from this type. The ratio stays because the tiles inside rows,
    /// cards and pickers stay, and it is those that this now pins.
    /// `CadenceTodayUnificationTests` guards that no header takes a `systemImage` again.
    @Test func theGlyphRatioIsStatedOnceForEveryTileThatIsLeft() {
        #expect(CadencePageHeaderMetrics.tileGlyphRatio == 0.44)
        #expect(CadencePageHeaderMetrics.tileGlyphRatio < 1)
        #expect(CadencePageHeaderMetrics.tileFillOpacity == 0.14)
    }

    /// A header with a zero anywhere in it draws as a collapsed row rather than as an error, which
    /// is the failure mode a ramp built out of ternaries invites.
    @Test func everyMeasurementIsPositiveInPageHeaderMetrics() {
        for role in CadencePageHeaderRole.allCases {
            for surface in Self.surfaces {
                let metrics = Self.metrics(role, surface)

                #expect(metrics.titleSize > 0)
                #expect(metrics.eyebrowSize > 0)
                #expect(metrics.countSize > 0)
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

    // MARK: - The tile border, which was the last thing the two tiles disagreed about

    /// T-157. `iOSIconTile` stroked `color.opacity(0.20)` and `CommitmentIconTile` stroked nothing,
    /// so a 0.14 tinted fill read as a plate on an iPad and as a wash on a Mac. The reason that is
    /// a fork rather than two contexts: `HabitIconTile` is a single shared view whose entire body is
    /// an `#if os(macOS)` picking between these two tiles, at 32/56pt on macOS against 34/52pt on
    /// iOS — the same tile, in the same card, within 4pt of the same size.
    @Test func theTileBorderIsOneValueForBothPlatforms() {
        #expect(CadencePageHeaderMetrics.tileBorderOpacity == 0.20)
        // Fainter than the fill would be an edge you cannot see; heavier reads as a control.
        #expect(CadencePageHeaderMetrics.tileBorderOpacity > CadencePageHeaderMetrics.tileFillOpacity)
        #expect(CadencePageHeaderMetrics.tileBorderOpacity < 0.5)
    }

    /// The assertion that bites when the call site is reverted rather than the constant. A shared
    /// number with one reader is not a convergence — `tileFillOpacity` was already 0.14 in the
    /// metrics *and* spelled `0.14` again inside `iOSIconTile`, which is how the pair drifted.
    ///
    /// `Cadence/iOS/` is invisible to this macOS-built target, so `iOSIconTile` can only be pinned
    /// as source text. `CommitmentIconTile` is read the same way deliberately: what matters is that
    /// the stroke is *there*, not that some rendered pixel is 0.20.
    @Test func bothTilesStrokeThatBorderAndNeitherRestatesTheNumbers() throws {
        let tiles = [
            ("CommitmentIconTile", "Cadence/macOS/Views/CommitmentSharedViews.swift"),
            ("iOSIconTile", "Cadence/iOS/iOSDesignSystem.swift"),
        ]

        for (name, path) in tiles {
            let body = try declarationBody(of: name, in: path)

            #expect(body.contains("CadencePageHeaderMetrics.tileBorderOpacity"), "\(name) does not read the shared tile border")
            #expect(body.contains("strokeBorder"), "\(name) does not stroke a border")
            #expect(body.contains("bordered"), "\(name) has no opt-out for a tile inside another plate")
            #expect(body.contains("CadencePageHeaderMetrics.tileFillOpacity"), "\(name) does not read the shared tile fill")
            // The literals, back in the body, are the regression.
            #expect(!body.contains("0.20"), "\(name) restates the border opacity")
            #expect(!body.contains("0.14"), "\(name) restates the fill opacity")
        }
    }

    // MARK: - The tile corner, which was the genuinely last thing they disagreed about

    /// T-178, the follow-on to T-157. The border converged there and the *corner* was deliberately
    /// left, because a radius changes geometry rather than adding a hairline: `CommitmentIconTile`
    /// computed `min(12, size * 0.28)` and drew it `.circular`, `iOSIconTile` read
    /// `Theme.radiusControl` and drew it `.continuous`.
    ///
    /// The token won, decided off renders of all four combinations at 32/34/52/56pt. Two things the
    /// renders showed that the argument did not: the formula saturates at 42.86pt, so the only
    /// values it ever produced in this app were 8.96 (at 32) and 12 (at 56) — both within 2pt of the
    /// token, and its one non-habit call site passed a literal `9` rather than trusting it; and the
    /// worry about a 56pt hero reading square belonged to the *curve*, not the radius, since 10pt
    /// `.circular` was clearly the most cornered of the four and 10pt `.continuous` the
    /// second-roundest.
    @Test func theTileCornerIsOneRadiusOnTheDeclaredScaleAndOneCurve() {
        #expect(CadencePageHeaderMetrics.tileCornerRadius == Theme.radiusControl)
        #expect(CadencePageHeaderMetrics.tileCornerStyle == .continuous)
        // The point of a token is that it is *on* the scale. A formula returning 8.96 was not.
        #expect([Theme.radiusControl, Theme.radiusCard, Theme.radiusPanel].contains(CadencePageHeaderMetrics.tileCornerRadius))
    }

    /// The call-site half, for the same reason as the border above: a shared radius with one reader
    /// is not a convergence. The forbidden strings are the two spellings that were there — the
    /// formula on macOS and the restated token plus literal curve on iOS.
    @Test func bothTilesReadThatCornerAndNeitherKeepsItsOldGeometry() throws {
        let tiles = [
            ("CommitmentIconTile", "Cadence/macOS/Views/CommitmentSharedViews.swift"),
            ("iOSIconTile", "Cadence/iOS/iOSDesignSystem.swift"),
        ]

        for (name, path) in tiles {
            let body = try declarationBody(of: name, in: path)

            #expect(body.contains("CadencePageHeaderMetrics.tileCornerRadius"), "\(name) does not read the shared tile radius")
            #expect(body.contains("CadencePageHeaderMetrics.tileCornerStyle"), "\(name) does not read the shared tile curve")
            #expect(!body.contains("0.28"), "\(name) still computes a size-relative radius")
            #expect(!body.contains(".circular"), "\(name) still draws a circular corner")
            #expect(!body.contains(".continuous"), "\(name) restates the corner curve")
            #expect(!body.contains("Theme.radiusControl"), "\(name) restates the radius token instead of reading the tile figure")
        }
    }

    /// **No call site overrides it.** Both tiles keep a `cornerRadius` escape hatch, and the history
    /// says an escape hatch is how a third geometry arrives: the macOS goals row passed
    /// `cornerRadius: 9` at 34pt while `HabitIconTile` next door computed 8.96, and one iOS call
    /// site passed `Theme.radiusControl` — the default — back in by hand. Both are gone. A future
    /// override is not forbidden, but it has to arrive as an edit to this list.
    @Test func noTileCallSitePassesItsOwnCorner() throws {
        var overrides: [String] = []

        for path in try swiftFiles(under: "Cadence") {
            let code = strippingComments(try sourceFile(path))
            for name in ["CommitmentIconTile(", "iOSIconTile("] {
                for arguments in argumentLists(after: name, in: code) where arguments.contains("cornerRadius:") {
                    overrides.append("\(path): \(name)")
                }
            }
        }

        #expect(overrides.isEmpty, "these call sites still pick their own tile corner: \(overrides)")
    }
}

/// Every balanced argument list following an occurrence of `opening` — so a `cornerRadius:` in the
/// *next* call along cannot be attributed to this one.
private func argumentLists(after opening: String, in source: String) -> [String] {
    var results: [String] = []
    var searchStart = source.startIndex

    while let match = source.range(of: opening, range: searchStart..<source.endIndex) {
        searchStart = match.upperBound
        var depth = 1
        var index = match.upperBound

        while index < source.endIndex, depth > 0 {
            if source[index] == "(" { depth += 1 }
            if source[index] == ")" { depth -= 1 }
            index = source.index(after: index)
        }
        results.append(String(source[match.upperBound..<index]))
    }
    return results
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)` on purpose: the URL variant
/// yields absolute paths that `FileManager` has already resolved through the `/tmp` against
/// `/private/tmp` symlink `#filePath` names literally.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let directory = root.appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

/// The source text of one top-level declaration, from its `struct` line to the next top-level
/// declaration in the same file. Crude on purpose: it over-reads at the tail, which can only make
/// the `!contains` assertions above stricter.
private func declarationBody(of name: String, in path: String) throws -> String {
    let source = strippingComments(try sourceFile(path))
    let pattern = "(?m)^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|enum|class|extension)\\s+\(name)\\b"
    guard let start = source.range(of: pattern, options: .regularExpression) else {
        Issue.record("\(path) does not declare \(name)")
        return ""
    }

    let rest = source[start.upperBound...]
    let nextPattern = "(?m)^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|enum|class|extension)\\s"
    let end = rest.range(of: nextPattern, options: .regularExpression)?.lowerBound ?? rest.endIndex
    return String(rest[..<end])
}

/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree), so read relative to it rather than resolving anything.
private func sourceFile(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` and `/* */` comments so the assertions read code rather than prose — the
/// doc comments above both tiles quote the very numbers this test forbids in their bodies.
private func strippingComments(_ source: String) -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
