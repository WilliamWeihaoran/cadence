import Foundation
import Testing
@testable import Cadence

/// T-5014: **the macOS task inspector's inline notes box drew embedded-task cards that did nothing
/// when clicked.**
///
/// `MarkdownEditor` renders `[[task:…]]` embeds as live cards whenever its host passes
/// `referenceTasks:`, and every click on a card — the checkbox, a subtask checkbox, the card body, a
/// field chip — is routed to a closure whose default is a no-op. `TaskDetailNotesSection` passed the
/// tasks and none of the closures, so the cards looked live and were inert, while
/// `TaskNoteEditorPane` (the same notes, one click away) wired all of them.
///
/// The closures are private to SwiftUI views and cannot be driven from a unit test, so the rule is
/// pinned as source text: every `MarkdownEditor(` call under `Cadence/macOS/` that passes
/// `referenceTasks:` also passes each card and task-link handler. The template editor passes none,
/// draws no live cards and is outside the rule. `FocusNotesPanel` joined the live-card hosts in
/// [[T-5060]] (c) and is pinned by name below.
@MainActor
struct CadenceMarkdownEditorEmbedWiringTests {

    /// The handlers a host that draws live cards owes the editor. `onHoverEmbeddedTask` is left
    /// out on purpose: a missing hover handler costs a keyboard shortcut, not a click that does
    /// nothing.
    static let requiredHandlers = [
        "onOpenTaskReference:",
        "onCreateEmbeddedTask:",
        "onToggleEmbeddedTask:",
        "onToggleEmbeddedSubtask:",
        "onRenameEmbeddedTask:",
        "onOpenEmbeddedTask:",
        "onEditEmbeddedTask:",
        "onTextViewChanged:",
    ]

    /// Every `MarkdownEditor(` call's argument list under `Cadence/macOS/`, with its file.
    private static func editorCalls() throws -> [(path: String, arguments: String)] {
        var calls: [(path: String, arguments: String)] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/macOS") {
            let source = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            var searchStart = source.startIndex
            while let hit = source.range(of: "MarkdownEditor(", range: searchStart..<source.endIndex) {
                // `MarkdownEditor(` only, not `SomethingMarkdownEditor(`.
                let isWholeName = hit.lowerBound == source.startIndex
                    || !(source[source.index(before: hit.lowerBound)].isLetter
                         || source[source.index(before: hit.lowerBound)].isNumber
                         || source[source.index(before: hit.lowerBound)] == "_")
                let openParen = source.index(before: hit.upperBound)
                if isWholeName,
                   let arguments = CadenceSourceScan.matchedBody(after: openParen, in: source, open: "(", close: ")") {
                    calls.append((path, arguments))
                }
                searchStart = hit.upperBound
            }
        }
        return calls
    }

    @Test func everyEditorThatDrawsLiveTaskCardsWiresTheirClicks() throws {
        let liveCardHosts = try Self.editorCalls().filter { $0.arguments.contains("referenceTasks:") }

        // Non-vacuity: the five hosts that draw live cards today — the core-note panel, the Notes
        // page, the list/task note pane, the inspector box this ticket is about, and Focus's
        // notes (T-5060 (c)).
        #expect(liveCardHosts.count >= 5)
        #expect(liveCardHosts.contains { $0.path.hasSuffix("TaskInspectorContentSupportViews.swift") })
        #expect(liveCardHosts.contains { $0.path.hasSuffix("FocusNotesPanel.swift") })

        for host in liveCardHosts {
            for handler in Self.requiredHandlers {
                #expect(
                    host.arguments.contains(handler),
                    "\(host.path) passes referenceTasks: to MarkdownEditor but not \(handler)"
                )
            }
        }
    }

    /// The inspector box specifically, by name, so a refactor that moves it out of the file the
    /// sweep above recognises cannot drop it from the rule silently.
    @Test func theInspectorNotesBoxWiresEveryCardHandler() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TaskInspectorContentSupportViews.swift")
        )
        let section = try #require(CadenceSourceScan.declarationBody("struct TaskDetailNotesSection", in: source))
        let call = try #require(section.range(of: "MarkdownEditor("))
        let arguments = try #require(
            CadenceSourceScan.matchedBody(after: section.index(before: call.upperBound), in: section, open: "(", close: ")")
        )
        #expect(arguments.contains("referenceTasks:"))
        for handler in Self.requiredHandlers {
            #expect(arguments.contains(handler), "TaskDetailNotesSection does not pass \(handler)")
        }
    }

    /// T-5060 (c): Focus's task notes resolve `[[task:…]]` embeds as cards, and every click on one
    /// is wired. Before this it passed no `referenceTasks:`, so the embeds drew unresolved.
    @Test func theFocusNotesPanelResolvesEmbedsAndWiresEveryCardHandler() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/FocusNotesPanel.swift")
        )
        let panel = try #require(CadenceSourceScan.declarationBody("struct FocusNotesPanel", in: source))
        let call = try #require(panel.range(of: "MarkdownEditor("))
        let arguments = try #require(
            CadenceSourceScan.matchedBody(after: panel.index(before: call.upperBound), in: panel, open: "(", close: ")")
        )
        #expect(arguments.contains("referenceTasks:"))
        for handler in Self.requiredHandlers {
            #expect(arguments.contains(handler), "FocusNotesPanel does not pass \(handler)")
        }
    }
}
