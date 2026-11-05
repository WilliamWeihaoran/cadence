import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// [[T-10020]], [[T-10021]], [[T-10022]]: the iOS Backups card on Settings → Data Safety drew its main button
/// and its heading differently from the Mac's Backups card and from the three cards above it.
///
/// - Create Backup was a tinted `.secondary` plate, the same weight as Clean Automatic beside it,
///   where the Mac fills it (`.filled(Theme.blue)`) and tints only the amber clean-up.
/// - The card opened on its description paragraph. The Export, Import and Delete Cadence Data cards
///   above it each open with a semibold title under their section label, and the Mac's Backups
///   card opens with `CadenceStoreBackupPresentation.title`.
///
/// - [[T-10022]]: an empty Available Backups card was a bare line where the Mac draws an
///   `externaldrive` glyph row, and Unrestored Store Files listed bare paths 8pt apart where the Mac
///   draws a row per folder divided by `CadenceRowDivider`.
///
/// `Cadence/iOS/` is `#if os(iOS)` and this target's default leg builds for macOS, so these are
/// source reads of the named declarations, comments blanked, each with a non-vacuity anchor.
@Suite
struct CadenceIOSStoreBackupCardTests {

    private let phonePath = "Cadence/iOS/iOSStoreBackupSettingsSection.swift"

    private func body(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let found = CadenceSourceScan.declarationBody(declaration, in: source)
        #expect(found != nil, "\(declaration) not found in \(path); the scan reads nothing")
        return (found ?? "").filter { !$0.isWhitespace }
    }

    private var phoneCard: String {
        get throws { try body("private var backupsCard: some View", in: phonePath) }
    }

    @Test func createBackupIsThePrimaryPlateAsTheMacFillsIt() throws {
        let mac = try body("var body: some View", in: "Cadence/macOS/Views/SettingsDataSafetySection.swift")
        #expect(
            mac.contains("SettingsActionButton(tone:.filled(Theme.blue),action:createBackup)"),
            "the Mac no longer fills Create Backup; this pins against it"
        )

        let card = try phoneCard
        let create = card.range(of: "title:CadenceStoreBackupPresentation.createButtonTitle,")
        let clean = card.range(of: "title:CadenceStoreBackupPresentation.cleanUpButtonTitle,")
        #expect(create != nil && clean != nil, "the scan no longer reaches the two buttons")
        guard let create, let clean, create.upperBound < clean.lowerBound else { return }

        let createArguments = card[create.upperBound..<clean.lowerBound]
        #expect(createArguments.contains("role:.primary,"))
        let cleanArguments = card[clean.upperBound...].prefix(160)
        #expect(!cleanArguments.contains("role:.primary"), "only the card's main act is filled")
    }

    @Test func theCardOpensWithItsTitleLikeItsSiblingsAndTheMac() throws {
        let card = try phoneCard
        let title = card.range(of: "Text(CadenceStoreBackupPresentation.title)")
        let description = card.range(of: "Text(CadenceStoreBackupPresentation.description)")
        #expect(description != nil, "the scan no longer reaches the description")
        #expect(title != nil)
        if let title, let description {
            #expect(title.upperBound < description.lowerBound, "the title heads the card")
            let styling = card[title.upperBound..<description.lowerBound]
            #expect(styling.contains(".cadenceFont(.rowTitle,base:15,weight:.semibold)"))
            #expect(styling.contains(".foregroundStyle(Theme.text)"))
        }

        // The sibling this matches: the Export card's title, drawn the same way.
        let export = try body(
            "struct iOSDataExportSettingsSection: View",
            in: "Cadence/iOS/iOSDataExportSettingsSection.swift"
        )
        #expect(export.contains(
            "Text(CadenceDataExportPresentation.title).cadenceFont(.rowTitle,base:15,weight:.semibold).foregroundStyle(Theme.text)"
        ), "the sibling no longer draws the title this pins against")
    }

    // MARK: - [[T-10022]]

    private var phoneSection: String {
        get throws { try body("struct iOSStoreBackupSettingsSection: View", in: phonePath) }
    }

    @Test func anEmptyBackupListIsAGlyphRowAsOnTheMac() throws {
        let mac = try body("var body: some View", in: "Cadence/macOS/Views/SettingsDataSafetySection.swift")
        #expect(
            mac.contains("ifbackups.isEmpty{HStack(spacing:12){Image(systemName:\"externaldrive\")"),
            "the Mac no longer draws the glyph row this pins against"
        )

        let section = try phoneSection
        let empty = section.range(of: "ifbackups.isEmpty{")
        let populated = section.range(of: "}else{letlisted=")
        #expect(empty != nil && populated != nil, "the scan no longer reaches the empty branch")
        guard let empty, let populated, empty.upperBound < populated.lowerBound else { return }

        let branch = section[empty.upperBound..<populated.lowerBound]
        #expect(branch.hasPrefix("HStack("), "the empty state is a row, not a bare line")
        let glyph = branch.range(of: "Image(systemName:\"externaldrive\")")
        let text = branch.range(of: "Text(CadenceStoreBackupPresentation.noBackupsText)")
        #expect(glyph != nil && text != nil)
        if let glyph, let text {
            #expect(glyph.upperBound < text.lowerBound, "the glyph leads the line")
        }
    }

    // MARK: - [[T-11431]]

    /// The empty state's glyph slot and a row's tile slot are one width, so "No backups
    /// available." leads where a row's title does. Measured 1.0pt apart on `Cadence-iPadPro11`
    /// (text size Medium) when the empty state's slot was a fixed `glyphSlot` and the row's
    /// tile scaled.
    @Test func theEmptyStateAndARowShareOneLeadingSlot() throws {
        let section = try phoneSection
        let empty = section.range(of: "ifbackups.isEmpty{")
        let populated = section.range(of: "}else{letlisted=")
        #expect(empty != nil && populated != nil, "the scan no longer reaches the empty branch")
        guard let empty, let populated, empty.upperBound < populated.lowerBound else { return }
        let branch = section[empty.upperBound..<populated.lowerBound]
        #expect(
            branch.contains(".frame(width:iOSStoreBackupListMetrics.leadingSlot(at:dynamicTypeSize,scaling:scaling))"),
            "the empty state's glyph no longer sits in the row's slot"
        )
        #expect(!branch.contains("iOSSettingsMetrics.glyphSlot"), "a fixed slot is back in the empty state")

        let row = try body("private struct iOSStoreBackupRow: View", in: phonePath)
        #expect(row.contains(
            "iOSIconTile(systemImage:\"externaldrive.fill\",color:Theme.amber,size:iOSSettingsMetrics.glyphSlot,iconSize:iOSStoreBackupListMetrics.rowGlyphSize)"
        ), "the row's tile no longer reads the shared slot")

        let metrics = try body("enum iOSStoreBackupListMetrics", in: phonePath)
        #expect(metrics.contains(
            "iOSTaskPageTypographyMetrics.glyphFrame(iOSSettingsMetrics.glyphSlot,glyph:rowGlyphSize,at:size,scaling:scaling)"
        ), "the slot no longer evaluates the tile's own expression")

        // The tile this matches: its side is the same `glyphFrame(size, glyph: iconSize)`.
        let tile = try body("struct iOSIconTile: View", in: "Cadence/iOS/iOSDesignSystem.swift")
        #expect(tile.contains(
            "letside=iOSTaskPageTypographyMetrics.glyphFrame(size,glyph:iconSize,at:dynamicTypeSize,scaling:scaling)"
        ), "the tile no longer sizes itself the way the shared slot assumes")
    }

    /// Non-vacuity for the test above: a scaled slot really does leave `glyphSlot` away from
    /// `.large`, which is why a fixed slot drifted. Asserts a relation, not a figure.
    @Test func aScaledTileSlotLeavesTheFixedSlotAwayFromLarge() {
        let fixed: CGFloat = 32
        let atLarge = iOSTaskPageTypographyMetrics.glyphFrame(fixed, glyph: 13, at: .large, scaling: .enabled)
        let atMedium = iOSTaskPageTypographyMetrics.glyphFrame(fixed, glyph: 13, at: .medium, scaling: .enabled)
        #expect(atLarge == fixed)
        #expect(atMedium < fixed)
    }

    @Test func unrestoredFoldersAreDividedRowsWithoutAnAction() throws {
        let card = try body("private var unrestoredCard: some View", in: phonePath)
        #expect(card.contains("ForEach(Array(retainedUnrestoredDirectories.enumerated())"), "the scan no longer reaches the list")
        #expect(card.contains("iOSRetainedUnrestoredDirectoryRow(directoryURL:directoryURL)"))
        #expect(card.contains(
            "ifindex<retainedUnrestoredDirectories.count-1{iOSSettingsRowDivider(tileGlyph:iOSRetainedUnrestoredDirectoryRow.tileGlyph)}"
        ), "one divider between rows, as the Unmanaged Store card divides its own")
        #expect(!card.contains("Text(directoryURL.path)"), "a bare path is back in the card")

        let row = try body("private struct iOSRetainedUnrestoredDirectoryRow: View", in: phonePath)
        #expect(row.contains("iOSIconTile(systemImage:\"exclamationmark.triangle\",color:Theme.amber,"))
        let path = row.range(of: "Text(directoryURL.path)")
        let detail = row.range(of: "Text(CadenceStoreBackupPresentation.unrestoredRowDetail)")
        #expect(path != nil && detail != nil)
        if let path, let detail { #expect(path.upperBound < detail.lowerBound, "path, then detail") }
        // Read-only: no closure member and no button, so nothing destructive can be handed to it.
        #expect(!row.contains("->Void"))
        #expect(!row.contains("Button") && !row.contains("ActionButton"))

        // The Mac's row reads the same shared detail, so the two cannot drift apart.
        let macRow = try body(
            "private struct RetainedUnrestoredOriginalsRow: View",
            in: "Cadence/macOS/Views/SettingsDataSafetySection.swift"
        )
        #expect(macRow.contains("Text(CadenceStoreBackupPresentation.unrestoredRowDetail)"))
    }
}
