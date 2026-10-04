import Foundation
import Testing
@testable import Cadence

@MainActor
struct CadenceCodexWidgetFollowupTests {
    @Test func codexWidgetFamilyBudgetsMatchTheSelectedContent() {
        let families = CadenceWidgetFamilyLayout.allCases
        #expect(families.map(\.todayTaskLimit) == [1, 3, 2, 8])
        #expect(families.map(\.habitLimit) == [2, 3, 8, 8])
        #expect(families.map(\.habitColumns) == [2, 3, 3, 3])
        #expect(families.map(\.calendarDayLimit) == [3, 6, 14, 14])
        #expect(families.map(\.milestoneGoalLimit) == [1, 3, 5, 5])
        for family in families.prefix(2) {
            #expect(family.habitLimit <= family.habitColumns, "small/medium must stay one row")
        }
        #expect((CadenceWidgetFamilyLayout.large.habitLimit + 2) / 3 == 3)
    }

    @Test(arguments: [true, false])
    func codexHabitOverrideExpiresAtMidnightBeforeItsTTL(isDone: Bool) throws {
        try withTemporaryDefaults("cadence.codex.widget.followups") { defaults in
            let day = try #require(DateFormatters.date(from: "2026-10-04"))
            let before = try #require(Calendar.current.date(bySettingHour: 23, minute: 59, second: 45, of: day))
            let id = UUID()
            CadenceWidgetRefreshCenter.markHabitCompletion(id, isDoneToday: isDone, now: before, userDefaults: defaults)
            let sameDay = CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before.addingTimeInterval(10), userDefaults: defaults)
            #expect(sameDay[id] == isDone)
            let afterMidnight = CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before.addingTimeInterval(30), userDefaults: defaults)
            #expect(afterMidnight[id] == nil)
            #expect(defaults.dictionary(forKey: "cadence.widgets.habits.recentlyChangedHabits") == nil)
        }
    }

    @Test func codexHabitOverrideStillHonorsTTLAndSnapshotDate() throws {
        try withTemporaryDefaults("cadence.codex.widget.followups") { defaults in
            let now = try #require(DateFormatters.date(from: "2026-10-04"))
            let id = UUID()
            CadenceWidgetRefreshCenter.markHabitCompletion(id, isDoneToday: true, now: now, userDefaults: defaults)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now.addingTimeInterval(90), userDefaults: defaults)[id] == true)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now.addingTimeInterval(91), userDefaults: defaults)[id] == nil)
            CadenceWidgetRefreshCenter.markHabitCompletion(id, isDoneToday: false, now: now, userDefaults: defaults)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: now, dateKey: "2026-10-05", userDefaults: defaults)[id] == nil)
        }
    }

    @Test func codexLegacyHabitOverridesAreDatedFromTheirTimestamp() throws {
        try withTemporaryDefaults("cadence.codex.widget.followups") { defaults in
            let day = try #require(DateFormatters.date(from: "2026-10-04"))
            let before = try #require(Calendar.current.date(bySettingHour: 23, minute: 59, second: 45, of: day))
            let id = UUID()
            let payload: [String: Any] = ["timestamp": before.timeIntervalSince1970, "isDoneToday": true]
            defaults.set([id.uuidString: payload], forKey: "cadence.widgets.habits.recentlyChangedHabits")
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before, userDefaults: defaults)[id] == true)
            #expect(CadenceWidgetRefreshCenter.recentHabitCompletionStates(now: before.addingTimeInterval(30), userDefaults: defaults)[id] == nil)
        }
    }

    @Test func codexCalendarReadyContentHasItsDatedBackgroundRoute() throws {
        let route = try CadenceScanInstrument(
            "calendar widget background route",
            fires: "content.widgetURL(entry.snapshot.calendarURL)",
            andNotOn: "// .widgetURL(entry.snapshot.calendarURL)\ncontent.widgetURL(otherURL)",
            by: { CadenceSourceScan.codeOnly($0).contains(".widgetURL(entry.snapshot.calendarURL)") }
        )
        let paths = ["CadenceWidgets/CalendarSnapshotWidget.swift"]
        #expect(try route.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
    }

    @Test func codexWidgetProvidersAndViewsShareFamilyBudgets() throws {
        let rule = try CadenceScanInstrument(
            "widget family content budget",
            fires: "family.cadenceLayout.habitLimit",
            andNotOn: "// family.cadenceLayout.habitLimit\nlet limit = 8",
            by: { CadenceSourceScan.codeOnly($0).contains(".cadenceLayout.") }
        )
        let paths = [
            "CadenceWidgets/TodayTasksWidget.swift", "CadenceWidgets/TodayTasksWidgetView.swift",
            "CadenceWidgets/HabitCheckInWidget.swift", "CadenceWidgets/CalendarSnapshotWidget.swift",
            "CadenceWidgets/MilestoneMomentumWidget.swift",
        ]
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try rule.sweep(paths, atLeast: 5, including: paths[2], read: read) == paths.sorted())
        let habit = CadenceSourceScan.codeOnly(try read(paths[2]))
        #expect(habit.contains("limit: family.cadenceLayout.habitLimit"))
        #expect(habit.contains("paddedHabits(count: layout.habitLimit)"))
        #expect(habit.contains("count: layout.habitColumns"))
        #expect(habit.contains(".contentMarginsDisabled()"))
        #expect(!habit.contains("summaryRail"))
        let calendar = CadenceSourceScan.codeOnly(try read(paths[3]))
        #expect(calendar.contains("renderedCount: snapshot.state == .ready"))
        #expect(calendar.contains("min(snapshot.days.count, family.cadenceLayout.calendarDayLimit)"))
        #expect(calendar.contains("family.cadenceLayout.calendarDayLimit) : 0"))
        #expect(calendar.contains("entry.snapshot.days.prefix(widgetFamily.cadenceLayout.calendarDayLimit)"))
        let milestone = CadenceSourceScan.codeOnly(try read(paths[4]))
        #expect(milestone.contains("min(snapshot.visibleGoals.count, family.cadenceLayout.milestoneGoalLimit)"))
        #expect(milestone.contains("entry.snapshot.visibleGoals.prefix(widgetFamily.cadenceLayout.milestoneGoalLimit)"))
        let today = CadenceSourceScan.codeOnly(try read(paths[0]))
        #expect(today.contains("family.cadenceLayout.todayTaskLimit"))
        #expect(today.contains("limit: snapshotLimit(for: family)"))
        #expect(today.contains("renderedCount: snapshot.tasks.count"))
    }

    @Test func codexHabitSnapshotRequestsOverridesForItsOwnDate() throws {
        let rule = try CadenceScanInstrument(
            "habit snapshot dated override",
            fires: "CadenceWidgetRefreshCenter.recentHabitCompletionStates(dateKey: todayKey)",
            andNotOn: "// recentHabitCompletionStates(dateKey: todayKey)\nCadenceWidgetRefreshCenter.recentHabitCompletionStates()",
            by: { CadenceSourceScan.codeOnly($0).contains("recentHabitCompletionStates(dateKey: todayKey)") }
        )
        let paths = ["Cadence/Services/CadenceHabitWidgetSupport.swift"]
        #expect(try rule.sweep(paths, atLeast: 1, including: paths[0], read: CadenceSourceScan.strippedSourceReader()) == paths)
    }

}
