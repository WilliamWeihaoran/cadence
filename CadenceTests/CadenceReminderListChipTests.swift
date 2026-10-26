import Foundation
import Testing
@testable import Cadence

/// [[T-7009]]: an Apple Reminder whose list has no title draws no list chip in the Inbox, on
/// either platform, through one shared answer.
///
/// `RemindersManager.makeItem` stores an untitled list as `""` (it is the grouping key), and both
/// rows printed it raw: an empty purple capsule on macOS, a bare glyph on iOS. The behaviour half
/// pins the shared answer; the source half pins that both rows ask it and neither prints
/// `reminder.listTitle` itself.
struct CadenceReminderListChipTests {

    @Test func anUntitledListHasNoChipAndANamedOneKeepsItsName() {
        #expect(AppleReminderRowPresentation.listChipTitle("") == nil)
        #expect(AppleReminderRowPresentation.listChipTitle("   ") == nil)
        #expect(AppleReminderRowPresentation.listChipTitle("\n\t ") == nil)
        #expect(AppleReminderRowPresentation.listChipTitle("Groceries") == "Groceries")
        // A named list is drawn as Apple Reminders spells it, not trimmed into a different name.
        #expect(AppleReminderRowPresentation.listChipTitle(" Work ") == " Work ")
    }

    @Test func bothInboxRowsDrawTheListChipOnlyThroughTheSharedAnswer() throws {
        let rows: [(path: String, declaration: String)] = [
            ("Cadence/macOS/Views/InboxSupportViews.swift", "private struct AppleReminderTaskRow: View"),
            ("Cadence/iOS/iOSInboxRemindersSection.swift", "private struct iOSInboxReminderRow: View"),
        ]
        for row in rows {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(row.path))
            guard let body = CadenceSourceScan.declarationBody(row.declaration, in: source) else {
                Issue.record("\(row.path): \(row.declaration) not found")
                continue
            }
            let dense = body.filter { !$0.isWhitespace }
            #expect(
                dense.contains("ifletlistChipTitle=AppleReminderRowPresentation.listChipTitle(reminder.listTitle)"),
                "\(row.path) no longer asks whether its reminder's list has a name to draw"
            )
            // The defect by name: the stored title printed straight into the chip.
            #expect(!dense.contains("Text(reminder.listTitle)"), "\(row.path) prints the raw list title again")
            #expect(!dense.contains("text:reminder.listTitle"), "\(row.path) prints the raw list title again")
            // Non-vacuity: the chip itself is still drawn from the answer.
            #expect(
                dense.contains("Text(listChipTitle)") || dense.contains("text:listChipTitle"),
                "\(row.path) asks the shared answer but no longer draws it"
            )
        }
    }
}
