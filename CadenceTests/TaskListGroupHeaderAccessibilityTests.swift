import Foundation
import Testing
@testable import Cadence

/// **The Mac task-group header says what it is to VoiceOver (T-7008).**
///
/// `TaskListGroupHeader` heads every group on Today, Inbox, All Tasks and list pages. It read as
/// its title plus an unexplained number (the overdue capsule had no label), its disclosure stated
/// no Expanded/Collapsed value while iOS's does, and with `isToggleEnabled: false` it was still a
/// `Button` whose action did nothing.
struct TaskListGroupHeaderAccessibilityTests {
    @Test func theDisclosureValueMatchesIOS() {
        #expect(TaskListGroupHeaderAccessibility.value(isCollapsed: true) == "Collapsed")
        #expect(TaskListGroupHeaderAccessibility.value(isCollapsed: false) == "Expanded")
    }

    @Test func theOverdueCapsuleIsLabelledWithItsCount() {
        #expect(TaskListGroupHeaderAccessibility.overdueLabel(count: 1) == "1 overdue task")
        #expect(TaskListGroupHeaderAccessibility.overdueLabel(count: 3) == "3 overdue tasks")
    }

    private func headerSource() throws -> String {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListDetailSupportViews.swift")
        )
        return try #require(
            CadenceSourceScan.declarationBody("struct TaskListGroupHeader<LeadingContent: View>: View", in: source)
        )
    }

    @Test func aCollapsibleHeaderIsAButtonThatStatesItsState() throws {
        let header = try headerSource()
        #expect(header.contains("chevron.right"), "non-vacuity: still the group header")
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: header))
        let toggleBranch = try #require(body.range(of: "if isToggleEnabled {"))
        let elseBranch = try #require(body.range(of: "} else {"))
        let button = try #require(body.range(of: "Button(action: onToggle)"), "the collapsible header is no longer a Button")
        let value = try #require(
            body.range(of: ".accessibilityValue(TaskListGroupHeaderAccessibility.value(isCollapsed: isCollapsed))"),
            "the disclosure no longer states Expanded/Collapsed"
        )
        #expect(toggleBranch.lowerBound < button.lowerBound && value.lowerBound < elseBranch.lowerBound,
                "the Button or its value left the collapsible branch")
    }

    @Test func aHeaderThatCannotCollapseIsAHeadingNotADeadButton() throws {
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: try headerSource()))
        let elseBranch = try #require(body.range(of: "} else {"))
        let disabled = String(body[elseBranch.upperBound...])
        #expect(disabled.contains("headerContent"), "non-vacuity: the disabled branch draws the header")
        #expect(disabled.contains(".accessibilityAddTraits(.isHeader)"), "the non-collapsible header lost its header trait")
        #expect(!disabled.contains("Button("), "the non-collapsible header is a button again")
        #expect(!body.contains("if isToggleEnabled { onToggle() }"), "the no-op Button action is back")
    }

    @Test func theOverdueCapsuleCarriesItsLabelAndTooltip() throws {
        let header = try headerSource()
        #expect(header.contains("flag.fill"), "non-vacuity: the overdue capsule is still drawn here")
        #expect(header.contains(".accessibilityLabel(TaskListGroupHeaderAccessibility.overdueLabel(count: overdueCount))"))
        #expect(header.contains(".help(TaskListGroupHeaderAccessibility.overdueLabel(count: overdueCount))"))
        #expect(header.contains(".accessibilityElement(children: .ignore)"), "the glyph and number are read separately again")
    }
}
