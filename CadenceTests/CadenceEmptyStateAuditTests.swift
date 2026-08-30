import Foundation
import Testing
@testable import Cadence

// MARK: - Reading empty states out of source

/// The `message:` / `title:` / `subtitle:` arguments of every empty-state call in a file.
///
/// **Why source and not values.** An empty state is two string arguments passed to a `View`
/// initialiser from inside another `View`'s `body`. There is no seam: nothing a test can call
/// returns "the words this screen shows when it is empty", and `Cadence/iOS/` is not compiled by
/// this target at all. So the shape is read as text — but read *scoped to the call*, because a
/// file-wide `contains` cannot tell an empty state's subtitle from a button label thirty lines
/// away.
enum CadenceEmptyStateAudit {

    /// Both shared empty-state components. `EmptyStateView` is the cross-platform one; the phone
    /// draws `iOSEmptyPanel` because its pane chrome differs, which
    /// `CadenceDeletedSelectionGuardTests` records as deliberate.
    static let componentNames = ["EmptyStateView(", "iOSEmptyPanel("]

    private static let argumentPattern = "(?:message|title|subtitle)\\s*:\\s*\"([^\"\\\\\\n]*)\""

    /// The text between the parentheses of each empty-state call, brace-matched over the call's own
    /// `(`…`)` so a later call's arguments cannot leak into an earlier one's segment.
    ///
    /// String literals are skipped while counting depth: a subtitle reading `"Try (again)"` would
    /// otherwise close the call early and truncate everything after it.
    static func callSegments(in source: String) -> [String] {
        var segments: [String] = []
        for name in componentNames {
            var searchStart = source.startIndex
            while let found = source.range(of: name, range: searchStart..<source.endIndex) {
                searchStart = found.upperBound
                var depth = 1
                var index = found.upperBound
                var inLiteral = false
                while index < source.endIndex, depth > 0 {
                    let character = source[index]
                    if inLiteral {
                        if character == "\\" {
                            index = source.index(after: index)
                        } else if character == "\"" || character.isNewline {
                            inLiteral = false
                        }
                    } else if character == "\"" {
                        inLiteral = true
                    } else if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    guard index < source.endIndex else { break }
                    index = source.index(after: index)
                }
                if index <= source.endIndex {
                    segments.append(String(source[found.upperBound..<min(index, source.endIndex)]))
                }
            }
        }
        return segments
    }

    /// Every hand-spelled empty-state literal in `source`, in call order.
    static func literals(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: argumentPattern) else { return [] }
        var found: [String] = []
        for segment in callSegments(in: source) {
            let range = NSRange(segment.startIndex..., in: segment)
            for match in regex.matches(in: segment, range: range) {
                guard let captured = Range(match.range(at: 1), in: segment) else { continue }
                let text = String(segment[captured])
                if !text.trimmingCharacters(in: .whitespaces).isEmpty { found.append(text) }
            }
        }
        return found
    }

    /// String literals, comments already stripped. Used by the touch-verb rule so an identifier
    /// like `onTapGesture` cannot be read as copy.
    static func stringLiterals(in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"\\\\\\n]*)\"") else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[captured])
        }
    }
}

// MARK: - The audit

/// **Empty states, audited as a family rather than one screen at a time.**
///
/// Three defects had already been found and fixed one by one — T-469's "Add a task above" beside a
/// field that exists at no width, T-473's "Create a task to get started" under the `+` it restates,
/// and `TasksPanel` saying both of them at once — and each fix was pinned against the single file
/// it was found in. This suite asks the two questions those fixes imply, over every surface:
///
/// 1. **Is the copy shared?** A sentence spelled at two call sites is a sentence that will drift,
///    and it does: the Notes page's four tab pairs claimed in a comment to be "Same words macOS
///    uses, tab for tab" while the Events subtitle differed by a full stop, and Saved Links said
///    "Tap + to save a link" on the Mac against "Save URLs that belong with this list." on the
///    phone.
/// 2. **Is the copy true?** Two halves — does it name a control that is on *that* screen at *that*
///    width, and does it tell "you have nothing" apart from "your filter matched nothing".
@MainActor
struct CadenceEmptyStateAuditTests {

    // MARK: One spelling per sentence

    /// **No empty-state sentence is written out in two files.**
    ///
    /// The generalisation of the per-screen fixes: rather than pinning one screen's words, this
    /// says that any wording two screens share has to live in one place. It is the assertion
    /// `CadenceEmptyStateCopy` was created for and that nothing enforced — the file's own doc
    /// comment lists three pairs that had already drifted before anyone noticed.
    @Test func noEmptyStateSentenceIsSpelledInTwoFiles() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let read = CadenceSourceScan.strippedSourceReader()

        let handSpelled = try emptyStateLiteralInstrument().sweep(
            files,
            // The same floor `CadenceRetiredCopyTests` uses for the same tree.
            atLeast: 300,
            // The month agenda, which still spells its own two lines because no other screen
            // says them — so a walk that skipped the iOS tree cannot report this map clean.
            including: "Cadence/iOS/iOSCalendarMonthAgendaViews.swift",
            read: read
        )

        var spellings: [String: [String]] = [:]
        for path in handSpelled {
            for literal in Set(CadenceEmptyStateAudit.literals(in: try read(path))) {
                spellings[literal, default: []].append(path)
            }
        }

        for (sentence, paths) in spellings.sorted(by: { $0.key < $1.key }) where paths.count > 1 {
            let sorted = paths.sorted()
            #expect(
                emptyStateDuplicateAllowance[sentence] == sorted,
                """
                "\(sentence)" is written out in \(sorted). Move it to CadenceEmptyStateCopy and \
                read it from both, or add it to emptyStateDuplicateAllowance with the guard that \
                already holds the pair together.
                """
            )
        }
    }

    /// Exemptions rot, so each one is checked the way `CadenceRetiredCopyTests` checks its own: the
    /// files named must still say the thing, and the suite claimed to be holding them together must
    /// still exist and still name them.
    @Test func theOneAllowedDuplicatePairIsStillHeldTogetherElsewhere() throws {
        for (sentence, paths) in emptyStateDuplicateAllowance {
            #expect(paths.count > 1, "\"\(sentence)\" is allowed as a duplicate but names one file")
            for path in paths {
                let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                #expect(
                    CadenceEmptyStateAudit.literals(in: code).contains(sentence),
                    "\(path) no longer spells \"\(sentence)\" — delete the allowance"
                )
            }
        }

        // The guard the allowance defers to. It asserts both files carry the same three strings,
        // which is a weaker mechanism than a shared constant but is a real one — and if it goes
        // away the allowance has nothing behind it.
        let guardSuite = try CadenceSourceScan.sourceFile("CadenceTests/CadenceDeletedSelectionGuardTests.swift")
        #expect(guardSuite.contains("theMacMissingListStateReusesTheSentenceIOSAlreadyShips"))
        #expect(guardSuite.contains("\"List not found\""))
    }

    /// The detector the sweep turns on, checked against the tree rather than only its fixtures: a
    /// file that reads the shared constants must come back clean, and one that spells its own words
    /// must not.
    @Test func theEmptyStateDetectorSeparatesAConstantFromALiteral() throws {
        let instrument = try emptyStateLiteralInstrument()

        let converged = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/LinksView.swift")
        #expect(converged.contains("CadenceEmptyStateCopy.savedLinksTitle"), "non-vacuity: wrong file")
        #expect(
            instrument.fires(on: converged) == false,
            "a screen reading only shared constants is still counted as hand-spelling"
        )

        let handSpelled = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarMonthAgendaViews.swift")
        #expect(instrument.fires(on: handSpelled))
    }

    /// The reader is scoped to the call, not to the file.
    ///
    /// The mistake this rules out is the cheap spelling of the sweep above — `subtitle: "…"`
    /// matched file-wide — which would count a `TextField` placeholder or a button label as empty-
    /// state copy and make the duplicate map mostly noise.
    @Test func theEmptyStateReaderIgnoresCopyOutsideTheCall() {
        let source = """
        struct Screen: View {
            var body: some View {
                TextField("Search", text: $query)
                Button("Add") { add() }
                EmptyStateView(message: "Nothing here", subtitle: "Add one with +.", icon: "tray")
                Text("A footnote")
            }
        }
        """
        #expect(CadenceEmptyStateAudit.literals(in: source) == ["Nothing here", "Add one with +."])

        // A literal carrying the call's own closing character does not truncate the read.
        let awkward = """
        EmptyStateView(message: "Nothing (yet)", subtitle: "Try again.", icon: "tray")
        """
        #expect(CadenceEmptyStateAudit.literals(in: awkward) == ["Nothing (yet)", "Try again."])

        #expect(CadenceEmptyStateAudit.literals(in: "Text(\"Not an empty state\")").isEmpty)
    }

    // MARK: Copy that names a control that is there

    /// **A Mac is not tapped.** `LinksView` said "Tap + to save a link" and `ListNotesEmptyState`
    /// "Tap + to create one", both inside `#if os(macOS)` files, and both beside a `+` that is
    /// clicked. It is the same defect as T-469's "Add a task above" one step less obvious: the
    /// control is there, but the sentence describes reaching it in a way that surface does not
    /// support.
    ///
    /// Swept over the whole desktop tree rather than the two files it was found in, for the reason
    /// `CadenceRetiredCopyTests` gives: a per-screen guard finds the screen you were looking at.
    @Test func noDesktopCopyAsksForATouchGesture() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence/macOS")
        let read = CadenceSourceScan.strippedSourceReader()

        let offenders = try touchGestureInstrument().sweep(
            files,
            atLeast: 100,
            including: "Cadence/macOS/Views/LinksView.swift",
            read: read
        )
        #expect(
            offenders.isEmpty,
            "\(offenders) tell a Mac user to tap, swipe or pinch. Name the click, or name no gesture."
        )
    }

    /// The touch-verb detector reads copy, not identifiers. `onTapGesture` is on almost every
    /// desktop view in the app, so a detector that matched it would report the whole tree.
    @Test func theTouchGestureDetectorReadsCopyRatherThanIdentifiers() throws {
        let instrument = try touchGestureInstrument()

        let ordinary = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/ListNotesViewSupportViews.swift")
        #expect(ordinary.contains(".onTapGesture"), "non-vacuity: the gesture modifier is gone")
        #expect(instrument.fires(on: ordinary) == false, "the sweep counts .onTapGesture as copy")
    }

    // MARK: "You have nothing" against "your filter matched nothing"

    /// The predicate itself. Both inputs decide the answer, and whitespace is not a search.
    @Test func aNarrowedListIsOneWithASearchOrAFilter() {
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "", filterNarrows: false) == false)
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "", filterNarrows: true))
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "roadmap", filterNarrows: false))
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "roadmap", filterNarrows: true))

        // A field holding only spaces narrows nothing: every matcher in the app trims before
        // comparing, so reporting it as a search would put "No matching goals" on a first run.
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "   ", filterNarrows: false) == false)
        #expect(CadenceEmptyStateCopy.isNarrowedToEmpty(searchText: "\n ", filterNarrows: false) == false)
    }

    /// Both desktop filter bars can hide a row that exists, and both say so — including in their
    /// **default** selection, which is what made this reachable without the reader touching
    /// anything. Goals opens on Active; Habits opens on Due Today.
    @Test func everyDesktopFilterKnowsWhetherItHidesAnything() {
        #expect(GoalStatusFilter.all.narrowsResults == false)
        for filter in [GoalStatusFilter.active, .paused, .done] {
            #expect(filter.narrowsResults, "\(filter.label) hides goals but does not say so")
        }

        #expect(HabitListFilter.all.narrowsResults == false)
        for filter in [HabitListFilter.today, .completed, .streaking] {
            #expect(filter.narrowsResults, "\(filter.label) hides habits but does not say so")
        }

        // The two defaults, named: these are the selections a reader who has touched nothing is
        // under, and they are the ones that were being reported as "you have none".
        #expect(GoalStatusFilter.active.narrowsResults)
        #expect(HabitListFilter.today.narrowsResults)
    }

    /// The three desktop pages ask the predicate rather than the search field.
    ///
    /// Read as source because the branch is a `?:` inside a private computed property of a `View`.
    /// The negative half is the one that matters: `searchText.isEmpty` as the empty state's own
    /// condition is exactly the bug, and it is what a revert looks like.
    @Test func theThreeFilteredDesktopPagesAskTheFilterAndNotJustTheSearchField() throws {
        for path in [
            "Cadence/macOS/Views/GoalsView.swift",
            "Cadence/macOS/Views/GoalTimelineView.swift",
            "Cadence/macOS/Views/HabitsView.swift",
        ] {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            let segments = CadenceEmptyStateAudit.callSegments(in: code)
            #expect(segments.count == 1, "\(path) draws \(segments.count) empty states")
            let empty = try #require(segments.first)

            #expect(
                empty.contains("isNarrowedToEmpty"),
                "\(path)'s empty state does not ask whether a filter is narrowing the page"
            )
            #expect(
                empty.contains("searchText.isEmpty") == false,
                "\(path)'s empty state is back to reading the search field alone"
            )
            #expect(
                code.contains("CadenceEmptyStateCopy.isNarrowedToEmpty("),
                "\(path) re-rolls the narrowing rule instead of asking the shared one"
            )
            #expect(
                code.contains("narrowsResults"),
                "\(path) passes the shared rule something other than its filter"
            )
        }
    }

    /// The phone's reference picker, which had the same defect in its purest form: `isEmpty` was
    /// computed from the **search-filtered** candidates and fed the first-run words, so a query
    /// that missed told a reader with a full library to go and create their first note.
    ///
    /// Source-shape, and stated as such: `Cadence/iOS/` is not compiled by this target.
    @Test func thePhoneReferencePickerTellsAMissedSearchFromAnEmptyLibrary() throws {
        let code = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift")
        )
        #expect(code.contains("struct iOSMarkdownReferencePickerSheet"), "non-vacuity: wrong file")

        // The unfiltered read exists and is asked of the same candidate functions, so a cancelled
        // task still counts as unreferenceable rather than as something the search hid.
        #expect(code.contains("private var hasNothingToOffer: Bool"))
        #expect(code.contains("candidateNotes(from: notes, query: \"\")"))
        #expect(code.contains("candidateTasks(from: tasks, query: \"\")"))

        // And the panel branches on it, on all three arguments.
        let segments = CadenceEmptyStateAudit.callSegments(in: code)
        let picker = try #require(segments.first { $0.contains("kind.emptyTitle") })
        for argument in ["kind.noMatchTitle", "kind.noMatchSubtitle", "kind.noMatchIcon"] {
            #expect(picker.contains(argument), "the picker's empty state never reaches \(argument)")
        }
        #expect(picker.contains("hasNothingToOffer ?"), "the picker's empty state does not branch")

        // The first-run words are still there and still say what they said; the fix adds a second
        // statement rather than replacing the one that was right when the library really is empty.
        // "No tasks yet" here is also `cadenceRetiredCopy`'s one live exemption.
        for firstRun in ["No notes yet", "No tasks yet", "Create a task first, then reference it here."] {
            #expect(code.contains(firstRun), "the picker lost its genuine first-run copy: \(firstRun)")
        }
    }

    // MARK: The constants themselves

    /// The converged pairs, by value, so a "convergence" that quietly adopted the wrong side of a
    /// drift still fails.
    @Test func theConvergedEmptyStateCopySaysTheTrueHalfOfEachPair() {
        // Names no control, because the two surfaces do not carry the same one: a bare `+` on the
        // Mac, a labelled "Add Link" button on the phone.
        #expect(CadenceEmptyStateCopy.savedLinksSubtitle == "Save URLs that belong with this list.")
        #expect(CadenceEmptyStateCopy.savedLinksSubtitle.contains("+") == false)

        // Names one, because here both surfaces really do show a bare `+`.
        #expect(CadenceEmptyStateCopy.listNotesSubtitle == "Add a note with +.")

        // The scoped sentence, not the restatement of the title above it.
        #expect(CadenceEmptyStateCopy.completedTasksSubtitle == "Completed work from this list will collect here.")
        #expect(CadenceEmptyStateCopy.completedTasksSubtitle.contains("Completed tasks will appear here") == false)

        // The Notes page's Events tab, which is the pair that had drifted by a full stop.
        #expect(CadenceEmptyStateCopy.meetingNotesSubtitle == "Create one from a calendar event.")

        // Every shared sentence ends in a full stop. The drift this file exists to stop was a
        // missing one, twice.
        for sentence in [
            CadenceEmptyStateCopy.savedLinksSubtitle,
            CadenceEmptyStateCopy.listNotesSubtitle,
            CadenceEmptyStateCopy.completedTasksSubtitle,
            CadenceEmptyStateCopy.noteActionTasksSubtitle,
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true),
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false),
            CadenceEmptyStateCopy.dailyNotesSubtitle,
            CadenceEmptyStateCopy.weeklyNotesSubtitle,
            CadenceEmptyStateCopy.notepadSubtitle,
            CadenceEmptyStateCopy.meetingNotesSubtitle,
        ] {
            #expect(sentence.hasSuffix("."), "\"\(sentence)\" is a sentence without a full stop")
            #expect(sentence.contains("\n") == false, "an empty state's line is one line")
        }
    }

    // MARK: T-526 — the Lists empty state, against the section it points at

    /// **The clause that names Archived is only said when Archived is drawn.**
    ///
    /// Behavioural: `Cadence/Shared/` is compiled by this target, so these are the values the two
    /// shells will render, not a reading of their source.
    ///
    /// The first-run half is the one the defect was about. The empty state shows only when there
    /// are no *active* lists, and on a fresh or fully emptied store there is nothing archived
    /// either — so the reader most certain to see this sentence was the reader for whom the
    /// section it pointed at does not exist.
    @Test func theListsEmptyStateOnlyOffersArchivedRestoreWhenArchivedIsOnScreen() {
        #expect(
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false)
                == "Create an area or project here."
        )
        #expect(
            CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true)
                == "Create an area or project here, or restore one from Archived."
        )

        // Stated as an absence too, so a rewording that keeps the promise under different words
        // fails rather than passing on a changed literal.
        let firstRun = CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: false)
        #expect(firstRun.localizedCaseInsensitiveContains("archiv") == false)
        #expect(firstRun.localizedCaseInsensitiveContains("restore") == false)

        // And the half that is still true keeps saying it: the fix is a condition, not a deletion.
        #expect(CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: true).contains("Archived"))

        // "here" survives on both, because iOSListCreateButtonsRow is directly above the panel on
        // both shells — that clause was never the false one.
        #expect(firstRun.contains("here"))
    }

    /// **Both shells ask the same predicate that draws the section, and each spells it once.**
    ///
    /// Source-shape, and stated as such: `Cadence/iOS/` is not compiled by this target, so nothing
    /// here executes a `View`. What it can say is the thing the defect was made of — the sentence
    /// and the section were deciding independently. Now `hasArchivedLists` is the single reader of
    /// `archivedAreas`/`archivedProjects` emptiness in each file, and both the section and the
    /// subtitle go through it.
    @Test func bothListShellsAskTheSamePredicateThatDrawsTheArchivedSection() throws {
        for path in [
            "Cadence/iOS/iOSListViews.swift",
            "Cadence/iOS/iOSListsRegularPane.swift",
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let code = CadenceSourceScan.strippingComments(raw)
            #expect(code != raw, "\(path) carries comments and the stripper blanked none of them")

            #expect(
                code.contains("private var hasArchivedLists: Bool"),
                "\(path) has no single predicate for whether Archived is on screen"
            )
            let body = try #require(
                bodyOfComputedProperty("hasArchivedLists", in: code),
                "\(path)'s hasArchivedLists has no body"
            )
            #expect(
                body.contains("!archivedAreas.isEmpty || !archivedProjects.isEmpty"),
                "\(path)'s hasArchivedLists is not the predicate the Archived section was drawn from"
            )

            // The section is drawn from it...
            #expect(
                code.contains("if hasArchivedLists {"),
                "\(path)'s archivedSection no longer branches on the shared predicate"
            )
            // ...and the empty state asks it before offering to restore from it.
            let empty = try #require(
                CadenceEmptyStateAudit.callSegments(in: code)
                    .first { $0.contains("CadenceEmptyStateCopy.activeListsTitle") },
                "\(path) no longer draws the active-lists empty state"
            )
            #expect(
                empty.contains("CadenceEmptyStateCopy.activeListsSubtitle(hasArchived: hasArchivedLists)"),
                "\(path)'s empty state does not pass the section's own predicate"
            )

            // Spelled once. Two copies of this expression is how the sentence and the section came
            // to disagree, so a second one is the regression rather than a style slip.
            #expect(
                CadenceSourceScan.matchCount(
                    #"!archivedAreas\.isEmpty \|\| !archivedProjects\.isEmpty"#,
                    in: code
                ) == 1,
                "\(path) spells the archived predicate more than once again"
            )
        }
    }

    // MARK: T-519 — the Focus detail pane, against the pane beside it

    /// **The Focus detail pane no longer promises tasks that are already next to it.**
    ///
    /// It said "Ready when you are / Today tasks will appear here." for both of the two ways this
    /// branch is reached, and `selectedItem` falls back to `pickItems.first`, so those two are:
    /// nothing is ready — in which case the picker pane beside it is showing the shared focus
    /// empty state and this was a second, differently worded promise about it — or a chosen
    /// subject was deleted while the picker still lists others, in which case today's tasks are
    /// literally on screen to the left.
    ///
    /// Source-shape: `Cadence/iOS/` is not compiled by this target. The retirement of the sentence
    /// itself is enforced app-wide by `cadenceRetiredCopy`, not here.
    @Test func theFocusDetailPaneNeverPromisesTasksThatAreAlreadyBesideIt() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFocusView.swift")
        let code = CadenceSourceScan.strippingComments(raw)
        #expect(code.contains("struct iOSFocusView"), "non-vacuity: wrong file")
        #expect(code != raw, "the stripper blanked no comments in a file that has them")

        // The branch exists and is the thing `case nil` draws.
        #expect(code.contains("private var unselectedDetail: some View"))
        #expect(
            CadenceSourceScan.matchCount(#"case nil:\s+unselectedDetail"#, in: code) == 1,
            "focusDetailPane's nil case no longer draws unselectedDetail"
        )

        let body = try #require(
            bodyOfComputedProperty("unselectedDetail", in: code),
            "unselectedDetail has no body"
        )
        // It branches, on the same list the pane beside it is showing.
        #expect(
            body.contains("if pickItems.isEmpty {"),
            "the placeholder does not ask whether there is anything to select"
        )
        // Empty: the same words the picker pane says, because it is one page and not two.
        #expect(body.contains("CadenceEmptyStateCopy.focusTitle"))
        #expect(body.contains("CadenceEmptyStateCopy.focusSubtitle"))
        // Full: the house pattern for a detail pane with no selection, which Goals and Habits use.
        #expect(body.contains("iOSFeatureEmptyDetail(systemImage: \"timer\", title: \"No session selected\")"))

        // The picker pane really does say the shared sentence at the same moment — the claim that
        // makes the empty half a convergence rather than a new spelling.
        #expect(CadenceSourceScan.matchCount("CadenceEmptyStateCopy.focusTitle", in: code) == 3)

        // And the house pattern is still the house pattern.
        let components = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift")
        )
        #expect(components.contains("struct iOSFeatureEmptyDetail: View"))
        #expect(components.contains("subtitle: \"Select an item from the list.\""))
    }

    /// The text between the braces of `var <name>` — the shape `CadenceSourceScan.functionBody`
    /// cannot read, because a computed property has no parameter list to key on.
    private func bodyOfComputedProperty(_ name: String, in source: String) -> String? {
        guard let declaration = source.range(of: "var \(name)") else { return nil }
        guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else {
            return nil
        }
        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            if source[index] == "{" {
                depth += 1
            } else if source[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[source.index(after: open.lowerBound)..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// Every screen that used to spell one of these now reads it. Counted by *file*, because the
    /// point is that no surface kept a private copy.
    @Test func bothSurfacesReadEachConvergedConstant() throws {
        let readers: [String: [String]] = [
            "savedLinks": ["Cadence/macOS/Views/LinksView.swift", "Cadence/iOS/iOSListSupportViews.swift"],
            "listNotes": ["Cadence/macOS/Views/ListNotesViewSupportViews.swift", "Cadence/iOS/iOSListNotesView.swift"],
            "completedTasks": ["Cadence/macOS/Views/ListDetailSupportViews.swift", "Cadence/iOS/iOSListSupportViews.swift"],
            "noteActionTasks": ["Cadence/macOS/Views/NoteActionReviewSheets.swift", "Cadence/iOS/iOSAINoteActionsViews.swift"],
            "activeLists": ["Cadence/iOS/iOSListViews.swift", "Cadence/iOS/iOSListsRegularPane.swift"],
            "meetingNotes": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
            "notepad": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
            "dailyNotes": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
            "weeklyNotes": ["Cadence/macOS/Views/NotesView.swift", "Cadence/iOS/iOSNotesView.swift"],
        ]

        for (constant, paths) in readers.sorted(by: { $0.key < $1.key }) {
            for path in paths {
                let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                #expect(
                    code.contains("CadenceEmptyStateCopy.\(constant)Title"),
                    "\(path) does not read CadenceEmptyStateCopy.\(constant)Title"
                )
                #expect(
                    code.contains("CadenceEmptyStateCopy.\(constant)Subtitle"),
                    "\(path) does not read CadenceEmptyStateCopy.\(constant)Subtitle"
                )
            }
        }
    }

    /// The two readers used across this suite genuinely differ.
    ///
    /// `CadenceSourceScan.codeOnly` blanks string literals as well as comments, so every literal
    /// assertion here would be permanently green against it. Pinned rather than trusted, because
    /// three separate agents have reached for the wrong one.
    @Test func theCopyReaderKeepsLiteralsAndTheStructuralReaderDoesNot() throws {
        let source = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEmptyStateCopy.swift")
        let stripped = CadenceSourceScan.strippingComments(source)
        let structural = CadenceSourceScan.codeOnly(source)

        #expect(stripped.contains("Save URLs that belong with this list."))
        #expect(structural.contains("Save URLs that belong with this list.") == false)
        #expect(structural.contains("static let savedLinksSubtitle"))
        #expect(stripped != source, "the file carries comments and the stripper blanked none of them")
        #expect(stripped.count == source.count, "the stripper changed the file's length")
    }
}

// MARK: - Fixtures

/// The one sentence still written out in two places, and the guard that holds those two together.
///
/// `CadenceDeletedSelectionGuardTests.theMacMissingListStateReusesTheSentenceIOSAlreadyShips`
/// asserts the Mac's missing-list state and the phone's carry the *same three literals*, chosen
/// deliberately over a shared constant so that editing one and not the other fails. That is a
/// weaker mechanism than `CadenceEmptyStateCopy` — it pins the pair rather than removing the second
/// copy — but it is a real one, and duplicating the enforcement here would give the next reader two
/// places to update. Checked for staleness by
/// `theOneAllowedDuplicatePairIsStillHeldTogetherElsewhere`.
let emptyStateDuplicateAllowance: [String: [String]] = [
    "List not found": [
        "Cadence/iOS/iOSRootSidebar.swift",
        "Cadence/macOS/Views/ListDetailView.swift",
    ],
    "This list may have been archived, deleted, or changed on another device.": [
        "Cadence/iOS/iOSRootSidebar.swift",
        "Cadence/macOS/Views/ListDetailView.swift",
    ],
]

/// Fires on a file that writes an empty state's words at the call site; silent on one that reads
/// them from the shared constants.
///
/// The two witnesses are the nearest possible miss — the same component, the same three arguments,
/// once as literals and once as constants — because that is the pair this detector gets wrong if it
/// gets anything wrong.
private func emptyStateLiteralInstrument() throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "empty-state copy spelled at the call site",
        fires: """
        struct Screen: View {
            var body: some View {
                EmptyStateView(message: "Nothing here", subtitle: "Add one.", icon: "tray")
            }
        }
        """,
        andNotOn: """
        struct Screen: View {
            var body: some View {
                EmptyStateView(
                    message: CadenceEmptyStateCopy.inboxTitle,
                    subtitle: CadenceEmptyStateCopy.inboxSubtitle,
                    icon: "tray"
                )
            }
        }
        """,
        by: { !CadenceEmptyStateAudit.literals(in: CadenceSourceScan.strippingComments($0)).isEmpty }
    )
}

/// Fires on desktop copy that asks for a touch gesture; silent on the gesture *modifier*, which is
/// on nearly every view in the tree.
private func touchGestureInstrument() throws -> CadenceScanInstrument {
    let pattern = "(?i)\\b(tap|taps|tapped|tapping|swipe|swipes|swiped|pinch|pinches)\\b"
    return try CadenceScanInstrument(
        "desktop copy asking for a touch gesture",
        fires: """
        struct Screen: View {
            var body: some View {
                EmptyStateView(message: "No links", subtitle: "Tap + to save a link", icon: "link")
            }
        }
        """,
        andNotOn: """
        struct Screen: View {
            var body: some View {
                Text("Saved Links")
                    .onTapGesture { select() }
                    .highPriorityGesture(TapGesture().onEnded { open() })
            }
        }
        """,
        by: { source in
            CadenceEmptyStateAudit
                .stringLiterals(in: CadenceSourceScan.strippingComments(source))
                .contains { $0.range(of: pattern, options: .regularExpression) != nil }
        }
    )
}
