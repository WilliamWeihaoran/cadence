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

    // MARK: - The empty copy

    @Test func nothingThisMonthIsSaidOnlyWhenEventsCouldHaveBeenRead() {
        let readable = CadenceCalendarAccessNotice.monthAgendaEmptyCopy(notice: nil)
        #expect(readable.message == "Nothing this month")

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
}
