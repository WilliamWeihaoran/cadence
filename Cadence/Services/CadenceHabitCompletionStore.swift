import Foundation
import SwiftData

/// The retired habit check-in writer ([[T-2079]]).
///
/// It used to be the **one** place a `HabitCompletion` was constructed, and that was the whole of
/// its job: four surfaces open-coded the same insert-if-none-exists toggle before [[T-374]] folded
/// them into `toggle(_:on:modelContext:commit:)`, and a scan kept it that way. [[T-359]]'s
/// duplicate collapse lived here for the same reason, until [[T-2077]] removed the startup repair
/// pass that was its only caller.
///
/// **Both are gone and nothing replaced them.** The owner retired habits at the depth *"remove the
/// UI and stop writing, keep the schema"*: `Habit`, `HabitCompletion` and `HabitInsights` stay in
/// `CadenceSchema`, their CloudKit record types stay, and the rows already in the owner's store
/// stay exactly as they are — but no code path creates, edits or deletes one again.
///
/// **The scan that policed the constructor is inverted rather than deleted**, and that inversion is
/// the strongest guard this retirement has:
/// `CadenceHabitCompletionDuplicateTests.nothingUnderCadenceConstructsAHabitCompletion` now asserts
/// that **no** file under `Cadence/` constructs one, this file included. A guard reading "only this
/// file writes X" became "no file writes X", which is strictly stronger than what it replaced.
///
/// **Reads are untouched, and they carry the rule the writer used to.**
/// `Habit.completionCountsByDate()` still collapses a duplicated day through
/// `HabitCompletion.collapsedCount(of:)` — a `max` over the day's rows — so an existing duplicate
/// still reports as one day rather than two. That was always the user-visible half of [[T-359]];
/// what has gone is the writer that could not make a duplicate and the startup pass that deleted
/// one.
///
/// The type is kept rather than the file deleted because it is named in `CadenceMCPServer`'s
/// **explicit** Sources phase (`Cadence.xcodeproj/project.pbxproj`), and removing a file from that
/// phase is a project-file edit [[T-117]] forbids while the owner has Xcode open.
nonisolated enum CadenceHabitCompletionStore {}
