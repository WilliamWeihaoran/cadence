import Foundation
import Testing
@testable import Cadence

/// **T-3156 / T-3158: All Tasks, Inbox and Today hand their pages a sort binding SwiftUI can compare.**
///
/// `iOSAllTasksView.sortModeBinding` was `Binding(get: { sortMode }, set: { ... })`. SwiftUI cannot
/// compare a closure-backed binding, so presenting the New task sheet over All Tasks re-ran
/// `iOSTaskCollectionPage` four times per present-and-Cancel, `Self._printChanges()` naming
/// `_sortMode` alone — with `iOSAllTasksView` itself at 0 passes. Measured on the standing iPhone
/// simulator at 0, 300 and 3,000 tasks, six trials each, scratch probes only: 4 per round trip
/// before (5 on one cold first trial), 0 in every trial once the binding became a key-path
/// projection of `$sortModeRaw`.
///
/// T-3158 measured the same closure pair on the other two surfaces with the same probes:
/// `iOSInboxView` re-ran `iOSTaskCollectionPage` and `iOSTaskViewOptionsBar` with `_sortMode
/// changed`, and `iOSTodayView` re-ran `iOSCompactTodayView` and its options bar. All three now
/// project their preference through one subscript, `String[sortModeFallingBackTo:]`, which differs
/// per surface only in the fallback it is handed.
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the passes can only
/// be counted on a simulator. This pins, as counts, the structure they depend on.
struct CadenceIOSAllTasksSortBindingTests {
    private static let projectionPath = "Cadence/Shared/CadenceTaskPlanningSupport.swift"
    private static let allTasksPath = "Cadence/iOS/iOSTaskCollectionViews.swift"

    /// Each surface, the declaration its view starts at, and the fallback its `sortMode` reads.
    private static let surfaces: [(path: String, declaration: String, fallback: String)] = [
        ("Cadence/iOS/iOSTaskCollectionViews.swift", "struct iOSAllTasksView:", "listOrder"),
        ("Cadence/iOS/iOSInboxView.swift", "struct iOSInboxView:", "listOrder"),
        ("Cadence/iOS/iOSTodayView.swift", "struct iOSTodayView:", "priority"),
    ]

    private func view(_ declaration: String, in path: String) throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        return try #require(
            CadenceSourceScan.declarationBody(declaration, in: source),
            "\(declaration) is gone from \(path)"
        )
    }

    @Test func allTasksBuildsNoClosureBackedBinding() throws {
        let view = try view("struct iOSAllTasksView:", in: Self.allTasksPath)
        #expect(
            CadenceSourceScan.matchCount(#"Binding\s*\(\s*get:"#, in: view) == 0,
            "iOSAllTasksView builds a Binding(get:set:) again, so every sheet over All Tasks re-runs iOSTaskCollectionPage (T-3156)"
        )
        // Non-vacuity: the page still receives the sort binding, and it is the AppStorage projection.
        #expect(CadenceSourceScan.matchCount(#"sortMode:\s*sortModeBinding"#, in: view) == 1)
        #expect(CadenceSourceScan.matchCount(#"\$sortModeRaw\[sortModeFallingBackTo:\s*\.listOrder\]"#, in: view) == 1)
    }

    /// T-3158: Inbox and Today, which built the same closure pair All Tasks did.
    @Test func inboxAndTodayBuildNoClosureBackedSortBinding() throws {
        for surface in Self.surfaces.dropFirst() {
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
