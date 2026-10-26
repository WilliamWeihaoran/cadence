import Foundation
import Testing
@testable import Cadence

/// [[T-7007]]: the Apple Reminders completion circle has one name and one read-only fade, shared by
/// the macOS Inbox row and the iOS one.
///
/// macOS called its circle "Complete in Apple Reminders" whatever the list allowed and drew a
/// read-only list's disabled circle at full strength; iOS said "This reminder list is read-only"
/// and faded it. The behaviour half pins the shared answers; the source half pins that both rows
/// read them and that neither spells its own.
struct CadenceReminderCompletionControlLabelTests {

    @Test func theCircleSaysWhetherItCanCompleteAnything() {
        #expect(
            AppleReminderRowPresentation.completionControlLabel(allowsCompletion: true)
                == "Complete reminder in Apple Reminders"
        )
        #expect(
            AppleReminderRowPresentation.completionControlLabel(allowsCompletion: false)
                == "This reminder list is read-only"
        )
        #expect(AppleReminderRowPresentation.completionControlOpacity(allowsCompletion: true) == 1)
        #expect(AppleReminderRowPresentation.completionControlOpacity(allowsCompletion: false) < 1)
    }

    @Test func bothInboxRowsReadTheSharedLabelAndFade() throws {
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
            #expect(
                body.contains("AppleReminderRowPresentation.completionControlLabel(allowsCompletion: reminder.allowsCompletion)"),
                "\(row.path) names its completion circle itself again"
            )
            #expect(
                body.contains("AppleReminderRowPresentation.completionControlOpacity(allowsCompletion: reminder.allowsCompletion)"),
                "\(row.path) no longer fades a read-only list's circle"
            )
            for retired in ["\"Complete in Apple Reminders\"", "\"Complete reminder in Apple Reminders\"", "\"This reminder list is read-only\""] {
                #expect(!body.contains(retired), "\(row.path) spells \(retired) itself")
            }
        }
    }
}
