import Foundation
import Testing
@testable import Cadence

/// One of the three owner-decided [[T-8201]] calendar parity fixes, which landed as three
/// commits off one verified tree. They share a premise — a macOS/iOS difference with no hardware
/// or input constraint behind it is drift, and the fix is one shared owner rather than a second
/// copy nudged closer by hand — and each has its own suite so each could land on its own.
///
/// Source scans where the claim is about a SwiftUI body, values where the claim is a value. Both
/// kinds, rather than only the first: a scan that said "the view is drawn" and nothing about what
/// it says would pass over a strip that printed the wrong number.

// MARK: - [[T-8851]] the all-day draft block

/// **An all-day draft's block is drawn in the all-day strip, on both platforms.**
///
/// iOS drew it at `calendarStartHour * 60`, an hour tall, so toggling All day on a 7:30 AM draft
/// threw the block to the top of the column and off the visible pane; macOS left its ghost on the
/// pressed range, which reads as a timed block for something that is not on the clock. The owner
/// chose neither: an all-day draft goes where an all-day item lives.
@Suite("An all-day draft is drawn in the all-day strip on both platforms")
@MainActor
struct CadenceAllDayDraftPlacementTests {

    /// One draft at a time, and a column clears only the day it set — so a column leaving the
    /// window cannot take down the chip of the column that now holds the draft.
    ///
    /// **Failing-first:** making `clear(dateKey:)` unconditional fails the third expectation.
    @Test func theAllDayDraftSessionIsKeyedByDayAndClearsOnlyItsOwnDay() {
        let session = CadenceCalendarAllDayDraftSession()
        #expect(session.dateKey == nil && !session.isDrafting(on: "2026-03-04"))

        session.set(dateKey: "2026-03-04", title: "Offsite")
        #expect(session.isDrafting(on: "2026-03-04"))
        #expect(!session.isDrafting(on: "2026-03-05"), "every day's strip thinks it holds the draft")
        #expect(session.chipTitle == "Offsite")

        session.clear(dateKey: "2026-03-05")
        #expect(session.isDrafting(on: "2026-03-04"),
                "a neighbouring column's clear took down the draft it does not own")

        // Moving the draft to another day is a set, not a clear-then-set: the strip never blinks.
        session.set(dateKey: "2026-03-05", title: "Offsite")
        #expect(!session.isDrafting(on: "2026-03-04") && session.isDrafting(on: "2026-03-05"))

        session.clear(dateKey: "2026-03-05")
        #expect(session.dateKey == nil && session.chipTitle == CadenceCalendarAllDayDraftSession.blankChipTitle)
    }

    /// A draft with nothing typed into it still has to be visible, so the chip has a word of its
    /// own — and a title that is only whitespace is not a title.
    @Test func aBlankDraftsChipStillSaysWhatItIs() {
        let session = CadenceCalendarAllDayDraftSession()
        session.set(dateKey: "2026-03-04", title: "")
        #expect(session.chipTitle == "All day", "a blank draft's chip is blank")
        session.set(dateKey: "2026-03-04", title: "   ")
        #expect(session.chipTitle == "All day", "a whitespace title is drawn as a title")
        session.set(dateKey: "2026-03-04", title: "  Flight  ")
        #expect(session.chipTitle == "Flight", "the chip prints the title's surrounding whitespace")
    }

    /// iOS: the hour ladder asks the shared rule before it draws a block, and the band draws the
    /// chip ahead of the day's real items.
    ///
    /// **Failing-first:** dropping the `drawsBlockInHourLadder` guard from `draftLayer` fails the
    /// first expectation; drawing the draft chip after the events `ForEach` fails the order.
    @Test func theIOSColumnDrawsNoLadderBlockForAnAllDayDraftAndTheBandDrawsTheChip() throws {
        let path = "Cadence/iOS/iOSCalendarTimelineViews.swift"
        let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
        let layer = try #require(
            CadenceSourceScan.declarationBody("private var draftLayer: some View", in: code),
            "draftLayer was not found in \(path)"
        )
        #expect(layer.contains("iOSTimelineDraftBlock("), "non-vacuity: the body read is not the draft layer")
        let guardRange = try #require(
            layer.range(of: "if CadenceCalendarDraftPlacement.placement(isAllDay: current.isAllDay).drawsBlockInHourLadder {"),
            "the iOS ladder draws a block for an all-day draft ([[T-8851]])"
        )
        let block = try #require(layer.range(of: "iOSTimelineDraftBlock("))
        #expect(guardRange.upperBound <= block.lowerBound, "the guard is not over the drawn block")

        // The editor's anchor is NOT inside that guard: it stays on the pressed range whatever the
        // toggle says ([[T-8502]]), so the panel does not move out from under the finger.
        let anchorPopover = try #require(layer.range(of: ".popover(isPresented: $isDraftEditorPresented"))
        #expect(block.upperBound <= anchorPopover.lowerBound)
        #expect(CadenceSourceScan.matchCount(#"iOSCalendarTimelineBlockLayout\.draftEditorAnchorFrame\("#, in: layer) == 1,
                "the draft layer no longer reads the editor's anchor from the tested seam")

        let chips = try #require(
            CadenceSourceScan.declarationBody("private struct iOSCalendarAllDayBandChips: View", in: code)
        )
        #expect(chips.contains("var draftTitle: String? = nil"), "the band takes no draft")
        let draftChip = try #require(chips.range(of: "CadenceAllDayDraftChip(title: draftTitle)"),
                                     "the iOS all-day band draws no draft chip")
        let events = try #require(chips.range(of: "ForEach(allDayEvents.prefix(split.events)"))
        #expect(draftChip.upperBound <= events.lowerBound,
                "the draft is drawn after the day's real items, so it can be the row that is hidden")
    }

    /// macOS: the same rule, over the same shared enum, and the ghost leaves the ladder with it.
    ///
    /// **Failing-first:** removing the `placement.drawsBlockInHourLadder` guard from the overlay
    /// fails the first expectation; dropping `onAllDayDraftChanged` from the popover call leaves
    /// the canvas unable to learn that the toggle moved.
    @Test func theMacGhostLeavesTheLadderForAnAllDayDraftAndTheBandsDrawTheChip() throws {
        let overlayPath = "Cadence/macOS/Views/TimelineDayCanvasOverlaySupport.swift"
        let overlayCode = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(overlayPath))
        let overlay = try #require(
            CadenceSourceScan.declarationBody("struct TimelineDraftCreationOverlay: View", in: overlayCode)
        )
        #expect(overlay.contains("TimelineDraftPopoverAnchor("), "non-vacuity: the body read is not the overlay")
        let guardRange = try #require(overlay.range(of: "if placement.drawsBlockInHourLadder {"),
                                      "the Mac ghost is still drawn for an all-day draft ([[T-8851]])")
        let ghost = try #require(overlay.range(of: "TimelineDraftGhostLayer("))
        let anchor = try #require(overlay.range(of: "TimelineDraftPopoverAnchor("))
        #expect(guardRange.upperBound <= ghost.lowerBound, "the guard is not over the ghost")
        #expect(ghost.upperBound <= anchor.lowerBound,
                "the popover's anchor fell inside the guard, so an all-day draft has no editor")

        let canvasPath = "Cadence/macOS/Views/TimelineDayCanvas.swift"
        let canvasCode = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(canvasPath))
        let canvas = try #require(
            CadenceSourceScan.declarationBody("struct TimelineDayCanvas: View", in: canvasCode)
        )
        #expect(canvas.contains("TimelineDraftCreationOverlay("), "non-vacuity: the body read is not the canvas")
        #expect(canvas.contains("onAllDayDraftChanged: adoptAllDayDraft"),
                "the canvas is never told the popover's All day toggle moved")
        #expect(canvas.contains("@Environment(\\.calendarAllDayDraft) private var allDayDraft"),
                "the canvas cannot reach the strip that now draws its all-day draft")
        #expect(canvas.contains("CadenceCalendarDraftPlacement.placement(isAllDay: allDayDraftTitle != nil)"),
                "the Mac canvas decides where the ghost goes without the shared rule")
        // Every path that takes the draft down takes the chip with it: the published value reads
        // the selection, not the toggle alone. Only one of the four teardown paths runs
        // `finishDraftCreation`, so a toggle-only reading strands a chip in the band.
        let published = try #require(
            CadenceSourceScan.declarationBody("private var publishedAllDayDraft: String?", in: canvas),
            "the Mac canvas publishes its draft without a single reading"
        )
        #expect(published.contains("guard draftSelection != nil else { return nil }"),
                "a dismissed draft leaves its chip in the all-day band")

        // Both macOS strips draw it: the Calendar page's pinned band and Today's pinned band.
        let pageCode = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift")
        )
        let header = try #require(
            CadenceSourceScan.declarationBody("struct CalDayHeaderView: View", in: pageCode)
        )
        #expect(header.contains("CadenceAllDayDraftChip(title: draftTitle)"),
                "the Calendar page's all-day band draws no draft chip")
        #expect(header.contains("@Environment(\\.calendarAllDayDraft) private var allDayDraft"))

        let todayCode = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanelShellViews.swift")
        )
        let band = try #require(
            CadenceSourceScan.declarationBody("struct SchedulePanelAllDayBand: View", in: todayCode)
        )
        #expect(band.contains("CadenceAllDayDraftChip(title: draftTitle)"),
                "Today's all-day band draws no draft chip")
        let panelCode = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SchedulePanel.swift")
        )
        #expect(panelCode.contains("if !allDayEvents.isEmpty || allDayDraftTitle != nil {"),
                "Today's band still appears only on a day that already has an all-day event, so a draft has nowhere to go")
    }

    /// Today's band pays for the draft's row and still costs nothing on an ordinary day, and the
    /// three-chip cap still protects the hour ladder on a short pane.
    ///
    /// **Failing-first:** adding `draftCount` after the `min` instead of before it lets four rows
    /// through.
    ///
    /// macOS-only: `SchedulePanelAllDayBandLayout` is a macOS type, and `CadenceTests` compiles
    /// for an iOS destination too ([[T-3244]]).
    #if os(macOS)
    @Test func todaysAllDayBandCountsTheDraftAsOneOfItsThreeRows() {
        #expect(SchedulePanelAllDayBandLayout.height(eventCount: 0) == 0,
                "an ordinary day's band no longer costs zero")
        #expect(SchedulePanelAllDayBandLayout.height(eventCount: 0, draftCount: 1) > 0,
                "a day whose only all-day item is a draft draws no band")
        #expect(SchedulePanelAllDayBandLayout.height(eventCount: 0, draftCount: 1)
                    == SchedulePanelAllDayBandLayout.height(eventCount: 1),
                "a draft row and an event row are not the same row")
        #expect(SchedulePanelAllDayBandLayout.height(eventCount: 3, draftCount: 1)
                    == SchedulePanelAllDayBandLayout.height(eventCount: 3),
                "a draft on a conference day grows the band past its own cap")
    }
    #endif
}
