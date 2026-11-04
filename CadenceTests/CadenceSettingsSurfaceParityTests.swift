import Foundation
import Testing
@testable import Cadence

/// [[T-11199]]: a Mac/iOS parity pass on Settings under [[T-8201]]. Four small differences with no
/// hardware or input sentence, each now one shared value both platforms read.
///
/// Read as source where the view is the claim: the iOS files never compile in this target and the
/// Mac rows are private views, so what is asserted is that each surface reads the shared constant
/// and neither types its own copy beside it.
struct CadenceSettingsSurfaceParityTests {

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    private static func body(_ declaration: String, in path: String) throws -> String {
        let source = try code(path)
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: source),
            "\(path): `\(declaration)` is gone"
        )
    }

    // MARK: - The sidebar layout card's eyebrow

    /// The Mac said "Main Sidebar Tabs" over the card iOS called "Sidebar Rows" -- the one synced
    /// layout record, edited from both. The sidebar draws rows, so iOS's noun is the one.
    @Test func bothSidebarLayoutCardsReadTheOneEyebrow() throws {
        #expect(CadenceSidebarSettingsCopy.sectionTitle == "Sidebar Rows")
        let mac = try Self.body("struct SettingsSidebarSection: View", in: "Cadence/macOS/Views/SettingsSectionViews.swift")
        #expect(mac.contains("SettingsSectionLabel(text: CadenceSidebarSettingsCopy.sectionTitle)"))
        let iOS = try Self.body("struct iOSSidebarLayoutSettingsSection: View", in: "Cadence/iOS/iOSSidebarLayoutSettingsSection.swift")
        #expect(iOS.contains("CadenceSettingsSectionLabel(text: CadenceSidebarSettingsCopy.sectionTitle)"))
        for (name, body) in [("Mac", mac), ("iOS", iOS)] {
            #expect(!body.contains("\"Main Sidebar Tabs\""), "\(name) types the old Mac eyebrow")
            #expect(!body.contains("\"Sidebar Rows\""), "\(name) types the eyebrow beside the shared one")
        }
    }

    // MARK: - Refresh-shaped buttons

    /// iOS's Refresh and Check iCloud Status drew `arrow.clockwise`; the Mac's drew bare words.
    @Test func everySettingsRefreshButtonDrawsTheSharedGlyph() throws {
        #expect(CadenceSettingsActionGlyph.refresh == "arrow.clockwise")
        let sites: [(path: String, needle: String)] = [
            ("Cadence/macOS/Views/SettingsRemindersSection.swift", #"Label("Refresh", systemImage: CadenceSettingsActionGlyph.refresh)"#),
            ("Cadence/macOS/Views/SettingsSyncSection.swift", #"Label("Check iCloud Status", systemImage: CadenceSettingsActionGlyph.refresh)"#),
            ("Cadence/iOS/iOSRemindersSettingsSection.swift", "title: \"Refresh\",\n                                systemImage: CadenceSettingsActionGlyph.refresh,"),
            ("Cadence/iOS/iOSSettingsOverviewSections.swift", "title: \"Check iCloud Status\",\n                            systemImage: CadenceSettingsActionGlyph.refresh,"),
        ]
        for site in sites {
            let source = try Self.code(site.path)
            #expect(source.contains(site.needle), "\(site.path) no longer reads the shared refresh glyph")
        }
        for path in ["Cadence/macOS/Views/SettingsRemindersSection.swift", "Cadence/macOS/Views/SettingsSyncSection.swift"] {
            let source = try Self.code(path)
            #expect(!source.contains(#"Text("Refresh")"#), "\(path) draws a bare Refresh again")
            #expect(!source.contains(#"Text("Check iCloud Status")"#), "\(path) draws a bare Check iCloud Status again")
            #expect(!source.contains("\"arrow.clockwise\""), "\(path) spells the glyph of its own")
        }
    }

    // MARK: - Allow Access on the Mac

    /// T-9955 kept iOS's access-button glyphs and gave the Mac's Open Settings one; the Mac's
    /// request buttons in Settings still drew bare words beside it. They wear the request glyph.
    @Test func everyMacSettingsRequestButtonWearsTheRequestGlyph() throws {
        let calendar = try Self.body("private var calendarAccessCard: some View", in: "Cadence/macOS/Views/SettingsListManagementSections.swift")
        #expect(calendar.contains("CadenceCalendarAccessNotice.connectOffer.actionTitle(on: .mac),\n                            systemImage: CadenceAccessButtonGlyph.requestAccess"))
        #expect(!calendar.contains(#"Text("Allow Access")"#), "Mac Settings > Calendar types its own bare Allow Access again")

        let reminders = try Self.body("private var accessCard: some View", in: "Cadence/macOS/Views/SettingsRemindersSection.swift")
        #expect(reminders.contains("Label(action.title, systemImage: CadenceAccessButtonGlyph.requestAccess)"))
        #expect(reminders.contains("Label(action.title, systemImage: CadenceAccessButtonGlyph.openSettings)"), "non-vacuity: the Open Settings half moved")
        #expect(!reminders.contains("Text(action.title)"), "Mac Settings > Reminders draws a bare Allow Access again")

        let notifications = try Self.body("private var notAuthorizedRow: some View", in: "Cadence/macOS/Views/SettingsNotificationsSection.swift")
        #expect(notifications.contains("CadenceNotificationSettingsCopy.enableNotificationsAction,\n                    systemImage: CadenceAccessButtonGlyph.requestAccess"))
        #expect(!notifications.contains("Text(CadenceNotificationSettingsCopy.enableNotificationsAction)"))
    }

    // MARK: - The Privacy card

    /// The Mac's Data Safety pane opens on a Privacy card the phone's Data Safety screen did not
    /// have. Both draw it now from one title, sentence and glyph, above the export card.
    @Test func bothDataSafetyScreensDrawTheOnePrivacyCard() throws {
        #expect(CadenceDataSafetyPrivacyCopy.title == "Privacy")
        #expect(CadenceDataSafetyPrivacyCopy.systemImage == "hand.raised.fill")
        #expect(CadenceDataSafetyPrivacyCopy.statement.hasPrefix("Cadence stores planning data locally"))

        let mac = try Self.body("private struct SettingsPrivacyStatementSection: View", in: "Cadence/macOS/Views/SettingsDataSafetySection.swift")
        let iOS = try Self.body("struct iOSPrivacyStatementSettingsSection: View", in: "Cadence/iOS/iOSSettingsOverviewSections.swift")
        for (name, card) in [("Mac", mac), ("iOS", iOS)] {
            #expect(card.contains("Text(CadenceDataSafetyPrivacyCopy.title)"), "\(name)'s card does not read the shared title")
            #expect(card.contains("Text(CadenceDataSafetyPrivacyCopy.statement)"), "\(name)'s card does not read the shared sentence")
            #expect(card.contains("CadenceDataSafetyPrivacyCopy.systemImage"), "\(name)'s card does not read the shared glyph")
            #expect(!card.contains("Cadence stores planning data"), "\(name)'s card types the sentence of its own")
            #expect(!card.contains("\"hand.raised.fill\""), "\(name)'s card spells the glyph of its own")
        }

        // Drawn on iOS's Data Safety screen, and above the export card, as on the Mac.
        let screen = try Self.body("private var dataSafetySection: some View", in: "Cadence/iOS/iOSSettingsView.swift")
        let card = try #require(screen.range(of: "iOSPrivacyStatementSettingsSection()"), "iOS Data Safety no longer draws the Privacy card")
        let export = try #require(screen.range(of: "iOSDataExportSettingsSection()"), "non-vacuity: the export card moved")
        #expect(card.lowerBound < export.lowerBound, "the Privacy card is no longer above the export card")
        #expect(CadenceSourceScan.matchCount("iOSPrivacyStatementSettingsSection\\(\\)", in: screen) == 1)
    }
}
