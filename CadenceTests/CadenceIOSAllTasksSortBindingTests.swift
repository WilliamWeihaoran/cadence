import Foundation
import Testing
@testable import Cadence

/// **T-3156: All Tasks hands `iOSTaskCollectionPage` a sort binding SwiftUI can compare.**
///
/// `iOSAllTasksView.sortModeBinding` was `Binding(get: { sortMode }, set: { ... })`. SwiftUI cannot
/// compare a closure-backed binding, so presenting the New task sheet over All Tasks re-ran
/// `iOSTaskCollectionPage` four times per present-and-Cancel, `Self._printChanges()` naming
/// `_sortMode` alone — with `iOSAllTasksView` itself at 0 passes. Measured on the standing iPhone
/// simulator at 0, 300 and 3,000 tasks, six trials each, scratch probes only: 4 per round trip
/// before (5 on one cold first trial), 0 in every trial once the binding became the key-path
/// projection `$sortModeRaw.iOSAllTasksSortMode`.
///
/// `Cadence/iOS/` is behind `#if os(iOS)` and this target builds for macOS, so the passes can only
/// be counted on a simulator. This pins, as counts, the structure they depend on.
struct CadenceIOSAllTasksSortBindingTests {
    private static let path = "Cadence/iOS/iOSTaskCollectionViews.swift"

    private func allTasksView() throws -> String {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.path))
        return try #require(
            CadenceSourceScan.declarationBody("struct iOSAllTasksView:", in: source),
            "iOSAllTasksView is gone from \(Self.path)"
        )
    }

    @Test func allTasksBuildsNoClosureBackedBinding() throws {
        let view = try allTasksView()
        #expect(
            CadenceSourceScan.matchCount(#"Binding\s*\(\s*get:"#, in: view) == 0,
            "iOSAllTasksView builds a Binding(get:set:) again, so every sheet over All Tasks re-runs iOSTaskCollectionPage (T-3156)"
        )
        // Non-vacuity: the page still receives the sort binding, and it is the AppStorage projection.
        #expect(CadenceSourceScan.matchCount(#"sortMode:\s*sortModeBinding"#, in: view) == 1)
        #expect(CadenceSourceScan.matchCount(#"\$sortModeRaw\.iOSAllTasksSortMode"#, in: view) == 1)
    }

    @Test func theProjectionReadsAndWritesTheStoredRawValue() throws {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.path))
        let projection = try #require(
            CadenceSourceScan.declarationBody("var iOSAllTasksSortMode: CadenceTaskSortMode", in: source),
            "the String projection iOSAllTasksSortMode is gone from \(Self.path)"
        )
        #expect(CadenceSourceScan.matchCount(#"CadenceTaskSortMode\(rawValue:\s*self\)\s*\?\?\s*\.listOrder"#, in: projection) == 1)
        #expect(CadenceSourceScan.matchCount(#"self\s*=\s*newValue\.rawValue"#, in: projection) == 1)
    }
}
