import Foundation
import Testing
@testable import Cadence

/// **T-6002.** Settings → Navigation → "Sidebar Rows" offered Calendar, Notes and Focus switches
/// on iPhone that changed nothing: the phone reads the synced layout only in the Tasks index,
/// Calendar and Notes are fixed tabs, and Focus is a row of the static `compactMoreSections`,
/// which never reads the hidden set. The owner's answer was to list only the rows the phone
/// honours rather than to caption the card — a control that appears to fail is worse than a
/// control that is not there.
///
/// iPad and Mac are untouched and a test below says so: the filter is asked only at compact width,
/// and the stored preference still carries every row.
///
/// `Cadence/iOS/` is invisible to this macOS test target, so the rule is driven directly and the
/// view's use of it is pinned as source text.
@MainActor
@Suite
struct CadenceCompactSidebarRowsTests {

    // MARK: - Behavioural: the rule

    @Test func compactKeepsOnlyTheRowsTheTasksTabOwnsAndDropsTheThreeThePhoneIgnores() {
        let all = CadenceSidebarLayout.primaryDestinations + [CadenceFeatureDestination.focus]
        let honoured = CadenceCompactTab.honouredSidebarRows(all)

        #expect(honoured == [.today, .allTasks])
        for ignored in [CadenceFeatureDestination.calendar, .notes, .focus] {
            #expect(!honoured.contains(ignored))
        }
    }

    /// The filter is the caller's order narrowed, never re-sorted: a user who moved All Tasks above
    /// Today on the Mac sees that order on the phone's card too.
    @Test func compactKeepsTheOrderItWasGiven() {
        let reordered: [CadenceFeatureDestination] = [.notes, .allTasks, .focus, .today, .calendar]
        #expect(CadenceCompactTab.honouredSidebarRows(reordered) == [.allTasks, .today])
        #expect(CadenceCompactTab.honouredSidebarRows([]).isEmpty)
    }

    /// The card and the index must not be able to disagree about what the phone honours — the
    /// defect was exactly a card offering rows the index would never read.
    @Test func theCardsCompactRowsAreTheRowsTheTasksIndexActuallyLists() {
        let hidden: Set<CadenceFeatureDestination> = [.calendar]
        let index = CadenceCompactTab.tasksIndexDestinations(hidden: hidden)
            .filter { $0 != .inbox }
        let card = CadenceCompactTab.honouredSidebarRows(
            CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(
                for: .init(order: [], hidden: hidden)
            )
        )
        #expect(card == index)
        #expect(card == [.today, .allTasks])
    }

    /// Regular width is unchanged: every customisable row is still offered, Focus included.
    @Test func regularWidthStillOffersEveryCustomisableRow() {
        let ordered = CadenceSidebarLayoutPreferenceStore.orderedCustomisableDestinations(
            for: .init(order: [], hidden: [])
        )
        #expect(Set(ordered) == CadenceSidebarLayout.customisableDestinations)
        #expect(ordered.count == 5)
    }

    // MARK: - Source pin: the view asks the rule, and only at compact width

    @Test func theSettingsCardNarrowsItsRowsOnlyAtCompactWidth() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSidebarLayoutSettingsSection.swift")
        )
        let section = try #require(
            CadenceSourceScan.declarationBody("struct iOSSidebarLayoutSettingsSection", in: source)
        )
        #expect(section.contains("@Environment(\\.horizontalSizeClass)"))

        let rows = try #require(CadenceSourceScan.declarationBody("private var rows:", in: section))
        #expect(rows.contains("horizontalSizeClass == .compact"))
        #expect(rows.contains("CadenceCompactTab.honouredSidebarRows("))
        // The regular-width answer is the unfiltered list, so iPad and Mac keep every row.
        #expect(rows.contains("orderedCustomisableDestinations(for: layout)"))
    }

    // MARK: - T-6221: the one-visible-row floor is measured over the rows the phone draws

    /// **T-6221.** With Today hidden, hiding All Tasks used to be allowed because Calendar and
    /// Notes — fixed tabs on the phone, never rows of its Tasks index — kept the floor "satisfied",
    /// and the index was left with no view rows. Measured over the compact rows it is refused;
    /// measured over the default (every primary row, the Mac's and iPad's sidebar) it still goes.
    @Test func theCompactFloorRefusesHidingTheLastOfTodayAndAllTasks() {
        let store = CadenceSidebarLayoutPreferenceStore.self
        let todayHidden = CadenceSidebarLayoutPreferenceStore.Layout(order: [], hidden: [.today])
        let compactFloor = CadenceCompactTab.honouredSidebarRows(CadenceSidebarLayout.primaryDestinations)
        #expect(compactFloor == [.today, .allTasks])

        #expect(store.hidden(setting: .allTasks, visible: false, in: todayHidden, floor: compactFloor) == nil)
        // The index the refusal protects still has a view row.
        #expect(!CadenceCompactTab.tasksIndexDestinations(hidden: todayHidden.hidden).isEmpty)

        // Regular width is unchanged: Calendar and Notes are rows there, so the toggle is allowed.
        #expect(store.hidden(setting: .allTasks, visible: false, in: todayHidden) == [.today, .allTasks])
        // And a row the phone ignores still toggles freely under the compact floor.
        #expect(store.hidden(setting: .calendar, visible: false, in: todayHidden, floor: compactFloor) == [.today, .calendar])
    }

    @Test func theSettingsCardMeasuresTheFloorOverTheCompactRowsOnlyAtCompactWidth() throws {
        let source = CadenceSourceScan.codeOnly(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSidebarLayoutSettingsSection.swift")
        )
        let section = try #require(
            CadenceSourceScan.declarationBody("struct iOSSidebarLayoutSettingsSection", in: source)
        )
        let floor = try #require(CadenceSourceScan.declarationBody("private var floorRows:", in: section))
        #expect(floor.contains("horizontalSizeClass == .compact"))
        #expect(floor.contains("CadenceCompactTab.honouredSidebarRows(CadenceSidebarLayout.primaryDestinations)"))

        let toggle = try #require(CadenceSourceScan.functionBody(named: "setVisibility", in: section))
        #expect(toggle.contains("floor: floorRows"), "the toggle no longer hands the store the width's floor")
    }
}
