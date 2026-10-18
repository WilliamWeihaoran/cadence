#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// [[T-1467]] — the macOS task row shows the notes excerpt and the open subtasks, with
/// checkboxes, the way iOS's row does (parity findings PA-01 and PA-02).
///
/// **Measured on the real row, hosted, not source-scanned.** The question is whether a task with
/// notes or open subtasks *draws more* than one without, and whether a subtask's checkbox under the
/// row actually finishes that subtask — both are behaviour a string match cannot see. Heights are
/// compared against the same row with the content taken away, so the test is independent of the
/// exact figures `CadenceTaskRowMetrics.desktop` sets.
@MainActor
@Suite(.serialized)
struct MacTaskRowInlineDetailTests {
    private let width: CGFloat = 520

    /// The plain row is the control: a task with notes is taller by the excerpt, and a task whose
    /// notes are only whitespace is not — `plainPreviewText` comes back empty, so no line is drawn.
    @Test func aTaskWithNotesDrawsAnExcerptLineAndBlankNotesDrawNone() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        let plain = AppTask(title: "Plain row")
        let noted = AppTask(title: "Noted row")
        noted.notes = "Pick up the dry cleaning before six"
        let blank = AppTask(title: "Blank notes row")
        blank.notes = "   \n  "
        for task in [plain, noted, blank] { context.insert(task) }
        try context.save()

        let plainHeight = rowHeight(plain, container: container)
        let notedHeight = rowHeight(noted, container: container)
        let blankHeight = rowHeight(blank, container: container)

        #expect(plainHeight > 0, "non-vacuity: the row did not lay out")
        #expect(notedHeight > plainHeight + 8, "a task with notes drew no excerpt: \(notedHeight) vs \(plainHeight)")
        #expect(abs(blankHeight - plainHeight) < 0.5, "whitespace-only notes drew a line: \(blankHeight) vs \(plainHeight)")
    }

    /// Open subtasks add rows; more than the cap adds the three rows plus an overflow line, not
    /// one row per subtask; and a finished task lists none — `listedSubtasks(for:)`'s rule, which
    /// keeps a Completed section from filling with checkboxes for work that is over.
    @Test func openSubtasksAreListedCappedAndHiddenUnderAFinishedTask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext

        let plain = AppTask(title: "No children")
        let two = AppTask(title: "Two children")
        let five = AppTask(title: "Five children")
        let done = AppTask(title: "Finished parent")
        let allDone = AppTask(title: "All children done")
        for task in [plain, two, five, done, allDone] { context.insert(task) }
        attach(2, to: two, in: context)
        attach(5, to: five, in: context)
        attach(2, to: done, in: context)
        done.status = .done
        attach(2, to: allDone, in: context).forEach { $0.isDone = true }
        try context.save()

        let plainHeight = rowHeight(plain, container: container)
        let twoHeight = rowHeight(two, container: container)
        let fiveHeight = rowHeight(five, container: container)
        let doneHeight = rowHeight(done, container: container)
        let allDoneHeight = rowHeight(allDone, container: container)

        #expect(twoHeight > plainHeight + 20, "two open subtasks drew no rows: \(twoHeight) vs \(plainHeight)")
        // Three rows and a "+2 more" line: taller than two rows, but by less than three more rows
        // would add — the cap held.
        let perRow = (twoHeight - plainHeight) / 2
        #expect(fiveHeight > twoHeight + perRow * 0.5, "the third row or the overflow line is missing")
        #expect(fiveHeight < twoHeight + perRow * 2.5, "five subtasks were listed uncapped: \(fiveHeight)")
        #expect(abs(doneHeight - plainHeight) < 0.5, "a finished task listed its subtasks: \(doneHeight)")
        #expect(abs(allDoneHeight - plainHeight) < 0.5, "finished subtasks were listed: \(allDoneHeight)")
    }

    /// The checkbox is a real control: pressing it through accessibility — the same action a click
    /// on the circle sends — finishes **that** subtask, and only that one.
    @Test func theInlineCheckboxFinishesItsSubtask() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = container.mainContext
        let task = AppTask(title: "Parent with a checklist")
        context.insert(task)
        let subtasks = attach(2, to: task, in: context)
        try context.save()

        // SwiftUI builds no accessibility children until something asks as an assistive client
        // would; the enhanced-UI attribute is that ask. Same harness and same reasoning as
        // `CadenceEyebrowAccessibilityTests.allNodes`.
        let app = NSApplication.shared
        let enhanced = NSSelectorFromString("accessibilitySetEnhancedUserInterfaceAttribute:")
        _ = app.perform(enhanced, with: NSNumber(value: true))
        defer { _ = app.perform(enhanced, with: NSNumber(value: false)) }

        let host = hostedRow(task, container: container)
        let window = try #require(host.window)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        window.orderFrontRegardless()
        _ = host.accessibilityChildren()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let target = subtasks[1].title
        let elements = accessibilityElements(in: host)
        // Non-vacuity: the harness reached the tree — the parent's own title is a static text in it.
        #expect(
            elements.contains { string($0, "accessibilityValue") == task.title },
            "the harness read no accessibility tree from the hosted row"
        )
        let presses = elements.filter { element in
            string(element, "accessibilityValue") == target
                && string(element, "accessibilityLabel") == CadenceTaskCompletionState.todo.accessibilityActionLabel
        }
        #expect(presses.count == 1, "expected one checkbox for \(target), found \(presses.count)")
        let checkbox = try #require(presses.first)
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(checkbox.responds(to: press), "the subtask's circle is not a pressable control")
        _ = checkbox.perform(press)

        #expect(subtasks[1].isDone, "the checkbox did not finish its subtask")
        #expect(!subtasks[0].isDone, "the checkbox finished a different subtask")
    }

    // MARK: - Harness

    @discardableResult
    private func attach(_ count: Int, to task: AppTask, in context: ModelContext) -> [Subtask] {
        let subtasks = (0..<count).map { index in
            let subtask = Subtask(title: "\(task.title) step \(index + 1)")
            subtask.order = index
            context.insert(subtask)
            subtask.parentTask = task
            return subtask
        }
        task.subtasks = subtasks
        return subtasks
    }

    private func rowHeight(_ task: AppTask, container: ModelContainer) -> CGFloat {
        let host = hostedRow(task, container: container)
        defer { host.window?.contentView = nil; host.window?.close() }
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    private func hostedRow(_ task: AppTask, container: ModelContainer) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: MacTaskRow(task: task)
            .frame(width: width)
            .modelContainer(container)
            .environment(CadenceDeepLinkManager.shared)
            .environment(DeleteConfirmationManager.shared)
            .environment(HoveredTaskManager.shared)
            .environment(HoveredEditableManager.shared)
            .environment(FocusManager.shared)
            .environment(TaskCompletionAnimationManager.shared))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return host
    }

    private func string(_ object: AnyObject, _ name: String) -> String {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), let result = object.perform(selector)?.takeUnretainedValue() else {
            return ""
        }
        return "\(result)"
    }

    private func accessibilityElements(in root: AnyObject, depth: Int = 0) -> [AnyObject] {
        guard depth < 20 else { return [] }
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        guard root.responds(to: childrenSelector),
              let children = root.perform(childrenSelector)?.takeUnretainedValue() as? [Any] else { return [root] }
        return [root] + children.flatMap { accessibilityElements(in: $0 as AnyObject, depth: depth + 1) }
    }
}
#endif
