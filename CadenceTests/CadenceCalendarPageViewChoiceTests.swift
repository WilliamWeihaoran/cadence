import Foundation
import Testing
@testable import Cadence

/// **[[T-7074]]: iOS Settings split the Calendar toolbar's one three-way choice into two rows.**
///
/// The toolbar is one Week / Month / Board control writing two stored keys; Settings drew those
/// keys as "Calendar view: Week / Month" and "Calendar style: Timeline / Board", so with Board on
/// the page Settings read "Calendar view: Week". Owner decision 2026-11-02: one "Calendar view" row
/// offering Week / Month / Board, writing both keys the way the toolbar does.
@MainActor
struct CadenceCalendarPageViewChoiceTests {
    private static let settingsPath = "Cadence/iOS/iOSSettingsOverviewSections.swift"

    @Test func boardIsReadAsBoardWhateverTheStoredMode() {
        for mode in CadenceCalendarViewMode.allCases {
            #expect(CadenceCalendarPageView(presentation: .board, viewMode: mode) == .board,
                    "Board with a stored \(mode.rawValue) must not read as a timeline range")
        }
        #expect(CadenceCalendarPageView(presentation: .timeline, viewMode: .week) == .week)
        #expect(CadenceCalendarPageView(presentation: .timeline, viewMode: .month) == .month)
        #expect(CadenceCalendarPageView(presentation: .timeline, viewMode: .twoWeeks) == nil,
                "no picker offers 2 Weeks, so no choice claims it")
    }

    /// The toolbar's write: Week and Month set the timeline plus the mode; Board sets the
    /// presentation and keeps the mode, so leaving Board returns to the range the reader had.
    @Test func eachChoiceWritesBothKeysTheWayTheToolbarDoes() {
        var presentation = CadenceCalendarPresentation.timeline
        var viewMode = CadenceCalendarViewMode.month
        CadenceCalendarPageView.board.apply(presentation: &presentation, viewMode: &viewMode)
        #expect(presentation == .board)
        #expect(viewMode == .month)

        CadenceCalendarPageView.week.apply(presentation: &presentation, viewMode: &viewMode)
        #expect(presentation == .timeline)
        #expect(viewMode == .week)

        presentation = .board
        CadenceCalendarPageView.month.apply(presentation: &presentation, viewMode: &viewMode)
        #expect(presentation == .timeline)
        #expect(viewMode == .month)
    }

    @Test func everyChoiceReadsBackAsItselfFromEveryStartingState() {
        for start in CadenceCalendarPresentation.allCases {
            for startMode in CadenceCalendarViewMode.allCases {
                for choice in CadenceCalendarPageView.allCases {
                    var presentation = start
                    var viewMode = startMode
                    choice.apply(presentation: &presentation, viewMode: &viewMode)
                    #expect(CadenceCalendarPageView(presentation: presentation, viewMode: viewMode) == choice)
                }
            }
        }
    }

    @Test func theChoicesAreTheToolbarsThreeInItsOrder() {
        #expect(CadenceCalendarPageView.allCases.map(\.title) == ["Week", "Month", "Board"])
    }

    @Test func settingsDrawsOneCalendarRowOverTheSharedChoice() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.settingsPath))
        #expect(!source.contains("calendarStyleRow"), "the second row is gone")
        #expect(!source.contains("\"Calendar style\""))
        let row = try #require(CadenceSourceScan.declarationBody("private var calendarViewRow: some View", in: source))
            .filter { !$0.isWhitespace }
        #expect(row.contains("rows:CadenceCalendarPageView.allCases.map"))
        #expect(row.contains("selection:calendarViewSelection,"))
        let selection = try #require(CadenceSourceScan.declarationBody(
            "private var calendarViewSelection: Binding<CadenceCalendarPageView>", in: source))
            .filter { !$0.isWhitespace }
        #expect(selection.contains("choice.apply(presentation:&presentation,viewMode:&viewMode)"))
        #expect(selection.contains("calendarViewMode=viewMode"), "the row writes the stored mode")
        #expect(selection.contains("calendarPresentation=presentation"), "and the stored presentation")
    }
}
