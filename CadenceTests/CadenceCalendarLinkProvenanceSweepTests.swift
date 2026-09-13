import Foundation
import Testing
@testable import Cadence

/// **T-899 + T-1043.** The two sides of [[T-624]]'s evidence gate, guarded by one sweep.
///
/// T-624 replaced "no calendar on this device carries this identifier" with "…and this device has
/// itself seen that identifier alive", because `Area.linkedCalendarID` / `Project.linkedCalendarID`
/// hold an `EKCalendar.calendarIdentifier` — documented as local to one device — on a CloudKit-
/// synced `@Model`. The gate has two halves and **neither was an invariant**, only a set of correct
/// call sites:
///
/// - **The reading half (T-899).** `CadenceCalendarLink` and `CadenceCalendarLinkRowState.forLink`
///   take an evidence parameter that **defaults to `.deviceLocal`**. That default is truthful for
///   an identifier read off a live `EKEvent`, and taking it is what kept T-624's second fix to two
///   files — but a new surface that reads a *synced* `linkedCalendarID` and forgets
///   `evidence: .synced(…)` gets the pre-T-624 rule back: the other device's good link announced as
///   broken, with a re-pick beside it that overwrites it.
/// - **The writing half (T-1043).** A link this device made must be recorded in
///   `CadenceCalendarLinkObservations`, or the gate can never report *that* link broken on the
///   device that made it. Every path does record it today, each for a different local reason. A new
///   link-writing surface — or a settings write that skips `saveCalendarLinks(_:)` — silently
///   produces a link that works and whose eventual breakage can never be reported.
///
/// Both halves want the same instrument, so they share one: a scan of `Cadence/` **as text**. Text
/// rather than symbols because `Cadence/iOS/` is inside `#if os(iOS)` and the macOS test target
/// compiles no symbol from it, while iOS is exactly where the next calendar surface is expected —
/// it has no list-editor calendar row today, which is the only reason there is not already a third
/// reading site.
///
/// ## Two corrections to the rule as T-1043 proposed it, both measured here
///
/// 1. **A fourth allowance is needed, for restore paths.** T-1043 proposed three conditions
///    (an unlink, reaches `recordPick`, reaches `saveCalendarLinks()`) on the day before T-274's
///    archive importer landed. `CadenceListEditSnapshot.restore` and
///    `CadenceArchiveImportService.write` both *put back a value the store already held* rather
///    than making a link, and recording nothing is the right answer for both — an imported foreign
///    identifier must read `.unverified`, which is what [[T-1084]] relies on. Without this
///    allowance the rule is red on four lines of landed, deliberate code.
/// 2. **The unlink allowance is not needed, so it is not here.** Measured over `Cadence/`: every
///    `= ""` write of a link is a settings surface that already routes through
///    `saveCalendarLinks(_:)`, so an unlink branch would be a rule with no site behind it. A future
///    bare unlink is a *cheap* false positive — it goes red once and is ledgered with its reason —
///    and that is better than a permanently unexercised branch.
///
/// ## A third, after [[T-1132]]
///
/// The two settings surfaces no longer assign `linkedCalendarID` at all. Both used to write the
/// field and then reach the store through a swallowed save — `try?` on iOS, a caught-and-`print`ed
/// error on macOS — with the observation refresh running either way; both now hand the write to
/// `CadenceCalendarLinkCommit.write(…)`, which puts the previous identifier back when the store
/// refuses. So the writer population lost two files and gained one, and the reach claim for
/// `Cadence/iOS/` moved to the funnel's call sites. The rule got **stricter**, not looser: a
/// settings write that skipped the save is now a bare assignment in a view, which is an offender
/// outright rather than one a missing mention of a helper has to catch.
///
/// Every allowance below is asserted to be load-bearing for that second reason: a category with no
/// site left is a rule nobody is reading any more.
struct CadenceCalendarLinkProvenanceSweepTests {

    // MARK: - The ledgers

    /// The one call site that takes `CadenceCalendarLink`'s `.deviceLocal` default rather than
    /// naming its provenance, and how many calls it makes.
    ///
    /// `CalendarEventEditPopover` takes its identifier off an `EKEvent` this Mac just fetched, so
    /// the default is the true answer there and passing `.synced` would gate a real deletion into
    /// silence — `theTimelineEventEditorDoesNotClaimASyncedIdentifier`, in
    /// `CadenceCalendarLinkRowStateTests`, pins that half. What this ledger adds is that it is the
    /// **only** such site.
    static let defaultedProvenanceSites = [
        "Cadence/macOS/Views/TimelineEventBlockSupportViews.swift": 1
    ]

    /// Declarations that write a `linkedCalendarID` and deliberately record no observation, because
    /// they put back a value the store already held rather than making a link.
    static let restoreDeclarations: Set<String> = [
        "Cadence/Shared/CadenceListEditSnapshot.swift#restore",
        "Cadence/Services/CadenceArchiveImportService.swift#write"
    ]

    /// The call that records a pick straight into the device-local observation record.
    static let recordPickNeedle = "CadenceCalendarLinkObservations.recordPick("

    /// **T-1132.** The one declaration that writes a link and records nothing *because recording is
    /// not its job*.
    ///
    /// `CadenceCalendarLinkCommit.write` is the commit both settings surfaces now hand their writes
    /// to, and the observation record must be written only once that commit has **landed** — it is
    /// an `@AppStorage` write computed off the model objects, so writing it beside the save is
    /// exactly the bug T-1132 fixed: a defaults write outliving a discarded change. The recording
    /// therefore sits in the callers' `saveCalendarLinks(_:)`, past the `catch`, and
    /// `everyCallerOfTheSharedLinkCommitHandsItToTheSettingsSave` below is what keeps it there.
    static let commitFunnelDeclarations: Set<String> = [
        "Cadence/Shared/CadenceCalendarLinkCommit.swift#write"
    ]

    /// The settings surfaces' one write path, and the call that reaches it.
    ///
    /// Before T-1132 this needle was `saveCalendarLinks()` and it vouched for a *settings
    /// declaration that mentioned it*. The surfaces no longer assign `linkedCalendarID` at all —
    /// they hand the write to `CadenceCalendarLinkCommit` — so the rule is stricter now than the
    /// needle ever made it: a settings write that skipped the save would be a bare assignment in a
    /// view, which is an offender outright rather than one a missing mention has to catch.
    static let commitFunnelNeedle = "CadenceCalendarLinkCommit.write("

    /// The funnel the two surfaces wrap that commit in, which is where the observation record is
    /// refreshed past the `catch`.
    static let settingsWriteNeedle = "saveCalendarLinks"

    // MARK: - The reading half (T-899)

    /// Every construction of `CadenceCalendarLink` or `CadenceCalendarLinkRowState.forLink` in the
    /// product tree either names its provenance or is the one ledgered site that relies on the
    /// default.
    @Test func everyReaderOfACalendarLinkNamesItsProvenanceOrIsLedgered() throws {
        let sites = try Self.readerSites()
        #expect(!sites.isEmpty, "the reader sweep found no call sites at all, so it guards nothing")

        var defaulted: [String: Int] = [:]
        for site in sites where !site.arguments.contains("evidence:") {
            defaulted[site.path, default: 0] += 1
        }

        #expect(defaulted == Self.defaultedProvenanceSites, """
            a calendar-link reader takes the `.deviceLocal` default without being ledgered for it. \
            A surface reading a CloudKit-synced `linkedCalendarID` must pass \
            `evidence: .synced(observedCalendarIDs:)`, or it calls another device's good link \
            broken and offers a re-pick that overwrites it (T-624/T-899). \
            Found \(defaulted.sorted { $0.key < $1.key }), \
            ledgered \(Self.defaultedProvenanceSites.sorted { $0.key < $1.key }).
            """)
    }

    /// The ledger is read in the other direction too: a site that has since started naming its
    /// provenance, or that has gone away, must leave the ledger rather than vouch for nothing.
    @Test func everyLedgeredDefaultedReaderIsStillThereAndStillDefaulted() throws {
        let sites = try Self.readerSites()
        for (path, count) in Self.defaultedProvenanceSites {
            let inFile = sites.filter { $0.path == path }
            #expect(inFile.count == count,
                    "\(path) no longer makes \(count) calendar-link call(s); it makes \(inFile.count)")
            #expect(inFile.allSatisfy { !$0.arguments.contains("evidence:") },
                    "\(path) names its provenance now, so its default-relying exemption is stale")
        }
    }

    // MARK: - The writing half (T-1043)

    /// Every write of a stored calendar link either records the pick, reaches the settings write
    /// that records it, or is a ledgered restore of a value the store already held.
    @Test func everyWriterOfAStoredCalendarLinkRecordsItOrIsALedgeredRestore() throws {
        let writes = try Self.writeSites()
        #expect(!writes.isEmpty, "the writer sweep found no assignments at all, so it guards nothing")

        var offenders: [String] = []
        for write in writes {
            guard let declaration = write.declaration else {
                offenders.append("\(write.path): a link write the sweep cannot attribute to a func")
                continue
            }
            let key = "\(write.path)#\(declaration.name)"
            let records = declaration.body.contains(Self.recordPickNeedle)
                || declaration.body.contains(Self.commitFunnelNeedle)
            guard !records,
                  !Self.restoreDeclarations.contains(key),
                  !Self.commitFunnelDeclarations.contains(key) else { continue }
            offenders.append(key)
        }

        #expect(offenders.isEmpty, """
            a surface writes a list's calendar link without recording that this device made it. \
            Since T-624 a break is reported only for an identifier this device has seen alive, so \
            an unrecorded link is one whose eventual breakage can never be reported here (T-1043). \
            Call `\(Self.recordPickNeedle)…)` beside the assignment, route it through \
            `\(Self.commitFunnelNeedle)…)`, or — only if it puts back a value the store already \
            held — add it to `restoreDeclarations` with the reason. Offenders: \(offenders.sorted()).
            """)
    }

    /// Both restore allowances still name a real declaration that really writes a link and really
    /// records nothing. An allowance kept past its site is a hole in the rule wearing an
    /// exemption's clothes.
    @Test func everyRestoreAllowanceStillNamesAWriteThatRecordsNothing() throws {
        let writes = try Self.writeSites()
        for key in Self.restoreDeclarations {
            let matching = writes.filter { write in
                guard let declaration = write.declaration else { return false }
                return "\(write.path)#\(declaration.name)" == key
            }
            #expect(!matching.isEmpty, "\(key) no longer writes a calendar link; drop the allowance")
            #expect(matching.allSatisfy { write in
                guard let body = write.declaration?.body else { return false }
                return !body.contains(Self.recordPickNeedle) && !body.contains(Self.commitFunnelNeedle)
            }, "\(key) records an observation now, so it is an ordinary link write rather than a restore")
        }
    }

    /// **T-1132.** The funnel allowance, read the same way: it still writes a link, it still
    /// records nothing itself, and every caller still hands it to the settings save that records
    /// past the `catch`. Without the caller half the allowance would excuse any new surface that
    /// simply called the commit and never refreshed the observation record — which is the T-1043
    /// hole in a newer shape.
    @Test func everyCallerOfTheSharedLinkCommitHandsItToTheSettingsSave() throws {
        let writes = try Self.writeSites()
        for key in Self.commitFunnelDeclarations {
            let matching = writes.filter { write in
                guard let declaration = write.declaration else { return false }
                return "\(write.path)#\(declaration.name)" == key
            }
            #expect(!matching.isEmpty, "\(key) no longer writes a calendar link; drop the allowance")
            #expect(matching.allSatisfy { $0.declaration?.body.contains(Self.recordPickNeedle) == false },
                    "\(key) records the pick itself now, before the commit it is supposed to follow")
        }

        let callers = try Self.commitFunnelCallers()
        #expect(callers.count >= 2, "the shared link commit is called from \(callers.count) place(s)")
        for caller in callers {
            let declaration = try #require(
                caller.declaration,
                "\(caller.path): a call to the shared link commit the sweep cannot attribute to a func"
            )
            #expect(
                declaration.body.contains(Self.settingsWriteNeedle),
                "\(caller.path)#\(declaration.name) commits a link without routing it through the save that records it"
            )
        }
    }

    /// All three categories still carry sites. A rule whose branch nothing exercises stops being
    /// read, and this is the branch T-1043's own proposal got wrong in both directions.
    @Test func allThreeWriterCategoriesAreStillLoadBearing() throws {
        let writes = try Self.writeSites()
        var recordsThePick = 0
        var commitsThroughTheFunnel = 0
        var restores = 0
        for write in writes {
            guard let declaration = write.declaration else { continue }
            let key = "\(write.path)#\(declaration.name)"
            if Self.restoreDeclarations.contains(key) {
                restores += 1
            } else if Self.commitFunnelDeclarations.contains(key) {
                commitsThroughTheFunnel += 1
            } else if declaration.body.contains(Self.recordPickNeedle) {
                recordsThePick += 1
            }
        }
        #expect(recordsThePick > 0, "no write records a pick directly any more")
        #expect(commitsThroughTheFunnel > 0, "no write goes through the shared link commit any more")
        #expect(restores > 0, "no restore path writes a link any more; drop the fourth allowance")
    }

    // MARK: - The sweep is reading what it claims to read

    /// The whole point of a text scan is `Cadence/iOS/`, which the macOS test target compiles no
    /// symbol from. Without this, both sweeps above could be passing on a tree they never opened.
    @Test func theSweepReadsTheIOSTreeAsTextAndNotOnlyTheMacOne() throws {
        // **T-1132 moved where iOS shows up.** It used to appear in the writer sweep, because
        // `iOSCalendarSettingsSection` assigned `linkedCalendarID` at six sites. It assigns none
        // now — every write goes to `CadenceCalendarLinkCommit` — so the reach claim is made
        // against the funnel's call sites, which is where the iOS tree appears today. The claim
        // itself is unchanged: this sweep must be opening `Cadence/iOS/` as text, or both rules
        // above are passing on a tree they never read.
        let callers = Set(try Self.commitFunnelCallers().map(\.path))
        #expect(callers.contains("Cadence/iOS/iOSCalendarSettingsSection.swift"),
                "the sweep never reached the iOS calendar settings surface, which commits four link writes")
        #expect(callers.contains("Cadence/macOS/Views/SettingsListManagementSections.swift"),
                "the sweep never reached the macOS calendar settings surface")

        let writes = try Self.writeSites()
        let paths = Set(writes.map(\.path))
        #expect(paths.contains("Cadence/macOS/Sheets/EditListSheet.swift"),
                "the sweep never reached the macOS list editor, which writes two")
        #expect(paths.count >= 4,
                "the writer population has shrunk below the four files that still assign a link directly")

        let readers = try Self.readerSites()
        #expect(Set(readers.map(\.path)).contains("Cadence/macOS/Sheets/ListEditorSupportViews.swift"),
                "the sweep never reached the list editor's calendar row")
    }

    // MARK: - The instrument is not vacuous

    /// The reader detector, against literal fixtures rather than repo files: a fixture read out of
    /// the tree can be retuned by the same edit that breaks the rule.
    @Test func theCallSiteReaderSeparatesADeclaredProvenanceFromADefaultedOne() {
        let declared = """
            private var link: CadenceCalendarLink {
                CadenceCalendarLink(
                    linkedCalendarID: selectedID,
                    evidence: .synced(observedCalendarIDs: ids)
                )
            }
            """
        let defaulted = """
            private var link: CadenceCalendarLink {
                CadenceCalendarLink(
                    linkedCalendarID: selectedID,
                    exclusion: .readOnly
                )
            }
            """
        #expect(Self.callSites(in: declared).count == 1)
        #expect(Self.callSites(in: declared).first?.contains("evidence:") == true)
        #expect(Self.callSites(in: defaulted).count == 1)
        #expect(Self.callSites(in: defaulted).first?.contains("evidence:") == false)
        #expect(Self.callSites(in: "CadenceCalendarLinkObservations.recordPick(id, replacing: old)").isEmpty,
                "the reader needle matched a neighbouring type whose name starts the same way")
    }

    /// The writer detector: it finds a link write, attributes it to the enclosing `func` rather
    /// than to the nearest brace, and does not mistake the value type's own `self.` initialisation
    /// for a write to a model.
    @Test func theWriteReaderAttributesAnAssignmentToItsEnclosingFunc() {
        let source = """
            struct Thing {
                init(linkedCalendarID: String) {
                    self.linkedCalendarID = linkedCalendarID
                }

                private func relink(_ link: Link, to calendarID: String) {
                    switch link.kind {
                    case .area:
                        areas.first { $0.id == link.id }?.linkedCalendarID = calendarID
                    default:
                        break
                    }
                    CadenceCalendarLinkObservations.recordPick(calendarID, replacing: stored)
                }
            }
            """
        let writes = Self.writeSites(in: source, path: "Fixture.swift")
        #expect(writes.count == 1, "the value type's own self-assignment was counted as a link write")
        #expect(writes.first?.declaration?.name == "relink")
        #expect(writes.first?.declaration?.body.contains(Self.recordPickNeedle) == true,
                "attribution stopped at the switch's braces rather than at the func's")
    }

    /// And it sees the shape the ticket is about: the same write with the settings save removed.
    ///
    /// This fixture is also, verbatim, the shape [[T-1132]] removed from `Cadence/iOS/` — a link
    /// write over a swallowed save — so it stays here as the negative fixture even though no file
    /// in the tree spells it any more.
    @Test func theWriteReaderSeesASettingsWriteThatSkipsTheSave() {
        let source = """
            struct Thing {
                private func relink(_ link: Link, to calendarID: String) {
                    areas.first { $0.id == link.id }?.linkedCalendarID = calendarID
                    try? modelContext.save()
                }
            }
            """
        let writes = Self.writeSites(in: source, path: "Fixture.swift")
        #expect(writes.count == 1)
        #expect(writes.first?.declaration?.body.contains(Self.commitFunnelNeedle) == false)
        #expect(writes.first?.declaration?.body.contains(Self.recordPickNeedle) == false)
    }

    /// The funnel-caller detector, against literal fixtures: a call to the shared commit is
    /// attributed to its enclosing `func`, and the needle does not match the declaration itself.
    @Test func theFunnelCallerReaderSeparatesACallFromTheDeclarationItCalls() {
        let caller = """
            struct Thing {
                private func toggle(_ calendarID: String, for area: Area) {
                    saveCalendarLinks { try CadenceCalendarLinkCommit.write(calendarID, to: area, in: modelContext) }
                }
            }
            """
        let declaration = """
            enum CadenceCalendarLinkCommit {
                static func write(_ calendarID: String, to area: Area, in modelContext: ModelContext) throws {
                    area.linkedCalendarID = calendarID
                }
            }
            """
        let callers = Self.commitFunnelCallers(in: caller, path: "Fixture.swift")
        #expect(callers.count == 1)
        #expect(callers.first?.declaration?.name == "toggle")
        #expect(callers.first?.declaration?.body.contains(Self.settingsWriteNeedle) == true)
        #expect(Self.commitFunnelCallers(in: declaration, path: "Fixture.swift").isEmpty,
                "the declaration of the commit was counted as a call to it")
    }

    // MARK: - Scanning

    struct ReaderSite {
        let path: String
        /// The call's own argument list, parenthesis-matched, so an `evidence:` in a neighbouring
        /// call cannot vouch for this one.
        let arguments: String
    }

    struct Declaration {
        let name: String
        let body: String
    }

    struct WriteSite {
        let path: String
        let declaration: Declaration?
    }

    /// Raw source for every product file, before comments and literals are blanked.
    ///
    /// The blanking is linear but not free, and 99% of these files mention neither needle, so it is
    /// deferred behind a raw `contains` prefilter. That cannot cause a miss: raw text is a superset
    /// of code-only text, so a file the prefilter drops has the needle in neither.
    private static func productSources() throws -> [(path: String, raw: String)] {
        var sources: [(path: String, raw: String)] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence").sorted() {
            let raw = try CadenceSourceScan.sourceFile(path)
            sources.append((path: path, raw: raw))
        }
        return sources
    }

    private static func readerSites() throws -> [ReaderSite] {
        try productSources()
            .filter { $0.raw.contains("CadenceCalendarLink") }
            .flatMap { source in
                callSites(in: CadenceSourceScan.codeOnly(source.raw))
                    .map { ReaderSite(path: source.path, arguments: $0) }
            }
    }

    private static func writeSites() throws -> [WriteSite] {
        try productSources()
            .filter { $0.raw.contains(".linkedCalendarID") }
            .flatMap { writeSites(in: CadenceSourceScan.codeOnly($0.raw), path: $0.path) }
    }

    /// **T-1132.** Every product-tree call of `CadenceCalendarLinkCommit.write(`, attributed to the
    /// `func` making it.
    private static func commitFunnelCallers() throws -> [WriteSite] {
        try productSources()
            .filter { $0.raw.contains(commitFunnelNeedle) }
            .flatMap { commitFunnelCallers(in: CadenceSourceScan.codeOnly($0.raw), path: $0.path) }
    }

    /// Qualified by the enum's own name, which is what separates a call from the declaration: the
    /// commit's own body spells `func write(`, never `CadenceCalendarLinkCommit.write(`.
    static func commitFunnelCallers(in source: String, path: String) -> [WriteSite] {
        let characters = Array(source)
        var results: [WriteSite] = []
        var spans: [FunctionSpan]?

        for start in occurrences(of: commitFunnelNeedle, in: characters) {
            let declarations = spans ?? functionSpans(in: characters)
            spans = declarations
            let enclosing = declarations
                .filter { $0.body.contains(start) }
                .min { $0.body.count < $1.body.count }
            results.append(
                WriteSite(
                    path: path,
                    declaration: enclosing.map {
                        Declaration(name: $0.name, body: String(characters[$0.body]))
                    }
                )
            )
        }
        return results
    }

    /// The argument list of every `CadenceCalendarLink(` / `CadenceCalendarLinkRowState.forLink(`
    /// call in `source`.
    static func callSites(in source: String) -> [String] {
        let characters = Array(source)
        var results: [String] = []
        for needle in ["CadenceCalendarLink(", "CadenceCalendarLinkRowState.forLink("] {
            for start in occurrences(of: needle, in: characters) {
                let open = start + needle.count - 1
                guard let close = matchingClose(of: "(", ")", from: open, in: characters) else { continue }
                results.append(String(characters[(open + 1)..<close]))
            }
        }
        return results
    }

    /// Every `x.linkedCalendarID = …` in `source` that is not the value type's own `self.` one,
    /// paired with the `func` declaration enclosing it.
    static func writeSites(in source: String, path: String) -> [WriteSite] {
        let characters = Array(source)
        let needle = ".linkedCalendarID"
        var results: [WriteSite] = []
        var spans: [FunctionSpan]?

        for start in occurrences(of: needle, in: characters) {
            var cursor = start + needle.count
            while cursor < characters.count, characters[cursor] == " " { cursor += 1 }
            guard cursor < characters.count, characters[cursor] == "=" else { continue }
            guard cursor + 1 >= characters.count || characters[cursor + 1] != "=" else { continue }
            guard start < 4 || String(characters[(start - 4)..<start]) != "self" else { continue }

            let declarations = spans ?? functionSpans(in: characters)
            spans = declarations
            let enclosing = declarations
                .filter { $0.body.contains(start) }
                .min { $0.body.count < $1.body.count }
            results.append(
                WriteSite(
                    path: path,
                    declaration: enclosing.map {
                        Declaration(name: $0.name, body: String(characters[$0.body]))
                    }
                )
            )
        }
        return results
    }

    struct FunctionSpan {
        let name: String
        let body: Range<Int>
    }

    /// Every `func` declaration in `source`, with the character range of its braced body.
    ///
    /// Attribution has to be by declaration rather than by nearest enclosing brace: every settings
    /// write in the app sits inside a `switch` whose braces do not contain the
    /// `saveCalendarLinks()` that makes it correct.
    static func functionSpans(in characters: [Character]) -> [FunctionSpan] {
        var spans: [FunctionSpan] = []
        for start in occurrences(of: "func ", in: characters) {
            if start > 0 {
                let previous = characters[start - 1]
                if previous.isLetter || previous.isNumber || previous == "_" { continue }
            }
            var cursor = start + 5
            var name = ""
            while cursor < characters.count,
                  characters[cursor].isLetter || characters[cursor].isNumber || characters[cursor] == "_" {
                name.append(characters[cursor])
                cursor += 1
            }
            guard !name.isEmpty else { continue }

            // Forward to the brace that opens the body: the first `{` outside the parameter list
            // and any generic or return-type brackets. Bounded so a body-less protocol requirement
            // cannot adopt the next declaration's braces.
            var depth = 0
            var open: Int?
            let limit = min(characters.count, cursor + 2_000)
            while cursor < limit {
                switch characters[cursor] {
                case "(", "[": depth += 1
                case ")", "]": depth -= 1
                case "{" where depth <= 0: open = cursor
                default: break
                }
                if open != nil { break }
                cursor += 1
            }
            guard let opened = open,
                  let close = matchingClose(of: "{", "}", from: opened, in: characters) else { continue }
            spans.append(FunctionSpan(name: name, body: opened..<(close + 1)))
        }
        return spans
    }

    private static func occurrences(of needle: String, in characters: [Character]) -> [Int] {
        let pattern = Array(needle)
        guard !pattern.isEmpty, characters.count >= pattern.count else { return [] }
        var results: [Int] = []
        for index in 0...(characters.count - pattern.count) {
            var offset = 0
            while offset < pattern.count, characters[index + offset] == pattern[offset] { offset += 1 }
            if offset == pattern.count { results.append(index) }
        }
        return results
    }

    private static func matchingClose(
        of open: Character,
        _ close: Character,
        from index: Int,
        in characters: [Character]
    ) -> Int? {
        var depth = 0
        var cursor = index
        while cursor < characters.count {
            if characters[cursor] == open { depth += 1 }
            if characters[cursor] == close {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor += 1
        }
        return nil
    }
}
