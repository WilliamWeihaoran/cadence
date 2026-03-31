#if os(macOS)
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

    func confirm() {
        guard let request else { return }
        let key = DateFormatters.dateKey(from: request.selectedDate)
        switch request.kind {
        case .doDate:
            request.task.scheduledDate = key
        case .dueDate:
            request.task.dueDate = key
        }
        self.request = nil
    }

    func clearDate() {
        guard let request else { return }
        switch request.kind {
        case .doDate:
            request.task.scheduledDate = ""
        case .dueDate:
            request.task.dueDate = ""
        }
        self.request = nil
    }

    func cancel() {
        request = nil
    }
}
#endif
