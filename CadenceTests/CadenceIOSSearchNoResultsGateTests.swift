import Foundation
import Testing

@testable import Cadence

/// iOS Search's "No results" panel and the calendar-access card (T-6113).
///
/// A source reading, because `iOSSearchView` is compiled only for iOS and this suite runs on the
/// macOS host. The defect was a gate keyed on `showsEvents`, which is true on the default **All**
/// scope as well as on **Events**: with Calendar access off, an All search that matched nothing
/// drew only the "Calendar access is off" card and never said "No results".
struct CadenceIOSSearchNoResultsGateTests {
    private func searchViewCode() throws -> String {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        let code = CadenceSourceScan.codeOnly(raw)
        #expect(code != raw, "non-vacuity: comments were not stripped")
        return code
    }

    /// Only the Events scope lets the access card stand in for "No results".
    @Test func theAccessCardReplacesNoResultsOnTheEventsScopeAlone() throws {
        let code = try searchViewCode()
        let body = try #require(
            CadenceSourceScan.declarationBody("private var calendarAccessCardReplacesNoResults: Bool", in: code),
            "could not read iOSSearchView.calendarAccessCardReplacesNoResults"
        )
        #expect(body.contains("scope == .events"))
        #expect(body.contains("!calendarManager.isAuthorized"))
        #expect(!body.contains("showsEvents"), "showsEvents is true on All too, which is the defect")
        #expect(!body.contains(".all"))
    }

    /// The panel's own gate reads that property, and no longer spells the old exception.
    @Test func theNoResultsPanelIsGatedOnTheEventsOnlyException() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSearchView.swift")
        #expect(raw.contains(#"title: "No results""#), "non-vacuity: the panel moved")
        let code = try searchViewCode()
        #expect(CadenceSourceScan.matchCount(
            #"if isSearching && visibleResultsAreEmpty && !calendarAccessCardReplacesNoResults \{"#,
            in: code
        ) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"showsEvents && !calendarManager\.isAuthorized"#,
            in: code
        ) == 0)
    }
}
