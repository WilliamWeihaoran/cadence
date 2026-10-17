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
            let mounted = mountedTaskRowCount(in: host, window: window)
            print("T-3004 \(grouping.rawValue): stored \(count), mounted task rows \(mounted)")
            #expect(mounted > 0, "positive control: the actual task rows must mount in this host")
            #expect(mounted < 100, "\(grouping.rawValue): mounted \(mounted) native task rows for \(count) tasks")
            #expect(mounted < count / 2, "an eager group may not pass as a lazy page")
        }
    }

    /// **The negative control the re-key needs — and that the overlay probe never had.**
    ///
    /// A probe that only saw what is on screen would read the same bounded number from a lazy page
    /// and from one that realized all thousand rows, and `mounted < count / 2` above would prove
    /// nothing at all. So the same thousand tasks are drawn once more in a deliberately EAGER
    /// `VStack` inside a `ScrollView` — the shape the section views had before T-3004 — and the
    /// same probe is asked again. It has to read far more there than the real page reads, or this
    /// harness cannot tell the two apart and every bound above is decorative.
    @Test func theProbeReadsAnEagerListAsFarLargerThanALazyOne() async throws {
        let count = 1_000
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        var seeded: [AppTask] = []
        for index in 0..<count {
            let task = AppTask(title: "Eager probe \(index)")
            task.order = index
            context.insert(task)
            seeded.append(task)
        }
        try context.save()

        let host = NSHostingView(rootView:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(seeded) { TaskListDisplayRow(task: $0) }
                }
            }
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
        let eager = mountedTaskRowCount(in: host, window: window)
        print("T-3201 eager control: stored \(count), mounted task rows \(eager)")
        #expect(
            eager > 100,
            "the probe read \(eager) rows from an EAGER list of \(count): it cannot tell eager from lazy, so the bounds in largeSingleGroupsMountOnlyABoundedSubsetOfNativeTaskRows are vacuous"
        )
    }

    /// **The probe is the row's own accessibility identifier, not an AppKit overlay ([[T-3201]]).**
    ///
    /// It used to count `RightClickActionTrigger.RightClickActionView`, which `MacTaskRow` carried
    /// for one reason: to turn a right-click into the same "open the inspector" the row's tap
    /// already did. [[T-1479]] replaced that overlay with a real `.contextMenu`, so the class left
    /// the row and this probe read **0** — a positive-control failure over a lazy-mount bound that
    /// still held perfectly well. The overlay was never what made a row a row; it was an
    /// implementation detail the probe had borrowed.
    ///
    /// `CadenceAccessibilityIdentifiers.taskRowTitle(title:)` is on the row's title because the row
    /// needs it there — `CadenceTodayRowCrushUITests` reads that element's width, and T-1432's
    /// defect is a title too truncated to look up by its text. One per realized row, and it cannot
    /// quietly disappear the way the overlay did without a UI test going red first.
    ///
    /// **Why the enhanced-user-interface dance.** SwiftUI builds no accessibility children until
    /// something asks as an assistive client would; `CadenceEyebrowAccessibilityTests` measured
    /// that for T-2022 and this is the same manoeuvre. Without it the tree comes back empty and
    /// the positive control above fails for the harness's reason rather than the view's.
    private func mountedTaskRowCount(in host: NSView, window: NSWindow) -> Int {
        let app = NSApplication.shared
        let enhanced = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        _ = app.perform(enhanced, with: NSNumber(value: true))
        defer { _ = app.perform(enhanced, with: NSNumber(value: false)) }

        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        _ = host.accessibilityChildren()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        var found = 0
        let identifierSelector = NSSelectorFromString("accessibilityIdentifier")
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        func walk(_ element: Any, depth: Int) {
            guard depth < 64 else { return }
            let object = element as AnyObject
            if object.responds(to: identifierSelector),
               let raw = object.perform(identifierSelector)?.takeUnretainedValue(),
               "\(raw)".hasPrefix(Self.taskRowTitlePrefix),
               "\(raw)".hasSuffix(".title") {
                found += 1
            }
            guard object.responds(to: childrenSelector),
                  let children = object.perform(childrenSelector)?.takeUnretainedValue() as? [Any] else { return }
            for child in children { walk(child, depth: depth + 1) }
        }
        walk(host, depth: 0)
        return found
    }

    /// Read off the builder rather than spelled out, so a change to the identifier's shape moves
    /// this probe with it instead of silently zeroing it. `marker` slugs to itself, so whatever
    /// sits in front of it is the fixed prefix every task-row title identifier carries.
    private static let taskRowTitlePrefix: String = {
        let sample = CadenceAccessibilityIdentifiers.taskRowTitle(title: "marker")
        guard let range = sample.range(of: "marker") else { return "task.row." }
        return String(sample[sample.startIndex..<range.lowerBound])
    }()

    /// The prefix is only a prefix if the builder still puts the slug in the middle. If this ever
    /// fails, `mountedTaskRowCount` is counting nothing and every bound below is vacuous.
    @Test func theRowIdentifierProbeStillMatchesTheIdentifierTheRowDraws() {
        let identifier = CadenceAccessibilityIdentifiers.taskRowTitle(title: "Virtualization probe 7")
        #expect(!Self.taskRowTitlePrefix.isEmpty, "the task-row identifier lost its fixed prefix")
        #expect(identifier.hasPrefix(Self.taskRowTitlePrefix), "\(identifier) no longer starts with \(Self.taskRowTitlePrefix)")
        #expect(identifier.hasSuffix(".title"), "\(identifier) no longer ends in .title")
        #expect(
            !CadenceAccessibilityIdentifiers.taskRowDueChip(title: "Virtualization probe 7")
                .hasSuffix(".title"),
            "the due chip now answers the row-title probe, which would double every count"
        )
    }
}
#endif
