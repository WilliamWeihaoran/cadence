//
//  CadenceTests.swift
//  CadenceTests
//
//  Created by William Wei on 3/26/26.
//

import Testing
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
import EventKit
#endif
@testable import Cadence

struct CadenceTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

#if os(macOS)
    @Test func appleAccountDefaultsStorageRoundTripsProfile() throws {
        let suiteName = "CadenceTests.appleAccount.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let storage = AppleAccountDefaultsStorage(defaults: defaults)
        let signedInAt = Date(timeIntervalSince1970: 1_777_777)
        let profile = AppleAccountProfile(
            userIdentifier: "apple-user-1",
            email: "person@example.com",
            givenName: "Ada",
            familyName: "Lovelace",
            signedInAt: signedInAt
        )

        storage.saveProfile(profile)

        #expect(storage.loadProfile() == profile)

        storage.clearProfile()

        #expect(storage.loadProfile() == nil)
    }

    @Test func appleAccountProfileMergePreservesFirstGrantFields() {
        let existing = AppleAccountProfile(
            userIdentifier: "apple-user-1",
            email: "person@example.com",
            givenName: "Ada",
            familyName: "Lovelace",
            signedInAt: Date(timeIntervalSince1970: 100)
        )
        let refreshedAt = Date(timeIntervalSince1970: 200)

        let merged = AppleAccountProfileMerge.merged(
            existing: existing,
            userIdentifier: "apple-user-1",
            email: nil,
            givenName: "",
            familyName: nil,
            signedInAt: refreshedAt
        )

        #expect(merged.email == "person@example.com")
        #expect(merged.givenName == "Ada")
        #expect(merged.familyName == "Lovelace")
        #expect(merged.signedInAt == refreshedAt)
    }

    @Test func appleSignInEntitlementParsingRecognizesDefaultValue() {
        let configured = AppleSignInEntitlementStatus.parsed(from: ["Default"])
        let missing = AppleSignInEntitlementStatus.parsed(from: nil)

        #expect(configured.isConfigured)
        #expect(configured.title == "Available")
        #expect(missing.isConfigured == false)
        #expect(missing.title == "Missing")
    }
#endif

    @Test func automaticBackupRetentionThinsStartupAndPreRestoreSnapshots() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))

        func date(daysAgo: Int, hour: Int, minute: Int = 0) throws -> Date {
            let day = try #require(calendar.date(byAdding: .day, value: -daysAgo, to: now))
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            return try #require(calendar.date(from: DateComponents(
                timeZone: calendar.timeZone,
                year: components.year,
                month: components.month,
                day: components.day,
                hour: hour,
                minute: minute
            )))
        }

        func snapshot(_ id: String, reason: StoreBackupReason, createdAt: Date) -> StoreBackupSnapshot {
            StoreBackupSnapshot(
                id: id,
                url: URL(fileURLWithPath: "/tmp/\(id)", isDirectory: true),
                createdAt: createdAt,
                reason: reason.displayName,
                sizeBytes: 1
            )
        }

        var snapshots: [StoreBackupSnapshot] = []
        for index in 0..<14 {
            snapshots.append(snapshot("startup-today-\(index)", reason: .startup, createdAt: try date(daysAgo: 0, hour: 12, minute: 59 - index)))
        }
        snapshots.append(snapshot("startup-day1-new", reason: .startup, createdAt: try date(daysAgo: 1, hour: 12)))
        snapshots.append(snapshot("startup-day1-old", reason: .startup, createdAt: try date(daysAgo: 1, hour: 9)))
        snapshots.append(snapshot("startup-day2-new", reason: .startup, createdAt: try date(daysAgo: 2, hour: 12)))
        snapshots.append(snapshot("startup-day2-old", reason: .startup, createdAt: try date(daysAgo: 2, hour: 9)))
        snapshots.append(snapshot("startup-old", reason: .startup, createdAt: try date(daysAgo: 40, hour: 12)))
        for index in 0..<7 {
            snapshots.append(snapshot("pre-restore-\(index)", reason: .preRestore, createdAt: try date(daysAgo: index, hour: 8)))
        }
        snapshots.append(snapshot("manual-old", reason: .manual, createdAt: try date(daysAgo: 90, hour: 12)))

        let removableIDs = Set(StoreBackupManager
            .automaticBackupSnapshotsToRemove(snapshots, now: now, calendar: calendar)
            .map(\.id))

        #expect(removableIDs.isSuperset(of: [
            "startup-today-5",
            "startup-today-6",
            "startup-today-7",
            "startup-today-8",
            "startup-today-9",
            "startup-today-10",
            "startup-today-11",
            "startup-today-12",
            "startup-today-13"
        ]))
        #expect(removableIDs.contains("startup-day1-new") == false)
        #expect(removableIDs.contains("startup-day1-old"))
        #expect(removableIDs.contains("startup-day2-new") == false)
        #expect(removableIDs.contains("startup-day2-old"))
        #expect(removableIDs.contains("startup-old"))
        #expect(removableIDs.contains("pre-restore-4") == false)
        #expect(removableIDs.contains("pre-restore-5"))
        #expect(removableIDs.contains("pre-restore-6"))
        #expect(removableIDs.contains("manual-old") == false)
    }

    @Test func deleteAllBackupsRemovesBackupRootForAccountDeletion() throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CadenceTests.store.\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: storeDirectory)
        }

        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: storeDirectory.appendingPathComponent("default.store"))

        let backupURL = try #require(try StoreBackupManager.createBackupIfStoreExists(
            reason: .manual,
            storeDirectoryURL: storeDirectory
        ))
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        let removedCount = try StoreBackupManager.deleteAllBackups(storeDirectoryURL: storeDirectory)

        #expect(removedCount == 1)
        #expect(StoreBackupManager.listBackups(storeDirectoryURL: storeDirectory).isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: storeDirectory.appendingPathComponent("Cadence Store Backups", isDirectory: true).path
        ))
    }

#if os(macOS)
    @Test func calendarHeaderVisibleRangeClampsOverscroll() {
        let range = calendarTimelineHeaderVisibleRange(
            headerOffset: -3_700,
            colWidth: 1,
            viewportWidth: 2,
            renderDays: 3_650
        )

        #expect(range.lowerBound <= range.upperBound)
        #expect(range.lowerBound >= 0)
        #expect(range.upperBound <= 3_650)
        #expect(range.contains(3_649))
    }

    @Test func calendarTimelineVisibleDayUsesLeadingEdge() {
        #expect(CalendarTimelineScrollSupport.clampedDayIndex(offsetX: -40, colWidth: 100) == 0)
        #expect(CalendarTimelineScrollSupport.clampedDayIndex(offsetX: 99, colWidth: 100) == 0)
        #expect(CalendarTimelineScrollSupport.clampedDayIndex(offsetX: 100, colWidth: 100) == 1)
        #expect(CalendarTimelineScrollSupport.clampedDayIndex(offsetX: CGFloat(calRenderDays + 4) * 100, colWidth: 100) == calRenderDays - 1)
    }

    @Test func todayTimelineJumpTargetUsesConcreteDateAndPreviousHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 15, minute: 30)))
        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let target = CalendarPageInteractionSupport.todayTimelineJumpTarget(
            now: now,
            calendar: calendar,
            bufferStart: bufferStart,
            todayDayIdx: 999
        )

        #expect(target == CalendarTimelineJumpTarget(dateKey: "2026-06-03", dayIndex: 2, hour: 14))
    }

    @Test func todayTimelineJumpTargetClampsDayAndHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 3, hour: 0, minute: 15)))
        let futureBufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)))

        let target = CalendarPageInteractionSupport.todayTimelineJumpTarget(
            now: now,
            calendar: calendar,
            bufferStart: futureBufferStart,
            todayDayIdx: 42
        )

        #expect(target == CalendarTimelineJumpTarget(dateKey: "2026-06-03", dayIndex: 0, hour: calStartHour))
    }

    @Test func monthIndexForOffsetHandlesSparseOrEmptyOffsets() {
        #expect(monthIndexForOffset(y: 120, offsets: [], totalMonths: 120) == 0)
        #expect(monthIndexForOffset(y: 99, offsets: [0, 100, 250], totalMonths: 120) == 0)
        #expect(monthIndexForOffset(y: 100, offsets: [0, 100, 250], totalMonths: 120) == 1)
        #expect(monthIndexForOffset(y: 500, offsets: [0, 100, 250], totalMonths: 120) == 2)
    }

    @Test func rememberedTimelineDayIndexSurvivesDSTBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let day = CalendarPageStateSupport.rememberedTimelineDayIndex(
            rememberedDateKey: "2026-03-09",
            bufferStart: bufferStart,
            todayDayIdx: 0,
            calendar: calendar
        )

        #expect(day == 2)
    }

    /// Leaving the month grid returns to the day the *block* on screen was showing.
    ///
    /// `visibleMonthIdx` indexes the grid's rendered blocks, and a block opens on its month's
    /// first Sunday rather than on the 1st. Today here is Fri May 1 2026, which the grid draws as
    /// trailing fill on April's block (index 59) — so block 59 is the page holding today and
    /// returns today, while block 60 opens on Sun May 3 and returns that.
    @Test func monthToTimelineReturnUsesTheDayTheVisibleBlockWasShowing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let mayBlockDay = CalendarPageStateSupport.timelineDayIndexForMonthViewReturn(
            visibleMonthIdx: 60,
            bufferStart: bufferStart,
            todayDayIdx: 120,
            calendar: calendar,
            today: today
        )
        let blockHoldingTodayDay = CalendarPageStateSupport.timelineDayIndexForMonthViewReturn(
            visibleMonthIdx: 59,
            bufferStart: bufferStart,
            todayDayIdx: 120,
            calendar: calendar,
            today: today
        )

        // Jan 1 + 122 days = May 3, May's first Sunday and the first cell of its block.
        #expect(mayBlockDay == 122)
        // Jan 1 + 120 days = May 1, i.e. today, because today is drawn on block 59.
        #expect(blockHoldingTodayDay == 120)
    }

    @Test func calendarTitleUsesVisibleTimelineMonthAcrossBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let label = CalendarPageLifecycleSupport.calendarTitleLabel(
            viewMode: .week,
            visibleMonthIdx: 60,
            visibleTimelineDayIndex: 12,
            anchorDateKey: "2026-04-20",
            bufferStart: bufferStart,
            todayDayIdx: 0,
            calendar: calendar
        )

        #expect(label == "May 2026")
    }

    @Test func calendarMonthModeOpensMonthContainingTimelineAnchor() throws {
        let calendar = Calendar.current

        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 12)))
        let currentMonthStart = monthStart(for: today, calendar: calendar)

        let juneIndex = CalendarPageStateSupport.monthIndexForTimelineAnchor(
            anchorDateKey: "2026-06-18",
            currentMonthStart: currentMonthStart,
            calendar: calendar
        )

        #expect(juneIndex == 61)
    }

    @Test func calendarMonthReturnAnchorsVisibleMonth() throws {
        let calendar = Calendar.current

        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 12)))
        let currentMonthStart = monthStart(for: today, calendar: calendar)

        let previousMonthKey = CalendarPageStateSupport.dateKeyForVisibleMonth(
            visibleMonthIdx: 59,
            currentMonthStart: currentMonthStart,
            calendar: calendar,
            today: today
        )
        let currentMonthKey = CalendarPageStateSupport.dateKeyForVisibleMonth(
            visibleMonthIdx: 60,
            currentMonthStart: currentMonthStart,
            calendar: calendar,
            today: today
        )

        // April 2026 opens on Wed Apr 1, so its block starts at the first Sunday, Apr 5 — the
        // first day that page actually draws. Handing back Apr 1 would name a day drawn on
        // March's page, and the month -> week -> month round trip would come back a block early.
        #expect(previousMonthKey == "2026-04-05")
        // May 5 2026 is on May's own block, so returning to the timeline keeps today.
        #expect(currentMonthKey == "2026-05-05")
    }

    @Test func calendarViewModeChangeCommitsVisibleTimelineDayBeforeOpeningMonth() throws {
        let calendar = Calendar.current
        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        var visibleMonthIdx = 60
        var monthGridResetNonce = 0
        var didRestoreTimelineScroll = true
        var visibleTimelineDayIndex: Int? = 48
        var anchorDateKey = "2026-05-01"

        CalendarPageDataSupport.handleViewModeChange(
            oldMode: .week,
            newMode: .month,
            visibleMonthIdx: &visibleMonthIdx,
            monthGridResetNonce: &monthGridResetNonce,
            didRestoreTimelineScroll: &didRestoreTimelineScroll,
            visibleTimelineDayIndex: &visibleTimelineDayIndex,
            anchorDateKey: &anchorDateKey,
            bufferStart: bufferStart,
            todayDayIdx: 4,
            calendar: calendar,
            currentMonthStart: monthStart(for: bufferStart, calendar: calendar)
        )

        #expect(anchorDateKey == "2026-06-18")
        #expect(visibleMonthIdx == 61)
        #expect(monthGridResetNonce == 1)
    }
#endif

    @Test func calendarBoardSummaryLimitsMarkersAndCountsOverflow() {
        let dateKey = "2026-05-27"
        let tasks = (0..<3).map { index in
            let task = AppTask(title: "Task \(index)")
            task.scheduledDate = dateKey
            task.order = index
            return task
        }
        let bundles = [
            TaskBundle(title: "Bundle 1", dateKey: dateKey, startMin: 540, durationMinutes: 30),
            TaskBundle(title: "Bundle 2", dateKey: dateKey, startMin: 600, durationMinutes: 30)
        ]
        let events = [
            CadenceCalendarBoardMarker(id: "event-1", kind: .event, color: Theme.purple, isCompleted: false, count: 1),
            CadenceCalendarBoardMarker(id: "event-2", kind: .event, color: Theme.blue, isCompleted: false, count: 1)
        ]

        let summary = CadenceCalendarBoardSupport.daySummary(
            dateKey: dateKey,
            tasks: tasks,
            bundles: bundles,
            eventMarkers: events,
            maxTaskMarkers: 2,
            maxEventMarkers: 1,
            maxBundleMarkers: 1
        )

        #expect(summary.dateKey == dateKey)
        let taskKindsAreTasks = summary.taskMarkers.allSatisfy { marker in
            if case .task = marker.kind { return true }
            return false
        }
        let firstEventIsEvent: Bool = {
            guard let kind = summary.eventMarkers.first?.kind else { return false }
            if case .event = kind { return true }
            return false
        }()

        #expect(summary.taskMarkers.count == 1)
        #expect(summary.taskMarkers.first?.count == 3)
        #expect(taskKindsAreTasks)
        #expect(summary.eventMarkers.count == 1)
        #expect(firstEventIsEvent)
        #expect(summary.bundleCount == 1)
        #expect(summary.overflowCount == 2)
        #expect(summary.totalCount == 7)
    }

    @Test func calendarBoardUsesMonthTitleAndNavigationSemantics() throws {
        let calendar = Calendar.current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 27, hour: 12)))
        let nextMonth = CadenceScheduleSupport.shiftedDate(date, mode: .month, by: 1, calendar: calendar)

        #expect(CadenceScheduleSupport.calendarTitle(for: date, mode: .month, calendar: calendar) == "May 2026")
        #expect(DateFormatters.dateKey(from: nextMonth) == "2026-06-27")
    }

#if os(macOS)
    @Test func calendarBoardMonthNavigationClampsToValidDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        let january31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)))
        let february = CalendarPageStateSupport.boardDateByMovingMonth(january31, by: 1, calendar: calendar)
        let februaryComponents = calendar.dateComponents([.year, .month, .day, .hour], from: february)

        #expect(februaryComponents.year == 2026)
        #expect(februaryComponents.month == 2)
        #expect(februaryComponents.day == 28)
        #expect(februaryComponents.hour == 0)

        let leapJanuary31 = try #require(calendar.date(from: DateComponents(year: 2028, month: 1, day: 31, hour: 12)))
        let leapFebruary = CalendarPageStateSupport.boardDateByMovingMonth(leapJanuary31, by: 1, calendar: calendar)
        let leapFebruaryComponents = calendar.dateComponents([.year, .month, .day], from: leapFebruary)

        #expect(leapFebruaryComponents.year == 2028)
        #expect(leapFebruaryComponents.month == 2)
        #expect(leapFebruaryComponents.day == 29)
    }

    @Test func calendarBoardAnchorRoundTripsBackToTimelineDay() throws {
        let calendar = Calendar.current
        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let currentMonthStart = monthStart(for: bufferStart, calendar: calendar)

        let boardAnchorKey = CalendarPageStateSupport.boardAnchorDateKey(
            viewMode: .week,
            visibleMonthIdx: 60,
            visibleTimelineDayIndex: 48,
            anchorDateKey: "2026-05-01",
            bufferStart: bufferStart,
            currentMonthStart: currentMonthStart,
            calendar: calendar
        )
        let returnDay = CalendarPageStateSupport.timelineDayIndex(
            anchorDateKey: boardAnchorKey,
            bufferStart: bufferStart,
            todayDayIdx: 4,
            calendar: calendar
        )

        #expect(boardAnchorKey == "2026-06-18")
        #expect(returnDay == 48)
    }
#endif

#if os(macOS)
    @MainActor
    @Test func markdownImageStyleDoesNotCaptureTrailingNewline() throws {
        let imageID = UUID()
        let imageLine = "![Photo](cadence-image://\(imageID.uuidString))"
        let text = "\(imageLine)\nafter"
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.string = text

        MarkdownStylist.apply(to: textView)

        let storage = try #require(textView.textStorage)
        let imageLineLength = (imageLine as NSString).length
        let newlineIndex = imageLineLength
        let afterIndex = imageLineLength + 1

        #expect(storage.attribute(.cadenceMarkdownImage, at: 0, effectiveRange: nil) is MarkdownImageLayoutInfo)
        #expect(storage.attribute(.cadenceMarkdownHidden, at: 0, effectiveRange: nil) as? Bool == true)
        #expect(storage.attribute(.cadenceMarkdownImage, at: newlineIndex, effectiveRange: nil) == nil)
        #expect(storage.attribute(.cadenceMarkdownHidden, at: newlineIndex, effectiveRange: nil) == nil)
        #expect(storage.attribute(.cadenceMarkdownImage, at: afterIndex, effectiveRange: nil) == nil)
        #expect(storage.attribute(.cadenceMarkdownHidden, at: afterIndex, effectiveRange: nil) == nil)
    }

    @MainActor
    @Test func eventNoteSupportRecoversWhenCalendarEventIdentifierDrifts() throws {
        let oldID = "old-event-id"
        let newID = "new-event-id"
        let note = Note(
            kind: .meeting,
            title: "Planning Sync",
            calendarEventID: oldID,
            calendarID: "calendar-1",
            eventDateKey: "2026-04-29",
            eventStartMin: 600,
            eventEndMin: 630
        )

        let reopened = try #require(EventNoteSupport.noteForEditing(
            calendarEventID: newID,
            eventTitle: " planning   sync ",
            calendarID: "calendar-1",
            eventDateKey: "2026-04-29",
            eventStartMin: 600,
            eventEndMin: 630,
            notes: [note],
            insert: { _ in Issue.record("Should reuse matching meeting note instead of inserting") }
        ))

        #expect(reopened.id == note.id)
        #expect(reopened.calendarEventID == newID)
    }

    @MainActor
    @Test func recurringEventOccurrenceIdentifiersKeepMeetingNotesSeparate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let baseID = "recurring-event-id"
        let firstOccurrence = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 10, minute: 0)))
        let secondOccurrence = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 6, hour: 10, minute: 0)))
        let firstID = CalendarEventIdentity.occurrenceIdentifier(
            baseIdentifier: baseID,
            occurrenceDate: firstOccurrence,
            calendar: calendar
        )
        let secondID = CalendarEventIdentity.occurrenceIdentifier(
            baseIdentifier: baseID,
            occurrenceDate: secondOccurrence,
            calendar: calendar
        )
        let firstNote = Note(
            kind: .meeting,
            title: "Planning Sync",
            content: "First occurrence notes",
            calendarEventID: firstID,
            calendarID: "calendar-1",
            eventDateKey: "2026-04-29",
            eventStartMin: 600,
            eventEndMin: 630
        )

        var insertedNote: Note?
        let secondNote = try #require(EventNoteSupport.noteForEditing(
            calendarEventID: secondID,
            eventTitle: "Planning Sync",
            calendarID: "calendar-1",
            eventDateKey: "2026-05-06",
            eventStartMin: 600,
            eventEndMin: 630,
            notes: [firstNote],
            insert: { insertedNote = $0 }
        ))

        #expect(CalendarEventIdentity.lookupIdentifier(from: secondID) == baseID)
        #expect(secondNote.id != firstNote.id)
        #expect(insertedNote?.id == secondNote.id)
        #expect(secondNote.calendarEventID == secondID)
        #expect(firstNote.content == "First occurrence notes")
    }

    @MainActor
    @Test func eventNoteCreationSeedsFromNativeCalendarNotes() throws {
        var insertedNote: Note?
        let created = try #require(EventNoteSupport.noteForEditing(
            calendarEventID: "event-1",
            eventTitle: "Planning Sync",
            calendarID: "calendar-1",
            eventDateKey: "2026-05-06",
            eventStartMin: 600,
            eventEndMin: 630,
            nativeNotes: "Agenda\n\n- Review launch blockers",
            notes: [],
            insert: { insertedNote = $0 }
        ))

        #expect(insertedNote?.id == created.id)
        #expect(created.content == "Agenda\n\n- Review launch blockers")
    }

    @MainActor
    @Test func eventNoteCreationFallsBackToMarkdownTitleWhenNativeNotesAreEmpty() throws {
        var insertedNote: Note?
        let created = try #require(EventNoteSupport.noteForEditing(
            calendarEventID: "event-2",
            eventTitle: "Planning Sync",
            calendarID: "calendar-1",
            eventDateKey: "2026-05-06",
            eventStartMin: 600,
            eventEndMin: 630,
            nativeNotes: "   \n ",
            notes: [],
            insert: { insertedNote = $0 }
        ))

        #expect(insertedNote?.id == created.id)
        #expect(created.content == "# Planning Sync\n\n")
    }

    @Test func allDayEventDragPayloadKeepsOccurrenceIdentifierIntact() throws {
        let rawIdentifier = "event-1#occurrence=2026-05-06:600"
        let payload = CalendarEventDragPayload.allDayEventPayload(
            from: "allDayEvent:2026-05-06|\(rawIdentifier)"
        )

        #expect(payload?.sourceDateKey == "2026-05-06")
        #expect(payload?.eventIdentifier == rawIdentifier)
        #expect(CalendarEventIdentity.lookupIdentifier(from: payload?.eventIdentifier ?? "") == "event-1")
    }

    @Test func timedCalendarEventSegmentsAcrossMidnightForVisibleDay() throws {
        let store = EKEventStore()
        let calendar = Calendar.current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 18)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 6)))
        let secondDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let event = EKEvent(eventStore: store)
        event.title = "EXP Building Work"
        event.startDate = start
        event.endDate = end
        event.isAllDay = false

        let firstSegment = try #require(CalendarEventItem(event: event, clippedTo: start, calendar: calendar))
        let secondSegment = try #require(CalendarEventItem(event: event, clippedTo: secondDay, calendar: calendar))

        #expect(firstSegment.dateKey == "2026-06-11")
        #expect(firstSegment.startMin == 18 * 60)
        #expect(firstSegment.durationMinutes == 6 * 60)
        #expect(secondSegment.dateKey == "2026-06-12")
        #expect(secondSegment.startMin == 0)
        #expect(secondSegment.durationMinutes == 6 * 60)
    }

    @Test func calendarBoardEventDisplayUsesClippedVisibleDaySegment() throws {
        let store = EKEventStore()
        let calendar = Calendar.current
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 18)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 6)))
        let secondDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 12)))
        let event = EKEvent(eventStore: store)
        event.title = "EXP Building Work"
        event.startDate = start
        event.endDate = end
        event.isAllDay = false

        let segment = try #require(CalendarEventItem(event: event, clippedTo: secondDay, calendar: calendar))
        let boardItem = CalendarBoardEventDisplayItem(timed: segment)

        #expect(boardItem.dateKey == "2026-06-12")
        #expect(boardItem.startMin == 0)
        #expect(boardItem.durationMinutes == 6 * 60)
        #expect(boardItem.sortKey.startMinute == 0)
    }

    @MainActor
    @Test func linkedCalendarMeetingNotesAreSortedAndScoped() throws {
        let older = Note(kind: .meeting, title: "Older", calendarEventID: "a", calendarID: "calendar-1", eventDateKey: "2026-04-28", eventStartMin: 900)
        let newer = Note(kind: .meeting, title: "Newer", calendarEventID: "b", calendarID: "calendar-1", eventDateKey: "2026-04-29", eventStartMin: 600)
        let otherCalendar = Note(kind: .meeting, title: "Other", calendarEventID: "c", calendarID: "calendar-2", eventDateKey: "2026-04-30", eventStartMin: 600)

        let notes = EventNoteSupport.meetingNotes(forLinkedCalendarID: "calendar-1", in: [older, newer, otherCalendar])

        #expect(notes.map(\.title) == ["Newer", "Older"])
    }
#endif

    @Test func slashCommandTokenDetectsLineAndInlineTriggers() throws {
        let lineStart = "/" as NSString
        let lineStartToken = try #require(MarkdownSlashCommandTokenSupport.token(in: lineStart, cursor: lineStart.length, requiresTrailingSpace: false))
        #expect(lineStartToken.range == NSRange(location: 0, length: 1))
        #expect(lineStartToken.query == "")

        let inline = "Plan /h" as NSString
        let inlineToken = try #require(MarkdownSlashCommandTokenSupport.token(in: inline, cursor: inline.length, requiresTrailingSpace: false))
        #expect(inlineToken.range == NSRange(location: 5, length: 2))
        #expect(inlineToken.query == "h")
    }

    @Test func slashCommandTokenAllowsBackslashAliasAndRejectsPaths() throws {
        let backslash = "Plan \\h" as NSString
        let backslashToken = try #require(MarkdownSlashCommandTokenSupport.token(in: backslash, cursor: backslash.length, requiresTrailingSpace: false))
        #expect(backslashToken.range == NSRange(location: 5, length: 2))
        #expect(backslashToken.query == "h")

        let url = "https://example.com/" as NSString
        #expect(MarkdownSlashCommandTokenSupport.token(in: url, cursor: url.length, requiresTrailingSpace: false) == nil)
    }

}
