import Foundation
import Testing
@testable import Cadence

/// The mobile Notes header collapsed from three stacked rows into one: the title, and the tab
/// strip right-aligned beside it. That only works while the labels stay short, so the width budget
/// is asserted rather than eyeballed — and it got tighter, not looser, when the title stopped being
/// the constant word "Notes" and became the note's date.
///
/// **T-3086 added the other half.** The budget is the *phone's*, and the strip drew the phone's
/// abbreviations on every host — including a 646pt iPad Notes pane with hundreds of points going
/// spare. `CadenceNotesTabVocabulary` now carries both readings, the order both platforms draw them
/// in, and the measured width that selects between them; what is pinned below is that the four
/// words are the Mac's four words, that the order is the Mac's order, and that the regular-width
/// path reads `label` while the compact one reads `shortLabel`.
@MainActor
struct MobileNotesTabLabelTests {

    /// Measured against the narrowest supported phone (390pt). The title is now a date, and its
    /// widest reading is a week range (`Aug 17–23`, ~80pt at 15pt bold) rather than the ~52pt
    /// "Notes" this budget was first set against; each tab is its label at 13pt semibold plus 12pt
    /// of padding with a 44pt floor. Six characters per label is what still fits.
    @Test func everyShortLabelFitsBesideTheTitleOnOneRow() {
        for tab in CadenceNotesTabVocabulary.allCases {
            #expect(tab.shortLabel.count <= CadenceNotesTabVocabulary.shortLabelCharacterBudget)
            #expect(!tab.shortLabel.isEmpty)
        }
    }

    /// Shortening two labels must not make two tabs read the same.
    @Test func shortLabelsAreDistinct() {
        let labels = CadenceNotesTabVocabulary.allCases.map(\.shortLabel)
        #expect(Set(labels).count == labels.count)
    }

    /// The two labels that were shortened, named explicitly: this is the assertion that fails if
    /// someone "restores" the long spellings and quietly reintroduces the clipping.
    @Test func theTwoLongLabelsAreTheShortenedOnes() {
        #expect(CadenceNotesTabVocabulary.events.shortLabel == "Events")
        #expect(CadenceNotesTabVocabulary.notepad.shortLabel == "Pad")
    }

    /// The dated tabs name a *kind*, not a moment.
    ///
    /// They read "Today" and "Week" while both notes were pinned to the current day and there was
    /// nothing else they could be showing. The header has a date picker now, so a tab lit up as
    /// "Today" could sit beside a title reading "Aug 13" — the header disagreeing with itself.
    @Test func theDatedTabsNameTheKindRatherThanTheMoment() {
        #expect(CadenceNotesTabVocabulary.today.shortLabel == "Daily")
        #expect(CadenceNotesTabVocabulary.week.shortLabel == "Weekly")
        for label in CadenceNotesTabVocabulary.allCases.map(\.shortLabel) {
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
        #expect(CadenceNotesTabVocabulary.events.coreTab == nil)
        for core in CadenceCoreNoteTab.allCases {
            let tab = CadenceNotesTabVocabulary(coreTab: core)
            #expect(tab.coreTab == core)
            #expect(core.noteKind == tab.noteKind)
        }
    }

    /// The four words in full, and they are macOS's: `NotesView.NotesPage.title` spelled these as
    /// its own literals, which is how two of the four came to differ between the platforms.
    @Test func theFullLabelsAreTheFourWordsTheMacNotesPageUses() {
        #expect(CadenceNotesTabVocabulary.today.label == "Daily")
        #expect(CadenceNotesTabVocabulary.week.label == "Weekly")
        #expect(CadenceNotesTabVocabulary.notepad.label == "Notepad")
        #expect(CadenceNotesTabVocabulary.events.label == "Event Notes")
    }

    /// The Mac's own third spelling: the heading over each of its four list columns, which differed
    /// from its own tab strip on two of the four. iOS draws no column heading, so this is read by
    /// macOS alone — and is pinned here because it is the copy most likely to drift next.
    @Test func theColumnTitlesAreTheHeadingsTheMacNotesListsDraw() {
        #expect(CadenceNotesTabVocabulary.today.columnTitle == "Daily Notes")
        #expect(CadenceNotesTabVocabulary.week.columnTitle == "Weekly Notes")
        #expect(CadenceNotesTabVocabulary.notepad.columnTitle == "Notepad")
        #expect(CadenceNotesTabVocabulary.events.columnTitle == "Event Notes")
    }

    /// **The order, and the half of T-3086 that moves tap targets.** Mobile ran `today, week,
    /// events, notepad` against the Mac's `daily, weekly, notepad, meeting` — the last two
    /// transposed, so Notepad was third on one platform and fourth on the other.
    @Test func theNotesTabOrderIsTheMacsOrder() {
        #expect(
            CadenceNotesTabVocabulary.allCases.map(\.noteKind) == [.daily, .weekly, .permanent, .meeting]
        )
        #expect(CadenceNotesTabVocabulary.allCases.count == 4)
    }

    /// The same order, read off the Mac rather than restated. `Cadence/macOS/Views/NotesView.swift`
    /// is behind `#if os(macOS)` but is a file this target can read, and its `NotesPage` is still
    /// the declaration mobile was moved to agree with.
    @Test func theMacNotesPageStillDeclaresTheOrderMobileWasMovedTo() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/NotesView.swift")
        )
        let body = try #require(CadenceSourceScan.declarationBody("enum NotesPage", in: source))
        let cases = CadenceSourceScan.captures(#"\bcase\s+(daily|weekly|notepad|meeting)\b"#, in: body)
            .map(\.text)
        #expect(cases == ["daily", "weekly", "notepad", "meeting"])
    }

    /// **Which label a surface draws is a width, not a platform.**
    ///
    /// The two live hosts are the numbers in the middle: the iPad's Notes pane is 646pt at its
    /// narrowest (an 11" iPad in portrait, 834pt less the 188pt shell sidebar) and reads the full
    /// words; Today's Notes inspector is regular width too and bottoms out at
    /// `CadenceTodayLayoutSupport.inspectorPaneMinWidth`, where the full-label strip alone overruns
    /// the row — so it keeps the abbreviations.
    @Test func theRegularWidthPathDrawsFullLabelsAndTheCompactOneDrawsAbbreviations() {
        let regular = { CadenceNotesTabVocabulary.usesFullLabels(isRegularWidth: true, headerWidth: $0) }
        let compact = { CadenceNotesTabVocabulary.usesFullLabels(isRegularWidth: false, headerWidth: $0) }

        #expect(regular(646))
        #expect(regular(CadenceNotesTabVocabulary.fullLabelMinimumHeaderWidth))
        #expect(!regular(CadenceNotesTabVocabulary.fullLabelMinimumHeaderWidth - 1))
        #expect(!regular(CadenceTodayLayoutSupport.inspectorPaneMinWidth))

        // The phone is never the full-label case, however wide it claims to be.
        #expect(!compact(646))
        #expect(!compact(390))

        // Unmeasured is the abbreviation, not the pushed row. See the doc on `usesFullLabels`.
        #expect(!regular(0))
    }

    /// The floor is below the narrowest regular-width host that clears it and above the arithmetic
    /// it was cut from, so neither end of the fork is decorative.
    @Test func theFullLabelWidthFloorSitsBetweenTheTwoHostsItSeparates() {
        #expect(CadenceNotesTabVocabulary.fullLabelMinimumHeaderWidth > CadenceTodayLayoutSupport.inspectorPaneMinWidth)
        #expect(CadenceNotesTabVocabulary.fullLabelMinimumHeaderWidth < 646)
    }

    /// **The iPad reads the Mac's words; the phone reads the abbreviations.** `Cadence/iOS/` is
    /// behind `#if os(iOS)` and invisible to this macOS-built target, so the one render site is
    /// read as source. This is the assertion that fails if the strip goes back to drawing
    /// `shortLabel` unconditionally and the iPad shows the phone's abbreviations again.
    @Test func theIPadNotesStripDrawsTheFullWordsRatherThanThePhonesAbbreviations() throws {
        let raw = try CadenceSourceScan.sourceFile("Cadence/iOS/iOSNotesView.swift")
        let source = CadenceSourceScan.strippingComments(raw)
        #expect(source != raw)
        #expect(source.count == raw.count)
        #expect(source.contains("iOSQuietTabButton("))

        #expect(
            CadenceSourceScan.matchCount(#"title:\s*usesFullLabels \? tab\.label : tab\.shortLabel"#, in: source) == 1,
            "the Notes tab strip no longer picks its label by width — the iPad is showing the phone's abbreviations"
        )
        #expect(
            CadenceSourceScan.matchCount(#"CadenceNotesTabVocabulary\.usesFullLabels\("#, in: source) == 1,
            "the width rule is no longer the shared one"
        )
        // The header reads the width the view already measures rather than measuring a second one
        // of its own — the same `hostWidth` that picks the one-column/two-column layout.
        #expect(
            CadenceSourceScan.matchCount(#"iOSNotesHeader\([^)]*hostWidth: hostWidth"#, in: source) == 1,
            "the Notes header is no longer handed the measured host width"
        )
        // The header's own stored property, as distinct from the view's `@State` of the same name.
        #expect(CadenceSourceScan.matchCount(#"\n    var hostWidth: CGFloat"#, in: source) == 1)
        #expect(CadenceSourceScan.matchCount(#"horizontalSizeClass"#, in: source) >= 1)
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
