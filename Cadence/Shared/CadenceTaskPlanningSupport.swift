import Foundation
import SwiftUI

enum CadenceTaskSortMode: String, CaseIterable, Hashable, Identifiable {
    case listOrder
    case priority
    case doDate
    case dueDate
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listOrder: return "List Order"
        case .priority: return "Priority"
        case .doDate: return "Do Date"
        case .dueDate: return "Due Date"
        case .newest: return "Newest"
        }
    }
}

enum CadenceTodayTaskGroupKind: String, CaseIterable, Hashable {
    case overdue
    case dueToday
    case plannedToday

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueToday: return "Due Today"
        case .plannedToday: return "Planned Today"
        }
    }
}

struct CadenceTodayTaskGroup: Identifiable {
    let kind: CadenceTodayTaskGroupKind
    let tasks: [AppTask]

    var id: CadenceTodayTaskGroupKind { kind }
    var title: String { kind.title }
}

struct CadenceTaskDisplayGroup: Identifiable {
    let id: String
    let title: String
    let accent: Color
    let tasks: [AppTask]
    let dropKey: String?

    init(
        id: String,
        title: String,
        accent: Color,
        tasks: [AppTask],
        dropKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.accent = accent
        self.tasks = tasks
        self.dropKey = dropKey
    }
}

struct CadenceTaskDateBuckets {
    let overdueIDs: Set<UUID>
    let dueTodayIDs: Set<UUID>
    let doTodayIDs: Set<UUID>

    func contains(_ task: AppTask) -> Bool {
        overdueIDs.contains(task.id) || dueTodayIDs.contains(task.id) || doTodayIDs.contains(task.id)
    }
}
