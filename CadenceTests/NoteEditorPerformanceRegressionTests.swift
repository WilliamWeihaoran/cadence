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
        let focusSource = try sourceFile("Cadence/macOS/Views/FocusViewSupportViews.swift")

        #expect(taskInspectorSource.contains("text: taskNotesBinding"))
        #expect(focusSource.contains("text: taskNotesBinding"))
        #expect(taskInspectorSource.contains("fallbackContentCommitDelay: UInt64 = 15_000_000_000"))
        #expect(focusSource.contains("fallbackContentCommitDelay: UInt64 = 15_000_000_000"))
        #expect(!taskInspectorSource.matches(#"set:\s*\{\s*task\.notes\s*=\s*\$0\s*\}"#))
        #expect(!focusSource.matches(#"set:\s*\{\s*task\.notes\s*=\s*\$0\s*\}"#))
    }

    @Test func markdownStylingUsesDebounceInsteadOfPerKeystrokeRestyle() throws {
        let source = try sourceFile("Cadence/macOS/Editor/MarkdownEditorInteractionSupport.swift")

        #expect(source.contains("stylingDebounceDelay"))
        #expect(source.contains("pendingStylingWorkItem?.cancel()"))
        #expect(source.contains("scheduleStylingUpdate(for: textView)"))
        #expect(!source.contains("stylingCoalescingDelay"))
        #expect(!source.contains("stylingUpdateIsScheduled"))
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
