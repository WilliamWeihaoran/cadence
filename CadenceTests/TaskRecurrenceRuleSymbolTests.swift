import Foundation
import Testing
@testable import Cadence

/// **[[T-12285]].** `TaskRecurrenceRule.systemImage` drew `.daily` as `sun.max` — the app's
/// do-date/Today glyph — and the other periods as calendar glyphs, while `.none`, the one case
/// that does not repeat, was the only one given a loop. Seen on the phone: a daily undated task
/// in the Inbox under a `Daily` chip with a sun on it.
///
/// Decided (keeper, 2026-11-06): every repeating case draws the capture card's `repeat` loop; the
/// period is told by the label beside it. `.none` draws a neutral glyph that is neither a loop nor
/// a date.
struct TaskRecurrenceRuleSymbolTests {

    private static let repeating: [TaskRecurrenceRule] = TaskRecurrenceRule.allCases.filter { $0 != .none }

    @Test func everyRepeatingCaseDrawsTheCaptureCardsRepeatLoop() {
        #expect(Self.repeating.count == TaskRecurrenceRule.allCases.count - 1, "non-vacuity: .none plus the periods")
        for rule in Self.repeating {
            #expect(rule.systemImage == TaskRecurrenceRule.repeatSymbol, "\(rule) does not draw the repeat loop")
            #expect(rule.systemImage == CadenceCaptureField.repeatRule.symbol,
                    "\(rule) disagrees with the capture card's Repeat field about the same value")
        }
    }

    @Test func theNonRepeatingCaseDrawsNoLoop() {
        let glyph = TaskRecurrenceRule.none.systemImage
        #expect(glyph == TaskRecurrenceRule.notRepeatingSymbol)
        #expect(glyph != TaskRecurrenceRule.repeatSymbol, "Never must not draw the repeat loop")
        #expect(!glyph.hasPrefix("repeat") && !glyph.hasPrefix("arrow."),
                "Never must not draw any loop-shaped glyph: \(glyph)")
    }

    /// No recurrence glyph may borrow a date glyph: the sun is the do-date/Today glyph, and a
    /// calendar reads as a date being set.
    @Test func noCaseBorrowsADateGlyph() {
        #expect(CadenceBoardCardMetadata.doDateIcon.hasPrefix("sun."), "non-vacuity: the do-date glyph is still a sun")
        for rule in TaskRecurrenceRule.allCases {
            #expect(!rule.systemImage.hasPrefix("sun."), "\(rule) draws the do-date sun")
            #expect(!rule.systemImage.hasPrefix("calendar"), "\(rule) draws a date glyph")
        }
    }

    // MARK: - Source shape: the field rows and the Focus chip name the field, not the rule

    /// A "Repeat" field row is the field's own icon, whatever rule it holds; reading the rule's
    /// glyph there would draw `minus.circle` — a remove button — beside "Repeat · Never".
    @Test func repeatFieldRowsAndTheFocusChipReadTheSharedRepeatSymbol() throws {
        let sites: [(file: String, needle: String)] = [
            ("Cadence/Shared/Components/CadenceSchedulePanel.swift",
             #"CadenceFieldRow(label: "Repeat", systemImage: TaskRecurrenceRule.repeatSymbol"#),
            ("Cadence/iOS/iOSTaskDetailSheetSections.swift",
             #"iOSEditorFieldRow(label: "Repeat", systemImage: TaskRecurrenceRule.repeatSymbol"#),
            ("Cadence/macOS/Views/FocusSidebarSupportViews.swift",
             "icon: TaskRecurrenceRule.repeatSymbol)"),
            ("Cadence/Shared/Components/CadenceScheduleCaptureCard.swift",
             "case .repeatRule: return TaskRecurrenceRule.repeatSymbol"),
        ]
        for site in sites {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(site.file))
            #expect(source.contains(site.needle), "\(site.file) does not read \(site.needle)")
            #expect(!source.contains("repeatRule.systemImage, color"), "\(site.file) draws the rule's glyph as the field icon")
        }
    }
}
