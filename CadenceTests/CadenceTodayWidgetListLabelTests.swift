import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-17067]]: the Today widget's row names its list the way the app's Today does.
///
/// `CadenceTodayWidgetSupport.widgetTask` handed the row the raw `AppTask.containerName`, and the
/// widget draws the pill only when that is non-empty -- so a task in a blank-named project drew no
/// list at all, and one in a whitespace-named area drew an empty capsule, while the app's Today
/// files the same task under a heading reading "Untitled Project" / "Untitled Area".
@MainActor
@Suite("Today widget list label")
struct CadenceTodayWidgetListLabelTests {
    private let todayKey = "2026-08-20"

    @Test func aWidgetRowNamesABlankListAsTodaysHeadingDoes() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let named = Area(name: "  Admin  ")
        let blankArea = Area(name: "")
        let spaceProject = Project(name: "   ")
        modelContext.insert(named)
        modelContext.insert(blankArea)
        modelContext.insert(spaceProject)

        func dueToday(_ title: String, order: Int, area: Area? = nil, project: Project? = nil) -> AppTask {
            let task = AppTask(title: title)
            task.dueDate = todayKey
            task.order = order
            task.area = area
            task.project = project
            modelContext.insert(task)
            return task
        }
        let tasks = [
            dueToday("Named", order: 0, area: named),
            dueToday("Blank area", order: 1, area: blankArea),
            dueToday("Blank project", order: 2, project: spaceProject),
            dueToday("Inbox", order: 3),
        ]
        try modelContext.save()

        let snapshot = CadenceTodayWidgetSupport.snapshot(from: tasks, todayKey: todayKey, limit: 8)
        #expect(snapshot.tasks.count == 4, "non-vacuity: every row reached the widget")

        let labels = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.title, $0.containerName) })
        #expect(labels["Named"] == "Admin")
        #expect(labels["Blank area"] == "Untitled Area")
        #expect(labels["Blank project"] == "Untitled Project")
        // Unchanged: an Inbox row draws no pill.
        #expect(labels["Inbox"] == "")

        // The same words as the app's Today group each listed task sits under.
        let groups = CadenceTaskQuerySupport.todayListGroups(from: tasks, contexts: [])
        for group in groups where group.title != CadenceBoardCardMetadata.inboxLabel {
            for task in group.tasks {
                #expect(labels[task.title] == group.title, "\(task.title)")
            }
        }
    }

    /// A row filed under both an area and a project names the project, as `containerName`,
    /// `listGroupKey(for:)` and the row's list chip all do.
    @Test func aDualFiledRowNamesItsBlankProjectNotItsArea() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Home")
        let project = Project(name: "")
        modelContext.insert(area)
        modelContext.insert(project)
        let task = AppTask(title: "Dual")
        task.dueDate = todayKey
        task.area = area
        task.project = project
        modelContext.insert(task)
        try modelContext.save()

        #expect(CadenceTodayWidgetSupport.listLabel(for: task) == "Untitled Project")
    }
}

#if os(macOS)
/// [[T-17068]]: the Mac Today header names the day `todayKey()` names. Its eyebrow read `Date()`,
/// so under the Debug today override ([[T-15200]]) it spelled the real date above a page drawn for
/// the shifted day, while iPad Today's header (handed `DateFormatters.now()` by `iOSTodayView`) and
/// the Mac schedule pane beside it ([[T-15611]]) both followed the override. A view's private
/// property cannot be driven from a unit test, so this reads the header's code.
@MainActor
struct CadenceMacTodayHeaderDayTests {
    @Test func theMacTodayHeaderSpellsTheOverriddenDayNotTheRealClock() throws {
        let support = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift")
        )
        let header = try #require(
            CadenceSourceScan.declarationBody("struct TasksPanelHeader<Trailing: View>: View", in: support),
            "non-vacuity: TasksPanelHeader is gone or its braces do not balance"
        )
        #expect(header.contains("DateFormatters.longDate.string(from: DateFormatters.now())"))
        #expect(!header.contains("Date()"), "the Mac Today header reads the real clock again")
    }
}
#endif
