// macOS only: the Kanban board, list header and Completed tab are macOS app types.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **The Mac list page and its Kanban board say what their controls are ([[T-7080]]..[[T-7084]]).**
///
/// Five controls on the list detail page read to VoiceOver as less than they show: the project
/// deadline chip as a bare date, the board's "Completed N" disclosure with no Expanded/Collapsed
/// value, the add-column rail as an unnamed "+", the card's completion circle as an unnamed
/// button, and a Completed-tab row with nothing to say whether the task was finished or canceled.
@MainActor
struct CadenceMacTaskBoardAccessibilityTests {
    private func source(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: T-7080

    @Test func theDeadlineChipSaysWhoseDateItIsOnBothHeaders() throws {
        #expect(ListDetailHeaderAccessibility.deadlineLabel(dueDate: "2026-10-30")
                == "Deadline \(DateFormatters.shortDateString(from: "2026-10-30"))")

        let mac = try source("Cadence/macOS/Views/ListDetailView.swift")
        let header = try #require(CadenceSourceScan.declarationBody("private var header: some View", in: mac))
        #expect(header.contains("project.dueDate"), "non-vacuity: the deadline chip is still drawn here")
        #expect(header.contains(".accessibilityLabel(ListDetailHeaderAccessibility.deadlineLabel(dueDate: project.dueDate))"),
                "the Mac deadline chip reads as a bare date again")
        #expect(header.contains(".accessibilityElement(children: .ignore)"))

        let iOS = try source("Cadence/iOS/iOSListDetailView.swift")
        #expect(iOS.contains(".accessibilityLabel(ListDetailHeaderAccessibility.deadlineLabel(dueDate: projectDueDate))"),
                "iOS spells its own deadline label again")
    }

    // MARK: T-7081

    @Test func theBoardCompletedDisclosureStatesItsState() throws {
        let file = try source("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        let toggle = try #require(CadenceSourceScan.declarationBody("struct KanbanCompletedTasksToggle: View", in: file))
        #expect(toggle.contains("Text(\"Completed\")"), "non-vacuity: still the Completed disclosure")
        #expect(toggle.contains(".accessibilityValue(TaskListGroupHeaderAccessibility.value(isCollapsed: !isExpanded))"),
                "the board's Completed disclosure no longer states Expanded/Collapsed")
    }

    // MARK: T-7082

    @Test func theAddColumnRailIsNamed() throws {
        #expect(KanbanBoardSupport.addColumnLabel == "Add column")
        let file = try source("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        let rail = try #require(CadenceSourceScan.declarationBody("private var addSectionRail: some View", in: file))
        #expect(rail.contains("addSection()"), "non-vacuity: still the add-column rail")
        #expect(rail.contains(".cadenceControlLabel(KanbanBoardSupport.addColumnLabel)"),
                "the add-column rail is an unnamed + again")
    }

    // MARK: T-7083

    @Test func theCardCompletionCircleIsNamedForItsState() throws {
        let support = try source("Cadence/macOS/Views/KanbanCardSupportViews.swift")
        let button = try #require(CadenceSourceScan.declarationBody("struct KanbanCompletionButton: View", in: support))
        #expect(button.contains("TaskCompletionProgressGlyph("), "non-vacuity: still the card's completion circle")
        #expect(button.contains(".accessibilityLabel(accessibilityLabel)"), "the card's completion circle is unnamed again")

        let card = try source("Cadence/macOS/Views/KanbanCardView.swift")
        let label = try #require(CadenceSourceScan.declarationBody("private var completionAccessibilityLabel: String", in: card))
        #expect(label.contains(".state.accessibilityActionLabel"),
                "the card no longer reads the list row's shared action phrase")
        let header = try #require(CadenceSourceScan.declarationBody("private var cardHeader: some View", in: card))
        #expect(header.components(separatedBy: "completionAccessibilityLabel: completionAccessibilityLabel").count - 1 == 2,
                "both arms of the card header must pass the label")
    }

    // MARK: T-7084

    @Test func aCompletedTabRowSaysWhetherItWasFinishedOrCanceled() throws {
        let done = AppTask(title: "Ship it")
        done.status = .done
        let cancelled = AppTask(title: "Drop it")
        cancelled.status = .cancelled
        #expect(ListLogRowPresentation.statusLabel(for: done) == "Completed")
        #expect(ListLogRowPresentation.statusLabel(for: cancelled) == "Canceled")

        let file = try source("Cadence/macOS/Views/ListDetailSupportViews.swift")
        #expect(file.contains("Image(systemName: glyph.symbolName)"), "non-vacuity: the Completed tab row glyph")
        #expect(file.contains(".accessibilityLabel(ListLogRowPresentation.statusLabel(for: task))"),
                "the Completed tab's glyph reads as nothing again")
    }
}

#endif
