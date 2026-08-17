import Testing

@testable import Cadence

@MainActor
struct NoteTemplateLibraryTests {
    @Test func overridesReplaceTemplateFieldsForMatchingNoteKinds() {
        let raw = NoteTemplateLibrary.setOverride(
            for: "project-brief",
            title: "Custom Brief",
            subtitle: "Custom scope",
            body: "# Custom",
            in: ""
        )

        let template = NoteTemplateLibrary.templates(for: .list, overridesRaw: raw)
            .first { $0.id == "project-brief" }

        #expect(template?.title == "Custom Brief")
        #expect(template?.subtitle == "Custom scope")
        #expect(template?.body == "# Custom")
    }

    @Test func resetOverrideRestoresDefaultTemplate() throws {
        let customizedRaw = NoteTemplateLibrary.setOverride(
            for: "research-note",
            title: "Custom Research",
            subtitle: "Changed",
            body: "# Changed",
            in: ""
        )
        let resetRaw = NoteTemplateLibrary.resetOverride(for: "research-note", in: customizedRaw)

        let defaultTemplate = try #require(NoteTemplateLibrary.defaultTemplate(id: "research-note"))
        let template = try #require(NoteTemplateLibrary.templates(for: .list, overridesRaw: resetRaw).first { $0.id == "research-note" })

        #expect(template == defaultTemplate)
        #expect(NoteTemplateLibrary.overrides(from: resetRaw).isEmpty)
    }

    /// Editing a template back to its defaults must *remove* the override, not store one that
    /// happens to equal the default.
    ///
    /// This has to start from a customized state. Starting from `in: ""` — as it used to — the
    /// `removeValue` under test runs against an already-empty dictionary, so the assertion is
    /// satisfied by never entering the other branch and deleting the removal keeps the suite
    /// green. The user-visible consequence of that bug is a template that reports "Customized"
    /// forever after you have typed the defaults back into it.
    @Test func matchingDefaultValuesRemoveAnExistingOverride() throws {
        let defaultTemplate = try #require(NoteTemplateLibrary.defaultTemplate(id: "checklist"))

        let customized = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: "Custom",
            subtitle: "Custom subtitle",
            body: "# Custom",
            in: ""
        )
        #expect(NoteTemplateLibrary.overrides(from: customized)[defaultTemplate.id] != nil)
        #expect(NoteTemplateLibrary.isCustomized(defaultTemplate, overridesRaw: customized))

        let restored = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: defaultTemplate.title,
            subtitle: defaultTemplate.subtitle,
            body: defaultTemplate.body,
            in: customized
        )

        #expect(NoteTemplateLibrary.overrides(from: restored).isEmpty)
        #expect(!NoteTemplateLibrary.isCustomized(defaultTemplate, overridesRaw: restored))
    }

    /// Restoring one template must not disturb another that is still customized — the removal is
    /// keyed, not a wipe.
    @Test func restoringOneTemplateLeavesOtherOverridesAlone() throws {
        let checklist = try #require(NoteTemplateLibrary.defaultTemplate(id: "checklist"))
        let brief = try #require(NoteTemplateLibrary.defaultTemplate(id: "project-brief"))

        var raw = NoteTemplateLibrary.setOverride(
            for: checklist.id, title: "C", subtitle: "C", body: "# C", in: ""
        )
        raw = NoteTemplateLibrary.setOverride(
            for: brief.id, title: "B", subtitle: "B", body: "# B", in: raw
        )
        raw = NoteTemplateLibrary.setOverride(
            for: checklist.id,
            title: checklist.title,
            subtitle: checklist.subtitle,
            body: checklist.body,
            in: raw
        )

        #expect(Set(NoteTemplateLibrary.overrides(from: raw).keys) == [brief.id])
        #expect(!NoteTemplateLibrary.isCustomized(checklist, overridesRaw: raw))
        #expect(NoteTemplateLibrary.isCustomized(brief, overridesRaw: raw))
    }

    /// The three functions behind the Settings → Templates screen, none of which had a test.
    /// `editableTemplates` is the list you see, `noteKinds(containing:)` is the "used by" line on
    /// each row, and `isCustomized` is the badge and the Reset button's enabled state.
    @Test func templateSettingsSurfaceReportsEveryTemplateItsKindsAndItsCustomizedState() throws {
        let all = NoteTemplateLibrary.editableTemplates(overridesRaw: "")

        // Every template offered by any kind must be reachable from the settings list, or it is
        // a template the user can apply but never edit.
        let reachable = Set(all.map(\.id))
        for kind in NoteKind.allCases {
            for template in NoteTemplateLibrary.templates(for: kind, overridesRaw: "") {
                #expect(reachable.contains(template.id), "\(template.id) is applied by \(kind) but not editable")
            }
        }
        #expect(Set(all.map(\.id)).count == all.count)

        // `noteKinds(containing:)` must agree with `templates(for:)` in both directions.
        for template in all {
            let claimed = Set(NoteTemplateLibrary.noteKinds(containing: template))
            let actual = Set(NoteKind.allCases.filter { kind in
                NoteTemplateLibrary.templates(for: kind, overridesRaw: "").contains { $0.id == template.id }
            })
            #expect(claimed == actual, "\(template.id) kinds disagree")
            #expect(!claimed.isEmpty, "\(template.id) is editable but no kind offers it")
        }

        // The editable list carries overrides through, and only for the overridden row.
        let brief = try #require(all.first { $0.id == "project-brief" })
        let raw = NoteTemplateLibrary.setOverride(
            for: brief.id, title: "Renamed", subtitle: "Rescoped", body: "# Body", in: ""
        )
        let edited = NoteTemplateLibrary.editableTemplates(overridesRaw: raw)

        #expect(edited.first { $0.id == brief.id }?.title == "Renamed")
        #expect(edited.first { $0.id == brief.id }?.body == "# Body")
        #expect(edited.filter { NoteTemplateLibrary.isCustomized($0, overridesRaw: raw) }.map(\.id) == [brief.id])
        #expect(edited.map(\.id) == all.map(\.id))
    }

    /// Clearing the Title field asks for the default title back — `merged` falls back to it — so it
    /// must not record an override.
    ///
    /// It used to: `""` differs from the default title as a raw string, so an override was stored,
    /// the field repopulated with the original text on the next read, and the template reported
    /// itself Customized with an enabled "Reset Template" while looking completely untouched.
    @Test func clearingTheTitleDoesNotRecordAnOverride() throws {
        let defaultTemplate = try #require(NoteTemplateLibrary.defaultTemplate(id: "daily-plan"))

        let raw = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: "",
            subtitle: defaultTemplate.subtitle,
            body: defaultTemplate.body,
            in: ""
        )

        #expect(NoteTemplateLibrary.overrides(from: raw).isEmpty)
        #expect(!NoteTemplateLibrary.isCustomized(defaultTemplate, overridesRaw: raw))
    }

    /// The same rule has to clear an override that already exists, not merely decline to add one.
    @Test func clearingTheDescriptionRemovesAnExistingOverride() throws {
        let defaultTemplate = try #require(NoteTemplateLibrary.defaultTemplate(id: "daily-plan"))

        let customized = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: defaultTemplate.title,
            subtitle: "Rescoped",
            body: defaultTemplate.body,
            in: ""
        )
        #expect(NoteTemplateLibrary.isCustomized(defaultTemplate, overridesRaw: customized))

        let cleared = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: defaultTemplate.title,
            subtitle: "   ",
            body: defaultTemplate.body,
            in: customized
        )

        #expect(NoteTemplateLibrary.overrides(from: cleared).isEmpty)
        #expect(!NoteTemplateLibrary.isCustomized(defaultTemplate, overridesRaw: cleared))
    }

    /// An empty *body* has no fallback in `merged`, so it is a genuine edit and keeps its override.
    /// This is what stops the "empty means default" rule from swallowing a deliberately blank
    /// template.
    @Test func clearingTheBodyIsARealCustomization() throws {
        let defaultTemplate = try #require(NoteTemplateLibrary.defaultTemplate(id: "daily-plan"))

        let raw = NoteTemplateLibrary.setOverride(
            for: defaultTemplate.id,
            title: defaultTemplate.title,
            subtitle: defaultTemplate.subtitle,
            body: "",
            in: ""
        )

        #expect(NoteTemplateLibrary.isCustomized(defaultTemplate, overridesRaw: raw))
        let template = try #require(
            NoteTemplateLibrary.editableTemplates(overridesRaw: raw).first { $0.id == defaultTemplate.id }
        )
        #expect(template.body.isEmpty)
        #expect(template.title == defaultTemplate.title)
    }
}
