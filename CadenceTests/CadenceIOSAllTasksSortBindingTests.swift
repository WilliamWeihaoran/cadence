import Foundation
import Testing
@testable import Cadence

/// **T-3156 / T-3158: All Tasks, Inbox and Today hand their pages a sort binding SwiftUI can compare.**
///
/// iOSAllTasksView's sortModeBinding (spelled without backticks: [[T-8731]] deleted it, and a
/// claim about a symbol that is gone is exactly what the comment census forbids naming as if it
/// were live) was `Binding(get: { sortMode }, set: { ... })`. SwiftUI cannot
/// compare a closure-backed binding, so presenting the New task sheet over All Tasks re-ran
/// `iOSTaskCollectionPage` four times per present-and-Cancel, `Self._printChanges()` naming
/// `_sortMode` alone — with `iOSAllTasksView` itself at 0 passes. Measured on the standing iPhone
/// simulator at 0, 300 and 3,000 tasks, six trials each, scratch probes only: 4 per round trip
/// before (5 on one cold first trial), 0 in every trial once the binding became a key-path
/// projection of `$sortModeRaw`.
///
/// T-3158 measured the same closure pair on the other two surfaces with the same probes:
/// `iOSInboxView` re-ran `iOSTaskCollectionPage` and its options bar with `_sortMode changed`, and
/// `iOSTodayView` re-ran `iOSCompactTodayView` and its options bar.
///
/// **What the measurement was actually about is the binding's *location*, not the subscript**, and
/// [[T-8731]] is where that distinction starts paying. All Tasks and Inbox no longer store a
/// `CadenceTaskSortMode` at all: they took the Mac's Sort + Order + Group model, so each stores
/// three `@AppStorage` enums under the Mac's own keys and hands the page `$sortField`,
/// `$sortDirection` and `$groupingMode` — property-wrapper projections, which are exactly the
/// comparable locations the subscript was introduced to produce. The regression this suite exists
/// to catch is unchanged and is asserted the same way: no `Binding(get:set:)` anywhere in either
/// view. Today keeps the single chip and the subscript, and keeps its own assertions below.
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the passes can only
/// be counted on a simulator. This pins, as counts, the structure they depend on.
struct CadenceIOSAllTasksSortBindingTests {
    private static let projectionPath = "Cadence/Shared/CadenceTaskPlanningSupport.swift"

    /// The two pages that took the Mac's three controls ([[T-8731]]), with the Mac default each
    /// one's `@AppStorage` declares — the same defaults `TasksPageView` declares for the same two
    /// keys, which is the half a source scan can see and the half that would drift.
    private static let threeControlSurfaces: [(path: String, declaration: String, field: String, direction: String, grouping: String)] = [
        ("Cadence/iOS/iOSTaskCollectionViews.swift", "struct iOSAllTasksView:", "date", "ascending", "byDate"),
        ("Cadence/iOS/iOSInboxView.swift", "struct iOSInboxView:", "custom", "ascending", "none"),
    ]

    /// The one surface still on the single `CadenceTaskSortMode` chip and the subscript.
    private static let todaySurface = (
        path: "Cadence/iOS/iOSTodayView.swift",
        declaration: "struct iOSTodayView:",
        fallback: "priority"
    )

    private func view(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: source),
            "\(declaration) is gone from \(path)"
        )
    }

    /// **The regression itself**: neither three-control page may build a closure-backed binding,
    /// and each must hand the page the three `@AppStorage` projections instead.
    @Test func theThreeControlPagesBuildNoClosureBackedBinding() throws {
        for surface in Self.threeControlSurfaces {
            let view = try view(surface.declaration, in: surface.path)
            #expect(
                CadenceSourceScan.matchCount(#"Binding\s*\(\s*get:"#, in: view) == 0,
                "\(surface.declaration) builds a Binding(get:set:) again, so every sheet over it re-runs iOSTaskCollectionPage (T-3156, T-3158)"
            )
            // Non-vacuity, and the whole of [[T-8731]]'s control set: three bindings reach the
            // page, each the `$` projection of a stored enum rather than a derived value.
            for binding in ["sortField", "sortDirection", "groupingMode"] {
                #expect(
                    CadenceSourceScan.matchCount(#"\#(binding):\s*\$\#(binding)"#, in: view) == 1,
                    "\(surface.declaration) does not hand the page $\(binding)"
                )
            }
            // The stored keys are the Mac's, with the Mac's defaults — the drift this would show.
            #expect(CadenceSourceScan.matchCount(
                #"@AppStorage\(CadencePreferenceKeys\.\w+SortField\)\s*private var sortField: TaskSortField = \.\#(surface.field)"#,
                in: view
            ) == 1, "\(surface.declaration) sortField default")
            #expect(CadenceSourceScan.matchCount(
                #"@AppStorage\(CadencePreferenceKeys\.\w+SortDirection\)\s*private var sortDirection: TaskSortDirection = \.\#(surface.direction)"#,
                in: view
            ) == 1, "\(surface.declaration) sortDirection default")
            #expect(CadenceSourceScan.matchCount(
                #"@AppStorage\(CadencePreferenceKeys\.\w+GroupingMode\)\s*private var groupingMode: TaskGroupingMode = \.\#(surface.grouping)"#,
                in: view
            ) == 1, "\(surface.declaration) groupingMode default")
            // And the retired one-chip preference is not read here any more.
            #expect(CadenceSourceScan.matchCount(#"sortModeFallingBackTo"#, in: view) == 0)
        }
    }

    /// T-3158's surviving half: Today still carries the single chip and the subscript.
    @Test func todayBuildsNoClosureBackedSortBinding() throws {
        let surface = Self.todaySurface
        let view = try view(surface.declaration, in: surface.path)
        let binding = try #require(
            CadenceSourceScan.declarationBody("private var sortModeBinding: Binding<CadenceTaskSortMode>", in: view),
            "sortModeBinding is gone from \(surface.declaration)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"Binding\s*\("#, in: binding) == 0,
            "\(surface.declaration) builds its sort binding as Binding(get:set:) again, so every New task sheet re-runs its page (T-3158)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\$sortModeRaw\[sortModeFallingBackTo:\s*\.\#(surface.fallback)\]"#, in: binding) == 1,
            "\(surface.declaration)'s sort binding is not the AppStorage projection with fallback .\(surface.fallback)"
        )
        // The projection's fallback is the one the view's own read uses.
        #expect(
            CadenceSourceScan.matchCount(#"CadenceTaskSortMode\(rawValue:\s*sortModeRaw\)\s*\?\?\s*\.\#(surface.fallback)"#, in: view) == 1
        )
        // Non-vacuity: the binding is still what reaches the page.
        #expect(CadenceSourceScan.matchCount(#"sortMode:\s*sortModeBinding"#, in: view) >= 1)
    }

    @Test func theProjectionReadsAndWritesTheStoredRawValue() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.projectionPath))
        let projection = try #require(
            CadenceSourceScan.declarationBody("subscript(sortModeFallingBackTo fallback: CadenceTaskSortMode)", in: source),
            "the String subscript sortModeFallingBackTo: is gone from \(Self.projectionPath)"
        )
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskSortMode\(rawValue:\s*self\)\s*\?\?\s*fallback"#, in: projection) == 1)
        #expect(CadenceSourceScan.matchCount(#"self\s*=\s*newValue\.rawValue"#, in: projection) == 1)
    }

    /// The subscript's behaviour, run rather than read: it is ordinary `String` code, so it
    /// compiles on macOS too.
    @Test func theProjectionFallsBackAndWritesThroughToTheRawValue() {
        var raw = "not-a-sort-mode"
        #expect(raw[sortModeFallingBackTo: .priority] == .priority)
        #expect(raw[sortModeFallingBackTo: .listOrder] == .listOrder)
        raw[sortModeFallingBackTo: .listOrder] = .priority
        #expect(raw == CadenceTaskSortMode.priority.rawValue)
        #expect(raw[sortModeFallingBackTo: .listOrder] == .priority)
    }
}
