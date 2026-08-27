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
    @Test func focusTimerMinutesRollUpToTheContainingList() {
        let context = Context(name: "Work")
        let project = Project(name: "Website", context: context)
        let task = AppTask(title: "Write copy")
        task.project = project

        CadenceFocusSupport.logElapsedSeconds(25 * 60, to: task)

        #expect(task.actualMinutes == 25)
        #expect(project.loggedMinutes == 25)
    }

    /// Falls back to the area when there is no project, matching the manual log sheet.
    @Test func focusTimerMinutesRollUpToTheAreaWhenThereIsNoProject() {
        let area = Area(name: "Life")
        let task = AppTask(title: "Errand")
        task.area = area

        CadenceFocusSupport.logElapsedSeconds(90, to: task)

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
