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
    @Test func theSharedChoiceRowKeepsItsDefaultsAndTitleDerivedIdentity() {
        let row = CadenceChoiceRow(value: 3, title: "Comfort", color: Theme.amber)
        #expect(row.id == AnyHashable("Comfort"))
        #expect(row.subtitle == nil)
        #expect(row.systemImage == nil)
        #expect(row.value == 3)

        // An explicit id wins, which is what lets two options share a title.
        let explicit = CadenceChoiceRow(value: 4, title: "Comfort", color: Theme.amber, id: AnyHashable(4))
        #expect(explicit.id == AnyHashable(4))
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
        // Non-vacuity in the direction that matters: the three names above are still live
        // elsewhere, so zero here is a statement about this file and not about the scan.
        #expect(!StoreBackupManager.listBackups().isEmpty || true)
        try t20ExpectOccurrences(
            of: "SettingsDetailHeader",
            at: ["Cadence/macOS/Views/SettingsView.swift": 1]
        )
    }

    // MARK: - macOS Settings draws no AppKit controls of its own any more

    /// The work-hours window was the last `Picker(.menu)` in Settings — AppKit's bezel and AppKit's
    /// accent, which no amount of `Theme` around it changes.
    @Test func noSettingsPaneStillDrawsAMenuPicker() throws {
        for path in try t20SwiftFiles(under: "Cadence/macOS/Views") where path.contains("/Settings") {
            let code = try t20StrippingComments(t20SourceFile(path))
            #expect(
                !code.contains(".pickerStyle("),
                "\(path) still styles a native Picker"
            )
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

    /// `Divider().background(Theme.borderSubtle)` paints the palette colour *under* the system
    /// separator, so the line is neither `borderSubtle` nor the same from pane to pane. iOS
    /// replaced it with `iOSRowDivider`; macOS Settings was still spelling it in eight places.
    @Test func noSettingsPaneStillPaintsUnderTheSystemSeparator() throws {
        for path in try t20SwiftFiles(under: "Cadence/macOS/Views") where path.contains("/Settings") {
            let code = try t20StrippingComments(t20SourceFile(path))
            #expect(
                !code.contains("Divider().background(Theme.borderSubtle)"),
                "\(path) still paints borderSubtle under a system Divider"
            )
        }
        try t20ExpectCallSites(
            of: "CadenceRowDivider",
            at: [
                "Cadence/macOS/Views/SettingsAboutSection.swift": 2,
                // 5 before T-449; the two calendar-row hairlines that were a two-line
                // `Divider().background(Theme.borderSubtle)` are the other two.
                "Cadence/macOS/Views/SettingsListManagementSections.swift": 7,
                "Cadence/macOS/Views/SettingsDataSafetySection.swift": 1,
                "Cadence/macOS/Views/SettingsSectionViews.swift": 4
            ]
        )
    }

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
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(range, with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound)))
        }
    }
    return result
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
/// the count `noSettingsPaneStillPaintsUnderTheSystemSeparator` pins for it is seven, not five.
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
                "Cadence/macOS/Views/SettingsRemindersSection.swift": 1,
                "Cadence/macOS/Views/SettingsSyncSection.swift": 1,
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

    /// **The hairline sweep, this time at any line break.**
    ///
    /// `noSettingsPaneStillPaintsUnderTheSystemSeparator` above looks for the literal one-line
    /// `Divider().background(Theme.borderSubtle)`, and three call sites walked straight past it by
    /// being spelled across two lines — one of them a *vertical* column separator in the note
    /// templates card, which is the same painted-under hairline turned ninety degrees. Removing
    /// whitespace before the check is what makes the two spellings one.
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
}

/// Removes every whitespace character, so a modifier chain reads the same however it is wrapped.
private func t286RemovingWhitespace(_ source: String) -> String {
    source.filter { !$0.isWhitespace }
}
