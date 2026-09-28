import Foundation
import Testing
@testable import Cadence

/// **T-1404, the reader half: the reason it is not built, measured instead of argued.**
///
/// [[T-1366]] left two opt-in, durable instruments — `CadenceWidgetGenerationLedger`'s three slots
/// per widget kind in the app group, and `CadenceStartupCostLedger.lastReport` in the app's own
/// domain. [[T-1404]] closed the privacy half (the reset takes both) and refused the display half
/// on an argument: *a diagnostics row added today would say `instrumentDisabled` to every user
/// forever, because nothing a person can reach switches the instrument on.*
///
/// An argument in a ledger entry rots. This file turns it into two numbers a run re-derives:
///
/// 1. **The reachability census.** Over the 618 `.swift` files the three shipping targets compile,
///    the four reader entry points and `setEnabled` have **no call site at all** — every one of
///    the 40 references to them in this repository is in `CadenceTests/`. The same sweep, same
///    instrument, same walk, finds the five shipping *writer* sites in three files, which is the
///    control: a column of zeroes means something only because the column beside it is not zero.
///    A sweep that walked an empty list, or missed its witness file, throws rather than passing.
/// 2. **What the row would print.** Driven rather than reasoned about: on a defaults domain in the
///    state a device is in — nobody has ever set either key — all **thirteen** readings (four
///    widget kinds × three slots, plus the launch report) answer `.instrumentDisabled`. Flip the
///    two keys by hand, which only a test or a debugger can do, and the same thirteen answer
///    `.nothingRecorded`. Those are different sentences and the display T-1404 priced exists to
///    tell them apart; today only one of them is reachable.
///
/// **This suite is not a veto on building the reader.** It is the opposite: when someone adds the
/// switch T-1404 says has to come first, `noShippingSurfaceCanSwitchEitherInstrumentOn` goes red
/// and names the file that added it — which is precisely the moment the reader is owed, and the
/// moment [[T-1494]] is answered. Deleting these two tests is part of building it, and the failure
/// messages say so rather than leaving the next agent to guess whether they found a guard or a bug.
struct CadenceInstrumentReaderReachTests {

    // MARK: - The walk

    /// The three targets that ship. `CadenceTests` is swept separately and only as the positive
    /// witness: a needle that matches nothing anywhere is a typo, not a finding.
    static let shippingDirectories = ["Cadence", "CadenceWidgets", "CadenceMCPServer"]

    /// The file that declares the widget ledger and holds two of the five shipping writer sites.
    /// Passed as `including:` so a walk that silently stopped short refuses instead of reporting a
    /// clean sweep.
    static let widgetLedgerPath = "Cadence/Services/CadenceTodayWidgetSupport.swift"

    static let widgetTestPath = "CadenceTests/CadenceWidgetCostInstrumentTests.swift"
    static let startupTestPath = "CadenceTests/CadenceStartupCostInstrumentTests.swift"

    // MARK: - The needles

    /// Every way to *read* what either instrument recorded. These are the entry points a
    /// diagnostics row would call, and the whole of T-1404's second half is that nothing does.
    static let readerNeedles = [
        "CadenceWidgetGenerationLedger\\.lastGeneration\\(",
        "CadenceWidgetGenerationLedger\\.lastSuccess\\(",
        "CadenceWidgetGenerationLedger\\.lastRefusal\\(",
        "CadenceStartupCostLedger\\.lastReport\\(",
    ]

    /// The only way to turn either instrument on. `enabledDefaultsKey` is `internal`, so a caller
    /// *could* write the key directly — that spelling is a needle too, for the same reason
    /// [[T-745]]'s sweep carries six spellings of one store rather than the one it first found.
    static let switchNeedles = [
        "CadenceWidgetGenerationLedger\\.setEnabled\\(",
        "CadenceStartupCostLedger\\.setEnabled\\(",
        "Cadence(WidgetGenerationLedger|StartupCostLedger)\\.enabledDefaultsKey",
    ]

    /// **The control column.** These five sites are the instruments doing their job, and they are
    /// in shipping code: the probe asks whether it is on, the probe writes a record, the launch
    /// opens a recorder, the recorder commits a report, and T-1404's own closed half clears both
    /// ledgers in the privacy reset. If this column ever reads empty, the sweep above is not
    /// reaching shipping source and its zero proves nothing.
    static let writerNeedles = [
        "CadenceWidgetGenerationLedger\\.isEnabled\\(",
        "CadenceWidgetGenerationLedger\\.record\\(",
        "CadenceWidgetGenerationLedger\\.clearStoredState\\(",
        "CadenceStartupCostLedger\\.begin\\(",
        "CadenceStartupCostLedger\\.store\\(",
        "CadenceStartupCostLedger\\.clearStoredState\\(",
    ]

    /// The three shipping files the control column must land in, with what each one is for. Read as
    /// an equality rather than a subset: a fourth file appearing here is a writer nobody ledgered,
    /// and one of these three dropping out is an instrument that stopped being driven.
    static let shippingWriterSites: [String: String] = [
        "Cadence/Services/CadenceTodayWidgetSupport.swift":
            "the probe asks whether it is on, and writes the record when it is",
        "Cadence/Services/PersistenceController.swift":
            "the launch opens a recorder and the recorder commits the report",
        "Cadence/Services/CadencePrivacyDataResetService.swift":
            "T-1404's closed half: the reset clears both ledgers",
    ]

    // MARK: - (1) The reachability census

    /// **Nothing in the app, the widget extension or the MCP server reads either ledger.**
    ///
    /// The four reader entry points exist, are `internal`, and have no caller outside the test
    /// target. That is not a style observation: it is the measured form of T-1404's sentence *"the
    /// ledgers are read by `CadenceWidgetCostInstrumentTests` and `CadenceStartupCostInstrumentTests`
    /// and by a debugger"*, and it is what makes the refusal to build a display checkable rather
    /// than remembered.
    @Test func noShippingSurfaceReadsEitherInstrumentLedger() throws {
        let paths = try shippingFiles()
        let read = Self.codeReader()
        let hits = try Self.readerInstrument().sweep(
            paths,
            atLeast: 500,
            including: Self.widgetLedgerPath,
            read: read
        )

        #expect(hits.isEmpty, """
        A shipping file now reads one of T-1366's instrument ledgers: \(hits.joined(separator: ", ")).
        Swept \(paths.count) files in \(Self.shippingDirectories.joined(separator: ", ")); the \
        control column (`theSameSweepFindsTheShippingWriters`) lands in \
        \(Self.shippingWriterSites.count) of them, so this zero is a fact about the tree.
        If that file is the diagnostics surface T-1404 priced, the reader half is built and this \
        test and its sibling are what you delete — close T-1404's successor T-1494 in the same \
        commit rather than deleting a guard and leaving the ticket open.
        """)
    }

    /// **And nothing can switch one on, which is the load-bearing half.**
    ///
    /// A reader with no switch in front of it is a surface that cannot be wrong and cannot be
    /// useful. `setEnabled` is `internal` and reachable from any target that compiles the app, and
    /// the count of callers outside `CadenceTests/` is zero — so the *only* ways to opt in are a
    /// debugger and `defaults write`, neither of which is a product surface.
    @Test func noShippingSurfaceCanSwitchEitherInstrumentOn() throws {
        let paths = try shippingFiles()
        let hits = try Self.switchInstrument().sweep(
            paths,
            atLeast: 500,
            including: Self.widgetLedgerPath,
            read: Self.codeReader()
        )

        #expect(hits.isEmpty, """
        A shipping file now sets one of T-1366's instrument opt-ins: \(hits.joined(separator: ", ")).
        This is the condition T-1404 refused the reader on — "a diagnostics row added today would \
        say instrumentDisabled to every user forever" — and it no longer holds, so the reader half \
        is now buildable and is owed. See T-1494.
        """)
    }

    /// **The control, and it is expected to find things.**
    ///
    /// The same walk, the same reader, the same `codeOnly` stripping — only the needle differs. A
    /// column of zeroes above is indistinguishable from a sweep pointed at the wrong tree, a
    /// pattern that stopped compiling (`matchCount` answers `-1`, which no `> 0` passes by
    /// accident), or a `swiftFiles` that walked nothing. This is the column that separates them,
    /// and it is pinned to an exact set rather than to "not empty".
    @Test func theSameSweepFindsTheShippingWriters() throws {
        let paths = try shippingFiles()
        let read = Self.codeReader()
        let hits = try Self.writerInstrument().sweep(
            paths,
            atLeast: 500,
            including: Self.widgetLedgerPath,
            read: read
        )

        #expect(hits == Self.shippingWriterSites.keys.sorted(), """
        The shipping writer sites moved. Expected \(Self.shippingWriterSites.keys.sorted()), \
        found \(hits) over \(paths.count) swept files.
        Every zero in this suite is measured with this instrument, so until this row is right the \
        two above are not evidence of anything.
        """)

        // Occurrences, not files: `CadencePrivacyDataResetService` holds two of the six and a
        // per-file reading would let one of them disappear behind the other.
        let occurrences = try Self.count(Self.writerNeedles, over: paths, read: read)
        #expect(occurrences == 6, """
        \(occurrences) shipping writer call sites, expected 6 (isEnabled, record, begin, store, \
        and the reset's two clearStoredState lines) over \(paths.count) files.
        """)
    }

    /// **The positive witness for the reader and switch needles: they do match, in `CadenceTests/`.**
    ///
    /// Without this, `noShippingSurfaceReadsEitherInstrumentLedger` passes just as green against a
    /// mistyped needle that matches nothing anywhere in the repository — which is the failure mode
    /// this repository has already been bitten by twice, and the reason
    /// `CadenceScanInstrument.sweep` makes `atLeast:` and `including:` non-defaulted.
    @Test func theSameNeedlesDoMatchInTheTestTargetThatIsTheOnlyReaderThereIs() throws {
        let paths = try CadenceSourceScan.swiftFiles(under: "CadenceTests")
        let read = Self.codeReader()
        let readerHits = try Self.readerInstrument().sweep(
            paths,
            atLeast: 300,
            including: Self.widgetTestPath,
            read: read
        )
        let switchHits = try Self.switchInstrument().sweep(
            paths,
            atLeast: 300,
            including: Self.startupTestPath,
            read: read
        )

        #expect(readerHits.contains(Self.widgetTestPath) && readerHits.contains(Self.startupTestPath), """
        The reader needles no longer match the two suites that are the only readers in the \
        repository (found: \(readerHits)). A needle that matches nothing matches shipping code \
        just as silently.
        """)
        #expect(switchHits.contains(Self.widgetTestPath) && switchHits.contains(Self.startupTestPath), """
        The switch needles no longer match the suites that call `setEnabled` (found: \(switchHits)).
        """)

        // The denominator, said out loud rather than implied by a green run: 40 references, every
        // one of them here. `theSameSweepFindsTheShippingWriters` is the other 6.
        let readerAndSwitch = try Self.count(
            Self.readerNeedles + Self.switchNeedles,
            over: paths,
            read: read
        )
        #expect(readerAndSwitch >= 30, """
        \(readerAndSwitch) reader/switch call sites in CadenceTests over \(paths.count) files, \
        which is too few to be the population T-1404 measured — the walk or the needles are wrong.
        """)
    }

    // MARK: - (2) What the row would print

    /// **All thirteen readings a diagnostics surface would render say the same thing today.**
    ///
    /// Four widget kinds × three slots, plus the launch report. On a defaults domain nobody has
    /// touched — the state of every device, because the census above shows nothing sets either
    /// key — every one answers `.instrumentDisabled`.
    ///
    /// The second half is what makes the first half an argument about a *display* rather than about
    /// an empty store: flip the two keys and the same thirteen move to `.nothingRecorded`. "The
    /// instrument is off" and "it is on and this widget has not generated" are different advice,
    /// which is exactly the distinction T-1404 priced a presentation type for — and only the first
    /// of the two is reachable without a debugger.
    @Test func aDiagnosticsRowAddedTodayWouldBeSilentInEveryOneOfTheThirteenSlots() throws {
        try withTemporaryDefaults("CadenceTests.instrumentReaderReach") { defaults in
            let untouched = Self.silences(defaults: defaults)
            #expect(untouched.count == 13, "the sweep reads \(untouched.count) slots, not the thirteen a display would render")
            #expect(Set(untouched) == ["instrumentDisabled"], """
            Not every slot reads `instrumentDisabled` on an untouched domain: \(untouched).
            T-1404's refusal is that all thirteen do, which is the sentence a diagnostics row \
            would print to every user for as long as nothing can set the two keys.
            """)

            // Only a test or a debugger can run these two lines against a real domain. That is the
            // ticket's whole point, and it is why this is a positive witness rather than a second
            // assertion about the same state.
            CadenceWidgetGenerationLedger.setEnabled(true, userDefaults: defaults)
            CadenceStartupCostLedger.setEnabled(true, defaults: defaults)

            let optedIn = Self.silences(defaults: defaults)
            #expect(Set(optedIn) == ["nothingRecorded"], """
            With both instruments on and nothing recorded the slots read \(optedIn), not \
            `nothingRecorded` throughout — so the reading above was not the switch, and this \
            suite is measuring something other than what T-1404 refused on.
            """)
        }
    }

    // MARK: - Instruments

    /// Each instrument carries the *nearest* negative it must not fire on — the declaration of the
    /// very member it hunts callers of, which is the line that would make a naive `contains` read
    /// every ledger as its own caller.
    static func readerInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "instrumentLedgerReader",
            fires: "let reading = CadenceWidgetGenerationLedger.lastSuccess(kind: kind)",
            andNotOn: "static func lastSuccess(kind: String) -> CadenceWidgetLedgerReading {",
            by: { fires(Self.readerNeedles, in: $0) }
        )
    }

    static func switchInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "instrumentLedgerSwitch",
            fires: "CadenceStartupCostLedger.setEnabled(true, defaults: defaults)",
            andNotOn: "static func setEnabled(_ enabled: Bool, defaults: UserDefaults) {",
            by: { fires(Self.switchNeedles, in: $0) }
        )
    }

    static func writerInstrument() throws -> CadenceScanInstrument {
        try CadenceScanInstrument(
            "instrumentLedgerWriter",
            fires: "CadenceWidgetGenerationLedger.record(record, userDefaults: userDefaults)",
            andNotOn: "static func record(_ record: CadenceWidgetGenerationRecord) {",
            by: { fires(Self.writerNeedles, in: $0) }
        )
    }

    // MARK: - Reading

    func shippingFiles() throws -> [String] {
        try Self.shippingDirectories.flatMap { try CadenceSourceScan.swiftFiles(under: $0) }
    }

    /// **String literals blanked as well as comments, and both halves are load-bearing.**
    ///
    /// Comments, because every ledger entry point is named in the doc comment above its own
    /// declaration. Literals, because every needle below is spelled as a literal *in this file*,
    /// and this file is inside the `CadenceTests/` walk the positive witness
    /// `theSameNeedlesDoMatchInTheTestTargetThatIsTheOnlyReaderThereIs` uses — without `codeOnly`
    /// that witness would be matching itself, which is the trap `CadenceTestTargetHygieneTests`
    /// names for the target it is itself a member of.
    ///
    /// Cached and applied at the *read*, not inside the detector: `codeOnly` walks a file
    /// character by character, and four tests × ~620 files × three instruments is the shape that
    /// turned a sweep in this repository into a sixteen-minute test once already ([[T-1269]]).
    static func codeReader() -> (String) throws -> String {
        var cache: [String: String] = [:]
        return { path in
            if let hit = cache[path] { return hit }
            let code = CadenceSourceScan.codeOnly(try CadenceSourceScan.sourceFile(path))
            cache[path] = code
            return code
        }
    }

    /// The detectors read text that has already been through `codeReader`, so they do no stripping
    /// of their own — which is also why the fixtures handed to `CadenceScanInstrument.init` are
    /// bare declarations with no comment and no literal in them.
    private static func fires(_ needles: [String], in code: String) -> Bool {
        needles.contains { CadenceSourceScan.matchCount($0, in: code) > 0 }
    }

    private static func count(
        _ needles: [String],
        over paths: [String],
        read: (String) throws -> String
    ) throws -> Int {
        var total = 0
        for path in paths {
            let code = try read(path)
            for needle in needles {
                // `-1` is "the pattern did not compile", which must never be summed into a count
                // an assertion then reads as small-but-real.
                let found = CadenceSourceScan.matchCount(needle, in: code)
                if found > 0 { total += found }
            }
        }
        return total
    }

    /// The thirteen slots a display would sweep, in the order a reader would print them.
    private static func silences(defaults: UserDefaults) -> [String] {
        var readings: [String] = []
        for kind in CadenceWidgetGenerationLedger.instrumentedKinds {
            readings.append(CadenceWidgetGenerationLedger.lastGeneration(kind: kind, userDefaults: defaults).silence?.rawValue ?? "recorded")
            readings.append(CadenceWidgetGenerationLedger.lastSuccess(kind: kind, userDefaults: defaults).silence?.rawValue ?? "recorded")
            readings.append(CadenceWidgetGenerationLedger.lastRefusal(kind: kind, userDefaults: defaults).silence?.rawValue ?? "recorded")
        }
        readings.append(CadenceStartupCostLedger.lastReport(defaults: defaults).silence?.rawValue ?? "recorded")
        return readings
    }
}
