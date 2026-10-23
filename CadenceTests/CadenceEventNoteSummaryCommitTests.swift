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
        #expect(sheet.contains("summaryHeaderAccessory: { appendSummary in"))
        #expect(sheet.contains("NoteActionMenu(note: note, onAppendSummary: appendSummary)"))
        #expect(!sheet.contains("NoteActionMenu(note: note)"))
        #expect(sheet.contains("onPersistContent: commitEventNote"))
    }

    @Test func thePanesAppendFlushesThenPersistsThroughTheHostsCommit() throws {
        let pane = try codeOnly("Cadence/macOS/Views/NoteEditorPane.swift")
        #expect(pane.contains("summaryHeaderAccessory(appendSummary)"))
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

private func codeOnly(_ relativePath: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    return CadenceSourceScan.strippingComments(source)
}
