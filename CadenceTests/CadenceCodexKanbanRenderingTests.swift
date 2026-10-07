#if os(macOS)
import AppKit
import Observation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

@MainActor
@Suite(.serialized)
struct CadenceCodexKanbanRenderingTests {
    @Test func listCardsAreBoundedAndOtherScrollerCallersKeepTheirRealizationPolicy() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let tasks = (0..<200).map { index in
            let task = AppTask(title: "Card probe \(index)")
            task.order = index
            context.insert(task)
            return task
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<AppTask>()) == 200)
        let day = try #require(DateFormatters.date(from: "2026-10-06"))
        let section = TaskSectionConfig(name: TaskSectionDefaults.defaultName)
        let columns: [(String, AnyView)] = [
            ("list", AnyView(TaskListKanbanColumn(
                title: "Inbox", color: Theme.dim, tasks: tasks, universeTasks: tasks, spanTasks: tasks,
                sortField: .custom, sortDirection: .ascending, container: .inbox, onAssignTask: { _ in }
            ))),
            ("section", AnyView(ListSectionKanbanColumn(
                section: section, tasks: tasks, universeTasks: tasks, spanTasks: tasks,
                sortField: .custom, sortDirection: .ascending,
                isBeingDragged: false, isAnotherSectionBeingDragged: false, isHighlighted: false,
                onReorderBefore: { _ in false }
            ))),
            ("day", AnyView(CalendarBoardDayColumn(
                dayIndex: 0, date: day, dateKey: "2026-10-06", tasks: tasks,
                bundles: [], events: [], allTasks: tasks, allBundles: [], areas: [], projects: [],
                add: .compose(.day(dateKey: "2026-10-06", startMin: 540)),
                onDropTaskOnDay: { _ in false }, onDropBundleOnDay: { _ in false },
                onDropTaskOnBundle: { _, _ in }
            ))),
            ("rail", AnyView(CalendarBoardRailColumn(
                rail: .unscheduled, tasks: tasks, add: .presentSheet {}, onDrop: { _ in false }
            )))
        ]
        for (name, column) in columns {
            let mounted = try await mountedCards(in: column, container: container, width: 260)
            print("T-3005 \(name): stored 200, mounted native cards \(mounted)")
            #expect(mounted > 0, "positive control: \(name) must mount actual KanbanCard views")
            if name == "list" {
                #expect(mounted < 100, "list mounted \(mounted) / 200 cards")
            } else {
                #expect(mounted == 200, "\(name)'s realization policy is outside this conversion")
            }
        }
    }

    @Test func horizontalListColumnsMountOnlyABoundedSubset() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let inbox = AppTask(title: "Inbox probe")
        context.insert(inbox)
        for index in 0..<20 {
            let area = Area(name: "Column probe \(index)")
            area.order = index
            context.insert(area)
            let task = AppTask(title: "Column card \(index)")
            task.area = area
            context.insert(task)
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Area>()) == 20)
        #expect(try context.fetchCount(FetchDescriptor<AppTask>()) == 21)
        let mounted = try await mountedCards(
            in: TaskListsKanbanView(sortField: .custom), container: container, width: 640
        ) { host in
            let initial = self.nativeCardCount(in: host)
            print("T-3005 horizontal at start: columns 21, mounted native cards \(initial)")
            #expect(initial > 0)
            #expect(initial < 10)
            let scroll = try #require(self.descendants(in: host, of: NSScrollView.self).first { view in
                (view.documentView?.bounds.width ?? 0) > view.contentSize.width
            }, "positive control: find the actual horizontal overflow scroller")
            let document = try #require(scroll.documentView)
            scroll.contentView.scroll(to: NSPoint(x: document.bounds.maxX - scroll.contentSize.width, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            #expect(scroll.contentView.bounds.minX > 0)
        }
        print("T-3005 horizontal at end: columns 21, mounted native cards \(mounted)")
        #expect(mounted > 0, "positive control: the actual board must mount cards")
        #expect(mounted < 10, "horizontal board mounted \(mounted) / 21 columns' cards")
    }

    @Test func sharedScrollerOptInKeepsGeometryAndTheFinalComposerSlot() throws {
        let source = try code("KanbanColumnSupportViews.swift")
        let scroll = try #require(CadenceSourceScan.declarationBody("struct KanbanColumnScroll", in: source))
        #expect(scroll.contains("var defersOffscreenCards = false"))
        let stack = try #require(CadenceSourceScan.declarationBody("private var cardStack: some View", in: scroll))
        let stackLines = stack.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #expect(stackLines.contains("LazyVStack(alignment: .leading, spacing: 8) { columnContents }"))
        #expect(stackLines.contains("VStack(alignment: .leading, spacing: 8) { columnContents }"))
        #expect(scroll.contains(".frame(minHeight: 200)"))
        #expect(scroll.components(separatedBy: ".contentShape(Rectangle())").count - 1 == 2)
        let contents = try #require(CadenceSourceScan.declarationBody("private var columnContents: some View", in: scroll))
        #expect(contents.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("content()"))
        #expect(contents.contains("if case .compose(let surface) = add, isComposing.wrappedValue"))
        #expect(contents.contains("InlineTaskComposer(surface: surface)"))
        #expect(contents.contains("isComposing.wrappedValue = false"))
        #expect(contents.contains("KanbanColumnAddTaskRow(isColumnHovered: isColumnHovered)"))
        #expect(contents.contains("isComposing.wrappedValue = true"))
        #expect(contents.contains("present()"))

        let callers = ["KanbanListColumnView.swift", "KanbanSectionColumnView.swift",
                       "CalendarBoardDayColumnSupportViews.swift", "CalendarBoardRailSupportViews.swift"]
        for path in callers {
            let caller = try code(path)
            #expect(caller.components(separatedBy: "KanbanColumnScroll(").count - 1 == 1,
                    "non-vacuity: \(path) must still call the actual shared scroller once")
            #expect(caller.contains("defersOffscreenCards: true") == (path == callers[0]))
        }
        let ios = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListSupportViews.swift"))
        #expect(ios.contains("struct iOSListKanbanPanel: View"))
        #expect(!ios.contains("KanbanColumnScroll("), "the iOS mention is prose, not an executable caller")
    }

    @Test func displayOrderingIsDerivedOnceWithoutChangingDropOrderingOrIdentity() throws {
        let source = try code("KanbanListColumnView.swift")
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: source))
        #expect(body.components(separatedBy: "unfrozenSortedTasks").count - 1 == 1)
        #expect(body.contains("let displayTasks = applyFrozenTaskOrder(naturalTasks, frozen: frozenTasks)"))
        #expect(body.contains("return columnBody(tasks: displayTasks)"))
        #expect(body.contains("columnTaskIDs: Set(naturalTasks.map(\\.id))"))
        #expect(body.contains("capturedTasks: naturalTasks"))
        let column = try #require(CadenceSourceScan.declarationBody("private func columnBody(tasks: [AppTask])", in: source))
        #expect(column.contains("header(count: tasks.count)"))
        #expect(column.contains("columnTaskScroll(tasks: tasks)"))
        #expect(column.contains(".dropDestination(for: String.self)"))
        #expect(column.contains("return moveTask(droppedTask, before: nil)"))
        #expect(column.contains(".onDisappear"))
        #expect(column.contains("hoveredKanbanColumnManager.endHovering(id: columnHoverID)"))
        let cards = try #require(CadenceSourceScan.declarationBody("private func taskCards(tasks: [AppTask])", in: source))
        #expect(cards.contains("ForEach(tasks)"))
        #expect(cards.contains("handleTaskDrop(items: items, before: task)"))
        let move = try #require(CadenceSourceScan.declarationBody("private func moveTask(", in: source))
        #expect(move.contains("unfrozenSortedTasks.sorted { $0.order < $1.order }"))
        #expect(move.contains("spanning: spanTasks"))
        #expect(move.contains("assigning: { onAssignTask(task) }"))
        #expect(move.contains("return reordered"))
        let board = try code("KanbanSupportViews.swift")
        #expect(board.contains("LazyHStack(alignment: .top, spacing: 12)"))
        #expect(board.contains("ForEach(listColumns(activeTasks: activeTasks))"))
    }

    private func code(_ file: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/\(file)"))
    }

    @Test func scrollingToTheEndStillMountsCardsWithoutMountingTheWholeColumn() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let tasks = (0..<200).map { index in
            let task = AppTask(title: "Scroll probe \(index)")
            task.order = index
            context.insert(task)
            return task
        }
        try context.save()
        let column = TaskListKanbanColumn(
            title: "Inbox", color: Theme.dim, tasks: tasks, universeTasks: tasks, spanTasks: tasks,
            sortField: .custom, sortDirection: .ascending, container: .inbox, onAssignTask: { _ in }
        )
        let mounted = try await mountedCards(in: column, container: container, width: 260) { host in
            let scroll = try #require(self.descendants(in: host, of: NSScrollView.self).first { view in
                (view.documentView?.bounds.height ?? 0) > view.contentSize.height
            }, "positive control: find the actual overflow scroller")
            let document = try #require(scroll.documentView)
            let end = document.bounds.maxY - scroll.contentSize.height
            #expect(end > 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: end))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            #expect(scroll.contentView.bounds.minY > 0, "the native scroll must actually move")
        }
        print("T-3005 list at end: stored 200, mounted native cards \(mounted)")
        #expect(mounted > 0)
        #expect(mounted < 100)
    }

    @Test func disappearingColumnReleasesOnlyItsOwnHoverRegistration() async throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let task = AppTask(title: "Hover probe")
        container.mainContext.insert(task)
        try container.mainContext.save()
        let manager = HoveredKanbanColumnManager.shared
        defer { manager.clear() }
        for replacement in [false, true] {
            manager.clear()
            let visibility = CodexKanbanVisibility()
            let column = TaskListKanbanColumn(
                title: "Inbox", color: Theme.dim, tasks: [task], universeTasks: [task], spanTasks: [task],
                sortField: .custom, sortDirection: .ascending, container: .inbox, onAssignTask: { _ in }
            )
            let root = CodexKanbanVisibilityHost(visibility: visibility) { column }
            var calls = 0
            let mounted = try await mountedCards(in: root, container: container, width: 260) { host in
                #expect(self.nativeCardCount(in: host) == 1, "non-vacuity: the real column appeared")
                manager.beginHovering(id: "kanban-list-column-inbox") { calls += 1 }
                #expect(manager.triggerCreateTask())
                #expect(calls == 1)
                if replacement {
                    manager.beginHovering(id: "replacement-column") { calls += 1 }
                }
                visibility.isShown = false
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                #expect(manager.triggerCreateTask() == replacement)
                #expect(calls == (replacement ? 2 : 1))
            }
            #expect(mounted == 0, "the column must actually disappear")
        }
    }

    private func mountedCards<V: View>(
        in view: V, container: ModelContainer, width: CGFloat,
        afterMount: ((NSView) async throws -> Void)? = nil
    ) async throws -> Int {
        let host = NSHostingView(rootView: view
            .modelContainer(container)
            .environment(RemindersManager.shared)
            .environment(CadenceDeepLinkManager.shared)
            .environment(DeleteConfirmationManager.shared)
            .environment(HoveredTaskManager.shared)
            .environment(HoveredEditableManager.shared)
            .environment(HoveredKanbanColumnManager.shared)
            .environment(HoveredSectionManager.shared)
            .environment(SectionCompletionAnimationManager.shared)
            .environment(FocusManager.shared)
            .environment(TaskCompletionAnimationManager.shared))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 320)
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
        try await afterMount?(host)
        return nativeCardCount(in: host)
    }

    private func descendants<V: NSView>(in view: NSView, of type: V.Type) -> [V] {
        let own = (view as? V).map { [$0] } ?? []
        return own + view.subviews.flatMap { descendants(in: $0, of: type) }
    }

    private func nativeCardCount(in view: NSView) -> Int {
        let own = view is RightClickActionTrigger.RightClickActionView ? 1 : 0
        return own + view.subviews.reduce(0) { $0 + nativeCardCount(in: $1) }
    }
}

@MainActor
@Observable
private final class CodexKanbanVisibility {
    var isShown = true
}

private struct CodexKanbanVisibilityHost<Content: View>: View {
    let visibility: CodexKanbanVisibility
    @ViewBuilder let content: () -> Content

    var body: some View {
        if visibility.isShown { content() }
    }
}
#endif
