// macOS only, like its siblings: the iOS page's wire is pinned by source scan, which reads files
// and runs on the macOS test host.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5050]] — the iOS goal detail reads an observed day, not the clock.**
///
/// `iOSGoalDetail.nextActionLine` computed `DateFormatters.todayKey()` in `body` for the "Next"
/// line's due label and overdue tint, and its summary's overdue / done-recently counts read
/// `Date()` — in a body whose inputs are the same on both sides of midnight. A goal detail left open
/// overnight kept yesterday's "Today" / "Tomorrow" and yesterday's red. `iOSGoalsView` now holds one
/// `CadenceObservedDay` (one per page, as Habits does under [[T-5012]]) and hands its key down.
///
/// `CadenceDayChangeAdoptionTests` pins the *files* that install the observer by equality; its
/// per-declaration check names `iOSHabitsView` in `iOSFeatureViews.swift`, so the goals page's
/// declaration is checked here instead. Every key is a literal.
@MainActor
struct CadenceGoalsObservedDayTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - The rule the detail now feeds its key into

    @Test func theNextActionTurnsOverdueOnceTheObservedDayPassesItsDueDate() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)

        let context = Context(name: "Work")
        let area = Area(name: "Launch", context: context)
        let goal = Goal(title: "Ship", context: context)
        let task = AppTask(title: "Write the notes")
        task.area = area
        task.context = context
        task.goal = goal
        task.dueDate = "2026-10-22"

        modelContext.insert(context)
        modelContext.insert(area)
        modelContext.insert(goal)
        modelContext.insert(task)
        try modelContext.save()

        func summary(on key: String) throws -> GoalContributionSummary {
            GoalContributionResolver.summary(for: goal, now: try #require(DateFormatters.date(from: key)))
        }

        let before = try summary(on: "2026-10-22")
        let after = try summary(on: "2026-10-23")
        #expect(before.nextActionDueDate == "2026-10-22")
        #expect(before.overdueTaskCount == 0)
        #expect(after.overdueTaskCount == 1)

        #expect(!CadenceFocusSupport.isOverdue(dueDateKey: "2026-10-22", todayKey: "2026-10-22"))
        #expect(CadenceFocusSupport.isOverdue(dueDateKey: "2026-10-22", todayKey: "2026-10-23"))
        #expect(
            CadenceFocusSupport.dueLabel(forDueDateKey: "2026-10-22", todayKey: "2026-10-22")
                != CadenceFocusSupport.dueLabel(forDueDateKey: "2026-10-22", todayKey: "2026-10-23")
        )
    }

    // MARK: - The wire

    @Test func theIOSGoalsPageObservesTheDayAndHandsItToTheDetail() throws {
        let source = try Self.code("Cadence/iOS/iOSFeatureViews.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct iOSGoalsView: View", in: source))
        #expect(page.contains("@State private var observedDay = CadenceObservedDay()"))
        #expect(page.contains("private var todayKey: String { observedDay.todayKey }"))
        #expect(!page.contains("DateFormatters.todayKey()"))

        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: page))
        #expect(body.contains("let _ = observedDay.todayKey"))
        #expect(body.components(separatedBy: ".cadenceTracksDayChanges($observedDay)").count - 1 == 1)

        // One construction site, and it carries the page's key (both the split pane and the push).
        #expect(page.components(separatedBy: "iOSGoalDetail(").count - 1 == 1)
        #expect(page.contains("todayKey: todayKey,"))
    }

    @Test func theGoalDetailReadsTheKeyItWasHandedNeverTheClock() throws {
        let source = try Self.code("Cadence/iOS/iOSFeatureDetailViews.swift")
        let detail = try #require(CadenceSourceScan.declarationBody("struct iOSGoalDetail: View", in: source))
        #expect(detail.contains("let todayKey: String"))
        #expect(!detail.contains("DateFormatters.todayKey()"))
        #expect(detail.contains(
            "GoalContributionResolver.summary(for: goal, now: DateFormatters.date(from: todayKey) ?? Date())"
        ))

        let line = try #require(CadenceSourceScan.declarationBody("private var nextActionLine: some View", in: detail))
        #expect(line.contains("CadenceFocusSupport.dueLabel(forDueDateKey: $0, todayKey: todayKey)"))
        #expect(line.contains("CadenceFocusSupport.isOverdue(dueDateKey: $0, todayKey: todayKey)"))
        #expect(!line.contains("let todayKey"))
    }
}
#endif
