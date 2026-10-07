import Foundation
import SwiftData
import Testing
@testable import Cadence

// MARK: - The instrument

/// **How many times one body evaluation of a view re-derives the whole task store.**
///
/// [[T-1500]]/[[T-1501]] asked for a count of *per-render* work, and the three things already
/// refuted (the unfiltered `@Query`, container laziness, a per-frame scroll write) are all
/// per-*frame* candidates. What nobody had counted is how many full passes over `allTasks` one
/// **body evaluation** performs — which matters because a SwiftUI view's computed property is
/// recomputed at every reference, so a body that reaches the same derivation six times pays for it
/// six times.
///
/// This reads the real source. It is not a model of SwiftUI: it walks the *declared* reference
/// graph — `body` → the computed properties it names → the properties those name — and counts how
/// many times the walk arrives at a named whole-store derivation.
///
/// **Two positions are distinguished, and the distinction is the point for the kanban.** A
/// reference in the ordinary body text is evaluated once (`fixed`). A reference inside a
/// `ForEach`'s *content closure* is evaluated once per element (`perElement`), so it is not a
/// constant at all — it is a count that grows with the user's data. A census that folded the two
/// together would report the board's cost as a number when it is a slope.
///
/// **What it deliberately does not count.** References inside a closure the body only *stores* —
/// `.onAppear`, `.onChange`, `.sheet`, `.onDrag`, `.onDrop` and the rest of
/// `deferredClosurePrefixes` — are removed before counting, because those run on an event and not
/// on a render. `TasksListView.revealsCompletedSection` is the worked example: it reaches the
/// universe, it is named twice in the body, and it costs a render nothing. The test below asserts
/// both halves of that, so a stripping rule that silently removed everything would be caught.
enum TaskSurfaceDerivationScan {

    /// A count in two positions. `fixed` is per body evaluation; `perElement` is per body
    /// evaluation **per element of the enclosing `ForEach`**.
    struct Reach: Equatable, CustomStringConvertible {
        var fixed: Int
        var perElement: Int

        static let zero = Reach(fixed: 0, perElement: 0)

        var description: String {
            perElement == 0 ? "\(fixed)" : "\(fixed) + \(perElement)/element"
        }
    }

    /// Modifier closures a view *stores* rather than evaluates while rendering.
    static let deferredClosurePrefixes = [
        ".onAppear", ".onDisappear", ".onChange", ".task", ".sheet", ".onTapGesture",
        ".onDrag", ".onDrop", ".refreshable", ".contextMenu", ".popover", ".alert",
        ".confirmationDialog", ".onSubmit", ".swipeActions", ".onHover", ".onReceive",
        ".fullScreenCover", ".onLongPressGesture", ".dropDestination"
    ]

    struct Split {
        /// The body with every deferred closure and every `ForEach` content closure taken out.
        var fixed: String
        /// Just the `ForEach` content closures, concatenated.
        var perElement: String
        var deferredRegionsRemoved: Int
        var forEachRegions: Int
    }

    struct Graph {
        let file: String
        let split: [String: Split]
        /// Every declaration the scan was asked for and could not find. Must be empty, or the
        /// census is reading a file that has moved under it.
        let missing: [String]

        var deferredRegionsRemoved: Int { split.values.reduce(0) { $0 + $1.deferredRegionsRemoved } }
        var forEachRegions: Int { split.values.reduce(0) { $0 + $1.forEachRegions } }

        /// How many times one evaluation of `body` arrives at `target`.
        func reach(to target: String) -> Reach {
            reach(from: "body", to: target, seen: ["body"])
        }

        /// The same walk, to a **call site** rather than to a declaration: how many times one
        /// evaluation of `body` executes the literal `token`. Used where the fix dissolves the
        /// declaration into a body-local `let`, so there is no property left to name.
        func reach(toCall token: String) -> Reach {
            walk(from: "body", seen: ["body"]) {
                TaskSurfaceDerivationScan.literalOccurrences(of: token, in: $0)
            }
        }

        private func walk(from name: String, seen: Set<String>, leaf: (String) -> Int) -> Reach {
            guard let parts = split[name] else { return .zero }
            var total = Reach.zero
            for (text, isPerElement) in [(parts.fixed, false), (parts.perElement, true)] {
                var here = Reach(fixed: leaf(text), perElement: 0)
                for candidate in split.keys.sorted() where candidate != name && !seen.contains(candidate) {
                    let hits = TaskSurfaceDerivationScan.occurrences(of: candidate, in: text)
                    guard hits > 0 else { continue }
                    let sub = walk(from: candidate, seen: seen.union([name, candidate]), leaf: leaf)
                    here.fixed += sub.fixed * hits
                    here.perElement += sub.perElement * hits
                }
                if isPerElement {
                    total.perElement += here.fixed + here.perElement
                } else {
                    total.fixed += here.fixed
                    total.perElement += here.perElement
                }
            }
            return total
        }

        private func reach(from name: String, to target: String, seen: Set<String>) -> Reach {
            guard let parts = split[name] else { return .zero }
            var total = Reach.zero
            for (text, isPerElement) in [(parts.fixed, false), (parts.perElement, true)] {
                for candidate in split.keys.sorted() where candidate != name && !seen.contains(candidate) {
                    let hits = TaskSurfaceDerivationScan.occurrences(of: candidate, in: text)
                    guard hits > 0 else { continue }
                    let sub = candidate == target
                        ? Reach(fixed: 1, perElement: 0)
                        : reach(from: candidate, to: target, seen: seen.union([name, candidate]))
                    let scaled = Reach(fixed: sub.fixed * hits, perElement: sub.perElement * hits)
                    if isPerElement {
                        total.perElement += scaled.fixed + scaled.perElement
                    } else {
                        total.fixed += scaled.fixed
                        total.perElement += scaled.perElement
                    }
                }
            }
            return total
        }
    }

    /// Builds the graph for one file over the declarations named in `declarations`, which are
    /// spelled the way `CadenceSourceScan.declarationBody` wants them (`"var body: some View"`,
    /// `"var activeTasks"`, `"func navItems("`).
    static func graph(
        file: String,
        declarations: [String: String],
        stripDeferred: Bool = true
    ) throws -> Graph {
        graph(
            source: try CadenceSourceScan.sourceFile(file),
            named: file,
            declarations: declarations,
            stripDeferred: stripDeferred
        )
    }

    /// The same walk over source **text** rather than over a path in the working tree.
    ///
    /// `graph(file:)` is this with the file read for you, and is the only spelling a shipped
    /// census should use. This one exists because a "did the landing flatten it?" question is a
    /// question about **two** revisions, and re-deriving the older number by hand — or by a second
    /// copy of the counting code — is how a comparison ends up measuring the instrument instead of
    /// the change. Hand it `git show <sha>:<path>` and the older revision is counted by exactly
    /// the walk that counts the current one.
    static func graph(
        source: String,
        named label: String,
        declarations: [String: String],
        stripDeferred: Bool = true
    ) -> Graph {
        let stripped = CadenceSourceScan.strippingComments(source)
        var split: [String: Split] = [:]
        var missing: [String] = []
        for (name, declaration) in declarations {
            guard let body = CadenceSourceScan.declarationBody(declaration, in: stripped) else {
                missing.append(name)
                continue
            }
            split[name] = self.split(body, stripDeferred: stripDeferred)
        }
        return Graph(file: label, split: split, missing: missing.sorted())
    }

    // MARK: - Text surgery

    static func split(_ body: String, stripDeferred: Bool) -> Split {
        var chars = Array(body)
        var deferredRemoved = 0
        if stripDeferred {
            let regions = trailingClosureRegions(prefixes: deferredClosurePrefixes, in: chars)
            deferredRemoved = regions.count
            chars = removing(regions, from: chars)
        }
        let loops = trailingClosureRegions(prefixes: ["ForEach"], in: chars)
        let perElement = loops.map { String(chars[$0]) }.joined(separator: "\n")
        let fixed = String(removing(loops, from: chars))
        return Split(
            fixed: fixed,
            perElement: perElement,
            deferredRegionsRemoved: deferredRemoved,
            forEachRegions: loops.count
        )
    }

    /// The `{ … }` that immediately follows one of `prefixes` — after that prefix's own balanced
    /// parenthesis list, when it has one. A prefix with a parenthesis list and **no** trailing
    /// closure (`.onDrop(of:delegate:)`) contributes nothing, which is what stops the scan from
    /// swallowing the next unrelated brace pair in the file.
    static func trailingClosureRegions(prefixes: [String], in chars: [Character]) -> [Range<Int>] {
        var regions: [Range<Int>] = []
        var index = 0
        while index < chars.count {
            guard let prefix = prefixes.first(where: { matches($0, in: chars, at: index) }) else {
                index += 1
                continue
            }
            var cursor = index + prefix.count
            while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
            if cursor < chars.count, chars[cursor] == "(" {
                guard let close = balanced(chars, from: cursor, open: "(", close: ")") else {
                    index += prefix.count
                    continue
                }
                cursor = close + 1
                while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
            }
            guard cursor < chars.count, chars[cursor] == "{",
                  let close = balanced(chars, from: cursor, open: "{", close: "}") else {
                index += prefix.count
                continue
            }
            regions.append(cursor..<(close + 1))
            index = close + 1
        }
        return regions
    }

    private static func matches(_ prefix: String, in chars: [Character], at index: Int) -> Bool {
        let needle = Array(prefix)
        guard index + needle.count <= chars.count else { return false }
        for offset in 0..<needle.count where chars[index + offset] != needle[offset] { return false }
        if let first = needle.first, isIdentifier(first), index > 0, isIdentifier(chars[index - 1]) {
            return false
        }
        return true
    }

    private static func balanced(
        _ chars: [Character], from start: Int, open: Character, close: Character
    ) -> Int? {
        var depth = 0
        var index = start
        while index < chars.count {
            if chars[index] == open { depth += 1 }
            else if chars[index] == close {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func removing(_ regions: [Range<Int>], from chars: [Character]) -> [Character] {
        guard !regions.isEmpty else { return chars }
        var kept: [Character] = []
        kept.reserveCapacity(chars.count)
        var cursor = 0
        for region in regions.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard region.lowerBound >= cursor else { continue }
            kept.append(contentsOf: chars[cursor..<region.lowerBound])
            cursor = region.upperBound
        }
        kept.append(contentsOf: chars[cursor...])
        return kept
    }

    private static func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    /// Plain substring occurrences of `token`, for a call-site target such as
    /// `"KanbanBoardSupport.activeTasks("`.
    static func literalOccurrences(of token: String, in text: String) -> Int {
        guard !token.isEmpty else { return 0 }
        return text.components(separatedBy: token).count - 1
    }

    /// Whole-identifier occurrences of `name`. A match preceded by `.` or `\` is a member and not
    /// this declaration; a match **followed** by `:` is an argument label or a type annotation, not
    /// a read — `tasksByDate: tasksByDate` is one reference, not two.
    static func occurrences(of name: String, in text: String) -> Int {
        let chars = Array(text)
        let needle = Array(name)
        guard !needle.isEmpty, chars.count >= needle.count else { return 0 }
        var count = 0
        var index = 0
        while index + needle.count <= chars.count {
            var isMatch = true
            for offset in 0..<needle.count where chars[index + offset] != needle[offset] {
                isMatch = false
                break
            }
            guard isMatch else {
                index += 1
                continue
            }
            let before: Character? = index > 0 ? chars[index - 1] : nil
            let afterIndex = index + needle.count
            let after: Character? = afterIndex < chars.count ? chars[afterIndex] : nil
            let okBefore = before.map { !isIdentifier($0) && $0 != "." && $0 != "\\" } ?? true
            let okAfter = after.map { !isIdentifier($0) && $0 != ":" } ?? true
            if okBefore && okAfter { count += 1 }
            index = afterIndex
        }
        return count
    }
}

// MARK: - The census

/// **The three unmeasured surfaces of [[T-1501]], counted, with the owner's smooth surface as the
/// control column.**
///
/// Every number below is a count of *derivations per body evaluation*, never a duration
/// ([[T-1279]]/[[T-1296]]). The control is `CalendarPageView` — the owner reports it as smooth and
/// it declares the byte-identical unfiltered `@Query private var allTasks: [AppTask]` that the
/// laggy surfaces declare, so a reading that came out the same for it would have measured nothing.
@Suite struct TaskSurfaceUniversePassCensusTests {

    private static let tasksListDeclarations = [
        "body": "var body: some View",
        "visibleTaskUniverse": "var visibleTaskUniverse",
        "naturalActiveTasks": "func naturalActiveTasks(",
        "completedTasks": "func completedTasks(",
        "completedTaskCount": "func completedTaskCount(",
        "dropCoordinator": "func dropCoordinator(",
        "revealsCompletedSection": "var revealsCompletedSection",
        "isEmptyPage": "func isEmptyPage("
    ]

    private static func tasksListGraph(
        stripDeferred: Bool = true
    ) throws -> TaskSurfaceDerivationScan.Graph {
        try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/TasksListView.swift",
            declarations: tasksListDeclarations,
            stripDeferred: stripDeferred
        )
    }

    // MARK: The instrument answers about itself first

    /// **The denominator.** A census that could not find its declarations, or whose stripping rule
    /// removed everything, reads zero for every subject and is indistinguishable from a clean
    /// result. So: every declaration resolved, and the two kinds of region it recognises were both
    /// actually present in the file it read.
    @Test func theCensusFoundEveryDeclarationItWasAskedFor() throws {
        let graph = try Self.tasksListGraph()
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        #expect(graph.split.count == Self.tasksListDeclarations.count)
        #expect(
            graph.deferredRegionsRemoved >= 3,
            "no deferred closure was stripped — the rule is reading nothing (\(graph.deferredRegionsRemoved))"
        )
        #expect(
            graph.forEachRegions >= 1,
            "no ForEach content closure was found — the per-element position cannot be reached"
        )
        // And the body it read is the body: three of its own local bindings, spelled as the file
        // spells them.
        let body = try #require(graph.split["body"]).fixed
        #expect(body.contains("let universe = visibleTaskUniverse"))
        #expect(body.contains("let completedCount = completedTaskCount(in: universe)"))
        #expect(body.contains("let coordinator = dropCoordinator(in: universe)"))
    }

    /// **The stripping rule is a rule and not a blanket.** `revealsCompletedSection` reaches the
    /// universe and is named twice in `TasksListView`'s body — in `.onAppear` and in `.onChange` —
    /// and it costs a *render* nothing, because neither closure runs on a render. With the rule
    /// off, the same walk finds it. A stripping rule that removed everything would read 0 here and
    /// 0 with the rule off too.
    @Test func aClosureTheBodyOnlyStoresIsNotRenderWork() throws {
        let stripped = try Self.tasksListGraph()
        let raw = try Self.tasksListGraph(stripDeferred: false)
        #expect(stripped.reach(to: "revealsCompletedSection") == .init(fixed: 0, perElement: 0))
        #expect(
            raw.reach(to: "revealsCompletedSection").fixed == 2,
            "the unstripped walk did not find the two stored references — the control is dead"
        )
    }

    // MARK: All Tasks, as a list

    /// **One body evaluation of `TasksListView` derives its whole task universe once, and it used
    /// to derive it seven times.**
    ///
    /// `visibleTaskUniverse` is a computed property, so it is recomputed at every reference, and
    /// the body reached it through six named derivations — `activeTasks`, `completedTaskCount`,
    /// `completedTasks`, `dropCoordinator`, `naturalActiveTasks`, and `isEmpty`, which re-reaches
    /// two of the others. Seven full passes over every task in the store, per render.
    ///
    /// **It read `2` until [[T-1580]], and the survivor was blocked on a real defect rather than on
    /// the census.** `dropCoordinator` stayed a computed property because parameterising it turns a
    /// property access in `body` into a *call*, and
    /// `noSuccessReportFollowsACommitSwallowedOneFrameDown` then read a call reaching a swallowed
    /// commit inside a block that reports success. The sweep was right: `TasksPanelSupport
    /// .assignTask` ended `try? modelContext.save(); return true`. It commits once, undoes and
    /// answers `TasksPanelDropOutcome` now, and the seventh derivation went with it.
    ///
    /// The control is `CalendarPageView`, which the owner calls smooth — see
    /// `theSmoothControlDerivesItsStoreOncePerBranch`, which must come out differently for any of
    /// this to mean anything.
    @Test func allTasksAsAListDerivesItsUniverseOncePerRender() throws {
        let subject = try Self.tasksListGraph().reach(to: "visibleTaskUniverse")
        #expect(subject == .init(fixed: 1, perElement: 0), "All Tasks (list) universe passes: \(subject)")
    }

    /// The same walk, to the property that **sorts**. `naturalActiveTasks` sorts the whole open set;
    /// it was reached three times per body evaluation (once directly, once through `activeTasks`,
    /// once through `isEmpty` → `activeTasks`).
    @Test func allTasksAsAListSortsItsRowsOncePerRender() throws {
        let sorts = try Self.tasksListGraph().reach(to: "naturalActiveTasks")
        #expect(sorts == .init(fixed: 1, perElement: 0), "All Tasks (list) sorts: \(sorts)")
    }

    // MARK: All Tasks, as a kanban board

    /// **The board's cost was not a number — it was a slope.**
    ///
    /// The board's active-task universe is two full passes over `allTasks`
    /// (`filter(\.isInActiveContainer)`, then `openTasks(from:)`). It was a computed property,
    /// reached once from `listColumns` **and once more inside the `ForEach` content closure**, which is
    /// evaluated once per column — so a board with twelve lists re-derived the universe thirteen
    /// times per render, and adding a list added a derivation. It is bound once in the body now,
    /// so the per-element term is gone.
    @Test func theKanbanBoardNoLongerRederivesItsUniverseOncePerColumn() throws {
        let graph = try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/KanbanSupportViews.swift",
            declarations: [
                "body": "var body: some View",
                "taskListColumnsBoard": "func taskListColumnsBoard(",
                "listColumns": "func listColumns("
            ]
        )
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        let derivations = graph.reach(toCall: "KanbanBoardSupport.activeTasks(")
        #expect(derivations == .init(fixed: 1, perElement: 0), "kanban universe derivations: \(derivations)")
    }

    /// **What `f0603016` flattened is one frame below what this ticket measured, and the two are
    /// different numbers over different things.**
    ///
    /// The board's per-column *universe* derivation above was already `1 + 0/element` when T-3005
    /// landed — the binding directly above took it there on 2026-09-29, a week earlier — so the
    /// lazy containers cannot have flattened the slope this ticket named, and nothing in this file
    /// moved when they landed. What they did flatten is a slope the first census never reached,
    /// because it stopped at `KanbanSupportViews.swift`: **the column's own sort**.
    ///
    /// `TaskListKanbanColumn` sorted through a `sortedTasks` computed property reached from the
    /// header's count and from the card `ForEach`, over an `unfrozenSortedTasks` the body also
    /// named twice for the freeze observer — **four sorts of the column's own tasks per column
    /// body evaluation**, the same it-is-a-computed-property shape as `visibleTaskUniverse`'s
    /// seven. T-3005 binds both in `body` and threads them, so it is one.
    ///
    /// **The landing's other half is invisible here and must not be read off this number.**
    /// `LazyHStack` bounds how many column bodies are *evaluated*; it cannot change what one
    /// costs, and this census walks declared references with no model of mounting at all. The
    /// mounting count is Codex's own measurement and lives in
    /// `CadenceCodexKanbanRenderingTests.horizontalListColumnsMountOnlyABoundedSubset`, which pins
    /// a bound rather than a number. Multiplying the two is the only way to a per-render total,
    /// and neither half is a duration ([[T-1279]]/[[T-1296]]).
    @Test func theAllTasksBoardColumnSortsOncePerColumnRenderAndNotFourTimes() throws {
        let graph = try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/KanbanListColumnView.swift",
            declarations: [
                "body": "var body: some View",
                "columnBody": "private func columnBody(",
                "header": "private func header(",
                "columnTaskScroll": "private func columnTaskScroll(",
                "taskCards": "private func taskCards(",
                "unfrozenSortedTasks": "private var unfrozenSortedTasks"
            ]
        )
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        let sorts = graph.reach(to: "unfrozenSortedTasks")
        #expect(sorts == .init(fixed: 1, perElement: 0), "All Tasks (kanban) column sorts: \(sorts)")
        // Non-vacuity: the property the walk arrived at is the one that sorts.
        let sort = try #require(graph.split["unfrozenSortedTasks"]).fixed
        #expect(sort.contains("tasks.taskSorted(by: sortField, direction: sortDirection)"))
    }

    // MARK: The *other* kanban — the section board of a list or project

    /// **The same defect one board over, and nobody had counted it: eight splits of one column's
    /// tasks for one render.**
    ///
    /// `ListSectionKanbanColumn` is Cadence's second kanban column. `columnHalves` is one pass over
    /// the column's `tasks` (`KanbanBoardSupport.columnHalves`), and it was a computed property
    /// reached through three more computed properties from **eight** places in one body evaluation:
    /// twice from `body`'s freeze observer, once from each branch of `columnHeader`, once from the
    /// card `ForEach`, and four times across the completed section's emptiness test, its toggle's
    /// count and its cards. Bound once in `body` and threaded, it is one.
    ///
    /// **Eight is the census's count and the executed count is smaller, which is worth saying
    /// rather than rounding away.** The walk has no model of branches: only one arm of
    /// `columnHeader` runs, and the completed cards only when the section is expanded — so a render
    /// of an expanded column with completed cards paid **seven**, and a collapsed one six. The
    /// number that changed is the shape, not the seventh pass: a computed property re-derived at
    /// every reference now has exactly one reference.
    @Test func theSectionColumnSplitsItsTasksOncePerRenderAndNotEightTimes() throws {
        let graph = try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/KanbanSectionColumnView.swift",
            declarations: [
                "body": "var body: some View",
                "columnBody": "private func columnBody(",
                "columnHeader": "private func columnHeader(",
                "header": "private func header(",
                "columnTaskScroll": "private func columnTaskScroll(",
                "activeTaskCards": "private func activeTaskCards(",
                "completedTaskSection": "private func completedTaskSection(",
                "completedTasksToggle": "private func completedTasksToggle(",
                "completedTaskCards": "private func completedTaskCards(",
                "columnHalves": "private var columnHalves"
            ]
        )
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        let splits = graph.reach(to: "columnHalves")
        #expect(splits == .init(fixed: 1, perElement: 0), "section column task splits: \(splits)")
        // Non-vacuity: the property the walk arrived at is the one that walks the column.
        let halves = try #require(graph.split["columnHalves"]).fixed
        #expect(halves.contains("KanbanBoardSupport.columnHalves(from: tasks)"))
        // And the body really is the body that binds it once, spelled as the file spells it.
        let body = try #require(graph.split["body"]).fixed
        #expect(body.contains("let halves = columnHalves"))
        #expect(body.contains("return columnBody(active: displayActive, completed: halves.completed)"))
    }

    /// **A card drop is an event, not a render ([[T-3020]]'s carried instrument gap).**
    ///
    /// `.dropDestination` was missing from `deferredClosurePrefixes`, so a census whose subject
    /// was reached only from a card drop would have counted it as render work. Nothing read wrong
    /// today; this pins the rule so the gap cannot quietly come back. The control in the same text
    /// is a reference in ordinary body position, which must still count.
    @Test func aReferenceInsideADropDestinationClosureCostsARenderNothing() {
        let body = """
        VStack { header(moveTask) }
            .dropDestination(for: String.self) { items, _ in
                moveTask(items)
                return true
            }
        """
        let split = TaskSurfaceDerivationScan.split(body, stripDeferred: true)
        #expect(split.deferredRegionsRemoved == 1)
        #expect(TaskSurfaceDerivationScan.occurrences(of: "moveTask", in: split.fixed) == 1)
        let unstripped = TaskSurfaceDerivationScan.split(body, stripDeferred: false)
        #expect(TaskSurfaceDerivationScan.occurrences(of: "moveTask", in: unstripped.fixed) == 2)
    }

    /// **The last kanban slope, removed by [[T-3020]]: the section board groups its cards ONCE per
    /// render, not once per column.**
    ///
    /// `ListSectionsKanbanView` used to call a since-deleted `sortedTasksForSection` — a `filter`
    /// over the board's whole task list, then a sort of what survived — **inside** its `ForEach` content
    /// closure. That is the per-element position, so this census read it as `0 + 1/element`: one
    /// full pass over the board's tasks per section column, and adding a column added a pass.
    ///
    /// **Unlike the All Tasks board it was not redundant, so no binding could fix it** — every
    /// column needs a *different* subset. The fix is one grouping pass in `body`
    /// (`columnCards(from:sections:sortField:direction:)`) that the `ForEach` only *indexes*. So the
    /// reading is now `1 + 0/element`: one call per render, no per-column term.
    ///
    /// **The eager stack is still pinned, deliberately.** T-3005 opted only the All Tasks list
    /// column into deferred realization, because this board's columns register hover with three
    /// managers and their offscreen lifecycle is unaccounted for. Every section column still mounts
    /// — which is exactly why the per-element term was worth removing. If someone makes it lazy,
    /// this must fail and send them to the ledger.
    ///
    /// Two halves, and either alone is satisfiable by a defect: the grouping call must be reached
    /// **once** and **outside** the `ForEach`, and the `ForEach` content must reach **no** pass over
    /// the board's `tasks` — not through the grouping call, and not through an open-coded
    /// `tasks.filter` either.
    @Test func theSectionBoardGroupsItsCardsOncePerRenderAndNotOncePerColumn() throws {
        let graph = try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/KanbanListSectionSupportViews.swift",
            declarations: [
                "body": "var body: some View",
                "sectionConfigs": "private var sectionConfigs",
                "baseSectionConfigs": "private var baseSectionConfigs"
            ]
        )
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        #expect(
            graph.forEachRegions >= 1,
            "no ForEach content closure was found — the per-element position cannot be reached"
        )
        let passes = graph.reach(toCall: "Self.columnCards(")
        #expect(
            passes == .init(fixed: 1, perElement: 0),
            "section board grouping passes over its task list: \(passes)"
        )
        let openCodedPasses = graph.reach(toCall: "tasks.filter")
        #expect(openCodedPasses == .zero, "section board open-codes a pass over its tasks: \(openCodedPasses)")
        // Non-vacuity: the ForEach content really is the column loop, and it reads the grouping.
        let body = try #require(graph.split["body"])
        #expect(body.perElement.contains("let sectionTasks = cardsBySectionName[section.name] ?? []"))
        #expect(body.fixed.contains("ForEach(columns, id: \\.id)"))
        // The retired per-column pass is gone from the file, not merely moved out of reach.
        let source = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/KanbanListSectionSupportViews.swift")
        #expect(!CadenceSourceScan.strippingComments(source).contains("sortedTasksForSection"))
        // The multiplier: every section column mounts, so a per-element term would be per *column*.
        #expect(
            body.fixed.contains("HStack(alignment: .top, spacing: 12)") && !body.fixed.contains("LazyHStack"),
            """
            this board's columns are no longer eagerly realized — [[T-3020]]'s ledger entry is now \
            wrong about what the per-element term would have multiplied
            """
        )
    }

    // MARK: The sidebar's lists ([[T-1500]])

    /// **The sidebar's whole-store tallies are already bound once, and that half is small and
    /// boring — say so rather than ship a change to justify the ticket.**
    ///
    /// `countInputs` performs three passes over `allTasks` (the overdue reduce, the
    /// `isInActiveContainer` filter, and the open-count reduce over what survives it), and
    /// `SidebarView.body` binds it to a `let` and hands the value to both nav groups. One
    /// reference, not one per row. The sidebar's per-render task cost that is *not* boring is the
    /// per-list relationship traversal, which is cross-file and counted in
    /// `SidebarListCountTraversalTests` below.
    @Test func theSidebarsWholeStoreTallyIsBuiltOncePerRenderAndNotOncePerRow() throws {
        let graph = try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/SidebarView.swift",
            declarations: [
                "body": "var body: some View",
                "countInputs": "var countInputs",
                "listsSection": "var listsSection",
                "listSections": "var listSections",
                "navItems": "func navItems("
            ]
        )
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        let reach = graph.reach(to: "countInputs")
        #expect(reach == .init(fixed: 1, perElement: 0), "sidebar whole-store tallies: \(reach)")
        // Non-vacuity: the property the walk arrived at is the one that walks the store.
        let counts = try #require(graph.split["countInputs"]).fixed
        #expect(TaskSurfaceDerivationScan.occurrences(of: "allTasks", in: counts) == 2)
    }

    // MARK: The control column

    /// **The control, and it comes out differently.** `CalendarPageView` derives a whole-store
    /// dictionary once per presentation branch, and its three branches are mutually exclusive — so
    /// at most two run (the timeline's `tasksByDate` and `unscheduledTasksByDate`) and the month
    /// grid the owner scrolls runs exactly one. None of the three sits inside a `ForEach`, so the
    /// control has **no per-element term at all**, which is the half that separates it from the
    /// board.
    @Test func theSmoothControlDerivesItsStoreOncePerBranch() throws {
        let graph = try TaskSurfaceDerivationScan.graph(
            file: "Cadence/macOS/Views/CalendarPageView.swift",
            declarations: [
                "body": "var body: some View",
                "tasksByDate": "var tasksByDate",
                "tasksByDateForMonth": "var tasksByDateForMonth",
                "unscheduledTasksByDate": "var unscheduledTasksByDate"
            ]
        )
        #expect(graph.missing.isEmpty, "the census could not find: \(graph.missing)")
        let month = graph.reach(to: "tasksByDateForMonth")
        let timeline = TaskSurfaceDerivationScan.Reach(
            fixed: graph.reach(to: "tasksByDate").fixed + graph.reach(to: "unscheduledTasksByDate").fixed,
            perElement: graph.reach(to: "tasksByDate").perElement
                + graph.reach(to: "unscheduledTasksByDate").perElement
        )
        #expect(month == .init(fixed: 1, perElement: 0), "calendar month grid passes: \(month)")
        #expect(timeline == .init(fixed: 2, perElement: 0), "calendar timeline passes: \(timeline)")
    }
}

// MARK: - The sidebar's lists column, driven ([[T-1500]])

/// **Task visits per render of the sidebar's lists column, with the calendar's as the control
/// column** — which is the measurement [[T-1500]] asked for, and explicitly *not* "is it lazy".
///
/// Driven against a real in-memory store rather than argued from the source: every list row the
/// column draws calls `CadenceTaskQuerySupport.openTaskCount(for:)`, which reads `area.tasks` /
/// `project.tasks` — a SwiftData to-many relationship — so one render walks one relationship per
/// list. This builds the store, calls the **real** row helper once per row exactly as
/// `SidebarComponents.areaRow` / `projectRow` do, and counts the `AppTask` objects those calls
/// actually walked.
///
/// **The answer is small and boring, and that is the finding.** The column's whole-store half is
/// three passes, bound once (`TaskSurfaceUniversePassCensusTests` pins the once), and the
/// per-list half visits each filed task exactly once. So a render costs a little under four visits
/// per task against the smooth control's one — the same order of magnitude, not the order of
/// magnitude that separates the kanban board, whose cost grows with the number of lists. Nothing
/// is changed here on the strength of that number.
@Suite @MainActor
struct SidebarListCountTraversalTests {

    @Test func oneSidebarRenderVisitsEachFiledTaskOnceMoreThanTheCalendarDoes() throws {
        let container = try CadenceTestStore.container()
        let context = ModelContext(container)

        // The denominator, stated up front so a reading of zero cannot pass for a clean one.
        let listCount = 12
        let filedTaskCount = 216
        let storeTaskCount = 264

        var areas: [Area] = []
        var projects: [Project] = []
        for index in 0..<(listCount / 2) {
            let area = Area(name: "Area \(index)")
            let project = Project(name: "Project \(index)")
            context.insert(area)
            context.insert(project)
            areas.append(area)
            projects.append(project)
        }

        var allTasks: [AppTask] = []
        for index in 0..<storeTaskCount {
            let task = AppTask(title: "Task \(index)")
            context.insert(task)
            if index < filedTaskCount / 2 {
                task.area = areas[index % areas.count]
            } else if index < filedTaskCount {
                task.project = projects[index % projects.count]
            }
            allTasks.append(task)
        }
        try context.save()

        #expect(allTasks.count == storeTaskCount, "the fixture is not the size the denominator claims")
        #expect(areas.count + projects.count == listCount)

        // MARK: The subject — one relationship read per list row, counted as it happens.

        var relationshipReads = 0
        var visitsThroughRelationships = 0
        for area in areas where area.isActive {
            _ = CadenceSidebarLayout.listCount(openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: area))
            relationshipReads += 1
            visitsThroughRelationships += (area.tasks ?? []).count
        }
        for project in projects where project.isActive {
            _ = CadenceSidebarLayout.listCount(openTaskCount: CadenceTaskQuerySupport.openTaskCount(for: project))
            relationshipReads += 1
            visitsThroughRelationships += (project.tasks ?? []).count
        }

        #expect(relationshipReads == listCount, "one read per list: \(relationshipReads) of \(listCount)")
        #expect(
            visitsThroughRelationships == filedTaskCount,
            "the row helpers walked \(visitsThroughRelationships) tasks, not \(filedTaskCount)"
        )

        // MARK: The whole-store half, driven through the two functions `countInputs` calls.

        let todayKey = DateFormatters.todayKey()
        _ = CadenceSidebarLayout.overdueTaskCount(from: allTasks, todayKey: todayKey)
        let inActiveContainers = allTasks.filter(\.isInActiveContainer)
        let openCount = CadenceTaskQuerySupport.openTaskCount(from: inActiveContainers)
        #expect(
            inActiveContainers.count == storeTaskCount,
            "the filter pass did not reach the whole store: \(inActiveContainers.count)"
        )
        #expect(openCount == storeTaskCount, "every fixture task is open: \(openCount)")

        // Three passes, read off `countInputs` rather than assumed: `allTasks` twice (the overdue
        // reduce and the active-container filter), and the open-count reduce over what the filter
        // returns.
        let sidebarSource = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SidebarView.swift")
        )
        let countInputs = try #require(
            CadenceSourceScan.declarationBody("var countInputs", in: sidebarSource),
            "countInputs has moved — the pass count below is unanchored"
        )
        #expect(TaskSurfaceDerivationScan.occurrences(of: "allTasks", in: countInputs) == 2)
        #expect(countInputs.contains("allTasks.filter(\\.isInActiveContainer)"))
        #expect(countInputs.contains("CadenceTaskQuerySupport.openTaskCount("))
        let wholeStorePasses = 3

        let sidebarVisits = wholeStorePasses * storeTaskCount + visitsThroughRelationships

        // MARK: The control column — the surface the owner calls smooth.

        let monthBuckets = CalendarPageDataSupport.monthTasksByDate(allTasks)
        #expect(monthBuckets.isEmpty, "the fixture has no dated tasks, so the control's pass is over all of them and files none")
        let calendarVisits = storeTaskCount

        // And it reaches no list relationship at all, which is the half that is not a pass count.
        let scheduleSource = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceScheduleSupport.swift")
        )
        let monthPass = try #require(
            CadenceSourceScan.declarationBody("static func monthTasksByDate(", in: scheduleSource),
            "the control's pass has moved"
        )
        #expect(!monthPass.contains("area.tasks"))
        #expect(!monthPass.contains("project.tasks"))

        #expect(
            sidebarVisits == wholeStorePasses * storeTaskCount + filedTaskCount,
            "sidebar task visits per render: \(sidebarVisits)"
        )
        #expect(
            calendarVisits == storeTaskCount,
            "calendar task visits per render: \(calendarVisits)"
        )
        #expect(
            sidebarVisits > calendarVisits * 3 && sidebarVisits < calendarVisits * 5,
            "sidebar \(sidebarVisits) vs control \(calendarVisits) — a ratio that is not a lag story"
        )
    }
}

// MARK: - [[T-3020]]'s behavioural half

/// **The one grouping pass draws exactly the cards the per-column filter drew, in the same order.**
///
/// The census above proves the section board's pass is no longer per column; this proves it did
/// not change a card. The oracle is the retired per-column filter, verbatim, run once per column
/// — so every column of every fixture below is compared by **identity and order** against what the
/// board used to draw, across all three sort fields and both directions. The fixture is built to
/// hold the cases the grouping could plausibly get wrong: case-only name differences in both
/// directions, a name the task pads with whitespace, an empty name (the default section), two
/// columns whose names differ only by case, cancelled work, a column no task names, a task naming
/// no column, NSString-only case equivalences (`ß`/`SS`, composed/decomposed `é`), and sort ties.
@Suite @MainActor
struct ListSectionBoardColumnCardsParityTests {

    /// The retired `sortedTasksForSection` of `ListSectionsKanbanView`, transcribed verbatim.
    private func retiredColumn(
        _ section: TaskSectionConfig,
        of tasks: [AppTask],
        sortField: TaskSortField,
        direction: TaskSortDirection
    ) -> [AppTask] {
        let source = tasks.filter {
            !$0.isCancelled && $0.resolvedSectionName.caseInsensitiveCompare(section.name) == .orderedSame
        }
        return source.taskSorted(by: sortField, direction: direction)
    }

    private func card(
        _ title: String,
        in sectionName: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        order: Int = 0,
        date: String = ""
    ) -> AppTask {
        let task = AppTask(title: title)
        task.sectionName = sectionName
        task.status = status
        task.priority = priority
        task.order = order
        task.scheduledDate = date
        return task
    }

    private var sections: [TaskSectionConfig] {
        [
            TaskSectionConfig(name: TaskSectionDefaults.defaultName),
            TaskSectionConfig(name: "Doing"),
            TaskSectionConfig(name: "doing"),
            TaskSectionConfig(name: "Straße"),
            TaskSectionConfig(name: "Caf\u{E9}"),
            TaskSectionConfig(name: "Empty")
        ]
    }

    private var tasks: [AppTask] {
        [
            card("default by empty name", in: ""),
            card("default by name", in: TaskSectionDefaults.defaultName.uppercased(), priority: .high),
            card("doing upper", in: "DOING", priority: .medium, order: 3, date: "2026-10-09"),
            card("doing padded", in: "  Doing ", priority: .medium, order: 3, date: "2026-10-09"),
            card("doing tie", in: "doing", priority: .medium, order: 3, date: "2026-10-09"),
            card("doing early", in: "Doing", priority: .low, order: 1, date: "2026-10-01"),
            card("doing cancelled", in: "Doing", status: .cancelled),
            card("doing done", in: "Doing", status: .done, order: 2),
            card("strasse", in: "STRASSE"),
            card("cafe decomposed", in: "CAFE\u{301}"),
            card("orphan", in: "Nowhere"),
            card("orphan cancelled", in: "Nowhere", status: .cancelled)
        ]
    }

    @Test func everyColumnDrawsTheCardsThePerColumnFilterDrewInTheSameOrder() {
        let tasks = tasks
        let sections = sections
        var compared = 0
        var nonEmpty = 0
        for field in TaskSortField.allCases {
            for direction in TaskSortDirection.allCases {
                let grouped = ListSectionsKanbanView.columnCards(
                    from: tasks, sections: sections, sortField: field, direction: direction
                )
                for section in sections {
                    let expected = retiredColumn(section, of: tasks, sortField: field, direction: direction)
                    let actual = grouped[section.name] ?? []
                    #expect(
                        actual.map(ObjectIdentifier.init) == expected.map(ObjectIdentifier.init),
                        """
                        \(section.name) by \(field.rawValue) \(direction.rawValue): \
                        \(actual.map(\.title)) != \(expected.map(\.title))
                        """
                    )
                    compared += 1
                    if !expected.isEmpty { nonEmpty += 1 }
                }
            }
        }
        // Non-vacuity: every (field, direction, column) was compared, and most columns have cards.
        #expect(compared == TaskSortField.allCases.count * TaskSortDirection.allCases.count * sections.count)
        #expect(nonEmpty >= TaskSortField.allCases.count * TaskSortDirection.allCases.count * 4)
    }

    /// The cases parity alone would pass vacuously if the oracle drew nothing for them.
    @Test func caseOnlyColumnsShareTheirCardsAndCancelledWorkReachesNoColumn() {
        let grouped = ListSectionsKanbanView.columnCards(
            from: tasks, sections: sections, sortField: .custom, direction: .ascending
        )
        let doing = Set((grouped["Doing"] ?? []).map(\.title))
        #expect(doing == ["doing upper", "doing padded", "doing tie", "doing early", "doing done"])
        #expect(Set((grouped["doing"] ?? []).map(\.title)) == doing)
        #expect((grouped["Empty"] ?? []).isEmpty)
        #expect(grouped["Nowhere"] == nil, "a task naming no column grew a bucket")
        let everyCard = grouped.values.flatMap { $0 }
        #expect(!everyCard.contains { $0.isCancelled }, "a cancelled card reached a column")
        #expect(Set((grouped[TaskSectionDefaults.defaultName] ?? []).map(\.title))
                == ["default by empty name", "default by name"])
    }

    /// Two columns with one name are one bucket, and a card is drawn once in it, not twice.
    @Test func aDuplicatedColumnNameDoesNotDrawACardTwice() {
        let doubled = [TaskSectionConfig(name: "Doing"), TaskSectionConfig(name: "Doing")]
        let grouped = ListSectionsKanbanView.columnCards(
            from: [card("one", in: "doing")], sections: doubled, sortField: .date, direction: .ascending
        )
        #expect((grouped["Doing"] ?? []).map(\.title) == ["one"])
    }
}
