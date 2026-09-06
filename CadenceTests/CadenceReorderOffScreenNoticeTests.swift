import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-1077: the notice a drop that landed off screen shows, and the drops it stays silent for.**
///
/// [[T-1054]] asked whether a row drag should be offered at all under a non-custom sort, on the
/// premise that the dragged row always springs back there. `CadenceRowReorderSequenceTests`
/// refuted that premise behaviourally — a drag *between rows that tie on the active sort key* lands
/// exactly where it was dropped, because `TaskOrdering.precedes` falls through to
/// `fallbackPrecedes` on a tie and `fallbackPrecedes`'s first key is `order`. So the condition is
/// per **drop**, not per sort, and the accepted outcome is a notice on the subset that really is
/// invisible rather than a refusal of the whole gesture.
///
/// **The asymmetry is the test.** Every assertion below comes in a pair: the same surface, the same
/// sort, one drop inside a tie band and one across a boundary. A predicate that fired on everything
/// would pass half of them and a predicate that fired on nothing would pass the other half; only
/// the intended one passes both. `CadenceRowReorderSequenceTests`'s three drops are reused verbatim
/// as the fixture, so what the notice claims and what the store did are measured over one arrangement.
@MainActor
struct CadenceReorderOffScreenNoticeTests {

    private func container() throws -> ModelContainer {
        try CadenceTestStore.container()
    }

    private func notice(
        _ droppedTitle: String,
        onto targetTitle: String,
        in tasks: [AppTask],
        field: TaskSortField,
        direction: TaskSortDirection
    ) throws -> String? {
        let dropped = try #require(tasks.first { $0.title == droppedTitle })
        let target = try #require(tasks.first { $0.title == targetTitle })
        return CadenceReorderVisibility.notice(
            droppedID: dropped.id,
            targetID: target.id,
            in: tasks,
            sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: field, direction: direction) }
        )
    }

    /// The four-task board `CadenceRowReorderSequenceTests` drags on: custom order Alpha…Delta,
    /// date order the exact reverse, so every pair is on a different date.
    private func datedBoard(in modelContext: ModelContext) throws -> [AppTask] {
        let dates = ["2026-09-04", "2026-09-03", "2026-09-02", "2026-09-01"]
        let tasks = ["Alpha", "Bravo", "Charlie", "Delta"].enumerated().map { index, title -> AppTask in
            let task = AppTask(title: title)
            task.order = index
            task.scheduledDate = dates[index]
            modelContext.insert(task)
            return task
        }
        try modelContext.save()
        return tasks
    }

    private func band(
        in modelContext: ModelContext,
        _ configure: (AppTask) -> Void = { _ in }
    ) throws -> [AppTask] {
        let tasks = ["Alpha", "Bravo", "Charlie"].enumerated().map { index, title -> AppTask in
            let task = AppTask(title: title)
            task.order = index
            configure(task)
            modelContext.insert(task)
            return task
        }
        try modelContext.save()
        return tasks
    }

    // MARK: - The one sentence

    /// **The notice is not the refusal, and cannot become it by accident.**
    ///
    /// Two separate claims, because two separate things would be wrong. Reusing
    /// `CadenceOrderCommit.failureNotice` would tell a user whose drop the store *accepted* that
    /// nothing was saved and nothing was moved — both false. And a sentence naming a sort mode
    /// would be wrong on one of the two surfaces that draw it, because they label the same
    /// arrangement `Custom` (`TaskSortField`) and `List Order` (`CadenceTaskSortMode`).
    @Test func theOffScreenSentenceClaimsTheMoveRatherThanARefusal() {
        #expect(CadenceReorderVisibility.offScreenNotice == "Moved, but this sort doesn't show it there.")
        #expect(CadenceReorderVisibility.offScreenNotice != CadenceOrderCommit.failureNotice)
        #expect(!CadenceReorderVisibility.offScreenNotice.contains("Nothing was moved"))
        #expect(!CadenceReorderVisibility.offScreenNotice.contains("Couldn't"))
        for label in [TaskSortField.custom.rawValue, CadenceTaskSortMode.listOrder.title] {
            #expect(
                !CadenceReorderVisibility.offScreenNotice.contains(label),
                "the sentence names \(label), which is this arrangement's name on only one of the two surfaces"
            )
        }
    }

    // MARK: - Silent inside a tie band, and only there

    /// **The pair that is the whole ticket, under `.date`.** Same board, same sort, two drops.
    ///
    /// Undated rows all share `TaskOrdering.noDateSortKey`, so a drag among them is fully visible
    /// and says nothing. A drag across a date boundary is the one that springs back, and it is the
    /// only one that speaks.
    @Test func onlyADropAcrossADateBoundarySpeaks() throws {
        let modelContext = ModelContext(try container())
        let undated = try band(in: modelContext)
        #expect(undated.taskSorted(by: .date, direction: .ascending).map(\.title) == ["Alpha", "Bravo", "Charlie"])
        #expect(try notice("Charlie", onto: "Alpha", in: undated, field: .date, direction: .ascending) == nil)

        let dated = try datedBoard(in: ModelContext(try container()))
        #expect(
            try notice("Alpha", onto: "Delta", in: dated, field: .date, direction: .ascending)
                == CadenceReorderVisibility.offScreenNotice
        )
    }

    /// **The same pair under `.priority`, where ties are the common case rather than the edge one.**
    /// Four ranks, so any list longer than four rows has a band.
    @Test func onlyADropAcrossAPriorityBandSpeaks() throws {
        let modelContext = ModelContext(try container())
        let oneBand = try band(in: modelContext) { $0.priority = .high }
        #expect(try notice("Charlie", onto: "Bravo", in: oneBand, field: .priority, direction: .descending) == nil)

        let mixed = try band(in: ModelContext(try container())) { task in
            task.priority = task.title == "Charlie" ? .low : .high
        }
        #expect(
            try notice("Charlie", onto: "Bravo", in: mixed, field: .priority, direction: .descending)
                == CadenceReorderVisibility.offScreenNotice
        )
        #expect(
            try notice("Alpha", onto: "Bravo", in: mixed, field: .priority, direction: .descending) == nil,
            "the two rows still sharing a rank are still a band"
        )
    }

    /// **Under `.custom` nothing is ever off screen**, for the structural reason rather than by a
    /// special case: `.custom`'s whole comparison *is* the fallback, so `sortKeyOrder` answers
    /// `.tie` for every pair. Asserted over the board whose every pair differs on date *and*
    /// priority, so a predicate reading the wrong field would fail here.
    @Test func underTheCustomSortEveryDropIsVisible() throws {
        let modelContext = ModelContext(try container())
        let tasks = try datedBoard(in: modelContext)
        for dropped in tasks {
            for target in tasks where target.id != dropped.id {
                #expect(
                    try notice(dropped.title, onto: target.title, in: tasks, field: .custom, direction: .ascending) == nil
                )
            }
        }
    }

    /// **A timed drop inside one day is still across a boundary**, because `.date`'s key does not
    /// stop at the day: timed work leads untimed work, and earlier leads later. The two rows here
    /// share a `scheduledDate` and would tie on a predicate that only compared the day.
    @Test func theDateKeyRunsPastTheDayItself() throws {
        let modelContext = ModelContext(try container())
        let tasks = try band(in: modelContext) { $0.scheduledDate = "2026-09-06" }
        let nineAM = try #require(tasks.first { $0.title == "Alpha" })
        nineAM.scheduledStartMin = 540
        try modelContext.save()

        #expect(
            try notice("Charlie", onto: "Alpha", in: tasks, field: .date, direction: .ascending)
                == CadenceReorderVisibility.offScreenNotice
        )
        #expect(
            try notice("Charlie", onto: "Bravo", in: tasks, field: .date, direction: .ascending) == nil,
            "the two untimed rows on one day are a band"
        )
    }

    // MARK: - Today, which has a key the sort chip cannot reach

    /// **On Today a drop can be off screen under `List Order` too**, because
    /// `CadenceTaskQuerySupport.todaySortKeyOrder` leads with the date-bucket rank and no chip
    /// setting removes it. This is the reason the notice takes a comparator rather than a
    /// `TaskSortField`, and the reason it is asked per drop.
    @Test func todaysBucketRankMakesEvenAListOrderDropOffScreen() throws {
        let modelContext = ModelContext(try container())
        let todayKey = "2026-09-06"
        let dueToday = AppTask(title: "Due")
        dueToday.dueDate = todayKey
        dueToday.order = 0
        let doToday = AppTask(title: "Do")
        doToday.scheduledDate = todayKey
        doToday.order = 1
        let alsoDoToday = AppTask(title: "Also Do")
        alsoDoToday.scheduledDate = todayKey
        alsoDoToday.order = 2
        for task in [dueToday, doToday, alsoDoToday] { modelContext.insert(task) }
        try modelContext.save()

        let tasks = [dueToday, doToday, alsoDoToday]
        #expect(dueToday.todayRank(todayKey: todayKey) != doToday.todayRank(todayKey: todayKey), "non-vacuity")

        func todayNotice(_ dropped: AppTask, onto target: AppTask) -> String? {
            CadenceReorderVisibility.notice(
                droppedID: dropped.id,
                targetID: target.id,
                in: tasks,
                sortKeyOrder: {
                    CadenceTaskQuerySupport.todaySortKeyOrder($0, $1, todayKey: todayKey, sortMode: .listOrder)
                }
            )
        }

        #expect(todayNotice(alsoDoToday, onto: dueToday) == CadenceReorderVisibility.offScreenNotice)
        #expect(todayNotice(alsoDoToday, onto: doToday) == nil, "two rows in one bucket are a band under List Order")
    }

    /// **`.dueDate` and `.newest` are the two modes with no `TaskSortField` twin**, so their keys
    /// are spelled only in `CadenceTaskQuerySupport.sortKeyOrder` and only this measures them.
    @Test func theModeOnlyVocabularyCarriesItsOwnKeysToo() throws {
        let modelContext = ModelContext(try container())
        let tasks = try band(in: modelContext)
        let alpha = try #require(tasks.first { $0.title == "Alpha" })
        let bravo = try #require(tasks.first { $0.title == "Bravo" })
        let charlie = try #require(tasks.first { $0.title == "Charlie" })
        alpha.dueDate = "2026-09-06"
        try modelContext.save()

        #expect(CadenceTaskQuerySupport.sortKeyOrder(charlie, alpha, sortMode: .dueDate) != .tie)
        #expect(CadenceTaskQuerySupport.sortKeyOrder(charlie, bravo, sortMode: .dueDate) == .tie)
        // `createdAt` is stamped per task, so no two of these were made at the same instant.
        #expect(CadenceTaskQuerySupport.sortKeyOrder(charlie, alpha, sortMode: .newest) != .tie)
    }

    // MARK: - The split that made the predicate possible

    /// **`sortKeyOrder` and the comparator it was split out of still agree, pair by pair.**
    ///
    /// The predicate is only worth anything if `.tie` really is the condition under which the
    /// display falls through to `order`. That is a claim about the *shape* of `precedes`, and it is
    /// measured here rather than read off the source: over every ordered pair of a probe set and
    /// every field/direction, recomposing `.before`/`.after`/`.tie` + `fallbackPrecedes` must give
    /// back exactly what `precedes` answers.
    @Test func theSplitKeyRecomposesIntoTheComparatorExactly() throws {
        let modelContext = ModelContext(try container())
        let probes = try probeSet(in: modelContext)
        var ties = 0
        var ordered = 0

        for lhs in probes {
            for rhs in probes {
                for field in TaskSortField.allCases {
                    for direction in TaskSortDirection.allCases {
                        let key = TaskOrdering.sortKeyOrder(lhs, rhs, field: field, direction: direction)
                        let recomposed: Bool
                        switch key {
                        case .before: recomposed = true
                        case .after: recomposed = false
                        case .tie: recomposed = TaskOrdering.fallbackPrecedes(lhs, rhs)
                        }
                        #expect(
                            recomposed == TaskOrdering.precedes(lhs, rhs, field: field, direction: direction),
                            "\(field)/\(direction) disagrees on \(lhs.title) vs \(rhs.title)"
                        )
                        if key == .tie { ties += 1 } else { ordered += 1 }
                    }
                }
            }
        }
        #expect(ties > 0 && ordered > 0, "non-vacuity: the probe set produced \(ties) ties and \(ordered) ordered pairs")
    }

    /// The same recomposition over the other vocabulary, including the `sectionNames` argument
    /// `.listOrder` reads and Today's leading bucket rank.
    @Test func theModeKeyRecomposesIntoItsComparatorExactly() throws {
        let modelContext = ModelContext(try container())
        let probes = try probeSet(in: modelContext)
        let sectionNames = ["Backlog", "Doing"]
        var ties = 0
        var ordered = 0

        for lhs in probes {
            for rhs in probes {
                for mode in CadenceTaskSortMode.allCases {
                    for names in [nil, sectionNames] as [[String]?] {
                        let key = CadenceTaskQuerySupport.sortKeyOrder(lhs, rhs, sortMode: mode, sectionNames: names)
                        let recomposed: Bool
                        switch key {
                        case .before: recomposed = true
                        case .after: recomposed = false
                        case .tie: recomposed = TaskOrdering.fallbackPrecedes(lhs, rhs)
                        }
                        #expect(
                            recomposed == CadenceTaskQuerySupport.sortTasks(lhs, rhs, sortMode: mode, sectionNames: names),
                            "\(mode) disagrees on \(lhs.title) vs \(rhs.title)"
                        )
                        if key == .tie { ties += 1 } else { ordered += 1 }
                    }
                }
            }
        }
        #expect(ties > 0 && ordered > 0, "non-vacuity: \(ties) ties and \(ordered) ordered pairs")
    }

    /// A tie-heavy set that still differs on every key either comparator reads: two dates, one of
    /// them timed, two priorities, two due dates, two section names, and duplicates of each so the
    /// tie branch is reached.
    private func probeSet(in modelContext: ModelContext) throws -> [AppTask] {
        var tasks: [AppTask] = []
        for (index, spec) in [
            ("Undated none", "", -1, TaskPriority.none, "", TaskSectionDefaults.defaultName),
            ("Undated none twin", "", -1, TaskPriority.none, "", TaskSectionDefaults.defaultName),
            ("Undated high", "", -1, TaskPriority.high, "2026-09-06", "Doing"),
            ("Dated untimed", "2026-09-06", -1, TaskPriority.low, "", "Backlog"),
            ("Dated untimed twin", "2026-09-06", -1, TaskPriority.low, "", "Backlog"),
            ("Dated timed", "2026-09-06", 540, TaskPriority.medium, "2026-09-07", "Doing"),
            ("Later dated", "2026-09-09", 60, TaskPriority.high, "2026-09-06", "Backlog")
        ].enumerated() {
            let task = AppTask(title: spec.0)
            task.scheduledDate = spec.1
            task.scheduledStartMin = spec.2
            task.priority = spec.3
            task.dueDate = spec.4
            task.sectionName = spec.5
            task.order = index % 3
            modelContext.insert(task)
            tasks.append(task)
        }
        try modelContext.save()
        return tasks
    }

    // MARK: - The three surfaces that draw it

    /// **Every surface that renumbers rows from a drop sets, clears and draws the notice.**
    ///
    /// The set-and-clear is pinned as one expression for the reason
    /// `CadenceReorderCommitSurfaceTests.everySurfaceNamesARefusedReorderInTheOneSharedSentence`
    /// gives about the refusal sentence: a site that only sets it leaves a stale line up over a
    /// later drop that landed in plain sight, and a site that only clears it never speaks.
    ///
    /// **`reordered ?` and not `reordered ? nil :`** — this is the opposite arm from the refusal
    /// line directly above it at each site, and that asymmetry is the assertion. A drop the store
    /// refused moved nothing, so it cannot also have moved somewhere off screen.
    @Test func everyRowDropSurfaceReportsAnOffScreenLanding() throws {
        var reporting = 0
        for path in [
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/macOS/Views/TasksListView.swift",
            "Cadence/macOS/Views/ListDetailComponents.swift"
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(
                !source.contains("\"Moved, but this sort"),
                "\(path) retypes the off-screen sentence instead of reading it"
            )
            #expect(
                source.contains("reorderOffScreenNotice = reordered ? CadenceReorderVisibility.notice("),
                "\(path) does not ask, on a landed drop, whether the row is visible"
            )
            #expect(
                source.contains(") : nil"),
                "\(path) never clears the off-screen notice, so a stale line outlives its drop"
            )
            #expect(
                source.contains("CadenceInlineNotice(text: reorderOffScreenNotice, tone: .informational)"),
                "\(path) sets a notice nothing draws, or draws it as a failure"
            )
            reporting += 1
        }
        #expect(reporting == 3, "expected three row-drop surfaces, checked \(reporting)")
    }

    /// **The informational tone is not red**, which is the whole reason the component was split.
    /// `Theme.red` is this app's failure colour and nothing failed here.
    @Test func theInformationalToneIsNotTheFailureColour() {
        #expect(CadenceInlineNotice.Tone.informational.color != CadenceInlineNotice.Tone.failure.color)
        #expect(CadenceInlineNotice.Tone.failure.color == Theme.red)
        #expect(CadenceInlineNotice.Tone.informational.color == Theme.dim)
    }

    /// **The failure notice is the same component, not a near-copy of it.** If it grew its own
    /// `Text` stack back the two would drift on font, weight and the dismissal affordance.
    @Test func theFailureNoticeIsTheSharedComponent() throws {
        let source = try CadenceCommitSurfaceScan.scanned("Cadence/Shared/Components/CadenceInlineFailureNotice.swift")
        #expect(source.contains("CadenceInlineNotice(text: text, tone: .failure, onDismiss: onDismiss)"))
        #expect(!source.contains("Text(text)"), "the failure notice spells its own sentence again")
    }

    /// **An id the surface cannot resolve says nothing.** A drop whose row is not in the sequence
    /// handed to the notice is one the surface knows nothing about, and a sentence about where that
    /// row went would be a guess.
    @Test func anUnresolvableDropSaysNothing() throws {
        let modelContext = ModelContext(try container())
        let tasks = try datedBoard(in: modelContext)
        let alpha = try #require(tasks.first { $0.title == "Alpha" })
        #expect(
            CadenceReorderVisibility.notice(
                droppedID: alpha.id,
                targetID: UUID(),
                in: tasks,
                sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: .date, direction: .ascending) }
            ) == nil
        )
        #expect(
            CadenceReorderVisibility.notice(
                droppedID: UUID(),
                targetID: alpha.id,
                in: tasks,
                sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: .date, direction: .ascending) }
            ) == nil
        )
    }

    // MARK: - The notice and the store agree

    /// **End to end, over the drop `CadenceRowReorderSequenceTests` proves springs back.** The
    /// notice fires, the store took the move, and the visible sequence is unchanged — all three at
    /// once, which is the state the sentence describes.
    @Test func theNoticeFiresOnTheDropThatReallyDoesSpringBack() throws {
        let modelContext = ModelContext(try container())
        let tasks = try datedBoard(in: modelContext)
        let displayed = tasks.taskSorted(by: .date, direction: .ascending)
        #expect(displayed.map(\.title) == ["Delta", "Charlie", "Bravo", "Alpha"])

        let dropped = try #require(tasks.first { $0.title == "Alpha" })
        let target = try #require(tasks.first { $0.title == "Delta" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )

        #expect(
            tasks.taskSorted(by: .date, direction: .ascending).map(\.title) == ["Delta", "Charlie", "Bravo", "Alpha"],
            "non-vacuity: the row no longer springs back, so there is nothing to notice"
        )
        #expect(
            tasks.taskSorted(by: .custom, direction: .ascending).map(\.title) == ["Bravo", "Charlie", "Alpha", "Delta"],
            "and `order` did change — Alpha moved in the custom arrangement, where nothing on screen shows it"
        )
        #expect(
            try notice("Alpha", onto: "Delta", in: displayed, field: .date, direction: .ascending)
                == CadenceReorderVisibility.offScreenNotice
        )
    }

    /// The mirror: the drop that stays put says nothing, and the store agrees it moved.
    @Test func theNoticeStaysSilentOnTheDropThatStaysPut() throws {
        let modelContext = ModelContext(try container())
        let tasks = try band(in: modelContext)
        let displayed = tasks.taskSorted(by: .date, direction: .ascending)
        let dropped = try #require(tasks.first { $0.title == "Charlie" })
        let target = try #require(tasks.first { $0.title == "Alpha" })
        #expect(
            TasksPanelSupport.reorderTask(
                droppedID: dropped.id,
                targetID: target.id,
                scopeTasks: displayed,
                modelContext: modelContext
            )
        )

        #expect(tasks.taskSorted(by: .date, direction: .ascending).map(\.title) == ["Charlie", "Alpha", "Bravo"])
        #expect(try notice("Charlie", onto: "Alpha", in: displayed, field: .date, direction: .ascending) == nil)
    }

    // MARK: - T-1085: the two card drops

    private func cardNotice(
        _ droppedTitle: String,
        before targetTitle: String?,
        in tasks: [AppTask],
        field: TaskSortField,
        direction: TaskSortDirection,
        columnOrder: [AppTask]? = nil
    ) throws -> String? {
        let dropped = try #require(tasks.first { $0.title == droppedTitle })
        let target = try targetTitle.map { title in try #require(tasks.first { $0.title == title }) }
        return CadenceReorderVisibility.cardDropNotice(
            dropped: dropped,
            before: target,
            inColumnOrder: (columnOrder ?? tasks).sorted { $0.order < $1.order },
            sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: field, direction: direction) }
        )
    }

    /// **The same asymmetry the row half is measured by, on a card.** One board, one sort, two
    /// drops: across a date boundary and inside a tie band. A predicate that fired on everything
    /// passes the first and a predicate that fired on nothing passes the second.
    @Test func aCardDroppedOnAnotherCardAsksTheSameQuestionARowDoes() throws {
        let modelContext = ModelContext(try container())
        let dated = try datedBoard(in: modelContext)
        #expect(
            try cardNotice("Alpha", before: "Delta", in: dated, field: .date, direction: .ascending)
                == CadenceReorderVisibility.offScreenNotice
        )
        #expect(try cardNotice("Alpha", before: "Delta", in: dated, field: .custom, direction: .ascending) == nil)

        let tied = try band(in: modelContext)
        #expect(try cardNotice("Charlie", before: "Alpha", in: tied, field: .date, direction: .ascending) == nil)
    }

    /// **A drop on the column itself has no card to be measured against, so it borrows the last
    /// one.** `KanbanBoardSupport` renumbers a `before: nil` drop to the end of the column's
    /// `order`, so what the user is shown is *the bottom of this column* — and that claim is true
    /// exactly when the card ties with whatever is currently last.
    ///
    /// The pair is the assertion: under `.date` on a board whose date order is the reverse of its
    /// custom order, dropping Alpha on the column bottom cannot show it at the bottom; under
    /// `.custom` it can. Same drop, same array, opposite answers.
    @Test func aDropOnTheColumnItselfIsMeasuredAgainstTheCardCurrentlyLast() throws {
        let modelContext = ModelContext(try container())
        let dated = try datedBoard(in: modelContext)
        #expect(
            try cardNotice("Alpha", before: nil, in: dated, field: .date, direction: .ascending)
                == CadenceReorderVisibility.offScreenNotice
        )
        #expect(try cardNotice("Alpha", before: nil, in: dated, field: .custom, direction: .ascending) == nil)

        // **And it is the *last* card it reads, not the first**, which is a different assertion and
        // needs a column where those two disagree: Alpha is dated, Bravo and Charlie are not, so
        // under `.date` the bottom of the column is a tie band of two. Dropping Bravo there really
        // does put it at the bottom and says nothing; reading the *first* card instead would
        // compare it against Alpha's date and speak.
        let mixed = try band(in: modelContext)
        let onlyDatedCard = try #require(mixed.first { $0.title == "Alpha" })
        onlyDatedCard.scheduledDate = "2026-09-04"
        try modelContext.save()
        #expect(try cardNotice("Bravo", before: nil, in: mixed, field: .date, direction: .ascending) == nil)
        #expect(
            try cardNotice("Alpha", before: nil, in: mixed, field: .date, direction: .ascending)
                == CadenceReorderVisibility.offScreenNotice,
            "non-vacuity: this column can produce the sentence at all"
        )
    }

    /// **A column with nothing else in it says nothing.** Not a sentence about an empty column: a
    /// card that is the only thing in the sequence is at the bottom of it by definition, whatever
    /// the sort. Both spellings of "nothing else" are covered — an empty `columnOrder`, and one
    /// holding only the dropped card, which is what a same-column drop on the column background
    /// hands in.
    @Test func aCardWithNothingToLandBesideSaysNothing() throws {
        let modelContext = ModelContext(try container())
        let dated = try datedBoard(in: modelContext)
        let alpha = try #require(dated.first { $0.title == "Alpha" })
        for columnOrder in [[], [alpha]] {
            #expect(
                CadenceReorderVisibility.cardDropNotice(
                    dropped: alpha,
                    before: nil,
                    inColumnOrder: columnOrder,
                    sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: .date, direction: .ascending) }
                ) == nil
            )
        }
    }

    /// **A card refiled from another column is not in the destination column, and that is the half
    /// most likely to land somewhere the sort will not show.** This is why `cardDropNotice` takes
    /// the `AppTask` and not an id: an id lookup against `columnOrder` would answer `nil` on every
    /// cross-column drop, and the surface would be silent precisely where it has most to say.
    @Test func aCardArrivingFromAnotherColumnIsStillAnswered() throws {
        let modelContext = ModelContext(try container())
        let dated = try datedBoard(in: modelContext)
        let incoming = try #require(dated.first { $0.title == "Alpha" })
        let destination = dated.filter { $0.title != "Alpha" }
        #expect(!destination.contains { $0.id == incoming.id }, "non-vacuity: the card really is elsewhere")
        #expect(
            CadenceReorderVisibility.cardDropNotice(
                dropped: incoming,
                before: nil,
                inColumnOrder: destination.sorted { $0.order < $1.order },
                sortKeyOrder: { TaskOrdering.sortKeyOrder($0, $1, field: .date, direction: .ascending) }
            ) == CadenceReorderVisibility.offScreenNotice
        )
    }

    /// **The section board's key leads with the completed/active split, and no sort chip removes
    /// it** — the same shape as Today's bucket rank in the row half (T-1077). A section column
    /// draws active cards, then the toggle, then completed ones, so an active card dropped onto a
    /// completed one lands in the other stack under **every** sort the board offers, `.custom`
    /// included — where `TaskOrdering.sortKeyOrder` answers `.tie` for every pair by construction
    /// and would have been silent.
    ///
    /// The pair below is that claim exactly: the same drop, read through the two keys.
    @Test func theSectionBoardsKeyLeadsWithTheHalfTheCardIsDrawnIn() throws {
        let modelContext = ModelContext(try container())
        let tasks = try band(in: modelContext)
        let active = try #require(tasks.first { $0.title == "Alpha" })
        let finished = try #require(tasks.first { $0.title == "Charlie" })
        finished.status = .done
        finished.completedAt = Date()
        try modelContext.save()
        #expect(CadenceTaskQuerySupport.isFinishedTask(finished))
        #expect(!CadenceTaskQuerySupport.isFinishedTask(active))

        for field in TaskSortField.allCases {
            #expect(
                KanbanBoardSupport.cardSortKeyOrder(active, finished, field: field, direction: .ascending) == .before,
                "\(field) loses the completed/active split, which no chip removes"
            )
            #expect(
                TaskOrdering.sortKeyOrder(active, finished, field: .custom, direction: .ascending) == .tie,
                "non-vacuity: the sort field alone really does tie here"
            )
        }

        #expect(
            CadenceReorderVisibility.cardDropNotice(
                dropped: active,
                before: finished,
                inColumnOrder: tasks.sorted { $0.order < $1.order },
                sortKeyOrder: { KanbanBoardSupport.cardSortKeyOrder($0, $1, field: .custom, direction: .ascending) }
            ) == CadenceReorderVisibility.offScreenNotice
        )
        // Two active cards under `.custom` still say nothing: the split is a lead key, not a
        // second reason to speak.
        let bravo = try #require(tasks.first { $0.title == "Bravo" })
        #expect(
            CadenceReorderVisibility.cardDropNotice(
                dropped: bravo,
                before: active,
                inColumnOrder: tasks.sorted { $0.order < $1.order },
                sortKeyOrder: { KanbanBoardSupport.cardSortKeyOrder($0, $1, field: .custom, direction: .ascending) }
            ) == nil
        )
    }

    /// The source half, matching `everyRowDropSurfaceReportsAnOffScreenLanding` for the two card
    /// surfaces — and asserting the thing that made them a separate ticket: **the notice does not
    /// go through the failure slot.** `ListSectionKanbanColumn` funnels four different refusals
    /// into `columnFailureNotice`, and a fifth arm there would have put a sentence claiming the
    /// move into a slot `CadenceKanbanColumnLifecycleSurfaceTests` pins as the refusal's.
    @Test func everyCardDropSurfaceReportsAnOffScreenLanding() throws {
        var reporting = 0
        for path in [
            "Cadence/macOS/Views/KanbanListColumnView.swift",
            "Cadence/macOS/Views/KanbanSectionColumnView.swift"
        ] {
            let source = try CadenceCommitSurfaceScan.scanned(path)
            #expect(source.contains("private func moveTask("), "non-vacuity: wrong file read")
            #expect(
                !source.contains("\"Moved, but this sort"),
                "\(path) retypes the off-screen sentence instead of reading it"
            )
            #expect(
                source.contains("reorderOffScreenNotice = reordered ? CadenceReorderVisibility.cardDropNotice("),
                "\(path) does not ask, on a landed drop, whether the card is visible"
            )
            #expect(
                source.contains(") : nil"),
                "\(path) never clears the off-screen notice, so a stale line outlives its drop"
            )
            #expect(
                !source.contains("reorderFailureNotice = reorderOffScreenNotice")
                    && !source.contains("columnFailureNotice: reorderOffScreenNotice"),
                "\(path) reports a landed drop through the refusal slot"
            )
            reporting += 1
        }
        #expect(reporting == 2, "expected two card-drop surfaces, checked \(reporting)")

        // Drawn, on the informational tone, by both columns' headers. The list board's column
        // owns its header detail; the section board's goes through `KanbanColumnHeader`.
        let list = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanListColumnView.swift")
        #expect(list.contains("CadenceInlineNotice(text: reorderOffScreenNotice, tone: .informational)"))
        let support = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanColumnSupportViews.swift")
        #expect(support.contains("CadenceInlineNotice(text: offScreenNotice, tone: .informational)"))
        let section = try CadenceCommitSurfaceScan.scanned("Cadence/macOS/Views/KanbanSectionColumnView.swift")
        #expect(section.contains("offScreenNotice: reorderOffScreenNotice"))
    }
}
