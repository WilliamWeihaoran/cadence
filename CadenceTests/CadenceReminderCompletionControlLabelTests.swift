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

    /// [[T-8735]]: both Inbox reminder rows carry priority on the shared completion circle. The
    /// macOS row drew a 3pt vertical priority bar beside its own grey `Circle().strokeBorder`, which
    /// turned green when ticked; iOS's row has always drawn `CadenceTaskCompletionCircle` tinted by
    /// priority and no bar. Its two metadata labels are unfilled, as `MacTaskRow`'s dates are.
    @Test func bothInboxRowsDrawPriorityOnTheSharedCompletionCircle() throws {
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
                CadenceSourceScan.matchCount(
                    #"CadenceTaskCompletionCircle\(\s*glyph:\s*\.binary\(\s*isDone:\s*rowState\.isCompleting,\s*tint:\s*AppleReminderRowPresentation\.priorityTint\(reminder\.priority\)"#,
                    in: body
                ) == 1,
                "\(row.path) no longer tints the shared completion circle by the reminder's priority"
            )
            #expect(
                CadenceSourceScan.matchCount(#"Circle\(\)\s*\.(strokeBorder|stroke|fill)\("#, in: body) == 0,
                "\(row.path) hand-draws its own completion circle again"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\.frame\(width:\s*3\)"#, in: body) == 0,
                "\(row.path) draws a vertical priority bar again"
            )
            #expect(
                CadenceSourceScan.matchCount(#"\.background\("#, in: body) <= 1,
                "\(row.path) fills a metadata chip again; only the row's hover wash is a background"
            )
        }
    }
}
