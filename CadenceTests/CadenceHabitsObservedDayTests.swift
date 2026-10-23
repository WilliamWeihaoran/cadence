// macOS only: `HabitListFilter` is the macOS Habits page's filter. The iOS page's wire is pinned by
// source scan below, which reads files and compiles on either destination's host.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-5012]] (a) — the Habits pages read an observed day, not the clock.**
///
/// Both platforms' Habits pages computed `todayKey` from the clock in a body whose inputs are the
/// same on both sides of midnight, so a page left open overnight kept "Done today" on yesterday's
/// tick and the Due Today / Completed Today filters on yesterday's set. Each page now holds one
/// `CadenceObservedDay` (one per page, not per row — [[T-3124]]) and hands its key down.
///
/// Which views install the observer is pinned by `CadenceDayChangeAdoptionTests`. This suite pins
/// the filter's rule by behaviour and the key reaching it. Every key is a literal.
@MainActor
struct CadenceHabitsObservedDayTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - The filter's rule

    @Test func aHabitTickedYesterdayLeavesCompletedTodayOnceTheDayTurns() {
        let habit = Habit(title: "Stretch")
        habit.frequencyType = .daily
        habit.completions = [HabitCompletion(date: "2026-10-21", habit: habit)]

        #expect(HabitListFilter.completed.matches(habit, todayKey: "2026-10-21"))
        #expect(!HabitListFilter.completed.matches(habit, todayKey: "2026-10-22"))
    }

    @Test func dueTodayFollowsTheObservedDaysWeekday() {
        let habit = Habit(title: "Laundry")
        habit.frequencyType = .daysOfWeek
        habit.frequencyDays = [4] // Thursday; 2026-10-22 is a Thursday.

        #expect(HabitListFilter.today.matches(habit, todayKey: "2026-10-22"))
        #expect(!HabitListFilter.today.matches(habit, todayKey: "2026-10-23"))
    }

    // MARK: - The wire

    @Test func theMacPageFiltersAndRendersAgainstItsObservedDay() throws {
        let source = try Self.code("Cadence/macOS/Views/HabitsView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct HabitsView: View", in: source))
        #expect(page.contains("private var todayKey: String { observedDay.todayKey }"))
        #expect(page.contains("filter.matches(habit, todayKey: todayKey)"))
        #expect(page.contains("HabitDetailView(habit: habit, todayKey: todayKey)"))

        let filter = try Self.code("Cadence/macOS/Views/HabitListSupport.swift")
        #expect(!filter.contains("DateFormatters.todayKey()"))
    }

    @Test func theIOSPageHandsItsObservedDayToItsRows() throws {
        let source = try Self.code("Cadence/iOS/iOSFeatureViews.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct iOSHabitsView: View", in: source))
        #expect(page.contains("private var todayKey: String { observedDay.todayKey }"))
        #expect(page.contains("iOSHabitCheckInGlyph(habit: habit, todayKey: todayKey)"))
    }

    @Test func rowsAndDetailsAskTheObservedDayWhetherTheHabitIsDue() throws {
        // `isDueToday` is a clock read; the rows and detail panes ask the key they were handed.
        let mac = try Self.code("Cadence/macOS/Views/HabitsSupportViews.swift")
        let card = try #require(CadenceSourceScan.declarationBody("struct HabitListCard: View", in: mac))
        #expect(card.contains("if habit.isDue(onDayKey: todayKey) {"))
        let detail = try #require(CadenceSourceScan.declarationBody("struct HabitDetailView: View", in: mac))
        #expect(detail.contains("habit.isDue(onDayKey: todayKey)"))
        #expect(!mac.contains("isDueToday"))

        let iosPage = try #require(CadenceSourceScan.declarationBody(
            "struct iOSHabitsView: View", in: try Self.code("Cadence/iOS/iOSFeatureViews.swift")))
        #expect(iosPage.contains("habits.filter { $0.isDue(onDayKey: todayKey) }"))
        #expect(!iosPage.contains("isDueToday"))

        let iosDetail = try Self.code("Cadence/iOS/iOSFeatureDetailViews.swift")
        for name in ["struct iOSHabitSummaryRow: View", "struct iOSHabitDetail: View"] {
            let view = try #require(CadenceSourceScan.declarationBody(name, in: iosDetail), "\(name)")
            #expect(view.contains("habit.isDue(onDayKey: todayKey)"), "\(name)")
            #expect(!view.contains("isDueToday"), "\(name)")
        }
    }
}
#endif
