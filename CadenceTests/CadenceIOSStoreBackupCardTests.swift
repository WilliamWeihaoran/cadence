import Foundation
import Testing
@testable import Cadence

/// [[T-10020]], [[T-10021]]: the iOS Backups card on Settings → Data Safety drew its main button
/// and its heading differently from the Mac's Backups card and from the three cards above it.
///
/// - Create Backup was a tinted `.secondary` plate, the same weight as Clean Automatic beside it,
///   where the Mac fills it (`.filled(Theme.blue)`) and tints only the amber clean-up.
/// - The card opened on its description paragraph. The Export, Import and Delete Cadence Data cards
///   above it each open with a semibold title under their section label, and the Mac's Backups
///   card opens with `CadenceStoreBackupPresentation.title`.
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
}
