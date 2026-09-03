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
    CadenceSharedLiteralExemption(
        "No notes yet",
        path: "Cadence/iOS/iOSMarkdownAccessoryViews.swift",
        why: """
        `CadenceEmptyStateCopy.notepadTitle` is the Notes page's Notepad tab with nothing in it. \
        `iOSMarkdownReferencePickerKind.note.emptyTitle` is a picker with nothing to *link*, over \
        every note the app holds rather than the notepad ones, and its subtitle says so \
        ("Create or open a note first, then link it here."). Same English, two scopes — the same \
        distinction `cadenceRetiredCopy` already carves this file out for with "No tasks yet", and \
        T-285's `FocusPickerSupportViews` carve-out before that. Reading one off the other would \
        make renaming a tab silently rename a picker.
        """
    ),
]

/// A call site the widened harvest newly reaches, deferred rather than forgiven.
///
/// **T-555.** This is deliberately *not* `cadenceSharedLiteralExemptions`. Every entry there is a
/// measured false positive — a hit the sweep is right to see and wrong to call a defect. Every
/// entry here is a **true** positive that another ticket owns, written down so the widening could
/// land on its own: three sibling agents were editing these surfaces the morning it did, and a
/// detector that can only land with its fixes attached is a detector that never lands.
///
/// The list is exact in both directions, and neither direction is a floor:
/// `noCallSiteRetypesASharedStringConstant` fails on an offender nobody listed, and
/// `everyStaticFuncConstantOffenderIsLedgeredAndEveryLedgerEntryIsStillReal` fails on an entry that
/// has stopped being one. So an entry cannot outlive its fix, and a new offender cannot hide behind
/// an entry that was written for a different line.
struct CadenceStaticFuncConstantOffender {
    let literal: String
    let path: String
    /// The ticket that owns the *fix*. This file owns only the fact that it is a defect.
    let ticket: String
    let why: String

    init(_ literal: String, path: String, ticket: String, why: String) {
        self.literal = literal
        self.path = path
        self.ticket = ticket
        self.why = why
    }
}

/// Four call sites, three files, two tickets — the whole of what widening the harvest to
/// `static func` newly reaches on this tree. Measured against `HEAD` rather than a dirty checkout:
/// a sibling's untracked file was adding hits of its own while this was written, and counting them
/// would have credited them to this widening.
let cadenceStaticFuncConstantLedger: [CadenceStaticFuncConstantOffender] = [
    CadenceStaticFuncConstantOffender(
        "No goals yet",
        path: "Cadence/macOS/Views/GoalPickerViews.swift",
        ticket: "T-698",
        why: """
        Line 137 spells `CadenceEmptyStateCopy.goalsTitle(isNarrowed:)`'s body inline — \
        `searchQuery…isEmpty ? "No goals yet" : emptyText` is the same ternary over the same two \
        strings. This is the exact shape [[T-548]] converged and [[T-555]] says the sweep could \
        not see: the constant is spelled as a function, so the harvest walked past it.
        """
    ),
    CadenceStaticFuncConstantOffender(
        "No matching goals",
        path: "Cadence/macOS/Views/GoalPickerViews.swift",
        ticket: "T-698",
        why: """
        The narrowed half of the same ternary, twice, as the `emptyText` default on both pickers in \
        the file (lines 13 and 89). [[T-550]] deleted this argument where callers passed it \
        explicitly — `CreateGoalSheet` and `HabitsFormSupportViews` are clean on this tree — and \
        left the two *defaults* behind, because nothing was looking at defaults.
        """
    ),
    CadenceStaticFuncConstantOffender(
        "No lists yet",
        path: "Cadence/iOS/iOSRootSidebar.swift",
        ticket: "T-699",
        why: """
        `emptyListsRow` types the words that `CadenceListsSummary.eyebrow(areaCount:projectCount:)` \
        returns when both counts are zero. Not a call site that should read `eyebrow` — a sidebar \
        row is not a summary line — which is the point: the words have no `static let` home at all, \
        only a function's fallback branch, and that is why nothing flagged the second and third \
        spellings of them.
        """
    ),
    CadenceStaticFuncConstantOffender(
        "No lists yet",
        path: "Cadence/iOS/iOSGoalAttachListsSheet.swift",
        ticket: "T-699",
        why: """
        The third spelling, and the one that shows the shape of the fix: it is written \
        `isNarrowedToEmpty ? "No matching lists" : "No lists yet"`, which is \
        `goalsTitle(isNarrowed:)` and `habitsTitle(isNarrowed:)` again with the noun changed. Its \
        narrowed twin `"No matching lists"` clears the twelve-character floor and is still \
        invisible, because it is declared nowhere at all — the sweep can only see the half that \
        has a home. The ticket owns both halves.
        """
    ),
]

/// A placeholder label typed inline with **no** declaration anywhere, and the measured reason it
/// stays that way.
///
/// **T-515.** [[T-505]] declared a label iff its literal appeared at **≥2 sites in ≥2 files**, and
/// recorded the four that fell below that bar in a ticket so the omission would read as a decision.
/// A ticket is not a guard. This list is the same decision held mechanically: the rule does *not*
/// widen — a constant with one call site is a name, not a de-duplication, and widening to "≥2 sites
/// in ≥1 file" would still never reach `"Untitled Column"`, which has exactly one — but every
/// undeclared member of the family now has to be written down with a reason, and
/// `everyPlaceholderLabelInTheAppIsDeclaredOrRecorded` fails on a **new** one nobody listed.
///
/// That is strictly stronger than widening: it covers the one-site case, it costs no constant in
/// `Models/` for a label one macOS view file uses, and the next `"Untitled …"` typed anywhere in
/// the product has to justify itself at the point it is added rather than at the next audit.
struct CadenceUndeclaredPlaceholderLabel {
    let literal: String
    let path: String
    let why: String

    init(_ literal: String, path: String, why: String) {
        self.literal = literal
        self.path = path
        self.why = why
    }
}

/// **Three, not four, since T-539.** `"Untitled task"` left this list by being *fixed*, which is
/// the outcome the list is for: its entry said the answer was "say Task title", not "capitalise",
/// and once the prompt said that, `everyUndeclaredPlaceholderLabelIsStillUndeclaredAndStillTyped`
/// failed on the entry rather than letting it sit. An entry retiring itself is not the list
/// shrinking under pressure — a *new* label still has to be declared or written down.
let cadenceUndeclaredPlaceholderLabels: [CadenceUndeclaredPlaceholderLabel] = [
    CadenceUndeclaredPlaceholderLabel(
        "Untitled subtask",
        path: "Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift",
        why: """
        Two sites in one file, both inside the same embed drawing. Below [[T-505]]'s bar and \
        staying there: a reader editing one of the two has the other on screen. Lower-cased like \
        the "Untitled task" rows [[T-513]] fixed, but unlike those it has no capitalised twin \
        anywhere to disagree with — there is no `defaultSubtaskTitle`.
        """
    ),
    CadenceUndeclaredPlaceholderLabel(
        "Untitled List",
        path: "Cadence/macOS/Views/TaskBundlePickerSupportViews.swift",
        why: """
        Two sites in one file, the picker row and the chip beside it. Same reason as \
        "Untitled subtask": one file, both visible at once, and no second target needs to read it.
        """
    ),
    CadenceUndeclaredPlaceholderLabel(
        "Untitled Column",
        path: "Cadence/iOS/iOSColumnWindDownSupport.swift",
        why: """
        One site, one file. The case that shows why widening [[T-505]]'s rule was the wrong answer \
        to [[T-515]]: no threshold on *repetition* reaches a label used once, so only a \
        completeness rule over the whole family can hold it at all.
        """
    ),
]

/// The three roots that make up the shipped product: the app, the widget extension and the MCP
/// server. The shared-constant sweep above walks only `Cadence/` because that is where every
/// call site it can act on lives; the placeholder-family rules below walk all three, because
/// "every `Untitled …` a user can read" is a claim about the product, not about one target.
let cadencePlaceholderScanRoots = ["Cadence", "CadenceWidgets", "CadenceMCPServer"]

/// Every whole `"Untitled …"` string literal in the product, mapped to the files that type it.
///
/// The needle is derived from `CadenceTitleNormalization.defaultCompactTitle` rather than spelled
/// here, so renaming the family re-points this harvest instead of silently emptying it.
/// Interpolated and escaped literals are excluded by the pattern — those are
/// `noSourceFileBuildsAPlaceholderLabelByInterpolation`'s half of the family.
func cadencePlaceholderLabelSites() throws -> (sites: [String: Set<String>], filesRead: Int) {
    let family = NSRegularExpression.escapedPattern(for: CadenceTitleNormalization.defaultCompactTitle)
    let pattern = try NSRegularExpression(pattern: "\"(\(family)[^\"\\\\]*)\"")
    let read = CadenceSourceScan.strippedSourceReader()
    var sites: [String: Set<String>] = [:]
    var filesRead = 0
    for root in cadencePlaceholderScanRoots {
        for path in try CadenceSourceScan.swiftFiles(under: root) {
            let source = try read(path)
            filesRead += 1
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                guard let literalRange = Range(match.range(at: 1), in: source) else { continue }
                sites[String(source[literalRange]), default: []].insert(path)
            }
        }
    }
    return (sites, filesRead)
}

/// Every placeholder label with a declaration behind it, whether or not the sweep can guard it.
///
/// `defaultCompactTitle` is unioned in by hand for the one reason
/// `everyUntitledPlaceholderHasOneDeclarationTheSweepCanSee` already states out loud: `"Untitled"`
/// is eight characters, under the harvest's twelve-character floor. It is declared; it is simply
/// not swept. Leaving it out here would report the app's most common placeholder as undeclared.
func cadenceDeclaredPlaceholderLabels() throws -> Set<String> {
    let family = CadenceTitleNormalization.defaultCompactTitle
    var declared = Set(try cadenceSharedStringConstants().map(\.literal).filter { $0.hasPrefix(family) })
    declared.insert(family)
    return declared
}

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

/// One literal typed at one path — the unit the [[T-555]] ledger is exact about.
struct CadenceLiteralSite: Hashable, Comparable, CustomStringConvertible {
    let literal: String
    let path: String

    var description: String { "\"\(literal)\" in \(path)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.literal, lhs.path) < (rhs.literal, rhs.path)
    }
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
            // The walk, the instrument and the T-499 target boundary all live in
            // `cadenceSharedConstantOffenders`, so the ledger check below reads exactly what this
            // reads. The ledger itself is subtracted **here and not there**: a rule that both
            // defers a hit and decides what the hits are would define its own deferral as
            // complete, and there would be nothing for T-555's ledger to be checked against.
            let offenders = try cadenceSharedConstantOffenders(
                for: constant,
                in: files,
                mcpMembers: mcpMembers,
                read: read
            ).filter { path in
                !cadenceStaticFuncConstantLedger.contains {
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
        // T-505's four in the same file, which the same subtraction hid for the same reason: the
        // labels had no declaration at all, so the sweep had nothing to subtract *from*.
        #expect(mcp.contains("CadenceTitleNormalization.defaultGoalTitle"))
        #expect(mcp.contains("\"Untitled Goal\"") == false)
        #expect(mcp.contains("\"Untitled Habit\"") == false)
    }

    // MARK: - The placeholder family

    /// **Every "Untitled …" label a user can read has a declaration, in the one tree every target
    /// compiles.**
    ///
    /// [[T-505]]. The sweep above reports *a shared constant re-typed*, so its blind spot is not a
    /// weak detector but an absence upstream of it: seven of these labels were declared **nowhere**,
    /// and with nothing to compare a literal against the sweep could not see 45 re-typings spanning
    /// all three targets. That is a failure mode worth naming, because it looks exactly like a clean
    /// tree from inside the sweep. The fix is a declaration, not a rule — no line of the sweep
    /// changed.
    ///
    /// The two halves are different kinds of assertion, deliberately:
    ///
    /// - **The values are behavioural.** This target evaluates the constants, so renaming one label
    ///   and not the surfaces that share its shape fails here with no source scan involved.
    /// - **The declaration site is what arms the sweep**, and `Models/` is load-bearing rather than
    ///   tidy: `CadenceReadService` is `CadenceMCPServer`'s and the two widget-support files are
    ///   `CadenceWidgets`', and neither target compiles the whole of `Cadence/Shared/`.
    @Test func everyUntitledPlaceholderHasOneDeclarationTheSweepCanSee() throws {
        // Behavioural: the labels, as this target reads them.
        #expect(CadenceTitleNormalization.defaultGoalTitle == "Untitled Goal")
        #expect(CadenceTitleNormalization.defaultHabitTitle == "Untitled Habit")
        #expect(CadenceTitleNormalization.defaultMilestoneTitle == "Untitled Milestone")
        #expect(CadenceTitleNormalization.defaultNoteTitle == "Untitled Note")
        #expect(CadenceTitleNormalization.defaultAreaName == "Untitled Area")
        #expect(CadenceTitleNormalization.defaultProjectName == "Untitled Project")
        #expect(CadenceTitleNormalization.defaultReminderTitle == "Untitled Reminder")

        let harvested = Dictionary(grouping: try cadenceSharedStringConstants(), by: \.name)
        #expect(harvested.count >= 30, "non-vacuity: the harvest returned \(harvested.count) names")

        // Paired, not two lists: the point is that the value this target *evaluates* is the value
        // the sweep *guards*. A name whose harvested literal has drifted from its runtime value is
        // a constant with a guard pointed at the wrong string.
        for (name, value) in [
            ("defaultTaskTitle", CadenceTitleNormalization.defaultTaskTitle),
            ("defaultContextName", CadenceTitleNormalization.defaultContextName),
            ("defaultGoalTitle", CadenceTitleNormalization.defaultGoalTitle),
            ("defaultHabitTitle", CadenceTitleNormalization.defaultHabitTitle),
            ("defaultMilestoneTitle", CadenceTitleNormalization.defaultMilestoneTitle),
            ("defaultNoteTitle", CadenceTitleNormalization.defaultNoteTitle),
            ("defaultAreaName", CadenceTitleNormalization.defaultAreaName),
            ("defaultProjectName", CadenceTitleNormalization.defaultProjectName),
            ("defaultReminderTitle", CadenceTitleNormalization.defaultReminderTitle)
        ] {
            // The floor first, because it explains every other failure here: a label shortened
            // below twelve characters leaves the harvest silently, taking its guard with it and
            // leaving the declaration behind to look like coverage.
            #expect(
                value.count >= 12,
                "\"\(value)\" is under the sweep's 12-character floor, so \(name) guards nothing"
            )

            let declarations = harvested[name] ?? []
            #expect(
                declarations.count == 1,
                "\(name) reaches the sweep \(declarations.count) times, not once"
            )
            #expect(
                declarations.first?.literal == value,
                "\(name) is harvested as \(declarations.first?.literal ?? "nothing"), not \(value)"
            )
            #expect(
                declarations.first?.declaredIn == "Cadence/Models/ModelEnums.swift",
                "\(name) is declared in \(declarations.first?.declaredIn ?? "nowhere"), which is not the one tree CadenceMCPServer and CadenceWidgets both compile"
            )
        }

        // The one placeholder that cannot join them, said out loud so the omission does not read as
        // an oversight: `"Untitled"` is eight characters, under that floor. T-499 declared it for
        // the shared *name*; it gets no sweep coverage and never will under this rule.
        #expect(CadenceTitleNormalization.defaultCompactTitle == "Untitled")
        #expect(CadenceTitleNormalization.defaultCompactTitle.count < 12)
        #expect(harvested["defaultCompactTitle"] == nil)
    }

    /// Both non-app targets compile the file the labels are declared in.
    ///
    /// This is the half of [[T-505]] that fails as a **build break** rather than a red test, which
    /// is why it is asserted rather than assumed: `-scheme Cadence` builds `CadenceWidgets`, so a
    /// widget-support file reading a constant its own target cannot compile stops the build before
    /// any test runs — and `CadenceMCPServer` is not in that scheme at all, so the same mistake
    /// there is invisible until somebody builds it separately.
    @Test func everyTargetThatDrawsAnUntitledLabelCompilesTheFileDeclaringThem() throws {
        let declaration = "Cadence/Models/ModelEnums.swift"

        let mcp = try cadenceMCPServerMemberFiles()
        #expect(mcp.contains(declaration))
        #expect(mcp.contains("Cadence/Services/MCPReadOnly/CadenceReadService.swift"))

        let widgets = try TargetSourceGraph(
            name: "CadenceWidgets",
            // Widget-only file: no other target builds the intents.
            phaseAnchor: "Cadence/Services/CadenceWidgetIntents.swift",
            synchronizedRoots: ["CadenceWidgets"],
            ownFolder: "CadenceWidgets"
        ).memberFiles
        #expect(widgets.count >= 40, "the widget source list parsed as \(widgets.count) files")
        #expect(widgets.contains(declaration), "the widget target cannot read the labels it draws")
        #expect(widgets.contains("Cadence/Services/CadenceHabitWidgetSupport.swift"))
        #expect(widgets.contains("Cadence/Services/CadenceMilestoneWidgetSupport.swift"))

        // And the boundary has both answers on today's tree, or it is a claim rather than a
        // measurement: `GoalListLinkHelpers` types two of these same labels and is app-only, which
        // is precisely why `Shared/` was not an option for the declaration.
        #expect(widgets.contains("Cadence/Shared/GoalListLinkHelpers.swift") == false)
        #expect(mcp.contains("Cadence/Shared/GoalListLinkHelpers.swift") == false)
    }

    // MARK: - The shape the sweep cannot see

    /// **No file in the product builds a placeholder label out of a prefix and a noun.**
    ///
    /// [[T-512]]. This is the sweep's structural blind spot, not a weakness in its detector:
    /// `cadenceSharedStringConstants` excludes interpolated literals **by construction** — a
    /// `"\(title) (Hidden)"` is not something a call site could re-type verbatim — so a label
    /// *assembled* at the call site is invisible to it no matter how exactly the assembled text
    /// matches a declared constant. Two files did exactly that: `"Untitled \(kind.noun)"` and
    /// `"Untitled \(noun)"`, where the noun is `Area`/`Project`/`Context`, so at runtime they
    /// produced `defaultAreaName`, `defaultProjectName` and `defaultContextName` character for
    /// character. Renaming any of those three left both builders behind with nothing going red.
    ///
    /// The needle is **derived**, not spelled: it is `defaultCompactTitle` plus a space, so
    /// renaming the family re-points this rule instead of quietly emptying it. That is the whole
    /// point — a guard whose needle is a literal has the same defect as the code it guards.
    ///
    /// It is the interpolation half of a pair. The concatenation spelling — `"Untitled " + noun` —
    /// leaves a whole literal `"Untitled "` behind, which is not a declared label, so
    /// `everyPlaceholderLabelInTheAppIsDeclaredOrRecorded` below catches it instead. Between them
    /// there is no way left to build one of these labels without either reading a constant or
    /// writing down why not.
    @Test func noSourceFileBuildsAPlaceholderLabelByInterpolation() throws {
        let prefix = "\(CadenceTitleNormalization.defaultCompactTitle) "
        // The family is one prefix and a noun. Asserted rather than assumed, because it is what
        // makes the derived needle above the right needle.
        for label in [
            CadenceTitleNormalization.defaultTaskTitle,
            CadenceTitleNormalization.defaultContextName,
            CadenceTitleNormalization.defaultGoalTitle,
            CadenceTitleNormalization.defaultHabitTitle,
            CadenceTitleNormalization.defaultMilestoneTitle,
            CadenceTitleNormalization.defaultNoteTitle,
            CadenceTitleNormalization.defaultAreaName,
            CadenceTitleNormalization.defaultProjectName,
            CadenceTitleNormalization.defaultReminderTitle
        ] {
            #expect(label.hasPrefix(prefix), "\"\(label)\" is not \"\(prefix)\" plus a noun")
        }

        let instrument = try CadenceScanInstrument(
            "placeholder label built by interpolation",
            fires: """
            struct Row {
                let name = "\(prefix)\\(kind.noun)"
            }
            """,
            // The nearest miss, and both halves of it matter: the same text in a comment, and a
            // *whole* declared label as a literal. A detector that fired on either would report
            // the declaration file and every doc comment in the repo.
            andNotOn: """
            struct Row {
                // Was "\(prefix)\\(kind.noun)".
                let fallback = "\(CadenceTitleNormalization.defaultAreaName)"
                let name = kind.untitledName
            }
            """,
            by: { CadenceSourceScan.strippingComments($0).contains("\"\(prefix)\\(") }
        )

        let files = try cadencePlaceholderScanRoots.flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
        let hits = try instrument.sweep(
            files,
            // 555 under `Cadence/` alone when this shipped, plus the widget and MCP roots.
            atLeast: 500,
            // One of the two files that held a hit, so a walk that skipped the iOS tree cannot
            // report the product clean.
            including: "Cadence/iOS/iOSListDeletionSupport.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            hits.isEmpty,
            """
            \(hits) build a "\(prefix)…" label by interpolation. The shared-constant sweep cannot \
            see that shape, so read the declared label instead — `CadenceListDeletionKind\
            .untitledName` is the model.
            """
        )
    }

    /// The two confirmations [[T-512]] was about, from both sides of the target boundary.
    ///
    /// The delete confirmation's mapping lives in `Shared/`, so this target *evaluates* it: the
    /// labels are the constants, and they are still what the old interpolation produced. The
    /// wind-down sheet is `Cadence/iOS/`, which the macOS test target does not compile, so its half
    /// is a source assertion — the weaker claim, said as the weaker claim.
    @Test func theListConfirmationsReadThePlaceholderLabelsTheyUsedToInterpolate() throws {
        #expect(CadenceListDeletionKind.area.untitledName == CadenceTitleNormalization.defaultAreaName)
        #expect(CadenceListDeletionKind.project.untitledName == CadenceTitleNormalization.defaultProjectName)
        #expect(CadenceListDeletionKind.context.untitledName == CadenceTitleNormalization.defaultContextName)

        // Behaviour-preserving, stated as an equation rather than as a promise: every kind's label
        // is still exactly the text `"Untitled \(kind.noun)"` used to build. This is also the
        // assertion that goes red if one constant is renamed out of the family.
        #expect(CadenceListDeletionKind.allCases.count == 3, "non-vacuity: no kinds to check")
        for kind in CadenceListDeletionKind.allCases {
            #expect(
                kind.untitledName == "\(CadenceTitleNormalization.defaultCompactTitle) \(kind.noun)",
                "\(kind.noun)'s placeholder no longer matches the label it replaced"
            )
        }

        // `strippingComments`, not `codeOnly`: `codeOnly` blanks string literals too, so a quoted
        // needle there can never match and the absence assertions would be permanently green.
        let deletion = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListDeletionSupport.swift")
        )
        #expect(deletion.contains("enum iOSListDeletionTarget"), "non-vacuity: file unread")
        #expect(deletion.contains("kind.untitledName"))

        let windDown = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSListWindDownSupport.swift")
        )
        #expect(windDown.contains("enum iOSListWindDownList"), "non-vacuity: file unread")
        #expect(windDown.contains("CadenceTitleNormalization.defaultAreaName"))
        #expect(windDown.contains("CadenceTitleNormalization.defaultProjectName"))
    }

    // MARK: - The rest of the family

    /// **Every `"Untitled …"` a user can read is either declared or written down.**
    ///
    /// [[T-515]], answered by a completeness rule rather than by widening [[T-505]]'s threshold —
    /// see `cadenceUndeclaredPlaceholderLabels` for why that is the stronger of the two.
    ///
    /// This is the *dual* of the sweep at the top of this file, and the pairing is the point. The
    /// sweep asks "is a declared constant re-typed?", which cannot see a label that was never
    /// declared — the absence [[T-505]] was about. This asks "is every label of this family
    /// declared?", which cannot see a declared label re-typed. Neither alone closes it.
    @Test func everyPlaceholderLabelInTheAppIsDeclaredOrRecorded() throws {
        let (sites, filesRead) = try cadencePlaceholderLabelSites()
        #expect(filesRead >= 500, "the placeholder harvest read \(filesRead) files")
        // Non-vacuity with real edges: the harvest finds the declarations themselves and finds a
        // call site far from them, so a pattern that stopped matching cannot pass as a clean tree.
        #expect(sites[CadenceTitleNormalization.defaultTaskTitle] != nil)
        #expect(sites[CadenceTitleNormalization.defaultAreaName] != nil)
        // **Re-baselined by T-609, and the shape changed as well as the number.** This was
        // `count >= 10` over the files typing `"Untitled"` inline. T-609 routed 16 of them through
        // `TaskTitleSupport.displayTitle` and the population fell to 9, so the floor went red on a
        // change that made the tree *better* — which is what a bare count over a deliberately
        // shrinking population always eventually does. Named witnesses hold the same claim without
        // that failure mode: both of these type the compact label in `Models/`, the one tree all
        // three targets compile, and both sit under the harvest's twelve-character floor, so no
        // de-duplication sweep can take them. A harvest that stopped matching loses both at once.
        //
        // **Amended by T-733**, because the reason these two were named has half changed. Both used
        // to be **stored defaults** — `Note.title` and `Document.title` each defaulted to the word.
        // `Note`'s is gone: a stored default is text the user has to delete before typing, and it
        // produced `UntitledTarget` on a simulator. What is left in `Note.swift` is `displayTitle`'s
        // per-kind fallback for `.list`, a draw-site string that stays ([[T-609]]). `Document` is a
        // legacy migration source with no UI, so its default was left alone. The witness holds
        // either way; the sentence explaining it did not.
        let compactSites = sites[CadenceTitleNormalization.defaultCompactTitle] ?? []
        #expect(compactSites.contains("Cadence/Models/Note.swift"))
        #expect(compactSites.contains("Cadence/Models/Document.swift"))

        let declared = try cadenceDeclaredPlaceholderLabels()
        #expect(declared.count >= 9, "non-vacuity: \(declared.count) declared placeholder labels")
        // Keyed by **site**, not by literal. A literal-keyed rule would let a recorded label
        // spread to a fourth file for free, which is the [[T-505]] shape all over again — the
        // recorded ones are recorded because they sit below a repetition threshold, so the
        // threshold has to be what the rule watches.
        let recorded = Dictionary(
            grouping: cadenceUndeclaredPlaceholderLabels,
            by: \.literal
        ).mapValues { Set($0.map(\.path)) }

        for (literal, paths) in sites.sorted(by: { $0.key < $1.key }) where !declared.contains(literal) {
            let unrecorded = paths.subtracting(recorded[literal] ?? [])
            #expect(
                unrecorded.isEmpty,
                """
                "\(literal)" is typed in \(unrecorded.sorted()) with no declaration behind it. \
                Either declare it beside the rest of the family in \
                `Cadence/Models/ModelEnums.swift` — the one tree all three targets compile — or add \
                a `CadenceUndeclaredPlaceholderLabel` saying why it stays inline.
                """
            )
        }
    }

    /// Each recorded label claims a specific file still types a specific undeclared placeholder.
    /// When that stops being true the entry is dead weight that can only hide the next one.
    ///
    /// The second assertion is the one that matters most: an entry whose literal has since *gained*
    /// a declaration is worse than stale, because it forgives a re-typing the sweep would now have
    /// caught.
    @Test func everyUndeclaredPlaceholderLabelIsStillUndeclaredAndStillTyped() throws {
        let declared = try cadenceDeclaredPlaceholderLabels()
        let family = CadenceTitleNormalization.defaultCompactTitle

        #expect(cadenceUndeclaredPlaceholderLabels.count == 3,
                "the recorded list changed size; re-read T-515's decision before adding to it")

        for entry in cadenceUndeclaredPlaceholderLabels {
            #expect(entry.literal.hasPrefix(family),
                    "\"\(entry.literal)\" is not a member of the \"\(family) …\" family this rule covers")
            #expect(
                declared.contains(entry.literal) == false,
                """
                "\(entry.literal)" is a declared constant now, so \(entry.path) should read it \
                rather than be forgiven for typing it.
                """
            )
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(entry.path))
            #expect(
                code.contains("\"\(entry.literal)\""),
                """
                \(entry.path) no longer types "\(entry.literal)" — delete the entry rather than \
                leaving it to cover the next one.
                """
            )
            #expect(entry.why.count > 40, "\"\(entry.literal)\" does not say why")
        }
    }

    /// [[T-513]]'s one unambiguous copy defect, pinned where this target can read it.
    ///
    /// `iOSGoalDetail` models a milestone as a nested `Goal`, so both labels are in scope in the
    /// same file and the wrong one is a plausible edit rather than a typo. The section is titled
    /// "Milestones" and iterates `milestones`; the three other rows that name a nested goal already
    /// say "Untitled Milestone".
    @Test func theMilestoneRowsAllNameAMilestone() throws {
        let detail = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureDetailViews.swift")
        )
        #expect(detail.contains("struct iOSGoalDetail"), "non-vacuity: file unread")
        #expect(detail.contains("iOSEditorSection(title: \"Milestones\")"),
                "non-vacuity: the Milestones section moved, so this scan pins nothing")
        // [[T-687]] routed this row through the trimming helper, so the needle is the call rather
        // than the ternary that used to be here. The claim is unchanged and is about *which label*:
        // a milestone row must not reach for the goal label that is in scope beside it.
        #expect(
            detail.contains(
                "CadenceTitleNormalization.display(milestone.title, fallback: CadenceTitleNormalization.defaultMilestoneTitle)"
            ),
            "the Milestones section labels an untitled milestone with something other than the milestone label"
        )
        #expect(
            detail.contains("milestone.title.isEmpty ?") == false,
            "the milestone row is back to the untrimmed ternary a title of spaces walks through (T-687)"
        )
        // The goal label is still used in the same file, for the rows that really are about a
        // goal — so this is a fix, not a blanket substitution.
        #expect(detail.contains("CadenceTitleNormalization.defaultGoalTitle"))
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


    // MARK: - A constant spelled as a function

    /// The widening sees something it could not see before, and still refuses a template.
    ///
    /// [[T-555]]. The instrument's two witnesses are the nearest possible miss and both are real
    /// code: the positive is `CadenceEmptyStateCopy.goalsTitle(isNarrowed:)`, the constant that
    /// found this gap; the negative is `CadenceCalendarDayBadge.markedDayLabel(date:hasItems:)`,
    /// whose accessibility label *nests* a nineteen-character literal inside an interpolation. A
    /// detector built on `"([^"\\\n]{12,})"` instead of a lexer fires on that negative — which is
    /// why the instrument is the fixture rather than a comment claiming it was checked.
    @Test func theHarvestReadsAConstantSpelledAsAStaticFuncAndNotATemplate() throws {
        let instrument = try CadenceScanInstrument(
            "shared constant spelled as a static func",
            fires: """
            nonisolated enum Copy {
                static func goalsTitle(isNarrowed: Bool) -> String {
                    isNarrowed ? "No matching goals" : "No goals yet"
                }
            }
            """,
            andNotOn: """
            nonisolated enum Copy {
                static func markedDayLabel(date: Date, hasItems: Bool) -> String {
                    "\\(dayName(date)), \\(hasItems ? "has scheduled items" : emptyPhrase)"
                }
            }
            """,
            by: { source in
                cadenceStaticFunctionBodies(in: source).contains { function in
                    cadencePlainStringLiterals(in: function.body).contains {
                        $0.count >= 12 && !cadenceIsGlyphName($0)
                    }
                }
            }
        )
        #expect(instrument.name == "shared constant spelled as a static func")

        // The walk finds functions in a real file, not only in a fixture string.
        let copy = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEmptyStateCopy.swift")
        )
        let declared = Set(cadenceStaticFunctionBodies(in: copy).map(\.name))
        for name in ["goalsTitle", "habitsTitle", "activeListsSubtitle"] {
            #expect(declared.contains(name), "the static-func walk missed \(name)")
        }

        let constants = try cadenceSharedStringConstants()
        let vendedByFunction = try cadenceSharedFunctionStringConstants(in: cadenceSharedConstantRoots())
        #expect(vendedByFunction.isEmpty == false, "non-vacuity: the function harvest returned nothing")

        // Named, not counted: the harvest population grows every time the app gains a sentence, so
        // an exact total here would be a number that rots rather than a claim that holds. What
        // must hold is that each of these reaches the sweep, and none of them can be reached by
        // the `static let` half — every one is spelled as a function.
        for (name, literal) in [
            ("goalsTitle", "No matching goals"),
            ("goalsTitle", "No goals yet"),
            ("goalsTitle", "All goals complete"),
            ("habitsTitle", "No matching habits"),
            ("habitsTitle", "No habits yet"),
            ("eyebrow", "No lists yet"),
            ("dormantLinkSummary", "This area is not active, so Cadence has stopped mirroring it. "
                + "The Apple calendar link is kept and resumes if the area becomes active again."),
        ] {
            #expect(
                vendedByFunction.contains { $0.name == name && $0.literal == literal },
                "the widened harvest no longer reads \"\(literal)\" out of \(name)(…)"
            )
        }

        // [[T-644]] again, in the half of the harvest that did not exist when it was written: the
        // parameter list is balanced *before* the body brace is looked for, so this repo's standard
        // `commit:` default closure is a parameter and not a body. Taking the first `{` after the
        // name would harvest the closure instead — and 33 declarations in `Shared/` carry one.
        let defaulted = """
        enum Persistence {
            static func commitEdit(
                commit: (ModelContext) throws -> Void = { try $0.save("a defaulted closure") }
            ) -> String {
                "the body's own constant"
            }
        }
        """
        let fromDefaulted = cadenceStaticFunctionBodies(in: defaulted)
            .flatMap { cadencePlainStringLiterals(in: $0.body) }
        #expect(fromDefaulted.contains("the body's own constant"))
        #expect(fromDefaulted.contains("a defaulted closure") == false,
                "the harvest read a defaulted closure in the signature as the function's body")

        // A `static func` with no body at all takes the *next* declaration's braces unless the
        // walk refuses it, and would then vend that declaration's constants under its own name.
        let requirement = """
        protocol Naming {
            static func title() -> String
        }
        enum Elsewhere {
            static func subtitle() -> String { "a constant of somebody else's" }
        }
        """
        #expect(
            cadenceStaticFunctionBodies(in: requirement).map(\.name) == ["subtitle"],
            "a bodiless protocol requirement adopted the next declaration's body"
        )

        // And the other direction on the real tree: the three spans a regex over the same bodies
        // harvests and a lexer does not. The first is a fragment nested in a template, the second
        // the tail of one, the third a run of Swift *code* between two unrelated quotes.
        let literals = Set(constants.map(\.literal))
        for artefact in ["has scheduled items", ") receive this session's time.", " : String(format: "] {
            #expect(
                literals.contains(artefact) == false,
                "\"\(artefact)\" is a template's insides, not a constant a call site could type"
            )
        }
    }

    /// **Both new readers, over a corpus wider than the one they are used on.**
    ///
    /// [[T-555]]. A crash report arrived from an integration run against a checkout this suite
    /// could not reproduce: `EXC_BREAKPOINT` in `cadenceStaticFunctionBodies(in:)`, on the line
    /// that forms the span between a parameter list and a body brace. The pair is *structurally*
    /// ordered — the brace is searched for from the closing parenthesis — and re-checking
    /// `CadenceSourceScan.matchedRange`'s contract in real Swift over 2288 declarations in 852
    /// files plus twelve adversarial shapes never inverted it, so the reader is not the finding
    /// and the walk now declines to form an unorderable span rather than trapping on one.
    ///
    /// This is the part that generalises. **A trap in a source-scan helper is not a test failure,
    /// it is a dead host** — and a crashed host emits no `.swift:line:col: error:` lines, so the
    /// run looks like nothing happened. Three tests in this file reach these two helpers, so the
    /// widest corpus available is the cheapest insurance: every Swift file in all three shipped
    /// targets, rather than the `Shared/` + `Models/` pair the harvest itself reads. A file a
    /// sibling agent is mid-way through writing is inside that set; the harvest's own roots are
    /// not necessarily.
    @Test func bothNewReadersSurviveEveryFileInTheProduct() throws {
        var filesRead = 0
        var declarations = 0
        var literals = 0
        for root in cadencePlaceholderScanRoots {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                filesRead += 1
                for function in cadenceStaticFunctionBodies(in: source) {
                    declarations += 1
                    literals += cadencePlainStringLiterals(in: function.body).count
                }
            }
        }

        // Named witnesses rather than a bare total: a walk that read nothing, or read only the
        // widget target, satisfies "it did not crash" perfectly.
        #expect(filesRead > 500, "non-vacuity: the readers were run over \(filesRead) files")
        #expect(declarations > 500, "non-vacuity: the walk found \(declarations) static funcs")
        #expect(literals > 100, "non-vacuity: the lexer read \(literals) literals")

        let badge = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceCalendarDayBadge.swift")
        )
        let found = Set(cadenceStaticFunctionBodies(in: badge).map(\.name))
        #expect(found.contains("markedDayLabel"), "the walk missed the file the negative fixture is drawn from")
    }

    /// **The ledger, exact in both directions.**
    ///
    /// [[T-555]] widened the harvest and deliberately fixed nothing: three sibling agents were
    /// editing these surfaces, and [[T-627]] had already shown a detector widening lands more
    /// safely on its own than bundled with its consequences. This is what makes that defensible —
    /// the deferral is mechanical, not a paragraph.
    ///
    /// Set equality, not a count and not a floor. `noCallSiteRetypesASharedStringConstant`
    /// subtracts the ledger, so **it** fails on an offender nobody wrote down; this fails on an
    /// entry that has stopped being an offender, which is what stops a fixed line's entry from
    /// quietly covering the next one typed in the same file.
    @Test func everyStaticFuncConstantOffenderIsLedgeredAndEveryLedgerEntryIsStillReal() throws {
        let constants = try cadenceSharedFunctionStringConstants(in: cadenceSharedConstantRoots())
        #expect(constants.isEmpty == false, "non-vacuity: the function harvest returned nothing")

        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        let read = CadenceSourceScan.strippedSourceReader()
        let mcpMembers = try cadenceMCPServerMemberFiles()

        var found: Set<CadenceLiteralSite> = []
        for constant in constants {
            for path in try cadenceSharedConstantOffenders(
                for: constant,
                in: files,
                mcpMembers: mcpMembers,
                read: read
            ) {
                found.insert(CadenceLiteralSite(literal: constant.literal, path: path))
            }
        }

        let ledgered = Set(
            cadenceStaticFuncConstantLedger.map { CadenceLiteralSite(literal: $0.literal, path: $0.path) }
        )
        #expect(
            found.subtracting(ledgered).isEmpty,
            "a static-func constant is re-typed at \(found.subtracting(ledgered).sorted()) and nothing owns it"
        )
        #expect(
            ledgered.subtracting(found).isEmpty,
            """
            \(ledgered.subtracting(found).sorted()) no longer re-types its constant — delete the \
            ledger entry rather than leaving it to forgive the next one.
            """
        )

        // A duplicated entry would satisfy set equality and still double-forgive.
        #expect(cadenceStaticFuncConstantLedger.count == 4,
                "the ledger holds \(cadenceStaticFuncConstantLedger.count) entries, not the four that were measured")
        #expect(cadenceStaticFuncConstantLedger.allSatisfy { $0.ticket.hasPrefix("T-") },
                "a ledger entry names no ticket, so nothing owns the fix")
        #expect(cadenceStaticFuncConstantLedger.allSatisfy { $0.why.count > 40 },
                "a ledger entry does not say why")
    }

    // MARK: - T-700: a constant spelled as a computed property

    /// **T-700.** The reader, pinned on fixtures rather than on the tree, because the tree is the
    /// thing it is supposed to be able to change. A computed `static var` carrying a literal is
    /// harvested; a **stored** one is not — its initializer is the other half's job, and taking it
    /// here would harvest it twice and read the *next* declaration's braces as its body.
    @Test func theComputedVarHarvestReadsAPropertyBodyAndNotAStoredInitializer() {
        let source = """
        enum Fixture {
            static var version: String {
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            }

            static var all: [Fixture] = [one, two]

            static let storedLabel = "Untitled Fixture Label"

            static func vended() -> String { "A vended sentence here" }
        }
        """
        let harvested = cadenceStaticComputedVarBodies(in: source)
        #expect(harvested.map(\.name) == ["version"],
                "the computed-var reader harvested \(harvested.map(\.name))")
        #expect(
            cadencePlainStringLiterals(in: harvested[0].body).contains("CFBundleShortVersionString"),
            "the reader read something other than the property's body"
        )
        // The stored declaration is *not* adopted.
        #expect(harvested.contains { $0.name == "all" } == false)
    }

    /// **The `=` refusal on its own**, because in the fixture above it is not the guard doing the
    /// work: `static func vended()` sits between `all` and the next brace, so the `func` refusal
    /// catches it first and a mutation deleting `!between.contains("=")` **survived**. This is the
    /// source where `=` is the only discriminator — a stored `static var` followed by an `init`,
    /// with no `func`, no `var` and no `}` in between — so the harvest would adopt the
    /// initializer's braces and report a literal nobody declared as a constant.
    @Test func theComputedVarHarvestRefusesAStoredDeclarationOnTheInitializerAlone() {
        let source = """
        enum Fixture {
            static var all: [String] = ["one", "two"]

            init() {
                report("A stored declaration is not a constant")
            }
        }
        """
        // Everything except `=` says this is a body: no `}`, no `func` and no `var` stands between
        // `all` and the brace the harvest would otherwise take.
        let between = " : [String] = [\"one\", \"two\"]\n\n    init() {"
        #expect(between.contains("}") == false)
        #expect(between.contains("func") == false)
        #expect(between.contains("var") == false)

        let harvested = cadenceStaticComputedVarBodies(in: source)
        #expect(
            harvested.isEmpty,
            "a stored `static var` adopted the next declaration's braces: \(harvested.map(\.name))"
        )
    }

    /// The widening, stated as the population it moved rather than as a paragraph. Two constants,
    /// both in one file, and the `Info.plist` keys they name are the whole of what T-700 was about.
    @Test func theComputedVarHalfHarvestsTheBuildIdentityKeysAndNothingElse() throws {
        let harvested = try cadenceSharedComputedVarStringConstants(in: cadenceSharedConstantRoots())
        #expect(
            harvested.map { "\($0.name)=\($0.literal)" }.sorted()
                == ["build=CFBundleVersion", "version=CFBundleShortVersionString"],
            "the computed-var half harvested \(harvested.map { "\($0.name)=\($0.literal)" }.sorted())"
        )
        #expect(harvested.allSatisfy { $0.declaredIn == "Cadence/Shared/AppStoreReviewReadiness.swift" })

        // And the whole harvest is the three halves, so the widening cannot be wired up and then
        // left unread by the sweep.
        let all = try cadenceSharedStringConstants()
        #expect(all.contains { $0.literal == "CFBundleShortVersionString" },
                "the computed-var half is not reaching the sweep")
    }

    /// The reader over **every** Swift file in all three shipped targets, not just the two roots it
    /// is used on. `cadenceStaticFunctionBodies` carries the same test for the same reason: a trap
    /// in a scan helper is a dead test host, and the file that provokes it is as likely to be one a
    /// sibling is mid-way through writing as one of the harvest's own roots.
    @Test func theComputedVarReaderSurvivesEverySwiftFileInTheRepository() throws {
        var filesRead = 0
        var propertiesRead = 0
        for root in ["Cadence", "CadenceWidgets", "CadenceMCPServer", "CadenceTests"] {
            for path in try CadenceSourceScan.swiftFiles(under: root) {
                filesRead += 1
                let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                for property in cadenceStaticComputedVarBodies(in: source) {
                    propertiesRead += 1
                    _ = cadencePlainStringLiterals(in: property.body)
                }
            }
        }
        #expect(filesRead >= 500, "the crash-safety walk read \(filesRead) files")
        #expect(propertiesRead > 0, "non-vacuity: the walk found no computed static var at all")
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
    /// **Re-measured at [[T-505]].** Declaring the seven remaining "Untitled …" labels turned the
    /// sweep's blind spot into hits: **45 more, in 20 files across all three targets, all 45 true
    /// positives, no exemption added.** That is the number that matters about this rule — its
    /// precision was never the limit, its *input* was, and the input is a declaration existing.
    ///
    /// **Re-measured again at the empty-state audit.** Converging nine duplicated empty states into
    /// `CadenceEmptyStateCopy` declared sixteen new shared constants, which is sixteen new needles
    /// for this rule. Fifteen produced no hit outside their declaration; the sixteenth,
    /// `notepadTitle` ("No notes yet"), collided with the phone's note reference picker — **one new
    /// hit, one collision of ordinary English, no new true positives to fix.** That is the same
    /// shape as `Completed Today` and is the second exemption below. The input grew and the
    /// precision did not move.
    ///
    /// This does not re-derive the numbers; it pins the shape of the claim, so the sweep cannot
    /// quietly become an empty rule with a paragraph attached.
    @Test func theSharedConstantSweepWasMeasuredBeforeItShipped() {
        #expect(cadenceSharedLiteralExemptions.count == 2,
                "the exemption list changed size; re-measure the precision claim above it")
        #expect(cadenceSharedLiteralExemptions.first?.literal == "Completed Today")
        #expect(cadenceSharedLiteralExemptions.last?.literal == "No notes yet")
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

/// Every `static let`/`static var` **or `static func`** in `Cadence/Shared/` or
/// `Cadence/Models/` that carries a plain string literal of at least 12 characters that is not a
/// glyph name.
///
/// **`static func` since [[T-555]].** A shared constant that takes a parameter — because it picks
/// between two strings, like `CadenceEmptyStateCopy.goalsTitle(isNarrowed:)` — has to be spelled
/// as a function, and the harvest used to walk straight past it. So the one rule this whole file
/// exists to hold ("every shared user-facing string has one home") did not apply to the constants
/// most likely to be re-typed, since a caller that cannot say `Copy.goalsTitle` in one token is a
/// caller already halfway to typing the words. Found while closing [[T-548]].
///
/// `cadencePlainStringLiterals(in:)` carries the constant-versus-template distinction and its
/// reasoning; the short version is that it is not a new rule, it is this doc comment's last
/// paragraph applied to a body instead of an initializer.
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
    // Two halves, kept as two functions rather than one flag. [[T-555]]'s ledger is a claim about
    // the offenders the **function** half newly reaches; folding a `spelling` discriminator into
    // `CadenceSharedStringConstant` instead would have put it inside an `Equatable` key that other
    // suites construct by hand to assert membership, where getting it wrong is a silently failing
    // comparison rather than a compile failure.
    try cadenceSharedStoredStringConstants(in: cadenceSharedConstantRoots())
        + cadenceSharedFunctionStringConstants(in: cadenceSharedConstantRoots())
        + cadenceSharedComputedVarStringConstants(in: cadenceSharedConstantRoots())
    // A total order, not just an order on the literal: one function can vend several constants and
    // one literal can be vended twice, so sorting on the literal alone leaves the result up to
    // `sort`'s instability and makes a harvest that reads the same tree twice answer differently.
        .sorted { ($0.literal, $0.declaredIn, $0.name) < ($1.literal, $1.declaredIn, $1.name) }
}

/// `Cadence/Shared/` and `Cadence/Models/`, the two trees a shared constant may be declared in.
func cadenceSharedConstantRoots() throws -> [String] {
    try CadenceSourceScan.swiftFiles(under: "Cadence/Shared")
        + CadenceSourceScan.swiftFiles(under: "Cadence/Models")
}

/// The half of the harvest that reads an initializer: `static let x = "…"`.
func cadenceSharedStoredStringConstants(in roots: [String]) throws -> [CadenceSharedStringConstant] {
    let pattern = try NSRegularExpression(
        pattern: #"static\s+(?:let|var)\s+(\w+)\s*(?::\s*String\s*)?=\s*"([^"\\]{12,})""#
    )
    var found: [CadenceSharedStringConstant] = []
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
    return found
}

/// The half of the harvest that reads a **body**: `static func x(…) -> String { … "…" … }`.
///
/// [[T-555]]. The distinction between a constant and a template is carried entirely by
/// `cadencePlainStringLiterals(in:)`, and it is the same distinction the stored half draws with
/// `[^"\\]` — read its doc comment before changing anything here.
func cadenceSharedFunctionStringConstants(in roots: [String]) throws -> [CadenceSharedStringConstant] {
    var found: [CadenceSharedStringConstant] = []
    for path in roots {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        for function in cadenceStaticFunctionBodies(in: source) {
            for literal in Set(cadencePlainStringLiterals(in: function.body)).sorted() {
                guard literal.count >= 12, !cadenceIsGlyphName(literal) else { continue }
                found.append(
                    CadenceSharedStringConstant(name: function.name, literal: literal, declaredIn: path)
                )
            }
        }
    }
    return found
}

/// The half of the harvest that reads a **computed property**: `static var x: String { … "…" … }`.
///
/// **T-700.** [[T-555]] taught the harvest to read a `static func` body and stopped there, so a
/// constant spelled as a computed `static var` stayed invisible for exactly the reason a function
/// was: the stored half only ever matched the initializer pattern `= "…"`, and a computed property
/// has no initializer. `CadenceAppBuildIdentity.version` and `.build` are the two on this tree, and
/// both of their `Info.plist` keys were re-typed in `CadenceDataExportService` — the second
/// hand-written copy `CadenceAppBuildIdentity`'s own doc comment says is how two surfaces come to
/// disagree about which key holds the build number. A wrong key there is a silent `?? "0"` rather
/// than a crash, which is what makes it the kind of duplication that drifts unnoticed.
///
/// The literal test is `cadencePlainStringLiterals(in:)`, the same lexer the function half uses and
/// for the same reason — read its doc comment before changing anything here.
func cadenceSharedComputedVarStringConstants(in roots: [String]) throws -> [CadenceSharedStringConstant] {
    var found: [CadenceSharedStringConstant] = []
    for path in roots {
        let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
        for property in cadenceStaticComputedVarBodies(in: source) {
            for literal in Set(cadencePlainStringLiterals(in: property.body)).sorted() {
                guard literal.count >= 12, !cadenceIsGlyphName(literal) else { continue }
                found.append(
                    CadenceSharedStringConstant(name: property.name, literal: literal, declaredIn: path)
                )
            }
        }
    }
    return found
}

/// The files that re-type `constant` and are not forgiven by the target boundary or by a measured
/// exemption — the sweep's verdict **before** [[T-555]]'s ledger is subtracted.
///
/// Split out of the sweep so the ledger has something to be checked against. A rule that both
/// defers a hit and decides what the hits are cannot be audited: the deferral would define itself
/// as complete.
func cadenceSharedConstantOffenders(
    for constant: CadenceSharedStringConstant,
    in files: [String],
    mcpMembers: Set<String>,
    read: (String) throws -> String
) throws -> [String] {
    let hits = try sharedLiteralInstrument(for: constant).sweep(
        files,
        // 300+ Swift files under `Cadence/`; the floor `CadenceRetiredCopyTests` uses for the same
        // tree.
        atLeast: 300,
        // The file that held four of this sweep's first hits, so a walk that skipped the iOS tree
        // cannot report the repo clean.
        including: "Cadence/iOS/iOSFocusView.swift",
        read: read
    )
    // The target boundary, stated as the rule it always meant (T-499): a file cannot read a
    // constant declared in a file its own target does not compile. So the subtraction applies only
    // while the *declaration* is out of `CadenceMCPServer`'s reach — a constant in `Models/` is
    // reachable from every target, and an MCP file re-typing one of those is an ordinary offender.
    // This is what makes the boundary self-retiring: moving a declaration into `Models/` deletes
    // its subtraction with no edit here.
    let unreachableFromMCP = !mcpMembers.contains(constant.declaredIn)
    return hits.filter { path in
        path != constant.declaredIn
            && !(unreachableFromMCP && mcpMembers.contains(path))
            && !cadenceSharedLiteralExemptions.contains {
                $0.literal == constant.literal && $0.path == path
            }
    }
}

// MARK: - A constant spelled as a function

/// Every **whole, uninterpolated** string literal in `source`, in the order they appear.
///
/// **T-555, and the whole of the constant/template distinction lives here.** A `static func`
/// returning a string is a *constant* when it picks between finished strings — `goalsTitle(isNarrowed:)`
/// — and a *template* when it assembles one — `markedDayLabel(date:hasItems:)`. Nothing about the
/// signature separates those two, and nothing needs to: **the literal does.** A template's product
/// is built at run time, so no call site can re-type it verbatim, so it is not the defect this
/// sweep can act on. That is not a new rule invented for functions; it is the rule the `static let`
/// half has always enforced by writing its initializer pattern as `"([^"\\]{12,})"`, where the
/// `\\` exclusion rejects an interpolated value before anything else looks at it.
///
/// **Which is why this is a lexer and not a regex.** Applied to a function *body* rather than to an
/// initializer, `"([^"\\\n]{12,})"` stops being anchored and starts pairing quotes that do not
/// belong together. Measured on this tree, it harvests three things that are not literals a call
/// site could type:
///
/// - `"has scheduled items"` out of `"\(dayName(date)), \(hasItems ? "has scheduled items" : emptyPhrase)"` —
///   a fragment *nested inside* a template. The `static let` half cannot see one of these, because
///   its pattern fails at the leading `\`, so harvesting it from a function would have widened what
///   counts as a literal while claiming only to widen where they are looked for.
/// - `") receive this session's time."` — the tail of an interpolated literal, read as though the
///   interpolation's closing quote opened it.
/// - `" : String(format: "` out of `DateFormatters.timeString` — the closing quote of one literal
///   paired with the opening quote of the next, so the "constant" is a span of **code**. Harmless
///   on this tree only because nothing else types it; a detector reading source as copy is the
///   `codeOnly` trap wearing different clothes.
///
/// So: scan left to right, and when a literal turns out to hold an escape or an interpolation,
/// discard it **and everything nested inside it**. Raw (`#"…"#`) and multi-line (`"""…"""`)
/// literals are skipped whole for the same reason — their text is not what a call site would type.
func cadencePlainStringLiterals(in source: String) -> [String] {
    let chars = Array(source)
    var literals: [String] = []
    var index = 0
    while index < chars.count {
        if chars[index] == "#", let past = cadenceSkippingRawLiteral(chars, from: index) {
            index = past
            continue
        }
        guard chars[index] == "\"" else {
            index += 1
            continue
        }
        if index + 2 < chars.count, chars[index + 1] == "\"", chars[index + 2] == "\"" {
            index = cadenceSkippingMultilineLiteral(chars, from: index + 3)
            continue
        }
        let scanned = cadenceScanningLiteral(chars, from: index)
        if let plain = scanned.plain { literals.append(plain) }
        index = scanned.next
    }
    return literals
}

/// One `"…"`. `plain` is non-`nil` only when the literal holds neither an escape nor an
/// interpolation — the same condition `[^"\\]` states in the stored-value half of the harvest.
private func cadenceScanningLiteral(
    _ chars: [Character],
    from start: Int
) -> (plain: String?, next: Int) {
    var index = start + 1
    var text = ""
    var plain = true
    while index < chars.count {
        switch chars[index] {
        case "\\":
            plain = false
            if index + 1 < chars.count, chars[index + 1] == "(" {
                index = cadenceSkippingInterpolation(chars, from: index + 1)
            } else {
                index += 2
            }
        case "\"":
            return (plain ? text : nil, index + 1)
        case "\n":
            // An unterminated literal is a mis-read, not a constant: give up on it rather than
            // running to the end of the file and swallowing everything after it.
            return (nil, index + 1)
        default:
            text.append(chars[index])
            index += 1
        }
    }
    return (nil, chars.count)
}

/// The body of a `\( … )`, skipped whole. **Including any literal inside it** — that nesting is
/// what makes "has scheduled items" part of a template rather than a constant of its own.
private func cadenceSkippingInterpolation(_ chars: [Character], from start: Int) -> Int {
    var depth = 0
    var index = start
    while index < chars.count {
        switch chars[index] {
        case "\"":
            index = cadenceScanningLiteral(chars, from: index).next
        case "(":
            depth += 1
            index += 1
        case ")":
            depth -= 1
            index += 1
            if depth == 0 { return index }
        default:
            index += 1
        }
    }
    return chars.count
}

/// `nil` when the `#` at `start` does not open a raw literal, so the caller keeps reading.
private func cadenceSkippingRawLiteral(_ chars: [Character], from start: Int) -> Int? {
    var hashes = 0
    while start + hashes < chars.count, chars[start + hashes] == "#" { hashes += 1 }
    guard start + hashes < chars.count, chars[start + hashes] == "\"" else { return nil }
    var index = start + hashes + 1
    while index < chars.count {
        if chars[index] == "\"" {
            var closing = 0
            while index + 1 + closing < chars.count, chars[index + 1 + closing] == "#" { closing += 1 }
            if closing >= hashes { return index + 1 + hashes }
        }
        index += 1
    }
    return chars.count
}

private func cadenceSkippingMultilineLiteral(_ chars: [Character], from start: Int) -> Int {
    var index = start
    while index + 2 < chars.count {
        if chars[index] == "\"", chars[index + 1] == "\"", chars[index + 2] == "\"" {
            return index + 3
        }
        index += 1
    }
    return chars.count
}

/// Every `static func` body in `source`, paired with the function's name.
///
/// Brace-matched rather than regex-matched, and the parameter list is balanced **first** — the
/// [[T-644]] rule. A signature carrying `commit: (ModelContext) throws -> Void = { try $0.save() }`
/// opens a brace of its own, and taking the first `{` after the name would read that default
/// closure as the body. Balancing `(` … `)` before looking for `{` also gets generic parameter
/// lists and `where` clauses for free.
func cadenceStaticFunctionBodies(in source: String) -> [(name: String, body: String)] {
    guard let pattern = try? NSRegularExpression(pattern: #"\bstatic\s+func\s+(\w+)"#) else { return [] }
    var bodies: [(name: String, body: String)] = []
    let range = NSRange(source.startIndex..., in: source)
    for match in pattern.matches(in: source, range: range) {
        guard let nameRange = Range(match.range(at: 1), in: source),
              let parameters = CadenceSourceScan.matchedRange(
                  after: nameRange.upperBound,
                  in: source,
                  open: "(",
                  close: ")"
              ) else { continue }
        // A declaration with no body of its own — a protocol requirement — would otherwise adopt
        // the *next* declaration's braces and be harvested as if it held that declaration's
        // literals. What separates the two is the text between the parameter list and the brace:
        // for a real body it is a return type, so a `}` or the word `func` in there means the
        // brace found belongs to something else.
        guard let body = CadenceSourceScan.matchedRange(
            after: parameters.upperBound,
            in: source,
            open: "{",
            close: "}"
        ) else { continue }
        // **Refused rather than asserted, and the ordering is not in doubt.** `matchedRange`
        // searches for the brace *from* the closing parenthesis, so `body.lowerBound` is one past a
        // brace at or after `parameters.upperBound` and the pair cannot invert — verified in real
        // Swift over 2288 `static func` declarations in 852 files, plus twelve adversarial shapes
        // (an unbalanced paren, brace or quote inside a default literal; a bodiless declaration; a
        // grapheme cluster before the name), none of which inverted it. This still declines to form
        // the span, because the cost of being wrong is asymmetric: a source-scan helper that traps
        // takes the **whole test host** down, and a crashed host emits no `.swift:line:col: error:`
        // lines at all, so the run reads as "nothing to see" rather than "this died". That failure
        // mode is the one `docs/SUBAGENT_RUNBOOK.md` warns reads as a surviving mutation.
        guard parameters.upperBound <= body.lowerBound else { continue }
        let between = source[parameters.upperBound..<body.lowerBound]
        guard !between.contains("func"), !between.contains("}") else { continue }
        bodies.append((String(source[nameRange]), String(source[body])))
    }
    return bodies
}

/// Every **computed** `static var` body in `source`, paired with the property's name.
///
/// **T-700.** The same brace matching `cadenceStaticFunctionBodies(in:)` does, with the one
/// difference that separates a computed property from a stored one: there is no parameter list, so
/// the body's `{` is the first brace after the type annotation, and a `=` between the name and that
/// brace means the declaration is **stored** — `static var all: [X] = [privacyPolicy, support]`,
/// whose "body" would otherwise be the next declaration's. `func`, `var` or `}` in the same span
/// says the same thing more loudly: the brace found belongs to something else.
///
/// Refused rather than asserted, for the reason `cadenceStaticFunctionBodies` records at length: a
/// source-scan helper that traps takes the whole test host with it, and a crashed host emits no
/// `.swift:line:col: error:` line at all, so the run reads as "nothing to see".
func cadenceStaticComputedVarBodies(in source: String) -> [(name: String, body: String)] {
    guard let pattern = try? NSRegularExpression(pattern: #"\bstatic\s+var\s+(\w+)\s*:"#) else { return [] }
    var bodies: [(name: String, body: String)] = []
    let range = NSRange(source.startIndex..., in: source)
    for match in pattern.matches(in: source, range: range) {
        guard let nameRange = Range(match.range(at: 1), in: source),
              let body = CadenceSourceScan.matchedRange(
                  after: nameRange.upperBound,
                  in: source,
                  open: "{",
                  close: "}"
              ) else { continue }
        guard nameRange.upperBound <= body.lowerBound else { continue }
        let between = source[nameRange.upperBound..<body.lowerBound]
        guard !between.contains("="), !between.contains("}"),
              !between.contains("func"), !between.contains("var") else { continue }
        bodies.append((String(source[nameRange]), String(source[body])))
    }
    return bodies
}
