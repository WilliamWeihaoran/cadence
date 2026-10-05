import Foundation
import Testing
@testable import Cadence

/// **One "what is in here" sentence per page, read by both search surfaces.**
///
/// T-1782: `CadenceFeatureDestination.searchSummary` was drawn in exactly one place — the third
/// line of an iOS search Pages row — while macOS's Cmd+K drew a `baseSubtitle` of its own for the
/// same pages, and the two disagreed about **seven of the nine** rows the palette has. Today read
/// "Daily dashboard and timeline" there and "Tasks, notes, and schedule" here; Notes "Workspace
/// notes" against "Daily, weekly, and permanent notes". Both strings were matched against, so the
/// words a query had to use to find a page differed by platform too.
///
/// **The rule was checked before anything was unified, and it does not decide this.** Page headers
/// do not describe the page the reader is already on, but search rows, pickers and empty states may
/// keep subtitles — and both of these are search *rows*. So the standing rule permits two registers
/// without requiring them. What decides it is that `baseSubtitle` was a **contents** line for all
/// nine entries, which is what `searchSummary` is, and that two of them were already `searchSummary`
/// verbatim because [[T-1701]] took them *from* the palette.
///
/// **Why these live in their own file rather than beside `CadenceFeatureDestinationCopyTests`.**
/// That suite holds the *pair* on one destination apart — subtitle against summary, the T-1701
/// contract. This one is about the two platforms agreeing, which is a different claim about the same
/// strings; and the file that declares that suite was leased to another agent while this landed.
///
/// **The enforcement is that there is nowhere left to put a second opinion**, not that two lists
/// currently agree. `GlobalSearchPageDefinition` stores one thing — the destination — and derives
/// its label, its subtitle and its aliases, exactly as T-258 deleted its stored `icon` rather than
/// leaving it stored-and-equal. A test that merely *compared* two stored lists would be green the
/// day somebody edited both, which is how the two agreed about Inbox and Goals and disagreed about
/// the other seven.
struct CadenceFeatureDestinationSearchConvergenceTests {

    /// **The behaviour.** Every row Cmd+K draws in its Pages section says what the destination says
    /// is in that page — the same sentence the iOS search row draws on its third line.
    ///
    /// Asserted through `pageResults`, which is the function that builds the row, rather than
    /// against the catalog: the subtitle a reader sees is assembled there (it is where the
    /// "• Hidden from sidebar" suffix is appended), so the catalog agreeing is not the claim.
    @Test func everyPaletteRowDrawsItsDestinationsOwnContentsSentence() {
        let rows = GlobalSearchDataSupport.pageResults(
            query: "",
            hiddenTabs: [],
            sidebarTabColorsRaw: ""
        )
        // Non-vacuity: a loop over nothing passes, and so does a lookup that never hits.
        #expect(rows.count == GlobalSearchPageDefinition.all.count)
        #expect(rows.count >= 7, "read \(rows.count) palette page rows")

        var matched = 0
        for page in GlobalSearchPageDefinition.all {
            let row = rows.first { $0.id == "page-\(page.feature.title)" }
            #expect(row != nil, "\(page.feature.rawValue) produced no palette row")
            guard let row else { continue }
            matched += 1
            #expect(
                row.subtitle == page.feature.searchSummary,
                "the palette says \"\(row.subtitle)\" about \(page.feature.rawValue) and the destination says \"\(page.feature.searchSummary)\" (T-1782)"
            )
            #expect(row.title == page.feature.title)
        }
        #expect(matched == GlobalSearchPageDefinition.all.count)

        // The suffix is still appended to that sentence rather than replacing it, so converging
        // the copy did not quietly drop the one thing the palette's own string was doing.
        let hidden = GlobalSearchDataSupport.pageResults(
            query: "",
            hiddenTabs: [.focus],
            sidebarTabColorsRaw: ""
        ).first { $0.id == "page-Focus" }
        #expect(hidden?.subtitle == "\(CadenceFeatureDestination.focus.searchSummary) • Hidden from sidebar")
    }

    /// **The enforcement, which is that there is nowhere left to put a second opinion.** The
    /// catalog stores one fact per row — the destination — and every string it used to carry is
    /// derived. A test that merely *compared* two stored lists would be green the day somebody
    /// edited both, which is how the two lists agreed about Inbox and Goals and disagreed about
    /// the other seven.
    ///
    /// Counted as a relation between the entry count and the literal count rather than against a
    /// fixed nine, so a tenth page is covered the day it is added.
    @Test func thePalettesPageCatalogStoresNothingButTheDestination() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/GlobalSearchSupportViews.swift"
        )
        let definition = try #require(
            CadenceSourceScan.declarationBody("struct GlobalSearchPageDefinition", in: source),
            "GlobalSearchPageDefinition no longer reads as a declaration this scan can scope to"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\n    let [a-zA-Z]+:"#, in: definition) == 1,
            "GlobalSearchPageDefinition stores something besides the destination again (T-1782)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"let feature: CadenceFeatureDestination"#, in: definition) == 1,
            "GlobalSearchPageDefinition no longer stores the destination it is about"
        )

        let catalog = try #require(
            CadenceSourceScan.declarationBody("extension GlobalSearchPageDefinition", in: source),
            "the Pages catalog no longer reads as an extension this scan can scope to"
        )
        let entries = CadenceSourceScan.matchCount(#"\.init\(feature: \."#, in: catalog)
        #expect(
            entries == GlobalSearchPageDefinition.all.count,
            "scanned \(entries) catalog entries against \(GlobalSearchPageDefinition.all.count) rows"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\""#, in: catalog) == 0,
            "the Pages catalog types a string again, and every string it used to type was a second answer to a question CadenceFeatureDestination already answers (T-1782)"
        )
    }

    /// **The words a query has to use no longer depend on the platform.** Cmd+K matched against its
    /// own per-page `aliases` and iOS against `searchAliases`, so five words reached a page on one
    /// platform and nothing on the other. They were folded into `searchKeywords` rather than
    /// dropped, and this is the half of T-1782 that says nothing stopped being findable.
    @Test func theWordsThatReachAPageAreTheSameOnBothPlatforms() {
        let strandedOnTheDesktop: [(CadenceFeatureDestination, [String])] = [
            (.today, ["dashboard", "daily"]),
            // Goals' two stranded words — "targets", "stages" — went with the destination in
            // T-2076; there is no page left for them to reach.
            (.notes, ["docs"]),
            (.allTasks, ["tasks", "all"]),
            (.calendar, ["schedule", "events"])
        ]
        for (destination, words) in strandedOnTheDesktop {
            for word in words {
                #expect(
                    destination.searchAliases.localizedCaseInsensitiveContains(word),
                    "\"\(word)\" no longer reaches \(destination.rawValue), and it reached it from Cmd+K before T-1782"
                )
                #expect(
                    GlobalSearchDataSupport.pageResults(
                        query: word,
                        hiddenTabs: [],
                        sidebarTabColorsRaw: ""
                    ).contains { $0.id == "page-\(destination.title)" },
                    "the palette no longer finds \(destination.rawValue) for \"\(word)\" (T-1782)"
                )
            }
        }

        // The control: a word no page claims finds none of them, so the assertions above are not
        // passing because everything matches everything.
        #expect(
            GlobalSearchDataSupport.pageResults(
                query: "zzqqx",
                hiddenTabs: [],
                sidebarTabColorsRaw: ""
            ).isEmpty
        )
    }
}

/// **The Commands half of the same convergence** (T-1940).
///
/// T-1782 emptied `GlobalSearchPageDefinition` of every stored string and left the catalog one
/// struct up untouched. `GlobalSearchCommandDefinition` stored `title`, `subtitle`, `icon` and
/// `aliases` beside its `command`, and **measured here, not inherited**: of its **six** rows,
/// **five** stored a title *and* a glyph that were character-for-character the destination's own —
/// Focus/`timer`, Today/`sun.max.fill`, All Tasks/`checklist`, Calendar/`calendar`,
/// Settings/`gearshape.fill`. Ten stored-and-equal strings. `.newTask` is the one genuine
/// exception: it opens the capture sheet rather than a page, so it has no destination to read and
/// its `plus.circle.fill` is its own.
///
/// **Why the count is not the Pages count's shape.** T-1782's ticket said nine of eleven Pages rows
/// disagreed and the real figure was seven of nine, because `.lists` and `.search` have no palette
/// row at all. Nothing of that kind is possible here: `GlobalSearchCommand` has exactly six cases
/// and the catalog lists all six, because a command case exists *only* because the palette offers
/// it. Six rows, six cases, five with a destination — and
/// `thePaletteOffersARowForEveryCommandItDeclares` pins that rather than leaving it to a reader.
///
/// **The enforcement is the deletion, not an agreement.** A test that compared the stored title to
/// `feature.title` would be green today and green the day somebody edited both — which is exactly
/// how the Pages glyphs agreed about eight rows and quietly disagreed about Notes. The stored
/// fields are gone, so there is nowhere for a sixth phrasing to live.
///
/// `subtitle` is deliberately **not** swept in. "Open the Today page" names what the command does
/// where a Pages row's sentence names what is in the page; a one-line row has room for one
/// sentence and the action is the right one. That is a second register, not a second answer.
@MainActor
struct CadenceCommandPaletteCommandCatalogTests {

    private static func commandRows() -> [GlobalSearchResult] {
        GlobalSearchDataSupport.commandResults(
            query: "",
            sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
        )
    }

    private static func row(
        for command: GlobalSearchCommand,
        in rows: [GlobalSearchResult]
    ) -> GlobalSearchResult? {
        rows.first { $0.destination == .command(command) }
    }

    /// **Non-vacuity, and the count this ticket turns on, counted rather than quoted.** Every loop
    /// below runs over these rows, and a loop over nothing passes.
    @Test func thePaletteOffersARowForEveryCommandItDeclares() {
        let rows = Self.commandRows()
        #expect(rows.count == GlobalSearchCommandDefinition.all.count)
        #expect(rows.count == GlobalSearchCommand.allCases.count)
        #expect(rows.count >= 6, "read \(rows.count) command rows")

        for command in GlobalSearchCommand.allCases {
            #expect(Self.row(for: command, in: rows) != nil, "\(command.rawValue) produced no palette row")
        }

        // The five that are a destination, and the one that is not. A sweep that found six
        // destinations — or four — would make every "the destination's own" assertion below say
        // something other than what it is written to say.
        let backed = GlobalSearchCommand.allCases.filter { $0.destination != nil }
        #expect(backed.count == 5, "\(backed.count) of the commands open a page")
        #expect(GlobalSearchCommand.newTask.destination == nil)
    }

    /// **The behaviour.** Every command row that opens a page draws that destination's own name and
    /// the sidebar's own glyph for it — asserted on the row `commandResults` builds, not on the
    /// catalog entry, so a definition that reintroduced a stored `icon` would fail here too.
    @Test func everyCommandRowDrawsItsDestinationsOwnNameAndGlyph() {
        let rows = Self.commandRows()
        #expect(rows.count >= 6, "non-vacuity: read \(rows.count) command rows")

        var checked = 0
        for command in GlobalSearchCommand.allCases {
            guard let destination = command.destination else { continue }
            guard let row = Self.row(for: command, in: rows) else { continue }
            checked += 1
            #expect(
                row.title == destination.title,
                "the \(command.rawValue) command row says \"\(row.title)\" and the destination says \"\(destination.title)\" (T-1940)"
            )
            #expect(
                row.icon == destination.systemImage,
                "the \(command.rawValue) command row draws \(row.icon), the sidebar draws \(destination.systemImage) (T-1940)"
            )
        }
        #expect(checked == 5, "checked \(checked) destination-backed command rows")

        // The one row that is not a destination keeps its own copy, and keeps a glyph that is NOT
        // the one its tint is borrowed from — it adds a task, it does not open the task index.
        let capture = Self.row(for: .newTask, in: rows)
        #expect(capture?.title == "New Task")
        #expect(capture?.icon == "plus.circle.fill")
        #expect(capture?.icon != CadenceFeatureDestination.allTasks.systemImage)

        // Discrimination for the loop: the rows are not all one glyph, so "they all match" is not
        // six copies of one assertion.
        #expect(Set(rows.map(\.icon)).count >= 5)
        #expect(Set(rows.map(\.title)).count == rows.count)
    }

    /// **The tint still resolves from the sidebar preference** (T-244), which the derivation above
    /// must not have quietly replaced with a destination default: `tintSource` is now
    /// `destination ?? .allTasks`, and if that had been spelled as a colour instead, a user's
    /// Settings → Sidebar override would stop reaching the palette.
    ///
    /// Fed hexes that appear in no palette in this app, so only a read of the preference can
    /// produce them (T-166).
    @Test func aSidebarOverrideStillReachesEveryCommandRow() {
        let overrides = CadenceFeatureDestination.allCases.enumerated()
            .map { "\($0.element.rawValue):\(String(format: "#%02X0405", $0.offset + 1))" }
            .sorted()
            .joined(separator: ",")

        let rows = GlobalSearchDataSupport.commandResults(query: "", sidebarTabColorsRaw: overrides)
        #expect(rows.count >= 6, "non-vacuity: read \(rows.count) command rows")

        for command in GlobalSearchCommand.allCases {
            guard let row = Self.row(for: command, in: rows) else { continue }
            #expect(
                row.tintHex == CadenceSidebarTint.hex(for: command.tintSource, overridesRaw: overrides),
                "\(command.rawValue) command row is \(row.tintHex), which is not what the sidebar preference says"
            )
            #expect(row.tintHex.hasSuffix("0405"), "\(command.rawValue) ignored the override entirely")
        }

        // The control: the same rows read a different colour with no override, so the assertion
        // above is not passing because every reading returns the same string.
        let defaults = Self.commandRows()
        #expect(Set(defaults.map(\.tintHex)) != Set(rows.map(\.tintHex)))
    }

    /// **The enforcement, which is that there is nowhere left to put a second name.** The catalog
    /// stores the command and the one sentence about the command, and types exactly one string per
    /// row — the subtitle — so the quote count is a relation against the entry count rather than a
    /// fixed six.
    @Test func thePalettesCommandCatalogTypesNothingButTheCommandAndItsVerb() throws {
        let source = try CadenceCommitSurfaceScan.scanned(
            "Cadence/macOS/Views/GlobalSearchSupportViews.swift"
        )
        let definition = try #require(
            CadenceSourceScan.declarationBody("struct GlobalSearchCommandDefinition", in: source),
            "GlobalSearchCommandDefinition no longer reads as a declaration this scan can scope to"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\n    let [a-zA-Z]+:"#, in: definition) == 2,
            "GlobalSearchCommandDefinition stores something besides the command and its subtitle again (T-1940)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"let command: GlobalSearchCommand"#, in: definition) == 1,
            "GlobalSearchCommandDefinition no longer stores the command it is about"
        )
        #expect(
            CadenceSourceScan.matchCount(#"let subtitle: String"#, in: definition) == 1,
            "GlobalSearchCommandDefinition no longer stores the one sentence that is its own"
        )

        let catalog = try #require(
            CadenceSourceScan.declarationBody("extension GlobalSearchCommandDefinition", in: source),
            "the Commands catalog no longer reads as an extension this scan can scope to"
        )
        let entries = CadenceSourceScan.matchCount(#"\.init\(command: \."#, in: catalog)
        #expect(
            entries == GlobalSearchCommandDefinition.all.count,
            "scanned \(entries) catalog entries against \(GlobalSearchCommandDefinition.all.count) rows"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\""#, in: catalog) == entries * 2,
            "the Commands catalog types a string besides the one subtitle a row is allowed (T-1940)"
        )
        #expect(
            CadenceSourceScan.matchCount(#"\b(title|icon|aliases):"#, in: catalog) == 0,
            "the Commands catalog names a title, a glyph or an alias again, and every one of those was a second answer to a question CadenceFeatureDestination already answers (T-1940)"
        )
    }

    /// **Nothing stopped being findable, and the platforms no longer disagree.** Every word the six
    /// rows carried as a hand-typed alias still reaches its row, and the five destination-backed
    /// rows now answer to everything their Pages row answers to — which they did not before: the
    /// Calendar *page* matched "month" and the Calendar *command* did not.
    @Test func everyWordThatReachedACommandStillReachesIt() {
        let typedBefore: [(GlobalSearchCommand, [String])] = [
            (.newTask, ["create", "task", "add"]),
            (.focus, ["pomodoro", "timer", "focus"]),
            (.today, ["today", "dashboard", "daily"]),
            (.allTasks, ["tasks", "all"]),
            (.calendar, ["calendar", "schedule", "events"]),
            (.settings, ["preferences", "settings"])
        ]
        for (command, words) in typedBefore {
            for word in words {
                #expect(
                    Self.row(
                        for: command,
                        in: GlobalSearchDataSupport.commandResults(
                            query: word,
                            sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
                        )
                    ) != nil,
                    "the palette no longer finds the \(command.rawValue) command for \"\(word)\" (T-1940)"
                )
            }
        }

        // Gained, not merely preserved: a word that reaches the Calendar page now reaches the
        // command that opens it. This is the asymmetry T-1782 left behind.
        for word in ["month", "pomodoro", "triage", "diagnostics"] {
            let pages = GlobalSearchDataSupport.pageResults(
                query: word,
                hiddenTabs: [],
                sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
            )
            let commands = GlobalSearchDataSupport.commandResults(
                query: word,
                sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
            )
            for page in pages {
                guard case let .sidebar(item) = page.destination else { continue }
                guard let command = GlobalSearchCommand.allCases.first(where: {
                    $0.destination?.macSidebarItem == item
                }) else { continue }
                #expect(
                    Self.row(for: command, in: commands) != nil,
                    "\"\(word)\" reaches the \(command.rawValue) page row and not the command that opens it (T-1940)"
                )
            }
        }

        // The control: a word no command claims finds none of them, so the assertions above are
        // not passing because everything matches everything.
        #expect(
            GlobalSearchDataSupport.commandResults(
                query: "zzqqx",
                sidebarTabColorsRaw: CadencePreferenceKeys.emptySidebarPreference
            ).isEmpty
        )
    }
}
