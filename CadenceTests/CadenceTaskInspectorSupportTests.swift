import Foundation
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

    @Test
    func everyActionHasAGlyphInBothStates() {
        for action in CadenceTaskInspectorSupport.StatusAction.allCases {
            #expect(action.systemImage(for: .todo).isEmpty == false)
            #expect(action.systemImage(for: action.status).isEmpty == false)
            #expect(action.systemImage(for: .todo) != action.systemImage(for: action.status))
        }
    }
}
