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
    var showSuccessToast: Bool = false

    @ObservationIgnored
    private var successToastTask: Task<Void, Never>?

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

    func presentSuccessToast() {
        successToastTask?.cancel()
        // Bring the main app window to front so the in-app toast is visible,
        // even when called from the global quick-capture panel.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isKind(of: NSWindow.self) && !$0.isKind(of: NSPanel.self) })?.makeKeyAndOrderFront(nil)
        withAnimation(.easeInOut(duration: 0.16)) {
            showSuccessToast = true
        }
        successToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                showSuccessToast = false
            }
        }
    }
}
#endif
