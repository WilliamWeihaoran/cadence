import Foundation
import Testing
@testable import Cadence

/// **T-9211: a date panel opened on a field with no date lit today as if it were picked.**
///
/// Every caller seeds the panel's `selection` with today when the field is empty, and the pills and
/// the grid read that seed as the selection. "Set due date" on an undated task opened with the
/// Today pill and today's cell filled blue and "Clear date" under them. The panels now take
/// `hasSelection`, and the rule they draw from is `CadenceDateSelectionState`.
@MainActor
struct CadenceDateSelectionStateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ key: String) throws -> Date {
        var components = DateComponents()
        let parts = key.split(separator: "-").compactMap { Int($0) }
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return try #require(calendar.date(from: components))
    }

    @Test func aDateIsPickedOnlyWhenTheFieldHasOne() throws {
        let seed = try day("2026-10-31")
        #expect(CadenceDateSelectionState.isSelected(seed, selection: seed, hasSelection: true, calendar: calendar))
        #expect(!CadenceDateSelectionState.isSelected(seed, selection: seed, hasSelection: false, calendar: calendar))
        // Another day is never picked, with or without a value.
        let other = try day("2026-11-01")
        #expect(!CadenceDateSelectionState.isSelected(other, selection: seed, hasSelection: true, calendar: calendar))
        #expect(!CadenceDateSelectionState.isSelected(other, selection: seed, hasSelection: false, calendar: calendar))
    }

    @Test func clearIsOfferedOnlyOverADate() {
        #expect(CadenceDateSelectionState.drawsClear(showsClear: true, hasSelection: true))
        #expect(!CadenceDateSelectionState.drawsClear(showsClear: true, hasSelection: false))
        #expect(!CadenceDateSelectionState.drawsClear(showsClear: false, hasSelection: true))
    }

    /// The panels draw from the rule, and the callers that open on an undated field say so. These
    /// are SwiftUI bodies, so the wiring is pinned as comment-stripped source text.
    @Test func thePanelsAndTheUndatedCallersPassTheValueThrough() throws {
        let picker = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceDatePicker.swift")
        )
        // The grid cell, the accessibility row and the quick pill all ask the rule.
        #expect(picker.components(separatedBy: "CadenceDateSelectionState.isSelected(").count - 1 == 3)
        #expect(!picker.contains("cal.isDate(d, inSameDayAs: selection)"))
        #expect(!picker.contains("cal.isDate(day, inSameDayAs: selection)"))
        #expect(!picker.contains("cal.isDate(selection, inSameDayAs: target)"))
        #expect(picker.contains("CadenceDateSelectionState.drawsClear(showsClear: showsClear, hasSelection: hasSelection)"))
        // The quick popover forwards to its grid; the field forwards its placeholder state.
        #expect(picker.components(separatedBy: "hasSelection: hasSelection\n").count - 1 == 1)
        #expect(picker.contains("hasSelection: placeholder == nil"))

        let callers: [(String, [String])] = [
            ("Cadence/macOS/Views/TasksPanelComponents.swift", ["hasSelection: !task.dueDate.isEmpty", "hasSelection: !task.scheduledDate.isEmpty"]),
            ("Cadence/macOS/Views/KanbanCardView.swift", ["hasSelection: !task.dueDate.isEmpty", "hasSelection: !task.scheduledDate.isEmpty"]),
            ("Cadence/macOS/Views/TaskEmbedFieldEditorPopover.swift", ["hasSelection: !task.dueDate.isEmpty", "hasSelection: !task.scheduledDate.isEmpty"]),
            ("Cadence/macOS/Views/KanbanColumnSupportViews.swift", ["hasSelection: !dueDateKey.isEmpty"]),
            ("Cadence/macOS/Views/TaskInspectorFieldSupportViews.swift", ["hasSelection: isOn"]),
            ("Cadence/macOS/Sheets/CreateTaskSheetSupportViews.swift", ["hasSelection: isOn"]),
            ("Cadence/Shared/Components/CadenceSchedulePanel.swift", ["hasSelection: !draft.dueDateKey.isEmpty", "hasSelection: draft.hasDoDate"]),
            ("Cadence/iOS/iOSTaskRowActionViews.swift", ["hasSelection: !dateKey.isEmpty"]),
        ]
        for (path, needles) in callers {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            for needle in needles {
                #expect(source.contains(needle), "\(path) lost `\(needle)`")
            }
        }
    }

    /// **[[T-16431]]: the schedule panel's Do and Due grids opened on today's month, with an
    /// undated task's Do grid drawing today as picked.**
    ///
    /// The panel is the task editor on both platforms (the Mac inspector, the iOS detail sheet, the
    /// inline panel). Its two grid months were `@State` seeded with today and never moved, so a task
    /// done in March opened its Do grid on November with the picked day off-screen; and the Do grid
    /// was the one T-9211 caller left on the default `hasSelection: true`, so "No date" sat over a
    /// filled Today pill and a filled today cell.
    @Test func theSchedulePanelGridsOpenOnTheirOwnDatesMonth() throws {
        let now = try #require(DateFormatters.date(from: "2026-11-11"))
        var draft = CadenceScheduleDraft(dateKey: "2027-03-17", startMin: 9 * 60, kind: .task)
        draft.dueDateKey = "2026-08-04"
        #expect(draft.hasDoDate)
        #expect(DateFormatters.dateKey(from: draft.gridMonth(for: .doDate, now: now)) == "2027-03-01")
        #expect(DateFormatters.dateKey(from: draft.gridMonth(for: .dueDate, now: now)) == "2026-08-01")

        // Unset rows open on the month of `now`, and an undated Do grid has nothing picked.
        draft.clearDoDate()
        draft.dueDateKey = ""
        #expect(!draft.hasDoDate)
        #expect(DateFormatters.dateKey(from: draft.gridMonth(for: .doDate, now: now)) == "2026-11-01")
        #expect(DateFormatters.dateKey(from: draft.gridMonth(for: .dueDate, now: now)) == "2026-11-01")

        // The panel asks for both months on the way open -- a tap and `expanding(_:)` -- and both
        // rows open through the re-anchoring binding, not the bare `@State`.
        let panel = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        )
        #expect(panel.contains("doViewMonth = draft.gridMonth(for: .doDate)"))
        #expect(panel.contains("dueViewMonth = draft.gridMonth(for: .dueDate)"))
        #expect(panel.contains("panel._doViewMonth = State(initialValue: panel.draft.gridMonth(for: .doDate))"))
        #expect(panel.contains("panel._dueViewMonth = State(initialValue: panel.draft.gridMonth(for: .dueDate))"))
        #expect(panel.contains("isExpanded: gridExpansion(.doDate)"))
        #expect(panel.contains("isExpanded: gridExpansion(.dueDate)"))
        #expect(!panel.contains("isExpanded: $isDoExpanded"))
        #expect(!panel.contains("isExpanded: $isDueExpanded"))
    }

    /// **[[T-10012]]: picking today made the panel's today marker vanish.**
    ///
    /// `CadenceCalendarDayBadge` names `MonthCalendarPanel` as the source of its colours and says a
    /// picked today keeps a ring; both iOS month grids draw it, and the panel behind every date field
    /// did not, so a task due today opened its picker on a plain solid circle. The ring takes the
    /// cell's edge and only a picked today steps its fill in to make room.
    @Test func aPickedTodayKeepsItsRingInsideTheCell() throws {
        #expect(MonthCalendarPanel.fillInset(for: .todayAndSelected) == CadenceDateSelectionMetrics.todayRingWidth + CadenceDateSelectionMetrics.todayRingGap)
        #expect(MonthCalendarPanel.fillInset(for: .todayAndSelected) > 0)
        for badge in CadenceCalendarDayBadge.allCases where badge != .todayAndSelected {
            #expect(MonthCalendarPanel.fillInset(for: badge) == 0, "\(badge) stepped its fill in")
        }

        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceDatePicker.swift")
        )
        let panel = try #require(
            CadenceSourceScan.declarationBody("struct MonthCalendarPanel: View", in: source),
            "MonthCalendarPanel is gone"
        )
        // Non-vacuity: the grid branch is in the body this reads.
        #expect(panel.contains("LazyVGrid("))
        #expect(panel.contains("CadenceCalendarDayBadge.style(isToday: isToday, isSelected: isSelected)"))
        #expect(panel.contains(".padding(Self.fillInset(for: badge))"))
        #expect(
            CadenceSourceScan.matchCount(
                "if badge\\.showsTodayRing \\{\\s*Circle\\(\\)\\s*\\.strokeBorder\\(Theme\\.blue, lineWidth: CadenceDateSelectionMetrics\\.todayRingWidth\\)",
                in: panel
            ) == 1,
            "the grid no longer draws the today ring on a picked today"
        )
    }
}
