import Foundation
import SwiftData
import Testing
@testable import Cadence

/// The inspector's rules, pinned once for both platforms. The iOS sheet used to answer these
/// questions differently from macOS — two rows where macOS had one breadcrumb, an editable minutes
/// picker where macOS reports a measurement — so the point of these tests is that there is now one
/// answer rather than two.
@MainActor
struct CadenceTaskInspectorSupportTests {

    // MARK: - Section segment visibility

    @Test
    func noSectionsMeansNoSegment() {
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(availableSections: []) == false)
    }

    @Test
    func loneDefaultSectionIsNotWorthAChevron() {
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(
            availableSections: [TaskSectionDefaults.defaultName]
        ) == false)
    }

    @Test
    func loneDefaultSectionIsRecognisedCaseInsensitively() {
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(availableSections: ["default"]) == false)
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(availableSections: ["DEFAULT"]) == false)
    }

    @Test
    func loneNamedSectionEarnsASegment() {
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(availableSections: ["Backlog"]))
    }

    @Test
    func severalSectionsAlwaysEarnASegment() {
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(
            availableSections: [TaskSectionDefaults.defaultName, "Doing"]
        ))
    }

    @Test
    func blankAndWhitespaceSectionsDoNotCount() {
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(availableSections: ["", "   "]) == false)
        #expect(CadenceTaskInspectorSupport.showsSectionSegment(
            availableSections: ["  \(TaskSectionDefaults.defaultName) ", " "]
        ) == false)
    }

    // MARK: - Section segment title

    @Test
    func unsetSectionReadsAsTheRealDefaultName() {
        #expect(CadenceTaskInspectorSupport.sectionSegmentTitle("") == TaskSectionDefaults.defaultName)
        #expect(CadenceTaskInspectorSupport.sectionSegmentTitle("   ") == TaskSectionDefaults.defaultName)
    }

    @Test
    func namedSectionKeepsItsNameTrimmed() {
        #expect(CadenceTaskInspectorSupport.sectionSegmentTitle("  Doing ") == "Doing")
    }

    // MARK: - Logged time

    @Test
    func noLoggedTimeReportsNothing() {
        #expect(CadenceTaskInspectorSupport.loggedLabel(minutes: 0) == nil)
        #expect(CadenceTaskInspectorSupport.loggedLabel(minutes: -30) == nil)
    }

    @Test
    func loggedTimeReadsLikeEveryOtherDurationInTheApp() {
        #expect(CadenceTaskInspectorSupport.loggedLabel(minutes: 45)
            == CadenceTaskPresentationSupport.estimateLabel(minutes: 45))
        #expect(CadenceTaskInspectorSupport.loggedLabel(minutes: 90)
            == CadenceTaskPresentationSupport.estimateLabel(minutes: 90))
    }

    // MARK: - Status actions

    @Test
    func statusActionsNeverTouchCompletion() {
        for action in CadenceTaskInspectorSupport.StatusAction.allCases {
            for current in TaskStatus.allCases {
                #expect(action.target(from: current) != .done)
            }
        }
    }

    /// One value since [[T-5015]] (b) retired In Progress; the set, and the uniqueness, still
    /// matter because the type is what three surfaces render.
    @Test
    func eachStatusActionOwnsExactlyOneValue() {
        let owned = CadenceTaskInspectorSupport.StatusAction.allCases.map(\.status)
        #expect(owned == [.cancelled])
        #expect(Set(owned).count == owned.count)
    }

    @Test
    func anInactiveActionMovesToItsOwnStatus() {
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.target(from: .todo) == .cancelled)
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.target(from: .done) == .cancelled)
        // A row still stored `.inprogress` — one the launch pass has not reached yet — can still
        // be cancelled from the inspector. The status is unwritable, not untouchable.
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.target(from: .inProgress) == .cancelled)
    }

    @Test
    func anActiveActionIsItsOwnUndo() {
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.target(from: .cancelled) == .todo)
    }

    @Test
    func activeStateFollowsTheTasksStatus() {
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.isActive(.cancelled))
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.isActive(.inProgress) == false)
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.isActive(.todo) == false)
    }

    @Test
    func labelsDescribeTheTapRatherThanTheState() {
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.title(for: .todo) == "Cancel")
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.title(for: .cancelled) == "Restore")
    }

    /// **[[T-7204]]: the iOS sheet's visible status button is "Cancel Task" / "Restore Task".**
    /// The shared `CadenceSchedulePanel` footer under it says "Cancel" and discards the edits; a
    /// bare "Cancel" here was a second button with that word and the opposite effect. The footer's
    /// literal is read from source so the collision this guards is the real one, not a copy.
    @Test
    func theIOSStatusButtonNamesTheTaskSoItIsNotASecondCancel() throws {
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.buttonTitle(for: .todo) == "Cancel Task")
        #expect(CadenceTaskInspectorSupport.StatusAction.cancelled.buttonTitle(for: .cancelled) == "Restore Task")

        let panel = try CadenceSourceScan.sourceFile("Cadence/Shared/Components/CadenceSchedulePanel.swift")
        #expect(panel.contains(#"Text(isReadOnly ? "Done" : "Cancel")"#),
                "non-vacuity: the panel footer no longer says Cancel; re-point this guard")
        var checked = 0
        for action in CadenceTaskInspectorSupport.StatusAction.allCases {
            for status in TaskStatus.allCases {
                #expect(action.buttonTitle(for: status) != "Cancel",
                        "\(status): the status button reads the same as the panel footer's Cancel again")
                checked += 1
            }
        }
        #expect(checked >= TaskStatus.allCases.count)

        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheetSections.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskStatusActionsSection: View", in: source)
        )
        #expect(body.contains("title: action.buttonTitle(for: task.status)"),
                "the iOS status button no longer draws the task-naming title (T-7204)")
        #expect(!body.contains("action.title(for:"), "the iOS status button is back on the bare shared word")
    }

    /// **[[T-7012]]: a cancelled task offers ONE way back to todo on the iOS sheet.** The completion
    /// button said "Reopen" beside "Restore", and both restored (T-344). Behavioural half: for every
    /// status, run each button the sheet draws on a real task and count the ones that land on
    /// `.todo`; the source half pins that the sheet asks the shared predicate.
    @Test
    func aCancelledTaskOffersOneWayBackToTodo() throws {
        var checked = 0
        for status in TaskStatus.allCases {
            var backToTodo = 0
            var completes = 0
            if CadenceTaskInspectorSupport.offersCompletionAction(for: status) {
                let (context, task) = try Self.makeTask(status)
                try CadenceTaskMutationSupport.toggleCompletion(task, modelContext: context, widgetEffects: CadenceTaskReopenWidgetEffects { _ in })
                if task.status == .todo { backToTodo += 1 }
                if task.status == .done { completes += 1 }
            }
            for action in CadenceTaskInspectorSupport.StatusAction.allCases
                where action.target(from: status) == .todo {
                backToTodo += 1
            }
            if status == .cancelled {
                #expect(backToTodo == 1, "a cancelled task shows \(backToTodo) ways back to todo")
                #expect(completes == 0, "a cancelled task can be completed from the sheet (T-344)")
            }
            if status == .done { #expect(backToTodo == 1) }
            checked += 1
        }
        #expect(checked >= 3, "non-vacuity: todo, done and cancelled at least")
        #expect(CadenceTaskInspectorSupport.offersCompletionAction(for: .todo))
        #expect(CadenceTaskInspectorSupport.offersCompletionAction(for: .done))

        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskDetailSheetSections.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("struct iOSTaskStatusActionsSection: View", in: source)
        )
        let gate = try #require(body.range(of: "if CadenceTaskInspectorSupport.offersCompletionAction(for: task.status) {"),
                                "the iOS completion button is no longer gated on the shared predicate (T-7012)")
        let button = try #require(body.range(of: #"title: isFinished ? "Reopen" : "Complete""#))
        #expect(gate.upperBound <= button.lowerBound, "the gate no longer encloses the completion button")
    }

    private static func makeTask(_ status: TaskStatus) throws -> (ModelContext, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Status")
        task.status = status
        context.insert(task)
        try context.save()
        return (context, task)
    }

    @Test
    func everyActionHasAGlyphInBothStates() {
        for action in CadenceTaskInspectorSupport.StatusAction.allCases {
            #expect(action.systemImage(for: .todo).isEmpty == false)
            #expect(action.systemImage(for: action.status).isEmpty == false)
            #expect(action.systemImage(for: .todo) != action.systemImage(for: action.status))
        }
    }
}
