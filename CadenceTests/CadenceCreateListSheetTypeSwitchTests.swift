// macOS only: `CreateListSheet` is a macOS sheet.
#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// **[[T-7269]]: switching New List between Area and Project keeps the icon and colour you picked.**
///
/// The `TypeButton` action wrote the new type's `defaultIcon` / `defaultColor` unconditionally, so
/// a pick snapped back on every switch. The owner's call was option (2): a field still holding the
/// OLD type's default follows the type to the new default, and anything else is the user's pick
/// and survives. Each field is decided on its own.
struct CadenceCreateListSheetTypeSwitchTests {
    private typealias ListType = CreateListSheet.ListType

    /// Non-vacuity: the two types' defaults differ, or "moved to the new default" and "kept"
    /// would be the same assertion.
    @Test func theTwoTypesHaveDistinctDefaults() {
        #expect(ListType.area.defaultIcon != ListType.project.defaultIcon)
        #expect(ListType.area.defaultColor.lowercased() != ListType.project.defaultColor.lowercased())
    }

    @Test func untouchedDefaultsFollowTheType() {
        let toProject = ListType.identityAfterSwitch(
            from: .area, to: .project,
            icon: ListType.area.defaultIcon, color: ListType.area.defaultColor
        )
        #expect(toProject.icon == ListType.project.defaultIcon)
        #expect(toProject.color == ListType.project.defaultColor)

        let backToArea = ListType.identityAfterSwitch(
            from: .project, to: .area,
            icon: toProject.icon, color: toProject.color
        )
        #expect(backToArea.icon == ListType.area.defaultIcon)
        #expect(backToArea.color == ListType.area.defaultColor)
    }

    @Test func aPickedIconAndColourSurviveTheSwitch() {
        let picked = (icon: "star.fill", color: "#f472b6")
        #expect(picked.icon != ListType.area.defaultIcon && picked.icon != ListType.project.defaultIcon)
        for (old, new) in [(ListType.area, ListType.project), (.project, .area)] {
            let result = ListType.identityAfterSwitch(from: old, to: new, icon: picked.icon, color: picked.color)
            #expect(result.icon == picked.icon, "\(old) -> \(new) threw away the picked icon")
            #expect(result.color == picked.color, "\(old) -> \(new) threw away the picked colour")
        }
    }

    /// A colour pick does not pin the untouched icon, and an icon pick does not pin the colour.
    @Test func eachFieldIsDecidedOnItsOwn() {
        let colourPicked = ListType.identityAfterSwitch(
            from: .area, to: .project,
            icon: ListType.area.defaultIcon, color: "#f472b6"
        )
        #expect(colourPicked.icon == ListType.project.defaultIcon)
        #expect(colourPicked.color == "#f472b6")

        let iconPicked = ListType.identityAfterSwitch(
            from: .area, to: .project,
            icon: "star.fill", color: ListType.area.defaultColor
        )
        #expect(iconPicked.icon == "star.fill")
        #expect(iconPicked.color == ListType.project.defaultColor)
    }

    /// The sheet's button routes through the helper rather than writing the defaults itself.
    @Test func theTypeButtonActionReadsTheHelper() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/CreateListSheet.swift")
        )
        #expect(source.contains("ListType.identityAfterSwitch("))
        #expect(!source.contains("selectedIcon = type.defaultIcon"), "the switch overwrites the icon unconditionally again")
        #expect(!source.contains("selectedColor = type.defaultColor"), "the switch overwrites the colour unconditionally again")
    }
}
#endif
