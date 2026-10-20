#if os(macOS)
import Foundation
import Testing
@testable import Cadence

struct CadenceCodexBlockMoveRemovalTests {
    @Test func retiredBlockMoveHasNoMutationOrCommitEntryPoint() throws {
        let schedule = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Services/SchedulingService.swift"))
        #expect(schedule.contains("static func dropTask("))
        #expect(!schedule.contains("static func dropBundle("))
        let board = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageBoardSupportViews.swift"))
        #expect(board.contains("static func schedule("))
        #expect(!board.contains("static func move("))
        let commit = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceTaskFieldEditCommit.swift"))
        #expect(commit.contains("enum CadenceTaskFieldEditCommit"))
        #expect(!commit.contains("commitBlockMove"))
        #expect(!commit.contains("CadenceTaskBundleSlotSnapshot"))
    }
}
#endif
