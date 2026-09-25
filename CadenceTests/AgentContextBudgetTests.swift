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

        #expect(try repositoryFile("AGENTS.md").contains("docs/CONTEXT_INDEX.md"))

        // T-1211: one loop over `Self.guideReferencePairings` rather than a clause per pair. The
        // hand-written list is exactly why `docs/MCP_AGENTS_REFERENCE.md` went unpinned — it was
        // created after the clauses were written, and a list does not add to itself. (T-1344 added
        // the Services route the same way and is now a row instead.)
        for pairing in Self.guideReferencePairings {
            #expect(
                try repositoryFile(pairing.guidePath).contains(pairing.linkFromGuide),
                "\(pairing.guidePath) never routes to \(pairing.linkFromGuide)"
            )
        }
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

    /// A long reference is half of a pair, and this checks the half that rots.
    ///
    /// **T-1211.** `docs/MCP_AGENTS_REFERENCE.md` was the only one of the long references nothing
    /// pinned, because the clauses this replaces were written when there were three and a fourth
    /// file does not add itself to a hand-written list. That is T-434's "unpinned and unrouted"
    /// gap one file later, which is why the fix is a table rather than another clause.
    ///
    /// **`citedSections` is the assertion with teeth, and it is why "the file still exists" was not
    /// enough.** These guides do not summarise their reference; they *name a section of it* at the
    /// point where the reasoning is needed — `CadenceMCPServer/AGENTS.md` sends a reader to "Why
    /// three kinds have no constructor" instead of restating T-1122, and `Cadence/Services/AGENTS.md`
    /// does it for eleven sections at once. Each entry is checked from **both** ends: the guide must
    /// still contain the quoted phrase, and the reference must still spell it as a `##` heading. So
    /// a renamed heading, a deleted section and a dropped citation all go red — which is the drift
    /// the ticket is about, a guide quietly ceasing to match the reference it exists for.
    ///
    /// `pinnedHeadings` is the weaker fallback for a reference whose guide links it without quoting
    /// a section name. It catches a gutted file and nothing finer.
    @Test func longAgentReferencesRemainExplicitlyArchived() throws {
        for pairing in Self.guideReferencePairings {
            // Flattened: a guide wraps its prose at ~100 columns, so a cited section name is as
            // likely to straddle a newline plus two spaces of indent as not. Comparing raw text
            // would make this pass or fail on where the wrap happened to land.
            let guide = flattenedWhitespace(try repositoryFile(pairing.guidePath))
            let reference = try repositoryFile(pairing.referencePath)
            let headings = reference
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { $0.hasPrefix("## ") }
                .map { $0.lowercased() }

            #expect(
                reference.contains(pairing.archivalMarker),
                "\(pairing.referencePath) no longer says it is \(pairing.archivalMarker)"
            )
            #expect(
                reference.contains("Do not load this whole file by default"),
                "\(pairing.referencePath) no longer tells a reader not to load it whole"
            )
            #expect(headings.count >= 4, "\(pairing.referencePath) has only \(headings.count) sections")

            for heading in pairing.pinnedHeadings {
                #expect(reference.contains(heading), "\(pairing.referencePath) lost \(heading)")
            }

            for section in pairing.citedSections {
                #expect(
                    guide.contains("\"\(section)\""),
                    "\(pairing.guidePath) no longer cites \"\(section)\"; pin what it cites now instead"
                )
                #expect(
                    headings.contains { $0.contains(section.lowercased()) },
                    "\(pairing.referencePath) has no heading for \"\(section)\", which \(pairing.guidePath) still sends readers to"
                )
            }
        }
    }

    /// Every assertion in the two loops above is satisfied by an empty string, which is what a path
    /// mismatch produces — the failure mode `CadenceMCPToolContractTests` names, and the reason this
    /// exists rather than being trusted.
    @Test func theGuideReferencePairingTableIsNotVacuous() throws {
        #expect(Self.guideReferencePairings.count == 5)
        #expect(Self.guideReferencePairings.contains { $0.referencePath == "docs/MCP_AGENTS_REFERENCE.md" })
        #expect(Self.guideReferencePairings.filter { !$0.citedSections.isEmpty }.count >= 4)

        for pairing in Self.guideReferencePairings {
            #expect(try repositoryFile(pairing.guidePath).count > 1_000)
            #expect(try repositoryFile(pairing.referencePath).count > 1_000)
            #expect(pairing.citedSections.isEmpty == false || pairing.pinnedHeadings.isEmpty == false)
        }
    }

    /// One row per long agent reference: where its guide links it, that it still says what it is,
    /// and the sections that guide sends readers to by name.
    private struct GuideReferencePairing {
        let guidePath: String
        /// Spelled as the guide spells it, relative path included — a link a reader can follow.
        let linkFromGuide: String
        let referencePath: String
        /// How the reference describes its own provenance. Not one wording: "former long" is for a
        /// guide that was replaced, "lifted out of" for one that still exists and still carries the
        /// rules, and flattening the two would lose the distinction T-1344 wrote down.
        let archivalMarker: String
        /// Quoted in the guide **and** a `##` heading in the reference. Matched case-insensitively
        /// and by containment, so a heading may carry a ticket suffix the citation does not.
        let citedSections: [String]
        /// Headings pinned without a citation to pair them to.
        let pinnedHeadings: [String]
    }

    private static let guideReferencePairings: [GuideReferencePairing] = [
        GuideReferencePairing(
            guidePath: "AGENTS.md",
            linkFromGuide: "docs/AGENTS_REFERENCE.md",
            referencePath: "docs/AGENTS_REFERENCE.md",
            archivalMarker: "former long root `AGENTS.md`",
            citedSections: [
                "Why the pre-commit hook ships inert",
                "The `try? save()` rule",
            ],
            pinnedHeadings: ["## Red Runs That Are Not Regressions"]
        ),
        GuideReferencePairing(
            guidePath: "Cadence/Shared/AGENTS.md",
            linkFromGuide: "../../docs/SHARED_AGENTS_REFERENCE.md",
            referencePath: "docs/SHARED_AGENTS_REFERENCE.md",
            archivalMarker: "former long `Cadence/Shared/AGENTS.md`",
            citedSections: ["This Task Is Over"],
            pinnedHeadings: ["## Source-Scanning Tests"]
        ),
        GuideReferencePairing(
            guidePath: "Cadence/iOS/AGENTS.md",
            linkFromGuide: "../../docs/IOS_AGENTS_REFERENCE.md",
            referencePath: "docs/IOS_AGENTS_REFERENCE.md",
            archivalMarker: "former long `Cadence/iOS/AGENTS.md`",
            // The one guide that links its reference without naming a section, so it gets the
            // weaker pin. A citation added there belongs here.
            citedSections: [],
            pinnedHeadings: ["## The Task Inspector Is Presented By A Host"]
        ),
        GuideReferencePairing(
            guidePath: "Cadence/Services/AGENTS.md",
            linkFromGuide: "../../docs/SERVICES_AGENTS_REFERENCE.md",
            referencePath: "docs/SERVICES_AGENTS_REFERENCE.md",
            archivalMarker: "lifted out of `Cadence/Services/AGENTS.md`",
            // T-1344 wrote this guide as one section name per bullet, so the pairing is total here
            // and this row is what the mechanism was built for.
            citedSections: [
                "Why The Store-Failure Reason Goes Through An Extractor",
                "Silent-Push Registration, And The Build With No Entitlement",
                "The Markdown File Count, And Why It Is Re-Counted",
                "The Markdown Image Lifecycle Sweep",
                "The Tag Slug Index, Measured",
                "Privacy Data Reset: Two Failure Rules",
                "Data Export: The Archive Timestamp, And Import",
                "List And Context Deletion Cascades",
                "Container Wind-Down",
                "EventKit Reminders Lived Behind An `#if os(macOS)`",
                "The Shared Write-Capable Container Gate",
            ],
            pinnedHeadings: []
        ),
        GuideReferencePairing(
            guidePath: "CadenceMCPServer/AGENTS.md",
            linkFromGuide: "../docs/MCP_AGENTS_REFERENCE.md",
            referencePath: "docs/MCP_AGENTS_REFERENCE.md",
            archivalMarker: "lifted out of `CadenceMCPServer/AGENTS.md`",
            citedSections: [
                "Why the prohibition was wrong",
                "Why deletion is refused",
                "Why three kinds have no constructor",
                "Why the tracking helpers cost four files",
                "Why bulk cancel got a cap and a dry run",
                "Why the write path's undo is two composed primitives",
            ],
            pinnedHeadings: []
        ),
    ]

    @Test func contextIndexRoutesByChangeType() throws {
        let index = try repositoryFile("docs/CONTEXT_INDEX.md")

        #expect(index.contains("SwiftData model"))
        #expect(index.contains("Shared UI/component/theme/date logic"))
        #expect(index.contains("iOS/iPadOS UI"))
        #expect(index.contains("MCP server/plugin"))
    }

    /// T-1363. This suite and `.github/workflows/docs.yml` are two guards on one rule, and until
    /// this test nothing compared their numbers. They disagreed by exactly one line: this suite
    /// counts `split(separator: "\n", omittingEmptySubsequences: false)`, which is `wc -l` + 1 on
    /// a newline-terminated file, and caps that at 200 — so it permits 199 by `wc -l`, while the
    /// job refused only `-gt 200` and permitted 200. A guide at exactly 200 `wc -l` lines was
    /// **green in the docs job and red in the test job from the same commit**, and which answer
    /// you got depended on which one you read.
    ///
    /// Asserted on the shell text rather than on behaviour because the job cannot be executed
    /// from here. That is a weaker instrument, so it is pinned to the two comparisons by their
    /// exact spelling and fails closed: a rewrite of the job that drops either operator fails
    /// this test rather than silently reopening the gap.
    @Test func theWorkflowJobAndThisSuiteCapTheGuidesAtTheSameSize() throws {
        let job = try repositoryFile(".github/workflows/docs.yml")

        // `wc -l` is one BELOW this suite's count, so the job's refusal is `>=` the budget.
        #expect(
            job.contains("[ \"$lines\" -ge \(Self.lineBudget) ]"),
            """
            docs.yml no longer refuses at `-ge \(Self.lineBudget)`. With `-gt` it permits a guide \
            of \(Self.lineBudget) lines by `wc -l`, which is \(Self.lineBudget + 1) by this \
            suite's count and red here — the T-1363 disagreement, reopened.
            """
        )
        // Bytes need no adjustment: `.utf8.count` and `wc -c` are the same number.
        #expect(
            job.contains("[ \"$bytes\" -gt \(Self.byteBudget) ]"),
            "docs.yml no longer refuses bytes at `-gt \(Self.byteBudget)`, so the two byte caps differ"
        )
        // The warning band is the other half: three guides sat at exactly the maximum, so the next
        // line added to any of them was red by construction. Losing the band loses the notice.
        #expect(
            job.contains("::warning file=$guide::"),
            "docs.yml lost T-1363's warning band, so a guide reaches the cap with no notice first"
        )
        // Non-vacuity: a file that failed to load, or a job renamed out from under this test,
        // would satisfy none of the above for the wrong reason.
        #expect(job.contains("git ls-files '*AGENTS.md' 'CLAUDE.md'"), "the budget job is gone or renamed")
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
/// `wc -c` and the `docs.yml` job report, so the three instruments cannot disagree ON BYTES. The
/// LINE counts are not automatically equal — `wc -l` is one below this one — and keeping the two
/// guards on the same file size is `theWorkflowJobAndThisSuiteCapTheGuidesAtTheSameSize` (T-1363).
/// Every run of whitespace collapsed to one space, so a phrase quoted across a line wrap in a
/// markdown guide still reads as the phrase it is.
private func flattenedWhitespace(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

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
