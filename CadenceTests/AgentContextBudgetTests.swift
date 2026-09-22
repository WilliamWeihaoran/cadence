import Foundation
import Testing

struct AgentContextBudgetTests {
    /// T-434's number, and the only one this suite had until T-1332. Kept exactly as it was: the
    /// byte budget below is an ADDITION, not a replacement, because the two fail on different
    /// things and a file can be bad in either direction.
    static let lineBudget = 200

    /// T-1332. A line count is a proxy for "how much an agent must read before starting", and the
    /// thing it proxies for is free to walk away from it. Measured at the ticket's HEAD:
    /// `Cadence/Services/AGENTS.md` was **17,958 bytes in 138 lines** (130 bytes/line) while root
    /// `AGENTS.md` was **12,459 bytes in 199 lines** (63 bytes/line) — so the Services guide was
    /// 44% more text than the root guide while sitting 31% further under the line cap, and both
    /// this suite and `.github/workflows/docs.yml` read it as the comfortable one. The longest
    /// single line in the capped set is 1,559 characters; the shortest-wrapping guide holds to
    /// ~100. A cap on lines cannot see that, and worse, it points the wrong way: rewrapping a
    /// dense paragraph onto more lines makes a file *fail* a budget it did not get worse against.
    ///
    /// **18,000 bytes, and it is a RATCHET rather than an allowance.** It is the largest guide in
    /// the tree today (17,958) rounded up to the nearest 500. Nothing has to be trimmed to land
    /// this, and nothing may grow past the file that is already the biggest — which is exactly the
    /// trade the ticket asked for, against the alternative of a scramble to shorten guides now.
    /// That is deliberately the opposite call from the 180-vs-200 reasoning below, and for a
    /// reason: the line cap was the *only* budget, so it had to leave room for ordinary additions.
    /// A second budget pinned at the maximum costs nobody a trim today and stops the one failure
    /// T-1332 names. If a guide genuinely needs more, the answer is T-434's and T-1208's — move
    /// the rationale to a linked long reference — and not a rewrap, which changes neither number
    /// honestly.
    ///
    /// **Bytes, not tokens.** No tokenizer is chosen here and none is implied. Bytes are an honest
    /// proxy that any reader can reproduce with `wc -c`; a token claim would not be.
    static let byteBudget = 18_000

    @Test func claudeStartupGuideStaysCompactAndRoutesToReference() throws {
        let guide = try repositoryFile("CLAUDE.md")

        #expect(guide.contains("# Cadence Claude Guide"))
        #expect(guide.contains("docs/CLAUDE_REFERENCE.md"))
        #expect(guide.contains("docs/CONTEXT_INDEX.md"))
        try expectSizeBudget("CLAUDE.md", lines: Self.lineBudget, bytes: Self.byteBudget)
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
            try expectSizeBudget(guide, lines: Self.lineBudget, bytes: Self.byteBudget)
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

/// Both budgets in one pass, and **both numbers in every failure message** (T-1332). Reporting only
/// the one that broke is how a guide ends up 44% larger than another while reading as the
/// comfortable one: the number nobody prints is the number nobody manages.
///
/// T-660/T-750. `omittingEmptySubsequences: false` counts a trailing newline's empty final element,
/// so the line count reads **one higher than `wc -l`** on every file here — all of them
/// newline-terminated. The invariant is exact and unconditional (`wc -l` == the number of `\n`
/// bytes == pieces − 1), so the failure message states both counts instead of leaving an agent to
/// reach for `wc -l` and land on the wrong one by exactly one.
///
/// The byte count is `.utf8.count`, which is the file's byte length exactly — the same number
/// `wc -c` and the `docs.yml` job report, so the three instruments cannot disagree.
private func expectSizeBudget(_ relativePath: String, lines lineLimit: Int, bytes byteLimit: Int) throws {
    let text = try repositoryFile(relativePath)
    let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
    let byteCount = text.utf8.count
    let wcDashL = lineCount - 1
    let sizes = """
        \(relativePath) is \(lineCount) lines by this test's count (\(wcDashL) by `wc -l`) \
        and \(byteCount) bytes (`wc -c`); the budgets are \(lineLimit) lines \
        (\(lineLimit - 1) by `wc -l`) and \(byteLimit) bytes.
        """
    // Interpolated rather than passed straight through: `#expect`'s second argument is a `Comment`,
    // which is `ExpressibleByStringInterpolation` but not constructible from a bare `String`.
    #expect(lineCount <= lineLimit, "\(sizes)")
    #expect(
        byteCount <= byteLimit,
        """
        \(sizes)
        Do NOT rewrap to pass this: rewrapping changes the line count and not the reading cost, \
        which is the defect T-1332 was filed about. Move rationale to a linked long reference \
        (the T-434 / T-1208 pattern) instead.
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
