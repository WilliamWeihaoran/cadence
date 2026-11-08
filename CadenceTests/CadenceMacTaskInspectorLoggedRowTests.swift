// macOS only: `TaskDetailPopover` is a macOS view.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-13565]]: the Mac task inspector draws the read-only "Logged" row the iOS sheet draws
/// (`iOSTaskFieldListSection.loggedRow`), fed by the same shared helper, and only when there is
/// focus time to report. Read-only: the figure is measured by the focus timer, never typed
/// (T-1278), so the row's trailing content is a `Text`, not a control.
@MainActor
struct CadenceMacTaskInspectorLoggedRowTests {
    private func makeTask(actualMinutes: Int) throws -> (ModelContext, AppTask) {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let context = ModelContext(container)
        let task = AppTask(title: "Logged")
        task.actualMinutes = actualMinutes
        context.insert(task)
        return (context, task)
    }

    private static func recordSections() throws -> String {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelComponents.swift")
        )
        return try #require(
            CadenceSourceScan.declarationBody("private var recordSections: some View", in: source)
        )
    }

    /// A task with logged focus time reports it, in the iOS row's wording.
    @Test func aTaskWithLoggedTimeGetsALoggedLabel() throws {
        let (_, task) = try makeTask(actualMinutes: 45)
        let label = try #require(TaskDetailPopover.loggedLabel(for: task))
        #expect(label == CadenceTaskInspectorSupport.loggedLabel(minutes: 45))
    }

    /// A task with none gets no label, and so no row.
    @Test func aTaskWithNoLoggedTimeGetsNoLoggedLabel() throws {
        let (_, task) = try makeTask(actualMinutes: 0)
        #expect(TaskDetailPopover.loggedLabel(for: task) == nil)
    }

    /// The inspector draws the row only under that label, as a read-only `Text`.
    @Test func theInspectorDrawsTheLoggedRowOnlyWhenThereIsALabel() throws {
        let body = try Self.recordSections()
        #expect(body.contains("if let logged = Self.loggedLabel(for: task) {"),
                "the Logged row is no longer gated on the shared label")
        #expect(body.contains(#"CadenceFieldRow(label: "Logged", systemImage: "stopwatch")"#),
                "the Logged row is gone, or drawn with another label or glyph")
        #expect(CadenceSourceScan.matchCount(#"CadenceFieldRow\(label: "Logged""#, in: body) == 1)
        let row = try #require(
            CadenceSourceScan.declarationBody(#"CadenceFieldRow(label: "Logged", systemImage: "stopwatch")"#, in: body)
        )
        #expect(row.contains("Text(logged)"), "the row no longer reports the label")
        #expect(CadenceSourceScan.matchCount(#"(TextField|Stepper|Picker|Button)\b"#, in: row) == 0,
                "the Logged row grew an editor; logged time is measured, not typed (T-1278)")
    }
}
#endif
