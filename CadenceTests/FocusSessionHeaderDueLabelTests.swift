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
    private let today = "2026-08-09"

    @Test func noDueDateDrawsNoChip() {
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "", todayKey: today) == nil)
    }

    /// [[T-15491]]: the header speaks the one due-date vocabulary, `dueLabel`'s, not "Due " +
    /// `DateFormatters.relativeDate` ("Due Today" / "Due Yesterday").
    @Test func aDueDateReadsTheOneDueDateVocabulary() {
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-08-09", todayKey: today) == "Due today")
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-08-10", todayKey: today) == "Due tomorrow")
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-08-08", todayKey: today) == "Overdue Aug 8")
        #expect(
            CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2026-09-30", todayKey: today)
                == CadenceFocusSupport.dueLabel(forDueDateKey: "2026-09-30", todayKey: today)
        )
    }

    /// **[[T-14353]].** The words follow the observed day handed in, never the clock: a session
    /// running across midnight turns "Due today" into "Overdue Mar 4" when the page's day turns.
    @Test func theWordsFollowTheObservedDayNotTheClock() {
        let clockToday = DateFormatters.todayKey()
        #expect(clockToday != "2001-03-04", "non-vacuity: the clock must not be on the observed day")
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2001-03-04", todayKey: "2001-03-04") == "Due today")
        #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: "2001-03-04", todayKey: "2001-03-05") == "Overdue Mar 4")
    }

    /// iOS's header is behind `#if os(iOS)`, so its wiring is read as source.
    @Test func theIOSHeaderDrawsTheDueChipBetweenPriorityAndEstimate() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let body = try #require(CadenceSourceScan.functionBody(named: "selectedTaskHeader", in: source))
        #expect(body.contains("task.priority.label"), "non-vacuity: still the session header")

        let due = try #require(
            body.range(of: "CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: task.dueDate, todayKey: todayKey)"),
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
        #expect(header.contains("CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: task.dueDate, todayKey: todayKey)"))
        // [[T-14353]]: the overdue tint reads the same observed day as the words, never the clock.
        #expect(header.contains("CadenceFocusSupport.isOverdue(dueDateKey: task.dueDate, todayKey: todayKey)"))
        #expect(!header.contains("DateFormatters.todayKey()"), "the Mac header reads the clock again")
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

/// **[[T-11211]] (b): both Focus session headers say the task repeats, at every width.** The fact
/// used to be only in the Mac's width-gated sidebar Session block; iOS Focus never said it. One
/// helper decides whether it draws, and each header draws it in its own vocabulary.
struct FocusSessionHeaderRecurrenceTests {
    @Test func aTaskThatDoesNotRepeatDrawsNothing() {
        #expect(CadenceFocusSupport.sessionHeaderRecurrence(for: .none) == nil)
    }

    @Test func aRepeatingTaskYieldsItsRuleAndTheRepeatGlyph() {
        let repeating = TaskRecurrenceRule.allCases.filter { $0 != .none }
        #expect(repeating.count == 4, "non-vacuity: the repeating rules changed")
        for rule in repeating {
            #expect(
                CadenceFocusSupport.sessionHeaderRecurrence(for: rule)
                    == CadenceFocusRecurrenceFact(label: rule.label, systemImage: TaskRecurrenceRule.repeatSymbol)
            )
        }
        #expect(CadenceFocusSupport.sessionHeaderRecurrence(for: .weekly)?.label == "Weekly")
    }

    @Test func bothHeadersReadTheOneHelper() throws {
        let call = "CadenceFocusSupport.sessionHeaderRecurrence(for: task.recurrenceRule)"
        let ios = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift"))
        let iosBody = try #require(CadenceSourceScan.functionBody(named: "selectedTaskHeader", in: ios))
        #expect(iosBody.contains("task.priority.label"), "non-vacuity: still the session header")
        #expect(iosBody.contains(call), "iOS's Focus session header no longer says the task repeats")
        #expect(iosBody.contains("systemImage: recurrence.systemImage"), "the iOS chip lost the repeat glyph")

        let mac = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusChromeSupportViews.swift")
        )
        let header = try #require(CadenceSourceScan.declarationBody("struct FocusSessionHeader: View", in: mac))
        #expect(header.contains("task.priority.label"), "non-vacuity: still the session header")
        #expect(header.contains(call), "the Mac's Focus session header no longer says the task repeats")
        #expect(!header.contains("isRecurring"), "the Mac header decides recurrence on its own again")
        #expect(!iosBody.contains("isRecurring"), "the iOS header decides recurrence on its own again")
    }
}
