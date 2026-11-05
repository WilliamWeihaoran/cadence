import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// **[[T-11541]].** An iOS settings card's hairline starts at its rows' text at every text size.
///
/// The rows lead with an `iOSIconTile(size: iOSSettingsMetrics.glyphSlot, iconSize: g)`, whose side
/// is `glyphFrame(glyphSlot, glyph: g)` and so scales with Dynamic Type, while the hairlines were
/// inset by a FIXED `rowTextInset = glyphSlot + glyphLabelSpacing`. The two agreed only at
/// `.large`. Every card's divider is now an `iOSSettingsRowDivider` naming the glyph its rows'
/// tile draws (or, for the Contexts and Available Backups cards, the slot function their leading
/// glyph is framed by), and the inset is that slot plus the spacing.
///
/// `Cadence/iOS/` is `#if os(iOS)` and this target's default leg builds for macOS, so the wiring is
/// read from source, comments blanked; the scaling the fix answers is computed from the shared,
/// ungated metrics the tile itself evaluates.
@Suite
struct CadenceIOSSettingsRowDividerTests {

    private func source(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private func body(_ declaration: String, in path: String) throws -> String {
        let found = CadenceSourceScan.declarationBody(declaration, in: try source(path))
        #expect(found != nil, "\(declaration) not found in \(path); the scan reads nothing")
        return (found ?? "").filter { !$0.isWhitespace }
    }

    /// The cards whose rows are led by an `iOSIconTile`: where the divider is, what it names, and
    /// the row whose tile draws that glyph.
    private static let tileCards: [(path: String, divider: String, row: String)] = [
        ("Cadence/iOS/iOSSettingsComponents.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSSettingsCategoryRow.tileGlyph)",
         "private struct iOSSettingsCategoryRow: View"),
        ("Cadence/iOS/iOSSidebarLayoutSettingsSection.swift",
         "iOSSettingsRowDivider(tileGlyph: Self.tileGlyph)",
         "private func rowContent("),
        ("Cadence/iOS/iOSRemindersSettingsSection.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSRemindersListRow.tileGlyph)",
         "private struct iOSRemindersListRow: View"),
        ("Cadence/iOS/iOSUnmanagedStoreSettingsSection.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSUnmanagedStoreDirectoryRow.tileGlyph)",
         "private struct iOSUnmanagedStoreDirectoryRow: View"),
        ("Cadence/iOS/iOSCalendarSettingsSection.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSDormantCalendarLinkRow.tileGlyph)",
         "private struct iOSDormantCalendarLinkRow: View"),
        ("Cadence/iOS/iOSCalendarSettingsSection.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSMissingCalendarLinkRow.tileGlyph)",
         "private struct iOSMissingCalendarLinkRow: View"),
        ("Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSListLifecycleSettingsRow.tileGlyph)",
         "private struct iOSListLifecycleSettingsRow: View"),
        ("Cadence/iOS/iOSStoreBackupSettingsSection.swift",
         "iOSSettingsRowDivider(tileGlyph: iOSRetainedUnrestoredDirectoryRow.tileGlyph)",
         "private struct iOSRetainedUnrestoredDirectoryRow: View"),
    ]

    /// No settings card insets a hairline by a constant any more: every divider in these cards
    /// goes through `iOSSettingsRowDivider`. The fixed `rowTextInset` constant is gone, so a new
    /// card cannot reach for it without failing to compile; the files are listed rather than swept.
    @Test func noSettingsCardInsetsItsHairlineByAConstant() throws {
        let files = Set(Self.tileCards.map(\.path)).union(["Cadence/iOS/iOSSettingsView.swift"])
        #expect(files.count == 8, "the scan reads fewer files than the cards live in")
        var calls = 0
        for path in files {
            let text = try source(path)
            // The two left: `iOSSettingsRowDivider`'s own body, and the calendar list's 24 (a 12pt
            // dot plus 12, a row with no tile; [[T-9771]]).
            let allowed = path.hasSuffix("iOSSettingsComponents.swift") || path.hasSuffix("iOSCalendarSettingsSection.swift") ? 1 : 0
            #expect(CadenceSourceScan.matchCount("iOSRowDivider\\(leadingInset:", in: text) == allowed,
                    "\(path) insets a hairline without going through iOSSettingsRowDivider")
            calls += CadenceSourceScan.matchCount("iOSSettingsRowDivider\\((tileGlyph|leadingSlot):", in: text)
        }
        let components = try source("Cadence/iOS/iOSSettingsComponents.swift")
        #expect(CadenceSourceScan.matchCount("static let rowTextInset", in: components) == 0,
                "a fixed row text inset is declared again")
        // Eight tile-led cards (two dividers in the lifecycle card), the Available Backups list and
        // the two Contexts cards.
        #expect(calls == 12, "a settings-card divider was added or lost; found \(calls)")
    }

    /// Each card's divider names the glyph its own rows' tile draws, and the row spaces its tile
    /// from its text by the spacing the inset adds.
    @Test func eachCardsDividerNamesTheGlyphItsRowsTileDraws() throws {
        for card in Self.tileCards {
            let file = try source(card.path)
            #expect(file.contains(card.divider), "\(card.path) no longer divides with \(card.divider)")
            let row = try body(card.row, in: card.path)
            #expect(row.contains("size:iOSSettingsMetrics.glyphSlot,iconSize:Self.tileGlyph"),
                    "\(card.row)'s tile draws a glyph its card's divider does not name")
            #expect(row.contains("spacing:iOSSettingsMetrics.glyphLabelSpacing)"),
                    "\(card.row) no longer spaces its tile from its text by the inset's spacing")
        }
        // The two non-tile cards name the slot function their leading glyph is framed by.
        let backups = try source("Cadence/iOS/iOSStoreBackupSettingsSection.swift").filter { !$0.isWhitespace }
        #expect(backups.contains("iOSSettingsRowDivider(leadingSlot:{iOSStoreBackupListMetrics.leadingSlot(at:$0,scaling:$1)})"))
        let root = try source("Cadence/iOS/iOSSettingsView.swift")
        #expect(CadenceSourceScan.matchCount(
            "iOSSettingsRowDivider\\(leadingSlot: \\{ iOSSettingsContextIconMetrics\\.side\\(at: \\$0, scaling: \\$1\\) \\}\\)", in: root
        ) == 2, "the active and archived Contexts cards no longer read the context icon's slot")
    }

    /// The divider sums the row's scaled slot and the spacing; a tile's slot is the expression the
    /// tile evaluates; the context icon's slot is the expression its frame evaluates.
    @Test func theInsetIsTheScaledSlotPlusTheSpacing() throws {
        let components = "Cadence/iOS/iOSSettingsComponents.swift"
        let divider = try body("struct iOSSettingsRowDivider: View", in: components)
        #expect(divider.contains(
            "iOSRowDivider(leadingInset:iOSSettingsMetrics.rowTextInset(after:leadingSlot(dynamicTypeSize,scaling)))"
        ))
        #expect(divider.contains("iOSSettingsMetrics.tileSlot(glyph:tileGlyph,at:$0,scaling:$1)"))

        let metrics = try body("enum iOSSettingsMetrics", in: components)
        #expect(metrics.contains("staticfuncrowTextInset(afterleadingSlot:CGFloat)->CGFloat{leadingSlot+glyphLabelSpacing}"))
        #expect(metrics.contains(
            "iOSTaskPageTypographyMetrics.glyphFrame(glyphSlot,glyph:glyph,at:size,scaling:scaling)"
        ), "the tile slot no longer evaluates the tile's own expression")
        let tile = try body("struct iOSIconTile: View", in: "Cadence/iOS/iOSDesignSystem.swift")
        #expect(tile.contains(
            "letside=iOSTaskPageTypographyMetrics.glyphFrame(size,glyph:iconSize,at:dynamicTypeSize,scaling:scaling)"
        ), "the tile no longer sizes itself the way the divider's slot assumes")

        let contexts = "Cadence/iOS/iOSSettingsContextSection.swift"
        let side = try body("enum iOSSettingsContextIconMetrics", in: contexts)
        let icon = try body("private struct iOSSettingsContextIcon: View", in: contexts)
        let frame = "CadenceSettingsTypographyLayout.glyphFrame(iOSSettingsMetrics.glyphSlot,glyph:15,role:.rowTitle,"
        #expect(side.contains(frame + "at:size,scaling:scaling)"))
        #expect(icon.contains(frame + "at:dynamicTypeSize,scaling:scaling)"), "the context icon is framed differently")
    }

    /// Non-vacuity: away from `.large` a scaled slot leaves the fixed `glyphSlot` for every glyph
    /// a settings card draws, in both directions, so a constant inset was wrong at every other
    /// size. Relations, not figures.
    @Test func everyCardsSlotLeavesTheFixedSlotAwayFromLarge() {
        let fixed: CGFloat = 32
        for glyph: CGFloat in [13, 14, 15] {
            let slot = { (size: DynamicTypeSize) in
                iOSTaskPageTypographyMetrics.glyphFrame(fixed, glyph: glyph, at: size, scaling: .enabled)
            }
            #expect(slot(.large) == fixed)
            #expect(slot(.medium) < fixed)
            #expect(slot(.xxLarge) > fixed)
            #expect(iOSTaskPageTypographyMetrics.glyphFrame(fixed, glyph: glyph, at: .xxLarge, scaling: .fixed) == fixed)
        }
        let context = { (size: DynamicTypeSize) in
            CadenceSettingsTypographyLayout.glyphFrame(fixed, glyph: 15, role: .rowTitle, at: size, scaling: .enabled)
        }
        #expect(context(.large) == fixed)
        #expect(context(.xxLarge) > fixed)
    }
}
