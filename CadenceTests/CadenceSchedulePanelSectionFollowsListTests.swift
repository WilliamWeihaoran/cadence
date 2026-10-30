import Foundation
import Testing
@testable import Cadence

/// **The panel's Section row follows its List row** ([[T-8591]]).
///
/// Changing a task's List in the iOS task sheet (or the inline task panel a note embeds) left
/// `draft.sectionName` naming the old list's section: the row read "Doing" over a list with no
/// such section, and Save -- which re-normalizes -- filed the task under that list's first section
/// instead. `CadenceSchedulePanel` now reconciles the two on every `draft.listToken` change, over
/// the `sectionChoices` its host already computes for the new list, so every host gets it.
///
/// The normalization is a value and is tested as one; the panel's wiring to it is source-scanned,
/// because a SwiftUI body is not reachable from a unit test. Shared code, so it runs on both legs.
@MainActor
struct CadenceSchedulePanelSectionFollowsListTests {

    private func source(_ relativePath: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: The value

    @Test func aSectionTheNewListLacksBecomesThatListsFirst() {
        let normalized = CadenceTaskMutationSupport.normalizedSectionName("Doing", among: ["Todo", "Later"])
        #expect(normalized == "Todo")
    }

    @Test func aSectionTheNewListHasIsKeptInThatListsSpelling() {
        let normalized = CadenceTaskMutationSupport.normalizedSectionName("later", among: ["Todo", "Later"])
        #expect(normalized == "Later")
    }

    /// The Inbox: the panel's choices are empty there, and the row must not go on naming the old
    /// list's section under its greyed-out label.
    @Test func noChoicesAnswersTheDefaultSection() {
        let normalized = CadenceTaskMutationSupport.normalizedSectionName("Doing", among: [])
        #expect(normalized == TaskSectionDefaults.defaultName)
    }

    /// The model-backed overload is this one over the list's names, so Save and the panel agree.
    @Test func theInboxOverloadAgreesWithTheNamesOverload() {
        let byModel = CadenceTaskMutationSupport.normalizedSectionName("Doing", area: nil, project: nil)
        let byNames = CadenceTaskMutationSupport.normalizedSectionName(
            "Doing",
            among: CadenceTaskMutationSupport.sectionNames(forArea: nil, project: nil)
        )
        #expect(byModel == byNames)
        #expect(byModel == TaskSectionDefaults.defaultName)
    }

    // MARK: The wiring

    /// On `body` itself, so it covers both presentations (the standard panel and the capture
    /// card), not only one of them.
    @Test func thePanelBodyReconcilesTheSectionOnAListChange() throws {
        let panel = CadenceSourceScan.codeOnly(source("Cadence/Shared/Components/CadenceSchedulePanel.swift"))
        #expect(!panel.isEmpty)
        let body = try #require(CadenceSourceScan.declarationBody("var body: some View", in: panel))
        // The body is the route to both presentations; the reconciliation sits beside it.
        #expect(body.contains("CadenceScheduleCaptureCard("))
        #expect(body.contains("standardPanel"))
        #expect(body.contains(".onChange(of: draft.listToken)"))
        #expect(body.contains("draft.sectionName = CadenceTaskMutationSupport.normalizedSectionName("))
        #expect(body.contains("among: sectionChoices"))
    }

    /// The two hosts the ticket named hand the panel the choices of the list the DRAFT names, so
    /// the panel's reconciliation reads the new list rather than the task's saved one.
    @Test func theTicketsHostsDeriveSectionChoicesFromTheDraftsList() {
        for path in ["Cadence/iOS/iOSTaskDetailSheet.swift", "Cadence/Shared/Components/CadenceTaskInlinePanel.swift"] {
            let host = source(path)
            #expect(!host.isEmpty, "\(path) was not read")
            #expect(host.contains("CadenceTaskComposerSupport.selection(fromToken: draft.listToken)"), "\(path)")
            #expect(
                host.contains("CadenceTaskMutationSupport.sectionNames(forArea: selectedArea, project: selectedProject)"),
                "\(path)"
            )
        }
    }
}
