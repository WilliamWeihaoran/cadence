import Foundation
import Testing
@testable import Cadence

// MARK: - The rule

/// One call site allowed to re-type a shared constant, and why.
///
/// **T-374.** "A correct shared helper exists and the call sites spell its body inline" is the most
/// common defect shape in this repo's audits — [[T-359]], [[T-362]], [[T-364]], [[T-441]],
/// [[T-446]], [[T-467]], [[T-472]] and [[T-492]] are all it, and every one was found by a
/// human-scale read that will not repeat reliably.
///
/// This file is the mechanical half, kept to the one form of the shape a scanner can judge without
/// guessing: **a string constant declared in `Cadence/Shared/` and re-typed as a literal
/// elsewhere.** A duplicated literal is exactly decidable — no "looks similar", no threshold — and
/// each hit names both ends, so acting on one is a one-line edit rather than an investigation.
///
/// **What it deliberately does not try to catch, and why.** Numeric constants are the other half of
/// the shape and are *not* decidable this way. A `20` at a call site is a padding, a count, an
/// index or a coincidence far more often than it is `Theme`'s or a metrics helper's, and the ticket
/// asks for exactly that honesty: a low-precision guard trains reviewers to ignore it. Two
/// exclusions keep this rule on the decidable side, both stated as rules rather than as an
/// allowlist:
///
/// - **Literals under 12 characters.** "None", "Inbox", "Other", "Custom" and "Notes" are English,
///   not constants; they collide with unrelated enum raw values and menu titles constantly. Below
///   12 the hits are collisions; at and above it they are phrases.
/// - **Glyph names** — an all-lowercase dotted identifier like `sun.max.fill`. An SF Symbol is a
///   picture, not a concept: the Today tab, a habit frequency row and a board card's do-date badge
///   draw the same sun without sharing a meaning. Defaults keys survive the rule because they carry
///   capitals (`calendar.workHours.endMinute.v1`), which is pinned below rather than assumed.
///
/// **Two target boundaries are subtracted, not exempted.** `CadenceWidgets/` is outside the walk,
/// and a file `CadenceMCPServer` compiles is subtracted from the hits of any constant *that target
/// cannot compile the declaration of* -- a literal there is not a call site that could read the
/// constant. That is [[T-354]]'s boundary, and it was measured rather than assumed -- three of this
/// sweep's first hits were "fixed" by reading the shared constant, which turned
/// `CadenceTargetSourceMembershipTests.mcpServerSourcesOnlyReferenceTypesThatTargetCompiles` red on
/// the very next run.
///
/// **The second clause of that sentence is [[T-499]]'s.** The subtraction used to be a flat file
/// set, so it hid every literal in an MCP file regardless of where the constant lived. It is a
/// predicate now, and the difference is that it retires itself: T-499 moved the three "Untitled …"
/// labels into `Cadence/Models/ModelEnums.swift`, which that target *does* compile, so the five
/// hits it had been hiding became ordinary offenders and were fixed rather than forgiven. The
/// remaining subtraction still covers constants declared only in `Shared/` -- `"Untitled Event"`,
/// say -- which an MCP file genuinely has no way to read.
struct CadenceSharedLiteralExemption {
    let literal: String
    let path: String
    let why: String

    init(_ literal: String, path: String, why: String) {
        self.literal = literal
        self.path = path
        self.why = why
    }
}

/// **The one collection.** Every entry is a measured false positive — a hit the sweep is right to
/// see and wrong to call a defect — not a deferral of work. `everySharedLiteralExemptionIsStillLoadBearing`
/// deletes any entry that stops describing the tree, so an exemption cannot outlive the line it was
/// written for and start covering the next offender.
let cadenceSharedLiteralExemptions: [CadenceSharedLiteralExemption] = [
    CadenceSharedLiteralExemption(
        "Completed Today",
        path: "Cadence/macOS/Views/HabitListSupport.swift",
        why: """
        `HabitListFilter.completed` filters habits done today. \
        `CadenceTodayPresentationSupport.completedSectionTitle` is the Today page's section of \
        *tasks* completed today. Same English, two concepts: reading one off the other would make \
        renaming the Today section silently rename a habit filter, which is a coupling this sweep \
        would have created rather than found.
        """
    ),
]

/// A string constant declared in `Cadence/Shared/`, read out of source rather than listed here.
///
/// Harvested rather than declared on purpose: a hand-kept list of constants is a census that goes
/// stale the first time somebody adds one, which is the failure mode [[T-374]] warns about in its
/// own text.
struct CadenceSharedStringConstant: Equatable, Sendable {
    let name: String
    let literal: String
    let declaredIn: String

    var owner: String { "`\(name)` in \(declaredIn)" }
}

@MainActor
struct CadenceSharedConstantReuseSweepTests {

    // MARK: - The sweep

    /// Nothing outside the file that declares it re-types a shared string constant.
    ///
    /// Through `CadenceScanInstrument` rather than a bare `contains`, for the [[T-161]] reason: a
    /// clean repo and a blinded detector look identical from outside, and `sweep`'s non-defaulted
    /// `atLeast:`/`including:` make the walk's non-vacuity a compile requirement rather than
    /// something a reader has to notice is missing.
    @Test func noCallSiteRetypesASharedStringConstant() throws {
        let constants = try cadenceSharedStringConstants()
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let read = CadenceSourceScan.strippedSourceReader()
        let mcpMembers = try cadenceMCPServerMemberFiles()

        for constant in constants {
            let hits = try sharedLiteralInstrument(for: constant).sweep(
                files,
                // 300+ Swift files under `Cadence/`; the floor `CadenceRetiredCopyTests` uses for
                // the same tree.
                atLeast: 300,
                // The file that held four of this sweep's first hits, so a walk that skipped the
                // iOS tree cannot report the repo clean.
                including: "Cadence/iOS/iOSFocusView.swift",
                read: read
            )
            // The target boundary, stated as the rule it always meant (T-499): a file cannot read
            // a constant declared in a file its own target does not compile. So the subtraction
            // applies only while the *declaration* is out of `CadenceMCPServer`'s reach — a
            // constant in `Models/` is reachable from every target, and an MCP file re-typing one
            // of those is an ordinary offender. This is what makes the boundary self-retiring:
            // moving a declaration into `Models/` deletes its subtraction with no edit here.
            let unreachableFromMCP = !mcpMembers.contains(constant.declaredIn)
            let offenders = hits.filter { path in
                path != constant.declaredIn
                    && !(unreachableFromMCP && mcpMembers.contains(path))
                    && !cadenceSharedLiteralExemptions.contains {
                        $0.literal == constant.literal && $0.path == path
                    }
            }

            #expect(
                offenders.isEmpty,
                """
                "\(constant.literal)" is declared as \(constant.owner) and is typed again in \
                \(offenders). Read the constant instead — or, if the two are different concepts \
                that happen to share their English, add a measured exemption saying so.
                """
            )
        }
    }

    /// The walk, named rather than trusted. `sweep` refuses an empty or short list but cannot know
    /// the tree it walked is the app; an `atLeast:` satisfied by one folder alone would pass.
    @Test func theSharedConstantSweepReachesEverySurfaceOfTheApp() throws {
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")

        for path in [
            "Cadence/Shared/TaskTitleSupport.swift",
            "Cadence/iOS/iOSFocusView.swift",
            "Cadence/macOS/Views/SchedulePanel.swift",
            "Cadence/Services/CadenceUITestSupport.swift",
            "Cadence/Models/ModelEnums.swift",
        ] {
            #expect(files.contains(path), "the shared-constant sweep never reaches \(path)")
        }

        // Reading contents, not just listing names: a walk that yields paths it cannot open would
        // satisfy every absence assertion above.
        #expect(
            try CadenceSourceScan.sourceFile("Cadence/Shared/TaskTitleSupport.swift")
                .contains("nonisolated enum TaskTitleSupport"),
            "non-vacuity: the sweep's reader returned no content"
        )
    }

    // MARK: - The harvest is a harvest

    /// The harvest found the constants the sweep was built from. Without this, a regex that stopped
    /// matching would turn the sweep green over zero constants — the quietest way this file could
    /// stop guarding anything at all.
    @Test func theHarvestReadsTheSharedConstantsTheSweepWasBuiltFrom() throws {
        let constants = try cadenceSharedStringConstants()
        #expect(constants.count >= 40, "the harvest read \(constants.count) shared string constants")

        let byLiteral = Dictionary(grouping: constants, by: \.literal)
        for literal in ["Untitled Task", "Untitled Context", "Linked calendar is missing"] {
            #expect(byLiteral[literal] != nil, "\"\(literal)\" is no longer harvested")
        }
        // `Models/`, not `Shared/`, since T-499 — and that is the assertion, not an incidental
        // path: the whole point of the move is that `CadenceMCPServer` compiles this file.
        #expect(
            byLiteral["Untitled Task"]?.first?.declaredIn == "Cadence/Models/ModelEnums.swift",
            "the harvest lost track of where a constant is declared"
        )
        #expect(
            byLiteral["Linked calendar is missing"]?.first?.declaredIn.hasPrefix("Cadence/Shared/") == true,
            "the harvest stopped reading Shared/ when Models/ was added to it"
        )
        #expect(constants.allSatisfy { $0.literal.count >= 12 }, "a short word reached the sweep")
        #expect(constants.allSatisfy {
            !$0.name.isEmpty
                && ($0.declaredIn.hasPrefix("Cadence/Shared/") || $0.declaredIn.hasPrefix("Cadence/Models/"))
        })
    }

    /// The two exclusions, checked as rules on real values rather than trusted as prose.
    ///
    /// The glyph rule's whole risk is one pair: dropping `calendar.workHours.endMinute.v1` as if it
    /// were a symbol name would blind the sweep to every preference key in the app.
    @Test func theHarvestDropsGlyphNamesAndKeepsDottedDefaultsKeys() throws {
        let literals = Set(try cadenceSharedStringConstants().map(\.literal))

        #expect(literals.contains("calendar.workHours.endMinute.v1"),
                "a dotted defaults key was mistaken for a glyph name")
        #expect(literals.contains("todayRolloverNoticeDismissedDate"))
        #expect(literals.contains("sun.max.fill") == false, "a glyph name reached the sweep")
        #expect(literals.contains("tray.fill") == false)
        #expect(literals.contains("None") == false, "a short word reached the sweep")

        // The rule itself, not only its effect on today's tree.
        #expect(cadenceIsGlyphName("sun.max.fill"))
        #expect(cadenceIsGlyphName("flag.fill"))
        #expect(cadenceIsGlyphName("calendar.workHours.endMinute.v1") == false)
        #expect(cadenceIsGlyphName("Untitled Task") == false)
    }

    /// The target boundary is a real subtraction with real edges, not a phrase in a comment.
    ///
    /// Both halves matter: it has to cover the files that actually broke, and it must not quietly
    /// swallow the app tree -- a boundary that returned every path would turn the sweep green over
    /// nothing while reading like a principled exclusion.
    ///
    /// **T-499 narrowed it from a file set to a rule.** It used to subtract every MCP member file
    /// from every constant's hits; it now subtracts them only for a constant whose *declaration*
    /// that target does not compile. The five hits it was hiding are fixed rather than forgiven:
    /// the labels moved to `Models/ModelEnums.swift`, which `CadenceMCPServer` does compile, so the
    /// subtraction no longer applies to them and `CadenceReadService` is swept like any other file.
    @Test func theSweepSkipsTheFilesTheMCPServerTargetCompiles() throws {
        let members = try cadenceMCPServerMemberFiles()
        #expect(members.count >= 40, "the MCP source list parsed as \(members.count) files")
        #expect(members.contains("Cadence/Services/MCPReadOnly/CadenceReadService.swift"))
        #expect(members.contains("Cadence/Services/NoteReferenceSupport.swift"))
        #expect(members.contains("Cadence/iOS/iOSFocusView.swift") == false,
                "the boundary swallowed an app-only file, which would blind the sweep to it")
        #expect(members.contains("Cadence/macOS/Views/SchedulePanel.swift") == false)

        // The rule has to have both answers on today's tree, or it is a constant dressed as a
        // predicate. `Models/ModelEnums.swift` is compiled by that target -- so nothing is
        // subtracted for the labels declared there -- and `Shared/CadenceEventTitleSupport.swift`
        // is not, so "Untitled Event" keeps its subtraction and an MCP file typing it is still not
        // an offender it could fix.
        #expect(members.contains("Cadence/Models/ModelEnums.swift"),
                "the labels T-499 moved are out of the MCP target's reach again")
        #expect(members.contains("Cadence/Shared/CadenceEventTitleSupport.swift") == false)

        // And the fix itself: the read service reads the labels rather than re-typing them.
        let mcp = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Services/MCPReadOnly/CadenceReadService.swift")
        )
        #expect(mcp.contains("CadenceTitleNormalization.defaultTaskTitle"), "non-vacuity: file unread")
        #expect(mcp.contains("\"Untitled Task\"") == false,
                "the MCP read service re-types the task-title fallback again")
        #expect(mcp.contains("\"Untitled Context\"") == false)
    }

    // MARK: - The detector

    /// The detector against the tree, not only against its own fixtures. The instrument's literal
    /// witnesses prove it still discriminates; this proves the shapes it was tuned on are the
    /// shapes the repo actually holds.
    @Test func theSharedConstantDetectorSeparatesACallSiteFromProse() throws {
        let constant = try #require(
            try cadenceSharedStringConstants().first { $0.literal == "Untitled Task" }
        )
        let instrument = try sharedLiteralInstrument(for: constant)

        // No: a file whose only "Untitled Task" is the paragraph about the naming convention.
        let prose = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEventTitleSupport.swift")
        #expect(prose.contains("Untitled Task"), "non-vacuity: the paragraph is gone")
        #expect(instrument.fires(on: prose) == false, "the sweep reads prose as a call site")

        // Yes: the declaration itself, which the sweep sees and then excludes by path rather than
        // by failing to see. A detector blind to its own declaration would be blind to every call
        // site spelled the same way.
        let declaration = try CadenceSourceScan.sourceFile(constant.declaredIn)
        #expect(instrument.fires(on: declaration))
    }

    // MARK: - Exemptions rot

    /// Each exemption claims a specific file still types a specific shared constant for a specific
    /// reason. When that stops being true it is dead weight that can only hide a regression.
    @Test func everySharedLiteralExemptionIsStillLoadBearing() throws {
        let literals = Set(try cadenceSharedStringConstants().map(\.literal))

        for exemption in cadenceSharedLiteralExemptions {
            #expect(literals.contains(exemption.literal),
                    """
                    "\(exemption.literal)" is no longer a shared constant, so the exemption for \
                    \(exemption.path) forgives a hit the sweep can no longer produce.
                    """)
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(exemption.path))
            #expect(code.contains(exemption.literal),
                    """
                    \(exemption.path) no longer types "\(exemption.literal)" — delete the exemption \
                    rather than leaving it to cover the next offender.
                    """)
            #expect(exemption.why.count > 40, "\"\(exemption.literal)\" does not say why")
        }
    }

    /// **The precision claim, written down.** A sweep whose numbers nobody measured is a sweep
    /// nobody can argue with. Over the tree as it stood when this shipped the raw rule produced
    /// **28 hits**. Five were in files `CadenceMCPServer` compiles and were subtracted by the
    /// target boundary above -- real duplication, but not reachable duplication. ([[T-499]] made
    /// them reachable and fixed all five; the boundary now subtracts nothing on this tree, which is
    /// what `theSweepSkipsTheFilesTheMCPServerTargetCompiles` states.) Of the **23 that reached a
    /// verdict**: 16 re-typings of `TaskTitleSupport.defaultDisplayTitle`, 2 of
    /// `CadenceContextPickerSupport.untitledName`, 4 preference keys re-typed inside
    /// `CadenceUITestSupport`'s defaults reset, and 1 collision of ordinary English -- **22 true
    /// positives, 96% precision, one exemption**.
    ///
    /// This does not re-derive the number; it pins the shape of the claim, so the sweep cannot
    /// quietly become an empty rule with a paragraph attached.
    @Test func theSharedConstantSweepWasMeasuredBeforeItShipped() {
        #expect(cadenceSharedLiteralExemptions.count == 1,
                "the exemption list changed size; re-measure the precision claim above it")
        #expect(cadenceSharedLiteralExemptions.first?.literal == "Completed Today")
    }
}

// MARK: - Fixtures

/// The files `CadenceMCPServer` compiles. `Cadence/Shared/` is not among them, so a shared constant
/// is not reachable from any of them and a literal there is not a call site.
///
/// Read off the project's own source list through the graph `CadenceTargetSourceMembershipTests`
/// already builds, rather than a second opinion about target membership -- which is the shape this
/// whole file is about.
func cadenceMCPServerMemberFiles() throws -> Set<String> {
    try TargetSourceGraph(
        name: "CadenceMCPServer",
        // MCP-only file: the router exists for no other target.
        phaseAnchor: "CadenceMCPToolRouter.swift",
        synchronizedRoots: [],
        ownFolder: "CadenceMCPServer"
    ).memberFiles
}

/// An all-lowercase dotted identifier: an SF Symbol name rather than a phrase.
func cadenceIsGlyphName(_ literal: String) -> Bool {
    literal.range(of: #"^[a-z0-9]+(\.[a-z0-9]+)+$"#, options: .regularExpression) != nil
}

/// The detector for one constant, as an instrument that cannot be built once it stops
/// discriminating.
///
/// The witnesses are the nearest possible miss: the same line, once typed and once read off the
/// constant. A shared constant's text appears in this repo's doc comments about as often as it
/// appears in code, so the negative witness carries the prose form too.
private func sharedLiteralInstrument(for constant: CadenceSharedStringConstant) throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "shared constant re-typed: \(constant.literal)",
        fires: """
        struct Screen {
            let subtitle = "\(constant.literal)"
        }
        """,
        andNotOn: """
        struct Screen {
            // Says "\(constant.literal)", from \(constant.name).
            let subtitle = Somewhere.\(constant.name)
        }
        """,
        by: { CadenceSourceScan.strippingComments($0).contains("\"\(constant.literal)\"") }
    )
}

/// Every `static let`/`static var` in `Cadence/Shared/` **or `Cadence/Models/`** whose value is a
/// plain string literal of at least 12 characters and is not a glyph name.
///
/// `Models/` is in the harvest for the reason [[T-499]] moved two constants there: it is the tree
/// every target compiles, so it is where a label the app *and* `CadenceMCPServer` both show has to
/// be declared. Harvesting only `Shared/` would have made that move silently *reduce* coverage —
/// the constant leaves the harvest, and the sixteen call sites already reading it stop being
/// guarded against a seventeenth typing it out again.
///
/// Interpolated and escaped literals are excluded by the pattern itself: `"\(title) (Hidden)"` is
/// not something a call site could re-type verbatim, so a hit on one would be noise by construction
/// rather than by judgement.
func cadenceSharedStringConstants() throws -> [CadenceSharedStringConstant] {
    let pattern = try NSRegularExpression(
        pattern: #"static\s+(?:let|var)\s+(\w+)\s*(?::\s*String\s*)?=\s*"([^"\\]{12,})""#
    )
    var found: [CadenceSharedStringConstant] = []
    let roots = try CadenceSourceScan.swiftFiles(under: "Cadence/Shared")
        + CadenceSourceScan.swiftFiles(under: "Cadence/Models")
    for path in roots {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        let range = NSRange(source.startIndex..., in: source)
        for match in pattern.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let literalRange = Range(match.range(at: 2), in: source) else { continue }
            let literal = String(source[literalRange])
            guard !cadenceIsGlyphName(literal) else { continue }
            found.append(
                CadenceSharedStringConstant(
                    name: String(source[nameRange]),
                    literal: literal,
                    declaredIn: path
                )
            )
        }
    }
    return found.sorted { $0.literal < $1.literal }
}
