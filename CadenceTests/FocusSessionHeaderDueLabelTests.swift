import Foundation
import Testing
@testable import Cadence

/// **Both Focus session headers say when the task is due, in one wording (T-7016).**
///
/// macOS's `FocusSessionHeader` drew "Due <relative date>" between priority and estimate; iOS's
/// `selectedTaskHeader` drew container, priority and estimate and never the deadline, so a task due
/// yesterday was focused on the iPad with no sign of it in the detail pane. Both now read
/// `CadenceFocusSupport.sessionHeaderDueLabel`.
struct FocusSessionHeaderDueLabelTests {
    private let reference = DateFormatters.date(from: "2026-08-09")!

    @Test func noDueDateDrawsNoChip() {
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "", relativeTo: reference) == nil)
    }

    @Test func aDueDateReadsDueAndTheRelativeDay() {
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-08-09", relativeTo: reference) == "Due Today")
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-08-10", relativeTo: reference) == "Due Tomorrow")
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-08-08", relativeTo: reference) == "Due Yesterday")
        // The words are `DateFormatters.relativeDate`'s, so the two cannot drift apart.
        #expect(
            CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-09-30", relativeTo: reference)
                == "Due \(DateFormatters.relativeDate(from: "2026-09-30", relativeTo: reference))"
        )
    }

    /// iOS's header is behind `#if os(iOS)`, so its wiring is read as source.
    @Test func theIOSHeaderDrawsTheDueChipBetweenPriorityAndEstimate() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let body = try #require(CadenceSourceScan.functionBody(named: "selectedTaskHeader", in: source))
        #expect(body.contains("task.priority.label"), "non-vacuity: still the session header")

        let due = try #require(
            body.range(of: "CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: task.dueDate)"),
            "iOS's Focus session header no longer draws the due-date chip"
        )
        let priority = try #require(body.range(of: "task.priority.label"))
        let estimate = try #require(body.range(of: "estimateLabel(for: task)"))
        #expect(priority.lowerBound < due.lowerBound && due.lowerBound < estimate.lowerBound,
                "the due chip left macOS's order: container, priority, due, estimate")
        #expect(body.contains("CadenceFocusSupport.isOverdue(dueDateKey: task.dueDate, todayKey: todayKey)"),
                "an overdue due chip is no longer tinted")
    }

    @Test func theMacHeaderReadsTheSameBuilder() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusChromeSupportViews.swift")
        )
        let header = try #require(CadenceSourceScan.declarationBody("struct FocusSessionHeader: View", in: source))
        #expect(header.contains("task.priority.label"), "non-vacuity: still the session header")
        #expect(header.contains("CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: task.dueDate)"))
        #expect(!header.contains("\"Due \\("), "macOS spells its own due wording again")
    }
}

/// **[[T-9652]].** The idle Mac Focus page's pick card draws a 2pt accent bar across its top. The
/// bar is a plain full-width `Rectangle` overlay, so without a clip its square ends stood out past
/// the card's 8pt rounded corners -- a blue tick at each top corner, brightest while the search
/// field is focused. The card now clips to its own shape after the bar, as `FocusTimerPanel` does.
struct CadenceFocusPickCardAccentClipTests {
    @Test func theAccentBarIsClippedToTheCardsCorners() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusPickerSupportViews.swift")
        let card = try #require(CadenceSourceScan.declarationBody("struct FocusPickSessionCard: View", in: source))
        let bodyEnd = try #require(card.range(of: "private var searchBar: some View"), "non-vacuity: the card's body moved")
        let body = String(card[..<bodyEnd.lowerBound]).filter { !$0.isWhitespace }
        let bar = try #require(body.range(of: ".overlay(alignment:.top){Rectangle().fill(Theme.blue.opacity(searchFieldFocused"),
                               "non-vacuity: the accent bar moved")
        #expect(body[bar.upperBound...].contains(".clipShape(RoundedRectangle(cornerRadius:8))"),
                "the accent bar's ends stand proud of the card's rounded corners")

        // The timer card is the precedent this follows: bar overlay, then the clip.
        let chrome = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusChromeSupportViews.swift")
        ).filter { !$0.isWhitespace }
        #expect(CadenceSourceScan.matchCount(#"\.frame\(height:2\)\}\.clipShape\(RoundedRectangle\("#, in: chrome) == 1,
                "non-vacuity: the timer card no longer clips its bar")
    }
}
