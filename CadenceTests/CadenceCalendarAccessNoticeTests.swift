import Foundation
import Testing
@testable import Cadence

/// [[T-5954]]: the Calendar page's notice when Apple Calendar cannot be read, and the empty copy
/// that must not claim the month is empty while it is up.
///
/// Authorization is an input here. Nothing in this suite reads EventKit's status, requests access,
/// or opens an `EKEventStore`.
struct CadenceCalendarAccessNoticeTests {

    // MARK: - The gate

    @Test func authorizedDrawsNoNoticeWhateverTheDeniedFlagSays() {
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: true, isDenied: false) == nil)
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: true, isDenied: true) == nil)
    }

    @Test func notYetAskedIsAnOfferAndDeniedIsAFault() {
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: false, isDenied: false) == .connectOffer)
        #expect(CadenceCalendarAccessNotice.resolve(isAuthorized: false, isDenied: true) == .denied)
    }

    @Test func fixtureEventsStandInForAccess() {
        #expect(
            CadenceCalendarAccessNotice.resolve(isAuthorized: false, isDenied: false, showsFixtureEvents: true) == nil
        )
        #expect(
            CadenceCalendarAccessNotice.resolve(isAuthorized: false, isDenied: true, showsFixtureEvents: true) == nil
        )
    }

    // MARK: - Words and actions

    @Test func titlesAreTheSettingsCardsOwn() {
        #expect(CadenceCalendarAccessNotice.connectOffer.title == CadenceCalendarSettingsCopy.connectOfferTitle)
        #expect(CadenceCalendarAccessNotice.denied.title == CadenceCalendarSettingsCopy.accessDeniedTitle)
        #expect(CadenceCalendarAccessNotice.connectOffer.title == "Connect Apple Calendar")
        #expect(CadenceCalendarAccessNotice.denied.title == "Calendar access denied")
    }

    @Test func onlyTheOfferRequestsAccessBecauseNeitherPlatformRePrompts() {
        #expect(CadenceCalendarAccessNotice.connectOffer.action == .requestAccess)
        #expect(CadenceCalendarAccessNotice.denied.action == .openSystemSettings)
        #expect(CadenceCalendarAccessNotice.connectOffer.actionTitle(on: .mac) == "Allow Access")
        #expect(CadenceCalendarAccessNotice.connectOffer.actionTitle(on: .mobile) == "Allow Access")
        #expect(CadenceCalendarAccessNotice.denied.actionTitle(on: .mac) == "Open Calendar Settings")
        #expect(CadenceCalendarAccessNotice.denied.actionTitle(on: .mobile) == "Open Settings")
    }

    @Test func theDeniedSentenceNamesEachPlatformsOwnSettings() {
        let mac = CadenceCalendarAccessNotice.denied.detail(on: .mac)
        let mobile = CadenceCalendarAccessNotice.denied.detail(on: .mobile)
        #expect(mac.contains("System Settings"))
        #expect(mobile.contains("iOS Settings"))
        #expect(mac != mobile)
        #expect(CadenceCalendarAccessNotice.connectOffer.detail(on: .mac) == CadenceCalendarSettingsCopy.accessRequiredDetail)
        #expect(CadenceCalendarAccessNotice.connectOffer.detail(on: .mobile) == CadenceCalendarSettingsCopy.accessRequiredDetail)
    }

    /// [[T-9572]]: the missing-access write failure and both Settings cards say the denied sentence
    /// from this one source, per platform. The alert used to say "Grant Calendar access in
    /// Settings → Calendar", which on iOS reads as the system app's Calendar pane.
    @Test func theMissingAccessWriteFailureAndBothSettingsCardsReadTheOneDeniedSentence() throws {
        for platform in [CadenceCalendarAccessNotice.Platform.mac, .mobile] {
            let message = CalendarWriteFailure.notAuthorized.message(on: platform)
            #expect(message.hasSuffix(CadenceCalendarAccessNotice.denied.detail(on: platform)))
            #expect(!message.contains("Settings → Calendar"), "the alert names Settings → Calendar again on \(platform)")
        }
        #expect(
            CalendarWriteFailure.notAuthorized.message(on: .mac)
                != CalendarWriteFailure.notAuthorized.message(on: .mobile)
        )
        // The build's own message is its platform's.
        #expect(
            CalendarWriteFailure.notAuthorized.message
                == CalendarWriteFailure.notAuthorized.message(on: .current)
        )
        // The other causes are one sentence on both platforms.
        for cause in [CalendarWriteFailure.noWritableCalendar, .invalidRange, .eventNotFound, .saveFailed("x")] {
            #expect(cause.message(on: .mac) == cause.message(on: .mobile))
        }

        // Neither Settings card types the denied sentence beside the source it now reads.
        let cards: [(path: String, platform: CadenceCalendarAccessNotice.Platform, call: String)] = [
            ("Cadence/macOS/Views/SettingsListManagementSections.swift", .mac, "CadenceCalendarAccessNotice.denied.detail(on: .mac)"),
            ("Cadence/iOS/iOSCalendarSettingsSection.swift", .mobile, "CadenceCalendarAccessNotice.denied.detail(on: .mobile)"),
        ]
        for card in cards {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(card.path))
            #expect(code.contains(card.call), "\(card.path) no longer reads the denied sentence from the notice")
            #expect(
                !code.contains("\"\(CadenceCalendarAccessNotice.denied.detail(on: card.platform))\""),
                "\(card.path) types the denied sentence again"
            )
        }
    }

    // MARK: - The empty copy

    @Test func nothingThisMonthIsSaidOnlyWhenEventsCouldHaveBeenRead() {
        let readable = CadenceCalendarAccessNotice.monthAgendaEmptyCopy(notice: nil)
        #expect(readable.message == "Nothing this month")
        // T-9203: Blocks are gone ([[T-3170]]), so the empty month promises only what it can draw.
        #expect(readable.subtitle == "Days with events or tasks show up here.")
        #expect(!readable.subtitle.localizedCaseInsensitiveContains("block"))

        for notice in [CadenceCalendarAccessNotice.connectOffer, .denied] {
            let copy = CadenceCalendarAccessNotice.monthAgendaEmptyCopy(notice: notice)
            #expect(copy.message != "Nothing this month")
            #expect(!copy.message.hasPrefix("Nothing"))
            #expect(copy.subtitle == CadenceCalendarAccessNotice.notConnectedSentence)
            #expect(copy.subtitle.contains("not connected"))
        }
    }

    @Test func aDayIsNothingScheduledOnlyWhenEventsCouldHaveBeenRead() {
        #expect(CadenceCalendarAccessNotice.dayEmptyText(notice: nil) == CadenceEmptyStateCopy.nothingScheduledTitle)
        #expect(CadenceCalendarAccessNotice.dayEmptyText(notice: .connectOffer) != CadenceEmptyStateCopy.nothingScheduledTitle)
        #expect(CadenceCalendarAccessNotice.dayEmptyText(notice: .denied) != CadenceEmptyStateCopy.nothingScheduledTitle)
    }

    // MARK: - Wiring (the iOS half does not compile in this target, so it is read as source)

    @Test func bothCalendarPagesDrawTheNoticeFromTheGate() throws {
        let mac = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageView.swift"))
        let iOS = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarView.swift"))
        for (name, source) in [("macOS", mac), ("iOS", iOS)] {
            #expect(source.contains("CadenceCalendarAccessNotice.resolve("), "\(name) Calendar page does not ask the gate")
            #expect(source.contains("if let accessNotice {"), "\(name) Calendar page does not draw the notice")
            #expect(source.contains("isAuthorized: calendarManager.isAuthorized"), "\(name) gate is not fed the manager")
        }
        #expect(mac.contains("CalendarPageAccessNoticeStrip(notice: accessNotice"))
        #expect(iOS.contains("iOSCalendarAccessNoticeBar(notice: accessNotice"))
        // The three empty states read the gate's copy, not a literal of their own.
        #expect(iOS.contains("accessNotice: accessNotice"))
        #expect(iOS.components(separatedBy: "CadenceCalendarAccessNotice.dayEmptyText(notice: accessNotice)").count - 1 == 2)
    }

    @Test func theMonthAgendaNoLongerSpellsItsOwnEmptyCopy() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift")
        let agenda = CadenceSourceScan.codeOnly(raw)
        #expect(agenda.contains("EmptyStateView("), "non-vacuity: the agenda's empty state moved")
        #expect(agenda.contains("CadenceCalendarAccessNotice.monthAgendaEmptyCopy(notice: accessNotice)"))
        // `codeOnly` blanks literals, so the literal check reads comment-stripped source instead,
        // anchored on a literal that is still there.
        let withLiterals = CadenceSourceScan.strippingComments(raw)
        #expect(withLiterals.contains("icon: \"calendar\""), "non-vacuity: literals survive this read")
        #expect(!withLiterals.contains("\"Nothing this month\""))
    }

    // MARK: - [[T-9953]] One glyph per access action on every iOS card

    @Test func eachAccessActionHasOneMobileButtonGlyphAndItIsNotTheTiles() {
        #expect(CadenceAccessButtonGlyph.requestAccess == "checkmark.circle.fill")
        #expect(CadenceAccessButtonGlyph.openSettings == "gearshape.fill")
        #expect(CadenceCalendarAccessNotice.connectOffer.mobileButtonSystemImage == CadenceAccessButtonGlyph.requestAccess)
        #expect(CadenceCalendarAccessNotice.denied.mobileButtonSystemImage == CadenceAccessButtonGlyph.openSettings)
        // The capture card put the tile's own glyph on its Allow Access button.
        #expect(CadenceCalendarAccessNotice.connectOffer.mobileButtonSystemImage != CadenceCalendarAccessNotice.connectOffer.systemImage)
    }

    /// The six iOS access buttons read the one pair. Read as source: none of these files compiles
    /// in this target.
    @Test func everyIOSAccessButtonReadsTheOneGlyphPair() throws {
        let needles: [(file: String, reads: [String])] = [
            ("Cadence/iOS/iOSRemindersSettingsSection.swift", [
                "title: action.title(on: .mobile)",
                "systemImage: action.mobileButtonSystemImage",
                "tint: action == .openSystemSettings ? Theme.amber : Theme.blue"
            ]),
            ("Cadence/iOS/iOSInboxRemindersSection.swift", [
                "title: action.title(on: .mobile)",
                "systemImage: action.mobileButtonSystemImage",
                "tint: action == .openSystemSettings ? Theme.amber : Theme.blue"
            ]),
            ("Cadence/iOS/iOSCalendarSettingsSection.swift", [
                "systemImage: calendarManager.isDenied ? CadenceAccessButtonGlyph.openSettings : CadenceAccessButtonGlyph.requestAccess"
            ]),
            ("Cadence/iOS/iOSSearchView.swift", ["systemImage: notice.mobileButtonSystemImage"]),
            ("Cadence/iOS/iOSCalendarQuickCreateSheet.swift", ["systemImage: notice.mobileButtonSystemImage"]),
            ("Cadence/iOS/iOSNotificationsSettingsSection.swift", ["systemImage: CadenceAccessButtonGlyph.requestAccess"])
        ]
        for (file, reads) in needles {
            let raw = try CadenceSourceScan.sourceFile(file)
            let source = CadenceSourceScan.strippingComments(raw)
            #expect(source.contains("iOSActionButton("), "non-vacuity: \(file) draws no action button")
            for needle in reads {
                #expect(source.contains(needle), "\(file) no longer reads `\(needle)`")
            }
            for retired in ["\"gear\"", "\"gearshape.fill\"", "\"checkmark.shield.fill\""] {
                #expect(!source.contains(retired), "\(file) spells an access glyph of its own again: \(retired)")
            }
        }
    }
}
