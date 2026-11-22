// macOS only: `KanbanBoardSupport` lives behind `#if os(macOS)` in `Cadence/macOS/Views/`.
#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **[[T-19021]]: a Mac Kanban card set back down on its OWN column's body stays where it was.**
///
/// Both Mac boards put one `.dropDestination` on the whole column -- header, top padding and the
/// 8pt gap between two cards included -- and answered every card released there with
/// `moveTask(_, before: nil)`, which appends. A card lifted and let go just above the first card,
/// or between two cards, jumped to the bottom of the column it never left. The iOS board refuses
/// that drop (`CadenceKanbanCardDrop.drop`'s `.columnBody` arm) and reaches "last" through an end
/// slot ([[T-16503]]); the Mac columns now ask the same rule through
/// `KanbanBoardSupport.cardLanding` and draw the same slot.
///
/// The rule and the write are asked directly, once per board, with each board's own idea of
/// "this column" -- the section board's open and finished cards of one section, the list board's
/// cards of one list. The wiring of each column is read from source. Neither half is a sighting:
/// what a pointer released over the header or a gap does on screen is for an attended session.
@MainActor
struct CadenceMacKanbanOwnColumnDropTests {

    private final class CountingCommit {
        private(set) var commitCount = 0
        func commit(_ modelContext: ModelContext) throws {
            commitCount += 1
            try modelContext.save()
        }
    }

    private func task(_ title: String, section: String = TaskSectionDefaults.defaultName, order: Int,
                      project: Project? = nil, in modelContext: ModelContext) throws -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = section
        task.order = order
        task.project = project
        modelContext.insert(task)
        try modelContext.save()
        return task
    }

    /// What the column's `dropCard(_:at:)` does: ask the rule, and write only what it allows.
    private func dropCard(
        _ task: AppTask,
        at slot: CadenceKanbanCardDrop.Slot,
        column: [AppTask],
        span: [AppTask],
        listKey: String,
        in modelContext: ModelContext,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() },
        assigning assign: () -> Void = {}
    ) -> Bool {
        guard let landing = KanbanBoardSupport.cardLanding(of: task, at: slot, inColumn: column) else { return false }
        return KanbanBoardSupport.reorder(
            column.sorted(by: TaskOrdering.fallbackPrecedes),
            moving: task,
            before: landing.before,
            spanning: span,
            ofList: listKey,
            in: modelContext,
            commit: commit,
            assigning: assign
        )
    }

    private func titles(_ tasks: [AppTask]) -> [String] {
        tasks.sorted { $0.order < $1.order }.map(\.title)
    }

    // MARK: - The section board (`ListSectionKanbanColumn`)

    /// Red before the fix: D, let go on the strip above A or the gap between two cards, went back
    /// to the bottom with a commit. Now nothing is written and the drop answers `false`.
    @Test func sectionBoardOwnColumnBodyDropWritesNothing() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let a = try task("A", section: "Doing", order: 0, in: modelContext)
        let b = try task("B", section: "Doing", order: 1, in: modelContext)
        let c = try task("C", section: "Doing", order: 2, in: modelContext)
        let finished = try task("Finished", section: "Doing", order: 3, in: modelContext)
        finished.status = .done
        let column = [a, b, c, finished]
        let seam = CountingCommit()

        let key = CadenceTaskDropSupport.containerKey(for: .inbox)
        #expect(!dropCard(a, at: .columnBody, column: column, span: column, listKey: key, in: modelContext, commit: seam.commit))
        #expect(!dropCard(finished, at: .columnBody, column: column, span: column, listKey: key, in: modelContext, commit: seam.commit),
                "a finished card is one of the column's cards too")
        #expect(seam.commitCount == 0, "an own-column body drop committed")
        #expect(titles([a, b, c]) == ["A", "B", "C"], "an own-column body drop moved a card: \(titles([a, b, c]))")
        #expect(a.order == 0)
    }

    /// The end slot is how "last" stays reachable in a card's own column.
    @Test func sectionBoardOwnColumnEndSlotDropMakesTheCardLast() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let a = try task("A", section: "Doing", order: 0, in: modelContext)
        let b = try task("B", section: "Doing", order: 1, in: modelContext)
        let c = try task("C", section: "Doing", order: 2, in: modelContext)
        let column = [a, b, c]

        #expect(dropCard(a, at: .columnEnd, column: column, span: column,
                         listKey: CadenceTaskDropSupport.containerKey(for: .inbox), in: modelContext))
        #expect(titles(column) == ["B", "C", "A"], "the end slot did not put the card last: \(titles(column))")
    }

    /// Cross-column body drops keep appending, refiled under the destination section.
    @Test func sectionBoardBodyDropFromAnotherColumnStillAppends() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let moved = try task("Moved", section: "Backlog", order: 0, in: modelContext)
        let a = try task("A", section: "Doing", order: 1, in: modelContext)
        let b = try task("B", section: "Doing", order: 2, in: modelContext)
        let span = [moved, a, b]

        #expect(dropCard(moved, at: .columnBody, column: [a, b], span: span,
                         listKey: CadenceTaskDropSupport.containerKey(for: .inbox), in: modelContext,
                         assigning: { moved.sectionName = "Doing" }))
        #expect(moved.sectionName == "Doing")
        #expect(titles(span) == ["A", "B", "Moved"])
    }

    // MARK: - The All Tasks list board (`TaskListKanbanColumn`)

    /// Red before the fix: the list board's column appended its own card the same way.
    @Test func listBoardOwnColumnBodyDropWritesNothing() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let project = Project(name: "Garden")
        modelContext.insert(project)
        let a = try task("A", order: 0, project: project, in: modelContext)
        let b = try task("B", order: 1, project: project, in: modelContext)
        let c = try task("C", order: 2, project: project, in: modelContext)
        let column = [a, b, c]
        let seam = CountingCommit()

        #expect(!dropCard(b, at: .columnBody, column: column, span: column,
                          listKey: CadenceTaskDropSupport.containerKey(for: .project(project.id)),
                          in: modelContext, commit: seam.commit))
        #expect(seam.commitCount == 0, "an own-column body drop committed")
        #expect(titles(column) == ["A", "B", "C"], "an own-column body drop moved the card: \(titles(column))")
    }

    @Test func listBoardOwnColumnEndSlotDropMakesTheCardLast() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let project = Project(name: "Garden")
        modelContext.insert(project)
        let a = try task("A", order: 0, project: project, in: modelContext)
        let b = try task("B", order: 1, project: project, in: modelContext)
        let c = try task("C", order: 2, project: project, in: modelContext)
        let column = [a, b, c]

        #expect(dropCard(b, at: .columnEnd, column: column, span: column,
                         listKey: CadenceTaskDropSupport.containerKey(for: .project(project.id)), in: modelContext))
        #expect(titles(column) == ["A", "C", "B"], "the end slot did not put the card last: \(titles(column))")
    }

    @Test func listBoardBodyDropFromAnotherListStillAppends() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let project = Project(name: "Garden")
        modelContext.insert(project)
        let moved = try task("Moved", order: 0, in: modelContext)
        let a = try task("A", order: 1, project: project, in: modelContext)
        let b = try task("B", order: 2, project: project, in: modelContext)

        #expect(dropCard(moved, at: .columnBody, column: [a, b], span: [a, b, moved],
                         listKey: CadenceTaskDropSupport.containerKey(for: .project(project.id)), in: modelContext,
                         assigning: { moved.project = project }))
        #expect(moved.project?.id == project.id)
        #expect(titles([a, b, moved]) == ["A", "B", "Moved"])
    }

    // MARK: - The shared rule

    /// One rule, three slots: a card on itself and an own-column body refuse; the end slot never does.
    @Test func theSharedSlotRuleRefusesOnlyItselfAndItsOwnBody() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let a = try task("A", order: 0, in: modelContext)
        let b = try task("B", order: 1, in: modelContext)

        #expect(CadenceKanbanCardDrop.landing(of: a, at: .card(a), isOwnColumn: true) == nil)
        #expect(CadenceKanbanCardDrop.landing(of: a, at: .card(b), isOwnColumn: true)?.before?.id == b.id)
        #expect(CadenceKanbanCardDrop.landing(of: a, at: .columnBody, isOwnColumn: true) == nil)
        let across = try #require(CadenceKanbanCardDrop.landing(of: a, at: .columnBody, isOwnColumn: false))
        #expect(across.before == nil)
        let own = try #require(CadenceKanbanCardDrop.landing(of: a, at: .columnEnd, isOwnColumn: true))
        #expect(own.before == nil)
    }

    // MARK: - The wiring, read from source

    private func code(_ file: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/\(file)"))
    }

    /// Each Mac column routes its body drop through the rule's `.columnBody`, draws the end slot
    /// under its last open card, and routes the slot through `.columnEnd`.
    @Test func bothMacColumnsAskTheSharedRuleAndDrawTheEndSlot() throws {
        for (file, body) in [
            ("KanbanListColumnView.swift", "private func columnBody(tasks: [AppTask])"),
            ("KanbanSectionColumnView.swift", "private func columnBody(active: [AppTask], completed: [AppTask])")
        ] {
            let source = try code(file)
            let column = try #require(CadenceSourceScan.declarationBody(body, in: source), "\(file)")
            #expect(column.count > 500, "non-vacuity: \(file)'s column body read as \(column.count) characters")
            #expect(CadenceSourceScan.matchCount(#"dropCard\([A-Za-z]+, at: \.columnBody\)"#, in: column) == 1,
                    "\(file)'s column body no longer asks the shared rule")
            #expect(!column.contains("before: nil)"), "\(file)'s column body appends without asking the rule")
            #expect(CadenceSourceScan.matchCount(#"dropCard\([A-Za-z]+, at: \.columnEnd\)"#, in: source) == 1,
                    "\(file)'s end slot does not land at the column's end")
            let drop = try #require(CadenceSourceScan.declarationBody("private func dropCard(", in: source), "\(file)")
            #expect(drop.contains("KanbanBoardSupport.cardLanding(of: task, at: slot, inColumn: tasks)"), "\(file)")
            #expect(drop.contains("moveTask(task, before: landing.before)"), "\(file)")
            #expect(CadenceSourceScan.matchCount(#"KanbanColumnEndDropSlot\("#, in: source) == 1, "\(file) draws no end slot")
        }
        let section = try code("KanbanSectionColumnView.swift")
        #expect(CadenceSourceScan.matchCount(#"if !active\.isEmpty \{\s*columnEndDropSlot\s*\}"#, in: section) == 1,
                "the section column no longer draws its end slot under the last open card")
        let list = try code("KanbanListColumnView.swift")
        #expect(CadenceSourceScan.matchCount(#"if !tasks\.isEmpty \{\s*KanbanColumnEndDropSlot\("#, in: list) == 1,
                "the list column no longer draws its end slot under the last card")
    }
}
#endif
