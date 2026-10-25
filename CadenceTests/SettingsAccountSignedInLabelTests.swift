#if os(macOS)
import Foundation
import Testing
@testable import Cadence

/// [[T-6433]]: the Apple Account card's sign-in date names its year only outside the current year.
@MainActor
struct SettingsAccountSignedInLabelTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func sameYearSignInKeepsTheBareMonthAndDay() {
        #expect(SettingsAccountSection.signedInLabel(day(2026, 10, 20), relativeTo: day(2026, 10, 25)) == "Signed in Oct 20")
    }

    @Test func signInFromAnotherYearSpellsTheYear() {
        #expect(SettingsAccountSection.signedInLabel(day(2025, 10, 20), relativeTo: day(2026, 10, 25)) == "Signed in Oct 20, 2025")
    }
}
#endif
