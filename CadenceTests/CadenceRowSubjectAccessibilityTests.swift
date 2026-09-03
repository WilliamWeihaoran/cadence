import Foundation
import Testing
@testable import Cadence

/// **A row's remove/complete glyph never said which row it belonged to** (T-673, from T-637).
///
/// Six bare `xmark` buttons removed a thing — a draft subtask, a task picked into a block, a
/// goal's linked list, a goal's task contributor, a saved subtask — and two completion circles
/// ticked one, with no accessible name at all. Naming them "Remove" or "Complete task" alone would
/// have been the T-472/T-484 shape (`CadenceControlAccessibilityLabelTests`) — a missing string —
/// but it is not: the *action* is guessable from the glyph, and eight identical "Remove"
/// announcements are no better than eight silent ones. What each site was missing is the
/// **subject**, so every assertion below checks that the row hands its own title down through
/// `.accessibilityValue`, not that some string exists.
///
/// **Why a source scan and not a view test.** `.accessibilityLabel`/`.accessibilityValue` write
/// into an `AccessibilityAttachmentModifier` no headless test can read back, and every one of these
/// eight sites is a private view or a private helper method with no public surface to instantiate
/// through `@testable import` and inspect. Reading the declaration's own source text is the only
/// way to pin what argument each modifier was given.
///
/// **Why the assertions check the *shape* of the argument, not just that the modifier is present.**
/// A test asserting `.accessibilityValue(` occurs in the body would still pass a fix that wrote
/// `.accessibilityValue("Subtask")` — a constant, carrying no more information than the missing
/// label did. Each check below requires the argument to be the row's own stored property (or an
/// expression built from it), by asserting the exact call the row makes rather than merely its
/// presence.
struct CadenceRowSubjectAccessibilityTests {

    // MARK: - Site 1: a draft subtask in the full create-task sheet

    private static let createTaskSheetPath = "Cadence/macOS/Sheets/CreateTaskSheet.swift"

    @Test func createTaskSheetDraftSubtaskRemoveButtonNamesTheDraftItRemoves() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.createTaskSheetPath))
        let body = try #require(
            CadenceSourceScan.declarationBody("private func subtaskRow(at index: Int) -> some View", in: source)
        )

        #expect(body.contains(#".accessibilityLabel("Remove")"#))
        #expect(body.contains(".accessibilityValue(TaskTitleSupport.displayTitle("))
        // The subject: this row's own draft text, not the model `Subtask` (there is none yet).
        #expect(body.contains("subtaskTitles[index],"))
        #expect(body.contains("fallback: TaskTitleSupport.defaultCompactDisplayTitle"))
    }

    // MARK: - Sites 2 and 3: the compact quick-create popover

    private static let quickCreatePath = "Cadence/macOS/Views/QuickCreateChoiceSupportViews.swift"

    @Test func quickCreateDraftSubtaskRemoveButtonNamesTheDraftItRemoves() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.quickCreatePath))
        let body = try #require(
            CadenceSourceScan.declarationBody(
                "private func subtaskRow(title: String, index: Int) -> some View",
                in: source
            )
        )

        #expect(body.contains(#".accessibilityLabel("Remove")"#))
        // The subject is the row's own `title` parameter, not a re-read of `subtaskTitles[index]`
        // — a second, independent read would drift the moment either copy changed.
        #expect(body.contains(
            ".accessibilityValue(TaskTitleSupport.displayTitle(title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))"
        ))
    }

    @Test func quickCreateSelectedTaskRemoveButtonNamesTheTaskItRemoves() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.quickCreatePath))
        let body = try #require(
            CadenceSourceScan.declarationBody("private func selectedTaskRow(_ task: AppTask) -> some View", in: source)
        )

        #expect(body.contains(#".accessibilityLabel("Remove")"#))
        #expect(body.contains(
            ".accessibilityValue(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle))"
        ))
    }

    // MARK: - Sites 4 and 5: a goal's attached work

    private static let goalsSupportPath = "Cadence/macOS/Views/GoalsSupportViews.swift"

    @Test func goalLinkedListDetachButtonNamesTheListItDetaches() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.goalsSupportPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct GoalLinkedListRow: View", in: source))

        #expect(body.contains(#".accessibilityLabel("Detach")"#))
        #expect(body.contains(".accessibilityValue(normalizedTitle)"))
        // The normalisation itself: routed through `CadenceTitleNormalization.display`, keyed on
        // which relationship is set, rather than interpolating `link.title` raw — an area or
        // project with a blank *name* passes an empty string through `link.title` untouched.
        #expect(body.contains("CadenceTitleNormalization.display("))
        #expect(body.contains("link.area != nil"))
        #expect(body.contains("CadenceTitleNormalization.defaultAreaName"))
        #expect(body.contains("CadenceTitleNormalization.defaultProjectName"))
    }

    @Test func goalTaskContributorDetachButtonNamesTheTaskItDetaches() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.goalsSupportPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct GoalTaskContributorRow: View", in: source))

        #expect(body.contains(#".accessibilityLabel("Detach")"#))
        #expect(body.contains(
            ".accessibilityValue(TaskTitleSupport.displayTitle(task.title, fallback: TaskTitleSupport.defaultDisplayTitle))"
        ))
    }

    // MARK: - Sites 6 and 7: a saved subtask's own row

    private static let tasksPanelSupportPath = "Cadence/macOS/Views/TasksPanelSupportViews.swift"

    @Test func subtaskRowRemoveButtonNamesTheSubtaskItRemoves() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.tasksPanelSupportPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct SubtaskRow: View", in: source))

        #expect(body.contains(#".accessibilityLabel("Remove")"#))
        // Shared with the visible title text and the completion circle below, so all three read
        // the same normalised string rather than three independent copies of the same expression.
        #expect(body.contains("private var displayTitle: String {"))
        #expect(CadenceSourceScan.matchCount(#"\.accessibilityValue\(displayTitle\)"#, in: body) == 2)
    }

    /// **The other half of this struct: the completion circle "still spelled its own state"**
    /// rather than reading `CadenceTaskCompletionState.accessibilityActionLabel`, the shared answer
    /// `TaskCompletionButton` (macOS's task row) and `iOSTaskViews`' circle already read theirs
    /// from (T-594, pointed at iOS in T-611). A `Subtask` has only two states — done or not — so
    /// this maps straight to `.done` / `.todo` rather than needing the mid-fill states a full
    /// `AppTask` can be in.
    @Test func subtaskRowCompletionCircleReadsTheSharedCompletionStateLabel() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.tasksPanelSupportPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct SubtaskRow: View", in: source))

        #expect(body.contains("private var completionState: CadenceTaskCompletionState {"))
        #expect(body.contains("subtask.isDone ? .done : .todo"))
        #expect(body.contains(".accessibilityLabel(completionState.accessibilityActionLabel)"))
    }

    // MARK: - Site 8: a habit's completion toggle

    private static let habitsSupportPath = "Cadence/macOS/Views/HabitsSupportViews.swift"

    /// Same shared label as the subtask circle, plus the habit's own normalised title — the ledger
    /// grouped this with the subtask circle as "two completion circles tick one" (T-673), so both
    /// take the same fix shape.
    @Test func habitToggleCircleReadsTheSharedCompletionStateLabelAndNamesTheHabit() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.habitsSupportPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct HabitListCard: View", in: source))

        #expect(body.contains(
            ".accessibilityLabel((isDoneToday ? CadenceTaskCompletionState.done : .todo).accessibilityActionLabel)"
        ))
        #expect(body.contains(".accessibilityValue(CadenceTitleNormalization.display("))
        #expect(body.contains("habit.title,"))
        #expect(body.contains("fallback: CadenceTitleNormalization.defaultHabitTitle"))
    }

    // MARK: - The count itself, exact rather than a floor

    /// **Eight sites, each named above by its own test — not a floor.** A population this small
    /// invites exactly the mistake `docs/SUBAGENT_RUNBOOK.md` warns against: a `>=` here would stay
    /// green if one of the eight regressed while an unrelated `.accessibilityValue` appeared
    /// somewhere else. Counted **within each declaration's own body**, not the whole file — a
    /// whole-file count would also catch `ContainerPickerBadge.accessibilityValue(label)`
    /// (`TasksPanelSupportViews.swift:246`, T-594's own list-badge fix), which is a ninth
    /// `.accessibilityValue(` in one of these five files that has nothing to do with this ticket.
    @Test func exactlyEightAccessibilityValuesWereAddedAcrossTheEightSites() throws {
        func count(_ declaration: String, in path: String) throws -> Int {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
            return CadenceSourceScan.matchCount(#"\.accessibilityValue\("#, in: body)
        }

        var total = 0
        total += try count("private func subtaskRow(at index: Int) -> some View", in: Self.createTaskSheetPath)
        total += try count(
            "private func subtaskRow(title: String, index: Int) -> some View",
            in: Self.quickCreatePath
        )
        total += try count("private func selectedTaskRow(_ task: AppTask) -> some View", in: Self.quickCreatePath)
        total += try count("struct GoalLinkedListRow: View", in: Self.goalsSupportPath)
        total += try count("struct GoalTaskContributorRow: View", in: Self.goalsSupportPath)
        // Both subtask-row sites (the circle and the delete button) live in one struct.
        total += try count("struct SubtaskRow: View", in: Self.tasksPanelSupportPath)
        total += try count("struct HabitListCard: View", in: Self.habitsSupportPath)

        #expect(total == 8)
    }
}
