import Foundation
import Testing

struct AgentContextBudgetTests {
    @Test func claudeStartupGuideStaysCompactAndRoutesToReference() throws {
        let guide = try repositoryFile("CLAUDE.md")

        #expect(guide.contains("# Cadence Claude Guide"))
        #expect(guide.contains("docs/CLAUDE_REFERENCE.md"))
        #expect(guide.contains("docs/CONTEXT_INDEX.md"))
        try expectLineCount("CLAUDE.md", isAtMost: 200)
    }

    /// T-434. This used to name three files and three different literals, which meant nine of the
    /// twelve `AGENTS.md` files had no ceiling at all — including `Cadence/Models/` and
    /// `CadenceMCPServer/`, the two closest to one, and including the guide whose unmarked claim
    /// got T-338 and T-387 filed as bugs twice.
    ///
    /// **Decision: every `AGENTS.md` in the repository is capped, and they share one number.**
    /// Not "only the always-loaded ones" — by this repo's own rules there is no such thing as an
    /// `AGENTS.md` nobody loads. Root is startup context (`CLAUDE.md`, "First Reads"), and every
    /// scoped guide is mandatory reading before editing its subtree (root `AGENTS.md`, "Scoped
    /// Guides"). A cap that has to be added by hand is a cap that arrives late, so the list is
    /// discovered by walking the tree: a scoped guide created tomorrow is covered tomorrow.
    ///
    /// The number is 200, matching the `CLAUDE.md` ceiling above rather than inventing a third
    /// scale. 180 was rejected deliberately: the root guide reached 179 lines the day this was
    /// written, so that cap had one line of headroom left and was already forcing trims to pay for
    /// additions — a wall, not a budget, and a budget people route around by starting a thirteenth
    /// file is worse than a looser one they respect.
    @Test func activeAgentGuidesStayCompactAndRouteToReferences() throws {
        let guides = try agentGuidePaths()

        // Non-vacuity: the walk has to have actually found the guides it claims to cap.
        #expect(guides.count >= 12, "found only \(guides.count) AGENTS.md files")
        #expect(guides.contains("AGENTS.md"))
        #expect(guides.contains("Cadence/Models/AGENTS.md"))
        #expect(guides.contains("CadenceMCPServer/AGENTS.md"))

        for guide in guides {
            try expectLineCount(guide, isAtMost: 200)
        }

        #expect(try repositoryFile("AGENTS.md").contains("docs/AGENTS_REFERENCE.md"))
        #expect(try repositoryFile("AGENTS.md").contains("docs/CONTEXT_INDEX.md"))
        #expect(try repositoryFile("Cadence/Shared/AGENTS.md").contains("../../docs/SHARED_AGENTS_REFERENCE.md"))
        #expect(try repositoryFile("Cadence/iOS/AGENTS.md").contains("../../docs/IOS_AGENTS_REFERENCE.md"))
    }

    /// The cap only helps if the guide is reachable. Root `AGENTS.md` is the only index of the
    /// scoped guides, so a guide missing from that list is a file no agent is told to read — the
    /// same "unpinned and unrouted" gap T-434 is about, in the other direction.
    @Test func everyScopedAgentGuideIsRoutedFromTheRootGuide() throws {
        let root = try repositoryFile("AGENTS.md")
        let scoped = try agentGuidePaths().filter { $0 != "AGENTS.md" }

        #expect(scoped.count >= 11, "found only \(scoped.count) scoped guides")
        for guide in scoped {
            #expect(root.contains("`\(guide)`"), "root AGENTS.md never routes to \(guide)")
        }
    }

    @Test func longClaudeReferenceRemainsExplicitlyArchived() throws {
        let reference = try repositoryFile("docs/CLAUDE_REFERENCE.md")

        #expect(reference.contains("Long Claude Reference"))
        #expect(reference.contains("former long `CLAUDE.md`"))
        #expect(reference.contains("Do not load"))
        #expect(reference.contains("## Calendar / Events"))
    }

    @Test func longAgentReferencesRemainExplicitlyArchived() throws {
        let root = try repositoryFile("docs/AGENTS_REFERENCE.md")
        let shared = try repositoryFile("docs/SHARED_AGENTS_REFERENCE.md")
        let iOS = try repositoryFile("docs/IOS_AGENTS_REFERENCE.md")

        #expect(root.contains("former long root `AGENTS.md`"))
        #expect(shared.contains("former long `Cadence/Shared/AGENTS.md`"))
        #expect(iOS.contains("former long `Cadence/iOS/AGENTS.md`"))
        #expect(root.contains("## Red Runs That Are Not Regressions"))
        #expect(shared.contains("## Source-Scanning Tests"))
        #expect(iOS.contains("## The Task Inspector Is Presented By A Host"))
    }

    @Test func contextIndexRoutesByChangeType() throws {
        let index = try repositoryFile("docs/CONTEXT_INDEX.md")

        #expect(index.contains("SwiftData model"))
        #expect(index.contains("Shared UI/component/theme/date logic"))
        #expect(index.contains("iOS/iPadOS UI"))
        #expect(index.contains("MCP server/plugin"))
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func repositoryFile(_ relativePath: String) throws -> String {
    try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

/// T-660/T-750. `omittingEmptySubsequences: false` counts a trailing newline's empty final element,
/// so this reads **one higher than `wc -l`** on every file here — all of them newline-terminated.
/// The invariant is exact and unconditional (`wc -l` == the number of `\n` bytes == pieces − 1), so
/// the failure message states both counts instead of leaving an agent to reach for `wc -l` and land
/// on the wrong one by exactly one.
private func expectLineCount(_ relativePath: String, isAtMost limit: Int) throws {
    let lineCount = try repositoryFile(relativePath)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .count
    let wcDashL = lineCount - 1
    #expect(
        lineCount <= limit,
        """
        \(relativePath) has \(lineCount) lines by this test's count (\(wcDashL) by `wc -l`); \
        keep it at or under \(limit) here, i.e. at or under \(limit - 1) by `wc -l`.
        """
    )
}

/// Every `AGENTS.md` in the repository, repository-relative, discovered rather than enumerated.
/// Build products and dependency checkouts are skipped; a vendored guide is not this repo's
/// context budget.
private func agentGuidePaths() throws -> [String] {
    let root = repositoryRoot()
    guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
    var guides: [String] = []
    for case let entry as String in walker {
        if entry.hasPrefix(".git/") || entry.contains("/.build/") || entry.hasPrefix(".build/") { continue }
        if entry == "AGENTS.md" || entry.hasSuffix("/AGENTS.md") { guides.append(entry) }
    }
    return guides.sorted()
}
