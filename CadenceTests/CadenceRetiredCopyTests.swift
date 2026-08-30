import Foundation
import Testing
@testable import Cadence

// MARK: - The declared list

/// One string this app has deliberately stopped saying, and why.
///
/// `stillAllowedIn` is for phrases that are wrong *on the screens that retired them* and fine
/// somewhere else — a picker with nothing to pick is not the same statement as a page with no work
/// on it, which is the carve-out `CadenceDesktopEmptyStateConvergenceTests` already makes for
/// `FocusPickerSupportViews`. Every entry in it is checked for staleness below, so an exemption
/// cannot outlive the line it was written for.
struct CadenceRetiredPhrase {
    let text: String
    /// The ticket that retired it, or the constant that records the decision.
    let retiredBy: String
    let why: String
    let stillAllowedIn: [String]

    init(_ text: String, retiredBy: String, why: String, stillAllowedIn: [String] = []) {
        self.text = text
        self.retiredBy = retiredBy
        self.why = why
        self.stillAllowedIn = stillAllowedIn
    }
}

/// **The one collection.** Adding a retired phrase is a line here and nothing else: the sweep below
/// walks every Swift file under `Cadence/` for every entry, so a screen written next year inherits
/// the whole list without anyone remembering to name it.
///
/// That inheritance is the point. T-285 retired "Create a task to get started" and pinned it — but
/// pinned it *against `TasksListView.swift`*, and the string was alive in `ListDetailComponents`
/// (T-473) and, together with "No tasks yet", in `TasksPanel` the whole time. Per-screen guards
/// find the screen you were looking at. This one finds the file you had not thought of.
let cadenceRetiredCopy: [CadenceRetiredPhrase] = [
    CadenceRetiredPhrase(
        "Create a task to get started",
        retiredBy: "T-285",
        why: """
        A restatement of the floating "+" already on screen behind it. The empty state names the \
        reachable control instead — CadenceEmptyStateCopy.listDetailSubtitle.
        """
    ),
    CadenceRetiredPhrase(
        "No tasks yet",
        retiredBy: "T-285",
        why: """
        The Mac's spelling of a title the phone wrote three other ways. Note that \
        CadenceEmptyStateCopy.listDetailTitle is "No tasks here" and not "No tasks here yet" \
        precisely so a revert cannot hide inside the replacement.
        """,
        // A reference picker is empty because there is nothing to *link*, not because there is no
        // work; its subtitle ("Create a task first, then reference it here.") says so. Same
        // distinction, same reason, as the FocusPicker carve-out T-285 wrote down.
        stillAllowedIn: ["Cadence/iOS/iOSMarkdownAccessoryViews.swift"]
    ),
    CadenceRetiredPhrase(
        "Inbox is empty",
        retiredBy: "T-285",
        why: #"The Mac's Inbox title against the phone's "Inbox is clear". One idea, one sentence."#
    ),
    CadenceRetiredPhrase(
        "Add a task above",
        retiredBy: "CadenceTodayPresentationSupport.emptySubtitle",
        why: """
        Names an inline field that exists on no width: compact capture is the tab bar's centre "+", \
        iPad's is this page's floating one, and the Mac's is the glyph on the task column header. \
        Copy naming a control that is not on screen is worse than no copy (T-469).
        """
    ),
    CadenceRetiredPhrase(
        "Nothing planned for today",
        retiredBy: "CadenceTodayPresentationSupport.emptyTitle",
        why: """
        The iPad's leftover title for a five-card empty deck that was deleted. Two spellings of one \
        sentence, one of them unreachable, is how the hosts start disagreeing again.
        """
    ),
    CadenceRetiredPhrase(
        "Today tasks will appear here.",
        retiredBy: "T-519",
        why: """
        iOSFocusView's detail-pane placeholder, and false in both cases it was drawn in. \
        `selectedItem` falls back to `pickItems.first`, so it appeared either while the picker \
        pane beside it was showing the shared focus empty state about the same list, or while a \
        deleted subject left the pane empty with today's tasks listed to the left. The pane says \
        CadenceEmptyStateCopy.focusSubtitle in the first case and "Select an item from the list." \
        in the second.
        """
    ),
    CadenceRetiredPhrase(
        "Create a goal, then set its date range.",
        retiredBy: "T-525",
        why: """
        The Goals roadmap's first-run subtitle, and the second clause was not a requirement. \
        `GoalTimelineView.rows` is built from `GoalMissionGrouping.groups` alone, which reads no \
        date, so one undated goal already fills the page — with a rail row and a "No date" chip. \
        The sentence told a reader who had made a goal that the page in front of them was waiting \
        on dates. What dates actually buy is the bar, and the copy says that instead.
        """
    ),
    CadenceRetiredPhrase(
        "Cadence account and data were deleted.",
        retiredBy: "T-474",
        why: """
        Sign in with Apple is macOS-only, so on iPhone and iPad the reset clears no account profile \
        and the success notice must not say it did. The sentence itself is not retired — macOS \
        still shows it — so it is allowed exactly where it is defined and nowhere else.
        """,
        stillAllowedIn: ["Cadence/Services/CadencePrivacyDataResetService.swift"]
    ),
    CadenceRetiredPhrase(
        "Delete Account & Data",
        retiredBy: "T-474",
        why: """
        The same claim as the notice above, one control earlier: it was the iOS section label while \
        the button beneath it correctly read "Delete Cadence Data". macOS keeps it, because macOS \
        keeps the account.
        """,
        stillAllowedIn: ["Cadence/macOS/Views/SettingsDataSafetySection.swift"]
    ),
]

// MARK: - The sweep

/// **Retired copy, checked once for the whole app instead of once per screen.**
///
/// The through-line behind T-473 and T-469: both were live instances of copy this repo had already
/// decided against, and both survived because the guard that retired the wording was written
/// against the single file the author happened to be editing. Two more per-screen assertions would
/// have left the next screen just as unprotected.
///
/// Comments are stripped before every check, which is deliberate and load-bearing: this repo
/// records retired wording in tombstone comments on purpose — `TasksListView`, `InboxSupportViews`,
/// `CadenceTasksPageScope` and `CadenceTodayPresentationSupport` all quote strings from this list —
/// and those paragraphs are the institutional memory, not the offence.
@MainActor
struct CadenceRetiredCopyTests {

    /// The sweep. Every entry, every Swift file under `Cadence/`.
    ///
    /// It runs through `CadenceScanInstrument` rather than a bare `contains`, for the T-161 reason:
    /// "no offenders" is what a clean repo and a blinded detector both look like, and `sweep`'s
    /// non-defaulted `atLeast:`/`including:` make the walk's non-vacuity a compile requirement
    /// rather than something a reader has to notice is missing.
    @Test func noRetiredCopyIsStillDrawnAnywhereInTheApp() throws {
        let files = try retiredCopySwiftFiles(under: "Cadence")
        let read = retiredCopyStrippedSourceReader()

        for phrase in cadenceRetiredCopy {
            let hits = try retiredCopyInstrument(for: phrase).sweep(
                files,
                // 300+ Swift files under `Cadence/`; the same floor
                // `CadencePrivacyDataResetSurfaceTests` uses for the same tree.
                atLeast: 300,
                // The file T-473 was found in, so a walk that skipped the macOS view folder
                // cannot report this list clean.
                including: "Cadence/macOS/Views/ListDetailComponents.swift",
                read: read
            )
            let offenders = hits.filter { !phrase.stillAllowedIn.contains($0) }

            #expect(
                offenders.isEmpty,
                """
                "\(phrase.text)" was retired by \(phrase.retiredBy) and is still drawn in \
                \(offenders). \(phrase.why)
                """
            )
        }
    }

    /// The walk itself, named rather than trusted.
    ///
    /// `sweep` already refuses an empty or short list, but it cannot know that the tree it walked
    /// is the app: an `atLeast:` satisfied entirely by one folder would pass. These are the four
    /// surfaces the list is about, one of them the iOS tree the macOS test target cannot compile.
    @Test func theRetiredCopySweepReachesEverySurfaceOfTheApp() throws {
        let files = try retiredCopySwiftFiles(under: "Cadence")

        for path in [
            "Cadence/Shared/CadenceEmptyStateCopy.swift",
            "Cadence/iOS/iOSListDetailView.swift",
            "Cadence/macOS/Views/TasksPanel.swift",
            "Cadence/Services/CadencePrivacyDataResetService.swift",
        ] {
            #expect(files.contains(path), "the retired-copy sweep never reaches \(path)")
        }

        // Reading contents, not just listing names: a walk that yields paths it cannot open would
        // satisfy every absence assertion above.
        #expect(
            try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceEmptyStateCopy.swift")
                .contains("nonisolated enum CadenceEmptyStateCopy"),
            "non-vacuity: the sweep's reader returned no content"
        )
    }

    /// Exemptions rot. Each one claims a specific file still says a specific thing for a specific
    /// reason; when that stops being true the entry is dead weight that can only ever hide a
    /// regression, so it has to fail rather than sit there.
    @Test func everyRetiredCopyExemptionIsStillLoadBearing() throws {
        for phrase in cadenceRetiredCopy {
            for path in phrase.stillAllowedIn {
                let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
                #expect(
                    code.contains(phrase.text),
                    """
                    \(path) no longer says "\(phrase.text)" — delete the exemption from \
                    cadenceRetiredCopy rather than leaving it to cover the next offender.
                    """
                )
            }
        }
    }

    /// The list is a list, and it still holds the entries the two tickets that built it are about.
    /// Without this, deleting `cadenceRetiredCopy` down to nothing turns the sweep green.
    @Test func theRetiredCopyListStillHoldsTheDecisionsItWasBuiltFrom() {
        #expect(cadenceRetiredCopy.count >= 7)

        let texts = Set(cadenceRetiredCopy.map(\.text))
        #expect(texts.contains("Create a task to get started"), "T-473's string left the list")
        #expect(texts.contains("Add a task above"), "T-469's string left the list")
        #expect(texts.contains("Cadence account and data were deleted."), "T-474's string left the list")
        #expect(texts.count == cadenceRetiredCopy.count, "the list holds a duplicate phrase")

        // Every entry says which decision retired it and why; an entry that does not is a string
        // nobody can safely delete later.
        for phrase in cadenceRetiredCopy {
            #expect(!phrase.text.isEmpty)
            #expect(!phrase.retiredBy.isEmpty, "\"\(phrase.text)\" does not name the decision that retired it")
            #expect(phrase.why.count > 40, "\"\(phrase.text)\" does not say why")
        }
    }

    /// The detector, against the tree rather than against its own fixtures.
    ///
    /// The instrument's literal witnesses prove it can still tell a live string from a commented
    /// one; this proves the two shapes it was tuned on are the two shapes the repo actually holds.
    /// Both halves are wanted: fixtures cannot be retuned by an edit to the tree, and the tree
    /// cannot drift away from the fixtures without one of these failing.
    @Test func theRetiredCopyDetectorSeparatesALiveStringFromATombstone() throws {
        let phrase = try #require(cadenceRetiredCopy.first { $0.text == "No tasks yet" })
        let instrument = try retiredCopyInstrument(for: phrase)

        // Yes: the reference picker's live `emptyTitle`, which is why it is exempt rather than
        // undetected — the sweep sees it and the allowlist forgives it.
        let picker = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSMarkdownAccessoryViews.swift")
        #expect(instrument.fires(on: picker))

        // No: a file whose only copy of the phrase is the paragraph recording its retirement.
        let tombstone = try CadenceSourceScan.sourceFile("Cadence/macOS/Views/TasksListView.swift")
        #expect(tombstone.contains("No tasks yet"), "non-vacuity: the tombstone is gone")
        #expect(instrument.fires(on: tombstone) == false, "the sweep counts tombstone comments as offences")
    }
}

// MARK: - Fixtures

/// The detector for one phrase, as an instrument that cannot be built once it stops discriminating.
///
/// The witnesses are the nearest possible miss: the same line, once live and once commented out.
/// That is the pair this scan gets wrong if it gets anything wrong, because the retired strings in
/// this repo appear far more often in tombstones than in code.
private func retiredCopyInstrument(for phrase: CadenceRetiredPhrase) throws -> CadenceScanInstrument {
    try CadenceScanInstrument(
        "retired copy: \(phrase.text)",
        fires: """
        struct Screen {
            let subtitle = "\(phrase.text)"
        }
        """,
        andNotOn: """
        struct Screen {
            // It used to read "\(phrase.text)"; see \(phrase.retiredBy).
            let subtitle = "something else"
        }
        """,
        by: { CadenceSourceScan.strippingComments($0).contains(phrase.text) }
    )
}

/// Reads each file once and hands the sweep source with its comments already blanked.
///
/// The detector strips again on whatever it is given, and must: that is what its two witnesses
/// check, and moving the strip out of the detector to save time here would leave the instrument
/// unable to tell a live string from a tombstone — the one distinction it exists to make.
/// `strippingComments` is idempotent, so the second pass over already-blank text costs two failed
/// regex searches. Reading and stripping every file once per *phrase* would not: the stripper
/// rescans from the start of the string after each match, which is quadratic, and there are seven
/// phrases and 300-odd files.
private func retiredCopyStrippedSourceReader() -> (String) throws -> String {
    CadenceSourceScan.strippedSourceReader()
}

/// Enumerated by `enumerator(atPath:)` rather than `enumerator(at:)`: the URL variant yields
/// absolute paths, and `#filePath` can name the repo through a symlinked prefix (`/tmp` against
/// `/private/tmp` on an isolated build tree) that `FileManager` resolves and the literal does not.
private func retiredCopySwiftFiles(under relativeDirectory: String) throws -> [String] {
    try CadenceSourceScan.swiftFiles(under: relativeDirectory)
}
