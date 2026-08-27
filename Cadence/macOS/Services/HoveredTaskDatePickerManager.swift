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
    }

    static let shared = HoveredTaskDatePickerManager()

    var request: Request?

    private init() {}

    func present(for task: AppTask, kind: DateKind) {
        let dateKey = switch kind {
        case .doDate:
            task.scheduledDate
        case .dueDate:
            task.dueDate
        }

        request = Request(
            task: task,
            kind: kind,
            selectedDate: DateFormatters.date(from: dateKey) ?? Date()
        )
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
