// T-3244: compiled for macOS only. `CadenceTests` now also builds for an iOS destination, and
// this suite reaches macOS-only app types (or AppKit) that do not exist there. The gate preserves
// exactly the coverage this file had before; narrowing it so any cross-platform half runs on iOS
// too is follow-up, not part of making the target iOS-capable.
#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import Cadence

/// T-20: macOS Settings adopts the vocabulary iOS was rebuilt on in `775833d`, and the two
/// platforms stop keeping two of everything.
///
/// **Value assertions first, source scans only where nothing else can see.** Every type moved here
/// lives outside `#if`, so most of what this file checks is a real property read on a real value.
/// The scans that remain do the one job a value cannot: prove the *old* declaration is gone rather
/// than merely unused. `Cadence/iOS/` is entirely inside `#if os(iOS)` and this target builds for
/// macOS, so the iOS half has no symbols to reference at all — the helpers at the bottom follow
/// `SettingsCategoryReachTests`: exact per-file counts rather than "contains", comment-stripping
/// rather than allowlisting, and a non-vacuity test so a broken scan cannot make the absence
/// assertions pass by reading nothing.
@MainActor
struct SettingsSharedVocabularyTests {

    // MARK: - One row height, spelled once

    /// The one platform difference inside the shared field vocabulary, and the reason it is a
    /// property rather than a literal at four call sites: a finger is 44pt and a pointer is not.
    ///
    /// This target builds for macOS, so this is the desktop answer. The iOS answer is checked by
    /// the `#if` being present at all — see `theRowHeightIsAskedOfOnePlaceRatherThanRetyped`.
    @Test func theSharedRowHeightIsTheDesktopFigureOnDesktop() {
        #expect(CadenceSettingsRowMetrics.rowHeight == 34)
        #expect(CadenceSettingsRowMetrics.glyphSlot == 22)
        #expect(CadenceSettingsRowMetrics.glyphLabelSpacing == 9)
    }

    /// Nothing re-types the height. A second `44` or `34` in a settings row, a value button or an
    /// inset well is exactly how the two platforms came to disagree in the first place —
    /// `iOSSettingsMetrics.minimumTapTarget` was its own stored `44` beside `iOSEditorFieldRow`'s
    /// own literal `44` beside `iOSChoicePopoverList`'s own literal `44`.
    @Test func theRowHeightIsAskedOfOnePlaceRatherThanRetyped() throws {
        let metrics = try t20StrippingComments(t20SourceFile("Cadence/Shared/Components/CadenceFieldRows.swift"))
        #expect(metrics.contains("#if os(macOS)"), "the row height stopped being a per-platform answer")

        // The components that draw a row read the property; none of them types a number. Four in
        // the shared file since T-286: the field row, the info row, the inset well the titled
        // field now delegates to, and the notice row three Settings panes were each drawing by
        // hand.
        try t20ExpectOccurrences(
            of: "CadenceSettingsRowMetrics.rowHeight",
            at: [
                "Cadence/Shared/Components/CadenceFieldRows.swift": 4,
                "Cadence/Shared/Components/CadenceChoicePicker.swift": 1,
                "Cadence/iOS/iOSSettingsComponents.swift": 1
            ]
        )
    }

    // MARK: - One choice picker, not two

    /// The picker is a real value with real defaults, checked by reading them.
    ///
    /// **T-490 changed what `id` is derived from, and this test with it.** It used to read
    /// `AnyHashable("Comfort")` — the *title* — with an `id:` parameter to override when two
    /// options shared one, and 32 of the 35 call sites took the default. The parameter is gone and
    /// the identity is `value`; `CadenceChoiceRowIdentityTests` is where that rule is pinned.
    @Test func theSharedChoiceRowKeepsItsDefaultsAndValueDerivedIdentity() {
        let row = CadenceChoiceRow(value: 3, title: "Comfort", color: Theme.amber)
        #expect(row.id == AnyHashable(3))
        #expect(row.subtitle == nil)
        #expect(row.systemImage == nil)
        #expect(row.value == 3)

        // Two options sharing a title stay two rows without the call site being asked about it.
        let sameTitle = CadenceChoiceRow(value: 4, title: "Comfort", color: Theme.amber)
        #expect(sameTitle.id != row.id)
    }

    /// The trigger's touch floor is opt-in and off by default, so the rows that pair it with a
    /// second control keep their layout. A default of `rowHeight` would silently re-space them.
    @Test func theValueButtonsTouchFloorIsOptIn() {
        let bare = CadenceChoiceValueButton(title: "Tasks") {}
        #expect(bare.minHeight == 0)
        #expect(bare.color == Theme.text)

        let inARow = CadenceChoiceValueButton(
            title: "Tasks",
            minHeight: CadenceSettingsRowMetrics.rowHeight
        ) {}
        #expect(inARow.minHeight == CadenceSettingsRowMetrics.rowHeight)
    }

    /// The popover is a cap, not a height — the property that keeps a one-row picker one row tall.
    @Test func theFittedPopoverCarriesACapRatherThanAHeight() {
        let popover = CadenceFittedPopover { EmptyView() }
        #expect(popover.width == 230)
        #expect(popover.maxHeight == 380)
    }

    /// The four iOS names are typealiases now, not a second set of structs.
    ///
    /// This is the assertion that fails if someone "restores" the iOS copy: a file that declares
    /// `struct iOSChoicePopoverList` again satisfies every call site and every other test here,
    /// and puts the two platforms back on two components that agree only by hand.
    @Test func theIOSChoicePickerIsTypealiasesAndDeclaresNoStructOfItsOwn() throws {
        let source = try t20StrippingComments(t20SourceFile("Cadence/iOS/iOSChoicePicker.swift"))
        for name in ["iOSChoiceRow", "iOSChoicePopoverList", "iOSChoiceValueButton", "iOSFittedPopover"] {
            #expect(
                source.range(of: "struct \(name)\\b", options: .regularExpression) == nil,
                "iOSChoicePicker.swift declares a second \(name)"
            )
            #expect(
                source.range(of: "typealias \(name)\\b", options: .regularExpression) != nil,
                "iOSChoicePicker.swift no longer aliases \(name) to the shared type"
            )
        }
    }

    /// Same for the editor field vocabulary.
    @Test func theIOSFieldVocabularyIsTypealiasesAndDeclaresNoStructOfItsOwn() throws {
        let design = try t20StrippingComments(t20SourceFile("Cadence/iOS/iOSDesignSystem.swift"))
        for name in ["iOSEditorSection", "iOSEditorDivider", "iOSEditorInlineLabel", "iOSEditorFieldRow"] {
            #expect(
                design.range(of: "struct \(name)\\b", options: .regularExpression) == nil,
                "iOSDesignSystem.swift declares a second \(name)"
            )
            #expect(
                design.range(of: "typealias \(name)\\b", options: .regularExpression) != nil,
                "iOSDesignSystem.swift no longer aliases \(name) to the shared type"
            )
        }

        let components = try t20StrippingComments(t20SourceFile("Cadence/iOS/iOSSettingsComponents.swift"))
        for name in ["iOSRowDivider", "iOSSettingsField"] {
            #expect(
                components.range(of: "struct \(name)\\b", options: .regularExpression) == nil,
                "iOSSettingsComponents.swift declares a second \(name)"
            )
            #expect(
                components.range(of: "typealias \(name)\\b", options: .regularExpression) != nil,
                "iOSSettingsComponents.swift no longer aliases \(name) to the shared type"
            )
        }
    }

    // MARK: - One card, one inset per platform

    /// The card is one component with the inset as a parameter. Both figures are read rather than
    /// asserted from memory, because `CadenceSettingsTemplatesCardLayoutTests` models both chrome
    /// chains down to the point and would silently stop describing the app if either moved.
    @Test func oneCardCarriesBothInsetsAsAParameter() {
        #expect(CadenceSettingsCard { EmptyView() }.padding == 14)
        #expect(CadenceSettingsCard(padding: 16) { EmptyView() }.padding == 16)
    }

    /// iOS's card is that parameter and nothing else — the 16 the layout test models.
    @Test func theIOSCardIsTheSharedCardAtSixteen() throws {
        try t20ExpectOccurrences(
            of: "CadenceSettingsCard(padding: 16)",
            at: ["Cadence/iOS/iOSSettingsComponents.swift": 1]
        )
    }

    // MARK: - The header stopped repeating the first row

    /// The badge is gone from both the shared file and the macOS wrapper, and no caller survives.
    ///
    /// Deleted rather than left unused: a component that still compiles and nothing draws is how
    /// the page-header `subtitle` parameter survived long enough to need removing three times.
    @Test func theSettingsStatusBadgeAndItsWrapperAreGone() throws {
        try t20ExpectNoLiveMention(of: "CadenceSettingsStatusBadge")
        try t20ExpectNoLiveMention(of: "SettingsStatusBadge")
    }

    /// The header takes a title and a tint, and has no trailing slot to put a second copy of a fact
    /// into. Constructing it here is the check — a generic `TrailingContent` parameter would not
    /// compile against this call.
    @Test func theSettingsHeaderHasNoTrailingSlot() {
        let header = CadenceSettingsHeader(title: "Calendar", tint: Theme.purple)
        #expect(header.title == "Calendar")
        #expect(header.tint == Theme.purple)

        let detail = SettingsDetailHeader(category: .calendar)
        #expect(detail.category == .calendar)
    }

    /// The nine-case `switch` behind the badge went with it, rather than being left computing
    /// values nothing draws. `StoreBackupManager` is the tell: `SettingsView` read it for exactly
    /// one thing, the "N backups" pill, and listing backups is not free.
    @Test func theDetailHeaderNoLongerComputesAnyStatusValues() throws {
        try t20ExpectOccurrences(
            of: "StoreBackupManager",
            at: ["Cadence/macOS/Views/SettingsView.swift": 0]
        )
        try t20ExpectOccurrences(
            of: "TagSupport.uniqueBySlug",
            at: ["Cadence/macOS/Views/SettingsView.swift": 0]
        )
        try t20ExpectOccurrences(
            of: "NoteTemplateLibrary.overrides",
            at: ["Cadence/macOS/Views/SettingsView.swift": 0]
        )
        // Non-vacuity in the direction that matters: the same scan finds two of the three names
        // alive in the panes that do use them, so a zero above is a statement about
        // `SettingsView.swift` rather than about a scan that read nothing.
        //
        // This line was `#expect(!StoreBackupManager.listBackups().isEmpty || true)`, which is an
        // assertion no value can fail — `x || true` is `true` — so the non-vacuity claim the
        // comment made was not being checked at all. (`NoteTemplateLibrary.overrides` is spelled
        // nowhere under `Cadence/`, so it has no live witness to offer; its zero above is an
        // absence claim and nothing more.)
        let dataSafety = try t20StrippingComments(
            t20SourceFile("Cadence/macOS/Views/SettingsDataSafetySection.swift")
        )
        #expect(
            dataSafety.contains("StoreBackupManager"),
            "the scan no longer finds StoreBackupManager anywhere, so the zero above proves nothing"
        )
        let tagsPane = try t20StrippingComments(
            t20SourceFile("Cadence/macOS/Views/SettingsTagsSection.swift")
        )
        #expect(
            tagsPane.contains("TagSupport.uniqueBySlug"),
            "the scan no longer finds TagSupport.uniqueBySlug anywhere, so the zero above proves nothing"
        )
        try t20ExpectOccurrences(
            of: "SettingsDetailHeader",
            at: ["Cadence/macOS/Views/SettingsView.swift": 1]
        )
    }

    // MARK: - macOS Settings draws no AppKit controls of its own any more

    /// The work-hours window was the last `Picker(.menu)` in Settings — AppKit's bezel and AppKit's
    /// accent, which no amount of `Theme` around it changes.
    ///
    /// **The two halves an absence sweep needs, and this one had neither.** The walk was counted
    /// nowhere, and the needle had no witness: every file in this sweep's own corpus is required
    /// *not* to contain it, so nothing in the corpus can show the spelling still matches anything.
    /// Measured — blinding the needle to `.pickerStyleZZZ(` left this test, and the whole suite,
    /// green. The needle is now one constant read by both the sweep and a positive witness outside
    /// the corpus, so a typo in it fails the witness instead of silently emptying the sweep.
    @Test func noSettingsPaneStillDrawsAMenuPicker() throws {
        var scanned = 0
        for path in try t20SwiftFiles(under: "Cadence/macOS/Views") where path.contains("/Settings") {
            scanned += 1
            let code = try t20StrippingComments(t20SourceFile(path))
            #expect(
                !code.contains(t20NativePickerNeedle),
                "\(path) still styles a native Picker"
            )
        }
        #expect(scanned >= 15, "scanned only \(scanned) settings panes")

        try t20ExpectTheNativePickerNeedleStillMatchesSomething()
    }

    /// **T-1087: the same rule, on the platform that had no sweep at all.**
    ///
    /// The macOS corpus above is one platform, and [[T-1082]] landed its preview sheet twice —
    /// macOS and iOS — with the mode choice drawn as `Picker(.segmented)` in both. Only the Mac's
    /// was caught. The phone's was found by reading, and
    /// `CadenceArchiveImportEntryPointTests.neitherArchiveImportSurfaceDrawsANativePicker` is the
    /// two-file plug that went in with it; this is the rule the plug stands in for.
    ///
    /// **Does the rule apply on iOS at all?** T-20's argument is AppKit's: a `Picker` on the Mac
    /// draws AppKit's bezel and AppKit's accent and takes no palette colour. UIKit's segmented
    /// control is not that object, so the argument does not transfer by itself — but the app has
    /// already made the same decision on its own terms, in `CadenceChoicePicker`'s doc comment:
    /// `CadenceChoiceRow` and its siblings were written as "shared custom replacements for native
    /// SwiftUI `Picker`/`.pickerStyle(.segmented)` controls **on iOS**". The vocabulary was iOS's
    /// first and macOS adopted it, which is what T-20 was. So the rule is the phone's rule, and the
    /// Mac's sweep is the one that arrived second.
    ///
    /// **Measured before widening, which is the judgement the ticket asked for:** stripped of
    /// comments, `Cadence/iOS/` and `Cadence/Shared/` hold **zero** `.pickerStyle(` and **zero**
    /// `Picker(` between them. There is no `.wheel` picker to exempt — the app's date entry is
    /// `CadenceDatePicker`, which styles a `DatePicker` through `.datePickerStyle(` and is a
    /// different needle. So a bare ban costs nothing today and pins a surface that is already
    /// clean; the day a deliberate `.wheel` picker is wanted, this is where to argue for it.
    ///
    /// **`Cadence/Shared/` is in the corpus and macOS's sweep does not cover it**, which is the
    /// second hole the same shape: a `Picker` added to a shared component draws on both platforms
    /// and would have been caught by neither sweep.
    @Test func noMobileOrSharedSurfaceDrawsANativePicker() throws {
        var scanned = 0
        for directory in ["Cadence/iOS", "Cadence/Shared"] {
            for path in try t20SwiftFiles(under: directory) {
                scanned += 1
                let code = try t20StrippingComments(t20SourceFile(path))
                #expect(
                    !code.contains(t20NativePickerNeedle),
                    "\(path) styles a native Picker; iOS's own vocabulary is CadenceChoicePicker"
                )
                #expect(
                    t20LiveNativePickerCount(in: code) == 0,
                    "\(path) draws a native Picker; iOS's own vocabulary is CadenceChoicePicker"
                )
            }
        }
        #expect(scanned >= 250, "scanned only \(scanned) mobile and shared files")

        try t20ExpectTheNativePickerNeedleStillMatchesSomething()

        // The second needle needs its own witness, and it needs to *discriminate*: the corpus is
        // full of `CadenceDatePicker(`, `iOSSearchScopePicker(` and `.photosPicker(`, none of which
        // is a native `Picker`, and a needle that matched those would make the zeros above
        // unreachable rather than true.
        #expect(t20LiveNativePickerCount(in: "Picker(selection: $mode) { }") == 1)
        #expect(t20LiveNativePickerCount(in: "Picker (\"Mode\", selection: $mode)") == 1)
        for read in [
            "CadenceDatePicker(selection: $startDate)",
            "iOSSearchScopePicker(scope: $scope)",
            "CadenceAccentPalettePicker(selectedHex: $hex)",
            ".photosPicker(isPresented: $isPicking)",
            "SwiftUI.Picker(selection: $mode) { }"
        ] {
            #expect(t20LiveNativePickerCount(in: read) == 0, "over-matched \(read)")
        }
    }

    /// Both work-hours halves present the same control. macOS reads the shared type by name; iOS
    /// reads it through the typealias, which the two tests above pin to the shared declaration.
    @Test func bothWorkHoursPickersPresentTheSharedChoiceList() throws {
        try t20ExpectCallSites(
            of: "CadenceChoicePopoverList",
            at: ["Cadence/macOS/Views/SettingsCalendarWorkHoursSection.swift": 1]
        )
        try t20ExpectCallSites(
            of: "iOSChoicePopoverList",
            at: ["Cadence/iOS/iOSCalendarSettingsSection.swift": 1]
        )
        try t20ExpectNoLiveMention(of: "SettingsWorkHoursTimePicker")
    }

    /// The default-page setting is a value row over the same list, and the stale-value repair it
    /// depended on still holds.
    @Test func theDefaultPageSettingIsAValueRowOverEveryPage() throws {
        #expect(ListDetailPage.resolved("Planning") == .tasks)
        #expect(ListDetailPage.allCases.count == 5)

        try t20ExpectCallSites(
            of: "CadenceFieldRow",
            at: ["Cadence/macOS/Views/SettingsSectionViews.swift": 1]
        )
        try t20ExpectCallSites(
            of: "CadenceChoicePopoverList",
            at: ["Cadence/macOS/Views/SettingsSectionViews.swift": 1]
        )
        // The pill row it replaced is gone: no settings pane fills a control with a saturated
        // accent to say "selected" any more.
        let navigation = try t20StrippingComments(t20SourceFile("Cadence/macOS/Views/SettingsSectionViews.swift"))
        #expect(!navigation.contains("selectedPage == page ? Theme.blue : Theme.surfaceElevated"))
    }

    // MARK: - The hairline paints the palette colour and nothing else
    //
    // `Divider().background(Theme.borderSubtle)` paints the palette colour *under* the system
    // separator, so the line is neither `borderSubtle` nor the same from pane to pane. iOS
    // replaced it with `iOSRowDivider`; macOS Settings was still spelling it in eight places.
    //
    // **T-553: `noSettingsPaneStillPaintsUnderTheSystemSeparator` lived here and is gone.** It
    // swept the same corpus for the *one-line* spelling of the same hairline, which is a strict
    // subset of what `noSettingsPanePaintsUnderTheSystemSeparatorAtAnyLineBreak` below already
    // catches — and it had none of that test's guards: it counted its walk nowhere, and it had no
    // detector test, so a typo in its needle emptied it silently. Two sweeps for one rule, one of
    // them the weaker, is a second place for the rule to rot. Its positive half was the only thing
    // it held alone, so that moved down to the surviving sweep rather than being deleted with it.

    /// The one inset well, read by the pane that used to keep a private copy of it.
    @Test func theAIPaneReadsTheSharedInsetWell() throws {
        try t20ExpectCallSites(
            of: "CadenceSettingsField",
            at: ["Cadence/macOS/Views/SettingsSectionViews.swift": 2]
        )
        let ai = try t20StrippingComments(t20SourceFile("Cadence/macOS/Views/SettingsSectionViews.swift"))
        #expect(
            ai.range(of: "func settingsField", options: .regularExpression) == nil,
            "the private inset-well copy is back"
        )
    }

    // MARK: - Non-vacuity

    /// The scan itself works. Without this, a wrong repository root or a broken enumerator makes
    /// every absence assertion above pass by reading nothing at all.
    @Test func theSourceScanIsNotVacuousInSettingsSharedVocabulary() throws {
        let files = try t20SwiftFiles(under: "Cadence")
        #expect(files.count > 400, "walked \(files.count) files")
        #expect(files.contains("Cadence/Shared/Components/CadenceChoicePicker.swift"))
        #expect(files.contains("Cadence/Shared/Components/CadenceFieldRows.swift"))

        let settingsPanes = try t20SwiftFiles(under: "Cadence/macOS/Views").filter { $0.contains("/Settings") }
        #expect(settingsPanes.count >= 12, "found only \(settingsPanes.count) macOS settings panes")

        // A symbol that is definitely live must be *found* by the same scan the absence
        // assertions use, or those assertions mean nothing.
        var liveHits = 0
        for path in files {
            let code = try t20StrippingComments(t20SourceFile(path))
            if code.range(of: "(?<![A-Za-z0-9_])CadenceSettingsRowMetrics(?![A-Za-z0-9_])", options: .regularExpression) != nil {
                liveHits += 1
            }
        }
        #expect(liveHits >= 4, "the sweep found CadenceSettingsRowMetrics in only \(liveHits) files")
    }
}

// MARK: - Source-reading helpers

private func t20ExpectCallSites(
    of name: String,
    at callSites: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in callSites {
        let code = try t20StrippingComments(t20SourceFile(path))
        let actual = code.components(separatedBy: "\(name)(").count - 1
        #expect(
            actual == expected,
            "\(path) calls \(name) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func t20ExpectOccurrences(
    of text: String,
    at files: [String: Int],
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    for (path, expected) in files {
        let code = try t20StrippingComments(t20SourceFile(path))
        let actual = code.components(separatedBy: text).count - 1
        #expect(
            actual == expected,
            "\(path) contains \(text) \(actual) times, expected \(expected)",
            sourceLocation: sourceLocation
        )
    }
}

private func t20ExpectNoLiveMention(
    of name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let pattern = "(?<![A-Za-z0-9_])\(name)(?![A-Za-z0-9_])"
    for path in try t20SwiftFiles(under: "Cadence") {
        let code = try t20StrippingComments(t20SourceFile(path))
        #expect(
            code.range(of: pattern, options: .regularExpression) == nil,
            "\(path) still refers to the retired \(name)",
            sourceLocation: sourceLocation
        )
    }
}

private func t20RepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// The one needle both native-picker sweeps read (T-20, T-1087).
///
/// It is a shared constant rather than a literal in each test because an absence sweep whose corpus
/// is required *not* to contain the needle cannot tell "no offenders" from "no matches ever" — the
/// exact failure T-20 measured, where blinding the needle to `.pickerStyleZZZ(` left the whole suite
/// green. One constant means one typo fails the shared witness below instead of silently emptying
/// two sweeps.
private let t20NativePickerNeedle = ".pickerStyle("

/// Live uses of SwiftUI's own `Picker`, and not of the app's controls whose names end in `Picker`.
///
/// The `(?<![A-Za-z0-9_.])` guard is the whole job: `CadenceDatePicker(`, `iOSSearchScopePicker(`
/// and `.photosPicker(` are all substring matches for `Picker(` and none of them is the control
/// under the rule. A sweep that counted those would be asserting a zero that can never be reached.
private func t20LiveNativePickerCount(in code: String) -> Int {
    let pattern = "(?<![A-Za-z0-9_.])Picker\\s*\\("
    let range = NSRange(code.startIndex..., in: code)
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return -1 }
    return expression.numberOfMatches(in: code, range: range)
}

/// The witness that both needles still match what they hunt.
///
/// It was a **file** — `CreateGoalSheet.swift`, which held the app's one remaining styled `Picker`
/// and sat outside every corpus above (macOS Settings, `Cadence/iOS`, `Cadence/Shared`), which is
/// what made it usable as the witness for all of them. The note here said: if it goes, re-anchor
/// on whatever replaced it or drop the rule; do not leave a needle nothing can match. [[T-2079]]
/// deleted that sheet with the rest of the goal write surface, and **measured on the tree it left
/// behind there is no live styled `Picker` anywhere under `Cadence/`** — the two remaining
/// `.pickerStyle(` occurrences, in `iOSChoicePicker.swift` and
/// `SettingsCalendarWorkHoursSection.swift`, are both inside comments describing what was
/// replaced. So there is nothing to re-anchor on.
///
/// Dropping the rule would be wrong — it is what keeps the settings panes off native pickers — so
/// the witness becomes a pair of literals. That still catches the failure this whole mechanism was
/// built for and measured against: blinding the needle to `.pickerStyleZZZ(` emptied the sweep and
/// left the suite green, and a typo now fails here. What it no longer proves is that the *reader*
/// opened a real file, which the corpus walk's own `scanned >= 15` floor carries instead.
private func t20ExpectTheNativePickerNeedleStillMatchesSomething(
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    // `.pickerStyle(` is the needle the sweeps grep for; it must match a styled picker and must
    // not match a bare one, or the sweep's zero is a zero nothing could have reached.
    #expect(
        try t20StrippingComments(".pickerStyle(.menu)").contains(t20NativePickerNeedle),
        "the needle no longer matches a styled Picker at all; it has been mistyped",
        sourceLocation: sourceLocation
    )
    #expect(
        try !t20StrippingComments("Picker(\"Kind\", selection: $kind)").contains(t20NativePickerNeedle),
        "the needle matches a bare Picker, so the sweep would fire on an unstyled one",
        sourceLocation: sourceLocation
    )

    // The second needle is `t20LiveNativePickerCount`'s own, and it is a different question: it
    // counts SwiftUI's `Picker(` while skipping the app's controls whose names merely end in
    // `Picker`. Both halves of that guard are witnessed.
    #expect(
        t20LiveNativePickerCount(in: "Picker(\"Kind\", selection: $kind) { }") == 1,
        "the live-Picker counter no longer counts a native Picker; it has drifted from the needle",
        sourceLocation: sourceLocation
    )
    #expect(
        t20LiveNativePickerCount(in: "CadenceDatePicker(selection: $date)") == 0,
        "the live-Picker counter counts one of the app's own *Picker controls",
        sourceLocation: sourceLocation
    )
}

private func t20SwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = t20RepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
        return []
    }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func t20SourceFile(_ relativePath: String) throws -> String {
    try String(contentsOf: t20RepositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
}

private func t20StrippingComments(_ source: String) throws -> String {
    // T-1269/T-1270: one pass per pattern, in CadenceSourceScan, on the guarded
    // `(?<!:)//` that the slashes in a URL cannot trigger.
    return CadenceSourceScan.strippingComments(source)
}

// MARK: - T-286: the seven panes T-20 left outside the vocabulary

/// **T-20 converted four macOS Settings panes and gave five others the hairline only.** Seven were
/// left entirely outside the shared row vocabulary, and the remaining work was recorded *inside the
/// Done entry for T-20* — which is where remaining work goes to be forgotten. It was: Tags (493
/// lines, carrying its own two spellings of the inset well), Templates (323, carrying a third),
/// Support Views (427), Reminders (151), Sync (85), Notifications (78) and Appearance (24). None of
/// them mentioned `CadenceFieldSection`, `CadenceFieldRow` or `CadenceSettingsField` at all, so a
/// settings row was still two heights and two spellings depending on which category you opened.
///
/// **Two of the seven did not fit the field row, and were not made to.**
///
/// - `SettingsSupportViews.swift` is a row *library*, not a pane: drag sources, drop targets,
///   inline editors, 28–30pt tinted identity tiles and paired destructive buttons. `CadenceFieldRow`
///   models a glyph in a fixed 22pt slot, a quiet label and one trailing control; passing those rows
///   through it as `content` would be the shared component in name only. What converted there is
///   the chrome that really was re-typed — the rename field's private well, and a "Color" heading
///   spelled two ways in one file.
/// - Notifications and Sync have no fields and no headings; they are single *status* cards. Rather
///   than bend them into a field row, the row they were each hand-drawing became one:
///   `CadenceSettingsNoticeRow`, which Reminders' access card and the tag catalog's empty row also
///   read. Four hand-written copies of one line, now five call sites of one component.
///
/// **Not in scope:** `SettingsListManagementSections.swift`. It is not one of the seven — T-20 gave
/// it the hairline, and it is the pane with the most `CadenceRowDivider` call sites already. Its two
/// stragglers, spelled across two lines and so invisible to T-20's one-line check, went in T-449;
/// the count `noSettingsPanePaintsUnderTheSystemSeparatorAtAnyLineBreak` pins for it is seven, not
/// five.
@MainActor
struct SettingsSevenPaneVocabularyTests {

    /// Every one of the seven now reads the shared titled group, the shared status row, the shared
    /// inset well, or — for the row library — is recorded above as resisting on purpose.
    ///
    /// Exact counts, not "contains": the failure this guards is one call site of several reverting,
    /// which a presence check cannot see. It is the same lesson `expectCallSites` in
    /// `CadenceSharedBoardChromeTests` was written for.
    @Test func theSevenPanesReadTheSharedFieldVocabulary() throws {
        try t20ExpectCallSites(
            of: "CadenceFieldSection",
            at: [
                "Cadence/macOS/Views/SettingsAppearanceSection.swift": 1,
                "Cadence/macOS/Views/SettingsNotificationsSection.swift": 1,
                "Cadence/macOS/Views/SettingsSyncSection.swift": 1,
                "Cadence/macOS/Views/SettingsRemindersSection.swift": 2,
                "Cadence/macOS/Views/SettingsTemplatesSection.swift": 2,
                "Cadence/macOS/Views/SettingsTagsSection.swift": 4
            ]
        )

        try t20ExpectCallSites(
            of: "CadenceSettingsNoticeRow",
            at: [
                "Cadence/macOS/Views/SettingsNotificationsSection.swift": 2,
                // 1 before T-600(b). The second is the Reminder Lists card's empty state, which
                // was a private one-line `summaryRow` — a glyph and "No open reminders." with
                // nothing after it — twenty lines under this pane's own access verdict drawn on
                // the shared row. It is the same shape (a glyph, what the state is, one sentence
                // of why), so the count went up because a near-copy was removed, not because a
                // row was added.
                "Cadence/macOS/Views/SettingsRemindersSection.swift": 2,
                // 1 before [[T-2000]]. The second is the mirroring-activity row — "Last import
                // 3:25 PM · Last export 3:45 PM · No errors" — which is a *history* verdict
                // beside the pane's existing *capability* verdict, not a second opinion on the
                // same question. It reached for the shared row unprompted, which is the outcome
                // this count exists to keep true.
                "Cadence/macOS/Views/SettingsSyncSection.swift": 2,
                "Cadence/macOS/Views/SettingsTagsSection.swift": 1,
                // T-450: the sidebar-tab editor's row, which T-286 left private.
                "Cadence/macOS/Views/SettingsSupportViews.swift": 1,
                // The row lives in the shared file; the declaration is not a call site.
                "Cadence/Shared/Components/CadenceFieldRows.swift": 0
            ]
        )

        try t20ExpectCallSites(
            of: "CadenceSettingsField",
            at: ["Cadence/macOS/Views/SettingsTemplatesSection.swift": 3]
        )
    }

    /// **T-450: the fifth private settings row is gone, and the shared one grew an optional glyph.**
    ///
    /// T-286 left `SidebarTabEditorSheet.settingsPanelRow` alone on the argument that reaching
    /// `CadenceSettingsNoticeRow` meant inventing a state glyph for a sheet that reports no state.
    /// That argument was sound about the glyph and wrong about the outcome: the private row had
    /// already drifted off the shared spelling in the way copies do, carrying an 11pt subtitle where
    /// the other four say 12 — and where the identity block twenty lines above it in the same sheet
    /// says 12. So the glyph became optional and the copy went.
    ///
    /// The sweep is over every Swift file in the app, not just this pane: the failure it guards is
    /// the helper being moved rather than removed.
    @Test func theFifthPrivateSettingsRowIsRetiredRatherThanRelocated() throws {
        let privateRow = try CadenceScanInstrument(
            "private settings panel row helper",
            fires: "private func settingsPanelRow<A: View>(title: String, subtitle: String) -> some View { EmptyView() }",
            andNotOn: "CadenceSettingsNoticeRow(title: title, detail: subtitle) { accessory() }",
            by: { source in
                CadenceSourceScan.matchCount(
                    "(?<![A-Za-z0-9_])settingsPanelRow(?![A-Za-z0-9_])",
                    in: source
                ) > 0
            }
        )

        let hits = try privateRow.sweep(
            try t20SwiftFiles(under: "Cadence"),
            atLeast: 400,
            including: "Cadence/macOS/Views/SettingsSupportViews.swift",
            read: { CadenceSourceScan.codeOnly(try t20SourceFile($0)) }
        )

        #expect(hits.isEmpty, "settingsPanelRow still declared in \(hits)")
    }

    /// **[[T-9627]].** The sidebar tab editor's header is the tab's glyph and name. A "Set this
    /// tab's color and visibility." subtitle described the sheet the user is already on, directly
    /// above the Color grid and the Visible switch it named.
    @Test func theSidebarTabEditorHeaderIsTheNameAlone() throws {
        // Comments stripped, literals kept: the sentence this guards against IS a literal.
        let code = CadenceSourceScan.strippingComments(
            try t20SourceFile("Cadence/macOS/Views/SettingsSupportViews.swift")
        )
        let sheet = try #require(
            CadenceSourceScan.declarationBody("struct SidebarTabEditorSheet: View", in: code),
            "SidebarTabEditorSheet moved"
        )
        #expect(sheet.contains("Text(destination.label)"), "non-vacuity: the header no longer names the tab")
        #expect(sheet.contains("SectionEyebrowLabel(text: \"Color\")"), "non-vacuity: the Color section moved")
        #expect(!sheet.contains("Set this tab"), "the header describes the sheet again")
    }

    /// **[[T-9625]].** Every Mac Settings switch is drawn one way: regular size, system accent. The
    /// sidebar tab editor's alone was `.controlSize(.small)` in `Theme.blue`.
    @Test func everyMacSettingsSwitchIsDrawnOneWay() throws {
        let files = [
            "Cadence/macOS/Views/SettingsSupportViews.swift",
            "Cadence/macOS/Views/SettingsNotificationsSection.swift",
            "Cadence/macOS/Views/SettingsListManagementSections.swift",
        ]
        var switches = 0
        for path in files {
            let code = CadenceSourceScan.strippingComments(try t20SourceFile(path))
            let lines = code.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(".toggleStyle(.switch)") {
                switches += 1
                // The modifiers on the same chain: the lines around the style up to the next blank
                // or closing brace.
                let window = lines[max(0, index - 4)...min(lines.count - 1, index + 4)].joined(separator: "\n")
                #expect(!window.contains(".controlSize("), "\(path):\(index + 1) sizes its switch")
                #expect(!window.contains(".tint("), "\(path):\(index + 1) tints its switch")
            }
        }
        // Non-vacuity: the tab editor's, the reminders' and each calendar's switch.
        #expect(switches == 3, "expected 3 Mac Settings switches, found \(switches)")
    }

    /// The glyph is **absent** on a row that reports no verdict, not blank.
    ///
    /// `systemImage: String = ""` would have satisfied the call-site count above while drawing an
    /// empty `Image` in the leading slot and pushing the title off the edge every other row starts
    /// on. So the declaration has to be optional and the body has to branch on it — the two facts a
    /// call-site count cannot see, and the only two the sheet's appearance depends on.
    @Test func theSharedNoticeRowDrawsNoGlyphWhenItIsGivenNone() throws {
        let code = CadenceSourceScan.codeOnly(
            try t20SourceFile("Cadence/Shared/Components/CadenceFieldRows.swift")
        )

        #expect(CadenceSourceScan.matchCount("var systemImage: String\\?", in: code) == 1)
        #expect(CadenceSourceScan.matchCount("if let systemImage \\{", in: code) == 1)

        // And the sheet's row is the one that omits it: no `systemImage:` argument anywhere in
        // that file, which is where a re-invented glyph would have to appear.
        try t20ExpectOccurrences(
            of: "systemImage",
            at: ["Cadence/macOS/Views/SettingsSupportViews.swift": 0]
        )
    }

    /// **The four private inset wells are deleted, not merely unused.**
    ///
    /// `SettingsAISection.settingsField` went in T-20 and its two `SettingsTagsSection` siblings did
    /// not, which is how the count in `CadenceSettingsField`'s own comment ("replaces six
    /// near-copies") came to describe a tree with three still in it — plus a fourth,
    /// `TemplateEditorField`, that comment never counted.
    @Test func noSettingsPaneKeepsAPrivateInsetWell() throws {
        try t20ExpectNoLiveMention(of: "TemplateEditorField")

        // The wells that stayed are helpers over the shared modifier rather than second
        // rectangles: placeholder-only fields have no eyebrow for the titled component to draw.
        // The needle is `cadenceSettingsWell(` and not `cadenceSettingsWell()`: the modifier took
        // an `insetsContent:` parameter in T-442, for content that draws its own text inset — the
        // note-template body is a `MarkdownEditor`, an `NSScrollView` that would otherwise float
        // inside a 12pt gutter of `surfaceElevated`. The counts are unchanged, which is the claim:
        // one rectangle with a knob, not a second rectangle.
        try t20ExpectOccurrences(
            of: "cadenceSettingsWell(",
            at: [
                "Cadence/macOS/Views/SettingsTagsSection.swift": 2,
                "Cadence/macOS/Views/SettingsSupportViews.swift": 1,
                // The titled field draws the same rectangle by delegating to it, which is what
                // makes a bare well and a labelled one one component rather than two.
                "Cadence/Shared/Components/CadenceFieldRows.swift": 2
            ]
        )

        // And the rectangle itself is gone, not just its call sites. The tell the three wells
        // shared was `.stroke` rather than `.strokeBorder` — it straddles the edge, so a well is a
        // point wider than it measures, which is how three "identical" wells were three different
        // widths — over a radius each had chosen for itself: 8, 8 and 7 against the shared
        // `Theme.radiusControl`.
        let tags = t286RemovingWhitespace(
            try t20StrippingComments(t20SourceFile("Cadence/macOS/Views/SettingsTagsSection.swift"))
        )
        #expect(tags.contains("structSettingsTagsSection"), "non-vacuity: still the tags pane")
        #expect(
            !tags.contains("RoundedRectangle(cornerRadius:8)"),
            "the tags pane draws its own radius-8 well again"
        )

        let context = t286RemovingWhitespace(
            try t20StrippingComments(t20SourceFile("Cadence/macOS/Views/SettingsSupportViews.swift"))
        )
        #expect(context.contains("structContextSettingsRow"), "non-vacuity: still the row library")
        #expect(
            !context.contains("RoundedRectangle(cornerRadius:7).stroke(Theme.borderSubtle)"),
            "the context row draws its own radius-7 well again"
        )
    }

    /// **The hairline sweep, at any line break — and now the only one.**
    ///
    /// The T-20 original looked for the literal one-line `Divider().background(Theme.borderSubtle)`,
    /// and three call sites walked straight past it by being spelled across two lines — one of them
    /// a *vertical* column separator in the note templates card, which is the same painted-under
    /// hairline turned ninety degrees. Removing whitespace before the check is what makes the two
    /// spellings one, which is why that original was deleted as a strict subset of this (T-553) and
    /// why its positive half is now asserted here.
    @Test func noSettingsPanePaintsUnderTheSystemSeparatorAtAnyLineBreak() throws {
        var scanned = 0
        var offenders: [String] = []

        for path in try t20SwiftFiles(under: "Cadence/macOS/Views") where path.contains("/Settings") {
            // The sweep has no hole any more. `SettingsListManagementSections.swift` carried the
            // last two-line survivor and was skipped by name (T-449); its two calendar-row
            // hairlines now read `CadenceRowDivider`, so every settings pane is scanned.
            scanned += 1
            let code = t286RemovingWhitespace(try t20StrippingComments(t20SourceFile(path)))
            if code.contains("Divider().background(Theme.borderSubtle") {
                offenders.append(path)
            }
        }

        #expect(scanned >= 15, "scanned only \(scanned) settings panes")
        #expect(offenders.isEmpty, "painted-under hairline(s) in: \(offenders.sorted().joined(separator: ", "))")

        // The positive half, inherited from the one-line sweep this replaced: the hairlines those
        // panes do draw read the shared component, at exact counts. An absence sweep whose corpus
        // had simply stopped drawing hairlines at all would be just as empty.
        try t20ExpectCallSites(
            of: "CadenceRowDivider",
            at: [
                "Cadence/macOS/Views/SettingsAboutSection.swift": 2,
                // 5 before T-449; the two calendar-row hairlines that were a two-line
                // `Divider().background(Theme.borderSubtle)` are the other two. The eighth is
                // T-557's dormant-links card, which separates the inactive lists still holding a
                // calendar link — it reached for the shared component unprompted, which is the
                // outcome this count exists to keep true rather than a number to chase.
                "Cadence/macOS/Views/SettingsListManagementSections.swift": 8,
                // 1 before T-575; the second is the footer hairline in the Mac's typed-phrase
                // reset confirmation, which is in this file and therefore in this sweep. The
                // third is [[T-1532]]'s "Other Backup Folders" list, which separates the backups
                // directories beside store locations the app has left behind. The fourth is
                // [[T-1680]]'s "Other Cadence Data Folders" list, which separates the *store*
                // folders the app is not using — the recovery store a failed launch wrote, and
                // the earlier store locations. The fifth is [[T-3045]]'s "Unrestored Store Files"
                // list, which separates the folders a restore moved aside and Cadence retained.
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 5,
                "Cadence/macOS/Views/SettingsSectionViews.swift": 4
            ]
        )
    }

    /// The detector against text that is not the repository, so the sweep above is not one typo
    /// away from matching nothing. Both spellings must be caught and the shared component must not.
    @Test func theHairlineDetectorCatchesBothSpellingsAndNotTheSharedOne() {
        #expect(t286RemovingWhitespace("""
        Divider()
            .background(Theme.borderSubtle)
            .padding(.leading, 24)
        """).contains("Divider().background(Theme.borderSubtle"))

        #expect(t286RemovingWhitespace("Divider().background(Theme.borderSubtle)")
            .contains("Divider().background(Theme.borderSubtle"))

        #expect(!t286RemovingWhitespace("CadenceRowDivider(leadingInset: 24)")
            .contains("Divider().background(Theme.borderSubtle"))

        // A bare `Divider()` is not the bug — the bug is painting the palette colour under the
        // system separator, which leaves the line neither colour.
        #expect(!t286RemovingWhitespace("Divider()\n    .padding(.vertical, 2)")
            .contains("Divider().background(Theme.borderSubtle"))
    }

    /// The shared divider gained an axis rather than the vertical call site keeping `Divider()`.
    @Test func theSharedHairlineDrawsBothAxes() throws {
        let rows = try t20StrippingComments(t20SourceFile("Cadence/Shared/Components/CadenceFieldRows.swift"))
        #expect(rows.contains("struct CadenceRowDivider"), "non-vacuity: still the divider's file")
        #expect(rows.contains("var axis: Axis = .horizontal"), "the hairline lost its axis")
        #expect(rows.contains("case .vertical"), "the hairline draws only one axis again")

        try t20ExpectCallSites(
            of: "CadenceRowDivider",
            at: [
                "Cadence/macOS/Views/SettingsTemplatesSection.swift": 2,
                "Cadence/macOS/Views/SettingsRemindersSection.swift": 1
            ]
        )
        #expect(
            try t20StrippingComments(t20SourceFile("Cadence/macOS/Views/SettingsTemplatesSection.swift"))
                .contains("CadenceRowDivider(axis: .vertical)"),
            "the templates card's column separator is back to a system Divider"
        )
    }

    /// **The `SettingsSectionLabel` + `SettingsCard` pair is the sixth spelling of the titled
    /// group**, and none of the seven writes it any more. The pair itself stays: three panes T-20
    /// converted for other reasons still use it, and this ticket is about the seven.
    @Test func noneOfTheSevenStacksTheOlderTitledGroupSpelling() throws {
        let seven = [
            "Cadence/macOS/Views/SettingsTagsSection.swift",
            "Cadence/macOS/Views/SettingsTemplatesSection.swift",
            "Cadence/macOS/Views/SettingsSupportViews.swift",
            "Cadence/macOS/Views/SettingsRemindersSection.swift",
            "Cadence/macOS/Views/SettingsSyncSection.swift",
            "Cadence/macOS/Views/SettingsNotificationsSection.swift",
            "Cadence/macOS/Views/SettingsAppearanceSection.swift"
        ]

        for path in seven {
            let code = try t20StrippingComments(t20SourceFile(path))
            #expect(code.count > 400, "non-vacuity: \(path) read as \(code.count) characters")
            #expect(!code.contains("SettingsSectionLabel("), "\(path) still stacks its own eyebrow")
            #expect(!code.contains("SettingsCard {"), "\(path) still stacks its own card")
        }

        // Still live where T-20 left it, so the assertions above are about these seven files and
        // not about the component having quietly disappeared.
        try t20ExpectCallSites(
            of: "SettingsSectionLabel",
            at: ["Cadence/macOS/Views/SettingsAboutSection.swift": 2]
        )
    }

    /// The row library that resisted says so in its own file, so the next reader does not re-file
    /// it as an oversight. Recorded in the source rather than only in `docs/TODO.md`, because the
    /// argument is about the rows declared here and belongs beside them.
    @Test func theRowLibraryRecordsWhyItStaysOutsideTheFieldRow() throws {
        let raw = try t20SourceFile("Cadence/macOS/Views/SettingsSupportViews.swift")
        #expect(raw.contains("struct ContextSettingsRow"), "non-vacuity: still the row library")
        #expect(raw.contains("T-286"), "the row library does not say which decision left it alone")
        #expect(raw.contains("CadenceFieldRow"), "the note does not name the component it declines")

        // The two things there that were genuinely re-typed did convert.
        try t20ExpectCallSites(
            of: "SectionEyebrowLabel",
            at: ["Cadence/macOS/Views/SettingsSupportViews.swift": 3]
        )
    }

    /// [[T-6972]]: the completed/archived list row truncates a long name instead of wrapping it,
    /// and its status capsule and both buttons keep their natural width. Before this nothing in
    /// the row had a line limit, so a long name wrapped and squeezed "Completed" and "Restore"
    /// into broken lines with it.
    @Test func theListLifecycleRowTruncatesTheNameAndHoldsItsControls() throws {
        let source = CadenceSourceScan.strippingComments(try t20SourceFile("Cadence/macOS/Views/SettingsSupportViews.swift"))
        let row = try #require(CadenceSourceScan.declarationBody("struct ListLifecycleRow: View", in: source))
        let flat = t286RemovingWhitespace(row)

        #expect(flat.contains("Text(title).font(.system(size:13,weight:.semibold)).foregroundStyle(Theme.text).lineLimit(1)"),
                "the list name can wrap again")
        #expect(flat.contains("Text(subtitle).font(.system(size:11)).foregroundStyle(Theme.dim).lineLimit(1)"),
                "the subtitle can wrap again")
        #expect(flat.contains("Text(statusLabel).font(.system(size:10,weight:.semibold))") , "non-vacuity: still the status capsule")
        // The capsule: a fixed size behind a one-line limit. The two buttons ([[T-9461]]) are the
        // shared `CadenceActionButton`, whose label is one line already, each held at its width.
        #expect(CadenceSourceScan.matchCount("\\.lineLimit\\(1\\)\\.fixedSize\\(\\)", in: flat) == 1,
                "the status capsule can be squeezed into wrapping again")
        #expect(flat.contains("CadenceActionButton(title:primaryLabel,role:.secondary,size:.compact,tint:Theme.text,action:onPrimary).fixedSize()"),
                "the primary button can be squeezed into wrapping again")
        #expect(flat.contains("CadenceActionButton(title:\"Delete\",role:.primary,size:.compact,tint:Theme.red,action:onDelete).fixedSize()"),
                "Delete can be squeezed into wrapping again")
    }

    /// [[T-9631]]: the phone's inactive-list row puts its two buttons under the name when the one
    /// line does not fit. On a 393pt iPhone the card hands the row ~329pt and the one-line row's
    /// fixed parts take ~246 of it, leaving ~83 for the name and its ~76pt status chip -- so every
    /// row truncated its name or its buttons. One line where it fits (the iPad's card), and the
    /// `iOSInboxRemindersSection.accessRow` shape -- actions under the text -- where it does not.
    @Test func thePhoneListLifecycleRowDropsItsButtonsUnderTheNameWhenTheLineDoesNotFit() throws {
        let source = CadenceSourceScan.strippingComments(try t20SourceFile("Cadence/iOS/iOSSettingsTemplateAndListSections.swift"))
        let row = try #require(CadenceSourceScan.declarationBody("private struct iOSListLifecycleSettingsRow: View", in: source))
        let flat = t286RemovingWhitespace(row)
        #expect(flat.contains("iOSMetaChip(label:statusLabel,color:statusTint)"), "non-vacuity: still the lifecycle row")

        let fits = try #require(flat.range(of: "ViewThatFits(in:.horizontal){"),
                                "the row is one line at every width again")
        let oneLine = "HStack(alignment:.center,spacing:iOSSettingsMetrics.glyphLabelSpacing){iconTilelabelsSpacer(minLength:10)primaryButtondeleteButton}"
        let twoLine = "HStack(alignment:.top,spacing:iOSSettingsMetrics.glyphLabelSpacing){iconTileVStack(alignment:.leading,spacing:8){labelsHStack(spacing:10){primaryButtondeleteButton}}Spacer(minLength:0)}"
        let first = try #require(flat.range(of: oneLine), "the one-line arrangement is gone")
        let second = try #require(flat.range(of: twoLine), "the buttons no longer drop under the name")
        // `ViewThatFits` takes the first child that fits, so the one line must be asked first.
        #expect(fits.upperBound <= first.lowerBound && first.upperBound <= second.lowerBound,
                "the fallback is tried before the one-line row")
        // Each button is drawn once per arrangement, from one declaration, so the two cannot drift.
        #expect(flat.components(separatedBy: "iOSActionButton(").count - 1 == 2)
    }

    /// [[T-9291]]: the archived context row is [[T-6972]]'s row's sibling — the same Restore/Delete
    /// pair under Settings → Contexts — and it had none of that fix, so a long context name wrapped
    /// and squeezed both buttons. The name truncates on one line and the two buttons hold their
    /// width; the active context row's name is one line too.
    @Test func theContextRowsTruncateTheNameAndHoldTheirControls() throws {
        let source = CadenceSourceScan.strippingComments(try t20SourceFile("Cadence/macOS/Views/SettingsSupportViews.swift"))
        let archived = t286RemovingWhitespace(
            try #require(CadenceSourceScan.declarationBody("struct ArchivedContextRow: View", in: source))
        )
        #expect(archived.contains("Text(context.name).font(.system(size:13)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)"),
                "the archived context's name can wrap again")
        // [[T-9461]]: the shared action button (its label is one line), held at its width.
        #expect(archived.contains("CadenceActionButton(title:CadenceListVocabularyCopy.unarchiveActionTitle,role:.secondary,size:.compact,tint:Theme.text,action:onRestore).fixedSize()"),
                "Unarchive can be squeezed into wrapping again")
        #expect(archived.contains("CadenceActionButton(title:\"Delete\",role:.primary,size:.compact,tint:Theme.red,action:onDelete).fixedSize()"),
                "Delete can be squeezed into wrapping again")

        let active = t286RemovingWhitespace(
            try #require(CadenceSourceScan.declarationBody("struct ContextSettingsRow: View", in: source))
        )
        #expect(active.contains(".font(.system(size:13)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail)"),
                "the active context's name can wrap again")
    }
}

/// Removes every whitespace character, so a modifier chain reads the same however it is wrapped.
private func t286RemovingWhitespace(_ source: String) -> String {
    source.filter { !$0.isWhitespace }
}


/// **[[T-9622]].** A Mac Settings card's hairline starts where its rows' text does.
///
/// `CadenceRowDivider` takes a leading inset "so it starts at the text rather than cutting across a
/// leading glyph", and every Settings card typed that inset as a literal: 42 under four row shapes
/// whose text starts at 40, 42 and 46, 44 under calendar rows whose name starts at 24 (20pt into
/// the text; Reminders' identical rows one pane over drew 24) and at 32. Each row now names its
/// leading geometry, lays itself out from those names, and the card reads the row's sum.
@MainActor
struct SettingsRowDividerInsetTests {
    private static let rowLayouts: [(path: String, declaration: String, needles: [String])] = [
        ("Cadence/macOS/Views/SettingsSupportViews.swift", "struct ContextSettingsRow: View",
         ["HStack(spacing: Self.glyphLabelSpacing)", ".frame(width: Self.glyphSide, height: Self.glyphSide)", ".padding(.horizontal, Self.horizontalPadding)"]),
        ("Cadence/macOS/Views/SettingsSupportViews.swift", "struct ArchivedContextRow: View",
         ["HStack(spacing: Self.glyphLabelSpacing)", ".frame(width: Self.glyphSide, height: Self.glyphSide)"]),
        ("Cadence/macOS/Views/SettingsSupportViews.swift", "struct SidebarTabSettingsRow: View",
         ["HStack(spacing: Self.glyphLabelSpacing)", ".frame(width: Self.glyphSide, height: Self.glyphSide)", ".padding(.horizontal, Self.horizontalPadding)"]),
        ("Cadence/macOS/Views/SettingsSupportViews.swift", "struct ListLifecycleRow: View",
         ["HStack(spacing: Self.glyphLabelSpacing)", ".frame(width: Self.glyphSide, height: Self.glyphSide)"]),
        ("Cadence/macOS/Views/SettingsListManagementSections.swift", "struct SettingsCalendarRow: View",
         ["HStack(alignment: .top, spacing: Self.dotLabelSpacing)", ".frame(width: Self.dotSide, height: Self.dotSide)"]),
        ("Cadence/macOS/Views/SettingsListManagementSections.swift", "struct SettingsMissingCalendarLinkRow: View",
         ["spacing: SettingsCalendarLinkRowMetrics.glyphLabelSpacing", ".frame(width: SettingsCalendarLinkRowMetrics.glyphColumnWidth)"]),
        ("Cadence/macOS/Views/SettingsListManagementSections.swift", "struct SettingsDormantCalendarLinkRow: View",
         ["spacing: SettingsCalendarLinkRowMetrics.glyphLabelSpacing", ".frame(width: SettingsCalendarLinkRowMetrics.glyphColumnWidth)"]),
        ("Cadence/macOS/Views/SettingsRemindersSection.swift", "struct SettingsRemindersListRow: View",
         ["HStack(spacing: Self.dotLabelSpacing)", ".frame(width: Self.dotSide, height: Self.dotSide)"]),
    ] + [
        "struct UnmanagedBackupDirectoryRow: View",
        "struct UnmanagedStoreDirectoryRow: View",
        "struct RetainedUnrestoredOriginalsRow: View",
        "struct StoreBackupRow: View",
    ].map { declaration in
        ("Cadence/macOS/Views/SettingsDataSafetySection.swift", declaration, [
            "HStack(spacing: SettingsStoreDirectoryRowMetrics.glyphLabelSpacing)",
            ".frame(width: SettingsStoreDirectoryRowMetrics.glyphSide, height: SettingsStoreDirectoryRowMetrics.glyphSide)",
            ".padding(.horizontal, SettingsStoreDirectoryRowMetrics.horizontalPadding)",
        ])
    }

    /// No Settings pane types a hairline inset; each reads the inset its rows declare.
    @Test func noSettingsHairlineTypesItsInset() throws {
        var named = 0
        var literal: [String] = []
        for path in try CadenceSourceScan.swiftFiles(under: "Cadence/macOS/Views")
        where (path as NSString).lastPathComponent.hasPrefix("Settings") {
            let code = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            named += CadenceSourceScan.matchCount("CadenceRowDivider\\(leadingInset: [A-Za-z][A-Za-z]*\\.dividerLeadingInset\\)", in: code)
            if CadenceSourceScan.matchCount("CadenceRowDivider\\(leadingInset: [0-9]", in: code) > 0 {
                literal.append(path)
            }
        }
        #expect(named >= 13, "non-vacuity: only \(named) named hairline insets in the Settings panes")
        #expect(literal.isEmpty, "a Settings hairline types its inset again: \(literal)")
    }

    /// Each row lays itself out from the names its inset is summed from, so the two cannot part.
    @Test func eachRowLaysOutFromTheNamesItsInsetSums() throws {
        for layout in Self.rowLayouts {
            let source = try CadenceSourceScan.sourceFile(layout.path)
            let body = try #require(
                CadenceSourceScan.declarationBody(layout.declaration, in: source),
                "\(layout.declaration) moved out of \(layout.path)"
            )
            for needle in layout.needles {
                #expect(body.contains(needle), "\(layout.declaration) lays out with a literal instead of `\(needle)`")
            }
        }
    }

    /// The sums themselves, read off the real types where they are visible to this target.
    @Test func theInsetsAreTheRowsOwnLeadingGeometry() {
        #expect(ContextSettingsRow.dividerLeadingInset
                == ContextSettingsRow.horizontalPadding + ContextSettingsRow.glyphSide + ContextSettingsRow.glyphLabelSpacing)
        #expect(SidebarTabSettingsRow.dividerLeadingInset
                == SidebarTabSettingsRow.horizontalPadding + SidebarTabSettingsRow.glyphSide + SidebarTabSettingsRow.glyphLabelSpacing)
        #expect(ArchivedContextRow.dividerLeadingInset == ArchivedContextRow.glyphSide + ArchivedContextRow.glyphLabelSpacing)
        #expect(ListLifecycleRow.dividerLeadingInset == ListLifecycleRow.glyphSide + ListLifecycleRow.glyphLabelSpacing)
        #expect(SettingsStoreDirectoryRowMetrics.dividerLeadingInset
                == SettingsStoreDirectoryRowMetrics.horizontalPadding + SettingsStoreDirectoryRowMetrics.glyphSide
                    + SettingsStoreDirectoryRowMetrics.glyphLabelSpacing)
        #expect(SettingsCalendarLinkRowMetrics.dividerLeadingInset
                == SettingsCalendarLinkRowMetrics.glyphColumnWidth + SettingsCalendarLinkRowMetrics.glyphLabelSpacing)
        // The relation the defect broke: the sidebar row's larger glyph and wider spacing put its
        // text further in than the contexts row whose inset it borrowed.
        #expect(SidebarTabSettingsRow.dividerLeadingInset > ContextSettingsRow.dividerLeadingInset)
    }

    /// **[[T-9771]]. The iOS half.** iOS's settings cards start their hairline at
    /// `iOSSettingsMetrics.rowTextInset`, the glyph slot plus the glyph-label spacing, and every row
    /// over that hairline has to draw its tile in that slot. The Sidebar Rows card drew a 34pt tile
    /// (text at 46, hairline at 44), and Settings > Calendar's broken- and dormant-link cards drew a
    /// 34pt tile over a hairline typed as 24 -- which ran under the tile itself. The iOS types are
    /// not compiled into this target, so the relation is read from source.
    @Test func theIOSRowsOverTheTextInsetHairlineDrawTheirTileInTheGlyphSlot() throws {
        let rows: [(path: String, declaration: String)] = [
            ("Cadence/iOS/iOSCalendarSettingsSection.swift", "struct iOSMissingCalendarLinkRow: View"),
            ("Cadence/iOS/iOSCalendarSettingsSection.swift", "struct iOSDormantCalendarLinkRow: View"),
            ("Cadence/iOS/iOSSidebarLayoutSettingsSection.swift", "private func rowContent("),
        ]
        for row in rows {
            let source = try CadenceSourceScan.sourceFile(row.path)
            let body = t286RemovingWhitespace(try #require(
                CadenceSourceScan.declarationBody(row.declaration, in: source),
                "\(row.declaration) moved out of \(row.path)"
            ))
            #expect(body.contains("HStackLayout(alignment:.top,spacing:iOSSettingsMetrics.glyphLabelSpacing)")
                    || body.contains("HStack(spacing:iOSSettingsMetrics.glyphLabelSpacing)"),
                    "\(row.declaration) no longer spaces its tile from its text by the inset's spacing")
            #expect(body.contains("size:iOSSettingsMetrics.glyphSlot,"),
                    "\(row.declaration) draws its tile at a size the hairline's inset is not summed from")
        }

        // The link cards' hairlines read the summed inset; the calendar list's own 24 (a 12pt dot
        // plus 12) is a different row and stays.
        let calendar = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSCalendarSettingsSection.swift")
        )
        for card in ["private var dormantLinksCard: some View", "private var missingLinksCard: some View"] {
            let body = try #require(CadenceSourceScan.declarationBody(card, in: calendar), "\(card) moved")
            #expect(body.contains("iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)"),
                    "\(card) types its hairline inset instead of reading the row text inset")
        }
        let sidebar = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSidebarLayoutSettingsSection.swift")
        )
        #expect(CadenceSourceScan.matchCount("iOSRowDivider\\(leadingInset: iOSSettingsMetrics\\.rowTextInset\\)", in: sidebar) == 1,
                "the Sidebar Rows card's hairline no longer reads the row text inset")
    }
}

/// **[[T-9954]].** The iPad Settings rail's lit row says it is the selected one, as every row of
/// the root sidebar beside it does (`iOSRootSidebar`'s three row types). It drew the selection
/// and stated nothing.
struct IOSSettingsRailSelectionTraitTests {
    @Test func theRailButtonStatesItsSelection() throws {
        let source = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSSettingsComponents.swift")
        )
        let body = try #require(
            CadenceSourceScan.declarationBody("private struct iOSSettingsRailButton: View", in: source),
            "iOSSettingsRailButton moved"
        )
        #expect(body.contains(".fill(isSelected ? Theme.surfaceElevated : Color.clear)"),
                "non-vacuity: the rail button no longer draws its selection here")
        #expect(body.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"),
                "the rail's lit row no longer states that it is selected")
        // The root sidebar is the precedent; if it stops stating selection this rule needs rereading.
        let sidebar = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/iOS/iOSRootSidebar.swift")
        )
        #expect(sidebar.components(separatedBy: ".accessibilityAddTraits(isSelected ? .isSelected : [])").count - 1 >= 3)
    }
}

#endif
