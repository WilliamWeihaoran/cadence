//
//  CadenceTests.swift
//  CadenceTests
//
//  Created by William Wei on 3/26/26.
//

import Testing
import Foundation
#if os(macOS)
import AppKit
#endif
@testable import Cadence

struct CadenceTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

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

    @Test func monthToTimelineReturnUsesVisibleMonthInsteadOfStaleRememberedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

        let currentMonthDay = CalendarPageStateSupport.timelineDayIndexForMonthViewReturn(
            visibleMonthIdx: 60,
            bufferStart: bufferStart,
            todayDayIdx: 120,
            calendar: calendar,
            today: today
        )
        let previousMonthDay = CalendarPageStateSupport.timelineDayIndexForMonthViewReturn(
            visibleMonthIdx: 59,
            bufferStart: bufferStart,
            todayDayIdx: 120,
            calendar: calendar,
            today: today
        )

        #expect(currentMonthDay == 120)
        #expect(previousMonthDay == 90)
    }

    @Test func calendarTitleUsesVisibleTimelineMonthAcrossBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

        let bufferStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20)))
        let label = CalendarPageLifecycleSupport.calendarTitleLabel(
            viewMode: .week,
            visibleMonthIdx: 60,
            visibleTimelineDayIndex: 12,
            rememberedDateKey: "2026-04-20",
            bufferStart: bufferStart,
            todayDayIdx: 0,
            calendar: calendar
        )

        #expect(label == "May 2026")
    }

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
