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
        // One, not three, since [[T-12642]]: the do-date pill's over-do / do-today pair became the
        // shared row emphasis, which takes the same observed day.
        #expect(CadenceSourceScan.matchCount(#"KanbanCardComputedSupport\.is\w+\(task: task, todayKey: todayKey\)"#, in: row) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskRowDoDateEmphasis\.emphasis\(for: task, todayKey: todayKey\)"#, in: row) == 1)

        let wrappers = try Self.code("Cadence/macOS/Views/ListDetailSupportViews.swift")
        for name in ["struct TaskListDisplayRow: View", "struct TaskListInteractiveRow: View"] {
            let wrapper = try #require(CadenceSourceScan.declarationBody(name, in: wrappers), "\(name)")
            #expect(wrapper.contains("let todayKey: String"), "\(name)")
            #expect(wrapper.contains("todayKey: todayKey,"), "\(name)")
        }
    }

    /// **[[T-14341]] -- the touch row, which [[T-5012]] left reading the clock.** `iOSTaskRow`
    /// measured its do-date emphasis and its due flag against `DateFormatters.todayKey()`, so on a
    /// phone left on Inbox, All Tasks, a list or the Calendar overnight a task due "today" stayed
    /// amber instead of turning red -- the row's inputs are the same on both sides of midnight.
    /// It takes the day with no default now, as `MacTaskRow` does, and every host hands down the
    /// observed day it already holds.
    @Test func theTouchRowTakesTheDayWithNoDefaultAndEveryHostHandsItsObservedDay() throws {
        let views = try Self.code("Cadence/iOS/iOSTaskViews.swift")
        let row = try #require(CadenceSourceScan.declarationBody("struct iOSTaskRow: View", in: views))
        #expect(row.contains("let todayKey: String"))
        #expect(!row.contains("let todayKey: String ="))
        #expect(!row.contains("DateFormatters.todayKey()"))
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskRowDoDateEmphasis\.emphasis\(for: task, todayKey: todayKey\)"#, in: row) == 1)
        #expect(CadenceSourceScan.matchCount(#"CadenceDueUrgency\.evaluate\(dueDateKey: task\.dueDate, isDone: task\.isDone, todayKey: todayKey\)"#, in: row) == 1)
        let listRow = try #require(CadenceSourceScan.declarationBody("struct iOSTaskListRow: View", in: views))
        #expect(listRow.contains("let todayKey: String"))
        #expect(listRow.contains("todayKey: todayKey)"))

        // The two group components take the key and hand it to every row they draw.
        let groups = try Self.code("Cadence/iOS/iOSTaskGroupSection.swift")
        for name in ["struct iOSTaskGroupSection: View", "struct iOSCompletedTasksSection: View"] {
            let group = try #require(CadenceSourceScan.declarationBody(name, in: groups), "\(name)")
            #expect(group.contains("let todayKey: String"), "\(name)")
            #expect(group.contains("todayKey: todayKey\n"), "\(name)")
        }

        // Every host hands down its observed day, never the clock -- one argument per section or
        // row it builds.
        let hosts: [(path: String, needle: String, count: Int)] = [
            ("Cadence/iOS/iOSTaskCollectionPage.swift", "todayKey: observedDay.todayKey,\n", 2),
            ("Cadence/iOS/iOSTaskCollectionPage.swift", "todayKey: todayKey,\n", 3),
            // Five since [[T-14581]]: the board panel takes the page's day for its cards too.
            ("Cadence/iOS/iOSListDetailView.swift", "todayKey: observedDay.todayKey", 5),
            ("Cadence/iOS/iOSListSupportViews.swift", "showsContainer: false, todayKey: todayKey)", 1),
            ("Cadence/iOS/iOSTodayTaskSections.swift", "dayAlreadyStatedBySurface: todayKey,\n                    todayKey: todayKey,", 1),
            ("Cadence/iOS/iOSTodayTaskSections.swift", "dayAlreadyStatedBySurface: todayKey,\n                todayKey: todayKey,", 1),
            ("Cadence/iOS/iOSCalendarInspectorView.swift", "todayKey: todayKey)", 3),
            ("Cadence/iOS/iOSCalendarView.swift", "dueOnlyTasks: selectedDueOnlyTasks,\n            todayKey: observedDay.todayKey,", 1),
            ("Cadence/iOS/iOSCalendarMonthAgendaViews.swift", "dayAlreadyStatedBySurface: dayKey, todayKey: todayKey)", 1),
        ]
        for host in hosts {
            let source = try Self.code(host.path)
            #expect(source.components(separatedBy: host.needle).count - 1 == host.count, "\(host.path): \(host.needle)")
        }
    }

    /// [[T-14541]]: the iOS Today's two children read the clock themselves -- the phone header's
    /// date eyebrow formatted `Date()` and the sections view computed `DateFormatters.todayKey()`
    /// for every row -- while every other input they take is the same on both sides of midnight,
    /// so SwiftUI kept their old bodies and Today kept yesterday's date and "Today" chips after the
    /// page's own day observer had turned. Both take the page's `content.todayKey` now.
    @Test func theIOSTodayChildrenTakeThePagesDayAndReadNoClock() throws {
        let sections = try Self.code("Cadence/iOS/iOSTodayTaskSections.swift")
        let compact = try Self.code("Cadence/iOS/iOSTodayCompactViews.swift")
        for (path, source) in [("iOSTodayTaskSections", sections), ("iOSTodayCompactViews", compact)] {
            #expect(!source.contains("DateFormatters.todayKey()"), "\(path)")
            #expect(!source.contains("Date()"), "\(path)")
        }
        let sectionsView = try #require(CadenceSourceScan.declarationBody("struct iOSTodayTaskSections: View", in: sections))
        #expect(sectionsView.contains("let todayKey: String\n"))
        let compactView = try #require(CadenceSourceScan.declarationBody("struct iOSCompactTodayView: View", in: compact))
        #expect(compactView.contains("let todayKey: String\n"))
        #expect(compactView.contains("eyebrow: DateFormatters.date(from: todayKey)"))
        // The compact view hands its key to both of its sections builds (DEBUG and release).
        #expect(compactView.components(separatedBy: "completedTasks: completedTodayTasks,\n            todayKey: todayKey,\n").count - 1 == 2)

        // Both hosts hand the page's observed day: the two-pane sections (DEBUG and release) and
        // the compact host's two `iOSCompactTodayView` builds.
        let page = try Self.code("Cadence/iOS/iOSTodayView.swift")
        #expect(page.components(separatedBy: "completedTasks: content.completedTasks,\n            todayKey: content.todayKey,\n").count - 1 == 2)
        let host = try #require(CadenceSourceScan.declarationBody("struct iOSCompactTodayHost: View, Equatable", in: page))
        #expect(host.components(separatedBy: "todayTaskGroups: content.taskGroups,\n            todayKey: content.todayKey,\n").count - 1 == 2)
        // And the host's `==` still compares the content that carries that key.
        #expect(host.contains("lhs.content == rhs.content"))
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

    /// **[[T-14581]] -- the touch board card, which neither [[T-5012]] nor [[T-14341]] reached.**
    /// `iOSBoardTaskCard` called the shared chip builder without a day, so its clock default
    /// answered the due chip's red and the do chip's amber/red -- and the card's inputs are the
    /// same on both sides of midnight, so a list board or the Calendar Board left open overnight
    /// kept yesterday's emphasis. It takes the day with no default now, as `KanbanCard` does, and
    /// all four of its builds hand down their host's observed day.
    @Test func theTouchBoardCardTakesTheDayWithNoDefaultAndEveryHostHandsItsObservedDay() throws {
        let cards = try Self.code("Cadence/iOS/iOSBoardCards.swift")
        let card = try #require(CadenceSourceScan.declarationBody("struct iOSBoardTaskCard: View", in: cards))
        #expect(card.contains("let todayKey: String\n"))
        #expect(!card.contains("let todayKey: String ="))
        #expect(!card.contains("DateFormatters.todayKey()"))
        #expect(card.contains("dateChipsArePickers: false,\n                todayKey: todayKey\n"))

        // The list board: the page hands its observed day to the panel, the panel to every column,
        // the column to both of its card builds (open and finished).
        let support = try Self.code("Cadence/iOS/iOSListSupportViews.swift")
        let panel = try #require(CadenceSourceScan.declarationBody("struct iOSListKanbanPanel: View", in: support))
        #expect(panel.contains("let todayKey: String\n"))
        #expect(panel.contains("todayKey: todayKey,\n"))
        let column = try #require(CadenceSourceScan.declarationBody("private struct iOSListKanbanColumn: View", in: support))
        #expect(column.contains("let todayKey: String\n"))
        #expect(CadenceSourceScan.matchCount(#"iOSBoardTaskCard\("#, in: column) == 2)
        #expect(CadenceSourceScan.matchCount(
            #"iOSBoardTaskCard\(task: task, showsContainerChip: false, todayKey: todayKey\)"#, in: column
        ) == 2)
        let page = try Self.code("Cadence/iOS/iOSListDetailView.swift")
        let call = try #require(page.range(of: "iOSListKanbanPanel("), "the list page draws no board")
        #expect(page[call.upperBound...].prefix(1_500).contains("todayKey: observedDay.todayKey,"))

        // The Calendar Board's day column, both builds (lane and finished footer), with the
        // column's observed day.
        let board = try Self.code("Cadence/iOS/iOSCalendarBoardView.swift")
        let day = try #require(CadenceSourceScan.declarationBody("private struct iOSCalendarBoardDayColumn: View", in: board))
        #expect(CadenceSourceScan.matchCount(#"iOSBoardTaskCard\("#, in: day) == 2)
        #expect(CadenceSourceScan.matchCount(
            #"iOSBoardTaskCard\(\s*task: task,\s*dayAlreadyStatedBySurface: dateKey,\s*todayKey: todayKey\s*\)"#, in: day
        ) == 2)

        // And no other build of the card anywhere in the iOS tree.
        #expect(CadenceSourceScan.matchCount(#"iOSBoardTaskCard\("#, in: support + board) == 4)
    }

    /// The chips the touch card draws, with `dateChipsArePickers: false` as it passes it, answer
    /// against the HANDED day: a task due on the literal day is neutral that day and urgent the
    /// next, and a task planned for it is amber that day and red the next.
    @Test func theTouchCardsChipsTurnWithTheHandedDay() {
        let due = task(due: "2019-03-05")
        func dueEmphasis(_ today: String) -> CadenceBoardCardChip.Emphasis? {
            CadenceBoardCardMetadata.chips(
                for: due, showsContainer: false, dateChipsArePickers: false, todayKey: today
            ).first { $0.kind == .dueDate }?.emphasis
        }
        #expect(dueEmphasis("2019-03-05") == .neutral)
        #expect(dueEmphasis("2019-03-06") == .urgent)

        let planned = task(scheduled: "2019-03-05")
        func doEmphasis(_ today: String) -> CadenceBoardCardChip.Emphasis? {
            CadenceBoardCardMetadata.chips(
                for: planned, showsContainer: false, dateChipsArePickers: false, todayKey: today
            ).first { $0.kind == .doDate }?.emphasis
        }
        #expect(doEmphasis("2019-03-05") == .attention)
        #expect(doEmphasis("2019-03-06") == .urgent)
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
        // Both section kinds, and the Apple Reminders section ([[T-14354]]).
        #expect(CadenceSourceScan.matchCount(#"\n\s+todayKey: todayKey,"#, in: body) == 3)
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
            "struct TaskNoteListRow: View", in: try Self.code("Cadence/Shared/CadenceNoteFolderSupport.swift")
        ))
        #expect(row.contains("let todayKey: String"))
        #expect(!row.contains("DateFormatters.todayKey()"))

        // [[T-8535]]: the iOS column draws the same row, handed its own page's observed day.
        let ios = try #require(CadenceSourceScan.declarationBody(
            "private var taskNoteSection: some View", in: try Self.code("Cadence/iOS/iOSListNotesView.swift")
        ))
        #expect(ios.contains("TaskNoteListRow("))
        #expect(ios.contains("todayKey: observedDay.todayKey"))
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

    /// [[T-14411]]: the daily and weekly rows say "Today" / "This Week" against the day they are
    /// HANDED, never the clock. Every key here is a literal years away from the real date, so a
    /// row that read `DateFormatters.todayKey()` / `currentWeekKey()` instead answers wrongly on
    /// both sides of the pair.
    @Test func theDailyAndWeeklyNoteRowsAnswerAgainstTheHandedDay() {
        let note = Note(kind: .daily, title: "2019-03-05", dateKey: "2019-03-05")
        #expect(DailyNoteListRow(note: note, isSelected: false, todayKey: "2019-03-05").isToday)
        #expect(!DailyNoteListRow(note: note, isSelected: false, todayKey: "2019-03-06").isToday)

        let weekKey = DateFormatters.weekKey(from: DateFormatters.date(from: "2019-03-05")!)
        let weekly = Note(kind: .weekly, title: weekKey, weekKey: weekKey)
        // Any day of that week names it; the next Monday's week does not.
        #expect(WeeklyNoteListRow(note: weekly, isSelected: false, todayKey: "2019-03-05").isThisWeek)
        #expect(WeeklyNoteListRow(note: weekly, isSelected: false, todayKey: "2019-03-07").isThisWeek)
        let nextWeek = DateFormatters.date(from: "2019-03-05")!.addingTimeInterval(7 * 86_400)
        #expect(!WeeklyNoteListRow(
            note: weekly, isSelected: false, todayKey: DateFormatters.dateKey(from: nextWeek)
        ).isThisWeek)
    }

    /// ...and every host hands them its observed day: the two Mac pages and the iOS list, at all
    /// four call sites, with no clock read left in either row.
    @Test func theNotesListRowsTakeTheHostsObservedDay() throws {
        let support = try Self.code("Cadence/Shared/CadenceNotesListSupport.swift")
        let daily = try #require(CadenceSourceScan.declarationBody("struct DailyNoteListRow: View", in: support))
        let weekly = try #require(CadenceSourceScan.declarationBody("struct WeeklyNoteListRow: View", in: support))
        for row in [daily, weekly] {
            #expect(row.contains("let todayKey: String"))
            #expect(!row.contains("DateFormatters.todayKey()"))
            #expect(!row.contains("currentWeekKey()"))
        }

        let mac = try Self.code("Cadence/macOS/Views/NotesView.swift")
        let dailyPage = try #require(CadenceSourceScan.declarationBody("private struct DailyNotesPage: View", in: mac))
        #expect(dailyPage.contains("DailyNoteListRow(note: note, isSelected: selectedNoteID == note.id, todayKey: observedDay.todayKey)"))
        let weeklyPage = try #require(CadenceSourceScan.declarationBody("private struct WeeklyNotesPage: View", in: mac))
        #expect(weeklyPage.contains("WeeklyNoteListRow(note: note, isSelected: selectedNoteID == note.id, todayKey: observedDay.todayKey)"))

        let ios = try #require(CadenceSourceScan.declarationBody(
            "struct iOSNotesView: View", in: try Self.code("Cadence/iOS/iOSNotesView.swift")
        ))
        #expect(ios.contains("DailyNoteListRow(note: note, isSelected: isSelected(note), todayKey: observedDay.todayKey,"))
        #expect(ios.contains("WeeklyNoteListRow(note: note, isSelected: isSelected(note), todayKey: observedDay.todayKey,"))
    }
}
#endif
