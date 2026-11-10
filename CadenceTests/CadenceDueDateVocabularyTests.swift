import Foundation
import Testing
@testable import Cadence

/// **[[T-15491]]: one task, one due-date wording, on every surface.**
///
/// There were two vocabularies. `CadenceWidgetDateSupport.dueLabel` ("Overdue Nov 9" / "Due today" /
/// "Due tomorrow" / "Due Nov 14") fed the timeline blocks, widgets and note reference chips;
/// `DateFormatters.relativeDate` ("Yesterday" / "Today", or "Due Yesterday" / "Due Today" with a
/// prefix) fed the task rows, the Focus header, Cmd+K, iOS search, the `[[` picker, the iOS embed
/// chips and the board cards. A task due yesterday read "Yesterday" on its Mac row and "Overdue
/// Nov 9" on its own timeline block beside it. Keeper's call (T-15500): the `dueLabel` words win.
///
/// The pin: the same overdue, today and tomorrow keys go to every builder a surface reads, and
/// every one must return `dueLabel`'s string for them.
@MainActor
struct CadenceDueDateVocabularyTests {
    private static let today = "2026-11-10"
    private static let cases: [(key: String, expected: String)] = [
        ("2026-11-09", "Overdue Nov 9"),
        ("2026-11-10", "Due today"),
        ("2026-11-11", "Due tomorrow"),
    ]

    private func task(dueDate: String) -> AppTask {
        let task = AppTask(title: "T")
        task.dueDate = dueDate
        return task
    }

    private func embedInfo(dueDate: String) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(), title: "T", statusRaw: TaskStatus.todo.rawValue, priorityRaw: TaskPriority.none.rawValue,
            sectionName: "", containerName: "", containerColorHex: "", dueDate: dueDate, scheduledDate: "",
            scheduledStartMin: -1, estimatedMinutes: 0, actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue, isDone: false, isCancelled: false, isMissing: false,
            subtasks: []
        )
    }

    /// The reference itself, so a change to its words is a change to this test's expectation and
    /// not a silent re-pin of every surface below.
    @Test func theOneBuilderSaysOverdueTodayAndTomorrowThisWay() {
        for (key, expected) in Self.cases {
            #expect(CadenceWidgetDateSupport.dueLabel(for: key, todayKey: Self.today) == expected)
        }
    }

    @Test func everySurfaceBuilderSaysTheSameWords() throws {
        let reference = try #require(DateFormatters.date(from: Self.today))
        for (key, expected) in Self.cases {
            let task = task(dueDate: key)

            // Mac and iOS task-row due chips, iOS search, the iOS `[[` picker.
            #expect(CadenceTaskPresentationSupport.dueDateLabel(for: task, todayKey: Self.today) == expected, "row chip, \(key)")
            // Focus: the session header on both platforms, and the pick rows.
            #expect(CadenceFocusSupport.sessionHeaderDueLabel(forDueDateKey: key, todayKey: Self.today) == expected, "Focus header, \(key)")
            #expect(CadenceFocusSupport.dueLabel(forDueDateKey: key, todayKey: Self.today) == expected, "Focus dueLabel, \(key)")
            // Timeline blocks on Mac and iOS.
            #expect(
                CadenceTimelineTaskBlockDetails.resolve(task: task, durationMinutes: 30, todayKey: Self.today).dueLabel == expected,
                "timeline block, \(key)"
            )
            // Board cards.
            #expect(CadenceBoardCardMetadata.dueDateChip(for: task, todayKey: Self.today)?.text == expected, "board card, \(key)")
            // iOS task-embed chips.
            let embedDue = CadenceTaskEmbedChipRow.slots(for: embedInfo(dueDate: key), relativeTo: reference)
                .first { $0.field == .dueDate }?.title
            #expect(embedDue == expected, "embed chip, \(key)")
            #if os(macOS)
            // Cmd+K's task subtitle carries the words as one of its parts, unprefixed.
            let subtitle = GlobalSearchIndexSupport.taskResult(for: task, todayKey: Self.today).subtitle
            #expect(subtitle.components(separatedBy: " • ").contains(expected), "Cmd+K, \(key): \(subtitle)")
            #endif
        }
    }

    /// No due date is no label, on the builder the rows read — never a stand-in string.
    @Test func noDueDateIsNoLabel() {
        #expect(CadenceTaskPresentationSupport.dueDateLabel(for: task(dueDate: ""), todayKey: Self.today) == nil)
    }

    /// The iOS row, search and `[[` picker are behind `#if os(iOS)` or in iOS-only files, so their
    /// wiring is read as source: each reads the shared builder and none prefixes its own "Due ".
    @Test func theIOSSurfacesReadTheBuilderAndAddNoPrefix() throws {
        let files: [(path: String, needle: String)] = [
            ("Cadence/iOS/iOSTaskViews.swift", "CadenceTaskPresentationSupport.dueDateLabel(for: task, todayKey: todayKey)"),
            ("Cadence/iOS/iOSSearchView.swift", "CadenceTaskPresentationSupport.dueDateLabel(for: task)"),
            ("Cadence/iOS/iOSMarkdownAccessoryViews.swift", "CadenceTaskPresentationSupport.dueDateLabel(for: task)"),
        ]
        for (path, needle) in files {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains(needle), "\(path) no longer reads the one due-date builder")
            #expect(!source.contains("\"Due \\(CadenceTaskPresentationSupport.dueDateLabel"), "\(path) prefixes its own Due")
        }
    }

    /// The other half of the old split: no surface listed in the ticket builds "Due " +
    /// `DateFormatters.relativeDate` for a task's due date again.
    @Test func noListedSurfaceSpellsDueWithRelativeDate() throws {
        let paths = [
            "Cadence/Shared/CadenceFocusPlanningSupport.swift",
            "Cadence/macOS/Views/GlobalSearchIndexSupport.swift",
            "Cadence/Shared/CadenceTaskEmbedTouchChips.swift",
            "Cadence/Shared/CadenceTaskPresentationSupport.swift",
            "Cadence/Shared/CadenceBoardCardMetadata.swift",
            "Cadence/macOS/Views/TasksPanelComponents.swift",
        ]
        for path in paths {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(!source.contains("relativeDate(from: task.dueDate"), "\(path) words a due date with relativeDate again")
            #expect(!source.contains("\"Due \\(DateFormatters.relativeDate"), "\(path) prefixes Due to relativeDate again")
            #expect(!source.contains("relativeDate(from: key, relativeTo: referenceDate))\""), "\(path) spells the Focus header the old way")
        }
    }

    /// **[[T-15502]]:** the list/project sidebar badges, the Apple Reminders row badge and the
    /// board column's due line speak the same vocabulary, so none of their files may word a date
    /// with `DateFormatters.relativeDate` ("Yesterday" / "Today") any more.
    @Test func listReminderAndColumnBadgesNoLongerSpellRelativeDate() throws {
        let files = [
            "Cadence/macOS/Views/SidebarSupportViews.swift": "CadenceSidebarLayout.listDueDateLabel(",
            "Cadence/iOS/iOSRootSidebar.swift": "CadenceSidebarLayout.listDueDateLabel(",
            "Cadence/Shared/CadenceSidebarLayout.swift": "CadenceWidgetDateSupport.dueLabel(",
            "Cadence/Shared/CadenceRemindersPresentationSupport.swift": "CadenceWidgetDateSupport.dueLabel(",
            "Cadence/Shared/Components/CadenceBoardColumnHeader.swift": "CadenceWidgetDateSupport.dueLabel(",
        ]
        for (path, needle) in files {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains(needle), "\(path) no longer reads the one due-date builder")
            #expect(!source.contains("relativeDate("), "\(path) words a due badge with relativeDate again")
        }
    }
}

/// **[[T-15494]]: Settings' "Last checked" stamp and four `Date.formatted` sites.**
///
/// The stamp now reads like the "Last import" / "Last export" row beside it, and every visible
/// stamp is built from the pinned `DateFormatters` / `TimeFormatters` pieces, so none follows the
/// host region's date order or picks up `Date.FormatStyle`'s narrow no-break space.
@MainActor
struct CadencePinnedDateTimeStampTests {
    private static let enUS = Locale(identifier: "en_US")
    private static let enGB = Locale(identifier: "en_GB")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    @Test func lastCheckedReadsLikeTheActivityRow() throws {
        let now = try date(2026, 11, 10, 18, 0)
        let earlierToday = try date(2026, 11, 10, 9, 41)
        let yesterday = try date(2026, 11, 9, 16, 2)
        let fourDaysAgo = try date(2026, 11, 6, 9, 0)
        #expect(CadenceSyncActivityStamp.lastCheckedLine(for: earlierToday, now: now, locale: Self.enUS) == "Last checked 9:41 AM")
        #expect(CadenceSyncActivityStamp.lastCheckedLine(for: yesterday, now: now, locale: Self.enUS) == "Last checked yesterday 4:02 PM")
        #expect(CadenceSyncActivityStamp.lastCheckedLine(for: fourDaysAgo, now: now, locale: Self.enUS) == "Last checked 4 days ago")
        // The same words as the activity row's stamp, by construction rather than by coincidence.
        #expect(
            CadenceSyncActivityStamp.lastCheckedLine(for: yesterday, now: now, locale: Self.enUS)
                == "Last checked \(CadenceSyncActivityStamp.string(for: yesterday, now: now, locale: Self.enUS))"
        )
    }

    @Test func aDateTimeStampIsPinnedEnglishWithThePinnedClock() throws {
        let instant = try date(2026, 11, 10, 9, 41)
        #expect(DateFormatters.dateTimeStamp(instant, locale: Self.enUS) == "Nov 10, 2026 at 9:41 AM")
        // A 24-hour region keeps the English month-day order and gets the app's one 24-hour face.
        #expect(DateFormatters.dateTimeStamp(instant, locale: Self.enGB) == "Nov 10, 2026 at 09:41")
        #expect(!DateFormatters.dateTimeStamp(instant, locale: Self.enUS).contains("\u{202F}"), "Date.FormatStyle's narrow no-break space is back")
    }

    @Test func theEventNotesConflictLabelUsesTheStamp() throws {
        let instant = try date(2026, 11, 10, 9, 41)
        #expect(CadenceEventNotesMerge.conflictDateText(instant) == DateFormatters.dateTimeStamp(instant))
    }

    /// The four sites and both Settings stamps: no `Date.formatted(date:time:)` left in them.
    @Test func noListedSiteFormatsThroughTheHostRegion() throws {
        let paths = [
            "Cadence/macOS/Views/SettingsSyncSection.swift",
            "Cadence/iOS/iOSSettingsOverviewSections.swift",
            "Cadence/Shared/CadenceStoreBackupPresentation.swift",
            "Cadence/Shared/CadenceEventNotesMerge.swift",
            "Cadence/Services/PersistenceController.swift",
        ]
        for path in paths {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(!source.contains(".formatted(date:"), "\(path) formats a date through the host region again")
        }
        for path in paths.prefix(2) {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains("CadenceSyncActivityStamp.lastCheckedLine(for: lastChecked"), "\(path) spells its own Last checked")
        }
        let backup = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceStoreBackupPresentation.swift"))
        #expect(backup.contains("DateFormatters.dateTimeStamp(backup.createdAt)"))
    }
}
