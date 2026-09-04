import EventKit
import Foundation
import Testing
@testable import Cadence

/// **T-547 — one literal, three concepts, hoisted as three.**
///
/// `"Apple Calendar"` was typed at eight sites in seven files and meant different things at
/// different ones: a **section label** over the controls that talk to EventKit, and a **fallback**
/// for two unrelated nil cases — an event whose calendar has no name, and a calendar whose account
/// has no name. [[T-524]] recorded that hoisting it would "make 7 offenders at once" and left it
/// alone, which was right about the sweep and incomplete about the reason: the defect is that one
/// name would have been made to serve two meanings, so a reword of the phone's inspector heading
/// would silently reword what a Mac prints when EventKit hands back an unnamed account.
///
/// So this suite asserts the **split**, not the de-duplication. Three constants, each read by the
/// sites that mean *that* concept, named one by one — a total would stay green while a site drifted
/// from one concept to the other, which is exactly the failure the split exists to prevent.
///
/// The scans read `strippingComments`, never `codeOnly`: `codeOnly` blanks string literals as well
/// as comments, so a quoted needle can never match there. `theNamingScanReadsLiteralsRatherThanBlankingThem`
/// pins that the two readers still differ.
@MainActor
struct CadenceAppleCalendarNamingTests {

    private static func strippedSource(at path: String) throws -> String {
        let raw = try CadenceSourceScan.sourceFile(path)
        #expect(raw.count > 500, "\(path) read as \(raw.count) characters; that is not the file")
        return CadenceSourceScan.strippingComments(raw)
    }

    /// Every site, named, with the concept it means and how many times it says it.
    ///
    /// Exact counts per file rather than a total: an aggregate of eight cannot tell you the eight
    /// are where you left them, and the population here is one a later pass is expected to shrink.
    private static let sites: [(path: String, expression: String, count: Int)] = [
        // The label: the eyebrow over the controls that read or write the system calendar.
        ("Cadence/iOS/iOSCalendarQuickCreateSheet.swift", "integrationSectionTitle", 1),
        ("Cadence/iOS/iOSCalendarEventEditSheet.swift", "integrationSectionTitle", 1),
        ("Cadence/iOS/iOSCalendarInspectorView.swift", "integrationSectionTitle", 1),
        ("Cadence/macOS/Sheets/ListEditorSupportViews.swift", "integrationSectionTitle", 1),
        // The fallback for `event.calendar?.title`: which calendar, when the event names none.
        ("Cadence/iOS/iOSBoardCards.swift", "unnamedCalendarTitle", 1),
        ("Cadence/iOS/iOSSearchView.swift", "unnamedCalendarTitle", 1),
        // The fallback for `calendar.source?.title`: which account, when the calendar names none.
        ("Cadence/iOS/iOSCalendarSettingsSection.swift", "unnamedAccountTitle", 1),
        ("Cadence/macOS/Views/SettingsListManagementSections.swift", "unnamedAccountTitle", 1),
        // T-692: the same fallback, converged from a hardcoded "Other" in the calendar-link
        // picker's own account grouping.
        ("Cadence/macOS/CadenceCalendarPicker.swift", "unnamedAccountTitle", 1),
    ]

    // MARK: - The split

    /// The three concepts are three declarations, and they are allowed to agree.
    ///
    /// Asserted against compiled code rather than as text, because this is the one claim in the
    /// suite that can be: `Cadence/Shared/` is in this target. The equality is deliberate and is
    /// stated so a reader does not "tidy" three constants into one — the point is that each can be
    /// reworded alone.
    @Test func theAppleCalendarNameIsThreeConstantsRatherThanOne() {
        #expect(CadenceAppleCalendarNaming.integrationSectionTitle == "Apple Calendar")
        #expect(CadenceAppleCalendarNaming.unnamedCalendarTitle == "Apple Calendar")
        #expect(CadenceAppleCalendarNaming.unnamedAccountTitle == "Apple Calendar")

        // And not the plural eyebrow one screen over, which is a fourth concept that already had
        // its own constant (T-599(e)). If these ever collapse, Settings → Calendar's list heading
        // and the sheets' section heading have become the same string by accident.
        #expect(
            CadenceCalendarSettingsCopy.appleCalendarsSectionTitle
                != CadenceAppleCalendarNaming.integrationSectionTitle
        )
    }

    /// Each site reads the constant for the concept it means, exactly as often as it says it.
    @Test func everySiteReadsTheConstantForTheConceptItMeans() throws {
        for site in Self.sites {
            let code = try Self.strippedSource(at: site.path)
            let pattern = "CadenceAppleCalendarNaming\\.\(site.expression)"
            #expect(
                CadenceSourceScan.matchCount(pattern, in: code) == site.count,
                """
                \(site.path) reads CadenceAppleCalendarNaming.\(site.expression) \
                \(CadenceSourceScan.matchCount(pattern, in: code)) times, expected \(site.count)
                """
            )
            #expect(
                !code.contains("\"Apple Calendar\""),
                "\(site.path) still spells \"Apple Calendar\" beside the constant that holds it"
            )
        }
    }

    /// **Nothing under `Cadence/` types the literal except the file that declares it.**
    ///
    /// Through `CadenceScanInstrument` rather than a bare `contains`, so a blinded detector cannot
    /// reach the walk: its witnesses are the nearest possible miss — the same line once typed and
    /// once read off the constant, with the prose form on the negative side, because this repo's
    /// doc comments say "Apple Calendar" far more often than its code does.
    @Test func onlyTheDeclarationTypesTheAppleCalendarLiteral() throws {
        let instrument = try CadenceScanInstrument(
            "Apple Calendar typed rather than read",
            fires: """
            struct Screen {
                let subtitle = "Apple Calendar"
            }
            """,
            andNotOn: """
            struct Screen {
                // Says "Apple Calendar", from CadenceAppleCalendarNaming.
                let subtitle = CadenceAppleCalendarNaming.integrationSectionTitle
            }
            """,
            by: { CadenceSourceScan.strippingComments($0).contains("\"Apple Calendar\"") }
        )

        let hits = try instrument.sweep(
            CadenceSourceScan.swiftFiles(under: "Cadence"),
            // 300+ Swift files under `Cadence/`; the floor the shared-constant sweep uses.
            atLeast: 300,
            // One of the eight original sites, so a walk that skipped the iOS tree cannot report
            // the repo clean.
            including: "Cadence/iOS/iOSBoardCards.swift",
            read: CadenceSourceScan.strippedSourceReader()
        )

        #expect(
            hits == ["Cadence/Shared/CadenceAppleCalendarNaming.swift"],
            "\"Apple Calendar\" is typed outside its declaration in \(hits)"
        )
    }

    /// The harvest sees all three, so `noCallSiteRetypesASharedStringConstant` guards them too.
    ///
    /// Not redundant with the sweep above: that one is this ticket's, and it will be deleted the
    /// day somebody decides the three names deserve three different sentences. This asserts the
    /// standing guard picked them up, which is what survives that day.
    @Test func allThreeAppleCalendarConstantsAreInTheSharedHarvest() throws {
        let harvested = try cadenceSharedStringConstants()
            .filter { $0.declaredIn == "Cadence/Shared/CadenceAppleCalendarNaming.swift" }
        #expect(
            Set(harvested.map(\.name)) == [
                "integrationSectionTitle",
                "unnamedCalendarTitle",
                "unnamedAccountTitle",
            ],
            "the harvest read \(harvested.map(\.name)) from the naming file"
        )
        #expect(harvested.allSatisfy({ $0.literal == "Apple Calendar" }))
    }

    /// The reader used above keeps literals; `codeOnly` blanks them. Pinned so the pairing cannot
    /// collapse into a permanently-green scan.
    @Test func theNamingScanReadsLiteralsRatherThanBlankingThem() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/Shared/CadenceAppleCalendarNaming.swift")
        #expect(CadenceSourceScan.strippingComments(raw).contains("\"Apple Calendar\""))
        #expect(CadenceSourceScan.codeOnly(raw).contains("\"Apple Calendar\"") == false)
    }

    // MARK: - T-692: the same absence, two words, on the same platform

    /// **The fixture, not the assumption.** `EKCalendar.source` is only ever unset in code by
    /// leaving a freshly-minted, never-saved calendar alone — there is no initializer that takes a
    /// source, and asking a real `EKEventStore` for its sources needs calendar access this suite
    /// does not have and must not request. A fresh `EKCalendar` has no source until one is
    /// assigned, so it reproduces the exact absence both call sites fall back on without touching
    /// EventKit permissions at all.
    ///
    /// Before T-692, `calendar.source?.title ?? "Other"` (`CadenceCalendarPicker`) and
    /// `calendar.source?.title ?? CadenceAppleCalendarNaming.unnamedAccountTitle` (Settings →
    /// Calendar) disagreed for this identical calendar. This pins that they no longer can: both
    /// expressions are the same expression now, so there is nothing left for them to disagree
    /// about, and a regression would have to reintroduce a second literal to reopen the gap.
    @Test func anUnnamedSourceReadsTheSameWordEverySiteThatFallsBackOnIt() {
        let store = EKEventStore()
        let calendarWithNoSource = EKCalendar(for: .event, eventStore: store)
        calendarWithNoSource.title = "Untitled Calendar"

        #expect(
            calendarWithNoSource.source == nil,
            "the fixture calendar already has a source, so it does not reproduce the absence T-692 is about"
        )

        // Settings → Calendar's fallback, and — after T-692 — `CadenceCalendarPicker`'s: the same
        // expression, so pinning it once covers both call sites' behaviour. The call-site scan in
        // `everySiteReadsTheConstantForTheConceptItMeans` is what confirms the picker actually
        // reads this constant rather than a second copy of the same literal.
        let resolved = calendarWithNoSource.source?.title ?? CadenceAppleCalendarNaming.unnamedAccountTitle
        #expect(resolved == "Apple Calendar")
    }
}
