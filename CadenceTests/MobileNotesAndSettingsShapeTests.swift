import Foundation
import Testing
@testable import Cadence

/// The mobile Notes header collapsed from three stacked rows into one: back control, the constant
/// word "Notes", and the tab strip right-aligned on the same row. That only works while the labels
/// stay short, so the width budget is asserted rather than eyeballed.
@MainActor
struct MobileNotesTabLabelTests {

    /// Measured against the narrowest supported phone (402pt): back control + title + horizontal
    /// padding costs roughly 90pt, and each tab is its label at 13pt semibold plus 24pt of padding
    /// with a 44pt floor. Six characters per label keeps all four tabs inside what is left.
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
