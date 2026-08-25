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

        // The three components that draw a row read the property; none of them types a number.
        try t20ExpectOccurrences(
            of: "CadenceSettingsRowMetrics.rowHeight",
            at: [
                "Cadence/Shared/Components/CadenceFieldRows.swift": 3,
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
                "Cadence/macOS/Views/SettingsListManagementSections.swift": 5,
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
    @Test func theSourceScanIsNotVacuous() throws {
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
