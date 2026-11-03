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

    /// **[[T-10205]] — the calendar's task surfaces are tasks too.** The Month and all-day task
    /// chips and the timeline's task block answered a right-click with a `RightClickActionTrigger`
    /// overlay that ran the click's own path, after [[T-1479]] had ruled right-click a menu and
    /// [[T-8062]] had carried that to the board card. Each now wears `MacTaskContextMenuHost`, which
    /// presents the row's menu with the row's outcome handling.
    @Test func theCalendarTaskChipsAndTimelineBlockRightClickPresentTheSameMenu() throws {
        // The host: the row's menu, the row's outcome modifier, and the row's Focus and Delete.
        let menuFile = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macMenuPath))
        let host = try #require(
            CadenceSourceScan.declarationBody("struct MacTaskContextMenuHost: ViewModifier", in: menuFile),
            "MacTaskContextMenuHost not found"
        )
        #expect(CadenceSourceScan.matchCount(#"\.contextMenu \{\s*MacTaskRowContextMenu\("#, in: host) == 1)
        #expect(CadenceSourceScan.matchCount(#"openDetail: openDetail"#, in: host) == 1)
        #expect(CadenceSourceScan.matchCount(#"startFocus: startFocus"#, in: host) == 1)
        #expect(CadenceSourceScan.matchCount(#"requestDelete: presentDelete"#, in: host) == 1)
        #expect(CadenceSourceScan.matchCount(#"MacTaskRowMenuOutcomeModifier\("#, in: host) == 1)
        #expect(CadenceSourceScan.matchCount(#"focusManager\.startFocus\(task: task"#, in: host) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"deleteConfirmationManager\.presentTaskDelete\(task, in: modelContext, willDelete: willDelete\)"#,
            in: host
        ) == 1)

        // The chips: both draw the one shared interaction, which carries the host and no overlay.
        let chipFile = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        )
        let chips = try #require(CadenceSourceScan.functionBody(named: "calendarTaskChipInteractions", in: chipFile))
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture \{ showInspector\.wrappedValue = true \}"#, in: chips) == 1,
                "the chip's click no longer opens the inspector")
        #expect(CadenceSourceScan.matchCount(
            #"\.modifier\(MacTaskContextMenuHost\(task: task, openDetail: \{ showInspector\.wrappedValue = true \}\)\)"#,
            in: chips
        ) == 1)
        #expect(CadenceSourceScan.matchCount("RightClickActionTrigger", in: chipFile) == 0,
                "an AppKit right-click overlay on a chip would take the click before the menu sees it")
        for chip in ["struct MonthTaskChip: View", "struct AllDayTaskChip: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(chip, in: chipFile), "\(chip) not found")
            #expect(body.contains(".calendarTaskChipInteractions(task: task, showInspector: $showInspector)"))
        }

        // The timeline block: the menu's Edit is the click's own `handleBlockTap`.
        let blockPath = "Cadence/macOS/Views/TimelineTaskBlock.swift"
        let blockFile = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(blockPath))
        let block = try body("var body: some View", in: blockPath)
        #expect(blockFile.contains("struct TimelineTaskBlock: View"), "non-vacuity: wrong file read")
        #expect(CadenceSourceScan.matchCount(#"\.onTapGesture \{\s*handleBlockTap\(\)\s*\}"#, in: block) == 1)
        #expect(CadenceSourceScan.matchCount(
            #"\.modifier\(MacTaskContextMenuHost\(task: task, openDetail: handleBlockTap, willDelete: clearAfterDelete\)\)"#,
            in: block
        ) == 1)
        #expect(CadenceSourceScan.matchCount("RightClickActionTrigger", in: blockFile) == 0,
                "an AppKit right-click overlay on the block would take the click before the menu sees it")
        // The delete teardown clears what the hover's Cmd+Delete clears, so no state names a gone task.
        let teardown = try #require(CadenceSourceScan.functionBody(named: "clearAfterDelete", in: blockFile))
        for cleared in ["hoveredTaskManager.hoveredTask = nil", "selectedTaskID = nil", "activeDragTaskID = nil", "hoveredEditableManager.endHovering("] {
            #expect(teardown.contains(cleared), "the block's delete teardown no longer runs \(cleared)")
        }
    }

    @Test func aRefusedMenuWriteIsTitledLikeIOSTitlesIt() {
        #expect(MacTaskRowMenuFailure.move.title == CadenceTaskMutationSupport.moveFailureAlertTitle)
        #expect(MacTaskRowMenuFailure.recurrence("x").title == CadenceTaskMutationSupport.recurrenceFailureAlertTitle)
        #expect(MacTaskRowMenuFailure.recurrence("x").message == "x")
        #expect(MacTaskRowMenuFailure.move.message == CadenceTaskFieldEditCommit.saveFailureNotice)
        #expect(MacTaskRowMenuFailure.duplicate.message == CadenceTaskFieldEditCommit.saveFailureNotice)
    }

    // MARK: - [[T-8107]] The date submenus say the date

    /// The submenu label carries the set date the way "Priority: High" carries the level, and is
    /// the bare title when nothing (or no parseable date) is set.
    @Test func theDateSubmenuTitleCarriesTheSetDate() {
        #expect(CadenceTaskDateMenuLabel.title("Due Date", dateKey: "2025-10-31") == "Due Date: Fri, Oct 31")
        #expect(CadenceTaskDateMenuLabel.title("Do Date", dateKey: "2026-11-02") == "Do Date: Mon, Nov 2")
        #expect(CadenceTaskDateMenuLabel.title("Due Date", dateKey: "") == "Due Date")
        #expect(CadenceTaskDateMenuLabel.title("Do Date", dateKey: "not a date") == "Do Date")
    }

    /// The quick row that would write the set date is the checked one; an arbitrary date checks
    /// none, which is why the label has to carry the date ([[T-8107]]'s decision).
    @Test func theQuickRowThatWouldWriteTheSetDateIsChecked() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10)))
        func key(_ offset: Int) throws -> String {
            DateFormatters.dateKey(from: try #require(calendar.date(byAdding: .day, value: offset, to: now)))
        }

        #expect(CadenceTaskDateMenuLabel.checkedPick(for: try key(0), now: now, calendar: calendar) == .today)
        #expect(CadenceTaskDateMenuLabel.checkedPick(for: try key(1), now: now, calendar: calendar) == .tomorrow)
        #expect(CadenceTaskDateMenuLabel.checkedPick(for: try key(7), now: now, calendar: calendar) == .nextWeek)
        #expect(CadenceTaskDateMenuLabel.checkedPick(for: try key(3), now: now, calendar: calendar) == nil)
        #expect(CadenceTaskDateMenuLabel.checkedPick(for: "", now: now, calendar: calendar) == nil)

        let today = DateFormatters.todayKey()
        #expect(CadenceTaskDateMenuLabel.glyph(.today, dateKey: today, otherwise: "flag.fill") == "checkmark.circle.fill")
        #expect(CadenceTaskDateMenuLabel.glyph(.tomorrow, dateKey: today, otherwise: "calendar") == "calendar")
    }

    /// Both menus read that one helper for both submenus: a title per submenu and a glyph per quick
    /// row, each over the field its submenu edits. Counted per menu, so either platform dropping it
    /// goes red.
    @Test func bothMenusTitleAndCheckTheirDateSubmenusThroughTheSharedHelper() throws {
        for (declaration, path) in [
            ("struct iOSTaskRowContextMenu: View", Self.iOSPath),
            ("struct MacTaskRowContextMenu: View", Self.macMenuPath),
        ] {
            let menu = try body(declaration, in: path)
            #expect(CadenceSourceScan.matchCount(#"CadenceTaskDateMenuLabel\.title\("Do Date", dateKey: task\.scheduledDate\)"#, in: menu) == 1, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"CadenceTaskDateMenuLabel\.title\("Due Date", dateKey: task\.dueDate\)"#, in: menu) == 1, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"CadenceTaskDateMenuLabel\.glyph\(\.\w+, dateKey: task\.scheduledDate,"#, in: menu) == 3, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"CadenceTaskDateMenuLabel\.glyph\(\.\w+, dateKey: task\.dueDate,"#, in: menu) == 3, "\(path)")
            #expect(CadenceSourceScan.matchCount(#"Label\("(?:Do|Due) Date", systemImage"#, in: menu) == 0, "\(path) still has a bare date submenu title")
        }
    }
}
#endif
