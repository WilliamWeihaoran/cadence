import Foundation
import SwiftData
import Testing
@testable import Cadence

/// **T-490.** `CadenceChoiceRow` is the option type behind every popover picker on both platforms.
/// Its `id` defaulted to `AnyHashable(title)` with an optional override, and **32 of the 35 call
/// sites took the default** — so two options whose *displayed* titles happened to match collapsed
/// into one `ForEach` identity in `CadenceChoicePopoverList` and only one of them drew.
///
/// That is live copy, not a hypothetical: an unnamed area renders as "Untitled Area" and an unnamed
/// milestone as "Untitled Milestone", so two unnamed ones are two options with one title. An area
/// the user actually names "None" collides with the none row.
///
/// The fix derives `id` from `value` and **removes the parameter**, rather than making it
/// mandatory. `value` is already `Hashable`, it is already what `selection` is compared against,
/// and a picker offering two rows with the same `value` is broken at the binding before it is
/// broken at the identity — so the type can answer the question once instead of 35 authors
/// answering it each. Deriving it also makes identity survive a rename, which is what `ForEach`
/// identity is for.
@MainActor
struct CadenceChoiceRowIdentityTests {

    /// The collision itself. Two distinct values, one title, two rows.
    @Test func twoOptionsWithTheSameTitleAreStillTwoRows() {
        let first = CadenceChoiceRow(value: "a", title: "Untitled Area", color: Theme.dim)
        let second = CadenceChoiceRow(value: "b", title: "Untitled Area", color: Theme.dim)

        #expect(first.id != second.id)
        #expect(Set([first.id, second.id]).count == 2)
    }

    /// The other half, and the reason `value` is the right derivation rather than an index: a row
    /// whose title changes is the same row. An index-derived or title-derived identity either
    /// reshuffles on a rename or drops the row.
    @Test func aChoiceRowKeepsItsIdentityWhenOnlyItsTitleChanges() {
        let before = CadenceChoiceRow(value: 42, title: "Every day", color: Theme.dim)
        let after = CadenceChoiceRow(value: 42, title: "Daily", subtitle: "renamed", color: Theme.blue)

        #expect(before.id == after.id)
        #expect(before.id == AnyHashable(42))
    }

    /// The `value` types the app's 35 call sites actually use — `Int` minutes, `String` tags,
    /// `UUID?` goals and areas, and enum cases — each identifying itself.
    @Test func everyChoiceRowIdentityIsItsOwnValue() {
        let none = CadenceChoiceRow<UUID?>(value: nil, title: "None", color: Theme.dim)
        let goalID = UUID()
        let goal = CadenceChoiceRow<UUID?>(value: goalID, title: "None", color: Theme.dim)

        #expect(none.id == AnyHashable(UUID?.none))
        #expect(goal.id == AnyHashable(Optional(goalID)))
        #expect(none.id != goal.id)

        let noTime = CadenceChoiceRow(value: -1, title: "No time", color: Theme.dim)
        let midnight = CadenceChoiceRow(value: 0, title: "No time", color: Theme.dim)
        #expect(noTime.id != midnight.id)

        let low = CadenceChoiceRow(value: TaskPriority.low, title: "Flag", color: Theme.dim)
        let high = CadenceChoiceRow(value: TaskPriority.high, title: "Flag", color: Theme.dim)
        #expect(low.id != high.id)
    }

    /// The collision, reached through the app's own data rather than through hand-built rows: two
    /// unnamed areas both read "Untitled Area" out of `CadenceAreaPickerSupport`, which is what the
    /// iOS list editor's Area popover maps straight into `CadenceChoiceRow`.
    ///
    /// This is the pair of tickets meeting: [[T-488]] is what makes the two rows appear, and T-490
    /// is what keeps them two.
    @Test func twoUnnamedAreasAreTwoRowsInTheAreaPicker() throws {
        let modelContext = ModelContext(try CadenceModelContainerFactory.makeInMemoryContainer())
        let first = Area(name: "")
        let second = Area(name: "  ")
        modelContext.insert(first)
        modelContext.insert(second)

        let rows = CadenceAreaPickerSupport.items(
            from: [first, second],
            selectedID: nil,
            noneTitle: "None"
        ).map { item in
            CadenceChoiceRow(
                value: item.id?.uuidString ?? "none",
                title: item.title,
                systemImage: item.icon,
                color: item.tint
            )
        }

        #expect(rows.map(\.title) == ["None", "Untitled Area", "Untitled Area"])
        #expect(Set(rows.map(\.id)).count == 3)
    }
}
