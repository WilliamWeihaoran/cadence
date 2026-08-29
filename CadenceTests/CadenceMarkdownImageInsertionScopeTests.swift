import Foundation
import Testing
@testable import Cadence

/// **T-421 — an image may only be inserted where the store can see it afterwards.**
///
/// `CadenceMarkdownSourceInventory` answers one question for the image sweep: does any *stored*
/// markdown still reference this asset? T-411 widened it from `Note.content` to every markdown
/// field in `CadenceSchema` after an image pasted into a task's notes was collected out from under
/// a live task. Two markdown surfaces are still outside that scan and always will be:
///
/// - the note **template** body, a JSON string in `UserDefaults` under
///   `NoteTemplateLibrary.storageKey`;
/// - the calendar sheets' **Apple Calendar note**, which is `EKEvent.notes` in EventKit.
///
/// The direction of harm decides the fix. An asset the inventory over-counts is a *leak* — T-411
/// chose that side deliberately — but an asset it cannot see at all is *deleted*, and the bytes are
/// `.externalStorage`. So the door closes rather than the scan widening:
/// `iOSMarkdownEditingSurface.allowsImageInsertion` is `false` at hosts whose text is not a row in
/// the store, and these tests pin both that every image path through that editor is behind the flag
/// and that every out-of-store host sets it.
///
/// `Cadence/iOS/` is not compiled by this macOS test target, so the editor assertions here are
/// **source scans**, not behaviour. The non-vacuity test at the bottom is what makes them mean
/// anything; `aTemplateBodyRoundTripsThroughAStringNotTheStore` is the one behavioural test, and it
/// pins the premise the refusal rests on.
struct CadenceMarkdownImageInsertionScopeTests {

    private func strippedSource(_ path: String) throws -> String {
        CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
    }

    // MARK: - The flag exists and every door is behind it

    /// There are four ways an image reaches the text in this editor, and they do not share a
    /// funnel: the toolbar's photo button, the `/image` slash command, a paste, and the photos
    /// picker's completion. A flag consulted at one of them is a fix for one of them.
    @Test func everyImageDoorInTheEditorIsBehindTheFlag() throws {
        let code = try strippedSource("Cadence/iOS/iOSMarkdownEditingSurface.swift")

        #expect(code.contains("var allowsImageInsertion = true"), "the flag is gone or renamed")

        // The toolbar button is removed rather than disabled. Bound to a `let` because a ternary
        // producing an optional closure *inside* the toolbar call is where the Swift type checker
        // gives up — measured on the iOS-simulator build, which is the only thing that compiles
        // this file: `failed to produce diagnostic for expression`.
        #expect(code.contains("let chooseImagesAction: (() -> Void)? = allowsImageInsertion ? { chooseImages() } : nil"))
        #expect(code.contains("chooseImages: chooseImagesAction,"))

        // The slash command is filtered out of the strip rather than offered and ignored.
        #expect(code.contains("if !allowsImageInsertion, case .chooseImage = command.action { return false }"))

        // The picker presenter, which `/image` reaches directly rather than through the toolbar.
        let picker = try #require(
            CadenceSourceScan.functionBody(named: "chooseImages", in: code),
            "chooseImages() could not be read; the assertion below would be measuring nothing"
        )
        #expect(
            picker.contains("guard allowsImageInsertion else { return }"),
            "chooseImages() presents the picker without consulting the flag"
        )

        // Paste. Guarded in the creator rather than by passing `nil` — same expression problem as
        // above, and `iOSMarkdownTextView.paste(_:)` falls through to `super.paste` on an empty
        // result, so a refused paste is an ordinary text paste rather than a swallowed one.
        #expect(code.contains("onCreatePastedImages: createPastedImageAssets,"))
        let paste = try #require(
            CadenceSourceScan.functionBody(named: "createPastedImageAssets", in: code),
            "createPastedImageAssets() could not be read; the assertion below would be measuring nothing"
        )
        #expect(
            paste.contains("guard allowsImageInsertion else { return [] }"),
            "a pasted image mints an asset without consulting the flag"
        )

        // The relation behind "four doors": every `MarkdownImageAsset` this file mints comes from
        // one of the two creators above, both of which are now unreachable when the flag is off. A
        // third creator is a fifth door and this is what notices.
        #expect(
            CadenceSourceScan.matchCount("MarkdownImageAssetService\\.createAsset\\(", in: code) == 2,
            "the editor grew another asset creator; check it is behind allowsImageInsertion too"
        )
    }

    /// The toolbar takes `nil` for "this host has no image button" rather than a no-op closure. A
    /// button that is drawn and refuses the tap advertises a capability the row does not have.
    @Test func theToolbarDropsTheImageButtonRatherThanDisablingIt() throws {
        let code = try strippedSource("Cadence/iOS/iOSMarkdownAccessoryViews.swift")

        #expect(code.contains("let chooseImages: (() -> Void)?"))
        #expect(code.contains("if let chooseImages {"))
        #expect(
            CadenceSourceScan.matchCount("\\.disabled\\(chooseImages", in: code) == 0,
            "the image button is dimmed rather than dropped"
        )
    }

    // MARK: - The template editor is the host that needs it

    /// The one host closed by T-421. Its `text` binding is a `UserDefaults` string, and it already
    /// refuses embedded task creation for the neighbouring reason — a template is a stencil, not a
    /// document, and must not mint rows.
    @Test func theNoteTemplateEditorRefusesImageInsertion() throws {
        let code = try strippedSource("Cadence/iOS/iOSSettingsTemplateAndListSections.swift")

        #expect(code.contains("allowsImageInsertion: false"), "the template body editor accepts images again")
        #expect(
            code.contains("allowsEmbeddedTaskCreation: false"),
            "the neighbouring refusal is gone; these two travel together"
        )

        // The relation, not a count: within this file every editor that refuses to mint tasks also
        // refuses to mint images, so a second template-shaped editor here cannot arrive with one
        // guard and not the other.
        let tasksRefused = CadenceSourceScan.matchCount("allowsEmbeddedTaskCreation: false", in: code)
        let imagesRefused = CadenceSourceScan.matchCount("allowsImageInsertion: false", in: code)
        #expect(tasksRefused > 0, "this file presents no guarded editor; the scan is measuring nothing")
        #expect(tasksRefused == imagesRefused)
    }

    /// The template body really is a `UserDefaults` string and not a row — the premise the refusal
    /// rests on. This half is behavioural: `NoteTemplateLibrary` is shared code and compiles here.
    @Test func aTemplateBodyRoundTripsThroughAStringNotTheStore() {
        let raw = NoteTemplateLibrary.setOverride(
            for: "checklist",
            title: "Checklist",
            subtitle: "Steps",
            body: "![](cadence-image://11111111-1111-1111-1111-111111111111)",
            in: ""
        )

        #expect(raw.contains("cadence-image"))
        #expect(NoteTemplateLibrary.storageKey == "noteTemplateOverrides")

        // Whatever an image reference in a template body would be, it is this string — reachable
        // only from `UserDefaults`, and so invisible to every `ModelContext` fetch the sweep makes.
        let restored = NoteTemplateLibrary.editableTemplates(overridesRaw: raw)
        #expect(restored.contains { $0.id == "checklist" && $0.body.contains("cadence-image") })
    }

    // MARK: - T-422: the Apple Calendar note

    /// The event editor is always an event, so its Apple Calendar note is always `EKEvent.notes`
    /// and always outside the store. A flat refusal is correct here.
    @Test func theCalendarEventEditorRefusesImageInsertion() throws {
        let code = try strippedSource("Cadence/iOS/iOSCalendarEventEditSheet.swift")

        #expect(code.contains("allowsImageInsertion: false"))
        #expect(code.contains("allowsEmbeddedTaskCreation: false"))

        // Same relation as the template file: this sheet's one editor refuses both, so a second
        // editor arriving with one guard and not the other fails here.
        let tasksRefused = CadenceSourceScan.matchCount("allowsEmbeddedTaskCreation: false", in: code)
        #expect(tasksRefused > 0, "this file presents no guarded editor; the scan is measuring nothing")
        #expect(tasksRefused == CadenceSourceScan.matchCount("allowsImageInsertion: false", in: code))
    }

    /// Quick create is the one host where the flat refusal would be **wrong**, and this is the test
    /// that says so.
    ///
    /// Its single `notes` state has two destinations: `calendarManager.createEvent(notes:)` in
    /// event mode, which is EventKit and outside the store, and `task.notes` in
    /// `configureTask(_:)` otherwise. `AppTask.notes` is in the inventory — reaching it was the
    /// whole of T-411 — so an image pasted into a *task* note here is safe and refusing it would
    /// remove a working capability to fix a hazard that mode does not have. Copying the sibling
    /// sheet's `false` is the plausible mistake; this fails on it.
    @Test func quickCreateRefusesImagesOnlyInEventMode() throws {
        let code = try strippedSource("Cadence/iOS/iOSCalendarQuickCreateSheet.swift")

        #expect(
            code.contains("allowsImageInsertion: kind != .event"),
            "quick create does not condition the refusal on the mode that decides where notes go"
        )
        #expect(
            CadenceSourceScan.matchCount("allowsImageInsertion: false", in: code) == 0,
            "quick create refuses images in task mode too, where AppTask.notes is in the inventory"
        )

        // Non-vacuity plus the premise: the two destinations really are what the condition claims.
        #expect(code.contains("allowsEmbeddedTaskCreation: false"))
        #expect(code.contains("task.notes = notes"), "the task destination is gone; re-check the condition")
        #expect(code.contains("notes: notes"), "the event destination is gone; re-check the condition")
    }

    /// The claim the three tests above add up to, stated once as a relation over the whole editor's
    /// host set: **every** `iOSMarkdownEditingSurface(` in the app either writes a row this store
    /// can see, or passes `allowsImageInsertion`. A tenth host binding the editor to something
    /// outside SwiftData without the flag fails here without anyone remembering to add a case.
    ///
    /// The out-of-store list is spelled out rather than inferred, because "is this text a row?" is
    /// not a question a source scan can answer — that judgement is the ticket's, and this is where
    /// it is written down.
    @Test func everyOutOfStoreEditorHostPassesTheFlagAndNoOtherHostNeedsTo() throws {
        let outOfStore = [
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift"
        ]
        for path in outOfStore {
            let code = try strippedSource(path)
            let editors = CadenceSourceScan.matchCount("iOSMarkdownEditingSurface\\(", in: code)
            let flagged = CadenceSourceScan.matchCount("allowsImageInsertion:", in: code)

            #expect(editors > 0, "\(path) presents no editor at all; this scan is measuring nothing")
            #expect(
                editors == flagged,
                "\(path) presents \(editors) editors but passes allowsImageInsertion \(flagged) times"
            )
        }

        // The complement, as a count rather than an absence assertion on named files: the flag is
        // passed at exactly these three hosts and nowhere else. A fourth host that needs it is a
        // deliberate edit to this list; a stray one is a red test.
        let appRoot = CadenceSourceScan.repositoryRoot().appendingPathComponent("Cadence").path
        let swiftFiles = try FileManager.default.subpathsOfDirectory(atPath: appRoot)
            .filter { $0.hasSuffix(".swift") }
            .map { "Cadence/" + $0 }
            .sorted()
        #expect(swiftFiles.count > 100, "walked \(swiftFiles.count) files; that is not the app source tree")

        var hostsPassingTheFlag: [String] = []
        for path in swiftFiles {
            if try strippedSource(path).contains("allowsImageInsertion:") {
                hostsPassingTheFlag.append(path)
            }
        }

        #expect(
            hostsPassingTheFlag == outOfStore.sorted(),
            "the set of hosts refusing image insertion changed: \(hostsPassingTheFlag)"
        )
    }

    // MARK: - The scan itself

    /// Every scan above reads a file this target does not compile. A reader that silently returns
    /// an empty string satisfies all the `== 0` checks, so this pins length, content and that the
    /// stripper ran.
    ///
    /// The name is suite-specific on purpose: `theSourceScanReachesTheFilesItClaimsTo` already
    /// exists in another suite, and a shared name makes a mutation's `✔ Test name()` line
    /// unattributable.
    @Test func theImageInsertionScopeScanReachesTheFilesItClaimsTo() throws {
        for path in [
            "Cadence/iOS/iOSMarkdownEditingSurface.swift",
            "Cadence/iOS/iOSMarkdownAccessoryViews.swift",
            "Cadence/iOS/iOSSettingsTemplateAndListSections.swift",
            "Cadence/iOS/iOSCalendarEventEditSheet.swift",
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            "Cadence/Services/CadenceMarkdownSourceInventory.swift"
        ] {
            let raw = try CadenceSourceScan.sourceFile(path)
            #expect(raw.count > 1_000, "\(path) read as \(raw.count) characters; that is not the file")

            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(path) lost no comment text; the stripper did not run")
            #expect(stripped.count == raw.count)
        }

        // Needle self-check for the one regex that carries a `== 0` verdict.
        #expect(CadenceSourceScan.matchCount("\\.disabled\\(chooseImages", in: ".disabled(chooseImages == nil)") == 1)
        #expect(CadenceSourceScan.matchCount("\\.disabled\\(chooseImages", in: "Button(action: chooseImages)") == 0)
    }
}
