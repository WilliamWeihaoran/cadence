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

    /// Twelve categories, all reachable by scrolling down a single list — the count is what the
    /// brief's "every one of the twelve reachable without scrolling sideways" is measured against.
    @Test func mobileOffersTwelveCategories() {
        #expect(CadenceMobileSettingsLayout.categories.count == 12)
    }

    /// The categories mobile deliberately does not offer: `sidebar` and `account` are macOS shell
    /// concerns, and `reminders` is macOS-only EventKit reminders.
    @Test func desktopOnlyCategoriesAreExcluded() {
        let mobile = Set(CadenceMobileSettingsLayout.categories)
        #expect(!mobile.contains(.sidebar))
        #expect(!mobile.contains(.reminders))
        #expect(!mobile.contains(.account))
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
