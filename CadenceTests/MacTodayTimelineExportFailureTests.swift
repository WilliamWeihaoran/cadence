#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-18925]] -- the Mac Today timeline's Export swallowed a refused write.**
///
/// `SchedulePanel`'s `.fileExporter` completion was `{ _ in exportDocument = nil }`, the one
/// exporter in the app with an empty failure branch: a destination that refused the write closed
/// the panel and said nothing. The completion now asks
/// `SchedulePanelDataSupport.exportFailureMessage(for:)` and puts the note export's alert up.
@MainActor
struct MacTodayTimelineExportFailureTests {
    @Test func aRefusedWriteYieldsTheNoteExportSentence() {
        let refused = CocoaError(.fileWriteNoPermission)
        let message = SchedulePanelDataSupport.exportFailureMessage(for: .failure(refused))
        #expect(message == NoteExportSupport.writeFailureMessage(refused.localizedDescription))
    }

    @Test func aWrittenFileOrACancelSaysNothing() {
        let url = URL(fileURLWithPath: "/nonexistent/Schedule.md")
        #expect(SchedulePanelDataSupport.exportFailureMessage(for: .success(url)) == nil)
        #expect(SchedulePanelDataSupport.exportFailureMessage(for: .failure(CocoaError(.userCancelled))) == nil)
    }

    /// The panel routes its completion through the helper and shows the shared title.
    @Test func thePanelReportsTheResultRatherThanDiscardingIt() throws {
        let read = CadenceSourceScan.strippedSourceReader()
        let panel = try read("Cadence/macOS/Views/SchedulePanel.swift")
        #expect(panel.contains("SchedulePanelDataSupport.exportFailureMessage(for: result)"))
        #expect(panel.contains("NoteExportSupport.failureAlertTitle"))
        #expect(!panel.contains("Export Failed"), "the alert title is re-spelled")
    }
}
#endif
