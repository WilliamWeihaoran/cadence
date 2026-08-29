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

        // The slash command is filtered out of the strip rather than offered and ignored. The
        // predicate is `MarkdownSlashCommand.refusingImageInsertion` since T-442, because macOS's
        // `/` menu had to make the identical refusal and open-coding `case .chooseImage` a second
        // time is the shape T-374 exists to stop. What is pinned here is that this strip *reads*
        // it; `theSlashMenuDropsTheImageCommandThroughOneSharedPredicate` pins what it returns.
        #expect(
            code.contains("MarkdownSlashCommand.refusingImageInsertion(MarkdownSlashCommand.all)"),
            "the iOS slash strip no longer reads the shared refusal"
        )
        // Scoped to the one function, not the file: `applySlashCommand` legitimately switches on
        // `.chooseImage` to run the follow-up, and a file-wide count would read that as the strip
        // still filtering for itself. Scoping a scan to a function body is the standing rule here.
        let choices = try #require(
            CadenceSourceScan.functionBody(named: "slashCommandChoices", in: code),
            "slashCommandChoices() could not be read; the assertion below would be measuring nothing"
        )
        #expect(
            choices.contains("case .chooseImage") == false,
            "the iOS strip re-tests the command's action itself instead of reading the shared predicate"
        )
        #expect(
            choices.contains("refusingImageInsertion"),
            "the shared refusal is read somewhere else in the file, not by the strip"
        )

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

    // MARK: - T-442: the same door on macOS

    /// **What the `/` refusal actually returns, as a value.**
    ///
    /// Everything else in this suite about slash commands is a source scan, because both call
    /// sites are inside SwiftUI views (one of them in a file this target does not compile). The
    /// predicate itself is shared, `nonisolated` and pure, so this half needs no scanning at all —
    /// and it is the half that would silently stop working if `refusingImageInsertion` were ever
    /// "simplified" into something that drops the wrong entry or reorders the menu.
    @Test func theSlashMenuDropsTheImageCommandThroughOneSharedPredicate() {
        let all = MarkdownSlashCommand.all
        let isImage: (MarkdownSlashCommand) -> Bool = { command in
            if case .chooseImage = command.action { return true }
            return false
        }

        // Non-vacuity: there is exactly one image command to drop, so the counts below are not
        // agreeing about an empty set.
        #expect(all.filter(isImage).count == 1)

        let refused = MarkdownSlashCommand.refusingImageInsertion(all)
        #expect(refused.contains(where: isImage) == false, "the image command survived the refusal")
        // Order-preserving and nothing else dropped — a `filter` that took the wrong side, or a
        // `Set` round trip, passes the two assertions above and fails this one.
        #expect(refused.map(\.id) == all.filter { !isImage($0) }.map(\.id))

        // macOS appends its template commands *before* filtering, so the predicate has to be
        // stated over an argument rather than over `all`.
        let withTemplates = all + MarkdownSlashCommand.templateCommands(
            for: [NoteTemplate(id: "probe", title: "Probe", subtitle: "Probe", body: "# Probe")]
        )
        let refusedWithTemplates = MarkdownSlashCommand.refusingImageInsertion(withTemplates)
        #expect(refusedWithTemplates.map(\.id).contains("probe"))
        #expect(refusedWithTemplates.count == withTemplates.count - 1)
    }

    /// **macOS has the same four doors, and one flag reaches all of them.**
    ///
    /// The panel, the paste and the drop all funnel through `onCreateMarkdownImages` — which is
    /// `MarkdownEditor.createAssets` — where iOS needed a separate guard per path. So the guard
    /// count here is smaller than iOS's on purpose, and the relation at the end is what says the
    /// funnel is real rather than assumed.
    ///
    /// This file *is* compiled by this target, unlike the iOS ones above, but `MarkdownEditor`'s
    /// image plumbing is `private` inside a SwiftUI view with no reachable seam, so the wiring is
    /// still read as source. What the funnel does once it is handed nothing is behaviour, and it is
    /// already pinned: `MarkdownImagePasteTests.aHostThatCreatesNoAssetDeclinesRatherThanSwallowingThePaste`
    /// is the test that a refused paste leaves the text alone and falls through to AppKit.
    @Test func everyImageDoorInTheMacOSEditorIsBehindTheFlag() throws {
        let code = try strippedSource("Cadence/macOS/Editor/MarkdownEditorView.swift")

        // Spelled exactly as iOS spells it, which is what lets the host sweep below count both
        // platforms with one needle.
        #expect(code.contains("var allowsImageInsertion = true"), "the flag is gone or renamed")

        // Door 1 — the toolbar's photo button, removed rather than disabled.
        #expect(code.contains("allowsImageInsertion ? { chooseImages() } : nil"))
        #expect(code.contains("onChooseImages: chooseImagesAction,"))
        #expect(code.contains("let onChooseImages: (() -> Void)?"))
        #expect(code.contains("if let onChooseImages {"))
        #expect(
            CadenceSourceScan.matchCount("\\.disabled\\(onChooseImages", in: code) == 0,
            "the image button is dimmed rather than dropped"
        )

        // Door 2 — the `/image` entry, dropped from the menu the editor is handed.
        #expect(code.contains("MarkdownSlashCommand.refusingImageInsertion(all)"))
        #expect(code.contains("slashCommands: availableSlashCommands,"))

        // Door 3 — the open panel, which `/image` also reaches through the coordinator's follow-up.
        let picker = try #require(
            CadenceSourceScan.functionBody(named: "chooseImages", in: code),
            "chooseImages() could not be read; the assertion below would be measuring nothing"
        )
        #expect(
            picker.contains("guard allowsImageInsertion else { return }"),
            "chooseImages() presents the panel without consulting the flag"
        )

        // Door 4 — paste and drop, which are the same door here.
        #expect(code.contains("onCreateImages: createAssets,"))
        let creator = try #require(
            CadenceSourceScan.functionBody(named: "createAssets", in: code),
            "createAssets() could not be read; the assertion below would be measuring nothing"
        )
        #expect(
            creator.contains("guard allowsImageInsertion else { return [] }"),
            "a pasted or dropped image mints an asset without consulting the flag"
        )

        // The relation behind "one funnel": every asset this file mints is minted inside
        // `createAssets`, so a creator added anywhere else in the view is a fifth door and fails
        // here rather than shipping unguarded.
        let mintedInFile = CadenceSourceScan.matchCount("MarkdownImageAssetService\\.createAssets?\\(", in: code)
        let mintedInCreator = CadenceSourceScan.matchCount("MarkdownImageAssetService\\.createAssets?\\(", in: creator)
        #expect(mintedInCreator > 0, "the creator mints nothing; this scan is measuring nothing")
        #expect(
            mintedInFile == mintedInCreator,
            "the editor mints assets outside createAssets; check that path is behind the flag too"
        )
    }

    /// **The macOS note-template editor: the shared markdown surface, with the door shut.**
    ///
    /// It was a bare `TextEditor` in 12pt monospace while iOS bound the same `UserDefaults` string
    /// to a full markdown editor — an unrecorded parity gap, and the reason T-421's fix was
    /// iOS-only: macOS had no image door to close because it had no image path at all. Closing the
    /// gap opens the door, so the two halves ship together.
    @Test func theMacOSNoteTemplateEditorIsTheSharedSurfaceAndRefusesImages() throws {
        let code = try strippedSource("Cadence/macOS/Views/SettingsTemplatesSection.swift")

        #expect(code.contains("MarkdownEditor("), "the macOS template body is not the shared editor")
        #expect(code.contains("allowsImageInsertion: false"), "the macOS template body accepts images")
        #expect(
            CadenceSourceScan.matchCount("TextEditor\\(", in: code) == 0,
            "the plain TextEditor is back on the template body"
        )

        // The shared surface, not a port of the iOS one — that view's toolbar, `[[`/`/` strips and
        // photos picker are phone chrome, and `Cadence/iOS/` does not compile on this platform
        // anyway.
        #expect(
            CadenceSourceScan.matchCount("iOSMarkdownEditingSurface", in: code) == 0,
            "the macOS pane names the iOS editor"
        )

        // The editor is an `NSScrollView` that insets its own text and draws its own background
        // edge to edge, so it opts out of the shared well's 12pt gutter rather than being wrapped
        // in a second, unpadded rectangle beside it.
        #expect(
            code.contains("insetsContent: false"),
            "the template body sits in the padded well; the editor floats in a 12pt gutter"
        )

        // A stencil that names one particular note is not reusable, so no reference lists and no
        // nested templates. These are absences of arguments, which is exactly the kind of claim
        // that rots quietly — hence stated rather than assumed.
        #expect(CadenceSourceScan.matchCount("referenceNotes:", in: code) == 0)
        #expect(CadenceSourceScan.matchCount("referenceTasks:", in: code) == 0)
        #expect(CadenceSourceScan.matchCount("slashTemplates:", in: code) == 0)
    }

    /// The premise both template refusals rest on, from the inventory's side.
    ///
    /// The brief for T-442 asked whether the template body is one of the fields
    /// `CadenceMarkdownSourceInventory` enumerates. **It is not, and cannot be:** every case is a
    /// stored property on a `CadenceSchema` model reached by a `ModelContext` fetch, and a template
    /// body is a JSON string in `UserDefaults`. The file says so in prose; this says it in a form
    /// that fails if a case is ever added for it without the sweep being taught to read defaults.
    @Test func noInventorySourceIsTheTemplateBody() {
        let entities = Set(CadenceMarkdownSourceInventory.Source.allCases.map(\.entityName))
        #expect(entities.count == CadenceMarkdownSourceInventory.Source.allCases.count, "two cases name one entity")
        #expect(entities.contains { $0.localizedCaseInsensitiveContains("template") } == false)

        // Non-vacuity, and the shape of the thing that is in there: `Note.content` is a stored
        // property on a model in the schema.
        #expect(entities.contains("Note"))
        #expect(CadenceMarkdownSourceInventory.Source.noteContent.propertyName == "content")
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
            "Cadence/iOS/iOSCalendarQuickCreateSheet.swift",
            // T-442. The same template body, edited on the other platform — the macOS host
            // arrived when its `TextEditor` became a `MarkdownEditor` and inherited the door.
            "Cadence/macOS/Views/SettingsTemplatesSection.swift"
        ]
        for path in outOfStore {
            let code = try strippedSource(path)
            // Two editors, one flag: iOS hosts draw `iOSMarkdownEditingSurface`, the macOS host
            // draws `MarkdownEditor`, and the property is spelled identically on both so the
            // relation below is one count rather than a per-platform branch.
            let editors = CadenceSourceScan.matchCount("iOSMarkdownEditingSurface\\(", in: code)
                + CadenceSourceScan.matchCount("MarkdownEditor\\(", in: code)
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
            "Cadence/macOS/Editor/MarkdownEditorView.swift",
            "Cadence/macOS/Views/SettingsTemplatesSection.swift",
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
