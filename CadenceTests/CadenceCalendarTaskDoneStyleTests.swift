import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// [[T-8241]]: a finished task looks the same on the iOS calendar as on the macOS one — diagonal
/// stripes over the timed block and a green check on the chips, never a strikethrough.
///
/// The decision lives once, in `CadenceCalendarTaskDoneStyle` and `DiagonalStripeOverlay`
/// (Shared), and both platforms read it ([[T-8201]]). The first three tests pin the decision; the
/// rest pin that each surface still asks it rather than growing its own copy again.
@MainActor
struct CadenceCalendarTaskDoneStyleTests {
    private static let doneStyleFile = "Cadence/Shared/CadenceCalendarTaskDoneStyle.swift"
    private static let iOSMonthFile = "Cadence/iOS/iOSCalendarMonthViews.swift"
    private static let iOSTimelineFile = "Cadence/iOS/iOSCalendarTimelineViews.swift"
    private static let macOSBlockFile = "Cadence/macOS/Views/TimelineTaskBlockSupportViews.swift"
    private static let macOSChipsFile = "Cadence/macOS/Views/CalendarPageMonthSupportViews.swift"

    @Test func onlyTheSettledStatesReplaceTheCallersOpenGlyph() {
        for open in ["circle", "circle.fill", "circle.dashed"] {
            #expect(CadenceCalendarTaskDoneStyle.chipGlyphSymbol(for: .done, open: open) == "checkmark.circle.fill")
            #expect(CadenceCalendarTaskDoneStyle.chipGlyphSymbol(for: .cancelled, open: open) == "xmark.circle.fill")
            for state in [CadenceTaskCompletionState.todo, .pendingCompletion, .pendingCancellation] {
                #expect(CadenceCalendarTaskDoneStyle.chipGlyphSymbol(for: state, open: open) == open)
            }
        }
    }

    /// The grey check iOS drew is the defect: done is `Theme.green` on both platforms.
    @Test func aDoneChipGlyphIsGreenAndACancelledOneIsThePlatesTertiaryTier() {
        #expect(CadenceCalendarTaskDoneStyle.chipGlyphTint(for: .done) == Theme.green)
        #expect(CadenceCalendarTaskDoneStyle.chipGlyphTint(for: .done) != CadenceCalendarEventStyle.plateTertiaryLabelColor())
        #expect(
            CadenceCalendarTaskDoneStyle.chipGlyphTint(for: .cancelled)
                == CadenceCalendarEventStyle.plateTertiaryLabelColor()
        )
        for state in [CadenceTaskCompletionState.todo, .pendingCompletion, .pendingCancellation] {
            #expect(CadenceCalendarTaskDoneStyle.chipGlyphTint(for: state) == nil, "\(state) took a settled tint")
        }
    }

    /// macOS's rule, `task.isDone`: done drops a tier, cancelled does not.
    @Test func onlyADoneTaskDropsItsTitleATier() {
        for state in CadenceTaskCompletionState.allCases {
            #expect(CadenceCalendarTaskDoneStyle.dimsTitle(for: state) == (state == .done), "\(state)")
        }
    }

    /// One stripe overlay, in Shared, outside any platform gate; macOS no longer keeps a copy.
    @Test func theStripeOverlayIsDeclaredOnceAndSharedByBothTimedBlocks() throws {
        let shared = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.doneStyleFile))
        #expect(CadenceSourceScan.matchCount(#"struct DiagonalStripeOverlay: View"#, in: shared) == 1)
        #expect(!shared.contains("#if os("), "the shared done style went behind a platform gate")

        let macOS = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macOSBlockFile))
        #expect(!macOS.contains("struct DiagonalStripeOverlay"), "macOS grew its own stripe overlay again")
        #expect(CadenceSourceScan.matchCount(#"if task\.isDone \{\s*DiagonalStripeOverlay\(\)"#, in: macOS) == 1)

        let iOS = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSTimelineFile))
        #expect(!iOS.contains("struct DiagonalStripeOverlay"), "iOS grew its own stripe overlay")
        #expect(CadenceSourceScan.matchCount(#"if task\.isDone \{\s*DiagonalStripeOverlay\(\)"#, in: iOS) == 1)
        #expect(CadenceSourceScan.matchCount(#"\.strikethrough\("#, in: iOS) == 0, "the iOS calendar struck a title through again")
        #expect(
            iOS.contains("CadenceCalendarTaskDoneStyle.dimsTitle(for: .resolve(task: task)) ? secondaryInk : primaryInk"),
            "the iOS timed block no longer drops a done title through the shared rule"
        )
    }

    /// The iOS chip used to have no done input at all; it now reads the shared decision for its
    /// glyph, the glyph's tint and the title tier, and both task call sites hand it the state.
    @Test func theIOSMiniChipDrawsTheSharedDoneLook() throws {
        let month = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSMonthFile))
        let chip = try #require(CadenceSourceScan.declarationBody("struct iOSCalendarMiniChip: View", in: month))
        #expect(chip.contains("var completion: CadenceTaskCompletionState? = nil"))
        #expect(chip.contains("CadenceCalendarTaskDoneStyle.chipGlyphSymbol(for: $0, open: icon)"))
        #expect(chip.contains("completion.flatMap { CadenceCalendarTaskDoneStyle.chipGlyphTint(for: $0) } ?? openGlyphTint"))
        #expect(chip.contains("CadenceCalendarTaskDoneStyle.dimsTitle(for: completion)"))
        #expect(chip.contains(".foregroundStyle(titleInk)"))

        #expect(CadenceSourceScan.matchCount(#"completion: \.resolve\(task: task\)"#, in: month) == 1)
        let timeline = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.iOSTimelineFile))
        #expect(CadenceSourceScan.matchCount(#"completion: \.resolve\(task: task\)"#, in: timeline) == 1)
        // The callers pass the OPEN glyph now; a caller choosing the check itself is the old shape.
        #expect(!month.contains(#"task.isDone ? "checkmark.circle.fill""#))
        #expect(!timeline.contains(#"task.isDone ? "checkmark.circle.fill""#))
    }

    /// And macOS reads the same decision for both of its task chips, so the two cannot drift.
    @Test func theMacChipsAskTheSameDecision() throws {
        let macOS = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(Self.macOSChipsFile))
        for declaration in ["struct MonthTaskChip: View", "struct AllDayTaskChip: View"] {
            let body = try #require(CadenceSourceScan.declarationBody(declaration, in: macOS))
            #expect(body.contains("CadenceCalendarTaskDoneStyle.chipGlyphSymbol(for: .resolve(task: task), open: \"circle\")"), "\(declaration)")
            #expect(body.contains("CadenceCalendarTaskDoneStyle.chipGlyphTint(for: .resolve(task: task))"), "\(declaration)")
        }
    }
}
