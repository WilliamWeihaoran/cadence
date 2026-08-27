import Foundation
import SwiftData

/// What a `cadence://task/<uuid>` link should actually do, decided **once, at the root**, against
/// the store.
///
/// The link used to be applied blind: `CadenceDeepLinkManager.handle(_:)` armed `pendingTaskID`
/// and the root sent every `.task` link to Today, on the assumption that Today would render the
/// row and the row would open the inspector and disarm. Today's scope is narrower than that
/// assumption — `CadenceTaskQuerySupport.activeTodayTasks` drops done and cancelled work, and a
/// task dated for another day was never in it — and the id has no owner outside a rendered row, so
/// a widget tap on a task finished elsewhere opened Today, showed nothing, and **left the id
/// armed**. It then fired on whatever unrelated screen next drew that row, which reads as the app
/// opening a task at random. That is the half of this worth fixing; a link that does nothing is
/// merely annoying.
///
/// So: `pendingTaskID` survives resolution only when the destination this returns is known to be
/// showing the task. In the other two cases it is cleared here, and the route carries the whole
/// answer.
///
/// This lives in `Shared/` rather than beside the manager because
/// `Cadence/Services/CadenceDeepLink.swift` is compiled into `CadenceWidgets`, which does not
/// build `CadenceTaskQuerySupport`; and because `Cadence/iOS/` is invisible to `CadenceTests`.
enum CadenceDeepLinkResolutionSupport {
    /// Why a task link resolved the way it did. Carried alongside the destination so a test can
    /// tell "routed to Today because the task is on Today" from "routed to Today because there is
    /// no such task" — two outcomes that share a destination and differ in everything else.
    enum TaskLinkOutcome: Equatable {
        /// No row with this id exists any more: deleted, or never synced down.
        case missing
        /// The task exists and Today lists it, so Today's row can open the inspector.
        case todayVisible
        /// The task exists and Today does not list it — done, cancelled, or dated for another day.
        case outsideToday
    }

    struct TaskLinkResolution: Equatable {
        var outcome: TaskLinkOutcome
        /// Where the root should navigate.
        var destination: CadenceFeatureDestination
        /// What `pendingTaskID` should be after resolution. `nil` means disarm.
        var pendingTaskID: UUID?
    }

    /// Whether Today would list this task, asked of the predicate Today actually runs rather than
    /// re-spelled here. `activeTodayTasks` is the one that decides — a second copy of "not done,
    /// not cancelled, due or do-dated today or earlier" is exactly the drift this ticket is about.
    static func todayShows(_ task: AppTask, todayKey: String) -> Bool {
        !CadenceTaskQuerySupport.activeTodayTasks(
            from: [task],
            todayKey: todayKey,
            sortMode: .listOrder
        ).isEmpty
    }

    /// **All Tasks is the fallback**, not the task's own list.
    ///
    /// Both were on the table. All Tasks wins on one hard constraint and one soft one. The hard
    /// one: `CadenceCompactRoute.pushedDestination` is a `CadenceFeatureDestination`, which has no
    /// case carrying a container id, so "open list X" is not currently expressible in the compact
    /// shell's route grammar — routing there would mean widening that grammar in a ticket about
    /// deep-link arming. The soft one: a task with no list has no "own list" but does have an All
    /// Tasks row, and All Tasks exists on both platforms' sidebars under one name.
    ///
    /// A missing task keeps Today, which is where a bare `cadence://today` goes: the link named a
    /// task that is gone, and All Tasks would be a page opened to show a row that is not on it.
    static func resolveTaskLink(id: UUID, task: AppTask?, todayKey: String) -> TaskLinkResolution {
        guard let task else {
            return TaskLinkResolution(outcome: .missing, destination: .today, pendingTaskID: nil)
        }
        guard todayShows(task, todayKey: todayKey) else {
            return TaskLinkResolution(outcome: .outsideToday, destination: .allTasks, pendingTaskID: nil)
        }
        return TaskLinkResolution(outcome: .todayVisible, destination: .today, pendingTaskID: id)
    }

    /// One row by id, or `nil`. A fetch rather than a `@Query`: `macOSRootView` deliberately keeps
    /// unbounded task queries off the root (see `NotificationReconcileObserver`), and a deep link
    /// needs one row on one tap, not an observed collection.
    static func task(with id: UUID, in modelContext: ModelContext) -> AppTask? {
        var descriptor = FetchDescriptor<AppTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}

extension CadenceDeepLinkManager {
    /// The destination a route should open, having first resolved any `.task` payload against the
    /// store and settled `pendingTaskID`.
    ///
    /// Both roots call this instead of reading `deepLink.featureDestination` directly, so neither
    /// can route a task link to a page that will not show it.
    @discardableResult
    func resolvedDestination(
        for deepLink: CadenceDeepLink,
        modelContext: ModelContext,
        todayKey: String = DateFormatters.todayKey()
    ) -> CadenceFeatureDestination {
        guard case .task(let id) = deepLink else { return deepLink.featureDestination }
        let resolution = CadenceDeepLinkResolutionSupport.resolveTaskLink(
            id: id,
            task: CadenceDeepLinkResolutionSupport.task(with: id, in: modelContext),
            todayKey: todayKey
        )
        // Only this link's own arm is touched. A newer link that landed between `handle(_:)` and
        // here owns `pendingTaskID`, and disarming it would be the same bug pointed the other way.
        if pendingTaskID == id {
            pendingTaskID = resolution.pendingTaskID
        }
        return resolution.destination
    }
}
