//
//  NotificationSchedulingDSTTests.swift
//  CadenceTests
//
//  T-3048. `TaskNotificationPlanner.startNotification` turned `scheduledStartMin` into an instant
//  by adding elapsed minutes to midnight. `.minute` is not a calendrical unit, so on the two days a
//  year that are 23 or 25 hours long the reminder landed an hour away from the clock reading every
//  timeline, row and chip renders for the same field — and the error is carried, not absorbed:
//  `triggerSpec` extracts `.hour`/`.minute` from this instant and `UNCalendarNotificationTrigger`
//  fires at them.
//
//  **Why this file states a zone instead of relying on the host.** The scheme's `TestAction` pins
//  `TZ=UTC` ([[T-1116]]) and UTC has no DST, so a test that read `Calendar.current` here would
//  measure a zone in which the whole distinction is invisible: it would pass against the defect and
//  against the fix, forever, and say nothing either time. Every assertion below therefore builds an
//  explicit `America/New_York` calendar through `CadenceTestTimeZones.calendar(_:)` and reads its
//  components back out of that same calendar. The pin is not touched and must not be.
//
//  New York rather than one of `CadenceTestTimeZones.identifiers`: it is the zone T-3048's
//  measurements were taken in, so a failure here is directly comparable to the numbers in the
//  ticket. America/Los_Angeles transitions on the same two dates and would read identically.
//

import Foundation
import SwiftData
import Testing
@testable import Cadence

@MainActor
struct NotificationSchedulingDSTTests {
    /// 2026-03-08 loses an hour at 02:00, 2026-11-01 repeats one at 02:00, and 2026-06-15 is an
    /// ordinary 24-hour day. The ordinary day is not padding: without it a green run cannot
    /// distinguish "the transition days are right" from "every day is wrong by the same amount".
    private static let springForward = "2026-03-08"
    private static let fallBack = "2026-11-01"
    private static let ordinary = "2026-06-15"
    private static let everyDay = [springForward, ordinary, fallBack]

    /// Long before any date under test, so `fireDate > now` is never the thing being measured here.
    /// The existing `NotificationSchedulingTests` owns the already-past guard.
    private static let longPast = Date(timeIntervalSince1970: 0)

    private func newYork() throws -> Calendar {
        try CadenceTestTimeZones.calendar("America/New_York")
    }

    private func scheduled(_ dateKey: String, startMin: Int) -> AppTask {
        let task = AppTask(title: "Standup")
        task.scheduledDate = dateKey
        task.scheduledStartMin = startMin
        return task
    }

    // MARK: - The defect

    @Test func startReminderFiresAtTheWallClockTimeTheUIRendersOnBothDSTTransitionDays() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let task = scheduled(dateKey, startMin: 540) // 09:00 — what every row renders
            let request = try #require(
                TaskNotificationPlanner.startNotification(for: task, now: Self.longPast, calendar: calendar),
                "no start reminder was planned for \(dateKey)"
            )
            let components = calendar.dateComponents([.hour, .minute], from: request.fireDate)

            #expect(
                components.hour == 9,
                """
                the start reminder for \(dateKey) fires at hour \(components.hour ?? -1), not 9 — \
                scheduledStartMin 540 is 09:00 and must read 09:00 on a 23-hour day, a 25-hour day \
                and an ordinary one alike
                """
            )
            #expect(components.minute == 0, "the start reminder for \(dateKey) fires at minute \(components.minute ?? -1), not 0")
            #expect(
                DateFormatters.dateKey(from: request.fireDate, calendar: calendar) == dateKey,
                "the start reminder for \(dateKey) landed on a different calendar day"
            )
        }
    }

    /// The leg that was always right, asserted on the same three days so a later edit cannot quietly
    /// convert it to the arithmetic this ticket removed.
    @Test func dueReminderStillFiresAtItsStatedHourOnBothDSTTransitionDays() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let task = AppTask(title: "Ship it")
            task.dueDate = dateKey
            let request = try #require(
                TaskNotificationPlanner.dueNotification(
                    for: task,
                    now: Self.longPast,
                    reminderHour: 9,
                    reminderMinute: 0,
                    calendar: calendar
                ),
                "no due reminder was planned for \(dateKey)"
            )
            let components = calendar.dateComponents([.hour, .minute], from: request.fireDate)

            #expect(
                components.hour == 9,
                "the due reminder for \(dateKey) fires at hour \(components.hour ?? -1), not the 9 it was asked for"
            )
            #expect(components.minute == 0, "the due reminder for \(dateKey) fires at minute \(components.minute ?? -1), not 0")
        }
    }

    /// The point of the fix, stated as the property rather than as two separate hours: a 09:00 start
    /// and a 09:00 due reminder on the same day are the same instant, on every day of the year.
    @Test func theStartAndDueLegsAgreeOnTheSameWallClockTimeOnEveryDSTDay() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            let timed = scheduled(dateKey, startMin: 540)
            let due = AppTask(title: "Ship it")
            due.dueDate = dateKey

            let start = try #require(
                TaskNotificationPlanner.startNotification(for: timed, now: Self.longPast, calendar: calendar)
            )
            let deadline = try #require(
                TaskNotificationPlanner.dueNotification(
                    for: due,
                    now: Self.longPast,
                    reminderHour: 9,
                    reminderMinute: 0,
                    calendar: calendar
                )
            )

            #expect(
                start.fireDate == deadline.fireDate,
                "on \(dateKey) a 09:00 start and a 09:00 due reminder are different instants"
            )
        }
    }

    // MARK: - The times that needed a decision

    /// 02:30 does not exist on 2026-03-08 in New York: the clocks go 01:59:59 EST -> 03:00:00 EDT.
    /// The chosen answer is the first instant at or after the missing reading, so a reminder inside
    /// the gap fires the moment the gap closes rather than being skipped or pushed a day. The old
    /// arithmetic answered 03:30 — a full hour past a start time nobody asked for.
    @Test func aStartTimeInsideTheSpringForwardGapFiresAsSoonAsTheGapCloses() throws {
        let calendar = try newYork()
        let task = scheduled(Self.springForward, startMin: 150) // 02:30, a reading this day skips

        let request = try #require(
            TaskNotificationPlanner.startNotification(for: task, now: Self.longPast, calendar: calendar),
            "a start time inside the DST gap planned no reminder at all"
        )
        let components = calendar.dateComponents([.hour, .minute], from: request.fireDate)

        #expect(
            components.hour == 3 && components.minute == 0,
            """
            a 02:30 start on \(Self.springForward) fired at \
            \(components.hour ?? -1):\(String(format: "%02d", components.minute ?? -1)), not 03:00 — \
            the chosen answer is the first instant after the gap closes
            """
        )
        #expect(
            DateFormatters.dateKey(from: request.fireDate, calendar: calendar) == Self.springForward,
            "the gap reminder left the task's own day"
        )
    }

    /// 01:30 happens twice on 2026-11-01. The chosen answer is the first of the two — the EDT one —
    /// because it is the only reading that cannot arrive after the time the user named.
    @Test func anAmbiguousStartTimeOnTheFallBackDayFiresAtTheFirstOfItsTwoReadings() throws {
        let calendar = try newYork()
        let task = scheduled(Self.fallBack, startMin: 90) // 01:30, a reading this day has twice

        let request = try #require(
            TaskNotificationPlanner.startNotification(for: task, now: Self.longPast, calendar: calendar)
        )
        let components = calendar.dateComponents([.hour, .minute], from: request.fireDate)

        #expect(components.hour == 1 && components.minute == 30, "the ambiguous start did not read 01:30")
        #expect(
            calendar.timeZone.secondsFromGMT(for: request.fireDate) == -14_400,
            """
            the 01:30 reminder on \(Self.fallBack) resolved to the second (EST) occurrence at offset \
            \(calendar.timeZone.secondsFromGMT(for: request.fireDate)) — it must be the first, EDT at -14400
            """
        )
    }

    /// The two ends of the range, on all three days. 1439 in particular must stay on the task's own
    /// day: a 23:59 reminder that rolls into tomorrow is a reminder for the wrong task list.
    @Test func midnightAndTheLastMinuteOfTheDayStayOnTheTasksOwnDay() throws {
        let calendar = try newYork()

        for dateKey in Self.everyDay {
            for (startMin, hour, minute) in [(0, 0, 0), (1439, 23, 59)] {
                let task = scheduled(dateKey, startMin: startMin)
                let request = try #require(
                    TaskNotificationPlanner.startNotification(for: task, now: Self.longPast, calendar: calendar),
                    "scheduledStartMin \(startMin) on \(dateKey) planned no reminder"
                )
                let components = calendar.dateComponents([.hour, .minute], from: request.fireDate)

                #expect(
                    components.hour == hour && components.minute == minute,
                    """
                    scheduledStartMin \(startMin) on \(dateKey) fired at \
                    \(components.hour ?? -1):\(String(format: "%02d", components.minute ?? -1)), not \
                    \(hour):\(String(format: "%02d", minute))
                    """
                )
                #expect(
                    DateFormatters.dateKey(from: request.fireDate, calendar: calendar) == dateKey,
                    "scheduledStartMin \(startMin) left \(dateKey)"
                )
            }
        }
    }

    /// A minute past the end of the day names no wall-clock time on that day, so no reminder is
    /// planned. Deliberate, and the one behaviour this fix changes beyond the DST days: every writer
    /// already holds the field to `0...1439` (`CadenceWriteService`, `AIActionService`), and the old
    /// arithmetic instead rolled such a value silently onto a *different calendar day* than the one
    /// the task is filed under — a reminder for a day the user is not looking at.
    @Test func aStartMinuteOutsideTheDayPlansNoReminderRatherThanOneOnTheFollowingDay() throws {
        let calendar = try newYork()

        for startMin in [1440, 1441, 2880] {
            let task = scheduled(Self.ordinary, startMin: startMin)
            #expect(
                TaskNotificationPlanner.startNotification(for: task, now: Self.longPast, calendar: calendar) == nil,
                "scheduledStartMin \(startMin) names no time on \(Self.ordinary) but still planned a reminder"
            )
        }
    }
}
