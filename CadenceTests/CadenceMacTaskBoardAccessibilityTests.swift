// macOS only: the Kanban board, list header and Completed tab are macOS app types.
#if os(macOS)
import Foundation
import SwiftData
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
        // [[T-8181]]: the circle moved out of the card header and into the Ledger card's state
        // gutter, so the two arms — settling and not — live in `completionRing`. Both must still
        // pass the label, which is the whole of what T-7083 asked for.
        let ring = try #require(CadenceSourceScan.declarationBody("private var completionRing: some View", in: card))
        #expect(ring.components(separatedBy: "accessibilityLabel: completionAccessibilityLabel").count - 1 == 2,
                "both arms of the card's completion ring must pass the label")
    }

    // MARK: T-8185

    /// The slot token was the one token in the Ledger run that was not a picker. It is now a
    /// `KanbanLedgerTokenButton` opening the inspector's own `CadenceTimeRoller`, held in a draft
    /// so a fling does not write once per row ([[T-1431]]'s shape).
    @Test func theSlotTokenIsAPickerOverTheInspectorsTimeRoller() throws {
        let card = try source("Cadence/macOS/Views/KanbanCardView.swift")
        let control = try #require(CadenceSourceScan.declarationBody("private func tokenControl(", in: card))
        let timeStart = try #require(control.range(of: "case .time:"), "non-vacuity: the slot arm is still here")
        let timeEnd = try #require(control.range(of: "case .duration:", range: timeStart.upperBound..<control.endIndex))
        let timeArm = String(control[timeStart.upperBound..<timeEnd.lowerBound])
        #expect(timeArm.contains("KanbanLedgerTokenButton("), "the slot token is a plain label again")
        #expect(timeArm.contains("action: openStartTimePicker"))
        #expect(timeArm.contains("KanbanStartTimePickerPopover(task: task, isPresented: $showStartTimePicker)"),
                "the slot token no longer opens the start-time picker")
        #expect(!control.contains("CadenceLedgerTokenLabel("), "a token in the run is drawn as a dead label again")
        let presenting = try #require(CadenceSourceScan.declarationBody("private var isPresentingInlinePopover: Bool", in: card))
        #expect(presenting.contains("showStartTimePicker"),
                "an open start-time picker no longer counts as an inline popover, so a click through it opens the inspector")

        let support = try source("Cadence/macOS/Views/KanbanCardSupportViews.swift")
        let popover = try #require(CadenceSourceScan.declarationBody("struct KanbanStartTimePickerPopover: View", in: support))
        #expect(popover.contains("CadenceTimeRoller(minutes: $draftMinutes)"),
                "the card's picker is not the inspector's roller over its own draft")
        #expect(!popover.contains("$task."), "the roller is bound straight to the task, one write per row crossed")
        #expect(popover.contains("KanbanCardStateSupport.commitStartMinute(draftMinutes, for: task, in: modelContext)"))
        #expect(popover.contains("CadenceTaskDateEditing.clearScheduledTime(task, in: modelContext)"))
    }

    @Test func theCardsStartTimeLandsOnceAndOnlyWhenItMoved() throws {
        let context = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let task = AppTask(title: "Slot")
        task.scheduledDate = "2026-03-01"
        task.scheduledStartMin = 9 * 60
        context.insert(task)
        try context.save()

        var reconciles = 0
        let reconciler = CadenceWindDownReconciler { _ in reconciles += 1 }

        #expect(!KanbanCardStateSupport.commitStartMinute(9 * 60, for: task, in: context, reconciler: reconciler),
                "opening and closing the picker on the same minute wrote anyway")
        #expect(reconciles == 0)
        #expect(task.scheduledStartMin == 9 * 60)

        #expect(KanbanCardStateSupport.commitStartMinute(10 * 60 + 5, for: task, in: context, reconciler: reconciler))
        #expect(task.scheduledStartMin == 10 * 60 + 5, "the picked minute did not land")
        #expect(reconciles == 1, "the start-time write skipped the wind-down reconcile (T-362)")
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
