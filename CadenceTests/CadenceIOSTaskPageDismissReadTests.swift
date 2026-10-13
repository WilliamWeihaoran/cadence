import Foundation
import Testing
@testable import Cadence

/// **T-3155: the two pages All Tasks is drawn through do not read `\.dismiss` themselves.**
///
/// `DismissAction` is replaced whenever a sheet is presented or dismissed above the view that reads
/// it. Tapping the tab bar's `+` over All Tasks therefore re-ran `iOSTasksPageView` and
/// `iOSTaskCollectionPage` twice on the way up and twice on the way down — `Self._printChanges()`
/// named `_dismiss` and nothing else — and each pass over `iOSTasksPageView` rebuilt
/// `iOSAllTasksView`, whose body filters and sorts the whole store. Measured on the standing
/// iPhone simulator at 0, 300 and 3,000 tasks, scratch tree only: those two bodies ran 8 times per
/// present-and-dismiss before (10 on the one cold first trial), and 0 in all 18 trials after. The fix is `iOSCompactBackActionReader`, which reads the action in a body of its
/// own so the change re-runs the header row alone.
///
/// The behaviour can only be counted on a simulator; `Cadence/iOS/` is behind `#if os(iOS)` and this
/// target builds for macOS. So this pins the structure that behaviour depends on, as counts: no
/// `@Environment(\.dismiss)` on either page, the reader in each page's header, and exactly one
/// `\.dismiss` read inside the reader itself.
struct CadenceIOSTaskPageDismissReadTests {
    private static let dismissRead = #"@Environment\(\\\.dismiss\)"#

    private static let pages = [
        "Cadence/iOS/iOSTasksPageView.swift",
        "Cadence/iOS/iOSTaskCollectionPage.swift",
    ]

    @Test func neitherAllTasksPageReadsTheDismissActionInItsOwnBody() throws {
        for path in Self.pages {
            let source = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                CadenceSourceScan.matchCount(Self.dismissRead, in: source) == 0,
                "\(path) reads \\.dismiss itself, so every sheet presented over it re-runs its body (T-3155)"
            )
            // Non-vacuity: the page still has a back action, and it comes from the reader.
            #expect(
                CadenceSourceScan.matchCount(#"iOSCompactBackActionReader\s*\{\s*onBack\s+in"#, in: source) == 1,
                "\(path) no longer takes its compact back action from iOSCompactBackActionReader"
            )
        }
    }

    @Test func theReaderIsWhereTheDismissActionIsRead() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSFeatureComponents.swift")
        )
        let reader = try #require(
            CadenceSourceScan.declarationBody("struct iOSCompactBackActionReader<", in: source),
            "iOSCompactBackActionReader is gone from iOSFeatureComponents.swift"
        )
        #expect(CadenceSourceScan.matchCount(Self.dismissRead, in: reader) == 1)
        // The compact-only rule the three pushed task pages share: no chevron where the iPad shell
        // hosts the page with no stack around it.
        #expect(CadenceSourceScan.matchCount(#"horizontalSizeClass == \.compact \? \{ dismiss\(\) \} : nil"#, in: reader) == 1)
    }
}
