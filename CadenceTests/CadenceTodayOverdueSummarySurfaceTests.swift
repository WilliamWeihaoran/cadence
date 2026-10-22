// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types (or AppKit) that do not exist there. The gate preserves
// exactly the coverage this file had before; narrowing it so any cross-platform half runs on iOS
// too is follow-up, not part of making the target iOS-capable.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// T-195, second half. Today's past-due summaries — "Past Due Lists" and "Past Due Sections" —
/// were declared in `macOS/Views/TasksPanelSupport.swift`, derived in `TasksPanelDerivedState.init`
/// and drawn by `TasksPanelSupportViews`, with **zero** references under `Cadence/iOS/`. Nothing in
/// any of it was AppKit-shaped: a filter over `Project.dueDate`, a walk of `sectionConfigs`, two
/// counts, and two cards.
///
/// T-3076 then removed the bands from both platforms' Today, and T-3078 deleted the shared
/// derivation (`CadenceTodayOverdueSummarySupport`) and the Mac's two `openOverdue…Summary` hops
/// with them — so the derivation and hop tests that lived here went too, having no subject. What
/// stays pins the removal: no Today draws or derives the cards, nothing re-declares the deleted
/// plumbing, and — because `Cadence/iOS/` is inside `#if os(iOS)` and this target builds for macOS
/// — the iOS call sites are scanned as source.
@Suite("Today past-due summaries")
struct CadenceTodayOverdueSummarySurfaceTests {

    /// **The Mac no longer draws them at all** — see
    /// `theMacTodayHasNoPastDueCardsLeftToGuardAgainst`, which is where that absence is pinned. What
    /// survives here is the other half of T-195's claim: the cards macOS *did* draw were the shared
    /// ones, so its own near-copies must still be gone rather than having come back to fill the gap.
    @Test func theMacPanelHasNoPrivateCopiesOfTheSharedCards() throws {
        let views = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanelSupportViews.swift"))
        #expect(!views.contains("struct TodayOverdueListCard"))
        #expect(!views.contains("struct TodayOverdueSectionCard"))
        #expect(!views.contains("struct OverdueSummaryCaption"))
    }

    /// **iOS's Today derives no past-due summaries and draws no past-due cards (T-3076).** This
    /// test used to assert the exact opposite, one assertion at a time, and is inverted rather than
    /// deleted: every string it names is one the phone's Today really did contain, so this is still
    /// the list of things that must not come back.
    ///
    /// The owner's second instruction is what widened it — *"my request on not showing past due
    /// sections and lists applies to mac os and ios as well"* — so the heading, the two card types
    /// and the `openRequest` hop are all absent from the one list both widths draw, and the host
    /// derives neither array.
    @Test func iOSTodayDerivesNoSummariesAndDrawsNoCards() throws {
        let host = try strippingComments(sourceFile("Cadence/iOS/iOSTodayView.swift"))
        #expect(host.contains("struct iOSTodayView: View"), "non-vacuity: wrong file read")
        #expect(!host.contains("CadenceTodayOverdueSummarySupport.listSummaries("))
        #expect(!host.contains("CadenceTodayOverdueSummarySupport.sectionSummaries("))
        #expect(!host.contains("iOSTodayOverdueSummaries("))

        let list = try strippingComments(sourceFile("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(list.contains("struct iOSTodayTaskSections: View"), "non-vacuity: wrong file read")
        #expect(!list.contains("CadenceTodayOverdueListCard(summary: summary)"))
        #expect(!list.contains("CadenceTodayOverdueSectionCard(summary: summary)"))
        #expect(!list.contains("CadenceTodayOverdueSummaryHeading("))
        #expect(!list.contains("CadenceTodayOverdueSummarySupport.openRequest(for: summary)"))
    }

    /// **No iOS file draws either card.** The count was `== 1` — the one list both widths share,
    /// which is what stopped a second near-copy growing beside it. It is `== 0` now, and the
    /// assertion still does the same job: the defect it catches has gone from "two files draw them"
    /// to "any file draws them".
    @Test func noIOSWidthDrawsThePastDueCards() throws {
        for host in ["Cadence/iOS/iOSTodayView.swift", "Cadence/iOS/iOSTodayCompactViews.swift"] {
            let source = try strippingComments(sourceFile(host))
            #expect(!source.contains("overdueSummaries"), "\(host) still passes past-due summaries through")
            #expect(!source.contains("CadenceTodayOverdueListCard("), "\(host) draws past-due list cards")
            #expect(!source.contains("CadenceTodayOverdueSectionCard("), "\(host) draws past-due column cards")
        }

        var drawing = 0
        var scanned = 0
        for path in try swiftFiles(under: "Cadence/iOS") {
            let source = try strippingComments(sourceFile(path))
            scanned += 1
            if source.contains("CadenceTodayOverdueListCard(") || source.contains("CadenceTodayOverdueSectionCard(") {
                drawing += 1
            }
        }
        // The self-check an absence count always needs: a walk that reads nothing scores 0 too.
        #expect(scanned > 60, "only \(scanned) iOS files scanned — the enumerator read nothing")
        #expect(drawing == 0, "\(drawing) iOS files still draw the past-due cards")
    }

    /// iOS must not have grown a second copy of the Mac's router. The clause about where a tapped
    /// card *landed* is gone with the cards; this half is about a type `Cadence/iOS/` may never
    /// reach, and is untouched by that.
    @Test func noIOSSurfaceReachesForTheMacOnlyNavigationManager() throws {
        var scanned = 0
        for path in try swiftFiles(under: "Cadence/iOS") {
            let source = try strippingComments(sourceFile(path))
            scanned += 1
            #expect(!source.contains("ListNavigationManager"), "\(path) reaches for the macOS-only navigation manager")
        }
        #expect(scanned > 60, "only \(scanned) iOS files scanned — the enumerator read nothing")
    }

    /// **The headings went with the derivation that owned them (T-3078).** This used to pin one
    /// owner for `"Past Due Lists"` / `"Past Due Sections"` so the platforms could not name the same
    /// run of cards differently; with no run of cards on either platform there is no owner left,
    /// so the claim is inverted rather than dropped — no product file spells either one.
    @Test func neitherPlatformRespellsTheHeadings() throws {
        let headings = try CadenceScanInstrument(
            "retired past-due heading literals",
            fires: "Text(\"Past Due Lists\")",
            andNotOn: "// Text(\"Past Due Lists\")\nText(\"Today\")"
        ) { source in
            let text = CadenceSourceScan.strippingComments(source)
            return ["\"Past Due Lists\"", "\"Past Due Sections\""].contains { text.contains($0) }
        }
        #expect(headings.fires(on: "Text(\"Past Due Sections\")"))
        let hits = try headings.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"), atLeast: 300,
            including: "Cadence/iOS/iOSTodayTaskSections.swift", read: CadenceSourceScan.sourceFile
        )
        #expect(hits.isEmpty, "retired past-due headings are spelled again: \(hits)")
    }

    /// The comment stripper is load-bearing above — several of these files explain the feature in
    /// prose that names the very strings and types being banned.
    @Test func theCommentStripperStripsInTodayOverdueSummarySurface() throws {
        let stripped = try strippingComments("let a = 1 // \"Past Due Lists\"\n/* ListNavigationManager */ let b = 2\n")
        #expect(!stripped.contains("Past Due Lists"))
        #expect(!stripped.contains("ListNavigationManager"))
        #expect(stripped.contains("let a = 1"))
        #expect(stripped.contains("let b = 2"))
    }

    /// **T-592 inverted, by the user.** This test used to guard "Nothing planned for today" against
    /// printing under a card saying three of your lists were past due: `isEmptyState` tested the four
    /// task buckets plus Completed, and the past-due cards were the one thing on macOS Today derived
    /// from *projects* and *columns* rather than tasks, so a day with no work on it drew both at once.
    ///
    /// **macOS Today draws no such card now** — *"remove these past due list displays from today's
    /// view"* — so the two clauses are gone and the page is empty exactly when its task buckets are.
    /// The guard has not been *dropped*; the thing it guarded against has. What has to hold instead
    /// is that nothing can put those arrays back into the panel's derived state without this failing.
    ///
    /// **And neither does the phone, since T-3076.** The sentence that used to close this comment
    /// — *"iOS still draws both bands and still guards on them. That divergence is deliberate and
    /// unresolved: the user has seen macOS's Today, not the phone's"* — came due the moment the
    /// owner saw the phone and said *"we should remove the banners that show the past due lists in
    /// today's view"*, then *"my request on not showing past due sections and lists applies to mac
    /// os and ios as well"*. The last two assertions below are that sentence inverted.
    @Test func neitherTodayHasPastDueCardsLeftToGuardAgainst() throws {
        let today = "2026-08-20"

        let derived = TasksPanelDerivedState(allTasks: [], todayKey: today)
        #expect(derived.isEmptyState, "a day with no tasks is empty, whatever the lists are doing")

        let panel = try strippingComments(sourceFile("Cadence/macOS/Views/TasksPanel.swift"))
        #expect(panel.contains("struct TasksPanel: View"), "non-vacuity: wrong file read")
        for banned in [
            "overdueListSummaries",
            "overdueSectionSummaries",
            "CadenceTodayOverdueListCard",
            "CadenceTodayOverdueSectionCard",
            "CadenceTodayOverdueSummaryHeading",
        ] {
            #expect(!panel.contains(banned), "macOS Today still draws \(banned)")
        }

        let derivedState = try strippingComments(
            sourceFile("Cadence/macOS/Views/TasksPanelDerivedState.swift")
        )
        #expect(derivedState.contains("struct TasksPanelDerivedState"), "non-vacuity: wrong file read")
        #expect(!derivedState.contains("OverdueSummary"))

        // Invert the old PRESENT pins across every product file, including new files. A comment
        // or string naming a retired symbol cannot satisfy this structural detector.
        let retiredNames = [
            "CadenceTodayOverdueSummarySupport", "openOverdueListSummary", "openOverdueSectionSummary",
            "CadenceTodayOverdueListCard", "CadenceTodayOverdueSectionCard", "CadenceTodayOverdueSummaryHeading",
            "CadenceOverdueSummaryCard", "CadenceOverdueSummaryHoverTracking", "CadenceOverdueSummaryIconTile",
            "CadenceOverdueSummaryMetrics", "CadenceOverdueSummaryCaption",
            "CadenceTodayOverdueListSummary", "CadenceTodayOverdueSectionSummary",
            "CadenceListOpenRequest", "iOSTodayOverdueListSheet", "pendingListOpen",
        ]
        let pattern = #"\b(?:"# + retiredNames.joined(separator: "|") + #")\b"#
        let retired = try CadenceScanInstrument(
            "retired Today past-due plumbing",
            fires: "struct CadenceTodayOverdueListCard: View {}",
            andNotOn: "// CadenceTodayOverdueListCard\nlet title = \"pendingListOpen\""
        ) { source in
            CadenceSourceScan.matchCount(pattern, in: CadenceSourceScan.codeOnly(source)) > 0
        }
        for name in retiredNames {
            #expect(retired.fires(on: "struct \(name) {}"), "detector missed \(name)")
        }
        let hits = try retired.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"), atLeast: 300,
            including: "Cadence/iOS/iOSTodayView.swift", read: CadenceSourceScan.sourceFile
        )
        #expect(hits.isEmpty, "deleted past-due plumbing is declared or referenced again: \(hits)")

        // What is gone is the drawing, on the one iOS file that did it.
        let iOSSections = try strippingComments(sourceFile("Cadence/iOS/iOSTodayTaskSections.swift"))
        #expect(iOSSections.contains("struct iOSTodayTaskSections: View"), "non-vacuity: wrong file read")
        #expect(!iOSSections.contains("CadenceTodayOverdueListCard"))
        #expect(!iOSSections.contains("CadenceTodayOverdueSectionCard"))
        #expect(!iOSSections.contains("CadenceTodayOverdueSummaryHeading"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields *absolute* paths,
/// and `#filePath` can name the repo through a symlinked prefix (`/tmp` against `/private/tmp` on
/// an isolated build tree) that `FileManager` resolves and the literal does not.
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

private func strippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}

#endif
