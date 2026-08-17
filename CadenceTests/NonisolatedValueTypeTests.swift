import Foundation
import Testing
@testable import Cadence

/// **This suite is deliberately not `@MainActor`, and that is the whole point of it.**
///
/// The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a value type declared
/// without an explicit `nonisolated` gets a main-actor-isolated *synthesized* `Equatable`. Every
/// `#expect(a == b)` below runs inside the nonisolated closure swift-testing's macro expands to,
/// so if any of these types loses its `nonisolated` the comparison re-emits
///
///     main actor-isolated conformance of 'X' to 'Equatable' cannot be used in nonisolated
///     context; this is an error in the Swift 6 language mode
///
/// — which is exactly the diagnostic that reached 107 sites before `Models/`, `Services/` and
/// `Shared/` were marked. Marking this suite `@MainActor` would silence it again, so don't.
///
/// It is not only about warnings. `Models/`, `DateFormatters.swift` and the `Cadence*WidgetSupport`
/// files compile straight into `CadenceWidgets`, whose timeline providers run **off** the main
/// actor, and into `CadenceMCPServer`, which is already `SWIFT_VERSION = 6.0`. A main-actor-isolated
/// value type reached from a timeline provider is a real hazard, not a style point — the same
/// reason `TaskOrdering` and `CadenceTaskRowMetrics` were made `nonisolated` before this sweep.
///
/// The assertions themselves are ordinary behaviour checks; they are chosen for coverage of the
/// *isolation* surface, one type per family, rather than to re-test what the family's own suite
/// already covers.
struct NonisolatedValueTypeTests {
    // MARK: - Models (compiled into CadenceWidgets and CadenceMCPServer)

    @Test func modelEnumsCompareFromANonisolatedContext() {
        #expect(TaskPriority.high != TaskPriority.low)
        #expect(TaskPriority(rawValue: "high") == .high)
        #expect(TaskStatus.done != .todo)
        #expect(TaskRecurrenceRule.weekly != .none)
        #expect(TaskRecurrenceEndMode.afterCount != .never)
        #expect(GoalKind.ongoing != .completable)
        #expect(GoalProgressType.hours != .subtasks)
        #expect(HabitFrequency.daysOfWeek != .daily)
        #expect(NoteKind.meeting != .daily)
        #expect(AreaStatus.archived != .active)
        #expect(ProjectStatus.paused != .active)
        #expect(GoalStatus.done != .active)
    }

    /// The type named in the task list: it lives in `Models/Habit.swift`, which the widget target
    /// compiles, and a habit widget renders a streak from a timeline provider.
    @Test func habitStreakUnitComparesFromANonisolatedContext() {
        #expect(HabitStreakUnit.days != HabitStreakUnit.weeks)
        #expect(HabitStreakUnit.days.shortLabel(8) == "8d")
        #expect(HabitStreakUnit.weeks.shortLabel(8) == "8w")
    }

    @Test func taskSectionConfigComparesFromANonisolatedContext() {
        let id = UUID()
        let left = TaskSectionConfig(uuid: id, name: "Default")
        let right = TaskSectionConfig(uuid: id, name: "Default")
        #expect(left == right)
        #expect(left.isDefault)
        #expect(TaskSectionConfig(uuid: id, name: "Backlog") != left)
    }

    /// `TaskOrdering` was `nonisolated` before this sweep; the vocabulary beside it is the part
    /// that gets compared.
    @Test func sortVocabularyComparesFromANonisolatedContext() {
        #expect(TaskSortField.priority != .date)
        #expect(TaskSortDirection.ascending != .descending)
        #expect(TaskOrdering.dateSortKey("") == TaskOrdering.noDateSortKey)
        #expect(TaskOrdering.dateSortKey("2026-08-18") == "2026-08-18")
    }

    // MARK: - Date and time vocabulary (also compiled into both extension targets)

    @Test func dateKeysResolveFromANonisolatedContext() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(DateFormatters.date(from: "2026-08-18", in: calendar))
        #expect(DateFormatters.dateKey(from: date, calendar: calendar) == "2026-08-18")
        #expect(DateFormatters.date(from: "not-a-date", in: calendar) == nil)
        #expect(TimeFormatters.timeString(from: 75) == "1:15 AM")
        #expect(TimeFormatters.durationLabel(minutes: 0, emptyPlaceholder: "-") == "-")
    }

    // MARK: - Markdown support (the largest share of the 107 sites)

    @Test func markdownPreviewBlocksCompareFromANonisolatedContext() {
        #expect(MarkdownPreviewParser.blocks(in: "# Title") == [.heading(level: 1, text: "Title")])
        #expect(MarkdownPreviewParser.blocks(in: "---") == [.divider])
        #expect(MarkdownPreviewBlock.paragraph("a") != MarkdownPreviewBlock.paragraph("b"))
    }

    @Test func markdownInlineAndListValuesCompareFromANonisolatedContext() throws {
        #expect(MarkdownInlineSpanKind.bold != MarkdownInlineSpanKind.italic)
        #expect(MarkdownChecklistSyntax.github != MarkdownChecklistSyntax.legacy)
        let info = try #require(MarkdownChecklistSupport.lineInfo(in: "- [x] ship it"))
        #expect(info.syntax == .github)
        #expect(info.isDone)
        #expect(info.content == "ship it")
        #expect(MarkdownRenderedBlockKind.image != MarkdownRenderedBlockKind.task)
        #expect(MarkdownTableAlignment.leading != MarkdownTableAlignment.trailing)
    }

    // MARK: - Notification planning (pure, and reconciled from a `scenePhase` checkpoint)

    @Test func notificationRequestsCompareFromANonisolatedContext() {
        let fireDate = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let left = CadenceNotificationRequest(
            identifier: NotificationIdentifiers.taskStart(taskID: id),
            kind: .taskStart,
            title: "Ship it",
            body: "9:00 AM",
            fireDate: fireDate
        )
        let right = CadenceNotificationRequest(
            identifier: NotificationIdentifiers.taskStart(taskID: id),
            kind: .taskStart,
            title: "Ship it",
            body: "9:00 AM",
            fireDate: fireDate
        )
        #expect(left == right)
        #expect(left.kind != .habitReminder)
        #expect(left.triggerSpec().repeats == false)
    }

    // MARK: - Shared navigation and layout vocabulary

    @Test func shellVocabularyComparesFromANonisolatedContext() throws {
        #expect(CadenceCompactTab.resolved("nonsense") == .tasks)
        #expect(CadenceTasksSection.resolved("inbox") == .inbox)
        #expect(CadenceFeatureDestination.today != .allTasks)
        let todayURL = try #require(URL(string: "cadence://today"))
        #expect(CadenceDeepLink(url: todayURL) == .today)
        #expect(CadenceTodayLayout.compact != .twoPane)
        #expect(CadenceSwipeRelease.closed != .open(.leading))
        #expect(CadenceTaskRecurrenceEditScope.thisTask != .thisAndFuture)
    }

    // MARK: - Off the main actor for real

    /// The narrower claim the rest of the suite only implies: these values can be built and
    /// compared on a thread that is not the main one, which is the situation a widget timeline
    /// provider is actually in.
    @Test func widgetShapedValuesSurviveADetachedTask() async {
        let result = await Task.detached { () -> Bool in
            let calendar = Calendar(identifier: .gregorian)
            let todayKey = DateFormatters.dateKey(from: Date(), calendar: calendar)
            return HabitStreakUnit.days == .days
                && TaskPriority.high.rank > TaskPriority.low.rank
                && !todayKey.isEmpty
                && TaskOrdering.dateSortKey("") == TaskOrdering.noDateSortKey
        }.value
        #expect(result)
    }
}
