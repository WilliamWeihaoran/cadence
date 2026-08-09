import Foundation
import Testing

struct NoteEditorPerformanceRegressionTests {
    @Test func coreNotePanelDoesNotPersistEveryEditorChange() throws {
        let source = try sourceFile("Cadence/macOS/Views/NotePanel.swift")

        #expect(source.contains("text: coreNoteContentBinding(for: note)"))
        #expect(source.contains("fallbackContentCommitDelay: UInt64 = 15_000_000_000"))
        #expect(!source.matches(#"set:\s*\{\s*note\.content\s*=\s*\$0\s*\}"#))
        #expect(!source.matches(#"set:\s*\{\s*update\(note:\s*note,\s*content:\s*\$0\)\s*\}"#))
    }

    @Test func taskNoteEditorsDoNotPersistEveryEditorChange() throws {
        let taskInspectorSource = try sourceFile("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        let focusSource = try sourceFile("Cadence/macOS/Views/FocusNotesPanel.swift")
        let timingSource = try sourceFile("Cadence/macOS/Views/MarkdownEditorSyncTiming.swift")

        #expect(taskInspectorSource.contains("text: taskNotesBinding"))
        #expect(focusSource.contains("text: taskNotesBinding"))
        #expect(timingSource.contains("fallbackContentCommitDelay: UInt64 = 15_000_000_000"))
        #expect(taskInspectorSource.contains("MarkdownEditorSyncTiming.fallbackContentCommitDelay"))
        #expect(focusSource.contains("MarkdownEditorSyncTiming.fallbackContentCommitDelay"))
        #expect(!taskInspectorSource.matches(#"set:\s*\{\s*task\.notes\s*=\s*\$0\s*\}"#))
        #expect(!focusSource.matches(#"set:\s*\{\s*task\.notes\s*=\s*\$0\s*\}"#))
    }

    @Test func markdownStylingRestylesSynchronouslyOnEveryKeystroke() throws {
        // Styling used to be debounced (~180ms) to amortize the cost of recompiling
        // NSRegularExpression patterns on every call. That regex-compilation cost is
        // now eliminated (patterns are cached `static let`s), and the debounce's
        // remaining effect was a visible "plain text, then pop to styled" delay on
        // every list/heading/quote/divider marker. textDidChange now restyles
        // immediately, matching textDidEndEditing's existing immediate call — no
        // debounce scaffolding should remain.
        let source = try sourceFile("Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift")

        #expect(!source.contains("stylingDebounceDelay"))
        #expect(!source.contains("pendingStylingWorkItem"))
        #expect(!source.contains("scheduleStylingUpdate"))
        #expect(source.contains("applyStyling(to: textView, in: textView.enclosingScrollView)"))
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repositoryRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

private extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}
