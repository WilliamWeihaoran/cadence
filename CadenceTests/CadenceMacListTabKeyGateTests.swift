// macOS only: the list page's key monitor and the root gates it shares are macOS concerns.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-19002]] — the Mac list page's Cmd-Shift-[ / ] stands down where the root's commands do.**
///
/// The chord is a key monitor of the page's own, so it never passed the root's modal gates and
/// flipped (and remembered) the list's tab behind the Cmd+K palette, the delete and date
/// confirmations, the New Task panel, the Edit List sheet and the global quick-task panel.
@Suite("Mac list tab key gate")
struct CadenceMacListTabKeyGateTests {
    private func steps(
        hasModal: Bool = false,
        isSearchPresented: Bool = false,
        isQuickTaskPanelVisible: Bool = false,
        isTaskCreationPresented: Bool = false,
        isSheetPresented: Bool = false
    ) -> Bool {
        ListDetailTabKeyGate.steps(
            hasModal: hasModal,
            isSearchPresented: isSearchPresented,
            isQuickTaskPanelVisible: isQuickTaskPanelVisible,
            isTaskCreationPresented: isTaskCreationPresented,
            isSheetPresented: isSheetPresented
        )
    }

    @Test func theChordStepsWithNothingUp() {
        #expect(steps())
    }

    @Test func aConfirmationRefusesIt() {
        #expect(!steps(hasModal: true))
    }

    @Test func thePaletteRefusesIt() {
        #expect(!steps(isSearchPresented: true))
    }

    @Test func theQuickTaskPanelRefusesIt() {
        #expect(!steps(isQuickTaskPanelVisible: true))
    }

    @Test func theNewTaskPanelRefusesIt() {
        #expect(!steps(isTaskCreationPresented: true))
    }

    @Test func aSheetRefusesIt() {
        #expect(!steps(isSheetPresented: true))
    }

    /// Wherever a root command may run and no creation panel or sheet is up, the chord may too.
    @Test func itAgreesWithTheRootGateWhereNeitherPageInputIsSet() {
        for bits in 0..<8 {
            let modal = bits & 1 != 0, search = bits & 2 != 0, panel = bits & 4 != 0
            #expect(
                steps(hasModal: modal, isSearchPresented: search, isQuickTaskPanelVisible: panel)
                    == RootViewMenuGate.runs(hasModal: modal, isSearchPresented: search, isQuickTaskPanelVisible: panel)
            )
        }
    }

    /// The monitor asks the gate before it steps, and feeds it every state it refuses.
    @Test func theMonitorAsksTheGateBeforeItSteps() throws {
        let source = try CadenceSourceScan.strippedSourceReader()("Cadence/macOS/Views/ListDetailView.swift")
        let body = try #require(CadenceSourceScan.declarationBody("private func installKeyMonitorIfNeeded()", in: source))
        let gate = try #require(body.range(of: "ListDetailTabKeyGate.steps("))
        let step = try #require(body.range(of: "moveTab(by:"))
        #expect(gate.lowerBound < step.lowerBound)
        for input in [
            "deleteConfirmationManager.request",
            "hoveredTaskDatePickerManager.request",
            "globalSearchManager.isPresented",
            "QuickTaskPanelController.shared.isVisible",
            "taskCreationManager.isPresented",
            "showEdit",
            "attachedSheet",
        ] {
            #expect(body.contains(input), "the gate is fed \(input)")
        }
    }
}
#endif
