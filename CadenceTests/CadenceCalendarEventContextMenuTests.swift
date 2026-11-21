#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-18883]]: on Mac a right-click on a Calendar EVENT did nothing -- Month chip, Week/Day all-day
/// chip, timeline block, Calendar Board card -- while the task beside it opened its menu. Every
/// event surface now hosts `MacEventContextMenu`: the click's own Edit, and the surface's existing
/// delete, absent on a view-only event ([[T-18175]]).
///
/// The menu's contents are pinned as values through the same gate the popover and the hover keys
/// read; that each surface hosts it is pinned as source text, because a SwiftUI context menu cannot
/// be opened from a unit test.
@MainActor
struct CadenceCalendarEventContextMenuTests {

    // MARK: - The menu's items

    @Test func aViewOnlyEventsMenuIsEditAlone() {
        let readOnly = TimelineEventBlockEditGate.allowsDelete(isEditable: false, isCancelled: false)
        let cancelled = TimelineEventBlockEditGate.allowsDelete(isEditable: true, isCancelled: true)
        #expect(MacEventContextMenu.items(allowsDelete: readOnly) == [.edit])
        #expect(MacEventContextMenu.items(allowsDelete: cancelled) == [.edit])
    }

    @Test func aWritableEventsMenuIsEditThenDelete() {
        let writable = TimelineEventBlockEditGate.allowsDelete(isEditable: true, isCancelled: false)
        #expect(MacEventContextMenu.items(allowsDelete: writable) == [.edit, .delete])
    }

    // MARK: - Every Mac event surface hosts it

    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    /// The Month chip and the all-day chip reach the menu through `calendarEventChipEditor`, the
    /// Board card through `CalendarEventHoverKeys` directly; the modifier hosts it with the hover
    /// keys' own gate and delete, so the menu's Delete asks the scope and confirms as Cmd+Delete does.
    @Test func theChipsAndTheBoardCardHostTheMenuThroughTheHoverModifier() throws {
        let eventFile = try Self.code("Cadence/macOS/Views/CalendarEventChipPopoverSupport.swift")
        let modifier = try #require(CadenceSourceScan.declarationBody("struct CalendarEventHoverKeys: ViewModifier", in: eventFile))
        #expect(CadenceSourceScan.matchCount(
            #"\.modifier\(MacEventContextMenuHost\(\s*allowsDelete: CalendarEventHoverKeysSupport\.allowsDelete\(item\.ekEvent\),\s*onEdit: onEdit,\s*onDelete: requestDelete\s*\)\)"#,
            in: modifier
        ) == 1)
        let chipEditor = try #require(CadenceSourceScan.functionBody(named: "calendarEventChipEditor", in: eventFile))
        #expect(CadenceSourceScan.matchCount(#"\.modifier\(CalendarEventHoverKeys\("#, in: chipEditor) == 1)

        let monthFile = try Self.code("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        for chip in ["struct MonthEventChip: View", "struct AllDayEventChip: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(chip, in: monthFile), "\(chip) moved")
            #expect(body.contains(".calendarEventChipEditor(isPresented: $showEditor)"), "\(chip) no longer opens the event editor")
        }

        let boardFile = try Self.code("Cadence/macOS/Views/CalendarBoardItemSupportViews.swift")
        let board = try #require(CadenceSourceScan.declarationBody("struct CalendarBoardEventCard: View", in: boardFile))
        #expect(CadenceSourceScan.matchCount(#"\.modifier\(CalendarEventHoverKeys\("#, in: board) == 1)
    }

    /// The timeline block hosts it with its own click and its one scope-then-confirm delete path.
    @Test func theTimelineBlockHostsTheMenuWithItsOwnClickAndDelete() throws {
        let file = try Self.code("Cadence/macOS/Views/TimelineEventBlock.swift")
        let block = try #require(CadenceSourceScan.declarationBody("struct TimelineEventBlock: View", in: file))
        #expect(CadenceSourceScan.matchCount(
            #"\.modifier\(MacEventContextMenuHost\(\s*allowsDelete: TimelineEventBlockEditGate\.allowsDelete\(isEditable: isEditable, isCancelled: isCancelled\),\s*onEdit: \{\s*selectedTaskID = nil\s*selectedEventID = item\.id\s*\},\s*onDelete: \{ requestEventMutation\(\.delete\) \}\s*\)\)"#,
            in: block
        ) == 1)
    }

    /// The host is the one place the menu is attached, and the menu names the hover keys every
    /// event surface registers ([[T-18884]]), as the task menu does ([[T-16532]]).
    @Test func theHostOpensTheMenuAndTheMenuNamesTheHoverKeys() throws {
        let file = try Self.code("Cadence/macOS/Views/CalendarEventChipPopoverSupport.swift")
        let host = try #require(CadenceSourceScan.declarationBody("struct MacEventContextMenuHost: ViewModifier", in: file))
        #expect(CadenceSourceScan.matchCount(#"content\.contextMenu \{\s*MacEventContextMenu\(allowsDelete: allowsDelete, onEdit: onEdit, onDelete: onDelete\)"#, in: host) == 1)
        let menu = try #require(CadenceSourceScan.declarationBody("struct MacEventContextMenu: View", in: file))
        #expect(menu.contains(".keyboardShortcut(MacTaskRowContextMenu.hoverKey(.edit, namedHere: true))"))
        #expect(menu.contains(".keyboardShortcut(MacTaskRowContextMenu.hoverKey(.delete, namedHere: true))"))
        #expect(menu.contains("Button(role: .destructive, action: onDelete)"))
    }
}
#endif
