import Foundation
import SwiftData

/// **The declaration site of `CadenceTaskMutationSupport`, holding the block clamps and the
/// bundle-membership rule.** (The empty-slot block constructor, `insertBundle(title:…)`, was here
/// until [[T-3170]] removed the last surface that created a block from an empty slot, so the
/// member counts below are one high.) The enum's other sixty-two members live in
/// `CadenceTaskMutationSupport.swift`, which extends this enum rather than declaring it —
/// fifty-six `internal` and six `private`.
/// (T-1122's entry counted this enum at "61 static members" when five were here; it is **62**
/// now, because `assignTask(_:to:)` came across and stopped being `private` in the process.
/// Count the `internal` ones only — 49 `static func` + 12 `static let` + 1 `static var`, of which
/// six are here — or the next re-measure will disagree with the ledger for no reason. A naive
/// `static` grep returns 68: the six surviving `private` members are the discrepancy.)
///
/// **That inversion is the point of the file, and it is deliberate (T-1122).** The enum's main file
/// reaches `NotificationManager` and `CadenceWidgetRefreshCenter`, and the latter is
/// `#if canImport(WidgetKit)` — two stacks that have no business in `CadenceMCPServer`, a headless
/// command-line tool whose Sources phase compiles whole *files*. `create_task_bundle` needed
/// the empty-slot constructor and the four clamps; `add_task_to_bundle` needed `assignTask(_:to:)`
/// and the snapshot that undoes it, and nothing else in the enum (both tools went with
/// [[T-3170]]). So those members are declared here,
/// on `Foundation`/`SwiftData` alone, and everything they touch — `AppTask`, `TaskBundle` and
/// `CadencePendingChangePersistence` — is already in that target.
///
/// **Why the declaration moved rather than the members being renamed into a second type.** An
/// `extension CadenceTaskMutationSupport` in this file would still require the main file to
/// declare the enum, which is the whole problem; and a differently-named helper type would break
/// the spelling `CadenceTaskMutationSupport.insertBundle(` that source-text scans pin at their
/// call sites — `CadenceBundleCreationParityTests` against `SchedulingService`, and
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


    // `assignTask(_:to:)` and `BundleMembership` were declared here -- the five-field membership
    // write and the snapshot that undid it. [[T-3170]] removed every caller: the two timelines'
    // drop-to-form-a-block gesture, the iOS Calendar Board's drag-onto-a-block, and finally
    // `insertBundle`/`addTask` themselves in the trio pass.
    //
    // **The four clamps above STAY, and not by oversight.** Nothing builds a block any more, so on
    // reachability alone they would go with the rest. They are kept because
    // `CadenceTaskBundleRetirementTests.theClampsMatchTheOnesThatSizedTheBlocks` asserts
    // `TaskBundleRetirement`'s own `minimumSlotMinutes`, `dayEndMin` and `clampedStart` against
    // them -- the migration re-spells this arithmetic because it has to be reachable from the
    // `nonisolated` archive import, and that test is the only thing keeping the two spellings
    // honest. Deleting these would silently retire that cross-check on the one piece of Block code
    // this ticket is deliberately keeping. They go when the migration does.
}
