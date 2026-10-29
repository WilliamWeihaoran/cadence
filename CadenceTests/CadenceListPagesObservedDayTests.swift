#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **T-5012 (b)–(d) — the list pages, the boards, Goals and Notes read an observed day.**
///
/// Each of these read `DateFormatters.todayKey()` in a body whose inputs are the same on both
/// sides of midnight — a row's red overdue tint and amber "do today", a card's do/due chips, a
/// goal's due flag, the Notes list's pinned current day — so a page left open overnight kept
/// yesterday's answer until something else redrew it. The fix is one observer per page host,
/// handing its key down; the rows and cards take it as a parameter with **no default**, which is
/// what makes a host that forgets it a compile error rather than a quiet clock read.
///
/// Which views install the observer is pinned by `CadenceDayChangeAdoptionTests`. This suite pins
/// the predicates by behaviour (every key a literal; nothing moves `NSTimeZone.default`) and the
/// rest of the wire by source.
@MainActor
struct CadenceListPagesObservedDayTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    private func task(scheduled: String = "", due: String = "", status: TaskStatus = .todo) -> AppTask {
        let task = AppTask(title: "T")
        task.scheduledDate = scheduled
        task.dueDate = due
        task.status = status
        return task
    }

    // MARK: - The predicates answer against the handed day, not the clock

    @Test func aTaskDueYesterdayIsOverdueOnceTheObservedDayTurns() {
        let due = task(due: "2026-10-22")
        #expect(!KanbanCardComputedSupport.isOverdue(task: due, todayKey: "2026-10-22"))
        #expect(KanbanCardComputedSupport.isOverdue(task: due, todayKey: "2026-10-23"))
    }

    @Test func aTaskPlannedForTodayBecomesOverdoAtMidnight() {
        let planned = task(scheduled: "2026-10-22")
        #expect(KanbanCardComputedSupport.isDoToday(task: planned, todayKey: "2026-10-22"))
        #expect(!KanbanCardComputedSupport.isOverdo(task: planned, todayKey: "2026-10-22"))

        #expect(!KanbanCardComputedSupport.isDoToday(task: planned, todayKey: "2026-10-23"))
        #expect(KanbanCardComputedSupport.isOverdo(task: planned, todayKey: "2026-10-23"))
    }

    @Test func aFinishedTaskIsNeverOverdoOrDoToday() {
        let finished = task(scheduled: "2026-10-22", status: .done)
        #expect(!KanbanCardComputedSupport.isOverdo(task: finished, todayKey: "2026-10-23"))
        #expect(!KanbanCardComputedSupport.isDoToday(task: finished, todayKey: "2026-10-22"))
    }

    @Test func overdoMeasuresAcrossAMonthAndAYearBoundary() {
        #expect(KanbanCardComputedSupport.isOverdo(task: task(scheduled: "2026-12-31"), todayKey: "2027-01-01"))
        #expect(!KanbanCardComputedSupport.isOverdo(task: task(scheduled: "2027-01-01"), todayKey: "2026-12-31"))
    }

    // MARK: - The predicates and the row/card read no clock

    @Test func theSharedPredicatesTakeTheDayAndReadNoClock() throws {
        let source = try Self.code("Cadence/macOS/Views/KanbanCardComputedSupport.swift")
        #expect(!source.contains("DateFormatters.todayKey()"))
        #expect(CadenceSourceScan.matchCount(#"task: AppTask, todayKey: String\) -> Bool"#, in: source) == 3)
    }

    @Test func theMacRowTakesTheDayWithNoDefaultAndHandsItToEveryPredicate() throws {
        let source = try Self.code("Cadence/macOS/Views/TasksPanelComponents.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct MacTaskRow: View", in: source))
        #expect(row.contains("let todayKey: String"))
        #expect(!row.contains("DateFormatters.todayKey()"))
        #expect(CadenceSourceScan.matchCount(#"KanbanCardComputedSupport\.is\w+\(task: task, todayKey: todayKey\)"#, in: row) == 3)

        let wrappers = try Self.code("Cadence/macOS/Views/ListDetailSupportViews.swift")
        for name in ["struct TaskListDisplayRow: View", "struct TaskListInteractiveRow: View"] {
            let wrapper = try #require(CadenceSourceScan.declarationBody(name, in: wrappers), "\(name)")
            #expect(wrapper.contains("let todayKey: String"), "\(name)")
            #expect(wrapper.contains("todayKey: todayKey,"), "\(name)")
        }
    }

    @Test func theKanbanCardHandsTheDayToItsChips() throws {
        let source = try Self.code("Cadence/macOS/Views/KanbanCardView.swift")
        let card = try #require(CadenceSourceScan.declarationBody("struct KanbanCard: View", in: source))
        #expect(card.contains("let todayKey: String"))
        // [[T-8181]]: the chips are read inside the card's Ledger run now, not in a metadata-row
        // builder of their own, so the call sits one level deeper. What is pinned is unchanged —
        // the card hands its HOST's observed day to the shared descriptor and never reads the clock.
        #expect(card.contains("dayAlreadyStatedBySurface: dayAlreadyStatedBySurface,\n                todayKey: todayKey\n"))
        #expect(!card.contains("DateFormatters.todayKey()"))
    }

    // MARK: - The hosts hand their observed day down

    @Test func theListTasksTabHandsItsObservedDayToBothSectionKinds() throws {
        let source = try Self.code("Cadence/macOS/Views/ListDetailComponents.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct ListTasksView: View", in: source))
        #expect(page.contains("private var todayKey: String { observedDay.todayKey }"))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: page))
        #expect(body.contains("let todayKey = self.todayKey"))
        #expect(CadenceSourceScan.matchCount(#"\n\s+todayKey: todayKey,"#, in: body) == 2)
    }

    @Test func theTasksPageHandsItsObservedDayToBothSectionKinds() throws {
        let source = try Self.code("Cadence/macOS/Views/TasksListView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct TasksListView: View", in: source))
        #expect(page.contains("private var todayKey: String { observedDay.todayKey }"))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: page))
        #expect(body.contains("let todayKey = self.todayKey"))
        #expect(CadenceSourceScan.matchCount(#"\n\s+todayKey: todayKey,"#, in: body) == 2)
        for name in ["private struct TasksListSectionView: View", "private struct TasksListCompletedSectionView: View"] {
            let section = try #require(CadenceSourceScan.declarationBody(name, in: source), "\(name)")
            #expect(section.contains("let todayKey: String"), "\(name)")
        }
    }

    @Test func theTodayPageHandsItsKeyToItsRowsAsTheirDay() throws {
        let source = try Self.code("Cadence/macOS/Views/TasksPanelSectionViews.swift")
        #expect(CadenceSourceScan.matchCount(#"dayAlreadyStatedBySurface: todayKey,\n\s+todayKey: todayKey,"#, in: source) == 2)
    }

    @Test func bothBoardsHandTheirObservedDayToEveryColumnAndCard() throws {
        let allTasks = try #require(CadenceSourceScan.declarationBody(
            "struct TaskListsKanbanView: View", in: try Self.code("Cadence/macOS/Views/KanbanSupportViews.swift")
        ))
        #expect(allTasks.contains("taskListColumnsBoard(activeTasks: activeTasks, todayKey: observedDay.todayKey)"))
        #expect(allTasks.contains("todayKey: todayKey,\n                        universeTasks:"))

        let sections = try #require(CadenceSourceScan.declarationBody(
            "struct ListSectionsKanbanView: View", in: try Self.code("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        ))
        #expect(sections.contains("let todayKey = observedDay.todayKey"))
        #expect(sections.contains("todayKey: todayKey,\n                                    universeTasks:"))

        let listColumn = try Self.code("Cadence/macOS/Views/KanbanListColumnView.swift")
        let sectionColumn = try Self.code("Cadence/macOS/Views/KanbanSectionColumnView.swift")
        #expect(CadenceSourceScan.matchCount(#"KanbanDraggableCard\(\s*task: task,\s*todayKey: todayKey"#, in: listColumn) == 1)
        #expect(CadenceSourceScan.matchCount(#"KanbanDraggableCard\(\s*task: task,\s*todayKey: todayKey"#, in: sectionColumn) == 2)

        let draggable = try Self.code("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        #expect(draggable.contains("KanbanCard(task: task, todayKey: todayKey)"))
    }

    @Test func theCalendarBoardHandsItsDayToTheRailAndDayColumnCards() throws {
        let rail = try Self.code("Cadence/macOS/Views/CalendarBoardRailSupportViews.swift")
        #expect(rail.contains("KanbanCard(task: task, showsContainerChip: true, todayKey: todayKey)"))
        let day = try Self.code("Cadence/macOS/Views/CalendarBoardDayColumnSupportViews.swift")
        #expect(CadenceSourceScan.matchCount(
            #"KanbanCard\(task: task, showsContainerChip: true, dayAlreadyStatedBySurface: dateKey, todayKey: todayKey\)"#,
            in: day
        ) == 2)
    }

    @Test func theListNotesPageHandsItsObservedDayToTheTaskNoteRows() throws {
        let page = try #require(CadenceSourceScan.declarationBody(
            "struct ListNotesView: View", in: try Self.code("Cadence/macOS/Views/ListNotesView.swift")
        ))
        let section = try #require(CadenceSourceScan.declarationBody("private var taskNoteSection: some View", in: page))
        #expect(section.contains("let todayKey = observedDay.todayKey"))
        #expect(section.contains("todayKey: todayKey,"))

        let row = try #require(CadenceSourceScan.declarationBody(
            "struct TaskNoteListRow: View", in: try Self.code("Cadence/macOS/Views/ListNotesListSupportViews.swift")
        ))
        #expect(row.contains("let todayKey: String"))
        #expect(!row.contains("DateFormatters.todayKey()"))
    }

    // **`theGoalsPageHandsItsObservedDayToEveryDueFlag` left with [[T-5002]].** T-5012 (b)-(d)
    // gave every list page one `CadenceObservedDay`; Goals was one of them, and the page, its
    // inspector, its sheet and `GoalDueDateLabel` are all deleted. Every other page the ticket
    // covered keeps its test in this file, and the adoption list itself is
    // `CadenceDayChangeAdoptionTests`.

    // MARK: - Notes

    @Test func theMacNotesListsPinTheObservedDayAndWeek() throws {
        let source = try Self.code("Cadence/macOS/Views/NotesView.swift")
        let daily = try #require(CadenceSourceScan.declarationBody("private struct DailyNotesPage: View", in: source))
        #expect(daily.contains("NotesListVisibility.dailyNotes(notes, todayKey: observedDay.todayKey)"))
        let weekly = try #require(CadenceSourceScan.declarationBody("private struct WeeklyNotesPage: View", in: source))
        #expect(weekly.contains("DateFormatters.weekKey(from: DateFormatters.date(from: observedDay.todayKey) ?? Date())"))
        #expect(!weekly.contains("currentWeekKey()"))
    }

    @Test func theIOSNotesListPinsTheObservedDayAndWeek() throws {
        let source = try Self.code("Cadence/iOS/iOSNotesView.swift")
        let page = try #require(CadenceSourceScan.declarationBody("struct iOSNotesView: View", in: source))
        let listed = try #require(CadenceSourceScan.declarationBody("private var listedNotes: [Note]", in: page))
        #expect(listed.contains("let todayKey = observedDay.todayKey\n        switch activeTab"))
        #expect(listed.contains("NotesListVisibility.dailyNotes(notesForActiveTab, todayKey: todayKey)"))
        #expect(!listed.contains("currentWeekKey()"))
    }
}
#endif
