import Foundation
import SwiftData

/// **The one-time pass that takes the Block feature out of the store without taking the user's
/// scheduling intent with it ([[T-3170]]).**
///
/// The owner asked for blocks to go ("the whole concept of bundle feels a bit unnecessary and adds
/// confusion"). The hazard in doing that is not the `TaskBundle` rows; it is the **members**.
/// `SchedulingActions.addTask` and `CadenceTaskMutationSupport.assignTask` both write
/// `task.scheduledStartMin = -1` when a task joins a block, because the block carries the slot and
/// the member deliberately does not. `-1` is this app's unscheduled sentinel. So removing blocks
/// and leaving the members alone would put every one of them on its date with **no time at all**,
/// which is the state the timeline's layout filters out — the user's blocked work would simply
/// stop being drawn, silently, with nothing to undo it from. Pushing the schedule down onto the
/// members first is therefore the first half of the removal, not a tidy-up after it.
///
/// **What "nothing moved" can and cannot mean.** The block itself disappears — that is the
/// request — so a literal pixel-for-pixel invariant is not available. What this pass does promise,
/// and what `CadenceTaskBundleRetirementTests` asserts, is:
///
/// - every member ends with a **real** `scheduledStartMin`, never `-1`;
/// - every member starts **inside the span the block occupied**, on the block's own day;
/// - members keep their `bundleOrder` sequence, so the column reads top-to-bottom as the block's
///   task list did;
/// - no member's `estimatedMinutes` is rewritten, because an estimate is user data that Focus,
///   planning totals and an hours-mode `Goal` all read — a migration may move a task's start, it
///   may not invent how long the user thinks the task takes.
///
/// **The two layouts, and why the second one exists.** A block's duration is independent of its
/// members' estimates: a 30-minute block can hold six half-hour tasks, because the block is a
/// container the user sized by dragging, not a sum.
///
/// - *It fits* (the members' natural lengths sum to no more than the block's duration): each
///   member starts where the previous one ended, from `bundle.startMin`. This is the case that
///   really does leave the day looking the way it looked, minus whatever tail of the block was
///   empty.
/// - *It does not fit*: the block's span is divided into as many equal slices as there are
///   members and each member starts at its slice. The members then **overlap**, which the timeline
///   already draws — `CadenceCalendarOverlapLayout` is the solver for exactly this — and which is
///   the honest rendering of a block that was always overcommitted. The alternative, spilling the
///   tail past the block's end, would move work onto a part of the day the user never gave it, and
///   that is a worse lie than an overlap. Where there are more members than minutes the integer
///   slices collapse and some members share a start minute; in that case their relative order is
///   the overlap solver's tie-break rather than `bundleOrder`, which is the one ordering promise
///   this pass cannot keep and does not make.
///
/// **A block with no members** has no schedule to push down, so it is simply deleted; there is
/// nothing to preserve and nothing that can be lost.
///
/// **The entity stays.** This pass deletes block *rows*; `TaskBundle` remains a `@Model` and a
/// member of `CadenceSchema`. This project has no `SchemaMigrationPlan` — `CadenceStoreSupport`,
/// `CadenceDataExportService` and `Note` all say so in terms — and build 22, shipping blocks, went
/// to App Store Connect on 2026-10-13. A store written by that build has to keep opening under
/// this one. Dropping the entity is a later build's job, once no device can still hold a record.
///
/// **Idempotent and self-guarding**, like every other startup pass here: it fetches the block
/// table first and answers `.nothingToDo` on an empty one, which after the first launch is every
/// launch. There is no `UserDefaults` flag on purpose — `PursuitToGoalMigration`'s note records why
/// one would be wrong anyway, since `PersistenceController.init` can apply a pending restore that
/// predates the pass — and because blocks can also arrive later from CloudKit or from an imported
/// archive, this pass has to stay armed rather than latch itself off.
///
/// **It has two entry points and they are isolated differently, on purpose.**
/// `retireAllBundles(in:capturing:)` is the walk — `nonisolated`, because
/// `CadenceArchiveImportService.apply` is `nonisolated` and has to run it inside its own
/// transaction so an imported archive's blocks never reach disk. `runIfNeeded(modelContext:commit:)`
/// is the launch pass that wraps the walk in a commit and a refusal path; it is `MainActor` by
/// this module's default because `CadenceDeleteSurvivorSnapshot` is, and its only caller
/// `PersistenceController.performStartupMaintenance` is too. The walk is written once and both
/// use it; do not grow a second member loop for the import.
nonisolated enum TaskBundleRetirement {

    /// The shortest slot a member may be credited with, and the end of the day a start minute is
    /// clamped inside.
    ///
    /// **Spelled here rather than read off `CadenceTaskMutationSupport`, and pinned by a test
    /// instead.** Those constants are `MainActor`-isolated under this module's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION`, and this arithmetic has to be reachable from the
    /// `nonisolated` archive import. `theClampsMatchTheOnesThatSizedTheBlocks` in
    /// `CadenceTaskBundleRetirementTests` fails if either side moves — the same arrangement
    /// `bundleClampsMatchTheTimelineDayRange` already holds between that type and
    /// `TimelineDayRange`, for the same reason and with the same failure mode.
    static let minimumSlotMinutes = 5
    static let dayEndMin = 24 * 60

    /// A start minute clamped so a minimum-length slot still ends inside the day. The same
    /// expression as `CadenceTaskMutationSupport.clampedBundleStart`, held by the same test.
    static func clampedStart(_ startMin: Int) -> Int {
        min(max(0, startMin), dayEndMin - minimumSlotMinutes)
    }

    /// How long a member counts as, for the purpose of deciding whether a block's members fit
    /// inside it. The same expression `CadenceTaskMutationSupport.bundleDuration(startingAt:tasks:)`
    /// used to *build* a block out of these tasks, which is what makes the fit question symmetric.
    static func naturalLength(of task: AppTask) -> Int {
        max(task.estimatedMinutes, minimumSlotMinutes)
    }

    /// The start minute each member takes when its block is retired, in `bundleOrder` order.
    ///
    /// Pure, and separated from the store walk below so the arithmetic can be asserted directly —
    /// the two branches are the whole of this migration's behaviour and a store round-trip is a
    /// poor place to read them.
    ///
    /// - Parameters:
    ///   - lengths: each member's `naturalLength(of:)`, in the order the members are laid out.
    ///   - blockStart: the block's `startMin`.
    ///   - blockDuration: the block's `durationMinutes`.
    /// - Returns: one start minute per entry in `lengths`, non-decreasing, each inside the day.
    static func memberStartMinutes(lengths: [Int], blockStart: Int, blockDuration: Int) -> [Int] {
        guard !lengths.isEmpty else { return [] }
        let span = max(blockDuration, minimumSlotMinutes)
        let start = clampedStart(blockStart)

        if lengths.reduce(0, +) <= span {
            var cursor = start
            var starts: [Int] = []
            starts.reserveCapacity(lengths.count)
            for length in lengths {
                starts.append(clampedStart(cursor))
                cursor += max(length, minimumSlotMinutes)
            }
            return starts
        }

        // Does not fit: share the block's own span out evenly rather than spilling past its end.
        // Integer division on purpose — a start minute is an `Int` — and `span * index / count`
        // rather than `index * (span / count)` so the slices stay spread across the whole span
        // instead of bunching at the top when `span` does not divide evenly.
        return lengths.indices.map { index in
            clampedStart(start + span * index / lengths.count)
        }
    }

    /// **The walk: pushes every block's schedule down onto its members and ends the blocks,
    /// committing nothing.**
    ///
    /// Shared by the launch pass below and by `CadenceArchiveImportService.apply`, which runs it
    /// after wiring and before its own `save()` so that an archive's blocks are unbundled *on the
    /// way in* and never reach disk. That is not an optimisation: every archive the owner has
    /// taken so far contains blocks, and an import that materialised them would restore a set of
    /// tasks that no surface can show until the next launch retires them.
    ///
    /// Membership is read from the **task** side (`task.bundle`), not from `bundle.tasks`:
    /// `CadenceTaskMutationSupport.bundleMembers(in:)` makes the same choice for the same reason —
    /// the to-many array can still list a task whose own `bundle` has moved on, and the inverse is
    /// what decides.
    ///
    /// - Parameter capture: handed each block and its members *before* they are rewritten, so a
    ///   caller that owns a commit can snapshot the rows that survive the delete. The launch pass
    ///   below is the one caller that does; the import does not, because its own `rollback()`
    ///   covers the whole transaction.
    /// - Returns: the number of blocks retired. `0` means the store held none.
    /// - Throws: whatever the two fetches throw. Nothing is written before both have succeeded.
    @discardableResult
    static func retireAllBundles(
        in modelContext: ModelContext,
        capturing capture: (TaskBundle, [AppTask]) -> Void = { _, _ in }
    ) throws -> Int {
        let bundles = try modelContext.fetch(FetchDescriptor<TaskBundle>())
        guard !bundles.isEmpty else { return 0 }

        // Only now is the task table worth reading: after the first launch the fetch above is what
        // this pass costs, and a full `AppTask` sweep on every launch for a feature that no longer
        // exists would be a real price for nothing.
        let tasks = try modelContext.fetch(FetchDescriptor<AppTask>())
        var membersByBundle: [UUID: [AppTask]] = [:]
        for task in tasks {
            guard let bundleID = task.bundle?.id else { continue }
            membersByBundle[bundleID, default: []].append(task)
        }

        for bundle in bundles {
            let members = membersByBundle[bundle.id] ?? []
            capture(bundle, members)
            retire(bundle, members: members, in: modelContext)
        }
        return bundles.count
    }

    /// **The launch pass**, which wraps the walk above in a commit and the refusal path that goes
    /// with it.
    ///
    /// - Parameter commit: See `CadencePendingChangePersistence.commitDelete(in:commit:)`. This
    ///   pass deletes rows, so it owns its save rather than leaving the work pending for
    ///   `performStartupMaintenance`'s single commit at the end — the same arrangement
    ///   `PursuitToGoalMigration` was built with, and the reason the launch call site discards the
    ///   outcome's `changedStore` instead of folding it into `changedStore` there.
    @discardableResult
    static func runIfNeeded(
        modelContext: ModelContext,
        commit: (ModelContext) throws -> Void = { try $0.save() }
    ) -> CadenceMaintenancePassOutcome {
        // **The refusal path puts the members back itself ([[T-1336]]).** This pass rewrites five
        // fields on rows that *survive* the delete, and `rollback()`'s reach onto an
        // already-materialised reference is the clause this repository's two Xcode majors have
        // answered differently. `CadenceTaskMutationSupport.deleteBundle` is wired exactly this
        // way, for exactly these five fields, and this is the launch-time twin of it: the restore
        // runs from inside `commitDelete`'s own `commit:` so it lands *before* the rollback.
        var survivors = CadenceDeleteSurvivorSnapshot()
        let retired: Int
        do {
            retired = try retireAllBundles(in: modelContext) { bundle, members in
                survivors.captureMembership(of: bundle)
                for member in members {
                    survivors.captureSlot(of: member)
                }
            }
        } catch {
            return .couldNotRead
        }
        guard retired > 0 else { return .nothingToDo }

        do {
            try CadencePendingChangePersistence.commitDelete(
                in: modelContext,
                commit: { try CadencePendingChangePersistence.commitEdit(in: $0, commit: commit, undo: survivors.restore) }
            )
        } catch {
            // There is no fourth `CadenceMaintenancePassOutcome` case for "could not write", and a
            // refused save is a failure rather than a result exactly as a refused read is — so it
            // answers `couldNotRead`, which `CadenceStartupStageVerdict.forMaintenancePass` records
            // as `refused`. A launch that could not retire the blocks must not read like a launch
            // with no blocks to retire; that is the whole distinction T-1402 drew.
            return .couldNotRead
        }
        return .changed
    }

    /// One block's half of the pass: lay its members out, detach them, delete it.
    ///
    /// The five field writes on each member are deliberately the ones
    /// `CadenceTaskMutationSupport.deleteBundle` already performs — `calendarEventID` included, for
    /// the reason recorded there — with exactly one difference, which is the whole ticket:
    /// `scheduledStartMin` is given the member's own slot instead of `-1`.
    private static func retire(_ bundle: TaskBundle, members: [AppTask], in modelContext: ModelContext) {
        let ordered = members.sorted {
            if $0.bundleOrder != $1.bundleOrder { return $0.bundleOrder < $1.bundleOrder }
            return $0.createdAt < $1.createdAt
        }
        let starts = memberStartMinutes(
            lengths: ordered.map { naturalLength(of: $0) },
            blockStart: bundle.startMin,
            blockDuration: bundle.durationMinutes
        )
        for (member, start) in zip(ordered, starts) {
            member.bundle = nil
            member.bundleOrder = 0
            member.scheduledDate = bundle.dateKey
            member.scheduledStartMin = start
            member.calendarEventID = ""
        }
        bundle.tasks = []
        modelContext.delete(bundle)
    }
}
