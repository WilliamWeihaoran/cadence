import Foundation
import SwiftData

/// **The declaration site of `CadenceTaskMutationSupport`, holding only the block constructor and
/// its clamps.** The other fifty-six members live in `CadenceTaskMutationSupport.swift`, which
/// extends this enum rather than declaring it.
///
/// **That inversion is the point of the file, and it is deliberate (T-1122).** The enum's main file
/// reaches `NotificationManager` and `CadenceWidgetRefreshCenter`, and the latter is
/// `#if canImport(WidgetKit)` — two stacks that have no business in `CadenceMCPServer`, a headless
/// command-line tool whose Sources phase compiles whole *files*. A `create_task_bundle` arm needs
/// `insertBundle(title:…)` and the four clamps and nothing else in the enum, so those five members
/// are declared here, on `Foundation`/`SwiftData` alone, and everything they touch — `AppTask`,
/// `TaskBundle` and `CadencePendingChangePersistence` — is already in that target.
///
/// **Why the declaration moved rather than the members being renamed into a second type.** An
/// `extension CadenceTaskMutationSupport` in this file would still require the main file to
/// declare the enum, which is the whole problem; and a differently-named helper type would break
/// the spelling `CadenceTaskMutationSupport.insertBundle(` that three source-text scans pin at
/// their call sites — `CadenceCreateTaskCommitSurfaceTests` against `iOSCalendarQuickCreateSheet`,
/// `CadenceBundleCreationParityTests` against `SchedulingService`, and
/// `CadenceSaveCommitDisciplineTests` against the same file by path. Declaring the enum here and
/// extending it there costs no call site and no pin a single character.
///
/// Do not "tidy" this back into the main file, and do not add members here that reach further than
/// `Foundation`/`SwiftData`: the first one that does silently re-blocks the arm this split exists
/// to unblock.
enum CadenceTaskMutationSupport {
    /// The day a bundle has to fit inside, and the shortest slot it may occupy.
    ///
    /// macOS spells the same two numbers as `TimelineDayRange` in `macOS/Views/TimelineMetrics.swift`,
    /// which this file cannot see — `Shared/` does not compile the timeline. They are deliberately
    /// identical, and `bundleClampsMatchTheTimelineDayRange` in `TaskBundleTests` fails if one side
    /// moves. Do not re-spell either literal at a call site; that is how the timeline clamp came to
    /// exist four times with three different bounds.
    static let bundleDayEndMin = 24 * 60
    static let bundleMinimumDuration = 5

    /// Clamps a start minute so a minimum-length block still ends inside the day.
    static func clampedBundleStart(_ startMin: Int) -> Int {
        min(max(0, startMin), bundleDayEndMin - bundleMinimumDuration)
    }

    /// Minutes a bundle starting at `startMin` needs in order to hold `tasks`, clamped inside the day.
    ///
    /// Every member contributes at least `bundleMinimumDuration`, so two estimate-less tasks still
    /// get a block tall enough to see and hit rather than a zero-height sliver.
    static func bundleDuration(startingAt startMin: Int, tasks: [AppTask]) -> Int {
        let total = tasks.reduce(0) { partial, task in
            partial + max(task.estimatedMinutes, bundleMinimumDuration)
        }
        return max(bundleMinimumDuration, min(total, bundleDayEndMin - clampedBundleStart(startMin)))
    }

    /// Mints an empty block from four explicit fields — the drag-out-a-range gesture's constructor,
    /// and the only member of the `insertBundle` family that takes no `commit:`.
    @discardableResult
    static func insertBundle(
        title: String,
        dateKey: String,
        startMin: Int,
        durationMinutes: Int,
        modelContext: ModelContext
    ) throws -> TaskBundle {
        let clampedStart = clampedBundleStart(startMin)
        let duration = min(max(bundleMinimumDuration, durationMinutes), bundleDayEndMin - clampedStart)
        let bundle = TaskBundle(
            title: TaskBundle.storedTitle(title),
            dateKey: dateKey,
            startMin: clampedStart,
            durationMinutes: duration
        )

        modelContext.insert(bundle)
        // See `duplicate(_:allTasks:modelContext:)` (T-1299): the same three lines, said once.
        try CadencePendingChangePersistence.commitInsert(of: bundle, in: modelContext)
        return bundle
    }
}
