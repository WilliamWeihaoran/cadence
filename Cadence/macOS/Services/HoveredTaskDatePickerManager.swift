#if os(macOS)
import SwiftData
import SwiftUI

@Observable
@MainActor
final class HoveredTaskDatePickerManager {
    enum DateKind {
        case doDate
        case dueDate

        var title: String {
            switch self {
            case .doDate: return "Set Do Date"
            case .dueDate: return "Set Due Date"
            }
        }

        var emptyLabel: String {
            switch self {
            case .doDate: return "No do date"
            case .dueDate: return "No due date"
            }
        }
    }

    struct Request: Identifiable {
        let id = UUID()
        let task: AppTask
        let kind: DateKind
        var selectedDate: Date
        /// Whether the field had a date when the panel opened. `selectedDate` is seeded with today
        /// on an undated field, which is honest for the grid -- it is what Apply writes -- but there
        /// is nothing for Clear to clear ([[T-9256]]).
        var fieldHasDate: Bool = true

        /// Clear is drawn only over a date the task has, by the rule every other Mac date panel
        /// draws from ([[T-9211]]'s `CadenceDateSelectionState`).
        var showsClear: Bool {
            CadenceDateSelectionState.drawsClear(showsClear: true, hasSelection: fieldHasDate)
        }
    }

    /// The request `present` raises for `task`'s `kind` field.
    static func request(for task: AppTask, kind: DateKind, now: Date = Date()) -> Request {
        let dateKey = switch kind {
        case .doDate:
            task.scheduledDate
        case .dueDate:
            task.dueDate
        }
        let fieldDate = DateFormatters.date(from: dateKey)
        return Request(
            task: task,
            kind: kind,
            selectedDate: fieldDate ?? now,
            fieldHasDate: fieldDate != nil
        )
    }

    static let shared = HoveredTaskDatePickerManager()

    var request: Request?

    private init() {}

    func present(for task: AppTask, kind: DateKind) {
        request = Self.request(for: task, kind: kind)
    }

    /// Takes the context rather than owning one: this is a `shared` singleton installed at app
    /// launch, and the overlay that presents it already has `@Environment(\.modelContext)`. The
    /// context is what routes the write through `CadenceTaskDateEditing`, so the notification for
    /// the day being replaced is retired with it (T-362).
    func confirm(in context: ModelContext) {
        guard let request else { return }
        let key = DateFormatters.dateKey(from: request.selectedDate)
        switch request.kind {
        case .doDate:
            CadenceTaskDateEditing.setScheduledDate(key, for: request.task, in: context)
        case .dueDate:
            CadenceTaskDateEditing.setDueDate(key, for: request.task, in: context)
        }
        self.request = nil
    }

    func clearDate(in context: ModelContext) {
        guard let request else { return }
        switch request.kind {
        case .doDate:
            CadenceTaskDateEditing.clearScheduledDate(request.task, in: context)
        case .dueDate:
            CadenceTaskDateEditing.clearDueDate(request.task, in: context)
        }
        self.request = nil
    }

    func cancel() {
        request = nil
    }
}
#endif
