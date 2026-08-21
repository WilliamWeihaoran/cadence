import Foundation
import Testing
@testable import Cadence

/// The mobile Notes header collapsed from three stacked rows into one: the title, and the tab
/// strip right-aligned beside it. That only works while the labels stay short, so the width budget
/// is asserted rather than eyeballed — and it got tighter, not looser, when the title stopped being
/// the constant word "Notes" and became the note's date.
@MainActor
struct MobileNotesTabLabelTests {

    /// Measured against the narrowest supported phone (390pt). The title is now a date, and its
    /// widest reading is a week range (`Aug 17–23`, ~80pt at 15pt bold) rather than the ~52pt
    /// "Notes" this budget was first set against; each tab is its label at 13pt semibold plus 12pt
    /// of padding with a 44pt floor. Six characters per label is what still fits.
    @Test func everyShortLabelFitsBesideTheTitleOnOneRow() {
        for tab in CadenceMobileNotesTab.allCases {
            #expect(tab.shortLabel.count <= CadenceMobileNotesTab.shortLabelCharacterBudget)
            #expect(!tab.shortLabel.isEmpty)
        }
    }

    /// Shortening two labels must not make two tabs read the same.
    @Test func shortLabelsAreDistinct() {
        let labels = CadenceMobileNotesTab.allCases.map(\.shortLabel)
        #expect(Set(labels).count == labels.count)
    }

    /// The two labels that were shortened, named explicitly: this is the assertion that fails if
    /// someone "restores" the long spellings and quietly reintroduces the clipping.
    @Test func theTwoLongLabelsAreTheShortenedOnes() {
        #expect(CadenceMobileNotesTab.events.shortLabel == "Events")
        #expect(CadenceMobileNotesTab.notepad.shortLabel == "Pad")
    }

    /// The dated tabs name a *kind*, not a moment.
    ///
    /// They read "Today" and "Week" while both notes were pinned to the current day and there was
    /// nothing else they could be showing. The header has a date picker now, so a tab lit up as
    /// "Today" could sit beside a title reading "Aug 13" — the header disagreeing with itself.
    @Test func theDatedTabsNameTheKindRatherThanTheMoment() {
        #expect(CadenceMobileNotesTab.today.shortLabel == "Daily")
        #expect(CadenceMobileNotesTab.week.shortLabel == "Weekly")
        for label in CadenceMobileNotesTab.allCases.map(\.shortLabel) {
            #expect(label != "Today")
            #expect(label != "Week")
        }
    }

    /// Renaming a *label* must not touch the persisted raw value behind it. `NoteKind.meeting` is
    /// stored in `Note.kindRaw`, and there is no `SchemaMigrationPlan` — changing it would strand
    /// every existing event note on every synced device.
    @Test func persistedNoteKindRawValuesAreUnchanged() {
        #expect(NoteKind.meeting.rawValue == "meeting")
        #expect(NoteKind.daily.rawValue == "daily")
        #expect(NoteKind.weekly.rawValue == "weekly")
        #expect(NoteKind.permanent.rawValue == "permanent")
    }

    /// Three of the four tabs are a single standing note; Event Notes is a list, and has no core
    /// note behind it. Round-tripping the three keeps the two enums in step.
    @Test func coreTabMappingRoundTrips() {
        #expect(CadenceMobileNotesTab.events.coreTab == nil)
        for core in CadenceCoreNoteTab.allCases {
            let tab = CadenceMobileNotesTab(coreTab: core)
            #expect(tab.coreTab == core)
            #expect(core.shortLabel == tab.shortLabel)
        }
    }
}

/// The iPhone settings surface's top level is now a vertical list of every category, grouped under
/// quiet eyebrows, instead of a horizontally scrolling strip that clipped mid-word. The iPad rail
/// reads from the same declaration, so the invariants below are what keep the two presentations
/// from drifting into different groupings of the same destinations.
@MainActor
struct MobileSettingsLayoutTests {

    @Test func everyCategoryIsFiledInExactlyOneGroup() {
        let filed = CadenceMobileSettingsLayout.groups.flatMap(\.kinds)
        #expect(Set(filed).count == filed.count)
        #expect(filed == CadenceMobileSettingsLayout.categories)
    }

    /// Every category, all reachable by scrolling down a single list — the brief this list was
    /// built for asked for all of them reachable without scrolling sideways, so the count is
    /// derived from the shared enum rather than typed in. It used to be a literal `12`, which
    /// meant the count and the exclusion list could only ever agree by coincidence.
    ///
    /// A second, literal assertion sat under this one and read `13` — it had to be edited again the
    /// moment `.coverage` was deleted, which is the maintenance cost the derived form exists to
    /// avoid. `onlyTheTwoDesktopShellCategoriesAreExcluded` below does the strong half by set
    /// equality, so the literal was buying nothing that the pair of them did not already say.
    @Test func mobileOffersEveryCategoryItDoesNotDeliberatelyExclude() {
        let expected = CadenceSettingsCategoryKind.allCases.count - CadenceMobileSettingsLayout.desktopOnly.count
        #expect(CadenceMobileSettingsLayout.categories.count == expected)
        // Non-vacuity: a derived count either side of an empty enum would agree at zero.
        #expect(expected > 8)
    }

    /// The categories mobile deliberately does not offer, and the only two it may omit.
    ///
    /// This test used to assert `!mobile.contains(.reminders)` alongside these, which is how the
    /// bug it encoded survived: Apple Reminders were unreachable from iOS Settings, and the suite
    /// asserted that was correct. EventKit reminders are fully available on iOS and
    /// `NSRemindersFullAccessUsageDescription` already shipped in the app's `Info.plist`; nothing
    /// about the platform justified the omission.
    @Test func onlyTheTwoDesktopShellCategoriesAreExcluded() {
        let mobile = Set(CadenceMobileSettingsLayout.categories)
        #expect(CadenceMobileSettingsLayout.desktopOnly == [.sidebar, .account])
        #expect(mobile.isDisjoint(with: CadenceMobileSettingsLayout.desktopOnly))
        // The strong half: not "these two are absent" but "nothing else is". A category dropped
        // from `groups` fails here even if nobody remembered to add an assertion for it.
        #expect(mobile == Set(CadenceSettingsCategoryKind.allCases).subtracting(CadenceMobileSettingsLayout.desktopOnly))
    }

    /// The bug this suite is being rewritten around, pinned on its own so a regression names
    /// itself. Reminders is the one integration on iOS whose settings screen is the *whole*
    /// surface — there is no iOS Inbox showing reminders — so if it falls out of the category
    /// list there is no other way to connect Apple Reminders on iPhone or iPad at all.
    @Test func remindersIsReachableFromMobileSettings() {
        #expect(CadenceMobileSettingsLayout.categories.contains(.reminders))
        #expect(!CadenceMobileSettingsLayout.desktopOnly.contains(.reminders))

        let systemGroup = CadenceMobileSettingsLayout.groups.first { $0.title == "System" }
        #expect(systemGroup?.kinds.contains(.reminders) == true)
        // Beside Calendar, not filed under App or Content: both are separately-authorized
        // EventKit stores the app reads, and they should read as the same kind of thing.
        #expect(systemGroup?.kinds.contains(.calendar) == true)
    }

    @Test func groupsHaveDistinctNonEmptyTitlesAndAreNeverEmpty() {
        let titles = CadenceMobileSettingsLayout.groups.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(CadenceMobileSettingsLayout.groups.allSatisfy { !$0.kinds.isEmpty })
    }

    /// Every row in the list draws a title and a glyph, so neither may be blank.
    @Test func everyCategoryHasATitleAndAGlyph() {
        for kind in CadenceMobileSettingsLayout.categories {
            #expect(!kind.title.isEmpty)
            #expect(!kind.icon.isEmpty)
        }
    }
}
