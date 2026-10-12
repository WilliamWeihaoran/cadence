import Foundation
import Testing
@testable import Cadence

/// **T-720.** `TaskRecurrenceRule` used to carry `label` and `shortLabel` side by side, four of
/// their five arms byte-identical ("Daily"/"Weekly"/"Monthly"/"Yearly"), differing only on
/// `.none` ("Never" vs "None").
///
/// **Nobody read that difference.** Every caller of `shortLabel` — `iOSTaskRowRepeatChip`, the
/// collapsed `Repeat:` menu title, the embedded task-card chip, and `FocusSidebar`'s repeat chip —
/// only reads it behind a guard that already excludes `.none` (`task.recurrenceRule != .none` or
/// `task.isRecurring`), so the one arm where the two spellings disagreed was unreachable through
/// every one of them. There was no caller for the distinction to serve, so `shortLabel` is gone
/// rather than kept as a second base for one property to inherit, and every former caller reads
/// `label` instead. A picker or menu listing every case — including the "turn recurrence off"
/// choice — still reads `.none` as "Never" through `label`, unchanged.
struct TaskRecurrenceRuleLabelTests {

    // MARK: - Behavioural

    @Test func labelSpellsEveryArmIncludingNever() {
        #expect(TaskRecurrenceRule.none.label == "Never")
        #expect(TaskRecurrenceRule.daily.label == "Daily")
        #expect(TaskRecurrenceRule.weekly.label == "Weekly")
        #expect(TaskRecurrenceRule.monthly.label == "Monthly")
        #expect(TaskRecurrenceRule.yearly.label == "Yearly")
    }

    // MARK: - Source shape: the duplicate is gone, not renamed

    @Test func taskRecurrenceRuleNoLongerDeclaresAShortLabel() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/Models/ModelEnums.swift")
        )
        let enumBody = try #require(
            CadenceSourceScan.declarationBody("enum TaskRecurrenceRule", in: source)
        )
        #expect(!enumBody.contains("shortLabel"), "shortLabel should have been folded into label")
    }

    /// The four call sites the ticket named, each read as reading `label` and not `shortLabel`.
    @Test func everyFormerShortLabelCallerNowReadsLabel() throws {
        let sites: [(file: String, needle: String)] = [
            ("Cadence/iOS/iOSTaskRowActionViews.swift", "title: task.recurrenceRule.label,"),
            (
                "Cadence/iOS/iOSTaskRowActionViews.swift",
                #"Label(task.recurrenceRule == .none ? "Repeat" : "Repeat: \(task.recurrenceRule.label)", systemImage: "repeat")"#
            ),
            ("Cadence/macOS/Editor/MarkdownTaskEmbedDrawingSupport.swift", "label: recurrence.label,"),
            (
                "Cadence/macOS/Views/FocusSidebarSupportViews.swift",
                "FocusStatusChip(title: task.recurrenceRule.label, color: Theme.blue, icon: \"arrow.clockwise\")"
            )
        ]
        for site in sites {
            let source = try CadenceSourceScan.sourceFile(site.file)
            #expect(source.contains(site.needle), "\(site.file) does not read \(site.needle)")
            #expect(
                !source.contains("recurrenceRule.shortLabel") && !source.contains("recurrence.shortLabel"),
                "\(site.file) still reads the removed shortLabel"
            )
        }
    }

    /// Self-checked instrument for the retired accessor: fires on either spelling of a
    /// `shortLabel` read, and not on the `label` read that replaced it.
    static let shortLabelReaderInstrument = try! CadenceScanInstrument(
        "taskRecurrenceRuleShortLabelReader",
        fires: "FocusStatusChip(title: task.recurrenceRule.shortLabel, color: Theme.blue)",
        andNotOn: "FocusStatusChip(title: task.recurrenceRule.label, color: Theme.blue)"
    ) { source in
        source.contains("recurrenceRule.shortLabel") || source.contains("recurrence.shortLabel")
    }

    @Test func theShortLabelReaderInstrumentStillDiscriminates() {
        #expect(Self.shortLabelReaderInstrument.fires(on: "task.recurrenceRule.shortLabel"))
        #expect(Self.shortLabelReaderInstrument.fires(on: "label: recurrence.shortLabel,"))
        #expect(!Self.shortLabelReaderInstrument.fires(on: "label: recurrence.label,"))
    }

    /// **T-3112.** The `#expect` used to sit *inside* the walk loop, so a walk over zero files
    /// fired zero assertions and the test reported PASSED — and
    /// `CadenceSourceScan.swiftFiles(under:)` returns `[]` *silently* when the enumerator is nil.
    /// Routed through the shared `sweep`, whose `atLeast:`/`including:` are non-defaulted for
    /// exactly this reason, so the assertion is now one claim about a walk that is proved to have
    /// happened. 613 `.swift` files under `Cadence/` measured 2026-10-11; the witness is one of
    /// the four converted call sites `everyFormerShortLabelCallerNowReadsLabel` pins by name, so
    /// the two tests go red together if it moves.
    @Test func noSourceFileReadsTaskRecurrenceRulesShortLabel() throws {
        let readers = try Self.shortLabelReaderInstrument.sweep(
            try CadenceSourceScan.swiftFiles(under: "Cadence"),
            atLeast: 500,
            including: "Cadence/iOS/iOSTaskRowActionViews.swift",
            read: CadenceSourceScan.sourceFile
        )
        #expect(readers.isEmpty, "these files still read TaskRecurrenceRule.shortLabel: \(readers)")
    }
}
