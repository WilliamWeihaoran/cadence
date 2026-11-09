import Foundation
import Testing
@testable import Cadence

/// **T-14292 — a list's Completed tab heads its rows with their count on iOS too.**
///
/// The Mac tab (`ListLogView`) drew `ListLogRowPresentation.countLabel(for:)` over its rows; the
/// iOS tab (`iOSListCompletedPanel`) drew the same rows with nothing over them, because the enum
/// lived in a `#if os(macOS)` file. It is shared now, so this suite is not platform-gated: the
/// count's copy is exercised on whichever platform runs it, and both readers are pinned by source.
@MainActor
struct CadenceListCompletedCountEyebrowTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
    }

    private func task(_ status: TaskStatus) -> AppTask {
        let task = AppTask(title: "t")
        task.status = status
        return task
    }

    @Test func theSharedCountNamesCancelledTasksApart() {
        #expect(ListLogRowPresentation.countLabel(for: [task(.done), task(.done), task(.done)]) == "3 completed")
        #expect(ListLogRowPresentation.countLabel(for: [task(.cancelled), task(.cancelled)]) == "2 canceled")
        #expect(ListLogRowPresentation.countLabel(for: [task(.done), task(.cancelled), task(.done)])
                == "2 completed, 1 canceled")
    }

    @Test func theCountLivesInSharedCode() throws {
        let shared = try Self.code("Cadence/Shared/ListLogRowPresentation.swift")
        #expect(shared.contains("enum ListLogRowPresentation"))
        #expect(!shared.contains("#if os("), "the count is gated to one platform again")
        let mac = try Self.code("Cadence/macOS/Views/ListDetailSupportViews.swift")
        #expect(!mac.contains("enum ListLogRowPresentation"), "a second, macOS-only copy is back")
    }

    @Test func theIOSCompletedTabHeadsItsRowsWithTheCount() throws {
        let source = try Self.code("Cadence/iOS/iOSListSupportViews.swift")
        let panel = try #require(CadenceSourceScan.declarationBody("struct iOSListCompletedPanel: View", in: source))
        #expect(panel.contains("SectionEyebrowLabel(text: ListLogRowPresentation.countLabel(for: tasks))"))
        // Over the rows, inside the same List: the eyebrow comes before the ForEach that draws them.
        let eyebrow = try #require(panel.range(of: "ListLogRowPresentation.countLabel(for: tasks)"))
        let rows = try #require(panel.range(of: "ForEach(tasks)"))
        #expect(eyebrow.lowerBound < rows.lowerBound)
    }
}
