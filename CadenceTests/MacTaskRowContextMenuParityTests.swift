#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-1479]] — the Mac task row's right-click is a menu, and it is iOS's menu.**
///
/// Two claims, both read from source because `iOSTaskRowContextMenu` is inside `#if os(iOS)` and this
/// target builds for macOS:
///
/// 1. `MacTaskRow` presents `MacTaskRowContextMenu` on right-click, and its tap still opens the
///    inspector — the owner's decision was that right-click gains a menu and takes nothing away.
/// 2. The Mac menu's words and its shared mutation calls are the iOS menu's, exactly. A second
///    vocabulary would be a new parity finding in the place PA-05 closed; the comparison is a set
///    equality, so an action added to one menu and not the other goes red from either side.
@MainActor
struct MacTaskRowContextMenuParityTests {
    private static let iOSPath = "Cadence/iOS/iOSTaskRowActionViews.swift"
    private static let macMenuPath = "Cadence/macOS/Views/MacTaskRowContextMenu.swift"
    private static let macRowPath = "Cadence/macOS/Views/TasksPanelComponents.swift"

    private func body(_ declaration: String, in path: String) throws -> String {
        let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(CadenceSourceScan.declarationBody(declaration, in: code), "\(declaration) not found in \(path)")
    }

    /// Every string literal in a body — item titles, submenu titles and SF Symbol names alike,
    /// because the symbol is part of what the menu says.
    private func literals(in body: String) -> Set<String> {
        Set(CadenceSourceScan.captures(#""((?:[^"\\]|\\.)*)""#, in: body).map(\.text))
    }

    private func sharedCalls(in body: String) -> Set<String> {
        Set(CadenceSourceScan.captures(
            #"\b((?:CadenceTaskMutationSupport|CadenceTaskDateEditing|CadenceTaskComposerSupport|CadenceFocusSupport|CadenceTaskRecurrenceWorkflowSupport)\.\w+)\("#,
            in: body
        ).map(\.text))
    }

    @Test func theMacMenuSaysExactlyWhatTheIOSMenuSays() throws {
        let iOS = literals(in: try body("struct iOSTaskRowContextMenu: View", in: Self.iOSPath))
        let mac = literals(in: try body("struct MacTaskRowContextMenu: View", in: Self.macMenuPath))

        // Non-vacuity: the reader reached both menus and both still carry the full action list.
        for title in ["Edit", "Focus", "Duplicate", "Delete Task", "Do Date", "Due Date", "Move Section", "Move to List", "Repeat", "Clear Do Date", "Clear Due Date", "Inbox"] {
            #expect(iOS.contains(title), "iOS menu no longer says \(title); this comparison proves nothing")
        }
        #expect(iOS.count >= 25, "read \(iOS.count) literals from the iOS menu")

        #expect(iOS.subtracting(mac).isEmpty, "the Mac menu is missing \(iOS.subtracting(mac).sorted())")
        #expect(mac.subtracting(iOS).isEmpty, "the Mac menu says \(mac.subtracting(iOS).sorted()), which iOS does not")
    }

    @Test func theMacMenuWritesThroughTheSameSharedHelpers() throws {
        let iOS = sharedCalls(in: try body("struct iOSTaskRowContextMenu: View", in: Self.iOSPath))
        let mac = sharedCalls(in: try body("struct MacTaskRowContextMenu: View", in: Self.macMenuPath))

        // Fifteen: four mutation calls, eight date edits, two pickable lists, one focus gate.
        // Counted rather than "non-empty" so a reader that stopped matching cannot pass as
        // agreement.
        #expect(iOS.count == 15, "read \(iOS.count) shared calls from the iOS menu: \(iOS.sorted())")
        // iOS reaches the recurrence apply through `iOSTaskRecurrenceSelection`, outside its menu
        // struct; the Mac menu calls it inline. [[T-9122]] adds the scope-answer half beside it
        // (`applyRecurrenceRule(_:scope:for:modelContext:)`, and the `recurrenceTargets` it hands
        // the commit), which iOS keeps in its scope dialog modifier: on the Mac it is a static on
        // the menu because the row's dialog and the note embed card's dialog share it. Those two
        // calls are the only allowed difference.
        #expect(iOS.subtracting(mac).isEmpty, "the Mac menu does not call \(iOS.subtracting(mac).sorted())")
        #expect(
            mac.subtracting(iOS) == [
                "CadenceTaskRecurrenceWorkflowSupport.applyRecurrenceRule",
                "CadenceTaskRecurrenceWorkflowSupport.recurrenceTargets",
            ],
            "the Mac menu calls \(mac.subtracting(iOS).sorted()), which iOS's menu does not"
        )
    }

    @Test func rightClickPresentsTheMenuAndTapStillOpensTheInspector() throws {
        let row = try body("var body: some View", in: Self.macRowPath)
        let rowFile = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macRowPath))
        #expect(rowFile.contains("struct MacTaskRow: View"), "non-vacuity: wrong file read")

        // Tap is untouched. Since [[T-7092]] it opens the inspector through `openDetail`, the one
        // function the tap, the menu's Edit and the "Open task" accessibility action share.
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture\(perform: openDetail\)"#, in: row) == 1)
        #expect(CadenceSourceScan.matchCount(#"func openDetail\(\) \{\s*showTaskInspector = true\s*\}"#, in: rowFile) == 1)

        // Right-click is the menu, and nothing else claims the gesture first.
        #expect(CadenceSourceScan.matchCount(#"\.contextMenu \{"#, in: row) == 1)
        #expect(CadenceSourceScan.matchCount(#"MacTaskRowContextMenu\("#, in: row) == 1)
        #expect(CadenceSourceScan.matchCount("RightClickActionTrigger", in: rowFile) == 0,
                "an AppKit right-click overlay on the row would take the click before the menu sees it")
        #expect(CadenceSourceScan.matchCount(#"MacTaskRowMenuOutcomeModifier\("#, in: row) == 1)

        // The menu's Edit is the inspector: the body hands the menu `openDetail` and sets the flag
        // nowhere itself, so every path from the row body goes through that one function ([[T-7164]]).
        #expect(CadenceSourceScan.matchCount(#"openDetail: openDetail"#, in: row) == 1)
        #expect(CadenceSourceScan.matchCount(#"showTaskInspector = true"#, in: row) == 0)
    }

    /// **[[T-8062]] — the board card is a task too.** `KanbanCard` is the card of a list's Kanban
    /// tab, the Tasks page's Kanban mode and the Calendar Board's day columns and rails; its
    /// right-click opened the inspector after T-1479 had ruled it a menu on the row.
    @Test func theBoardCardRightClickPresentsTheSameMenuAndClickStillOpensTheInspector() throws {
        let cardPath = "Cadence/macOS/Views/KanbanCardView.swift"
        let card = try body("var body: some View", in: cardPath)
        let cardFile = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(cardPath))
        #expect(cardFile.contains("struct KanbanCard: View"), "non-vacuity: wrong file read")

        // Click is unchanged: the tap goes through its chip guard to the one inspector function.
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture \{\s*openTaskInspectorFromCardTap\(\)\s*\}"#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount(#"func openTaskInspector\(\) \{\s*showTaskInspector = true\s*\}"#, in: cardFile) == 1)

        // Right-click is the row's menu with the row's outcome handling, and no AppKit overlay
        // claims the gesture before the menu sees it.
        #expect(CadenceSourceScan.matchCount(#"\.contextMenu \{"#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount(#"MacTaskRowContextMenu\("#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount(#"MacTaskRowMenuOutcomeModifier\("#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount("RightClickActionTrigger", in: cardFile) == 0,
                "an AppKit right-click overlay on the card would take the click before the menu sees it")
        #expect(CadenceSourceScan.matchCount(#"openDetail: openTaskInspector"#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount(#"startFocus: startFocus"#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount(#"requestDelete: presentDelete"#, in: card) == 1)
        #expect(CadenceSourceScan.matchCount(#"focusManager\.startFocus\(task: task"#, in: cardFile) == 1)
        #expect(CadenceSourceScan.matchCount(#"deleteConfirmationManager\.presentTaskDelete\(task"#, in: cardFile) == 1)

        // All three boards still draw this one card, so each gains the menu with it.
        for host in ["KanbanColumnSupportViews.swift", "CalendarBoardDayColumnSupportViews.swift", "CalendarBoardRailSupportViews.swift"] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/\(host)"))
            #expect(CadenceSourceScan.matchCount(#"\bKanbanCard\("#, in: code) >= 1, "\(host) no longer draws KanbanCard")
        }
    }

    @Test func aRefusedMenuWriteIsTitledLikeIOSTitlesIt() {
        #expect(MacTaskRowMenuFailure.move.title == CadenceTaskMutationSupport.moveFailureAlertTitle)
        #expect(MacTaskRowMenuFailure.recurrence("x").title == CadenceTaskMutationSupport.recurrenceFailureAlertTitle)
        #expect(MacTaskRowMenuFailure.recurrence("x").message == "x")
        #expect(MacTaskRowMenuFailure.move.message == CadenceTaskFieldEditCommit.saveFailureNotice)
        #expect(MacTaskRowMenuFailure.duplicate.message == CadenceTaskFieldEditCommit.saveFailureNotice)
    }
}
#endif
