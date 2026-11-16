import Foundation
import Testing
@testable import Cadence

/// [[T-11199]]: a Mac/iOS parity pass on Settings under [[T-8201]]. Four small differences with no
/// hardware or input sentence, each now one shared value both platforms read. [[T-12622]] and
/// [[T-12623]] add two button-emphasis pins from a later drift hunt.
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

    // MARK: - Settings > AI's key buttons

    /// [[T-13772]]: iOS's Save API Key / Test Connection / Delete API Key drew `key.fill`, `network`
    /// and `trash`, typed inline; the Mac's drew bare words. Both now read the one name.
    @Test func bothAIKeyCardsDrawTheSharedButtonGlyphs() throws {
        #expect(CadenceAISettingsCopy.saveAPIKeyGlyph == "key.fill")
        #expect(CadenceAISettingsCopy.testConnectionGlyph == "network")
        #expect(CadenceAISettingsCopy.deleteAPIKeyGlyph == "trash")
        let mac = try Self.body("struct SettingsAISection: View", in: "Cadence/macOS/Views/SettingsSectionViews.swift")
        let iOS = try Self.body("struct iOSAISettingsSection: View", in: "Cadence/iOS/iOSSettingsTemplateAndListSections.swift")
        for (name, body) in [("Mac", mac), ("iOS", iOS)] {
            #expect(body.contains("CadenceAISettingsCopy.saveAPIKeyAction"), "non-vacuity: \(name) is not the AI key card")
            for glyph in ["saveAPIKeyGlyph", "testConnectionGlyph", "deleteAPIKeyGlyph"] {
                #expect(
                    body.components(separatedBy: "systemImage: CadenceAISettingsCopy.\(glyph)").count - 1 == 1,
                    "\(name) does not draw CadenceAISettingsCopy.\(glyph) exactly once"
                )
            }
            // `systemImage:` only: the card's disclosure row draws a `key.fill` icon of its own.
            for literal in ["\"key.fill\"", "\"network\"", "\"trash\""] {
                #expect(!body.contains("systemImage: \(literal)"), "\(name) spells \(literal) of its own")
            }
        }
    }

    // MARK: - Check iCloud Status's emphasis

    /// [[T-12622]]: iOS drew Check iCloud Status as a filled `.primary` plate while the Mac draws it
    /// tinted. A status probe is not the card's main act, and iOS `.primary` is the Mac's `.filled`
    /// ([[T-10020]]), so iOS takes `.secondary` -- the role its own Reminders Refresh already wears.
    @Test func checkICloudStatusIsTintedOnBothPlatforms() throws {
        let mac = try Self.code("Cadence/macOS/Views/SettingsSyncSection.swift")
        #expect(mac.contains("SettingsActionButton(tone: .tinted(Theme.blue), action: probe.refresh)"))
        let iOS = try Self.code("Cadence/iOS/iOSSettingsOverviewSections.swift")
        let button = try #require(iOS.range(of: "title: \"Check iCloud Status\","), "iOS Check iCloud Status is gone")
        let call = iOS[button.lowerBound...].prefix(240)
        #expect(call.contains("role: .secondary,"), "iOS Check iCloud Status is not the secondary role")
        #expect(!call.contains("role: .primary"), "iOS Check iCloud Status is a filled plate again")
    }

    // MARK: - New Context on the Mac

    /// [[T-12623]]: the Mac's New Context was a quiet `plus.circle` text row while iOS draws a filled
    /// blue `plus` button and Settings > Tags' Create Tag draws the same on both. The Mac adopts
    /// the Tags idiom and stays at the foot of the active-contexts card ([[T-12630]]).
    @Test func macNewContextWearsTheTagsCreateIdiom() throws {
        let path = "Cadence/macOS/Views/SettingsListManagementSections.swift"
        let source = try Self.code(path)
        #expect(source.contains("SettingsActionButton(tone: .filled(Theme.blue), action: onCreateContext) {\n                                Label(\"New Context\", systemImage: \"plus\")"))
        #expect(!source.contains("\"plus.circle\""), "\(path) draws the old plus.circle row again")
        #expect(!source.contains("Text(\"New Context\")"), "\(path) draws a bare New Context text row again")
        #expect(CadenceSourceScan.matchCount("onCreateContext\\)", in: source) == 1, "New Context is wired other than once")

        let tags = try Self.code("Cadence/macOS/Views/SettingsTagsSection.swift")
        #expect(tags.contains("SettingsActionButton(tone: .filled(Theme.blue), action: createTag) {\n                                    Label(\"Create Tag\", systemImage: \"plus\")"), "non-vacuity: the Tags idiom moved")
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

    // MARK: - hunt0201b: three Settings sentences that said something false

    /// [[T-17815]]: the Notifications switch said "Enable reminders" two rows from the Settings
    /// category "Reminders", which is Apple Reminders. It names what it governs, and the word
    /// that belongs to the other pane is gone from it.
    @Test func theNotificationsSwitchDoesNotBorrowTheRemindersPanesName() {
        let title = CadenceNotificationSettingsCopy.remindersToggleTitle
        #expect(title == "Task notifications")
        #expect(!title.localizedCaseInsensitiveContains("reminder"), "the switch says reminders again")
        #expect(!title.hasPrefix("Enable"), "the switch label is a verb again")
    }

    /// [[T-17816]]: the Mac row editor's Visible switch said "hide the tab" under the card this
    /// file's first test renamed to rows.
    @Test func theSidebarRowEditorSaysRowNotTab() throws {
        let detail = CadenceSidebarSettingsCopy.visibilityDetail
        #expect(detail.contains("the row"))
        #expect(!detail.localizedCaseInsensitiveContains("tab"), "the detail says tab again")
        let sheet = try Self.body("struct SidebarTabEditorSheet: View", in: "Cadence/macOS/Views/SettingsSupportViews.swift")
        #expect(sheet.contains("detail: CadenceSidebarSettingsCopy.visibilityDetail"), "the sheet no longer reads the shared detail")
        #expect(!sheet.contains("hide the tab"), "the sheet types its own detail beside the shared one")
    }

    /// [[T-17817]]: the Mac's Other Backup Folders sentence said "nothing on this screen removes
    /// them" and, two clauses later, that deleting all data deletes them -- on the screen holding
    /// that button. It names the button, and claims only that nothing ELSE here removes them.
    @Test func theMacBackupFoldersSentenceDoesNotContradictTheResetBesideIt() throws {
        let detail = CadenceUnmanagedStoreCopy.macBackupFoldersDetail
        #expect(detail.contains("so \(CadenceDataResetCopy.title) deletes them"), "the sentence no longer names the reset that deletes them")
        #expect(!detail.contains("nothing on this screen removes them"), "the sentence denies the reset beside it again")
        #expect(detail.contains("nothing else on this screen removes them"))
        let pane = try Self.code("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        #expect(pane.contains("Text(CadenceUnmanagedStoreCopy.macBackupFoldersDetail)"), "the pane no longer reads the shared sentence")
        #expect(!pane.contains("Earlier versions of Cadence kept"), "the pane types its own sentence beside the shared one")
    }

    // MARK: - Delete API Key asks first

    /// [[T-18102]]: both Delete API Key buttons removed the Keychain item on one click. Each now
    /// only raises a confirmation, and `removeAPIKey` is reached from that dialog's destructive
    /// button alone. Sliced so the claim is about the button and the dialog, not the whole file.
    @Test func bothDeleteAPIKeyButtonsAskBeforeRemovingTheKey() throws {
        let surfaces = [
            ("Cadence/macOS/Views/SettingsSectionViews.swift", "struct SettingsAISection: View"),
            ("Cadence/iOS/iOSSettingsTemplateAndListSections.swift", "struct iOSAISettingsSection: View"),
        ]
        for (path, declaration) in surfaces {
            let body = try Self.body(declaration, in: path)
            let button = try #require(body.range(of: "title: CadenceAISettingsCopy.deleteAPIKeyAction"), "\(path): the Delete API Key button is gone")
            let dialog = try #require(body.range(of: ".confirmationDialog("), "\(path): the Delete API Key confirmation is gone")
            #expect(button.upperBound < dialog.lowerBound, "\(path): the dialog no longer follows the button")
            let buttonToDialog = String(body[button.upperBound..<dialog.lowerBound])
            #expect(!buttonToDialog.contains("removeAPIKey"), "\(path): the button removes the key itself again")
            #expect(buttonToDialog.contains("isConfirmingAPIKeyDeletion = true"), "\(path): the button no longer raises the confirmation")
            let dialogTail = String(body[dialog.lowerBound...])
            let message = try #require(dialogTail.range(of: "} message: {"), "\(path): the dialog has no message")
            let actions = String(dialogTail[..<message.lowerBound])
            #expect(actions.contains("CadenceAISettingsCopy.deleteAPIKeyConfirmationTitle"))
            #expect(actions.contains("isPresented: $isConfirmingAPIKeyDeletion"))
            #expect(actions.contains("Button(CadenceAISettingsCopy.deleteAPIKeyAction, role: .destructive"))
            #expect(actions.contains("removeAPIKey"), "\(path): confirming no longer removes the key")
            #expect(actions.contains("role: .cancel"), "\(path): the dialog has no Cancel")
            #expect(dialogTail[message.upperBound...].contains("Text(CadenceAISettingsCopy.deleteAPIKeyConfirmationMessage)"))
        }
        #expect(CadenceAISettingsCopy.deleteAPIKeyConfirmationTitle == "Delete API Key?")
        #expect(CadenceAISettingsCopy.deleteAPIKeyConfirmationMessage.contains("OpenAI API key"), "the message no longer names the key")
        #expect(CadenceAISettingsCopy.deleteAPIKeyConfirmationMessage.contains("paste the key again"), "the message no longer says what it costs")
    }
}
