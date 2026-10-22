// T-3269: compiled for macOS only — it scans a macOS-only view file, and the suite has nothing to
// say on the iOS leg.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **The macOS Calendar page title draws on one line at any window width** ([[T-3269]]).
///
/// Seen at the launcher's ~960pt window: the zoom stepper, the Week/Month/Board picker and the
/// Today button squeezed the title group until "Calendar" drew as `Cal` / `end` / `ar` and the
/// period label as `Octobe` / `r 2026`. Neither `Text` had a line limit, and the group sat at the
/// same layout priority as the controls, so the toolbar's `HStack` shared the width out equally.
///
/// Three claims, each a separate way the defect comes back:
///
/// 1. the title `Text("Calendar")` is one line AND holds its ideal width — it is a single fixed
///    word, so truncating it is as wrong as wrapping it;
/// 2. the period label is one line (it is the half allowed to give way, by tail truncation —
///    the same rule `DesktopPageHeader.eyebrowLine` follows);
/// 3. the group carries `.layoutPriority(1)`, so it is laid out before the controls.
///
/// Source-scanned because SwiftUI's stack allocation is not reachable from a unit test: there is
/// no seam that reports which subview won the width. Not seen on screen ([[T-3259]]).
struct CalendarPageToolbarTitleLineTests {
    private static func toolbarBody() throws -> String {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/CalendarPageSupportViews.swift")
        )
        return try #require(
            CadenceSourceScan.declarationBody("struct CalendarPageToolbar: View", in: source)
        )
    }

    /// The text between `start` and the next `Text(` (or the end of the body): one `Text`'s own
    /// modifier chain.
    private static func modifierChain(after start: String, in body: String) throws -> String {
        let head = try #require(body.range(of: start), "\(start) is gone from the toolbar")
        let rest = body[head.upperBound...]
        let end = rest.range(of: "Text(")?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    @Test func theCalendarPageTitleNeitherWrapsNorTruncates() throws {
        let chain = try Self.modifierChain(after: #"Text("Calendar")"#, in: try Self.toolbarBody())
        #expect(chain.contains(".lineLimit(1)"), "the Calendar title can wrap mid-word again")
        #expect(
            chain.contains(".fixedSize(horizontal: true, vertical: false)"),
            "the Calendar title no longer holds its own width, so a narrow window truncates it"
        )
    }

    @Test func theCalendarPeriodLabelStaysOnOneLine() throws {
        let chain = try Self.modifierChain(after: "Text(calendarTitleLabel)", in: try Self.toolbarBody())
        #expect(chain.contains(".lineLimit(1)"), "the period label can wrap mid-word again")
    }

    @Test func theCalendarTitleGroupIsLaidOutBeforeTheToolbarControls() throws {
        let body = try Self.toolbarBody()
        let label = try #require(body.range(of: "Text(calendarTitleLabel)"))
        let spacer = try #require(body.range(of: "Spacer()", range: label.upperBound..<body.endIndex))
        let between = body[label.upperBound..<spacer.lowerBound]
        #expect(
            between.contains(".layoutPriority(1)"),
            "the title group shares the toolbar's width with the controls instead of going first"
        )
    }
}
#endif
