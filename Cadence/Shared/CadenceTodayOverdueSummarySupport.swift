import Foundation

// `CadenceTodayOverdueSummarySupport` was here — the past-due derivation (the list and section
// walks, the two open-request hops and the two heading strings) — and it is gone (T-3078): with
// both platforms' past-due bands removed in T-3076, and the two macOS overdue-summary hops in
// `TasksPanelSupport` with them, nothing in the product derived or opened a summary any more.
//
// **What is left is held, not forgotten.** The two summary types below are still the inputs of
// `CadenceTodayOverdueListCard` / `CadenceTodayOverdueSectionCard`, and `CadenceListOpenRequest`
// is still what `iOSTodayView`'s `.sheet(item: $pendingListOpen)` presents. Those cards and that
// presenter have no caller either, but `CadenceCodexTaskSummaryTypographyTests` and
// `CadenceCodexPageCompletionTypographyTests` pin them and sit under the Codex lease, so their
// deletion — and with it this file's — waits on that lease (T-3078's remainder).

/// A project whose own due date has gone by.
///
/// The colour is carried as the list's `colorHex` rather than as a resolved `Color`: it is a
/// user-owned palette value. The card resolves it.
struct CadenceTodayOverdueListSummary: Identifiable, Equatable {
    let id: String
    let areaID: UUID?
    let projectID: UUID?
    let title: String
    let icon: String
    let colorHex: String
    let dueDateKey: String
    let activeTaskCount: Int
}

/// A kanban column whose due date has gone by, and the list it belongs to.
struct CadenceTodayOverdueSectionSummary: Identifiable, Equatable {
    let id: String
    let areaID: UUID?
    let projectID: UUID?
    let sectionName: String
    let parentName: String
    let parentIcon: String
    let parentColorHex: String
    let dueDateKey: String
    let openTaskCount: Int
    let completedTaskCount: Int
}

/// Which list to open, at which page, with which column brought into view.
///
/// **This is the decision; the transport is the platform-shaped half.** macOS says it with
/// `ListNavigationManager` — a shell-level router whose request the sidebar and `ListDetailView`
/// consume — and that manager is macOS-only. iOS has no equivalent and deliberately does not grow
/// one: its presenter is `iOSTodayOverdueListSheet`.
///
/// The target is a `Target` rather than a bare `UUID` for the same reason `CadenceFocusTarget` is:
/// an area and a project with equal ids are different destinations.
nonisolated struct CadenceListOpenRequest: Equatable, Identifiable {
    enum Target: Equatable {
        case area(UUID)
        case project(UUID)
    }

    var target: Target
    var page: ListDetailPage
    /// Only ever set alongside `.kanban`: a column is a thing the board draws, and no other page
    /// has anywhere to put a highlight.
    var sectionName: String?

    /// Derived from the request's own members rather than a fresh token, so `.sheet(item:)` treats
    /// two taps on the same card as the same presentation. A token would be right if this were an
    /// inbox something else consumed — `CadenceFocusHandoff` carries one for exactly that reason —
    /// and it is wrong here, where the request *is* the sheet's subject.
    var id: String {
        let targetID: String
        switch target {
        case .area(let uuid): targetID = "area-\(uuid.uuidString)"
        case .project(let uuid): targetID = "project-\(uuid.uuidString)"
        }
        return "\(targetID)|\(page.rawValue)|\(sectionName ?? "")"
    }
}

