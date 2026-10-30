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
            CadenceSourceScan.declarationBody("private func subtaskRow(_ draft: Binding<CreateTaskSubtaskDraft>) -> some View", in: source)
        )

        #expect(body.contains(#".accessibilityLabel("Remove")"#))
        #expect(body.contains(".accessibilityValue(TaskTitleSupport.displayTitle("))
        // The subject: this row's own draft text, not the model `Subtask` (there is none yet).
        // Since T-6452 the row is bound to its draft by identity rather than by index.
        #expect(body.contains("draft.wrappedValue.title,"))
        #expect(body.contains("fallback: TaskTitleSupport.defaultCompactDisplayTitle"))
    }

    // MARK: - Sites 2 and 3: the compact quick-create popover

    // **`quickCreateDraftSubtaskRemoveButtonNamesTheDraftItRemoves` left with [[T-3171]]'s seventh
    // adoption slice.** It was [[T-673]]'s second site: the drag-create popover's in-place Task
    // composer listed the subtasks typed into a new task, each with a "Remove" button naming its
    // draft. That popover is `CadenceSchedulePanel` now, `CadenceScheduleDraft` carries no
    // subtasks, and `QuickCreateChoiceSupportViews.swift` — the file the composer and its
    // `subtaskRow` were declared in — is deleted. The surviving subtask rows are the create
    // sheet's and the task panel's, both still swept below.
    //
    // **`quickCreateSelectedTaskRemoveButtonNamesTheTaskItRemoves` left with [[T-3170]].** It was
    // [[T-673]]'s third site: the popover's Block tab listed the tasks ticked into a new block,
    // each with a "Remove" button naming its task. The Block tab, and
    // `QuickCreateBundleTaskSelectionView` with its `selectedTaskRow`, went with the Block
    // feature's creation paths.

    // **Sites 4 and 5 left with [[T-5002]].** Both lived in `GoalsSupportViews.swift`, which is
    // deleted with the Goals screens: `GoalLinkedListRow`'s detach button had already gone with
    // [[T-2079]], and T-792's two "the visible Text reads the same normalised title the
    // announcement does" tests — `goalLinkedListVisibleTitleMatchesTheAnnouncedNormalisedTitle`
    // and `goalTaskContributorVisibleTitleMatchesTheAnnouncedDisplayTitle` — went with the rows
    // they read, as did `goalTaskContributorDetachButtonNamesTheTaskItDetaches`.
    //
    // **The RULE they were about is not gone and is not left unguarded**: that a row's visible
    // title and its accessibility value read one normalisation rather than two. `SubtaskRow`
    // below asserts exactly that, in the same shape, against a surface that still ships.
    // `TaskTitleSupport.displayTitle` keeps its own tests in `CadenceEmptyTitleFallbackSweepTests`.

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
    /// (T-673), and then read the *task* row's name for it. T-673 pointed it at
    /// `CadenceTaskCompletionState.accessibilityActionLabel`, so VoiceOver on a Mac subtask said
    /// "Complete task, Book flight" while both iOS subtask circles said "Complete subtask"
    /// ([[T-8610]]). One app, two platforms, no hardware reason: every subtask circle now reads
    /// `CadenceSubtaskAccessibility.completionActionLabel(isDone:)`, keyed on the two states a
    /// `Subtask` has.
    @Test func subtaskRowCompletionCircleReadsTheSharedSubtaskLabel() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.tasksPanelSupportPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct SubtaskRow: View", in: source))

        #expect(body.contains(".accessibilityValue(displayTitle)"), "non-vacuity: wrong body read")
        #expect(body.contains(".accessibilityLabel(CadenceSubtaskAccessibility.completionActionLabel(isDone: subtask.isDone))"))
        // The task row's name reaches no subtask circle.
        #expect(!body.contains("accessibilityActionLabel"))
    }

    /// The words themselves ([[T-8610]]): the iOS wording won, so the Mac took "subtask", and a done
    /// subtask's circle names the undo rather than repeating "Complete".
    @Test func theSharedSubtaskCompletionLabelNamesASubtask() {
        #expect(CadenceSubtaskAccessibility.completionActionLabel(isDone: false) == "Complete subtask")
        #expect(CadenceSubtaskAccessibility.completionActionLabel(isDone: true) == "Mark subtask todo")
        // Never the task row's names, which is the drift this closed.
        for isDone in [false, true] {
            let label = CadenceSubtaskAccessibility.completionActionLabel(isDone: isDone)
            #expect(!CadenceTaskCompletionState.allCases.map(\.accessibilityActionLabel).contains(label))
        }
    }

    /// No subtask circle spells its name as a literal any more: the three hosts read the rule.
    @Test func everySubtaskCircleReadsTheOneSubtaskRule() throws {
        let sites: [(path: String, declaration: String)] = [
            (Self.tasksPanelSupportPath, "struct SubtaskRow: View"),
            (Self.iOSTaskDetailComponentsPath, "struct iOSSubtaskRow: View"),
            (Self.iOSTaskRowActionViewsPath, "struct iOSTaskRowSubtaskRow: View"),
        ]
        for site in sites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(site.path))
            let body = try #require(CadenceSourceScan.declarationBody(site.declaration, in: source), "\(site.declaration)")
            #expect(
                CadenceSourceScan.matchCount(#"\.accessibilityLabel\(CadenceSubtaskAccessibility\.completionActionLabel\(isDone: "#, in: body) == 1,
                "\(site.declaration) does not read the shared subtask label"
            )
            #expect(!body.contains(#""Complete subtask""#), "\(site.declaration) spells the label itself")
            #expect(!body.contains(#""Mark subtask todo""#), "\(site.declaration) spells the label itself")
        }
    }

    // MARK: - The iOS twin of sites 6 and 7: the task sheet's subtask row ([[T-7011]])

    private static let iOSTaskDetailComponentsPath = "Cadence/iOS/iOSTaskDetailComponents.swift"

    /// **`iOSSubtaskRow` was the one subtask row T-673 never reached.** Its circle and its trash
    /// glyph announced "Complete subtask" and "Delete subtask" on every row alike, so a VoiceOver
    /// user in a five-item block could not tell which subtask a delete would take. It names its
    /// subject now exactly the way macOS's `SubtaskRow` does: one normalised `displayTitle`, handed
    /// to both buttons, with the compact "Untitled" fallback for a blank title.
    @Test func iOSSubtaskRowButtonsNameTheSubtaskTheyActOn() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSTaskDetailComponentsPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct iOSSubtaskRow: View", in: source))

        #expect(body.contains(#".accessibilityLabel("Delete subtask")"#), "non-vacuity: wrong body read")
        #expect(body.contains("private var displayTitle: String {"))
        #expect(body.contains(
            "TaskTitleSupport.displayTitle(subtask.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle)"
        ))
        #expect(CadenceSourceScan.matchCount(#"\.accessibilityValue\(displayTitle\)"#, in: body) == 2)
        // The fallback a blank subtask announces is a word, not silence.
        #expect(TaskTitleSupport.displayTitle("   ", fallback: TaskTitleSupport.defaultCompactDisplayTitle) == "Untitled")
    }

    // MARK: - The iOS task row's listed subtask ([[T-8592]])

    private static let iOSTaskRowActionViewsPath = "Cadence/iOS/iOSTaskRowActionViews.swift"

    /// **The subtasks listed under an iOS task row and board card were the last subtask circle
    /// still naming the raw title.** Its label was `"Complete subtask \(subtask.title)"` while the
    /// row drew `displayTitle`, so a blank subtask was announced "Complete subtask" over a row
    /// reading "Untitled". It names itself the way the sheet's `iOSSubtaskRow` does now: the
    /// action as the label, the normalised title as the value.
    @Test func iOSTaskRowSubtaskRowNamesTheSubtaskItDraws() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSTaskRowActionViewsPath))
        let body = try #require(CadenceSourceScan.declarationBody("struct iOSTaskRowSubtaskRow: View", in: source))

        #expect(body.contains("private var displayTitle: String {"))
        #expect(body.contains(
            "TaskTitleSupport.displayTitle(subtask.title, fallback: TaskTitleSupport.defaultCompactDisplayTitle)"
        ))
        #expect(body.contains("Text(displayTitle)"), "the row draws a different title from the one it announces")
        #expect(body.contains(".accessibilityLabel(CadenceSubtaskAccessibility.completionActionLabel(isDone: false))"))
        #expect(CadenceSourceScan.matchCount(#"\.accessibilityValue\(displayTitle\)"#, in: body) == 1)
        // The raw title reaches no accessibility modifier.
        #expect(CadenceSourceScan.matchCount(#"accessibility\w*\([^)]*subtask\.title"#, in: body) == 0)
    }

    // **Site 8 left with [[T-2079]] and its file with [[T-5002]].**
    // `habitToggleCircleReadsTheSharedCompletionStateLabelAndNamesTheHabit` was one half of
    // [[T-673]]'s "two completion circles tick one" pair: `HabitListCard`'s circle read the shared
    // `accessibilityActionLabel` and named the habit. T-2079 made the circle a glyph rather than a
    // button, and T-5002 deleted `HabitsSupportViews.swift` outright. The subtask circle, the
    // other half of the pair, is untouched and still asserted above.

    // MARK: - The count itself, exact rather than a floor

    /// **Eight sites, each named above by its own test — not a floor.** A population this small
    /// invites exactly the mistake `docs/SUBAGENT_RUNBOOK.md` warns against: a `>=` here would stay
    /// green if one of the eight regressed while an unrelated `.accessibilityValue` appeared
    /// somewhere else. Counted **within each declaration's own body**, not the whole file — a
    /// whole-file count would also catch `ContainerPickerBadge`'s own `.accessibilityValue(label)`
    /// (`TasksPanelSupportViews.swift:246`, T-594's own list-badge fix), which is a ninth
    /// `.accessibilityValue(` in one of these five files that has nothing to do with this ticket.
    @Test func exactlyEightAccessibilityValuesWereAddedAcrossTheEightSites() throws {
        func count(_ declaration: String, in path: String) throws -> Int {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: source))
            return CadenceSourceScan.matchCount(#"\.accessibilityValue\("#, in: body)
        }

        var total = 0
        total += try count("private func subtaskRow(_ draft: Binding<CreateTaskSubtaskDraft>) -> some View", in: Self.createTaskSheetPath)
        // Both subtask-row sites (the circle and the delete button) live in one struct.
        total += try count("struct SubtaskRow: View", in: Self.tasksPanelSupportPath)
        // `GoalLinkedListRow` and `HabitListCard` were the fourth and eighth sites and left with
        // [[T-2079]]; `GoalTaskContributorRow` was the fifth and left with [[T-5002]], which
        // deleted the file all three lived in — one `.accessibilityValue(` with it. The third,
        // the Block tab's `selectedTaskRow`, left with [[T-3170]], taking another. The second,
        // the drag-create popover's draft-subtask row, left with [[T-3171]]'s seventh slice.

        #expect(total == 3)
    }
}
