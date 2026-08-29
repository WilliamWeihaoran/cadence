import Foundation
import Testing

/// T-272: macOS Goals' **timeline** presentation had a route to Edit and no route to Attach List,
/// at every width, since before T-250 — the roadmap never had an inspector column to lose, so this
/// was not that ticket's fallout and not something T-271's width gate could reach either.
///
/// **The fix composes with T-271 rather than adding a second route.** `GoalInspectorSheet` and its
/// `.sheet(isPresented: $showGoalDetail)` are already installed on `GoalsView.body`, which wraps
/// *both* presentations; only the mission branch ever spent them. So the timeline needed a row/bar
/// action and nothing else: `onEditGoal` became `onOpenGoal`, wired to the same
/// `select(_:showsInspector:)` the cards call, with a literal `false` because the Gantt has no
/// column to select into at any width. Edit did not go anywhere — it is a button inside
/// `GoalInspectorView` — so the double-click now reaches a superset of what it used to.
///
/// These are source-scanning assertions because the thing being pinned is a *route*: which closure
/// a row is handed, and whether it is the shared one. There is no value to compute and a SwiftUI
/// tap gesture is not callable from a test. They follow `Cadence/Shared/AGENTS.md` —
/// comments stripped, exact counts rather than `contains`, and a non-vacuity test below so a path
/// mismatch cannot make the zero-counts pass against empty strings.
struct CadenceGoalTimelineRouteTests {

    private static let goalsView = "Cadence/macOS/Views/GoalsView.swift"
    private static let timelineView = "Cadence/macOS/Views/GoalTimelineView.swift"
    private static let timelineSupport = "Cadence/macOS/Views/GoalTimelineSupportViews.swift"
    private static let timelineBar = "Cadence/macOS/Views/GoalTimelineBarView.swift"

    // MARK: - The page hands the timeline the shared route

    /// One presenter for both presentations, and the timeline spends the *same* selection function
    /// the mission cards spend. A second `showGoalDetail = true` here would be a second place for
    /// "what opening a goal means" to be answered, which is the failure T-271's own gate note
    /// describes one paragraph up in the same file.
    @Test
    func theTimelineOpensTheSameInspectorSheetTheMissionCardsOpen() throws {
        let page = try goalRouteCode(Self.goalsView)

        #expect(goalRouteCount(of: "GoalTimelineView(", in: page) == 1)
        #expect(
            goalRouteCount(of: "onOpenGoal: { select($0, showsInspector: false) }", in: page) == 1,
            "the timeline branch no longer routes through the shared select(_:showsInspector:)"
        )
        #expect(
            goalRouteCount(of: "showsInspector: false", in: page) == 1,
            "the roadmap has no inspector column at any width; a computed gate here would be a lie"
        )
        #expect(
            goalRouteCount(of: "GoalInspectorSheet(", in: page) == 1,
            "both presentations reach one presenter, or the two modes can drift"
        )
        #expect(
            goalRouteCount(of: "onEditGoal", in: page) == 0,
            "Edit-only was the whole defect: it is reached from inside the inspector now"
        )
    }

    // MARK: - Every goal on the roadmap has one, including the directions

    /// Rows *and* bars, and the group row too.
    ///
    /// Hanging the route on `GoalTimelineBarView` alone would give a direction one only while it has
    /// both a start and an end date — `timelineBody` skips the bar otherwise — leaving an undated
    /// direction as the single goal on the page with no way to attach a list. It is the same
    /// argument `GoalsView.select` makes about its two card kinds, and it is why
    /// `GoalTimelineGroupRow` gained the gestures rather than only the milestone rail row.
    @Test
    func everyRowAndBarOnTheRoadmapCarriesTheRoute() throws {
        let timeline = try goalRouteCode(Self.timelineView)

        #expect(goalRouteCount(of: "let onOpenGoal: (Goal) -> Void", in: timeline) == 1)
        #expect(
            goalRouteCount(of: "onOpen: { onOpenGoal(goal) }", in: timeline) == 2,
            "expected the milestone rail row and the bar; one of the two lost its route"
        )
        #expect(
            goalRouteCount(of: "onOpen: { onOpenGoal($0) }", in: timeline) == 1,
            "the direction's group row takes its goal as an argument — it may have none"
        )
        #expect(goalRouteCount(of: "GoalTimelineGroupRow(", in: timeline) == 1)
        #expect(goalRouteCount(of: "onEdit", in: timeline) == 0)
    }

    /// The two rail rows, in the file that draws them. The double-tap must be attached **before**
    /// the single tap or the single-tap recognizer swallows the event — the reason the file's own
    /// comment gives, and the reason both rows are counted here rather than one.
    @Test
    func bothRailRowsOpenOnDoubleTapAndSelectOnSingle() throws {
        let support = try goalRouteCode(Self.timelineSupport)

        #expect(
            goalRouteCount(of: "let onOpen: (Goal) -> Void", in: support) == 1,
            "the group row's open callback"
        )
        #expect(
            goalRouteCount(of: "let onOpen: () -> Void", in: support) == 1,
            "the milestone rail row's open callback"
        )
        #expect(
            goalRouteCount(of: ".onTapGesture(count: 2", in: support) == 2,
            "both rail rows open on double-tap"
        )
        #expect(goalRouteCount(of: "onOpen(goal)", in: support) == 1)
        #expect(goalRouteCount(of: "onSelect(goal)", in: support) == 1)
        #expect(goalRouteCount(of: "perform: onOpen", in: support) == 1)
        #expect(goalRouteCount(of: "onEdit", in: support) == 0)
        // Selecting a direction has to be visible or the single tap changes only what a later
        // double tap would be about. One layer, composited over the group band's own fill.
        #expect(goalRouteCount(of: "if isSelected {", in: support) == 1)
        #expect(
            goalRouteCount(of: "Color(hex: \"#", in: support) == 0,
            "the selection wash is a Theme token, not a literal"
        )
    }

    @Test
    func theBarOpensOnDoubleTapToo() throws {
        let bar = try goalRouteCode(Self.timelineBar)

        #expect(goalRouteCount(of: "let onOpen: () -> Void", in: bar) == 1)
        #expect(goalRouteCount(of: "perform: onOpen", in: bar) == 1)
        #expect(goalRouteCount(of: "onEdit", in: bar) == 0)
    }

    // MARK: - Non-vacuity

    /// Every zero-count assertion above passes against an empty string, and an empty string is
    /// exactly what a wrong path produces on an isolated build tree. This proves the reader reached
    /// real source and that the comment stripper actually stripped — the prose in these files says
    /// "onEdit" and "Edit" repeatedly, so an unstripped scan would fail the absence checks rather
    /// than pass them, and a *stripped* scan that read nothing would pass everything.
    @Test
    func theSourceScanActuallyReadsTheseFilesInGoalTimelineRoute() throws {
        for path in [Self.goalsView, Self.timelineView, Self.timelineSupport, Self.timelineBar] {
            let raw = try goalRouteSource(path)
            let code = try goalRouteCode(path)
            #expect(raw.count > 1_000, "\(path) read \(raw.count) bytes")
            #expect(code.contains("struct "), "\(path) has no live struct after stripping")
            // The stripper blanks comments to spaces of equal length, so the lengths match and
            // only the bytes differ — a `code.count < raw.count` check here would be the vacuous
            // kind, passing on a stripper that did nothing only if it also read nothing.
            #expect(code != raw, "\(path) lost nothing to the comment stripper")
        }

        // A comment that mentions the banned needle, proving the stripper is why it counts zero.
        let support = try goalRouteSource(Self.timelineSupport)
        #expect(support.contains("// Higher count first"))
        #expect(try goalRouteCode(Self.timelineSupport).contains("Higher count first") == false)
    }
}

// MARK: - Helpers

private func goalRouteCount(of needle: String, in code: String) -> Int {
    code.components(separatedBy: needle).count - 1
}

private func goalRouteRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func goalRouteSource(_ relativePath: String) throws -> String {
    try String(
        contentsOf: goalRouteRepositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

/// Blanks `//` and `/* */` comments so the counts read code rather than prose.
private func goalRouteCode(_ relativePath: String) throws -> String {
    var result = try goalRouteSource(relativePath)
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
