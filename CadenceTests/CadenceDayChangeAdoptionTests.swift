import Foundation
import SwiftData
import Testing
@testable import Cadence

#if os(macOS)
/// T-3120 part (1): every Today surface that reads "today" in its own `body`, and whose host does
/// not hand it the day, observes the day changing itself — the way [[T-3104]] wired `TasksPanel`
/// and `iOSTodayView` (pinned by `CadenceDayChangeSupportTests`).
///
/// A child built with constant arguments, or with inputs that can be equal on both sides of
/// midnight, is not re-evaluated just because its host's body re-ran, so being *under* an
/// observing view is not enough: the timeline panes take no day at all, and the macOS Today header
/// takes only the day's counts.
@MainActor
struct CadenceDayChangeAdoptionTests {
    /// The adopting views, by file and by the declaration whose body installs the observer.
    private static let adopters: [(path: String, declaration: String)] = [
        ("Cadence/macOS/Views/TasksPanel.swift", "struct TasksPanel: View"),
        ("Cadence/iOS/iOSTodayView.swift", "struct iOSTodayView: View"),
        ("Cadence/macOS/Views/SchedulePanel.swift", "struct SchedulePanel: View"),
        ("Cadence/macOS/Views/TasksPanelSupportViews.swift", "struct TasksPanelHeader<Trailing: View>: View"),
        ("Cadence/iOS/iOSTodaySchedulePanel.swift", "struct iOSSchedulePanel: View"),
        ("Cadence/macOS/Views/CalendarPageView.swift", "struct CalendarPageView: View"),
        // T-5011: the always-visible sidebars' Today badge, and the macOS list rows' due flag
        // (their host `ContextSection` holds no day, so each row observes its own).
        ("Cadence/macOS/Views/SidebarView.swift", "struct SidebarView: View"),
        ("Cadence/macOS/Views/SidebarSupportViews.swift", "struct SidebarListRow: View"),
        ("Cadence/iOS/iOSRootSidebar.swift", "struct iOSSidebar: View"),
        ("Cadence/iOS/iOSTasksTabView.swift", "struct iOSTasksTabView: View"),
        // **T-5012 (a)'s two Habits pages left with [[T-5002]]**, which deleted both screens.
        // The observer they installed is still installed by every page below; their absence is
        // pinned by `CadenceCodexTrackingUIRetirementTests.codexRetiredTrackingViewsAreGoneFromTheTree`.
        // T-5010: the iOS Calendar, which hands its key to the timeline, month, agenda and board.
        ("Cadence/iOS/iOSCalendarView.swift", "struct iOSCalendarView: View"),
        // T-5012 (b)-(d): the list pages, both kanban boards, Goals and Notes — one observer per
        // page host, handing its key to every row and card (`CadenceListPagesObservedDayTests`).
        // Goals was one of them until [[T-5002]] deleted the page.
        ("Cadence/macOS/Views/ListDetailComponents.swift", "struct ListTasksView: View"),
        ("Cadence/macOS/Views/TasksListView.swift", "struct TasksListView: View"),
        // [[T-12791]]: a list's Completed tab draws `MacTaskRow`, which takes the day with no
        // default, and its host `ListDetailView` holds none.
        ("Cadence/macOS/Views/ListDetailSupportViews.swift", "struct ListLogView: View"),
        ("Cadence/macOS/Views/KanbanSupportViews.swift", "struct TaskListsKanbanView: View"),
        ("Cadence/macOS/Views/KanbanListSectionSupportViews.swift", "struct ListSectionsKanbanView: View"),
        ("Cadence/macOS/Views/ListNotesView.swift", "struct ListNotesView: View"),
        ("Cadence/macOS/Views/NotesView.swift", "private struct DailyNotesPage: View"),
        ("Cadence/macOS/Views/NotesView.swift", "private struct WeeklyNotesPage: View"),
        ("Cadence/iOS/iOSNotesView.swift", "struct iOSNotesView: View"),
        // [[T-7031]]: the iPad list Notes tab's event-note section drops a meeting once its day
        // is past, the same rule `ListNotesView` reads its own observed day for.
        ("Cadence/iOS/iOSListNotesView.swift", "struct iOSListNotesView: View"),
        // [[T-7983]]: Mac Today's Notes pane, whose Today and This Week tabs are day-keyed notes.
        ("Cadence/macOS/Views/NotePanel.swift", "struct NotePanel: View"),
        // [[T-8731]]: the touch Inbox and All Tasks took the Mac's Group control, and its By Date
        // buckets are measured against today — the same reason `TasksListView` above observes it.
        ("Cadence/iOS/iOSTaskCollectionPage.swift", "struct iOSTaskCollectionPage: View"),
        // [[T-13561]]: a list's touch Tasks tab took the Mac's Group control too, By Date included.
        ("Cadence/iOS/iOSListDetailView.swift", "struct iOSListDetailView: View"),
        // [[T-14351]]: both Focus pages, whose ready list and due words are scored against today
        // and whose idle screens draw nothing else that changes at midnight.
        ("Cadence/macOS/Views/FocusView.swift", "struct FocusView: View"),
        ("Cadence/iOS/iOSFocusView.swift", "struct iOSFocusView: View"),
        // [[T-14352]]: a note's linked-task chips, whose due words and red are measured against
        // today while every input the strip is handed is the same on both sides of midnight.
        ("Cadence/macOS/Views/NoteReferenceSupportViews.swift", "struct NoteReferenceStrip: View"),
        ("Cadence/iOS/iOSMarkdownAccessoryViews.swift", "struct iOSNoteReferencePanel: View"),
    ]

    private static let install = ".cadenceTracksDayChanges($observedDay)"

    /// Equality, not containment: a new adopter is a decision to add here, and a lost one is the
    /// bug this ticket fixed.
    @Test func theProductTreeInstallsTheDayObserverInExactlyTheExpectedFiles() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(files.count > 100, "the sweep read \(files.count) files")

        var installing: Set<String> = []
        for path in files where try read(path).contains(".cadenceTracksDayChanges(") {
            installing.insert(path)
        }
        // The modifier's own declaration is the one non-call site.
        installing.remove("Cadence/Shared/CadenceDayChangeSupport.swift")

        #expect(installing == Set(Self.adopters.map(\.path)))
    }

    /// Each adopter holds its own observed day, reads today through it (so the body depends on the
    /// state the observer writes), never reads the clock's key beside it, and installs the
    /// observer once, in its own body.
    @Test func everyAdopterReadsItsDayThroughTheObserverItInstalls() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        for (path, declaration) in Self.adopters {
            let source = try read(path)
            let view = try #require(CadenceSourceScan.declarationBody(declaration, in: source), "\(path)")
            #expect(view.contains("@State private var observedDay = CadenceObservedDay()"), "\(path)")
            #expect(view.contains("observedDay.todayKey"), "\(path)")
            #expect(view.contains("DateFormatters.todayKey()") == false, "\(path)")

            let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: view), "\(path)")
            #expect(body.components(separatedBy: Self.install).count - 1 == 1, "\(path)")
        }
    }

    /// [[T-7983]]: observing the day is not enough for the Notes pane, whose body draws notes it
    /// resolved once rather than a key it reads each pass. A day change must reload them — through
    /// `refreshFromStore()`, which flushes the editor into the note it was typed into before
    /// swapping — and the reload must resolve against the observed day.
    @Test func theTodayNotesPaneReloadsItsNotesWhenTheDayTurns() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/NotePanel.swift")
        let view = try #require(CadenceSourceScan.declarationBody("struct NotePanel: View", in: source))
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: view))
        let collapsed = body.filter { !$0.isWhitespace }
        #expect(collapsed.contains(".onChange(of:observedDay){_,_inrefreshFromStore()}"))

        let load = try #require(CadenceSourceScan.declarationBody("private func loadOrCreate()", in: view))
        #expect(load.filter { !$0.isWhitespace }.contains("dayKey:observedDay.todayKey"))

        // The reload flushes first, so the pending edit lands in the note it was typed into.
        let refresh = try #require(CadenceSourceScan.declarationBody("private func refreshFromStore()", in: view))
        let flush = try #require(refresh.range(of: "flushPendingEditorContent()"))
        let reload = try #require(refresh.range(of: "loadOrCreate()"))
        #expect(flush.lowerBound < reload.lowerBound)
    }

    /// [[T-14583]]: the Notes Daily and Weekly lists pin the observed period, but only a note that
    /// exists can be pinned -- and each host made the current period's note once, on appear (iOS:
    /// for `selectedDayKey`, which does not move at midnight). So a list left open across midnight
    /// (or a Monday) had no row for the new period. Each host now makes the new period's note when
    /// its observed day turns, through the existing note services, and selects nothing: the
    /// closure assigns no selection and the iOS one leaves `selectedDayKey` alone.
    @Test func theNotesListsMakeTheNewPeriodsNoteWhenTheDayTurnsAndSelectNothing() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let hosts: [(path: String, declaration: String, call: String)] = [
            ("Cadence/macOS/Views/NotesView.swift", "private struct DailyNotesPage: View",
             "createNote(forDateKey:observedDay.todayKey)normalizeSelection()"),
            ("Cadence/macOS/Views/NotesView.swift", "private struct WeeklyNotesPage: View",
             "createNote(forWeekKey:currentWeekKey)normalizeSelection()"),
            ("Cadence/iOS/iOSNotesView.swift", "struct iOSNotesView: View",
             "_=CadenceCoreNoteSupport.loadOrCreateCoreNotes(in:modelContext,dayKey:observedDay.todayKey)"),
        ]
        for host in hosts {
            let view = try #require(CadenceSourceScan.declarationBody(host.declaration, in: try read(host.path)), "\(host.path)")
            let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: view), "\(host.declaration)")
            let collapsed = body.filter { !$0.isWhitespace }
            let opener = ".onChange(of:observedDay){_,_in"
            #expect(collapsed.components(separatedBy: opener).count - 1 == 1, "\(host.declaration)")
            let handler = try #require(collapsed.range(of: opener), "\(host.declaration)")
            let rest = collapsed[handler.upperBound...]
            let closure = try #require(rest.range(of: "}").map { rest[..<$0.lowerBound] }, "\(host.declaration)")
            #expect(closure == Substring(host.call), "\(host.declaration): \(closure)")
            #expect(!closure.contains("selectedNoteID"), "\(host.declaration) selects the new note")
            #expect(!closure.contains("selectedDayKey"), "\(host.declaration) moves the browsed day")
        }

        // The Mac helpers make the note through the store service and never select it.
        let mac = try read("Cadence/macOS/Views/NotesView.swift")
        for (declaration, helper, service) in [
            ("private struct DailyNotesPage: View", "private func createNote(forDateKey key: String)",
             "try NoteMigrationService.dailyNote(for: key, in: modelContext)"),
            ("private struct WeeklyNotesPage: View", "private func createNote(forWeekKey key: String)",
             "try NoteMigrationService.weeklyNote(for: key, in: modelContext)"),
        ] {
            let view = try #require(CadenceSourceScan.declarationBody(declaration, in: mac), "\(declaration)")
            let body = try #require(CadenceSourceScan.declarationBody(helper, in: view), "\(declaration)")
            #expect(body.contains(service), "\(declaration)")
            #expect(!body.contains("selectedNoteID"), "\(declaration) selects the note it makes")
        }
    }

    /// The store half of [[T-14583]], against a throwaway in-memory store: before the new day's note
    /// is made, a list pinned to the new day has no row for it and drops yesterday's blank note; once
    /// the day-change service has run, the new day is listed -- and running it again writes nothing.
    @Test func makingTheNewDaysNoteGivesThePinnedListItsRowAndIsIdempotent() throws {
        let context = ModelContext(try CadenceTestStore.container())
        _ = try NoteMigrationService.dailyNote(for: "2019-03-05", in: context)
        func dailies() throws -> [Note] {
            try context.fetch(FetchDescriptor<Note>()).filter { $0.kind == .daily }.sorted { $0.dateKey > $1.dateKey }
        }
        #expect(NotesListVisibility.dailyNotes(try dailies(), todayKey: "2019-03-06").isEmpty)

        let made = try NoteMigrationService.dailyNote(for: "2019-03-06", in: context)
        #expect(NotesListVisibility.dailyNotes(try dailies(), todayKey: "2019-03-06").map(\.id) == [made.id])
        #expect(try NoteMigrationService.dailyNote(for: "2019-03-06", in: context).id == made.id)
        #expect(try dailies().count == 2)
    }
}
#endif
