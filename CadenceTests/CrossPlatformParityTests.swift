import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Cadence

/// Divergences between `Cadence/Shared/` and the platforms that call it. This has been the
/// highest-yield bug category in the repo: the failures are invisible on the machine the author
/// is using, because they only appear under another platform, another region, or another calendar.
@MainActor
struct CrossPlatformParityTests {
    // MARK: - Storage keys are Gregorian everywhere

    /// Every `yyyy-MM-dd` key on disk was written through `DateFormatters.ymd`, which pins
    /// `en_US_POSIX` and therefore Gregorian. Any other derivation of the same key must agree, or
    /// it produces a string that matches nothing in the store.
    ///
    /// `Calendar.current` is not Gregorian everywhere — region Thailand defaults to Buddhist, and
    /// Japanese and Islamic calendars are one Settings tap away. For 2026-08-11 those produce
    /// `2569-08-11`, `0008-08-11` (the year is era-relative) and `1448-02-27`.
    @Test func everyStorageKeyDerivationAgreesUnderNonGregorianCalendars() throws {
        let reference = try #require(DateFormatters.date(from: "2026-08-11"))
        let expected = DateFormatters.dateKey(from: reference)

        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese, .islamicUmmAlQura] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = TimeZone.current

            #expect(
                DateFormatters.dateKey(from: reference, calendar: calendar) == expected,
                "dateKey(from:calendar:) diverged under \(identifier)"
            )
        }
    }

    /// Every fixed-format `DateFormatter` in the app has to pin its locale, or the string it
    /// produces follows the host's `Language & Region` instead of the format string.
    ///
    /// `monthYear` did not, and it renders the notes list's month headers and the calendar page's
    /// month title. On a French Mac those read "AOÛT 2026" while every other string in the app —
    /// which ships no localizations at all — stayed English. It also made
    /// `NotesListVisibilityTests.monthGroupingFormsRunsOverTheFilteredList` fail against a
    /// perfectly correct implementation, purely because of who ran it.
    @Test func displayFormattersPinTheirLocaleSoOutputDoesNotFollowTheHostRegion() throws {
        let formatters: [(String, DateFormatter)] = [
            ("ymd", DateFormatters.ymd),
            ("monthYear", DateFormatters.monthYear),
            ("shortMonthYear", DateFormatters.shortMonthYear)
        ]

        for (name, formatter) in formatters {
            #expect(
                formatter.locale?.identifier == "en_US_POSIX",
                "\(name) does not pin its locale, so its output follows the host region"
            )
        }

        let august = try #require(DateFormatters.date(from: "2026-08-01"))
        #expect(DateFormatters.monthYear.string(from: august) == "August 2026")
        // The two spellings, side by side, so neither can quietly become the other: the long one
        // renders the macOS calendar title and the notes list's month headings, the short one
        // renders `iOSDateJumpTitle` on every surface that control appears on.
        #expect(DateFormatters.shortMonthYear.string(from: august) == "Aug 2026")
    }

    /// The key must round-trip: the parse side is what resolves a stored key back to a day, and it
    /// had the same `Calendar.current` dependency.
    @Test func storageKeysRoundTripUnderNonGregorianCalendars() throws {
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = TimeZone.current

            let parsed = try #require(DateFormatters.date(from: "2026-08-11", in: calendar))
            #expect(DateFormatters.dateKey(from: parsed, calendar: calendar) == "2026-08-11")
        }
    }

    /// The widget helpers used to format by hand, as a main-actor workaround: widget timeline
    /// providers run off the main actor and `DateFormatters` was isolated. The workaround read its
    /// components off `Calendar.current`, so the workaround itself introduced a divergence — the
    /// Today and Calendar widgets matched no rows and every task rendered "Overdue". They forward
    /// to `DateFormatters` now (T-301), and this stays as the assertion that they still agree.
    @Test func theWidgetsDeriveTheSameStorageKeyAsTheApp() throws {
        let reference = try #require(DateFormatters.date(from: "2026-08-11"))

        let expected = DateFormatters.dateKey(from: reference)
        #expect(CadenceWidgetDateSupport.dateKey(from: reference) == expected)

        // A test host's `Calendar.current` is always Gregorian, so the convenience spelling above
        // cannot distinguish a correct implementation from one reading `Calendar.current`'s own
        // components. The injectable form can.
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese, .islamicUmmAlQura] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = TimeZone.current
            #expect(
                CadenceWidgetDateSupport.dateKey(from: reference, calendar: calendar) == expected,
                "widget dateKey diverged under \(identifier)"
            )
        }

        let parsed = try #require(CadenceWidgetDateSupport.parsedDate(fromKey: "2026-08-11"))
        #expect(CadenceWidgetDateSupport.dateKey(from: parsed) == "2026-08-11")
    }

    /// A widget's date labels sit on the home screen beside app chrome that is English on every
    /// host, because `DateFormatters` pins every display format to `en_US_POSIX`. These three were
    /// built with `date.formatted(...)` instead, which follows `Locale.current`: measured on this
    /// toolchain under `fr_FR` they read `SAM.` and `15 août`, and under `ar_SA` — where the
    /// current calendar is Islamic too — `سبت`, `٢` and `٢ ربيع الأول`. The assertion is the
    /// English value, which is what a pinned formatter returns on any of those hosts.
    @Test func theWidgetsSpellDatesInEnglishTheWayTheAppDoes() throws {
        let saturday = try #require(DateFormatters.date(from: "2026-08-15"))

        #expect(CadenceWidgetDateSupport.weekdayLabel(from: saturday) == "SAT")
        #expect(CadenceWidgetDateSupport.dayNumberLabel(from: saturday) == "15")
        #expect(CadenceWidgetDateSupport.dayLabel(fromKey: "2026-08-15") == "Aug 15")
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-08-15", todayKey: "2026-08-01") == "Due Aug 15")
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-08-15", todayKey: "2026-08-20") == "Overdue Aug 15")

        // The app's own spelling of the same day, so the two cannot drift apart in either
        // direction — the widget is not merely English, it is the app's English.
        #expect(CadenceWidgetDateSupport.dayLabel(fromKey: "2026-08-15")
            == DateFormatters.shortDateString(from: "2026-08-15"))
        #expect(CadenceWidgetDateSupport.weekdayLabel(from: saturday)
            == DateFormatters.dayOfWeek.string(from: saturday).uppercased())
    }

    // MARK: - Archived kanban columns survive a write through `sectionNames`

    /// `sectionNames` hides archived columns on read, so it has to restore them on write. It used
    /// to rebuild the whole config array from the assigned value, which made every write a silent
    /// delete of every archived column — and `iOSListEditorViews` edits a list purely through this
    /// property, so opening a list on iPhone and tapping Save with no changes destroyed them.
    @Test func writingSectionNamesPreservesArchivedColumnsAndTheirMetadata() {
        let area = Area(name: "Website")
        area.sectionConfigs = [
            TaskSectionConfig(name: "Default"),
            TaskSectionConfig(name: "Doing", colorHex: "#ff5533", dueDate: "2026-09-01"),
            TaskSectionConfig(name: "Shipped", isCompleted: true, isArchived: true),
        ]

        // Exactly what the iOS editor does: read the visible names, write them straight back.
        #expect(area.sectionNames == ["Default", "Doing"])
        area.sectionNames = area.sectionNames

        #expect(area.sectionConfigs.map(\.name).sorted() == ["Default", "Doing", "Shipped"])

        let shipped = area.sectionConfigs.first { $0.name == "Shipped" }
        #expect(shipped?.isArchived == true)
        #expect(shipped?.isCompleted == true)

        // A surviving visible column keeps its identity and its metadata.
        let doing = area.sectionConfigs.first { $0.name == "Doing" }
        #expect(doing?.colorHex == "#ff5533")
        #expect(doing?.dueDate == "2026-09-01")
        #expect(doing?.isArchived == false)
    }

    /// Same accessor, same bug, on the other model.
    @Test func projectSectionNamesAlsoPreservesArchivedColumns() {
        let project = Project(name: "Launch")
        project.sectionConfigs = [
            TaskSectionConfig(name: "Default"),
            TaskSectionConfig(name: "Old Phase", isArchived: true),
        ]

        project.sectionNames = ["Default", "New Phase"]

        #expect(project.sectionConfigs.map(\.name) == ["Default", "New Phase", "Old Phase"])
        #expect(project.sectionConfigs.first { $0.name == "Old Phase" }?.isArchived == true)
    }

    /// Unarchiving still has to work: naming an archived column brings it back rather than
    /// leaving a duplicate behind.
    @Test func namingAnArchivedColumnUnarchivesItWithoutDuplicating() {
        let area = Area(name: "Website")
        area.sectionConfigs = [
            TaskSectionConfig(name: "Default"),
            TaskSectionConfig(name: "Shipped", colorHex: "#4ecb71", isArchived: true),
        ]

        area.sectionNames = ["Default", "Shipped"]

        #expect(area.sectionConfigs.count == 2)
        let shipped = area.sectionConfigs.first { $0.name == "Shipped" }
        #expect(shipped?.isArchived == false)
        #expect(shipped?.colorHex == "#4ecb71")
    }

    // MARK: - Focus logging

    /// Running the macOS timer never moved `project.loggedMinutes`, which an hours-mode goal
    /// reads — while macOS's own manual "log session" sheet did, and so did the bundle branch of
    /// the same timer. Three paths, two behaviors, one Mac.
    @Test func focusTimerMinutesRollUpToTheContainingList() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let context = Context(name: "Work")
        let project = Project(name: "Website", context: context)
        let task = AppTask(title: "Write copy")
        task.project = project

        CadenceFocusSupport.bankElapsedSeconds(25 * 60, to: task, in: modelContext)

        #expect(task.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
    }

    /// Falls back to the area when there is no project, matching the manual log sheet.
    @Test func focusTimerMinutesRollUpToTheAreaWhenThereIsNoProject() throws {
        let modelContext = ModelContext(try CadenceTestStore.container())
        let area = Area(name: "Life")
        let task = AppTask(title: "Errand")
        task.area = area

        CadenceFocusSupport.bankElapsedSeconds(90, to: task, in: modelContext)

        #expect(task.actualMinutes == 2)
        #expect(area.loggedMinutes == 2)
    }

    /// Nearest-minute, not rounded up. macOS ceil'd, so ten 61-second sessions reported twenty
    /// minutes of work for ten minutes done — and the same stopwatch reading logged a different
    /// number on each platform.
    @Test func elapsedSecondsConvertToMinutesByRoundingNotCeiling() {
        #expect(CadenceFocusSupport.minutes(fromElapsedSeconds: 61) == 1)
        #expect(CadenceFocusSupport.minutes(fromElapsedSeconds: 90) == 2)
        #expect(CadenceFocusSupport.minutes(fromElapsedSeconds: 20) == 0)
        #expect(CadenceFocusSupport.minutes(fromElapsedSeconds: 0) == 0)
        #expect(CadenceFocusSupport.minutes(fromElapsedSeconds: -5) == 0)
    }

    // MARK: - Month grid headings match their own columns

    /// `Calendar.shortWeekdaySymbols` is indexed by weekday number, so `[0]` is always Sunday
    /// however `firstWeekday` is set — localized in content, fixed in order. The grid honors
    /// `firstWeekday`, so pairing the two directly labelled every cell with the wrong weekday
    /// outside Sunday-first regions.
    @Test func monthGridHeadingsNameTheWeekdayOfTheirOwnColumn() throws {
        let monthDate = try #require(DateFormatters.date(from: "2026-08-15"))

        for firstWeekday in 1...7 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday

            let headings = CadenceScheduleSupport.weekdaySymbols(calendar: calendar)
            let days = CadenceScheduleSupport.monthGridDays(for: monthDate, calendar: calendar)

            #expect(headings.count == 7)
            try #require(days.count >= 7)

            for column in 0..<7 {
                let weekday = calendar.component(.weekday, from: days[column])
                let expected = calendar.shortWeekdaySymbols[weekday - 1]
                #expect(
                    headings[column] == expected,
                    "firstWeekday \(firstWeekday): column \(column) labelled \(headings[column]) but holds \(expected)"
                )
            }
        }
    }

    // MARK: - T-330: the list description macOS could search but not edit

    /// The macOS list editors' shared identity header now carries the description, and carries it
    /// as a *binding* — the thing that makes it editable rather than merely displayed. A copy of
    /// the string would satisfy "macOS shows the description" and still lose every keystroke.
    ///
    /// `Binding<String>?` rather than `String?`: `CreateContextSheet` shares this header for a model
    /// with no description at all, so the field has to be genuinely absent there, not empty.
    @Test func theMacOSListIdentityHeaderCarriesTheDescriptionAsALiveBinding() {
        var stored = "typed on iPhone"
        let withDescription = ListEditorIdentityHeader(
            name: .constant("Launch"),
            colorHex: .constant(Theme.blueHex),
            icon: .constant("checklist"),
            details: Binding(get: { stored }, set: { stored = $0 })
        )

        #expect(withDescription.details?.wrappedValue == "typed on iPhone")
        withDescription.details?.wrappedValue = "edited on macOS"
        #expect(stored == "edited on macOS")

        let withoutDescription = ListEditorIdentityHeader(
            name: .constant("Work"),
            colorHex: .constant(Theme.blueHex),
            icon: .constant("folder.fill")
        )
        #expect(withoutDescription.details == nil)
    }

    /// **The call-site half.** The binding above proves the header *can* carry a description; only
    /// the sheets can prove one survives a round trip, and their state and save paths are private
    /// to a SwiftUI `View`. So the three editors are read as source — the precedent
    /// `CadenceSharedBoardChromeTests` sets, and the only tool that reaches `Cadence/iOS/` at all
    /// from a target that builds for macOS.
    ///
    /// Both macOS sheets *write* the field; only the edit sheet also reads it back, because the
    /// create sheet has nothing to read. That asymmetry is why this is a table rather than a loop.
    @Test func everyListEditorOnBothPlatformsWritesTheDescriptionAndTheEditorsAlsoLoadIt() throws {
        let writes: [String: [String]] = [
            // iOS: the surface that could always do this, kept here so a regression that removes
            // it registers as the parity break it would be rather than as an iOS-only change.
            "Cadence/iOS/iOSListEditorViews.swift": ["area", "project"],
            "Cadence/macOS/Sheets/CreateListSheet.swift": ["area", "project"],
            "Cadence/macOS/Sheets/EditListSheet.swift": ["area", "project"]
        ]

        for (relativePath, models) in writes {
            let raw = try paritySourceFile(relativePath)
            let code = try parityStrippingComments(raw)
            #expect(code != raw, "\(relativePath) has no comments, so the stripper read the wrong file")
            #expect(code.count == raw.count, "the comment stripper changed \(relativePath)'s length")
            #expect(code.contains("ListEditorIdentityHeader") || code.contains("TextField"), "\(relativePath) is not a list editor")

            for model in models {
                #expect(
                    code.range(of: "\(model)\\.desc\\s*=", options: .regularExpression) != nil,
                    "\(relativePath) never writes \(model).desc"
                )
            }
        }

        // The edit sheets must seed their field from the stored value, or an existing description
        // is silently blanked the first time somebody renames the list.
        let editSheet = try parityStrippingComments(paritySourceFile("Cadence/macOS/Sheets/EditListSheet.swift"))
        for model in ["area", "project"] {
            #expect(
                editSheet.contains("State(initialValue: \(model).desc)"),
                "EditListSheet does not load \(model).desc into its field"
            )
        }

        // And both macOS sheets must hand it to the shared header rather than declaring a field
        // nothing draws.
        for relativePath in [
            "Cadence/macOS/Sheets/CreateListSheet.swift",
            "Cadence/macOS/Sheets/EditListSheet.swift"
        ] {
            let code = try parityStrippingComments(paritySourceFile(relativePath))
            let headers = code.components(separatedBy: "ListEditorIdentityHeader(").count - 1
            let passed = code.components(separatedBy: "details: $details").count - 1
            #expect(headers > 0, "\(relativePath) draws no identity header")
            #expect(passed == headers, "\(relativePath) draws \(headers) identity headers but passes a description to \(passed)")
        }

        // Self-check for the assignment regex: it must match a write and must not match the read
        // that loads the same property back out.
        #expect("area.desc = details".range(of: "area\\.desc\\s*=", options: .regularExpression) != nil)
        #expect("details = area.desc".range(of: "area\\.desc\\s*=", options: .regularExpression) == nil)
    }

    // MARK: - T-410: a corrupt habit reminder time reads the same on both platforms

    /// Behavioural, not a scan: the decision both editors now read, run directly.
    ///
    /// The two old renderings are asserted here as *inputs*, so this test knows what it replaced:
    /// 1440 is the value iOS showed as "12 AM", and -15 and 1440 are both values
    /// `Calendar.date(bySettingHour:minute:second:of:)` answers `nil` for, which is how macOS
    /// reached its `?? Date()`.
    @Test func aStoredHabitReminderMinuteOutsideTheSchedulableRangeOpensUnset() {
        // In range: loaded as-is, both ends included.
        for minute in [0, 540, 1439] {
            let state = CadenceHabitReminderEditing.editorState(for: minute)
            #expect(state.isOn, "\(minute) is schedulable but opened unset")
            #expect(state.minuteOfDay == minute, "\(minute) opened on a different time")
        }

        // Unset stays unset, and 0 is not confused with it — midnight is a real reminder time.
        let unset = CadenceHabitReminderEditing.editorState(for: nil)
        #expect(unset.isOn == false)
        #expect(unset.minuteOfDay == CadenceHabitReminderEditing.defaultMinuteOfDay)
        #expect(CadenceHabitReminderEditing.defaultMinuteOfDay == 540)

        // Out of range opens unset rather than as an invented time.
        for corrupt in [-15, -1, 1440, 1500, 100_000] {
            let state = CadenceHabitReminderEditing.editorState(for: corrupt)
            #expect(state.isOn == false, "\(corrupt) opened as a set reminder")
            #expect(
                state.minuteOfDay == CadenceHabitReminderEditing.defaultMinuteOfDay,
                "\(corrupt) opened on a fabricated time"
            )
        }

        // The range is the scheduler's, not a second copy of it: this is what fails if someone
        // respells `0...1439` here and the two drift.
        #expect(HabitNotificationPlanner.reminderMinuteRange == 0...1439)
        for minute in [-15, 1440, 1500] {
            #expect(
                HabitNotificationPlanner.reminderMinuteRange.contains(minute) == false,
                "\(minute) is schedulable, so the editor is right to show it"
            )
            #expect(
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) == nil,
                "\(minute) resolves to a real time, so it was never the macOS symptom"
            )
        }

        // And the picker clamp, which is what stopped `?? Date()` from being reachable.
        #expect(CadenceHabitReminderEditing.editorMinuteOfDay(540) == 540)
        #expect(CadenceHabitReminderEditing.editorMinuteOfDay(0) == 0)
        #expect(CadenceHabitReminderEditing.editorMinuteOfDay(1439) == 1439)
        #expect(CadenceHabitReminderEditing.editorMinuteOfDay(1440) == CadenceHabitReminderEditing.defaultMinuteOfDay)
        #expect(CadenceHabitReminderEditing.editorMinuteOfDay(-15) == CadenceHabitReminderEditing.defaultMinuteOfDay)

        // The old iOS rendering, kept as the thing that is no longer reached: `timeString` still
        // wraps, because ordinary in-range callers rely on it. The editor just stops feeding it
        // junk.
        #expect(TimeFormatters.timeString(from: 1440) == "12 AM")
        #expect(TimeFormatters.timeString(from: CadenceHabitReminderEditing.editorState(for: 1440).minuteOfDay) == "9 AM")
    }


    /// `Habit.reminderMinuteOfDay` is an unvalidated `Int?` and says so in its own doc, so the
    /// two habit editors each had to decide what an out-of-range value looks like — and decided
    /// differently. macOS fed it to `Calendar.date(bySettingHour:minute:second:of:)`, which
    /// returns `nil` for hour 24, and its `?? Date()` fallback then rendered the reminder as
    /// **the current time**. iOS fed the same value to `TimeFormatters.timeString(from:)`, which
    /// takes it modulo a day, so 1440 read as **12 AM**. Both are inventions; a picker opened on
    /// either one saves it straight back as if the user had chosen it.
    ///
    /// The agreed answer is that neither editor names a time it cannot justify: an out-of-range
    /// value opens **unset**, exactly as `nil` does, and the range consulted is
    /// `HabitNotificationPlanner.reminderMinuteRange` — the one T-363 already made the app's only
    /// check, rather than a second spelling of `0...1439`.
    @Test func bothHabitEditorsOpenACorruptReminderTimeAsUnsetRatherThanInventingOne() throws {
        for relativePath in [
            "Cadence/macOS/Views/HabitsFormSheets.swift",
            "Cadence/iOS/iOSTrackingEditorSheets.swift"
        ] {
            let raw = try paritySourceFile(relativePath)
            let code = try parityStrippingComments(raw)
            #expect(raw.count > 1_000, "\(relativePath) read as \(raw.count) characters")
            #expect(code != raw, "\(relativePath) has no comments, so the stripper read the wrong file")
            #expect(code.count == raw.count, "the comment stripper changed \(relativePath)'s length")
            #expect(code.contains("reminderMinuteOfDay"), "\(relativePath) is not a habit editor")

            #expect(
                code.contains("CadenceHabitReminderEditing.editorState(for: habit.reminderMinuteOfDay)"),
                "\(relativePath) still decides for itself what a corrupt reminder time looks like"
            )
            #expect(
                CadenceSourceScan.matchCount(#"habit\.reminderMinuteOfDay \?\?"#, in: code) == 0,
                "\(relativePath) still coerces a stored reminder time with ??"
            )
            #expect(
                CadenceSourceScan.matchCount(#"habit\.reminderMinuteOfDay != nil"#, in: code) == 0,
                "\(relativePath) still treats any non-nil stored minute as a set reminder"
            )
            #expect(
                CadenceSourceScan.matchCount(#"9 \* 60"#, in: code) == 0,
                "\(relativePath) still spells the default reminder time itself"
            )
            #expect(
                code.contains("CadenceHabitReminderEditing.defaultMinuteOfDay"),
                "\(relativePath) does not read the shared default reminder time"
            )
        }

        // The desktop picker is the surface that rendered "now": its `Date` binding must clamp
        // before it asks `Calendar` for an hour, or the fallback is reachable again.
        let picker = try parityStrippingComments(paritySourceFile("Cadence/macOS/Views/HabitsFormSupportViews.swift"))
        #expect(picker.contains("HabitReminderPicker"), "read the wrong file for the desktop reminder picker")
        #expect(
            picker.contains("CadenceHabitReminderEditing.editorMinuteOfDay(reminderMinuteOfDay)"),
            "the desktop reminder picker can still render an out-of-range minute as the current time"
        )

        // Self-checks for the two needles that must find nothing above.
        #expect(CadenceSourceScan.matchCount(#"habit\.reminderMinuteOfDay \?\?"#, in: "habit.reminderMinuteOfDay ?? 9 * 60") == 1)
        #expect(CadenceSourceScan.matchCount(#"habit\.reminderMinuteOfDay \?\?"#, in: "editorState(for: habit.reminderMinuteOfDay)") == 0)
        #expect(CadenceSourceScan.matchCount(#"habit\.reminderMinuteOfDay != nil"#, in: "habit.reminderMinuteOfDay != nil") == 1)
        #expect(CadenceSourceScan.matchCount(#"habit\.reminderMinuteOfDay != nil"#, in: "reminder.isOn") == 0)
    }

    // MARK: - The widget date vocabulary carries no member nothing calls (T-453)

    /// `CadenceWidgetDateSupport` exists to give the widget target one spelling of every date
    /// string the app already has. After [[T-301]] collapsed its hand-rolled copies into forwards
    /// to `DateFormatters`, one member — `storageCalendar(inheritingTimeZoneFrom:)` — was left
    /// behind with **zero** callers: the two in-enum uses it was written for, in
    /// `dateKey(from:calendar:)` and `parsedDate(fromKey:)`, both became `DateFormatters` calls in
    /// the same commit. It was found by a mutation that *survived* — re-pointing it at the
    /// caller's calendar changed no test, because nothing reached it.
    ///
    /// A survived mutation is a weak signal and an expensive one. This is the cheap version, and
    /// it generalises: **every** member of this enum must be reached, so the next collapse that
    /// strands one fails here instead of waiting for a mutation to notice.
    ///
    /// Reach is counted two ways because Swift spells it two ways: qualified
    /// (`CadenceWidgetDateSupport.dueLabel(...)`) from anywhere, and unqualified from inside the
    /// enum's own body. Counting only the first would call `dayLabel(fromKey:)` — a private-ish
    /// helper only `dueLabel` uses — dead, which it is not.
    @Test func everyMemberOfTheWidgetDateVocabularyIsReachedFromSomewhere() throws {
        let declaringPath = "Cadence/Services/CadenceTodayWidgetSupport.swift"
        let sources = try parityWidgetVocabularySources()
        let declaringSource = try #require(sources[declaringPath], "the walk missed \(declaringPath)")
        let body = try #require(
            parityEnumBody(named: "CadenceWidgetDateSupport", in: declaringSource),
            "could not brace-match CadenceWidgetDateSupport's body in \(declaringPath)"
        )

        let members = Set(parityCaptures(#"static func ([A-Za-z_][A-Za-z0-9_]*)\s*\("#, in: body))

        // Non-vacuity for the extraction. A member list that came back empty or truncated is how
        // a census like this reports "nothing is dead" while having read nothing at all.
        #expect(members.count >= 6, "read only \(members.sorted()) out of the widget date enum")
        #expect(members.contains("dateKey"), "the extraction missed dateKey")
        #expect(members.contains("dueLabel"), "the extraction missed dueLabel")

        let paths = sources.keys.sorted()
        var census: [String: Int] = [:]
        for member in members.sorted() {
            let qualified = try parityQualifiedCallInstrument(for: member).sweep(
                paths,
                atLeast: 700,
                including: declaringPath,
                // `paths` is `sources.keys`, so this subscript cannot miss; the walk's own
                // non-vacuity is carried by `atLeast:` and `including:` above.
                read: { sources[$0] ?? "" }
            )
            let unqualifiedInsideTheEnum = CadenceSourceScan.matchCount(
                #"(?<!func )(?<![.\w])"# + member + #"\s*\("#,
                in: body
            )
            census[member] = qualified.count + unqualifiedInsideTheEnum
        }

        let unreached = census.filter { $0.value == 0 }.keys.sorted()
        #expect(unreached.isEmpty, "widget date members nothing calls: \(unreached); census \(census)")

        // The census is only worth reading if it can also come back non-zero, so pin the two ends:
        // a member every widget spells, and one only its neighbour in the enum spells.
        #expect((census["dueLabel"] ?? 0) > 0, "the census cannot see a qualified call")
        #expect((census["dayLabel"] ?? 0) > 0, "the census cannot see an unqualified in-enum call")
    }
}

/// Every Swift file the widget date vocabulary could be called from: the app, the widget extension
/// that compiles a subset of it, and the test target. Read once and cached, because the census
/// above asks the same files one question per member.
private func parityWidgetVocabularySources() throws -> [String: String] {
    var sources: [String: String] = [:]
    for root in ["Cadence", "CadenceWidgets", "CadenceTests"] {
        let directory = parityRepositoryRoot().appendingPathComponent(root)
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { continue }
        for element in enumerator {
            guard let name = element as? String, name.hasSuffix(".swift") else { continue }
            let path = "\(root)/\(name)"
            sources[path] = CadenceSourceScan.codeOnly(try paritySourceFile(path))
        }
    }
    return sources
}

/// The text between the braces of `enum <name> {`, found by brace matching. Deliberately not
/// `CadenceSourceScan.functionBody`, which anchors on `func <name>(`.
private func parityEnumBody(named name: String, in source: String) -> String? {
    guard let declaration = source.range(of: "enum \(name) {") else { return nil }
    guard let open = source.range(of: "{", range: declaration.lowerBound..<source.endIndex) else { return nil }

    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        if source[index] == "{" {
            depth += 1
        } else if source[index] == "}" {
            depth -= 1
            if depth == 0 { return String(source[source.index(after: open.lowerBound)..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

private func parityCaptures(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
        Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
}

/// Fires on a **qualified** call of one member. The negative witness is the same member name
/// called on the enum this one forwards to — the nearest miss there is, and the one a detector
/// keyed on the bare name would fail.
private func parityQualifiedCallInstrument(for member: String) throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "qualified call of CadenceWidgetDateSupport.\(member)",
        fires: "        let value = CadenceWidgetDateSupport.\(member)(from: Date())",
        andNotOn: "        let value = DateFormatters.\(member)(from: Date())",
        by: { source in
            CadenceSourceScan.matchCount(#"CadenceWidgetDateSupport\."# + member + #"\s*\("#, in: source) > 0
        }
    )
}

private func parityRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func paritySourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: parityRepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks comments to spaces of equal length, so the stripped string is never shorter than the
/// raw one — see `Cadence/Shared/AGENTS.md`, which is why the callers above assert
/// `code != raw` **and** `code.count == raw.count` rather than a length inequality that can never
/// fail.
private func parityStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
