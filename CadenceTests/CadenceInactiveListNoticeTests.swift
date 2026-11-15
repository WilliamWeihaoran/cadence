import Foundation
import SwiftData
import Testing
@testable import Cadence

/// [[T-17906]]: a completed, archived, paused or canceled list opened from Search (iOS) or Cmd+K
/// (Mac) says so on its page, on both platforms through one decision.
@MainActor
struct CadenceInactiveListNoticeTests {

    @Test func anActiveListGetsNoNoticeAndKeepsItsEyebrow() {
        #expect(CadenceInactiveListNotice.notice(for: .active) == nil)
        let eyebrow = CadenceInactiveListNotice.eyebrow(baseEyebrow: "Home", notice: nil)
        #expect(eyebrow.eyebrow == "Home")
        #expect(eyebrow.detail == nil)
        let mac = CadenceInactiveListNotice.eyebrow(baseEyebrow: nil, notice: nil)
        #expect(mac.eyebrow == nil)
        #expect(mac.detail == nil)
    }

    /// The Settings > Lists row's rule: "Unarchive" only for archived, "Reopen" for the rest.
    @Test func everyInactiveLifecycleOffersTheSettingsRowsVerb() throws {
        let cases: [(CadenceListSearchLifecycle, String, String, Bool)] = [
            (.archived, "Archived", CadenceListVocabularyCopy.unarchiveActionTitle, false),
            (.completed, "Completed", "Reopen", true),
            (.paused, "Paused", "Reopen", false),
            (.cancelled, "Canceled", "Reopen", false),
        ]
        for (lifecycle, status, verb, completedTint) in cases {
            let notice = try #require(CadenceInactiveListNotice.notice(for: lifecycle))
            #expect(notice.statusLabel == status)
            #expect(notice.statusLabel == lifecycle.statusLabel)
            #expect(notice.actionTitle == verb)
            #expect(notice.usesCompletedTint == completedTint)
            #expect(notice.message == CadenceInactiveListNotice.hiddenMessage)
        }
        #expect(CadenceListVocabularyCopy.unarchiveActionTitle == "Unarchive")
    }

    /// Inactive: the status word leads, the context path follows as the detail clause; a blank
    /// base eyebrow (the Mac header) leaves the status alone.
    @Test func anInactiveListsEyebrowLeadsWithItsStatus() throws {
        let notice = try #require(CadenceInactiveListNotice.notice(for: .archived))
        let phone = CadenceInactiveListNotice.eyebrow(baseEyebrow: "Home / Garage", notice: notice)
        #expect(phone.eyebrow == "Archived")
        #expect(phone.detail == "Home / Garage")
        let mac = CadenceInactiveListNotice.eyebrow(baseEyebrow: nil, notice: notice)
        #expect(mac.eyebrow == "Archived")
        #expect(mac.detail == nil)
        let blank = CadenceInactiveListNotice.eyebrow(baseEyebrow: "  ", notice: notice)
        #expect(blank.detail == nil)
    }

    @Test func theNoticeReadsTheListsOwnStatusAndReopenBringsItBack() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let home = Context(name: "Home")
        let activeArea = Area(name: "Operations", context: home)
        let archivedArea = Area(name: "Garage", context: home)
        archivedArea.status = .archived
        let pausedProject = Project(name: "Atlas", context: home)
        pausedProject.status = .paused
        modelContext.insert(home)
        modelContext.insert(activeArea)
        modelContext.insert(archivedArea)
        modelContext.insert(pausedProject)
        try modelContext.save()

        #expect(CadenceInactiveListNotice.notice(area: activeArea, project: nil) == nil)
        #expect(CadenceInactiveListNotice.notice(area: nil, project: nil) == nil)
        #expect(CadenceInactiveListNotice.notice(area: archivedArea, project: nil)?.actionTitle == "Unarchive")
        #expect(CadenceInactiveListNotice.notice(area: nil, project: pausedProject)?.actionTitle == "Reopen")
        #expect(CadenceInactiveListNotice.notice(area: nil, project: pausedProject)?.statusLabel == "Paused")

        CadenceInactiveListNotice.reopen(area: archivedArea, project: nil)
        CadenceInactiveListNotice.reopen(area: nil, project: pausedProject)
        #expect(archivedArea.status == .active)
        #expect(pausedProject.status == .active)
        #expect(CadenceInactiveListNotice.notice(area: archivedArea, project: nil) == nil)
        #expect(CadenceInactiveListNotice.notice(area: nil, project: pausedProject) == nil)
    }

    /// Both pages read the one decision and reopen through it, so neither can drift to its own
    /// status test or its own verb (T-8201). `Cadence/iOS/` is `#if os(iOS)`, so its half is a
    /// source read.
    @Test func bothListPagesReadTheSharedNoticeAndReopenThroughIt() throws {
        let pages = [
            "Cadence/macOS/Views/ListDetailView.swift",
            "Cadence/iOS/iOSListDetailView.swift",
        ]
        for path in pages {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(code.contains("CadenceInactiveListNotice.notice(area: area, project: project)"), "\(path) does not read the notice")
            #expect(code.contains("CadenceInactiveListNotice.reopen(area: area, project: project)"), "\(path) does not reopen through the shared path")
            #expect(code.contains("CadenceInactiveListNotice.eyebrow("), "\(path) does not put the status on its eyebrow")
            #expect(code.contains("notice.actionTitle"), "\(path) does not draw the shared verb")
            #expect(!code.contains("\"Reopen\""), "\(path) spells its own Reopen")
            #expect(!code.contains("\"Unarchive\""), "\(path) spells its own Unarchive")
        }
    }
}
