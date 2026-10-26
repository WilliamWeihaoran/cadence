import EventKit
import Foundation
import Testing
@testable import Cadence

/// **Repeat on an EXISTING event** ([[T-3171]] (ii)): both event editors offer the Repeat row, open
/// it on what the event does, and a changed answer re-rules the series for this and future events.
///
/// Behavioural where the claim is a value — which rules are read, what is written back, which span
/// a save uses, what a Save asks the host to write — because an `EKRecurrenceRule` is a value and
/// an `EKEvent` over a throwaway `EKEventStore` is never saved. Nothing here opens the real store or
/// asks for calendar access. The iOS sheet and both managers' write halves are source scans: the
/// sheet is `#if os(iOS)` and a manager's save needs an authorized store.
@Suite("Event repeat edit")
@MainActor
struct CadenceEventRepeatEditTests {

    private var calendar: Calendar { Calendar.current }

    /// Monday 15 June 2026, 10 AM.
    private func monday() throws -> Date {
        let day = try #require(DateFormatters.date(from: "2026-06-15", in: calendar))
        return try #require(calendar.date(byAdding: .hour, value: 10, to: day))
    }

    private func rule(
        _ frequency: EKRecurrenceFrequency,
        interval: Int = 1,
        days: [EKRecurrenceDayOfWeek]? = nil,
        monthDays: [NSNumber]? = nil,
        setPositions: [NSNumber]? = nil,
        end: EKRecurrenceEnd? = nil
    ) -> EKRecurrenceRule {
        EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: days,
            daysOfTheMonth: monthDays,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: setPositions,
            end: end
        )
    }

    // MARK: Reading an event's rules

    @Test("A one-off reads as Never; a detached occurrence with no rule is not offered")
    func oneOffAndDetached() throws {
        let start = try monday()
        #expect(CadenceEventRepeatSetting(rules: nil, isDetached: false, start: start) == .noRepeat)
        #expect(CadenceEventRepeatSetting(rules: [], isDetached: false, start: start) == .noRepeat)
        #expect(
            CadenceEventRepeatSetting(rules: nil, isDetached: true, start: start) == nil,
            "a detached occurrence read as a one-off, so Never would end a series the editor cannot see"
        )
    }

    @Test("The four plain frequencies read back, and a refinement Cadence cannot spell is refused")
    func whatIsReadable() throws {
        let start = try monday()
        let read = { (rules: [EKRecurrenceRule]) in
            CadenceEventRepeatSetting(rules: rules, isDetached: false, start: start)?.rule
        }
        #expect(read([rule(.daily)]) == .daily)
        #expect(read([rule(.weekly)]) == .weekly)
        #expect(read([rule(.monthly)]) == .monthly)
        #expect(read([rule(.yearly)]) == .yearly)

        // Synced "weekly"/"monthly" naming only the event's own day is the same rule.
        #expect(read([rule(.weekly, days: [EKRecurrenceDayOfWeek(.monday)])]) == .weekly)
        #expect(read([rule(.monthly, monthDays: [15])]) == .monthly)

        // Each of these would be overwritten by a rule that means something else.
        #expect(read([rule(.weekly, interval: 2)]) == nil, "every other week read as weekly")
        #expect(read([rule(.weekly, days: [EKRecurrenceDayOfWeek(.tuesday)])]) == nil)
        #expect(read([rule(.weekly, days: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday)])]) == nil)
        #expect(read([rule(.monthly, monthDays: [1])]) == nil)
        #expect(read([rule(.monthly, days: [EKRecurrenceDayOfWeek(.monday)], setPositions: [1])]) == nil)
        #expect(read([rule(.daily), rule(.weekly)]) == nil, "two rules read as one")
    }

    @Test("Every answer Cadence writes reads back as itself")
    func roundTrip() throws {
        let start = try monday()
        let ends: [(TaskRecurrenceEndMode, String, Int)] = [(.never, "", 0), (.onDate, "2026-09-30", 0), (.afterCount, "", 7)]
        for repeatRule in TaskRecurrenceRule.allCases where repeatRule != .none {
            for (mode, key, count) in ends {
                let setting = CadenceEventRepeatSetting(rule: repeatRule, endMode: mode, endDateKey: key, endCount: count)
                let written = try #require(setting.eventKitRule)
                let back = CadenceEventRepeatSetting(rules: [written], isDetached: false, start: start)
                #expect(back == setting, "\(repeatRule) \(mode) read back as \(String(describing: back))")
            }
        }
        #expect(CadenceEventRepeatSetting.noRepeat.eventKitRule == nil)
    }

    // MARK: Writing

    @Test("A changed Repeat saves this and future events, whatever scope was answered")
    func theEditSpan() {
        for scope in CalendarRecurrenceEditScope.allCases {
            #expect(CadenceEventCreationSupport.editSpan(for: scope, changesRecurrence: true) == .futureEvents)
            #expect(CadenceEventCreationSupport.editSpan(for: scope, changesRecurrence: false) == scope.eventSpan)
        }
    }

    @Test("A Save writes the series only when Repeat or Ends moved")
    func onlyAMovedAnswerIsWritten() throws {
        let start = try monday()
        var opened = CadenceScheduleDraft(
            editingEventID: "e1", title: "Standup", notes: "", location: "", calendarID: "c",
            start: start, end: start.addingTimeInterval(3600), isAllDay: false
        )
        let weekly = CadenceEventRepeatSetting(rule: .weekly, endMode: .afterCount, endDateKey: "", endCount: 10)
        weekly.seed(&opened)

        var draft = opened
        draft.title = "Renamed"
        #expect(CadenceEventRepeatSetting.edit(draft: draft, opened: opened) == nil, "an untouched Save re-ruled the series")

        draft.seriesEndCount = 4
        #expect(CadenceEventRepeatSetting.edit(draft: draft, opened: opened)?.endCount == 4)

        draft = opened
        draft.repeatRule = .daily
        #expect(
            CadenceEventRepeatSetting.edit(draft: draft, opened: opened)
                == CadenceEventRepeatSetting(rule: .daily, endMode: .afterCount, endDateKey: "", endCount: 10)
        )

        draft.repeatRule = .none
        #expect(CadenceEventRepeatSetting.edit(draft: draft, opened: opened) == CadenceEventRepeatSetting.noRepeat)
    }

    @Test("Applying an answer replaces the event's rules, and Never clears them")
    func applyRecurrence() throws {
        let start = try monday()
        let event = EKEvent(eventStore: EKEventStore())
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)

        let daily = CadenceEventRepeatSetting(rule: .daily, endMode: .afterCount, endDateKey: "", endCount: 3)
        CadenceEventCreationSupport.applyRecurrence(daily, to: event)
        #expect(event.recurrenceRules?.count == 1)
        #expect(CadenceEventRepeatSetting(event: event) == daily)

        CadenceEventCreationSupport.applyRecurrence(.noRepeat, to: event)
        #expect(event.recurrenceRules?.isEmpty ?? true)
        #expect(CadenceEventRepeatSetting(event: event) == .noRepeat)
    }

    // MARK: The two editors and the writes they reach

    private func code(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
        return CadenceSourceScan.strippingComments(raw)
    }

    @Test("Both editors offer Repeat over readable rules and open on the event's own answer")
    func bothEditorsOfferRepeat() throws {
        for path in ["Cadence/iOS/iOSCalendarEventEditSheet.swift", "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift"] {
            let editor = try code(path)
            #expect(!editor.contains("offersEventRepeat: false"), "\(path) still withholds Repeat")
            #expect(editor.contains("offersEventRepeat: offersRepeat"), "\(path)")
            #expect(editor.contains("CadenceEventRepeatSetting(event: event"), "\(path) opens without the event's rule")
            #expect(editor.contains(".seed(&"), "\(path)")
            // A changed Repeat drops "Only This Event" from the scope question.
            #expect(
                CadenceSourceScan.matchCount(
                    #"if !savesRecurrenceChange \{\s*Button\(CalendarRecurrenceEditScope\.thisOccurrence\.label\)"#,
                    in: editor
                ) == 1,
                "\(path) still offers Only This Event for a new rule"
            )
            #expect(editor.contains("pendingAction == .save && draft.changesRecurrence(from: openedDraft)"), "\(path)")
        }
    }

    @Test("The iOS save carries the answer and the edit span into the write")
    func theIOSWrite() throws {
        let sheet = try code("Cadence/iOS/iOSCalendarEventEditSheet.swift")
        let save = try #require(CadenceSourceScan.functionBody(named: "applySave", in: sheet))
        #expect(save.contains("CadenceEventRepeatSetting.edit(draft: draft, opened: openedDraft)"))
        #expect(save.contains("span: CadenceEventCreationSupport.editSpan(for: scope, changesRecurrence: recurrence != nil)"))
        #expect(save.contains("recurrence: recurrence"))

        let manager = try code("Cadence/iOS/iOSCalendarManager.swift")
        let update = try #require(CadenceSourceScan.declarationBody("func updateEvent(", in: manager))
        #expect(
            CadenceSourceScan.matchCount(
                #"if let recurrence \{\s*CadenceEventCreationSupport\.applyRecurrence\(recurrence, to: event\)\s*\}\s*do \{\s*try store\.save\(event, span: span\)"#,
                in: update
            ) == 1,
            "the iOS update drops the answer, or applies it after the save"
        )
    }

    @Test("The macOS write applies the answer and saves with the edit span; every host forwards it")
    func theMacWrite() throws {
        let manager = try code("Cadence/macOS/Services/CalendarManager.swift")
        #expect(manager.contains("CadenceEventCreationSupport.applyRecurrence(recurrence, to: event)"))
        #expect(manager.contains("span: CadenceEventCreationSupport.editSpan(for: scope, changesRecurrence: recurrence != nil)"))
        for host in [
            "Cadence/macOS/Views/TimelineEventBlock.swift",
            "Cadence/macOS/Views/CalendarBoardItemSupportViews.swift",
            "Cadence/macOS/Views/CalendarEventChipPopoverSupport.swift",
        ] {
            let source = try CadenceSourceScan.sourceFile(host)
            #expect(CadenceSourceScan.matchCount(#"recurrence: request\.recurrence"#, in: source) == 1, "\(host) drops the answer")
        }
    }

    #if os(macOS)
    @Test("The macOS popover opens on the series' rule and asks the host to write only a moved one")
    func theMacRequest() throws {
        let start = try monday()
        let event = EKEvent(eventStore: EKEventStore())
        event.title = "Standup"
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.recurrenceRules = [rule(.weekly, end: EKRecurrenceEnd(occurrenceCount: 6))]
        let item = CalendarEventItem(event: event)
        let opened = CalendarEventEditPopover.openingDraft(for: item)
        #expect(opened.repeatRule == .weekly)
        #expect(opened.effectiveSeriesEndMode == .afterCount)
        #expect(opened.seriesEndCount == 6)

        var draft = opened
        draft.title = "Renamed"
        let untouched = CalendarEventEditRequest(draft: draft, opened: opened, originalStart: start, originalEnd: event.endDate)
        #expect(untouched.recurrence == nil)

        draft.repeatRule = .monthly
        let moved = CalendarEventEditRequest(draft: draft, opened: opened, originalStart: start, originalEnd: event.endDate)
        #expect(moved.recurrence == CadenceEventRepeatSetting(rule: .monthly, endMode: .afterCount, endDateKey: "", endCount: 6))
    }
    #endif
}
