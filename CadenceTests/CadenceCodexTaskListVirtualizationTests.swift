#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

@MainActor
@Suite(.serialized)
struct CadenceCodexTaskListVirtualizationTests {
    private let path = "Cadence/macOS/Views/TasksListView.swift"

    @Test func bothRowBearingSectionsAreLazyNotJustTheirPageWrapper() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        for name in ["TasksListSectionView", "TasksListCompletedSectionView"] {
            let section = try #require(CadenceSourceScan.declarationBody("struct \(name): View", in: source))
            let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: section))
            #expect(body.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("LazyVStack(alignment: .leading, spacing: 0)"),
                "\(name) still eagerly realizes an entire group inside the lazy page")
            #expect(body.contains("if !isCollapsed"))
            #expect(body.contains("ForEach("))
            #expect(body.contains("TaskListGroupHeader("))
        }
        let active = try #require(CadenceSourceScan.declarationBody("struct TasksListSectionView: View", in: source))
        #expect(active.contains("ForEach(section.tasks)"))
        #expect(active.contains("TaskListInteractiveRow("))
        #expect(active.contains(".dropDestination(for: String.self)"))
        #expect(active.contains("onDropOnTaskPayload: onDropOnTaskPayload"))
        let completed = try #require(CadenceSourceScan.declarationBody("struct TasksListCompletedSectionView: View", in: source))
        #expect(completed.contains("ForEach(tasks)"))
        #expect(completed.contains(".draggable(taskDragPayload(task))"))
    }

    @Test func pageStillOwnsCollapseRevealAndRowOrderFreeze() throws {
        let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        let page = try #require(CadenceSourceScan.declarationBody("struct TasksListView: View", in: source))
        #expect(page.contains("collapsedSectionIDs.contains(section.id)"))
        #expect(page.contains("onToggle: { toggleSection(section.id) }"))
        #expect(page.contains("isCompletedCollapsed = !revealsCompletedSection"))
        #expect(page.contains(".onChange(of: deepLinkManager.revealedCompletedTaskID)"))
        #expect(page.contains("applyFrozenTaskOrder(naturalTasks, frozen: frozenTaskOrder)"))
        #expect(page.contains("frozenGroups: .constant(nil)"))
        #expect(page.contains("scopeTasks: section.tasks"))
        #expect(!page.contains("pendingTaskID ="), "All Tasks must not arm an offscreen row's onAppear")
    }

    @Test func largeSingleGroupsMountOnlyABoundedSubsetOfNativeTaskRows() async throws {
        for (grouping, count) in [(TaskGroupingMode.none, 200), (.byDate, 1_000), (.byPriority, 200), (.byList, 200)] {
            let container = try CadenceModelContainerFactory.makeInMemoryContainer()
            let context = container.mainContext
            for index in 0..<count {
                let task = AppTask(title: "Virtualization probe \(index)")
                task.order = index
                context.insert(task)
            }
            try context.save()
            #expect(try context.fetchCount(FetchDescriptor<AppTask>()) == count)

            let host = NSHostingView(rootView:
                TasksListView(scope: .all, sortField: .custom, sortDirection: .ascending, groupingMode: grouping)
                    .modelContainer(container)
                    .environment(RemindersManager.shared)
                    .environment(CadenceDeepLinkManager.shared)
                    .environment(DeleteConfirmationManager.shared)
                    .environment(HoveredTaskManager.shared)
                    .environment(HoveredEditableManager.shared)
                    .environment(FocusManager.shared)
                    .environment(TaskCompletionAnimationManager.shared)
            )
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 320)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let mounted = nativeTaskRowCount(in: host)
            print("T-3004 \(grouping.rawValue): stored \(count), mounted native task rows \(mounted)")
            #expect(mounted > 0, "positive control: the actual task rows must mount in this host")
            #expect(mounted < 100, "\(grouping.rawValue): mounted \(mounted) native task rows for \(count) tasks")
            #expect(mounted < count / 2, "an eager group may not pass as a lazy page")
        }
    }

    private func nativeTaskRowCount(in view: NSView) -> Int {
        let own = view is RightClickActionTrigger.RightClickActionView ? 1 : 0
        return own + view.subviews.reduce(0) { $0 + nativeTaskRowCount(in: $1) }
    }
}
#endif
