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

    /// **Re-pointed for [[T-2078]], not weakened, and not deleted.** This guard used to walk five
    /// widget sources. `7b686a76` deleted two of them with the Habit Check-In and Milestone
    /// Momentum widgets, and `sweep` *reads* every path it is handed — so the stale list did not
    /// fail an assertion, it threw `NSCocoaErrorDomain 260` and `main` was red on an I/O error
    /// rather than on the thing this test is for. The three survivors are walked, `atLeast:` is
    /// re-derived 5 -> 3 rather than relaxed to a floor, and the witness is **named rather than
    /// indexed**: `including: paths[2]` used to be `HabitCheckInWidget.swift`, so deleting array
    /// entries alone would have silently re-pointed the non-vacuity claim at a different file.
    ///
    /// **Which assertions died with which widget, and where the equivalent went.**
    /// - `HabitCheckInWidget.swift`: `limit: family.cadenceLayout.habitLimit` and
    ///   `paddedHabits(count: layout.habitLimit)` were the provider-side and the view-side halves
    ///   of one claim — the family budget reaches the drawn content. **Both halves survive and are
    ///   asserted below**: the provider half on `TodayTasksWidget` and `CalendarSnapshotWidget`,
    ///   and the view half as the new `TodayTasksWidgetView` block, which this test walked in its
    ///   sweep but never actually read. That gap is the reason the view block is added here rather
    ///   than the habit block merely being dropped.
    /// - `count: layout.habitColumns` and `.contentMarginsDisabled()` have **no equivalent** and
    ///   are gone. No surviving widget lays content out in a family-sized grid, and
    ///   `.contentMarginsDisabled()` now appears nowhere under `CadenceWidgets/`.
    /// - `!habit.contains("summaryRail")` is gone and **was already vacuous before T-2078**:
    ///   `summaryRail` occurs nowhere in this repository and did not occur in
    ///   `HabitCheckInWidget.swift` either, so it was true of any file including an empty one. It
    ///   is replaced by a negative control that can actually fire — the Today view must not
    ///   hardcode a row count equal to any family's `todayTaskLimit`.
    /// - `MilestoneMomentumWidget.swift`'s two `milestoneGoalLimit` reads were the clamp-then-
    ///   prefix pair. The identical pair on `calendarDayLimit` is asserted below and is untouched,
    ///   so the shape those two lines guarded is still guarded.
    ///
    /// `habitLimit`, `habitColumns` and `milestoneGoalLimit` still exist on
    /// `CadenceWidgetFamilyLayout` and are deliberately **not** removed here. After T-2078 their
    /// only readers anywhere in the tree are the model assertions in
    /// `codexWidgetFamilyBudgetsMatchTheSelectedContent` above; retiring the properties is a
    /// separate decision and a separate ticket, not a side effect of fixing a red run.
    @Test func codexWidgetProvidersAndViewsShareFamilyBudgets() throws {
        let rule = try CadenceScanInstrument(
            "widget family content budget",
            fires: "family.cadenceLayout.todayTaskLimit",
            andNotOn: "// family.cadenceLayout.todayTaskLimit\nlet limit = 8",
            by: { CadenceSourceScan.codeOnly($0).contains(".cadenceLayout.") }
        )
        // Named, not indexed: the witness must survive an edit to this list, not follow its order.
        let todayProviderPath = "CadenceWidgets/TodayTasksWidget.swift"
        let todayViewPath = "CadenceWidgets/TodayTasksWidgetView.swift"
        let calendarPath = "CadenceWidgets/CalendarSnapshotWidget.swift"
        let paths = [todayProviderPath, todayViewPath, calendarPath]
        let read = CadenceSourceScan.strippedSourceReader()
        #expect(try rule.sweep(paths, atLeast: 3, including: calendarPath, read: read) == paths.sorted())
        let calendar = CadenceSourceScan.codeOnly(try read(calendarPath))
        #expect(calendar.contains("renderedCount: snapshot.state == .ready"))
        #expect(calendar.contains("min(snapshot.days.count, family.cadenceLayout.calendarDayLimit)"))
        #expect(calendar.contains("family.cadenceLayout.calendarDayLimit) : 0"))
        #expect(calendar.contains("entry.snapshot.days.prefix(widgetFamily.cadenceLayout.calendarDayLimit)"))
        let today = CadenceSourceScan.codeOnly(try read(todayProviderPath))
        #expect(today.contains("family.cadenceLayout.todayTaskLimit"))
        #expect(today.contains("limit: snapshotLimit(for: family)"))
        #expect(today.contains("renderedCount: snapshot.tasks.count"))
        let todayView = CadenceSourceScan.codeOnly(try read(todayViewPath))
        #expect(todayView.contains("entry.snapshot.tasks.prefix(widgetFamily.cadenceLayout.todayTaskLimit)"))
        #expect(todayView.contains("prefix(widgetFamily.cadenceLayout.todayTaskLimit - 1)"))
        let hardcodedBudgets = CadenceWidgetFamilyLayout.allCases
            .map { "prefix(\($0.todayTaskLimit))" }
            .filter { todayView.contains($0) }
        #expect(hardcodedBudgets.isEmpty, "the Today view's row budget must come from cadenceLayout, not a literal")
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
