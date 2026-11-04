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

/// The list Kanban tab's columns, decided where `CadenceTests` can see it ([[T-7033]]).
///
/// The iOS board used to branch on `tasks.isEmpty`, so a list whose tasks were all done (or that
/// had none yet) showed an empty panel instead of its configured columns — and with them went the
/// column headers, which are the `+` drop targets, and any way to start a board. macOS's
/// `ListSectionsKanbanView` draws every configured column whatever it holds. This is that rule:
/// every column, filled or not, and the board is drawn whenever there is a column to draw.
enum ListDetailKanbanBoard {
    static func columns(tasks: [AppTask], sectionNames: [String]) -> [CadenceTaskDisplayGroup] {
        CadenceTaskQuerySupport.sectionGroups(
            from: tasks,
            sectionNames: sectionNames,
            includingEmpty: true
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
        sectionNames: [String]
    ) -> [String: [AppTask]] {
        var byColumn: [String: [AppTask]] = [:]
        for group in CadenceTaskQuerySupport.sectionGroups(
            from: tasks,
            sectionNames: sectionNames,
            includingEmpty: true
        ) where !group.tasks.isEmpty {
            byColumn[group.title] = group.tasks
        }
        return byColumn
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

    /// The list editor's two due-date toggles, plural because each governs every row (iOS's
    /// spelling; the Mac's create and edit sheets read "due date").
    static let hideEmptyTaskDueDatesToggle = "Hide empty task due dates"
    static let hideEmptyColumnDueDatesToggle = "Hide empty column due dates"

    /// The list editors' name placeholders, with no ellipsis on a single-line field
    /// ([[T-10006]]).
    static let areaNamePlaceholder = "Area name"
    static let projectNamePlaceholder = "Project name"
}
