// macOS only: the Cmd+K palette and its support types do not exist in the iOS build.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-14014]] — Return in Cmd+K resolves against the query in the field.**
///
/// The palette commits what is typed only after a 40 ms debounce, and Return used to read the rows
/// and highlight of whatever had last been committed — so Return pressed inside that window opened
/// a result of the PREVIOUS query. These drive `GlobalSearchInteractionSupport`'s Return path over
/// real rows built by `GlobalSearchIndexSupport`, with a small model standing in for the view's
/// state: the committed query, and a highlight re-synced on every commit as the view re-syncs it.
@MainActor
struct CadenceGlobalSearchSubmitFlushTests {

    /// The view's state, reduced to what Return reads.
    @MainActor
    private final class PaletteModel {
        let tasks: [AppTask]
        var committedQuery: String
        var highlightedResultID: String?

        init(tasks: [AppTask], committedQuery: String) {
            self.tasks = tasks
            self.committedQuery = committedQuery
        }

        var rows: [GlobalSearchKeyboardRow] {
            let sections = GlobalSearchIndexSupport.buildIndexedSource(
                query: committedQuery.trimmingCharacters(in: .whitespacesAndNewlines),
                hiddenTabs: [],
                areas: [],
                projects: [],
                tasks: tasks,
                notes: [],
                eventResults: [],
                sidebarTabColorsRaw: "",
                includesCompletedTasks: false
            ).sections
            return GlobalSearchOverlayStateSupport.keyboardRows(
                from: GlobalSearchDataSupport.visibleSections(from: sections, expandedCategories: [])
            )
        }

        /// What `GlobalSearchOverlay.setCommittedQuery` does: commit, then keep the highlight on a
        /// row that still exists, else the first.
        func commit(_ query: String) {
            committedQuery = query
            highlightedResultID = GlobalSearchOverlayStateSupport.syncedHighlightID(
                current: highlightedResultID,
                rows: rows
            )
        }
    }

    private func taskID(_ task: AppTask) -> String {
        CadenceSearchIdentity.task(task.id)
    }

    /// The defect itself: "alp" lists both tasks with Alphabet highlighted, the user types "i", and
    /// Return lands before the debounce. It must open Alpine — the only row "alpi" matches — and
    /// not Alphabet, the highlighted row of the query the field no longer holds.
    @Test func returnInsideTheDebounceOpensAResultOfTheTypedQuery() throws {
        let alphabet = AppTask(title: "Alphabet soup")
        let alpine = AppTask(title: "Alpine hike")
        let model = PaletteModel(tasks: [alphabet, alpine], committedQuery: "alp")
        #expect(Set(model.rows.map(\.id)) == [taskID(alphabet), taskID(alpine)])
        model.highlightedResultID = taskID(alphabet)

        // The scheduled commit the debounce is still holding for "alpi".
        var committedByDebounce: [String] = []
        let scheduled = DispatchWorkItem { committedByDebounce.append("alpi") }
        var pending: DispatchWorkItem? = scheduled

        var selected: [String] = []
        var revealed: [String] = []
        GlobalSearchInteractionSupport.submitHighlightedResult(
            draftQuery: "alpi",
            committedQuery: model.committedQuery,
            pendingQueryCommit: &pending,
            commit: model.commit,
            highlightedResultID: { model.highlightedResultID },
            rows: { model.rows },
            onSelect: { selected.append($0.id) },
            onReveal: { revealed.append($0) }
        )

        #expect(selected == [taskID(alpine)])
        #expect(revealed.isEmpty)
        #expect(model.committedQuery == "alpi")
        // The debounce's own commit is cancelled, so the query is not committed a second time.
        #expect(scheduled.isCancelled)
        #expect(pending == nil)
        #expect(committedByDebounce.isEmpty)
    }

    /// With nothing pending, Return is what it always was: the highlighted row of the committed
    /// query, with no commit at all.
    @Test func returnWithNothingPendingOpensTheHighlightedRowWithoutCommitting() throws {
        let alphabet = AppTask(title: "Alphabet soup")
        let alpine = AppTask(title: "Alpine hike")
        let model = PaletteModel(tasks: [alphabet, alpine], committedQuery: "alp")
        model.highlightedResultID = taskID(alphabet)

        var commits: [String] = []
        var pending: DispatchWorkItem?
        var selected: [String] = []
        GlobalSearchInteractionSupport.submitHighlightedResult(
            draftQuery: "alp",
            committedQuery: model.committedQuery,
            pendingQueryCommit: &pending,
            commit: { commits.append($0); model.commit($0) },
            highlightedResultID: { model.highlightedResultID },
            rows: { model.rows },
            onSelect: { selected.append($0.id) },
            onReveal: { _ in }
        )

        #expect(selected == [taskID(alphabet)])
        #expect(commits.isEmpty)
    }
}
#endif
