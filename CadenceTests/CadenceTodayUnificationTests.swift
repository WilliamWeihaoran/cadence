import CoreGraphics
import Foundation
import Testing
@testable import Cadence

/// Today, unified across macOS, iPad and iPhone.
///
/// **Two kinds of test here, and the second kind is the point.** Pinning
/// `CadenceTaskPresentationSupport.rowTagLimit == 3` proves the shared figure is right; it proves
/// nothing about anybody *using* it. T-161 is the standing example — a committed fix was reverted
/// with all tests green, because the tests pinned a helper while nothing observed the call sites.
/// So every decision below also gets a call-site test that reads the real source and fails the
/// moment a platform goes back to its own copy.
///
/// Source-text assertions are the only tool available for the iOS half: `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so there is no iOS symbol to reference.
/// The precedent is `NoteEditorPerformanceRegressionTests` and `CadenceSharedBoardChromeTests`.
struct CadenceTodayUnificationTests {

    // MARK: - Sections: the intent vocabulary

    /// Today's groups say *why* a task is in front of you. macOS grouped by list — one flat tier of
    /// area/project groups — so the same day read as an inventory on the desktop and as a plan on
    /// the phone. The four names are `CadenceTodayTaskGroupKind`'s and always were; what changed is
    /// that macOS now reads them instead of spelling the same buckets "Past Due" and "Do Today".
    @Test func todayHasExactlyFourIntentGroupsAndTheyAreNamedForTheIntent() {
        #expect(CadenceTodayTaskGroupKind.allCases.count == 4)
        #expect(CadenceTodayTaskGroupKind.overdue.title == "Overdue")
        #expect(CadenceTodayTaskGroupKind.pastDo.title == "Past Do")
        #expect(CadenceTodayTaskGroupKind.dueToday.title == "Due Today")
        #expect(CadenceTodayTaskGroupKind.plannedToday.title == "Planned Today")
    }

    /// **The T-161 test for the sections.** Both platforms' Today must derive its groups from the
    /// one shared function. Revert either to a local list of the same four predicates — which is
    /// exactly what macOS's `todayDateSections` was — and this fails; pinning `todayGroups` itself
    /// would not have noticed.
    ///
    /// macOS calls it twice on purpose: once for the sections it draws and once for the hover-freeze
    /// snapshot that has to describe the same sections. Two call sites that must agree is the
    /// argument for the count being exact rather than "contains".
    @Test func everyTodaySurfaceGroupsByIntentThroughTheSharedQuery() throws {
        try expectCallSites(
            of: "CadenceTaskQuerySupport.todayGroups",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 2,
                "Cadence/iOS/iPadTodayView.swift": 1,
            ]
        )
    }

    /// The accents go with the names: a group that says "Overdue" in `Theme.red` on one platform
    /// and in neutral `Theme.dim` on another is two different statements.
    @Test func bothPlatformsTintTheirTodayGroupsFromTheSharedAccent() throws {
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.accent",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
    }

    /// macOS's Today by-list grouping is gone, not merely unselected. The section builder and the
    /// second spelling of the four buckets both have to be absent — a `todayDateSections` left in
    /// place behind a picker nobody can reach is the same fork with a longer fuse.
    @Test func theRetiredMacOSTodayGroupingsAreGone() throws {
        try expectNoLiveMention(of: "todayListSections")
        try expectNoLiveMention(of: "todayDateSections")
        try expectNoLiveMention(of: "todayControlledSections")
    }

    /// The day's finished work is headed and tinted the same on every Today. macOS said
    /// "Completed" over a predicate that only ever held tasks completed *today*, which described a
    /// logbook it was not showing.
    @Test func bothPlatformsHeadTheirCompletedGroupWithTheSharedTitle() throws {
        #expect(CadenceTodayPresentationSupport.completedSectionTitle == "Completed Today")

        try expectCallSites(
            of: "CadenceTodayPresentationSupport.completedSectionTitle",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.completedSectionAccent",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 1,
                "Cadence/iOS/iOSTodayTaskSections.swift": 1,
            ]
        )
    }

    /// And the empty day says one thing. macOS's "Due-today and do-today tasks will appear here"
    /// restated the page's scope where the shared subtitle names the next thing to do.
    @Test func bothPlatformsDrawTheSameEmptyToday() throws {
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.emptyTitle",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iPadTodayCompactViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.emptySubtitle",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iPadTodayCompactViews.swift": 1,
            ]
        )
    }

    // MARK: - The group heading

    /// 10 wins, and it is the app's one eyebrow size rather than a number chosen for this row. iOS
    /// drew its group count at 11pt above a 10pt eyebrow — the same exception `7e5459c` closed for
    /// the board column header, in a second place. A count is already demoted by weight and by the
    /// capsule around it and must not also be *bigger* than the label it counts.
    @Test func theGroupCountIsTheAppsOneEyebrowSize() {
        #expect(CadenceTaskGroupHeadingMetrics.countSize == 10)
        #expect(CadenceTaskGroupHeadingMetrics.countSize == SectionEyebrowLabel.fontSize)
        #expect(CadenceTaskGroupHeadingMetrics.countSize == CadencePageHeaderMetrics.metrics(role: .page, surface: .desktop).eyebrowSize)
    }

    /// One capsule fill for the whole app. iOS's group badge drew 0.11 and the page header 0.12 —
    /// the same drift `CadencePageHeaderMetrics.countFillOpacity` was written to settle, repeated
    /// one component along.
    @Test func theGroupCountReusesTheAppsOneCapsuleFill() {
        #expect(CadencePageHeaderMetrics.countFillOpacity == 0.12)
    }

    /// **The T-161 test for the heading.** Today's section header on both platforms must be the
    /// shared row. macOS is the one that had drifted furthest — sentence case, 11pt, neutral
    /// `Theme.dim`, and a red/neutral "3 / 7" pair beside it — so a revert here is the likely one.
    @Test func bothPlatformsDrawTheSharedTaskGroupHeading() throws {
        try expectCallSites(
            of: "CadenceTaskGroupHeading",
            at: [
                "Cadence/macOS/Views/TasksPanelSectionViews.swift": 1,
                "Cadence/iOS/iOSTaskGroupSection.swift": 1,
            ]
        )
    }

    // MARK: - The row: iOS wins

    /// Three, and iOS had it. `MacTaskRow` capped at two for the same strip of the same chips on
    /// the same task, and macOS's strip already collapses itself through `ViewThatFits` when the
    /// column is genuinely narrow — so the lower cap was hiding a tag the row had room for.
    @Test func bothRowsShowTheSameNumberOfTags() throws {
        #expect(CadenceTaskPresentationSupport.rowTagLimit == 3)

        try expectCallSites(
            of: "CadenceTaskPresentationSupport.rowTagLimit",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskViews.swift": 1,
            ]
        )
    }

    /// **The estimate chip crosses to macOS.** `CLAUDE.md` recorded the absence as deliberate —
    /// "the row has **no** estimate control" — which is what kept the gap open through two row
    /// passes; the user overturned it. Both rows open the one shared picker, which is the same
    /// `EstimatePickerPopoverContent` the inspector and the kanban card open.
    @Test func bothRowsCarryAnEstimateChipOverTheSharedPicker() throws {
        try expectCallSites(
            of: "MacTaskRowEstimateChip",
            at: ["Cadence/macOS/Views/TasksPanelComponents.swift": 2]
        )
        try expectCallSites(
            of: "iOSTaskRowEstimateChip",
            at: [
                "Cadence/iOS/iOSTaskViews.swift": 1,
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "EstimatePickerPopoverContent",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
            ]
        )
        // Same label on both, rather than one row saying "45m" and the other "45 min".
        try expectCallSites(
            of: "CadenceTaskPresentationSupport.estimateLabel",
            at: [
                "Cadence/macOS/Views/TasksPanelComponents.swift": 1,
                "Cadence/iOS/iOSTaskRowActionViews.swift": 1,
            ]
        )
    }

    /// `MacTaskRow`'s documented performance constraint, and the reason the estimate chip is its
    /// own `View` struct rather than three lines inline: the row itself must **not** observe
    /// `TaskCompletionAnimationManager`, because that manager ticks at display-link rate during a
    /// completion animation and an observation on the row re-renders every visible row's whole
    /// content. Only `TaskCompletionButton` and `TaskRowBackground` may hold it.
    ///
    /// Same shape as `NoteEditorPerformanceRegressionTests`: a constraint nothing else can express,
    /// pinned by reading the file.
    @Test func theTaskRowStillDoesNotObserveTheCompletionAnimationManager() throws {
        let source = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelComponents.swift"))
        let environments = source.components(separatedBy: "@Environment(TaskCompletionAnimationManager.self)").count - 1
        #expect(environments == 2, "expected exactly the two extracted sub-views to observe the animation manager")

        for owner in ["MacTaskRow", "MacTaskRowEstimateChip"] {
            let body = try declarationBody(of: owner, in: "Cadence/macOS/Views/TasksPanelComponents.swift")
            #expect(
                !body.contains("TaskCompletionAnimationManager"),
                "\(owner) observes TaskCompletionAnimationManager — every visible row will re-render on animation ticks"
            )
        }
    }

    // MARK: - The header: no identity tile, anywhere

    /// **The user's call, and it reversed the brief.** macOS was to gain iOS's identity tile; what
    /// landed instead is that neither platform has one. A rounded glyph square at the top of a page
    /// names the page you are already looking at — the deleted subtitle's argument, one row up.
    ///
    /// The parameter is *deleted*, not left inert. A dead parameter that still compiles is how
    /// `subtitle` survived long enough to need removing three separate times.
    @Test func neitherPageHeaderTakesAnIdentityTile() throws {
        let desktop = try declarationBody(of: "DesktopPageHeader", in: "Cadence/macOS/Views/macOSRootSupportViews.swift")
        let mobile = try declarationBody(of: "iOSPageHeader", in: "Cadence/iOS/iOSFeatureComponents.swift")

        for (name, body) in [("DesktopPageHeader", desktop), ("iOSPageHeader", mobile)] {
            #expect(!body.contains("systemImage"), "\(name) still takes a systemImage")
            #expect(!body.contains("IconTile"), "\(name) still draws an identity tile")
        }
    }

    /// And no wrapper may reintroduce one behind the two header views' backs. These five decide
    /// nothing about appearance by design, so a tile parameter on any of them is a tile.
    @Test func noPageHeaderWrapperReintroducesTheTile() throws {
        let wrappers: [(String, String)] = [
            ("PanelHeader", "Cadence/macOS/Views/TodaySupportViews.swift"),
            ("CommitmentPageHeader", "Cadence/Shared/Components/CommitmentSharedViews.swift"),
            ("CadenceSettingsHeader", "Cadence/Shared/CadenceSettingsSharedViews.swift"),
            ("iOSPanelHeader", "Cadence/iOS/iOSTaskViews.swift"),
            ("iOSCompactPageHeader", "Cadence/iOS/iOSFeatureComponents.swift"),
            ("iOSSettingsPageHeader", "Cadence/iOS/iOSSettingsComponents.swift"),
        ]

        for (name, path) in wrappers {
            let body = try declarationBody(of: name, in: path)
            #expect(!body.contains("systemImage"), "\(name) passes a systemImage to its header again")
            #expect(!body.contains("IconTile"), "\(name) draws its own identity tile")
        }
    }

    /// The metrics that fed the tile go with it — a size table entry nothing reads is the same
    /// hazard as the parameter, and this one carried a role×surface ramp that would read as live.
    /// `tileGlyphRatio` and `tileFillOpacity` **stay**: `CommitmentIconTile` reads both for the
    /// tiles inside rows, cards and pickers, which are not page identity.
    @Test func theHeaderTileMetricsAreGoneAndTheTileVocabularyIsNot() throws {
        let source = try strippingComments(sourceFile("Cadence/Shared/CadencePageHeaderMetrics.swift"))
        #expect(!source.contains("tileSize"))
        #expect(source.contains("tileGlyphRatio"))
        #expect(source.contains("tileFillOpacity"))
        #expect(CadencePageHeaderMetrics.tileGlyphRatio == 0.44)
        #expect(CadencePageHeaderMetrics.tileFillOpacity == 0.14)
    }

    /// Three tiers, still — dropping the tile is not a reason to fold macOS into `.regular`. The
    /// title ramp is the whole finding behind the third tier and it is untouched.
    @Test func theSurfaceRampSurvivesTheTileRemoval() {
        #expect(CadencePageHeaderSurface.allCases.count == 3)
        #expect(CadencePageHeaderMetrics.metrics(role: .page, surface: .desktop).titleSize == 22)
        #expect(CadencePageHeaderMetrics.metrics(role: .pane, surface: .desktop).titleSize == 16)
    }

    /// **The T-161 test for the header.** Today's task column on every platform heads itself with
    /// the day and the day's summary, through the one `eyebrowDetail` slot. macOS read `TASKS /
    /// Today` — an eyebrow naming the column and a title naming the page, neither of which the day
    /// changes.
    @Test func everyTodayHeaderCarriesTheDayAndItsSummary() throws {
        try expectCallSites(
            of: "eyebrowDetail: summary",
            at: [
                "Cadence/macOS/Views/TasksPanelSupportViews.swift": 1,
                "Cadence/iOS/iPadTodaySupportViews.swift": 1,
                "Cadence/iOS/iPadTodayCompactViews.swift": 1,
            ]
        )
        try expectCallSites(
            of: "DateFormatters.longDate.string",
            at: [
                "Cadence/macOS/Views/TasksPanelSupportViews.swift": 1,
                "Cadence/iOS/iPadTodayView.swift": 1,
                "Cadence/iOS/iPadTodayCompactViews.swift": 1,
            ]
        )
    }

    /// The summary itself is one derivation. macOS was computing no summary at all; the risk now is
    /// that it grows its own rather than calling the shared one.
    @Test func everyTodayDerivesItsSummaryOnce() throws {
        try expectCallSites(
            of: "CadenceTodayPresentationSupport.summary",
            at: [
                "Cadence/macOS/Views/TasksPanel.swift": 1,
                "Cadence/iOS/iPadTodayView.swift": 1,
            ]
        )
    }

    // MARK: - The scan itself

    /// The absence assertions above are only worth anything if the scan actually reads files, and a
    /// scan that silently returns nothing passes every one of them. This is the test that stops
    /// them going vacuous.
    @Test func theSourceScanActuallyReachesBothPlatformsSource() throws {
        let files = try swiftFiles(under: "Cadence")

        #expect(files.count > 300, "the source scan found \(files.count) files and cannot be doing its job")
        #expect(files.contains("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(files.contains("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceTaskGroupHeading.swift"))
    }

    /// And `declarationBody` has to actually find a body — an empty slice would pass every
    /// `!contains` above. The two header views are the ones those assertions depend on.
    @Test func theDeclarationSlicerActuallyFindsTheHeaderBodies() throws {
        let desktop = try declarationBody(of: "DesktopPageHeader", in: "Cadence/macOS/Views/macOSRootSupportViews.swift")
        let mobile = try declarationBody(of: "iOSPageHeader", in: "Cadence/iOS/iOSFeatureComponents.swift")

        #expect(desktop.contains("eyebrowDetail"))
        #expect(desktop.contains("countBadge"))
        #expect(mobile.contains("eyebrowDetail"))
        #expect(mobile.contains("iOSPageHeaderCountBadge"))
    }
}

// MARK: - Source-reading helpers

/// Fails unless `name` appears exactly `count` times in each listed file.
///
/// **Exact counts, not "contains".** A file that reverts one of two call sites to a local copy
/// still "contains" the shared name, which is T-161 reproduced inside the test written to prevent
/// it. A count that has to be edited on purpose is the point.
private func expectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try strippingComments(sourceFile(path))
        let actual = code.components(separatedBy: name).count - 1
        #expect(
            actual == expected,
            "\(path) mentions \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

/// Fails if `name` appears anywhere in `Cadence/` as live code rather than inside a comment.
/// Comments are exempt so the tombstones explaining what was removed can stay.
private func expectNoLiveMention(
    of name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"

    for path in try swiftFiles(under: "Cadence") {
        let code = try strippingComments(sourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to \(name)",
            sourceLocation: sourceLocation
        )
    }
}

/// The source text of one top-level declaration, from its `struct`/`enum` line to the next
/// top-level declaration in the same file. Crude, and deliberately so: it over-reads rather than
/// under-reads at the tail, which can only make the `!contains` assertions above stricter.
private func declarationBody(of name: String, in path: String) throws -> String {
    let source = try strippingComments(sourceFile(path))
    let pattern = "(?m)^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|enum|class|extension)\\s+\(name)\\b"
    guard let start = source.range(of: pattern, options: .regularExpression) else {
        Issue.record("\(path) does not declare \(name)")
        return ""
    }

    let rest = source[start.upperBound...]
    let nextPattern = "(?m)^(?:public |private |internal |fileprivate |final |nonisolated )*(?:struct|enum|class|extension)\\s"
    let end = rest.range(of: nextPattern, options: .regularExpression)?.lowerBound ?? rest.endIndex
    return String(rest[..<end])
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields absolute paths, and
/// `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on an
/// isolated build tree) that `FileManager` resolves and the literal does not.
private func swiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = repositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func sourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// Blanks out `//` line comments and `/* */` block comments so the assertions above read code
/// rather than prose.
private func strippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
}
