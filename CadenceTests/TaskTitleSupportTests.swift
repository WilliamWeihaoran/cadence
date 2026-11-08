import Foundation
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

    /// **[[T-13961]].** Escape or backspace-at-empty in the `#`/`~` panel writes the literal token
    /// back into the title. That token must stay text while the user keeps typing into it, or the
    /// title field reopens the panel on its own write and `Fix #42` cannot be typed.
    @Test func aRestoredInlineShortcutStaysLiteralUntilANewTokenStarts() throws {
        let shortcut = try #require(TaskTitleSupport.tagShortcut(in: "Fix #42"))
        let anchor = TaskTitleSupport.declinedInlineShortcutAnchor(prefix: shortcut.prefix, marker: "#")
        #expect(anchor == "Fix #")

        // The restored text, and more typed into the same token.
        #expect(TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix #42", anchor: anchor))
        #expect(TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix #", anchor: anchor))
        #expect(TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix #425", anchor: anchor))

        // A space starts a new token, so the next `#` routes again.
        #expect(!TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix #42 #", anchor: anchor))
        #expect(TaskTitleSupport.tagShortcut(in: "Fix #42 #")?.prefix == "Fix #42 ")
        // Deleting back past the marker ends the declined token.
        #expect(!TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix ", anchor: anchor))
        #expect(!TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix ~42", anchor: anchor))
        // Nothing declined, nothing suppressed.
        #expect(!TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix #42", anchor: nil))
        #expect(!TaskTitleSupport.isDeclinedInlineShortcut(in: "Fix #42", anchor: ""))
    }

    #if os(macOS)
    /// **[[T-13961]], the wiring.** The title field records where the restored token begins before
    /// writing it back, and its change handler asks the rule above before routing a `#` or `~`.
    /// A SwiftUI change handler cannot be driven from here, so this reads the source.
    @Test func theTitleFieldConsultsTheDeclinedTokenBeforeRouting() throws {
        let code = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskTitleEntryField.swift")
        )
        let restore = try #require(CadenceSourceScan.functionBody(named: "restoreLiteralShortcut", in: code))
        let record = try #require(restore.range(of: "declinedShortcutAnchor = TaskTitleSupport.declinedInlineShortcutAnchor(prefix: title, marker: marker)"))
        let write = try #require(restore.range(of: "title += "))
        #expect(record.upperBound <= write.lowerBound, "the anchor is read off the title after the token was appended")

        let handler = try #require(code.range(of: ".onChange(of: title) {"))
        let tail = code[handler.upperBound...]
        let consult = try #require(tail.range(of: "TaskTitleSupport.isDeclinedInlineShortcut(in: newValue, anchor: declinedShortcutAnchor)"))
        let route = try #require(tail.range(of: "TaskTitleSupport.containerShortcut(in: newValue)"))
        #expect(consult.upperBound <= route.lowerBound, "the field routes before asking whether the token was declined")
    }
    #endif
}
