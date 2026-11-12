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

    private func embedInfo(dueDate: String, isDone: Bool = false) -> MarkdownTaskEmbedRenderInfo {
        MarkdownTaskEmbedRenderInfo(
            id: UUID(), title: "T", statusRaw: TaskStatus.todo.rawValue, priorityRaw: TaskPriority.none.rawValue,
            sectionName: "", containerName: "", containerColorHex: "", dueDate: dueDate, scheduledDate: "",
            scheduledStartMin: -1, estimatedMinutes: 0, actualMinutes: 0,
            recurrenceRaw: TaskRecurrenceRule.none.rawValue, isDone: isDone, isCancelled: false, isMissing: false,
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
            // Cmd+K's task row carries the words in its own due field ([[T-16471]]).
            let row = GlobalSearchIndexSupport.taskResult(for: task, todayKey: Self.today)
            #expect(row.dueLabel == expected, "Cmd+K, \(key): \(String(describing: row.dueLabel))")
            #endif
        }
    }

    #if os(macOS)
    /// **[[T-16471]]: Cmd+K draws an overdue task's due date in its capsule.** The row used to find
    /// the due words by splitting the subtitle on " • " and keeping the last part that began
    /// "Due ", and [[T-15491]]'s overdue wording begins "Overdue": an overdue task's date was left
    /// in the dim metadata line, after the list and the tags, where a long name truncated it away.
    /// The due words now travel as their own field, as iOS Search's `dueLabel` does, and appear
    /// nowhere in the subtitle -- so every wording, overdue included, reaches the capsule.
    @Test func cmdKCarriesEveryDueWordingOutsideTheSubtitle() {
        for (key, expected) in Self.cases {
            let task = task(dueDate: key)
            let row = GlobalSearchIndexSupport.taskResult(for: task, todayKey: Self.today)
            #expect(row.dueLabel == expected, "\(key)")
            #expect(!row.subtitle.contains(expected), "\(key): the subtitle repeats the due words: \(row.subtitle)")
        }
        let overdue = GlobalSearchIndexSupport.taskResult(for: task(dueDate: "2026-11-09"), todayKey: Self.today)
        #expect(overdue.dueLabel?.hasPrefix("Overdue ") == true, "non-vacuity: the overdue case is the one a prefix split missed")

        let undated = GlobalSearchIndexSupport.taskResult(for: task(dueDate: ""), todayKey: Self.today)
        #expect(undated.dueLabel == nil)
    }
    #endif

    /// **[[T-15522]]:** a settled item whose date has passed says "Due Nov 9" -- the date, with no
    /// lateness claim -- because every surface's overdue predicate already calls it not late and
    /// tints it neutral. Today, tomorrow and later read the same settled or not, and an open item's
    /// past date still says "Overdue".
    @Test func aSettledItemsPastDateMakesNoLatenessClaim() {
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-11-09", todayKey: Self.today, isSettled: true) == "Due Nov 9")
        #expect(CadenceWidgetDateSupport.dueLabel(for: "2026-11-09", todayKey: Self.today) == "Overdue Nov 9")
        for (key, expected) in Self.cases where key >= Self.today {
            #expect(CadenceWidgetDateSupport.dueLabel(for: key, todayKey: Self.today, isSettled: true) == expected, "\(key)")
        }
        #expect(CadenceWidgetDateSupport.dueLabel(for: "", todayKey: Self.today, isSettled: true) == nil)
    }

    /// Every builder that reads a settled item hands it in: the done task's row chip, board card,
    /// timeline block, Focus label and embed chip, and the completed board column. Each pairs the
    /// words with its own overdue predicate, so the two cannot disagree again.
    @Test func everySettledSurfaceSaysDueNotOverdue() throws {
        let reference = try #require(DateFormatters.date(from: Self.today))
        let past = "2026-11-09"
        let done = task(dueDate: past)
        done.status = .done
        let open = task(dueDate: past)

        #expect(!done.isOverdue(todayKey: Self.today), "non-vacuity: a done task is not overdue")
        #expect(CadenceTaskPresentationSupport.dueDateLabel(for: done, todayKey: Self.today) == "Due Nov 9", "row chip")
        #expect(CadenceTaskPresentationSupport.dueDateLabel(for: open, todayKey: Self.today) == "Overdue Nov 9", "open row chip")
        let card = try #require(CadenceBoardCardMetadata.dueDateChip(for: done, todayKey: Self.today))
        #expect(card.text == "Due Nov 9" && card.emphasis == .neutral, "board card")
        #expect(CadenceBoardCardMetadata.dueDateChip(for: open, todayKey: Self.today)?.text == "Overdue Nov 9", "open board card")
        let block = CadenceTimelineTaskBlockDetails.resolve(task: done, durationMinutes: 30, todayKey: Self.today)
        #expect(block.dueLabel == "Due Nov 9" && !block.dueIsUrgent, "timeline block")
        #expect(CadenceFocusSupport.dueLabel(forDueDateKey: past, todayKey: Self.today, isSettled: true) == "Due Nov 9", "Focus")
        let embedDue = CadenceTaskEmbedChipRow.slots(for: embedInfo(dueDate: past, isDone: true), relativeTo: reference)
            .first { $0.field == .dueDate }?.title
        #expect(embedDue == "Due Nov 9", "embed chip")

        let completed = CadenceBoardColumnDueDatePlan.plan(
            dueDate: past, hideWhenEmpty: false, isCompleted: true, relativeTo: reference
        )
        #expect(completed.label == "Due Nov 9" && !completed.isOverdue, "completed column")
        let running = CadenceBoardColumnDueDatePlan.plan(
            dueDate: past, hideWhenEmpty: false, isCompleted: false, relativeTo: reference
        )
        #expect(running.label == "Overdue Nov 9" && running.isOverdue, "open column")
    }

    /// The three note-reference surfaces are a SwiftUI body each, so their wiring is read as source:
    /// each hands the task's `isDone` to the label it pairs with `isOverdue`.
    @Test func theNoteReferenceSurfacesHandInTheSettledState() throws {
        let needle = "CadenceFocusSupport.dueLabel(forDueDateKey: task.dueDate, todayKey: todayKey, isSettled: task.isDone)"
        for path in [
            "Cadence/Shared/CadenceNoteFolderSupport.swift",
            "Cadence/macOS/Views/NoteReferenceSupportViews.swift",
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift",
        ] {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(source.contains(needle), "\(path) words a done task's due date without its settled state")
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

    /// **[[T-16891]]: a cancelled task's past dates fly no late flag on its row or card.** It sits
    /// in Completed, struck through under the "Canceled" chip; the due chip said "Overdue Nov 9"
    /// in red there, and the do pill went red too, on the Mac row, the iOS row and both boards.
    /// Settled is `isFinishedTask` -- done OR cancelled -- for the words, the due flag's tint, the
    /// do pill's emphasis and the Mac row's own flag. An open task is unchanged, and the store-level
    /// `AppTask.isOverdue` still answers yes for the cancelled task (pinned in
    /// `TaskOverdueSupportTests`), which is the non-vacuity check: the row rule is what changed.
    @Test func aCancelledTasksPastDatesFlyNoLateFlagOnItsRowOrCard() throws {
        let past = "2026-11-09"
        let cancelled = task(dueDate: past)
        cancelled.scheduledDate = past
        cancelled.status = .cancelled
        let open = task(dueDate: past)
        open.scheduledDate = past

        #expect(cancelled.isOverdue(todayKey: Self.today), "non-vacuity: the store predicate still calls it overdue")
        #expect(CadenceTaskPresentationSupport.dueDateLabel(for: cancelled, todayKey: Self.today) == "Due Nov 9", "cancelled row chip words")
        #expect(!CadenceTaskPresentationSupport.dueDateIsLate(cancelled, todayKey: Self.today), "cancelled row flag tint")
        #if os(macOS)
        #expect(!KanbanCardComputedSupport.isOverdue(task: cancelled, todayKey: Self.today), "Mac row flag")
        #endif
        let card = try #require(CadenceBoardCardMetadata.dueDateChip(for: cancelled, todayKey: Self.today))
        #expect(card.text == "Due Nov 9" && card.emphasis == .neutral, "cancelled board card due chip")
        #expect(CadenceBoardCardMetadata.doDateEmphasis(for: cancelled, todayKey: Self.today) == .neutral, "cancelled do pill")

        #expect(CadenceTaskPresentationSupport.dueDateLabel(for: open, todayKey: Self.today) == "Overdue Nov 9", "open row chip words")
        #expect(CadenceTaskPresentationSupport.dueDateIsLate(open, todayKey: Self.today), "open row flag tint")
        #if os(macOS)
        #expect(KanbanCardComputedSupport.isOverdue(task: open, todayKey: Self.today), "open Mac row flag")
        #endif
        #expect(CadenceBoardCardMetadata.dueDateChip(for: open, todayKey: Self.today)?.emphasis == .urgent, "open board card")
        #expect(CadenceBoardCardMetadata.doDateEmphasis(for: open, todayKey: Self.today) == .urgent, "open do pill")
    }

    /// The iOS row's due tint is behind `#if os(iOS)`, so its wiring is read as code: it hands
    /// `CadenceDueUrgency` the finished predicate, not `task.isDone` ([[T-16891]]).
    @Test func theIOSRowTintsACancelledDeadlineAsSettled() throws {
        let row = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/iOS/iOSTaskViews.swift"))
        #expect(row.contains("CadenceDueUrgency.evaluate("), "non-vacuity: the iOS row reads the urgency classifier")
        #expect(row.contains("isDone: CadenceTaskQuerySupport.isFinishedTask(task),"), "the iOS row tints a cancelled deadline as late")
        #expect(!row.contains("isDone: task.isDone, todayKey: todayKey)"), "the iOS row went back to the done-only guard")
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
