import Foundation
import SwiftData

/// The retired `Goal` / `Habit` mutation helpers ([[T-2079]]).
///
/// `saveGoal(...)` and `saveHabit(...)` were the one write path for both models — the create that
/// inserted and the edit that wrote fields — and every caller went through them rather than
/// open-coding the rules they owned: `endDate` pulled forward to `startDate`, `targetHours` floored
/// at zero, `targetCount` floored at one, a context inherited from the parent goal or the habit's
/// goal, and a goal handed itself as a parent silently un-parented so `GoalContributionResolver`
/// could not walk a cycle. The callers were `CreateGoalSheet` and `HabitsFormSheets` on macOS,
/// `iOSTrackingEditorSheets` on iOS, and `CadenceWriteService`'s `create_goal` / `create_habit` MCP
/// arms. None of them exists any more.
///
/// **Why the whole type emptied rather than the functions being guarded.** The owner retired goals
/// and habits at the depth *"remove the UI and stop writing, keep the schema"*: the models, their
/// CloudKit record types and every row already in the owner's store stay, untouched and
/// recoverable, and no code path creates or edits one again. A `saveGoal` left in place with no
/// caller is a write one `+` button away from being live again, and **the compiler is the only
/// thing that can hold a removal like this** — a scan cannot. So the functions are gone and every
/// call site had to be removed before the tree would build, which is what makes the removal
/// provably complete rather than merely thorough.
///
/// The failure notices went with them. `goalSaveFailureNotice`, `habitSaveFailureNotice`,
/// `goalDeleteFailureNotice`, `habitDeleteFailureNotice` and the two iOS alert titles each named a
/// refusal that can no longer happen, and `goalDeleteConfirmationMessage` counted a cascade
/// (`ModelContext.deleteGoal`) that no longer exists either — see `TrackingDeleteHelpers`.
///
/// **The type is kept rather than the file deleted**, and that is a constraint rather than a
/// preference: this file is named in `CadenceMCPServer`'s **explicit** Sources phase in
/// `Cadence.xcodeproj/project.pbxproj`, and removing it from that phase is a project-file edit
/// [[T-117]] forbids while the owner has Xcode open. `CadenceHabitCompletionStore.swift` and
/// `GoalAssignmentRules.swift` are in that phase for the same reason; the third is all reads and
/// is untouched.
enum CadenceTrackingMutationSupport {}
