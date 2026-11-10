import Foundation

/// The tabs a list (area or project) detail page is made of, on both platforms.
///
/// There used to be two of these: this one under `macOS/Views/ListDetailView.swift` and an
/// `iOSListDetailPage` under `iOS/`, identical apart from the spelling of the Notes case — and they
/// had already drifted. macOS deleted its Planning tab when the Calendar Board absorbed the
/// Planning page's bucketing, drag-to-reschedule and "N unscheduled · N overdue" summary; iOS kept
/// showing a Planning tab long after. One enum is what stops that happening again.
///
/// It lives in `Shared/` for a second reason as well: `Cadence/iOS/` is entirely inside
/// `#if os(iOS)` and therefore invisible to `CadenceTests`, which builds for macOS, so a resolution
/// rule declared there could not be pinned by a test.
enum ListDetailPage: String, CaseIterable, Identifiable, Hashable {
    case tasks     = "Tasks"
    case kanban    = "Kanban"
    case documents = "Notes"
    case links     = "Links"
    case completed = "Completed"

    var id: String { rawValue }

    static let defaultPage: ListDetailPage = .tasks

    /// Persisted raw values outlive the tabs they name, and "Planning" is the live example: it is a
    /// stored value on disk (and in the Settings default-page preference) naming a page that exists
    /// on neither platform any more. Resolve anything unrecognised to Tasks, so a stale preference
    /// lands on a real page instead of leaving the detail pane blank and every pill unhighlighted.
    ///
    /// Read every persisted page value through here — `init(rawValue:)` returns `nil` for exactly
    /// the cases this exists to handle.
    static func resolved(_ rawValue: String) -> ListDetailPage {
        ListDetailPage(rawValue: rawValue) ?? defaultPage
    }

    /// The page a list opens on: its own remembered tab when it has one, the user's global
    /// default when it does not.
    ///
    /// **The stale case belongs to the list, not to the default.** macOS's restore used to read
    /// the per-list value through the failable `init(rawValue:)` and, when that returned `nil`,
    /// throw the value away and fall back to `resolved(defaultPageRawValue)`. So a list still
    /// holding `Planning` — the value `ListDetailPageTests` documents as live on disk — opened on
    /// **Links** if that was the global default, rather than on Tasks. A stale remembered tab is
    /// an unrecognised page name, which is exactly what `resolved(_:)` exists to map to Tasks;
    /// it is not evidence that the user wanted their global default for this list. T-351.
    static func rememberedPage(storedRawValue: String?, defaultPageRawValue: String) -> ListDetailPage {
        guard let storedRawValue, !storedRawValue.isEmpty else {
            return resolved(defaultPageRawValue)
        }
        return resolved(storedRawValue)
    }

    /// The defaults key a list's remembered tab is stored under — one per area or project, the
    /// same strings macOS has always written, so a list keeps its tab across the switch to Shared.
    ///
    /// T-7032: iOS had no per-list tab at all. Its `selectedPage` was one `@State` for the whole
    /// detail view, and on iPad that view is *updated* rather than rebuilt when the sidebar moves
    /// to another list, so list B opened on whatever tab list A was left on.
    static func rememberedPageDefaultsKey(areaID: UUID?, projectID: UUID?) -> String {
        if let areaID { return "listDetailTab.area.\(areaID.uuidString)" }
        if let projectID { return "listDetailTab.project.\(projectID.uuidString)" }
        return "listDetailTab.unknown"
    }

    /// The tab a detail page shows: the reader's own pick if it was made **on this list**, else the
    /// list's remembered tab, else the global default.
    ///
    /// The pick is tagged with the list it was made on (`choiceListKey`) because the view that
    /// holds it can outlive the list — iPad's sidebar swaps lists under one live view — and a pick
    /// made on list A is not a pick for list B. T-7032.
    static func displayedPage(
        choice: ListDetailPage?,
        choiceListKey: String?,
        listKey: String,
        storedRawValue: String?,
        defaultPageRawValue: String
    ) -> ListDetailPage {
        if let choice, choiceListKey == listKey { return choice }
        return rememberedPage(storedRawValue: storedRawValue, defaultPageRawValue: defaultPageRawValue)
    }

    /// What VoiceOver reads for a tab in the iOS strip: the name, and the count drawn beside it
    /// when one is drawn. `.accessibilityLabel` replaces the label, so passing the bare name used
    /// to drop the count (T-7032).
    func tabAccessibilityLabel(count: Int?) -> String {
        guard let count, count > 0 else { return rawValue }
        return "\(rawValue), \(count)"
    }

    /// The tab bars themselves are text-only; this is used by the Settings "default list page"
    /// picker.
    var icon: String {
        switch self {
        case .tasks:     return "checkmark.square"
        case .kanban:    return "square.grid.3x2"
        case .documents: return "doc.text"
        case .links:     return "link"
        case .completed: return "list.bullet.clipboard"
        }
    }
}

/// The geometry of the iOS list-detail tab strip (`Tasks / Kanban / Notes / Links / Completed`).
///
/// **T-6985: the strip overran an iPhone once its counts showed.** At 12 pt of padding either side
/// of every tab the five labels need ~356 pt bare and ~419 pt with two-digit counts beside Tasks,
/// Kanban and Completed (SF 13 pt, measured), against 369 pt on a 393 pt iPhone after the host's
/// 12 pt gutters. It sat in a horizontal scroll view with its indicator hidden, so "Completed" was
/// cut off at the right edge with nothing saying the row moved.
///
/// So the strip now tries these paddings in order and takes the first at which every tab fits
/// (`ViewThatFits`); only past the tightest does it scroll, and then it says so with an edge fade
/// and keeps the selected tab in view. Here, in `Shared/`, rather than in the iOS view, because
/// `Cadence/iOS/` is invisible to the macOS-hosted test target and the tiers are the decision —
/// `CadenceListDetailTabStripFitTests` prices them against measured label widths.
enum ListDetailTabStripMetrics {
    /// Horizontal padding either side of each tab's label, loosest first.
    static let horizontalPaddingTiers: [CGFloat] = [12, 8, 6]
    /// Between adjacent tabs.
    static let tabSpacing: CGFloat = 2
    /// Between a tab's label and its count.
    static let labelCountSpacing: CGFloat = 6
    /// The strip's own inset either side, inside the scroll content.
    static let stripInset: CGFloat = 1
    /// No tab narrower than a touch target, whatever the tier. "Links" sits right at it at 6 pt.
    static let minimumTabWidth: CGFloat = 44

    /// The width the strip needs, given each tab's content width (label, plus spacing and count
    /// where one shows) and a padding tier. The same sum `ViewThatFits` makes of the real views.
    static func stripWidth(contentWidths: [CGFloat], horizontalPadding: CGFloat) -> CGFloat {
        let tabs = contentWidths.map { max($0 + horizontalPadding * 2, minimumTabWidth) }
        return tabs.reduce(0, +)
            + tabSpacing * CGFloat(max(contentWidths.count - 1, 0))
            + stripInset * 2
    }
}

/// **Which column a LIVE list board draws a card under, on both platforms** ([[T-11222]] (b)).
///
/// A task can name a column the list no longer draws live. Archiving a column cancels its open
/// work, but nothing stops that work being reopened afterwards -- a reopen is `markTodo`, which
/// leaves `sectionName` alone -- so an open task in an archived column is one tap away; a column
/// deleted on one device while another files a task into it is the sync-borne case. The two boards
/// disagreed about such a task: iOS appended a column for its name, so the archived column came
/// back on the live board; the Mac matched configured live columns only, so the task sat on no
/// column and could not be seen. One rule now (keeper decision recorded in [[T-12120]], one app
/// on two platforms per [[T-8201]]): **it is drawn under Default.**
///
/// - **Display only.** Nothing is written to the task; reading this never re-files anything.
///   Only a gesture -- a drop, an edit -- moves a task.
/// - **A finished card of an ARCHIVED column stays with that column**, which the Show Archived
///   board draws with its finished half. Filing it under Default would pour every archived
///   column's wound-down work into Default's Completed count. A finished card whose column is not
///   configured at all has nowhere else to be seen, so it joins Default like an open one.
/// - **Live boards only.** The Show Archived board draws archived columns and no Default, so it
///   passes no filing and matches by the task's own name, as before.
///
/// `nil` when the list configures no live column, which only a caller with no list can hand it
/// (`normalizedSectionConfigs` always keeps a live Default): there is no Default to file under.
struct ListBoardCardFiling: Equatable {
    let liveColumnNames: [String]
    let archivedColumnNames: [String]

    init?(configs: [TaskSectionConfig]) {
        let live = configs.filter { !$0.isArchived }.map(\.name)
        guard !live.isEmpty else { return nil }
        liveColumnNames = live
        archivedColumnNames = configs.filter(\.isArchived).map(\.name)
    }

    /// The section name the live board files `task` under: its own, when a live column has that
    /// name (case-insensitively, as every board matches); otherwise Default, except a finished
    /// card whose name is an archived column's.
    func sectionName(for task: AppTask) -> String {
        let name = task.resolvedSectionName
        if Self.contains(liveColumnNames, name) { return name }
        if CadenceTaskQuerySupport.isFinishedTask(task), Self.contains(archivedColumnNames, name) {
            return name
        }
        return TaskSectionDefaults.defaultName
    }

    private static func contains(_ names: [String], _ name: String) -> Bool {
        names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// The list Kanban tab's columns, decided where `CadenceTests` can see it ([[T-7033]]).
///
/// The iOS board used to branch on `tasks.isEmpty`, so a list whose tasks were all done (or that
/// had none yet) showed an empty panel instead of its configured columns — and with them went the
/// column headers, which are the `+` drop targets, and any way to start a board. macOS's
/// `ListSectionsKanbanView` draws every configured column whatever it holds. This is that rule:
/// every column, filled or not, and the board is drawn whenever there is a column to draw.
enum ListDetailKanbanBoard {
    /// `filing` is the live board's rule for a card whose section names no live column
    /// (`ListBoardCardFiling`); `nil` matches every card by its own section name.
    static func columns(
        tasks: [AppTask],
        sectionNames: [String],
        filing: ListBoardCardFiling? = nil
    ) -> [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.sectionGroups(
            from: tasks,
            sectionNames: sectionNames,
            includingEmpty: true,
            filing: filing
        )
    }

    /// **The FINISHED cards each column closes with, bucketed by the same rule as the open ones**
    /// ([[T-9837]]).
    ///
    /// The iOS list board was handed `activeTasks` only, so a column whose work was all done read
    /// "0" and empty on an iPad while the Mac's `ListSectionKanbanColumn` showed it behind a
    /// `KanbanCompletedTasksToggle`. The candidate reason -- "the iOS list page has its own
    /// Completed tab" -- is not a hardware or input reason, and the Mac list page has finished
    /// work in more than one place too, so under [[T-8201]] it was drift.
    ///
    /// It is the SAME `sectionGroups` call `columns(tasks:sectionNames:)` makes, over the finished
    /// half instead of the open one, rather than a second bucketing rule: a column's open cards and
    /// its finished ones must agree about which section a task is in, including the
    /// case-insensitive match and the fallback for a section a list no longer configures. Returned
    /// keyed by the column title `columns(...)` produces, so a caller cannot mismatch them.
    ///
    /// `isFinishedTask`, through `CadenceTaskQuerySupport.completedTasks`, not `isDone`: a
    /// CANCELLED task is finished and `!$0.isDone` would file it among the work you still intend
    /// to do. That is the T-147 / T-203 / T-342 / T-381 shape, and
    /// `KanbanBoardSupport.columnHalves` records it for the Mac's own split.
    static func completedTasksByColumn(
        tasks: [AppTask],
        sectionNames: [String],
        filing: ListBoardCardFiling? = nil
    ) -> [String: [AppTask]] {
        var byColumn: [String: [AppTask]] = [:]
        for group in CadenceTaskQuerySupport.sectionGroups(
            from: tasks,
            sectionNames: sectionNames,
            includingEmpty: true,
            filing: filing
        ) where !group.tasks.isEmpty {
            byColumn[group.title] = group.tasks
        }
        return byColumn
    }

    /// **Every card a list board drop may name: the open cards AND the finished ones behind each
    /// column's Completed toggle** ([[T-15620]]).
    ///
    /// [[T-9837]] gave the iOS column the Mac's Completed footer and made its finished cards
    /// `.draggable`, but the board still checked a payload against the OPEN cards only, so a
    /// finished card lifted, was carried to another column, and snapped back with nothing written.
    /// The Mac's `ListSectionKanbanColumn` checks against the list's whole task set
    /// (`universeTasks`, finished cards included), so the same drag moves the card there. Being
    /// able to lift a card is not a hardware or input reason for refusing to set it down
    /// ([[T-8201]]).
    static func droppableCards(open: [AppTask], finished: [AppTask]) -> [AppTask] {
        open + finished
    }

    /// **The cards a drop into one column is ordered among: the column's open cards AND its
    /// finished ones** ([[T-15622]]).
    ///
    /// `CadenceKanbanCardDrop.drop` puts a card dropped `before:` a target in front of that target
    /// only if the target is in `columnTasks`; a target it cannot find sends the card to the end.
    /// The iOS board handed it the column's OPEN cards, so once a finished card behind the Completed
    /// toggle took a drop, the card would still land at the column's end. The Mac's
    /// `ListSectionKanbanColumn.moveTask` orders among the column's whole `tasks`, finished cards
    /// included, so a card dropped on a finished one lands in front of it there ([[T-8201]]).
    static func dropColumnCards(open: [AppTask], finished: [AppTask]) -> [AppTask] {
        open + finished
    }

    /// **Which configured columns the list board draws, on both platforms** ([[T-8565]]).
    ///
    /// The Mac's Kanban tab has a "Show Archived" pill (`showArchivedKanbanColumns`) that swaps the
    /// board to the list's ARCHIVED columns and back; iOS had no such control, so an archived
    /// column was reachable on iPhone and iPad only as a row in the list editor. A toggle is not
    /// pointer- or width-shaped, so under [[T-8201]] that was drift. One rule for both boards:
    /// off draws the live columns, on draws the archived ones and only those.
    static func visibleSectionConfigs(
        _ configs: [TaskSectionConfig],
        showArchived: Bool
    ) -> [TaskSectionConfig] {
        configs.filter { $0.isArchived == showArchived }
    }

    /// The "Show Archived" control's words and glyph, one spelling for both boards ([[T-8565]]).
    /// The label shortens to "Archived" while on, one of the four neutral cues the Mac pill uses
    /// for its "on" state instead of an accent.
    enum ArchivedColumnsToggle {
        static func title(showingArchived: Bool) -> String {
            showingArchived ? "Archived" : "Show Archived"
        }

        static func systemImage(showingArchived: Bool) -> String {
            showingArchived ? "archivebox.fill" : "archivebox"
        }

        static func accessibilityLabel(showingArchived: Bool) -> String {
            showingArchived ? "Hide archived columns" : "Show archived columns"
        }
    }

    /// The empty panel stands in only when the list has no column at all (every section archived).
    /// An open-task count is not the question: an empty column is a place to put work.
    static func drawsColumns(_ columns: [CadenceTaskDisplayGroup]) -> Bool {
        !columns.isEmpty
    }

    /// What a column's "Add task" row opens the composer with: the column's list **and** section
    /// ([[T-8184]]). It is the seed a `+` dragged onto the same column's header commits — the
    /// column's own drop identity resolved through `CadenceTaskDropSupport` — so the two ways of
    /// adding to a column cannot file the task in different places. macOS's section columns seed
    /// the same pair through `InlineTaskComposerSurface.column(container:sectionName:)`.
    static func addTaskSeed(
        for identity: CadenceTaskGroupDropIdentity,
        todayKey: String = DateFormatters.todayKey()
    ) -> CadenceTaskComposerSeed {
        CadenceTaskDropSupport.seed(
            forDropKey: CadenceTaskDropSupport.dropKey(forGroup: identity) ?? "",
            todayKey: todayKey
        )
    }
}

/// What a list page's header chips say to VoiceOver ([[T-7080]]).
///
/// The project deadline chip is a calendar glyph and a bare "Oct 30". iOS labelled it "Deadline
/// Oct 30" ([[T-3091]]); the Mac header drew the same chip unlabelled, so VoiceOver read a date
/// with nothing to say whose date it was. One spelling, read by both headers.
enum ListDetailHeaderAccessibility {
    static func deadlineLabel(dueDate: String) -> String {
        "Deadline \(DateFormatters.shortDateString(from: dueDate))"
    }

    /// The header's edit control, named for the list it edits ([[T-8563]] (e)). iOS said a bare
    /// "Edit list" and the Mac "Edit <name>"; the one that names the list is strictly more use to
    /// VoiceOver, so both read this. A blank name reads the header's own fallback title.
    static func editLabel(listName: String) -> String {
        "Edit \(TaskTitleSupport.displayTitle(listName, fallback: TaskTitleSupport.defaultCompactDisplayTitle))"
    }

    /// The header's edit control's glyph, drawn by both headers in the list's own colour
    /// ([[T-12602]], under [[T-8201]]). iOS drew `slider.horizontal.3` in plain text colour, a
    /// glyph that reads as "view options" elsewhere; the pencil is both platforms' edit glyph
    /// (Settings > Tags' per-row edit), and the Mac's header already drew it.
    static let editGlyph = "pencil"
}

/// The list surfaces' small words, one spelling on both platforms ([[T-8563]]).
///
/// Each of these was spelled two ways across iOS and macOS with no hardware constraint behind
/// either, and each spelling below is the owner's decision of 2026-11-02.
nonisolated enum CadenceListVocabularyCopy {
    /// The confirm of the New List and New Context sheets. iOS said "Save", which belongs to the
    /// edit sheets; a creation sheet names what it does, as the Mac's always has.
    static let createActionTitle = "Create"

    /// Bringing an archived list, context or tag back. iOS's Lists page alone said "Restore";
    /// Settings > Lists on both platforms already said "Unarchive". [[T-10571]]: archived
    /// contexts and tags said "Restore" on both platforms, so one action had two verbs by object
    /// type; its opposite is "Archive" everywhere. Backup restore and the cancelled-task undo keep
    /// "Restore" -- they are different actions.
    static let unarchiveActionTitle = "Unarchive"

    /// The tag-completion rows' subtitle under an archived tag: picking it unarchives it.
    static let unarchiveTagSubtitle = "\(unarchiveActionTitle) tag"

    /// The tag picker's row offering an archived tag that matches the query.
    static func unarchiveRowTitle(name: String) -> String {
        "\(unarchiveActionTitle) \"\(name)\""
    }

    /// The list editor's two due-date toggles, plural because each governs every card or column
    /// (iOS's spelling; the Mac's create and edit sheets read "due date").
    ///
    /// **[[T-14582]]: the task half is named for what it controls.** `hideDueDateIfEmpty` has one
    /// reader, the Mac board card's empty "Due" token (`KanbanCard`, via
    /// `AppTask.shouldShowDueDateField`); no task row on either platform reads it, so "task due
    /// dates" promised more than the switch does.
    static let hideEmptyTaskDueDatesToggle = "Hide empty due dates on board cards"
    static let hideEmptyColumnDueDatesToggle = "Hide empty column due dates"
    /// The caption under that switch in the iOS editor, which offers it because the field set is
    /// one union on both platforms ([[T-8562]]) and the flag syncs to the Mac. The touch board card
    /// draws no empty token at all -- its tokens are labels, not pickers (`iOSBoardTaskCard.tokens`),
    /// an input difference under [[T-8201]] -- so on iPhone and iPad the switch changes nothing on
    /// screen, and the caption says where it does.
    static let hideEmptyTaskDueDatesTouchCaption = "Applies to board cards on Mac."

    /// The name of a project's due-date row and a kanban column's due-date row, in every list
    /// editor on both platforms ([[T-13221]], under [[T-8201]]). One field had three names: "Due"
    /// in the Mac's list sheets, "Due Date" in the Mac column popover, "Due date" in both iOS
    /// editor rows -- no hardware makes a label differ. Sentence case, the iOS spelling and the
    /// field's accessibility name (`CadenceTaskControlAccessibility.dueDate`); it reads above or
    /// beside `CadenceBoardColumnDueDatePlan.emptyLabel` ("No due date") in all four.
    static let dueDateFieldLabel = "Due date"

    /// The list editors' name placeholders, with no ellipsis on a single-line field
    /// ([[T-10006]]).
    static let areaNamePlaceholder = "Area name"
    static let projectNamePlaceholder = "Project name"

    /// What each list type is for, under the New List type choice ([[T-12711]], under [[T-8201]]).
    /// The Mac's type cards always carried these two lines; the phone's Area/Project segment drew
    /// the two bare words, so a new user picked a type with nothing saying what either meant. No
    /// hardware constraint was behind the gap: the line fits under the segment on an iPhone.
    static let areaTypeDescription = "Ongoing responsibility, no end date"
    static let projectTypeDescription = "Finite effort with a clear outcome"

    static func listTypeDescription(isProject: Bool) -> String {
        isProject ? projectTypeDescription : areaTypeDescription
    }
}
