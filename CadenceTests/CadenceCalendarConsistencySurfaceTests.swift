import Foundation
import Testing
@testable import Cadence

/// A calendar as the two sorters read it: a title and an identity. Sorting is pinned through this
/// rather than through `EKCalendar` because building one needs a live `EKEventStore`, and the
/// property that matters — a *total* order — is entirely about these two fields.
private struct CalendarSortStub {
    let title: String
    let calendarIdentifier: String
}

private func sortedStubs(_ stubs: [CalendarSortStub]) -> [String] {
    CadenceCalendarSorting
        .sorted(stubs, title: \.title, identifier: \.calendarIdentifier)
        .map(\.calendarIdentifier)
}

/// macOS and iOS disagreed three ways about calendars and events (T-379, T-380, T-332):
/// two different calendar orders neither of which was stable, two different placeholder labels
/// for an event with no title, and two spellings of "trim the name".
struct CadenceCalendarConsistencySurfaceTests {

    // MARK: - T-379: one order, and a total one

    /// Two calendars sharing a title is not exotic — the same calendar name in two accounts does
    /// it. Both old sorters returned `false` in both directions for that pair, so `sorted()` was
    /// free to hand back either sequence.
    @Test func sharedCalendarOrderBreaksTitleTiesOnCalendarIdentifier() {
        let stubs = [
            CalendarSortStub(title: "Work", calendarIdentifier: "id-work-icloud"),
            CalendarSortStub(title: "Work", calendarIdentifier: "id-work-google")
        ]

        #expect(sortedStubs(stubs) == ["id-work-google", "id-work-icloud"])
        #expect(sortedStubs(stubs.reversed()) == ["id-work-google", "id-work-icloud"])

        // And the comparator disagrees with itself in the two directions, which is what an
        // unordered pair fails to do.
        #expect(
            CadenceCalendarSorting.isOrderedBefore(
                lhsTitle: "Work",
                lhsIdentifier: "id-work-google",
                rhsTitle: "Work",
                rhsIdentifier: "id-work-icloud"
            )
        )
        #expect(
            !CadenceCalendarSorting.isOrderedBefore(
                lhsTitle: "Work",
                lhsIdentifier: "id-work-icloud",
                rhsTitle: "Work",
                rhsIdentifier: "id-work-google"
            )
        )
    }

    /// The property the two platforms now share: the same set of calendars sorts to the same
    /// sequence whatever order EventKit enumerated them in. The fixture is tie-heavy on purpose —
    /// a fixture of distinct titles pins nothing, because both old spellings already agreed there.
    @Test func sharedCalendarOrderIsIndependentOfTheOrderEventKitReturns() {
        let stubs = [
            CalendarSortStub(title: "Personal", calendarIdentifier: "id-3"),
            CalendarSortStub(title: "work", calendarIdentifier: "id-5"),
            CalendarSortStub(title: "Work", calendarIdentifier: "id-1"),
            CalendarSortStub(title: "Birthdays", calendarIdentifier: "id-4"),
            CalendarSortStub(title: "Work", calendarIdentifier: "id-2")
        ]

        let permutationA = sortedStubs(stubs)
        let permutationB = sortedStubs(stubs.reversed())
        let permutationC = sortedStubs([stubs[2], stubs[4], stubs[0], stubs[1], stubs[3]])

        #expect(permutationA == permutationB)
        #expect(permutationA == permutationC)
        #expect(permutationA.count == stubs.count)
        #expect(Set(permutationA).count == stubs.count)

        #expect(permutationA == ["id-4", "id-3", "id-1", "id-2", "id-5"])

        // Non-vacuity: the fixture really is tie-heavy, and the tie really was unordered.
        // Both legacy comparators answer `false` in *both* directions for the two "Work"
        // calendars — which is precisely the pair `sorted()` was free to resolve either way,
        // and why asserting on the legacy *output* would pin nothing (an unstable sort may
        // happen to agree). The shared comparator answers the same pair definitively.
        let tiedFirst = stubs[2]
        let tiedSecond = stubs[4]
        #expect(tiedFirst.title == tiedSecond.title)
        #expect(!(tiedFirst.title < tiedSecond.title))
        #expect(!(tiedSecond.title < tiedFirst.title))
        #expect(
            tiedFirst.title.localizedCaseInsensitiveCompare(tiedSecond.title) == .orderedSame
        )
        #expect(
            CadenceCalendarSorting.isOrderedBefore(
                lhsTitle: tiedFirst.title,
                lhsIdentifier: tiedFirst.calendarIdentifier,
                rhsTitle: tiedSecond.title,
                rhsIdentifier: tiedSecond.calendarIdentifier
            )
        )
    }

    /// Case is a collation detail, not an ordering fact: `"apple"` belongs beside `"Apple"`, not
    /// after `"Zebra"`. The raw `<` macOS used sorts every capitalised title ahead of every
    /// lowercase one.
    @Test func sharedCalendarOrderIsCaseInsensitiveLikeTheiOSSpelling() {
        let stubs = [
            CalendarSortStub(title: "zebra", calendarIdentifier: "id-z"),
            CalendarSortStub(title: "Apple", calendarIdentifier: "id-a")
        ]

        #expect(sortedStubs(stubs) == ["id-a", "id-z"])
        #expect(stubs.sorted { $0.title < $1.title }.map(\.calendarIdentifier) == ["id-a", "id-z"])

        let mixed = [
            CalendarSortStub(title: "Zebra", calendarIdentifier: "id-Z"),
            CalendarSortStub(title: "apple", calendarIdentifier: "id-a")
        ]

        #expect(sortedStubs(mixed) == ["id-a", "id-Z"])
        // The legacy spelling puts "Zebra" first here, which is the divergence being closed.
        #expect(mixed.sorted { $0.title < $1.title }.map(\.calendarIdentifier) == ["id-Z", "id-a"])
    }

    // MARK: - T-380: one placeholder, and a title that is never blank-looking

    /// The macOS bug: `" ".isEmpty` is `false`, so a space-bar title passed the guard and became
    /// the event's real name. Both platforms now normalise before deciding.
    @Test func whitespaceOnlyEventTitlesNormalizeToOnePlaceholder() {
        #expect(CadenceEventTitleSupport.storedTitle("") == "Untitled Event")
        #expect(CadenceEventTitleSupport.storedTitle(" ") == "Untitled Event")
        #expect(CadenceEventTitleSupport.storedTitle("\n") == "Untitled Event")
        #expect(CadenceEventTitleSupport.storedTitle("  \n\t ") == "Untitled Event")
        #expect(CadenceEventTitleSupport.storedTitle(" ") != " ")

        #expect(CadenceEventTitleSupport.isBlank(" "))
        #expect(CadenceEventTitleSupport.isBlank("\n"))
        #expect(!CadenceEventTitleSupport.isBlank(" Team sync "))
    }

    /// A real title is stored trimmed, so the value the guard tested is the value that is saved.
    /// iOS previously tested the trimmed string and then assigned the untrimmed one.
    @Test func realEventTitlesAreStoredTrimmedRatherThanAsTyped() {
        #expect(CadenceEventTitleSupport.storedTitle(" Team sync ") == "Team sync")
        #expect(CadenceEventTitleSupport.storedTitle("Team sync\n") == "Team sync")
        #expect(CadenceEventTitleSupport.storedTitle("Team sync") == "Team sync")
    }

    /// One label for an untitled event, at every surface on both platforms. macOS wrote
    /// `"New Event"` on create and drew `"Untitled"`; iOS said `"Untitled Event"`.
    @Test func oneUntitledEventLabelIsUsedForStorageAndDisplay() {
        #expect(CadenceEventTitleSupport.defaultDisplayTitle == "Untitled Event")
        #expect(CadenceEventTitleSupport.displayTitle(nil) == "Untitled Event")
        #expect(CadenceEventTitleSupport.displayTitle("") == "Untitled Event")
        #expect(CadenceEventTitleSupport.displayTitle("   ") == "Untitled Event")
        #expect(CadenceEventTitleSupport.displayTitle(" Standup ") == "Standup")
        #expect(
            CadenceEventTitleSupport.displayTitle(nil)
                == CadenceEventTitleSupport.storedTitle(" ")
        )
    }

    // MARK: - T-332: one trim rule

    /// `"Name\n"` used to survive as `"Name\n"` on macOS and become `"Name"` on iOS.
    @Test func oneTrimRuleCoversNewlinesNotJustSpaces() {
        #expect(CadenceTitleNormalization.normalized("Name\n") == "Name")
        #expect(CadenceTitleNormalization.normalized("\nName ") == "Name")
        #expect(CadenceTitleNormalization.normalized(" Name\r\n") == "Name")
        #expect(CadenceTitleNormalization.isBlank("\n"))
        #expect(CadenceTitleNormalization.isBlank(" \n "))
        #expect(!CadenceTitleNormalization.isBlank("\nName"))

        // The weaker spelling macOS used, kept here as the thing being ruled out.
        #expect("Name\n".trimmingCharacters(in: .whitespaces) == "Name\n")
    }

    /// Task titles are not a parallel implementation of the rule; they are the same rule.
    @Test func taskTitleSupportAndEventTitlesShareTheOneTrimRule() {
        for raw in ["Name\n", " Name ", "\n", "", "  spaced  out  "] {
            #expect(TaskTitleSupport.normalized(raw) == CadenceTitleNormalization.normalized(raw))
            #expect(TaskTitleSupport.isEmpty(raw) == CadenceTitleNormalization.isBlank(raw))
        }

        #expect(TaskTitleSupport.displayTitle("\n") == "Untitled Task")
        #expect(CadenceEventTitleSupport.storedTitle("\n") == "Untitled Event")
    }

    // MARK: - Source scans

    // `Cadence/iOS/` is behind `#if os(iOS)` and is not compiled into this test target, so the
    // "both platforms" half of every ticket above can only be pinned by reading the source.

    private static let macOSCalendarManagerPath = "Cadence/macOS/Services/CalendarManager.swift"
    private static let iOSCalendarManagerPath = "Cadence/iOS/iOSCalendarManager.swift"

    /// Reads a source file and asserts the read was real: non-empty, comment-stripped without
    /// changing length, and actually different from the raw text.
    private func scannedSource(_ relativePath: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(relativePath)
        #expect(raw.count > 500, "\(relativePath) read back too small to be the real file")
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "\(relativePath) has no comments, so the stripper never ran")
        #expect(stripped.count == raw.count)
        return stripped
    }

    @Test func bothCalendarManagersSortCalendarsThroughTheSharedOrder() throws {
        for path in [Self.macOSCalendarManagerPath, Self.iOSCalendarManagerPath] {
            let source = try scannedSource(path)

            // Non-vacuity: this really is a calendar manager.
            #expect(CadenceSourceScan.matchCount(#"store\.calendars\(for: \.event\)"#, in: source) >= 1)

            #expect(
                CadenceSourceScan.matchCount(#"CadenceCalendarSorting\.sorted\("#, in: source) >= 1,
                "\(path) does not sort through CadenceCalendarSorting"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\$0\.title < \$1\.title"#, in: source) == 0,
                "\(path) still spells a raw title comparator"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    #"\$0\.title\.localizedCaseInsensitiveCompare"#,
                    in: source
                ) == 0,
                "\(path) still spells its own calendar comparator"
            )
        }
    }

    @Test func bothCalendarManagersStoreEventTitlesThroughTheSharedNormalizer() throws {
        for path in [Self.macOSCalendarManagerPath, Self.iOSCalendarManagerPath] {
            let source = try scannedSource(path)

            let assignments = CadenceSourceScan.matchCount(#"event\.title = "#, in: source)
            let normalized = CadenceSourceScan.matchCount(
                #"event\.title = CadenceEventTitleSupport\.storedTitle\("#,
                in: source
            )

            #expect(assignments == 2, "\(path) no longer has the two title assignments this pins")
            #expect(
                normalized == assignments,
                "\(path) assigns an event title without the shared normalizer"
            )
        }
    }

    /// The draft popover on the macOS timeline guarded with the same `title.isEmpty`, so fixing
    /// only the manager would have left the whitespace-only title reaching the store from here.
    @Test func noCalendarSurfaceStillSpellsTheNewEventFallback() throws {
        let paths = [
            Self.macOSCalendarManagerPath,
            Self.iOSCalendarManagerPath,
            "Cadence/macOS/Views/TimelineDayCanvas.swift",
            "Cadence/macOS/Views/CalendarEventPresentationSupport.swift",
            "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift",
            "Cadence/iOS/iOSCalendarEventSupport.swift"
        ]

        for path in paths {
            let source = try scannedSource(path)
            #expect(
                CadenceSourceScan.matchCount(#""New Event""#, in: source) == 0,
                "\(path) still spells the retired \"New Event\" fallback"
            )
            #expect(
                CadenceSourceScan.matchCount(#"title \?\? "Untitled""#, in: source) == 0,
                "\(path) still spells its own untitled-event label"
            )
        }

        // The canvas's *bundle* path was the different ticket this named, and it is closed:
        // T-567 routed it through `TaskBundle.storedTitle`, pinned by
        // `TaskBundleTests.noSurfaceStillTypesTheRetiredBundleNoun`. This still pins the event
        // branch by name rather than by a bare `isEmpty` sweep over the file, because the two
        // fallbacks are different copy owned by different types.
        let canvas = try scannedSource("Cadence/macOS/Views/TimelineDayCanvas.swift")
        #expect(
            CadenceSourceScan.matchCount(
                #"onCreateEvent\?\(CadenceEventTitleSupport\.storedTitle\(title\)"#,
                in: canvas
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(#"onCreateEvent\?\(title\.isEmpty"#, in: canvas) == 0
        )
        let iOSEventSupport = try scannedSource("Cadence/iOS/iOSCalendarEventSupport.swift")
        #expect(
            CadenceSourceScan.matchCount(
                #"CadenceEventTitleSupport\.displayTitle\("#,
                in: iOSEventSupport
            ) >= 1
        )
    }

    /// T-569. The iOS calendar drew a task label as `task.title.isEmpty ? "Untitled" : task.title`,
    /// which is the one spelling that cannot see a title of spaces: `"   ".isEmpty` is `false`, so
    /// the chip drew three spaces and read as a **blank line** on the grid, in the month cell and
    /// in the day card. `TaskTitleSupport.displayTitle` trims first, which is why
    /// `iOSCalendarBundleDetailSheet` — the same surface — never had the defect.
    ///
    /// The fallback is passed explicitly as `defaultCompactDisplayTitle`, because these four are
    /// narrow chips: the copy stays the "Untitled" they already drew rather than becoming
    /// `displayTitle`'s default "Untitled Task", so what changed is the trim and nothing else.
    @Test func theIOSCalendarTaskLabelsTrimBeforeTheyFallBack() throws {
        // The behaviour the four call sites now get, and the one they had. Both spellings are
        // here because the whole defect is the difference between them.
        #expect(
            TaskTitleSupport.displayTitle("   ", fallback: TaskTitleSupport.defaultCompactDisplayTitle)
                == TaskTitleSupport.defaultCompactDisplayTitle
        )
        #expect(("   ".isEmpty ? "Untitled" : "   ") == "   ", "the retired spelling drew the spaces")
        #expect(TaskTitleSupport.defaultCompactDisplayTitle == "Untitled", "the copy changed")

        for (path, count) in [
            ("Cadence/iOS/iOSCalendarTimelineViews.swift", 3),
            ("Cadence/iOS/iOSCalendarMonthViews.swift", 1),
        ] {
            let source = try scannedSource(path)
            #expect(
                CadenceSourceScan.matchCount(#"task\.title\.isEmpty \? "Untitled""#, in: source) == 0,
                "\(path) still falls back on an untrimmed title"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    #"TaskTitleSupport\.displayTitle\(task\.title, fallback: TaskTitleSupport\.defaultCompactDisplayTitle\)"#,
                    in: source
                ) == count,
                "\(path) no longer has the \(count) task labels this pins"
            )
        }
    }

    /// T-332's actual call sites. Each of these macOS forms has an iOS sibling that already
    /// trimmed `.whitespacesAndNewlines`; they now share one spelling instead of four.
    @Test func macOSNameFormsTrimThroughTheSharedNormalizer() throws {
        let paths = [
            "Cadence/macOS/Sheets/CreateListSheet.swift",
            "Cadence/macOS/Sheets/EditListSheet.swift",
            "Cadence/macOS/Sheets/CreateContextSheet.swift",
            "Cadence/macOS/Views/SettingsSupportViews.swift",
            "Cadence/macOS/Views/HabitsFormSheets.swift",
            "Cadence/macOS/Views/LinksView.swift"
        ]

        for path in paths {
            let source = try scannedSource(path)
            #expect(
                CadenceSourceScan.matchCount(
                    #"trimmingCharacters\(in: \.whitespaces\)"#,
                    in: source
                ) == 0,
                "\(path) still trims spaces without newlines"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceTitleNormalization\."#, in: source) >= 1,
                "\(path) does not route its name field through the shared normalizer"
            )
        }
    }

    /// `EditListSheet` saved the raw `name`, so it did not merely trim differently from iOS — it
    /// did not trim at all.
    @Test func editListSheetNormalizesTheNameItSavesRatherThanSavingItRaw() throws {
        let source = try scannedSource("Cadence/macOS/Sheets/EditListSheet.swift")

        #expect(CadenceSourceScan.matchCount(#"area\.name = "#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"project\.name = "#, in: source) == 1)
        #expect(
            CadenceSourceScan.matchCount(
                #"area\.name = CadenceTitleNormalization\.normalized\(name\)"#,
                in: source
            ) == 1
        )
        #expect(
            CadenceSourceScan.matchCount(
                #"project\.name = CadenceTitleNormalization\.normalized\(name\)"#,
                in: source
            ) == 1
        )
    }

    // MARK: - T-598(a): one start-time control, one word

    /// **Three sheets on one screen renamed the same control twice.**
    ///
    /// Quick-create said "Starts", the event editor said "Time", the block sheet said "Start" — and
    /// behind all three was byte-for-byte the same thing: a `clock.fill` glyph in `Theme.blue`, a
    /// `CadenceChoiceValueButton` showing `TimeFormatters.timeString(from:)`, and a popover of
    /// `stride(from: 0, to: 1440, by: 15)` rows formatted by that same function.
    ///
    /// `CadenceStartTimeFieldRow` is now the only place any of it is written. **The word is a
    /// `static let` inside the component rather than an argument**, which is the actual fix — a
    /// `label:` parameter is how the app came to have three of them. It is also the only guard
    /// available: `"Start"` is five characters, far under `CadenceSharedConstantReuseSweepTests`'
    /// twelve-character floor, so a shared *constant* spelling it could never have been armed
    /// against a call site re-typing the word.
    @Test func theThreeCalendarSheetsShareOneStartTimeRow() throws {
        // The winning word. "Start" is the noun that matches the "Date" and "Duration" rows beside
        // it; "Starts" was the only verb on the card and "Time" the only label that did not say
        // *which* time next to a Date row setting the other half of the same instant.
        #expect(CadenceStartTimeFieldRow.label == "Start")
        #expect(CadenceStartTimeFieldRow.label != "Starts")
        #expect(CadenceStartTimeFieldRow.label != "Time")

        // The component really does own the control the three sheets handed over.
        let component = try scannedSource("Cadence/Shared/Components/CadenceStartTimeFieldRow.swift")
        #expect(component.contains("stride(from: 0, to: 24 * 60, by: 15)"))
        #expect(component.contains("CadenceChoicePopoverList("))
        #expect(CadenceSourceScan.matchCount(#"TimeFormatters\.timeString\(from:"#, in: component) == 2)
        #expect(
            CadenceSourceScan.matchCount(#"label: *""#, in: component) == 0,
            "the label came back as an argument, which is how there were three of them"
        )

        for (path, binding) in [
            ("Cadence/iOS/iOSCalendarQuickCreateSheet.swift", "startTimeMinutesBinding"),
            ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "startTimeMinutesBinding"),
            ("Cadence/iOS/iOSCalendarBundleDetailSheet.swift", "startMinuteBinding")
        ] {
            let source = try scannedSource(path)

            // Non-vacuity: this is still a sheet with a Schedule card in it.
            #expect(source.contains("iOSEditorSection("), "\(path) is not the sheet this pins")

            #expect(
                source.contains("CadenceStartTimeFieldRow(minutes: \(binding))"),
                "\(path) does not use the shared start-time row"
            )
            for retired in [#"label: "Starts""#, #"label: "Time""#, #"label: "Start""#] {
                #expect(
                    CadenceSourceScan.matchCount(retired, in: source) == 0,
                    "\(path) still spells \(retired)"
                )
            }
            // The popover state each of them carried for this row and nothing else.
            #expect(
                CadenceSourceScan.matchCount("showStartTimePicker", in: source) == 0,
                "\(path) still owns the start-time popover's presentation state"
            )
        }
    }

    // MARK: - T-598(c): one "+N more"

    /// **The Calendar disagreed with the rest of the app about a plus sign, and with itself.**
    ///
    /// Twelve surfaces draw this line and they had split nine to three. All three spaced ones were
    /// calendar — the iOS timeline's unscheduled-task stack, the iOS month cell, and macOS's month
    /// cell — while `iOSCalendarTimelineViews`' *other* overflow line, in the same file, was
    /// unspaced like the other eight. The nine win, and `CadenceTaskSurfaceOptions.moreLabel(hidden:)`
    /// is now where the spelling lives.
    ///
    /// The remaining eight unspaced sites were left typing the literal by this ticket, on the
    /// grounds that they already agreed; T-638 converted them and added the repo-wide sweep,
    /// `CadenceTaskSurfaceOptionsTests.onlyTheSharedHelperSpellsTheOverflowLine`. What *this* still
    /// pins, and the sweep does not, is which calendar file draws the line and how many times —
    /// the split T-598 names, stated by name rather than as an absence.
    @Test func everyCalendarOverflowLineReadsTheSharedMoreLabel() throws {
        #expect(CadenceTaskSurfaceOptions.moreLabel(hidden: 3) == "+3 more")
        // The retired form, written out because the whole defect is the one character between them.
        #expect(CadenceTaskSurfaceOptions.moreLabel(hidden: 3) != "+ 3 more")
        #expect(CadenceTaskSurfaceOptions.moreLabel(hidden: 1) == "+1 more")

        // It is not `overflowCaption`, which is the other answer to the same question and says
        // both numbers because nothing on that surface reveals the rest.
        #expect(CadenceTaskSurfaceOptions.overflowCaption(shown: 24, total: 40) == "Showing 24 of 40")

        for (path, count) in [
            ("Cadence/iOS/iOSCalendarTimelineViews.swift", 2),
            ("Cadence/iOS/iOSCalendarMonthViews.swift", 1),
            ("Cadence/macOS/Views/CalendarPageMonthSupportViews.swift", 1)
        ] {
            let source = try scannedSource(path)
            #expect(
                CadenceSourceScan.matchCount(#""\+ ?\\\([^"]*\) more""#, in: source) == 0,
                "\(path) still spells its own overflow line"
            )
            #expect(
                CadenceSourceScan.matchCount(#"CadenceTaskSurfaceOptions\.moreLabel\(hidden:"#, in: source) == count,
                "\(path) no longer has the \(count) overflow lines this pins"
            )
        }

        // The detector is not blind: it matches both spellings it is meant to and neither of the
        // two nearby lines it must leave alone.
        #expect(CadenceSourceScan.matchCount(#""\+ ?\\\([^"]*\) more""#, in: #"Text("+ \(overflow) more")"#) == 1)
        #expect(CadenceSourceScan.matchCount(#""\+ ?\\\([^"]*\) more""#, in: #"Text("+\(n - 2) more")"#) == 1)
        #expect(CadenceSourceScan.matchCount(#""\+ ?\\\([^"]*\) more""#, in: #"Text("Showing \(n) of \(m)")"#) == 0)
        #expect(
            CadenceSourceScan.matchCount(
                #""\+ ?\\\([^"]*\) more""#,
                in: #"Text(CadenceTaskSurfaceOptions.moreLabel(hidden: overflow))"#
            ) == 0
        )
    }
}
