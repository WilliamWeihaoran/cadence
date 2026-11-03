import Foundation
import Testing
@testable import Cadence

/// **[[T-7985]] (Mac) and [[T-10461]] (iOS): the Inbox's Group menu offers None, By Date and By
/// Priority only, and a stored By List reads as None.**
///
/// No Inbox task is in a list by definition, so By List could only draw one "Inbox" heading over
/// every row. Both platforms ask `TaskGroupingMode.excluded(on:)` for the menu and bind the stored
/// value through `inboxResolved`, so the two Inboxes cannot drift ([[T-8201]]). The answer is run;
/// the wiring is read from source, because neither page can be hosted in a unit test.
struct CadenceInboxGroupingCasesTests {
    private static func code(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            .filter { !$0.isWhitespace }
    }

    @Test func theInboxOffersNoneByDateAndByPriorityOnly() {
        #expect(TaskGroupingMode.offered(on: .inbox) == [.none, .byDate, .byPriority])
        #expect(TaskGroupingMode.excluded(on: .inbox) == [.byList])
    }

    @Test func allTasksStillOffersEveryGrouping() {
        #expect(TaskGroupingMode.offered(on: .all) == TaskGroupingMode.allCases)
        #expect(TaskGroupingMode.excluded(on: .all).isEmpty)
    }

    @Test func aStoredByListReadsAsNoneInTheInbox() {
        #expect(TaskGroupingMode.byList.inboxResolved == .none)
        for mode in TaskGroupingMode.offered(on: .inbox) {
            #expect(mode.inboxResolved == mode, "\(mode.rawValue)")
        }
        // Writing through the projection stores what was picked.
        var stored = TaskGroupingMode.byList
        stored.inboxResolved = .byPriority
        #expect(stored == .byPriority)
    }

    /// The Mac page: its Group badge leaves out what the scope excludes, and the Inbox's binding
    /// reads through `inboxResolved` so the list never groups by a case its menu cannot show.
    @Test func theMacInboxReadsTheSharedAnswer() throws {
        let mac = try Self.code("Cadence/macOS/Views/macOSRootSupportViews.swift")
        #expect(mac.contains(#"CadenceEnumPickerBadge(title:"Group",selection:groupingMode,excluded:TaskGroupingMode.excluded(on:scope))"#))
        #expect(mac.contains("scope==.inbox?$inboxGroupingMode.inboxResolved:$allGroupingMode"))
    }

    /// The iOS side: the chip filters its rows by `excluded`, the bar hands the Group chip the
    /// page's exclusions, the collection page asks the shared answer for its scope, and the Inbox
    /// binds through `inboxResolved`.
    @Test func theIOSInboxReadsTheSharedAnswer() throws {
        let views = try Self.code("Cadence/iOS/iOSTaskViews.swift")
        #expect(views.contains("rows:Array(T.allCases).filter{!excluded.contains($0)}"))
        #expect(views.contains(#"iOSEnumChoiceChip(title:"Group",glyph:"rectangle.3.group",selection:$groupingMode,excluded:excludedGroupings)"#))

        let page = try Self.code("Cadence/iOS/iOSTaskCollectionPage.swift")
        #expect(page.contains("excludedGroupings:TaskGroupingMode.excluded(on:CadenceTasksPageScope(collection:collection))"))

        let inbox = try Self.code("Cadence/iOS/iOSInboxView.swift")
        #expect(inbox.contains("groupingMode:$groupingMode.inboxResolved"))
    }
}
