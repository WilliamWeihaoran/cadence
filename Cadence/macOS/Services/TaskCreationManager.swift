#if os(macOS)
import SwiftUI
import AppKit

enum TaskContainerSelection: Hashable {
    case inbox
    case area(UUID)
    case project(UUID)
}

struct TaskCreationSeed {
    var title: String = ""
    var notes: String = ""
    var dueDateKey: String = ""
    var doDateKey: String = ""
    var priority: TaskPriority = .none
    var container: TaskContainerSelection = .inbox
    var sectionName: String = TaskSectionDefaults.defaultName
}

@Observable
final class TaskCreationManager {
    static let shared = TaskCreationManager()

    var isPresented: Bool = false
    var seed: TaskCreationSeed = TaskCreationSeed()

    private init() {}

    func present(
        title: String = "",
        notes: String = "",
        dueDateKey: String = "",
        doDateKey: String = "",
        priority: TaskPriority = .none,
        container: TaskContainerSelection = .inbox,
        sectionName: String = TaskSectionDefaults.defaultName
    ) {
        seed = TaskCreationSeed(
            title: title,
            notes: notes,
            dueDateKey: dueDateKey,
            doDateKey: doDateKey,
            priority: priority,
            container: container,
            sectionName: sectionName
        )

        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        seed = TaskCreationSeed()
    }
}
#endif
