// macOS only: `RootCommandActionSupport`, `ListNavigationManager` and the inspector layer are
// macOS app types.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-5300]] — picking a task in macOS global search (Cmd+K) opens that task's inspector.**
///
/// It used to open the task's list and stop: nothing scrolled, nothing was marked, and with the
/// include-completed setting on a finished result landed inside a Completed group that
/// `ListTasksView` collapses on appear — so the row picked was not on screen at all. iOS has
/// always opened the task itself. The owner chose the inspector over a scroll-and-reveal.
///
/// The arm is called directly. It was split out of `handleSearchSelection` with its four
/// dependencies named precisely so it could be: the full `RootSearchSelectionContext` carries a
/// `CalendarManager`, which owns a real `EKEventStore`, and this arm wants nothing from it.
@MainActor
struct CadenceGlobalSearchTaskInspectorTests {

    private func store() throws -> ModelContext {
        ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
    }

    /// What the arm did before, plus the one thing it did not: the task itself.
    @Test func pickingATaskInAListOpensTheListAndThenTheTasksInspector() throws {
        let modelContext = try store()
        let project = Project(name: "Website")
        modelContext.insert(project)
        let task = AppTask(title: "Spec")
        task.project = project
        modelContext.insert(task)
        try modelContext.save()

        let navigation = ListNavigationManager.shared
        navigation.request = nil
        defer { navigation.request = nil }

        var selections: [SidebarItem] = []
        var inspected: [UUID] = []
        RootCommandActionSupport.handleTaskSelection(
            task.id,
            modelContext: modelContext,
            listNavigationManager: navigation,
            setSelection: { selections.append($0) },
            presentTaskInspector: { inspected.append($0) }
        )

        #expect(inspected == [task.id], "the row opened its list and stopped (T-5300)")
        #expect(selections == [.project(project.id)])
        #expect(navigation.request?.projectID == project.id)
        #expect(navigation.request?.page == .tasks)
    }

    /// The case the ticket is sharpest about: a completed task, whose row lands inside a group
    /// `ListTasksView` folds on appear, so opening the list reveals nothing at all.
    @Test func aCompletedInboxTaskOpensItsInspectorEvenThoughItsRowIsFolded() throws {
        let modelContext = try store()
        let task = AppTask(title: "Shipped")
        task.status = .done
        modelContext.insert(task)
        try modelContext.save()

        let navigation = ListNavigationManager.shared
        navigation.request = nil
        defer { navigation.request = nil }

        var selections: [SidebarItem] = []
        var inspected: [UUID] = []
        RootCommandActionSupport.handleTaskSelection(
            task.id,
            modelContext: modelContext,
            listNavigationManager: navigation,
            setSelection: { selections.append($0) },
            presentTaskInspector: { inspected.append($0) }
        )

        #expect(inspected == [task.id])
        #expect(selections == [.inbox])
        #expect(navigation.request == nil, "an inbox task has no list page to open")
    }

    /// A task deleted between the keystroke and the Return opens nothing — not an empty
    /// inspector, and not a page either.
    @Test func aTaskThatIsNoLongerThereOpensNothing() throws {
        let modelContext = try store()
        var selections: [SidebarItem] = []
        var inspected: [UUID] = []
        RootCommandActionSupport.handleTaskSelection(
            UUID(),
            modelContext: modelContext,
            listNavigationManager: ListNavigationManager.shared,
            setSelection: { selections.append($0) },
            presentTaskInspector: { inspected.append($0) }
        )
        #expect(inspected.isEmpty)
        #expect(selections.isEmpty)
    }

    // MARK: - The one-slot inbox the shell reads

    @Test func theManagerHoldsOneRequestAtATimeAndGivesItUp() {
        let manager = TaskInspectorPresentationManager.shared
        manager.dismiss()
        defer { manager.dismiss() }

        #expect(manager.requestedTaskID == nil)
        let first = UUID()
        manager.present(taskID: first)
        #expect(manager.requestedTaskID == first)
        let second = UUID()
        manager.present(taskID: second)
        #expect(manager.requestedTaskID == second)
        manager.dismiss()
        #expect(manager.requestedTaskID == nil)
    }

    // MARK: - The wiring a test cannot press

    /// The layer and the shell that mounts it are SwiftUI, so they are pinned as source: the
    /// request has to reach `TaskDetailPopover`, and the popover's dismissal has to clear the
    /// manager or the next Cmd+K opens over a stale request.
    @Test func theShellDrawsTheRequestedTaskAsATaskDetailPopover() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let shell = try read("Cadence/macOS/Views/macOSRootShellViews.swift")
        let stack = try #require(CadenceSourceScan.declarationBody("struct macOSRootOverlayStack: View", in: shell))
        #expect(stack.contains("TaskInspectorLayerView()"))
        #expect(stack.contains("GlobalSearchLayerView(onSelect: handleSearchSelection)"), "non-vacuity")

        let views = try read("Cadence/macOS/Views/macOSRootSupportViews.swift")
        let layer = try #require(CadenceSourceScan.declarationBody("struct TaskInspectorLayerView: View", in: views))
        #expect(layer.contains("TaskDetailPopover(task: task)"))
        #expect(CadenceSourceScan.matchCount(#"\.popover\(isPresented: isPresented"#, in: layer) == 1)
        #expect(layer.contains("taskInspectorPresentationManager.dismiss()"))
    }

    /// And the Cmd+K arm itself raises it. `presentTaskInspector` is the last thing the arm does,
    /// after the page it opens behind the inspector.
    @Test func theSearchSelectionArmRoutesATaskThroughTheExtractedHandler() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/macOSRootCommandActionSupport.swift")
        let selection = try #require(CadenceSourceScan.declarationBody("static func handleSearchSelection", in: source))
        #expect(selection.contains("case .task(let id):"))
        #expect(selection.contains("presentTaskInspector: context.presentTaskInspector"))

        let arm = try #require(CadenceSourceScan.declarationBody("static func handleTaskSelection", in: source))
        #expect(arm.contains("presentTaskInspector(task.id)"))
    }
}
#endif
