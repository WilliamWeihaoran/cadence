import Foundation
import Testing
@testable import Cadence

/// **T-352: the macOS root selection is deliberately not restored at launch.**
///
/// Every launch opens on Today. `macOSRootView.selection` is plain `@State` seeded to `.today`,
/// and nothing anywhere reads a stored value back into it — no `SceneStorage`, no `AppStorage`,
/// no restore path. That is the decided contract, not an oversight.
///
/// The defect this suite closes was a *comment*, not a mechanism.
/// `TasksPageView.requestedScope` documented itself as non-`nil` for "an `.inbox` selection
/// restored at launch", naming machinery the app has never had. A missing feature is visible the
/// moment anyone looks; a comment that asserts the feature exists stops anyone looking. So the
/// pin has two halves, and both are needed:
///
/// 1. the **code** contract — the selection stays unpersisted, so adding scene/app storage to it
///    is a deliberate decision rather than a quiet edit; and
/// 2. the **prose** contract — the doc comment keeps describing that, and cannot drift back to
///    claiming a restore.
///
/// Read through `strippingComments`, never `codeOnly`: `codeOnly` blanks string literals as well
/// as comments, which makes a quoted needle permanently unmatchable and the scan permanently
/// green. The one assertion that must read a *comment* reads the raw source on purpose, and says
/// so where it does it.
struct CadenceRootSelectionLaunchContractTests {
    private static let rootPath = "Cadence/macOS/macOSRootView.swift"
    private static let stateSupportPath = "Cadence/macOS/Views/macOSRootStateSupport.swift"
    private static let tasksPagePath = "Cadence/macOS/Views/macOSRootSupportViews.swift"

    /// Every attribute attached to a `var` whose name contains "selection", paired with that name.
    /// Reading the wrapper off the declaration rather than asserting one literal spelling is what
    /// makes this fail on a *new* persisted selection property, not only on an edit to this one.
    private func selectionPropertyWrappers(in source: String) -> [(wrapper: String, name: String)] {
        let pattern = "@([A-Za-z]+)(?:\\([^)]*\\))?\\s+(?:private\\s+)?var\\s+([A-Za-z]*[Ss]election[A-Za-z]*)"
        let wrappers = CadenceSourceScan.captures(pattern, in: source, group: 1).map(\.text)
        let names = CadenceSourceScan.captures(pattern, in: source, group: 2).map(\.text)
        return Array(zip(wrappers, names)).map { (wrapper: $0.0, name: $0.1) }
    }

    @Test func theMacRootSelectionIsPlainStateSeededToToday() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.rootPath)
        let source = CadenceSourceScan.strippingComments(raw)

        // Non-vacuity: the file was read, the stripper ran, and it blanked rather than shortened.
        #expect(source != raw, "the comment stripper did nothing")
        #expect(source.count == raw.count, "the stripper shortened the source instead of blanking it")
        #expect(source.contains("struct macOSRootView: View"), "\(Self.rootPath) is not where the scan thinks it is")

        #expect(
            source.contains("@State private var selection: SidebarItem? = .today"),
            "the root selection is no longer plain @State seeded to .today"
        )

        let found = selectionPropertyWrappers(in: source)
        #expect(found.contains { $0.name == "selection" }, "the scan matched no `selection` declaration at all")
        for property in found {
            #expect(
                property.wrapper == "State",
                "`\(property.name)` is declared @\(property.wrapper); the root selection is not persisted (T-352)"
            )
        }
    }

    /// `SceneStorage` is the *only* thing SwiftUI offers that restores a value into a scene at
    /// launch, and it appears nowhere in this app. Banning it in the two files that own the root
    /// selection is therefore an exact statement of the contract rather than a proxy for it.
    @Test func theMacRootOwnsNoSceneRestoredState() throws {
        for path in [Self.rootPath, Self.stateSupportPath] {
            let raw = try CadenceSourceScan.sourceFile(path)
            let source = CadenceSourceScan.strippingComments(raw)
            #expect(source != raw, "\(path): the comment stripper did nothing")
            #expect(!source.isEmpty, "\(path) read as empty")
            #expect(
                CadenceSourceScan.matchCount("@SceneStorage", in: source) == 0,
                "\(path) restores scene state; the macOS root selection is not restored at launch (T-352)"
            )
            #expect(
                CadenceSourceScan.matchCount("@AppStorage[^\\n]*SidebarItem", in: source) == 0,
                "\(path) persists a SidebarItem; the macOS root selection is not restored at launch (T-352)"
            )
        }

        // The claim above — that `SceneStorage` is unused app-wide — is itself checkable, so check
        // it. If it ever gains a legitimate use elsewhere this assertion is the place to relax,
        // and the two file-scoped bans above still stand.
        let files = try CadenceSourceScan.swiftFiles(under: "Cadence")
        #expect(files.count > 300, "the source walk found \(files.count) files and cannot be doing its job")
        #expect(files.contains(Self.rootPath), "\(Self.rootPath) is not where the walk thinks it is")
        let read = CadenceSourceScan.strippedSourceReader()
        let sceneStorageUsers = try files.filter { CadenceSourceScan.matchCount("@SceneStorage", in: try read($0)) > 0 }
        #expect(sceneStorageUsers.isEmpty, "@SceneStorage appeared in \(sceneStorageUsers)")
    }

    /// **Reads the raw source on purpose.** The subject here is the doc comment itself, so
    /// stripping comments would blank the only text this test is about. Every other scan in this
    /// suite reads stripped source; this one is the deliberate exception, and the assertions below
    /// prove it is reading prose by requiring text that only exists inside a comment.
    @Test func theRequestedScopeDocCommentDescribesTheRealContract() throws {
        let raw = try CadenceSourceScan.sourceFile(Self.tasksPagePath)
        #expect(raw.contains("var requestedScope: CadenceTasksPageScope?"), "the property this comment documents is gone")

        #expect(
            !raw.contains("restored at launch"),
            "the requestedScope comment claims a launch restore again; there is no such mechanism (T-352)"
        )
        #expect(
            raw.contains("Nothing restores a selection when the app launches"),
            "the requestedScope comment no longer states that the root selection is not restored (T-352)"
        )

        // Non-vacuity for a raw read: the sentence above must live in a comment, so the stripper
        // must remove it. If it survives stripping, this test is reading code and its premise is
        // wrong.
        let stripped = CadenceSourceScan.strippingComments(raw)
        #expect(stripped != raw, "the comment stripper did nothing")
        #expect(stripped.count == raw.count, "the stripper shortened the source instead of blanking it")
        #expect(
            !stripped.contains("Nothing restores a selection when the app launches"),
            "the sentence being pinned is not in a comment"
        )
        #expect(stripped.contains("var requestedScope: CadenceTasksPageScope?"), "the stripper ate the declaration")
    }
}
