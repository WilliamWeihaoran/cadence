import Foundation
import Testing

@testable import Cadence

/// **T-5162.** The macOS meeting-note sheet's Summarize used `NoteActionMenu`'s default append — a
/// bare store write that skipped the sheet's `commitEventNote`, so the summary never reached Apple
/// Calendar, and left the pane's buffer stale for the next flush to write back over it.
///
/// Source-shape pins: the sheet is not hostable in a unit test (EventKit, a live editor), and the
/// regression is the menu being drawn without `onAppendSummary` again, or the pane appending
/// before it flushes.
@MainActor
struct CadenceEventNoteSummaryCommitTests {
    @Test func theMeetingNoteSheetRoutesSummarizeThroughThePanesAppend() throws {
        let sheet = try codeOnly("Cadence/macOS/Views/EventNoteSupportViews.swift")
        #expect(sheet.contains("struct EventNoteEditorSheet: View"), "non-vacuity: wrong file read")
        #expect(sheet.contains("summaryHeaderAccessory: { appendSummary, flushPendingContent in"))
        #expect(sheet.contains("NoteActionMenu(note: note, onAppendSummary: appendSummary, flushPendingContent: flushPendingContent)"))
        #expect(!sheet.contains("NoteActionMenu(note: note)"))
        #expect(sheet.contains("onPersistContent: commitEventNote"))
    }

    @Test func thePanesAppendFlushesThenPersistsThroughTheHostsCommit() throws {
        let pane = try codeOnly("Cadence/macOS/Views/NoteEditorPane.swift")
        #expect(pane.contains("summaryHeaderAccessory(appendSummary, flushPendingEditorContent)"))
        let start = try #require(pane.range(of: "private func appendSummary(_ summary: String) {"))
        let end = try #require(pane.range(of: "private func replaceEditorContent(", range: start.upperBound..<pane.endIndex))
        let body = String(pane[start.upperBound..<end.lowerBound])
        let flush = try #require(body.range(of: "flushPendingEditorContent()"))
        let append = try #require(body.range(of: "CadenceAINoteSummary.appending(summary, to: note.content)"))
        let replace = try #require(body.range(of: "replaceEditorContent(content)"))
        #expect(flush.lowerBound < append.lowerBound)
        #expect(append.lowerBound < replace.lowerBound)
        // `replaceEditorContent` is what reaches the host: it persists through `onPersistContent`.
        _ = try #require(pane.range(of: "persistEditorContentIfNeeded(content, noteID: note.id)", range: end.upperBound..<pane.endIndex))
    }

    /// **T-5211.** The pane's default menu — the Notes page and a list's Notes tab, every
    /// `NoteEditorPane` that passes no accessory — routes Summarize through the same append, not the
    /// menu's bare store write that the next flush overwrote.
    @Test func thePanesDefaultMenuRoutesSummarizeThroughThePanesAppend() throws {
        let pane = try codeOnly("Cadence/macOS/Views/NoteEditorPane.swift")
        let start = try #require(pane.range(of: "private var headerControls: some View {"))
        let end = try #require(pane.range(of: "var body: some View {", range: start.upperBound..<pane.endIndex))
        let controls = String(pane[start.upperBound..<end.lowerBound])
        let menu = try #require(controls.range(of: "NoteActionMenu("), "non-vacuity: the default menu moved")
        let menuCall = String(controls[menu.lowerBound...])
        let close = try #require(menuCall.range(of: "onDelete: onDelete"))
        #expect(String(menuCall[..<close.lowerBound]).contains("onAppendSummary: appendSummary"))
    }
}

/// **[[T-9651]].** The Actions popover's Export, Summarize and Extract Tasks read `note.content`,
/// while a Mac editor holds up to 15 s of typing in its own buffer and a click on the pill moves no
/// first responder. Each read now runs the host editor's flush first, and every host hands it in.
@MainActor
struct CadenceNoteActionMenuFlushTests {
    @Test func everyReadOfTheNoteRunsTheHostsFlushFirst() throws {
        let menuFile = try codeOnly("Cadence/macOS/Views/AIActionsSupportViews.swift")
        let start = try #require(menuFile.range(of: "struct NoteActionMenu: View {"))
        let end = try #require(menuFile.range(of: "private enum NoteActionPickerMetrics", range: start.upperBound..<menuFile.endIndex))
        let menu = String(menuFile[start.upperBound..<end.lowerBound])
        #expect(menu.contains("var flushPendingContent: () -> Void = {}"), "non-vacuity: the menu takes no flush")

        // Export: the flush precedes the export call inside the row's action.
        let export = try #require(menu.range(of: "NoteExportService.export("), "non-vacuity: the export row moved")
        let exportRow = try #require(menu.range(of: "NoteActionPickerRow(icon: format.systemImage", options: .backwards, range: menu.startIndex..<export.lowerBound))
        #expect(menu[exportRow.upperBound..<export.lowerBound].contains("flushPendingContent()"), "Export reads the note before the editor's held typing reaches it")

        // Summarize and Extract Tasks: each function flushes before it builds the note context.
        for function in ["private func runSummary() {", "private func runTaskExtraction() {"] {
            let head = try #require(menu.range(of: function), "non-vacuity: \(function) moved")
            let read = try #require(menu.range(of: "AIActionService.noteContext(note: note", range: head.upperBound..<menu.endIndex))
            #expect(menu[head.upperBound..<read.lowerBound].contains("flushPendingContent()"), "\(function) reads the note before the editor's held typing reaches it")
        }
    }

    @Test func everyHostHandsTheMenuItsEditorsFlush() throws {
        let pane = try codeOnly("Cadence/macOS/Views/NoteEditorPane.swift")
        let panel = try codeOnly("Cadence/macOS/Views/NotePanel.swift")
        let sheet = try codeOnly("Cadence/macOS/Views/EventNoteSupportViews.swift")
        let calls = [pane, panel, sheet].map { $0.components(separatedBy: "NoteActionMenu(").count - 1 }
        #expect(calls == [1, 1, 1], "non-vacuity: the menu's call sites changed: \(calls)")
        #expect(pane.contains("flushPendingContent: flushPendingEditorContent"), "the Notes page / list Notes menu gets no flush")
        #expect(pane.contains("summaryHeaderAccessory(appendSummary, flushPendingEditorContent)"), "the meeting-note sheet's menu gets no flush")
        #expect(panel.contains("flushPendingContent: flushPendingEditorContent"), "the Today notes column's menu gets no flush")
        #expect(sheet.contains("flushPendingContent: flushPendingContent)"), "the meeting-note sheet drops the pane's flush")
    }
}

private func codeOnly(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    return CadenceSourceScan.strippingComments(source)
}
