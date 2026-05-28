import Testing
@testable import Cadence

struct TaskTitleSupportTests {
    @Test func priorityShortcutReadsLeadingAndTrailingBangs() throws {
        let leading = try #require(TaskTitleSupport.priorityShortcut(in: "!! call mom"))
        #expect(leading.title == "call mom")
        #expect(leading.priority == .medium)

        let trailing = try #require(TaskTitleSupport.priorityShortcut(in: "ship fix!!!!"))
        #expect(trailing.title == "ship fix")
        #expect(trailing.priority == .high)
    }

    @Test func priorityShortcutKeepsMiddleBangsAsTitleText() {
        #expect(TaskTitleSupport.priorityShortcut(in: "email! alice") == nil)
    }

    @Test func applyingPriorityShortcutUpdatesPriorityAndCleansTitle() {
        var priority: TaskPriority = .none

        let title = TaskTitleSupport.titleApplyingPriorityShortcut(
            "review launch plan !!!",
            priority: &priority
        )

        #expect(title == "review launch plan")
        #expect(priority == .high)
    }

    @Test func applyingTitleWithoutPriorityShortcutKeepsPriority() {
        var priority: TaskPriority = .medium

        let title = TaskTitleSupport.titleApplyingPriorityShortcut(
            "  review launch plan  ",
            priority: &priority
        )

        #expect(title == "review launch plan")
        #expect(priority == .medium)
    }

    @Test func inlineShortcutsOnlyStartAtTokenBoundary() throws {
        let tag = try #require(TaskTitleSupport.tagShortcut(in: "fix parser #bug"))
        #expect(tag.prefix == "fix parser ")
        #expect(tag.query == "bug")

        let list = try #require(TaskTitleSupport.containerShortcut(in: "plan review ~General"))
        #expect(list.prefix == "plan review ")
        #expect(list.query == "General")

        #expect(TaskTitleSupport.tagShortcut(in: "read chapter#3") == nil)
        #expect(TaskTitleSupport.containerShortcut(in: "read~later") == nil)
    }
}
