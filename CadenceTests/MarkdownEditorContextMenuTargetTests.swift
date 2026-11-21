import Foundation
import Testing
@testable import Cadence

/// **[[T-18882]] — a task card embedded in a note opens the task menu, as every other task surface does.**
///
/// The decision is `MarkdownEditorContextMenuTarget.classify`, and both editors' menus consult it:
/// a rendered table cell first, then a revealed table, then a task card, otherwise the text view's
/// own menu. The probes here read a fixture note by UTF-16 location -- the table by
/// `MarkdownTableEditor`, the card by `MarkdownTaskEmbedParser` -- standing in for each editor's
/// geometric hit test, which needs a laid-out text view.
struct MarkdownEditorContextMenuTargetTests {
    private static let taskID = UUID(uuidString: "2B1F4F8E-7A43-4F4B-9D7A-3C3F0B6A9E11")!
    private static let fixture = """
    Intro line

    | A | B |
    | --- | --- |
    | 1 | 2 |

    [[task:\(taskID.uuidString)|Call the bank]]

    Closing prose
    """

    private enum Kind: Equatable {
        case tableCell
        case revealedTable(Int)
        case taskEmbed(UUID)
        case text
    }

    private static func location(of needle: String) -> Int {
        (fixture as NSString).range(of: needle).location
    }

    /// The card's id when `location` falls inside a standalone `[[task:…]]` line of the fixture.
    private static func embedID(at location: Int) -> UUID? {
        let text = fixture as NSString
        let line = text.lineRange(for: NSRange(location: location, length: 0))
        guard let reference = MarkdownTaskEmbedParser.standaloneTaskReference(
            in: text.substring(with: line),
            lineStart: line.location
        ), NSLocationInRange(location, reference.range) else { return nil }
        return reference.id
    }

    private static func revealedAnchor(at location: Int) -> Int? {
        MarkdownTableEditor.grid(containingUTF16Location: location, in: fixture)?.storageRange.location
    }

    private func classify(at location: Int, tableCell: Bool = false, tableRevealed: Bool = true) -> Kind {
        let target = MarkdownEditorContextMenuTarget<Int>.classify(
            tableCell: { tableCell ? location : nil },
            revealedTableAnchor: { tableRevealed ? Self.revealedAnchor(at: location) : nil },
            taskEmbedID: { Self.embedID(at: location) }
        )
        switch target {
        case .tableCell: return .tableCell
        case .revealedTable(let anchor): return .revealedTable(anchor)
        case .taskEmbed(let id): return .taskEmbed(id)
        case .text: return .text
        }
    }

    @Test func aPressOnTheTaskCardIsTheTaskMenu() {
        let onCard = Self.location(of: "Call the bank")
        #expect(onCard != NSNotFound)
        #expect(classify(at: onCard) == .taskEmbed(Self.taskID))
        #expect(classify(at: Self.location(of: "[[task:")) == .taskEmbed(Self.taskID))
    }

    @Test func proseKeepsTheTextMenu() {
        #expect(classify(at: Self.location(of: "Intro")) == .text)
        #expect(classify(at: Self.location(of: "Closing")) == .text)
    }

    @Test func tablesStillComeFirst() {
        let inTable = Self.location(of: "| 1 |")
        let anchor = Self.location(of: "| A |")
        #expect(classify(at: inTable) == .revealedTable(anchor))
        #expect(classify(at: inTable, tableCell: true) == .tableCell)
        // A rendered cell is asked before a revealed table, so it wins even where both answer.
        #expect(classify(at: inTable, tableCell: true, tableRevealed: true) == .tableCell)
    }

    /// A probe is asked only when every branch above it missed: the card's hit test does not run
    /// under a table's answer.
    @Test func aLowerProbeIsNeverAskedOnceAHigherOneAnswers() {
        var embedAsked = 0
        _ = MarkdownEditorContextMenuTarget<Int>.classify(
            tableCell: { 1 },
            revealedTableAnchor: { 0 },
            taskEmbedID: { embedAsked += 1; return Self.taskID }
        )
        #expect(embedAsked == 0)
        _ = MarkdownEditorContextMenuTarget<Int>.classify(
            tableCell: { nil },
            revealedTableAnchor: { nil },
            taskEmbedID: { embedAsked += 1; return Self.taskID }
        )
        #expect(embedAsked == 1)
    }
}

/// The two editors' menus consult the classifier and answer its embed case with a task menu.
/// Read from source: the Mac menu needs a laid-out `NSTextView` and the iOS delegate is inside
/// `#if os(iOS)`.
struct MarkdownEditorContextMenuWiringTests {
    private func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    @Test func theMacRightClickAsksTheClassifierAndBuildsTheTaskMenu() throws {
        let source = try code("Cadence/macOS/Editor/MarkdownTableInteractionSupport.swift")
        let body = try #require(CadenceSourceScan.declarationBody("override func menu(for event: NSEvent) -> NSMenu?", in: source))
        #expect(body.contains("MarkdownEditorContextMenuTarget.classify("))
        #expect(body.contains("taskEmbedID: { markdownTaskEmbedID(at: point) }"))
        #expect(body.contains("case .taskEmbed(let id):"))
        #expect(body.contains("onTaskEmbedContextMenu?(id)"))

        let handlers = try code("Cadence/macOS/Views/TaskNotesEmbedHandlers.swift")
        let menu = try #require(CadenceSourceScan.declarationBody("func taskEmbedContextMenu(", in: handlers))
        #expect(menu.contains("MacTaskRowContextMenu("), "the card menu must be the row's menu, not a copy")
        #expect(menu.contains("NSHostingMenu(rootView:"))
        #expect(menu.contains("deleteConfirmationManager.presentTaskDelete("), "Delete Task keeps the refusable overlay")
        #expect(menu.contains("openEmbeddedTask(id: id, in: scope)"), "Edit is the card's own open path")
        #expect(handlers.contains("onTaskEmbedContextMenu = {"))
        #expect(handlers.contains("MacTaskRowMenuOutcomeModifier("))
    }

    @Test func theIOSLongPressAsksTheClassifierAndBuildsTheTaskMenu() throws {
        let source = try code("Cadence/iOS/iOSMarkdownTableEditing.swift")
        let body = try #require(CadenceSourceScan.declarationBody("func contextMenuInteraction(", in: source))
        #expect(body.contains("MarkdownEditorContextMenuTarget.classify("))
        #expect(body.contains("taskEmbedID: { taskEmbedMenuID(at: location, in: textView) }"))
        #expect(body.contains("case .taskEmbed(let id):"))
        #expect(body.contains("parent.onTaskEmbedMenu?(id, edit)"))
        #expect(body.contains("openTaskEmbedCard(id: id, in: textView)"), "Edit is the card's own tap path")

        let surface = try code("Cadence/iOS/iOSMarkdownEditingSurface.swift")
        #expect(surface.contains("iOSTaskEmbedContextMenu.menu("))
        #expect(surface.contains("iOSTaskEmbedMenuOutcomeModifier(outcome: embedMenuOutcome)"))

        let outcome = try code("Cadence/iOS/iOSTaskEmbedContextMenu.swift")
        #expect(outcome.contains(".iOSTaskDeleteConfirmation(task: task"), "Delete Task keeps the row's confirmation")
    }
}

/// **The iOS card menu says exactly what the iOS row menu says.** `iOSTaskEmbedContextMenu` is the
/// row's menu spelled in UIKit, because a `UITextView`-drawn card cannot carry a SwiftUI
/// `.contextMenu`; this holds the two literal sets equal (titles and SF Symbols alike) and the
/// shared writers equal, as `MacTaskRowContextMenuParityTests` does for the Mac.
struct iOSTaskEmbedContextMenuParityTests {
    private static let rowPath = "Cadence/iOS/iOSTaskRowActionViews.swift"
    private static let cardPath = "Cadence/iOS/iOSTaskEmbedContextMenu.swift"

    private func body(_ declaration: String, in path: String) throws -> String {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: code), "\(declaration) not found in \(path)")
    }

    private func literals(in body: String) -> Set<String> {
        Set(CadenceSourceScan.captures(#""((?:[^"\\]|\\.)*)""#, in: body).map(\.text))
    }

    private func sharedCalls(in body: String) -> Set<String> {
        Set(CadenceSourceScan.captures(
            #"\b((?:CadenceTaskMutationSupport|CadenceTaskDateEditing|CadenceTaskComposerSupport|CadenceFocusSupport|CadenceFocusHandoffCenter|iOSTaskRowContextMenu)\.\w+)\b"#,
            in: body
        ).map(\.text))
    }

    @Test func theCardMenuSaysExactlyWhatTheRowMenuSays() throws {
        let row = literals(in: try body("struct iOSTaskRowContextMenu: View", in: Self.rowPath))
        let card = literals(in: try body("enum iOSTaskEmbedContextMenu", in: Self.cardPath))
        for title in ["Edit", "Focus", "Duplicate", "Delete Task", "Do Date", "Due Date", "Move Section", "Move to List", "Clear Do Date", "Clear Due Date", "Inbox"] {
            #expect(card.contains(title), "the card menu no longer says \(title)")
        }
        #expect(row.count >= 25, "read \(row.count) literals from the row menu")
        #expect(row.subtracting(card).isEmpty, "the card menu is missing \(row.subtracting(card).sorted())")
        #expect(card.subtracting(row).isEmpty, "the card menu says \(card.subtracting(row).sorted()), which the row does not")
    }

    @Test func theCardMenuWritesThroughTheRowsWriters() throws {
        let card = sharedCalls(in: try body("enum iOSTaskEmbedContextMenu", in: Self.cardPath))
        let row = sharedCalls(in: try body("struct iOSTaskRowContextMenu: View", in: Self.rowPath))
        // The row calls its own statics as `Self.`; the card names the type.
        let rowShared = row.filter { !$0.hasPrefix("iOSTaskRowContextMenu.") }
        #expect(rowShared.count >= 12, "read \(rowShared.count) shared calls from the row menu: \(rowShared.sorted())")
        // The three the row reaches inside its own statics, which the card calls (below).
        #expect(
            rowShared.subtracting(card) == [
                "CadenceTaskMutationSupport.duplicate",
                "CadenceTaskMutationSupport.moveToContainer",
                "CadenceTaskMutationSupport.moveToSection",
            ],
            "the card menu does not call \(rowShared.subtracting(card).sorted())"
        )
        for writer in ["duplicate", "moveSection", "moveToList", "selectRecurrenceRule"] {
            #expect(card.contains("iOSTaskRowContextMenu.\(writer)"), "the card menu does not write through the row's \(writer)")
        }
    }
}
