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
/// **That constraint is gone, and this empty type is now a deletion nobody has made.** It read, up
/// to [[T-3010]], that the type was kept rather than the file deleted because this file was named
/// in `CadenceMCPServer`'s **explicit** Sources phase and removing it from that phase was a
/// `Cadence.xcodeproj/project.pbxproj` edit [[T-117]] forbids while the owner has Xcode open.
/// T-3010 (`3be4b126`) made that edit: this file, `GoalAssignmentRules.swift` and
/// `CadencePluralization.swift` left the phase and stayed on disk. The other two kept their place
/// on disk on their own merits — both still have app callers — but **this one has none anywhere**,
/// and an empty enum with no reference in the tree is [[T-260]]'s case for deleting the file
/// outright. It is left here only because T-3010's scope was the target membership; the deletion
/// is a separate pass, and the three remaining mentions of the name are doc comments in
/// `CadenceGlobalUndoSurfaceTests`, `CadenceTrackingEditorSaveCommitTests` (whose comment already
/// says "the file is deleted", which is not yet true) and `CadenceSaveCommitDisciplineTests`.
enum CadenceTrackingMutationSupport {}
