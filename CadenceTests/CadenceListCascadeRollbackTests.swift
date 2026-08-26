import Foundation
import SwiftData
import Testing
@testable import Cadence

/// T-291: a list cascade that could not finish had already deleted the list's goal links, and
/// every caller saved on top of it.
///
/// Two halves, and they only make sense together.
///
/// **Ordering.** `deleteProject` and `deleteArea` both ran `delete(uniqueGoalListLinks(…))` on the
/// line *before* `guard cascadeDeleteTasks(…) else { return false }`. So the one path that exists
/// to change nothing — "I could not read the store" — changed something: it severed every link
/// from the list to the goals it contributes to. The list survived, its tasks survived, and a goal
/// silently lost a list feeding its percentage.
///
/// **The `Bool`.** All three surfaces (`EditListSheet`, macOS `SettingsView`,
/// `iOSListDeletionSupport`) discarded the return value and saved anyway, which is what turned a
/// recoverable in-context mess into a committed one. `CadencePendingChangePersistence
/// .commitCascade` is now the only spelling: a `false` cascade rolls back and throws, exactly as a
/// refused commit does.
///
/// **Why the sweep is injectable.** The real trigger is a `fetch` that throws, which an in-memory
/// container will not do — the same reason `commitInsert`/`commitDelete` take their `commit` as a
/// parameter. Without the seam every `guard` here is unreachable from a test, which is precisely
/// how the ordering bug survived. The stand-in is faithful: the real sweep's contract is "returns
/// `false` having changed nothing".
/// A stand-in task sweep that records what it was asked about, so a test can prove the cascade
/// really reached the guard it is asserting on.
///
/// Deliberately outside the `@MainActor` suite: `CadenceListTaskSweep` is an ordinary
/// non-isolated closure, and a method on a main-actor-isolated type does not convert to one.
private final class RecordingSweep {
    private(set) var sweptIDs: [Set<UUID>] = []
    private let refusing: Set<UUID>

    /// - Parameter refusing: The task ids whose sweep fails. Empty means every sweep fails.
    init(refusing: Set<UUID> = []) {
        self.refusing = refusing
    }

    func sweep(_ ids: Set<UUID>) -> Bool {
        sweptIDs.append(ids)
        if refusing.isEmpty { return false }
        return refusing.isDisjoint(with: ids)
    }
}

@MainActor
struct CadenceListCascadeRollbackTests {

    // MARK: - Ordering

    /// The failure-shaped case, asserted **before** any rollback: at the instant the cascade gives
    /// up, the goal link must still be attached.
    ///
    /// A rollback would restore it either way, which is exactly why this is measured here and not
    /// after `commitCascade`. The ordering is what makes the `false` return mean "changed
    /// nothing"; the rollback is the second line of defence, not the first.
    @Test func aRefusedProjectSweepLeavesTheGoalLinkAttached() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let goal = Goal(title: "Ship v2")
        let project = Project(name: "Launch")
        let task = AppTask(title: "Write the release notes")
        task.project = project
        modelContext.insert(goal)
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()
        let link = try #require(modelContext.attachList(.project(project), to: goal))
        try modelContext.save()

        let sweep = RecordingSweep()
        let finished = modelContext.deleteProject(project, sweepTasks: sweep.sweep)

        #expect(finished == false)
        #expect(sweep.sweptIDs == [[task.id]], "the cascade never reached the task sweep")
        #expect(
            !link.isDeleted,
            "the cascade severed the project's goal link and then refused to finish"
        )
        #expect(!project.isDeleted)
        #expect(
            !modelContext.hasChanges,
            "an aborted cascade left a pending change for the next autosave to commit"
        )
        #expect(try modelContext.fetch(FetchDescriptor<GoalListLink>()).count == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<GoalListLink>()).count == 1)
    }

    /// The area's own sweep succeeds and a **nested project** is what fails, which is the second
    /// abort `deleteArea` can take. Its goal links have to survive that one too, so they go after
    /// the project loop rather than merely after the area's own guard.
    @Test func aRefusedNestedProjectLeavesTheAreasGoalLinkAttached() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let goal = Goal(title: "Ship v2")
        let area = Area(name: "Operations")
        let project = Project(name: "Launch", area: area)
        let areaTask = AppTask(title: "Renew the domain")
        areaTask.area = area
        let projectTask = AppTask(title: "Write the release notes")
        projectTask.project = project
        modelContext.insert(goal)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(areaTask)
        modelContext.insert(projectTask)
        try modelContext.save()
        let areaLink = try #require(modelContext.attachList(.area(area), to: goal))
        try modelContext.save()

        let sweep = RecordingSweep(refusing: [projectTask.id])
        let finished = modelContext.deleteArea(area, sweepTasks: sweep.sweep)

        #expect(finished == false)
        #expect(
            sweep.sweptIDs == [[areaTask.id], [projectTask.id]],
            "the area's own sweep and the nested project's sweep did not both run"
        )
        #expect(
            !areaLink.isDeleted,
            "the area dropped its goal link on the way out of a cascade it could not finish"
        )
        #expect(!area.isDeleted)
        #expect(!project.isDeleted)
        #expect(!modelContext.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<GoalListLink>()).count == 1)
    }

    /// Non-vacuity for both of the above: moving the link delete after the guard did not stop it
    /// deleting them. A successful cascade still takes the links, and leaves the goal itself.
    @Test func aCommittedProjectDeleteStillTakesItsGoalLinks() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let goal = Goal(title: "Ship v2")
        let project = Project(name: "Launch")
        let task = AppTask(title: "Write the release notes")
        task.project = project
        modelContext.insert(goal)
        modelContext.insert(project)
        modelContext.insert(task)
        try modelContext.save()
        _ = modelContext.attachList(.project(project), to: goal)
        try modelContext.save()
        #expect(try modelContext.fetch(FetchDescriptor<GoalListLink>()).count == 1)

        try CadencePendingChangePersistence.commitCascade(in: modelContext) {
            modelContext.deleteProject(project)
        }

        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<GoalListLink>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<AppTask>()).isEmpty)
        #expect(try store.fetch(FetchDescriptor<Goal>()).map(\.title) == ["Ship v2"])
    }

    // MARK: - The discarded return value

    /// The deeper half of T-291. The cascade said it could not finish; the surface saved anyway.
    ///
    /// `commitCascade` is where that pairing now lives, so a `false` return is rolled back rather
    /// than committed — and the surface gets a thrown error instead of silence.
    @Test func aCascadeThatCannotFinishIsRolledBackRatherThanSaved() throws {
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let goal = Goal(title: "Ship v2")
        let area = Area(name: "Operations")
        let project = Project(name: "Launch", area: area)
        let areaTask = AppTask(title: "Renew the domain")
        areaTask.area = area
        let projectTask = AppTask(title: "Write the release notes")
        projectTask.project = project
        let note = Note(kind: .list, title: "Runbook")
        note.area = area
        modelContext.insert(goal)
        modelContext.insert(area)
        modelContext.insert(project)
        modelContext.insert(areaTask)
        modelContext.insert(projectTask)
        modelContext.insert(note)
        try modelContext.save()
        _ = modelContext.attachList(.area(area), to: goal)
        try modelContext.save()

        let sweep = RecordingSweep(refusing: [projectTask.id])
        #expect(throws: CadencePendingChangePersistence.CascadeIncomplete.self) {
            try CadencePendingChangePersistence.commitCascade(in: modelContext) {
                modelContext.deleteArea(area, sweepTasks: sweep.sweep)
            }
        }

        #expect(!modelContext.hasChanges, "the half-built cascade is still pending")
        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Area>()).map(\.name) == ["Operations"])
        #expect(try store.fetch(FetchDescriptor<Project>()).map(\.name) == ["Launch"])
        #expect(try store.fetch(FetchDescriptor<AppTask>()).count == 2)
        #expect(try store.fetch(FetchDescriptor<Note>()).map(\.title) == ["Runbook"])
        #expect(try store.fetch(FetchDescriptor<GoalListLink>()).count == 1)
    }

    /// The other refusal a surface has to survive: the cascade finished, and the **commit** was
    /// refused. This is the one that used to be partly uncommittable — the task sweep saved
    /// part-way through, so the tasks stayed deleted while everything else came back. With
    /// `commitsImmediately: false` the whole tree is one pending change, which is what lets
    /// `deleteFailureNotice` say "Nothing was removed".
    @Test func aRefusedCommitRestoresTheWholeTreeIncludingItsTasks() throws {
        struct CommitRefused: Error {}
        let container = try CadenceModelContainerFactory.makeInMemoryContainer()
        let modelContext = ModelContext(container)
        let goal = Goal(title: "Ship v2")
        let area = Area(name: "Operations")
        let task = AppTask(title: "Renew the domain")
        task.area = area
        modelContext.insert(goal)
        modelContext.insert(area)
        modelContext.insert(task)
        try modelContext.save()
        _ = modelContext.attachList(.area(area), to: goal)
        try modelContext.save()

        #expect(throws: CommitRefused.self) {
            try CadencePendingChangePersistence.commitCascade(
                in: modelContext,
                commit: { _ in throw CommitRefused() },
                cascade: { modelContext.deleteArea(area) }
            )
        }

        #expect(!modelContext.hasChanges)
        let store = ModelContext(container)
        #expect(try store.fetch(FetchDescriptor<Area>()).map(\.name) == ["Operations"])
        #expect(
            try store.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Renew the domain"],
            "the task sweep committed mid-cascade again — the notice can no longer say nothing was removed"
        )
        #expect(try store.fetch(FetchDescriptor<GoalListLink>()).count == 1)
        #expect(try modelContext.fetch(FetchDescriptor<AppTask>()).map(\.title) == ["Renew the domain"])
    }

    // MARK: - The surfaces

    /// No surface calls a cascade and then saves over its answer.
    ///
    /// Scoped to the delete functions themselves, because all three files legitimately keep
    /// `try? modelContext.save()` elsewhere — reordering, reopening, and the editors' own field
    /// edits. A file-wide absence check would be pinning the wrong thing.
    @Test func noListDeleteSurfaceSavesOverTheCascadesAnswer() throws {
        let sites: [(path: String, functions: [String])] = [
            ("Cadence/macOS/Sheets/EditListSheet.swift", ["deleteArea", "deleteProject"]),
            ("Cadence/macOS/Views/SettingsView.swift", ["report"]),
            ("Cadence/iOS/iOSListDeletionSupport.swift", ["perform"])
        ]

        for site in sites {
            let raw = try CadenceSourceScan.sourceFile(site.path)
            #expect(raw.count > 400, "\(site.path) read as \(raw.count) characters")
            let stripped = CadenceSourceScan.strippingComments(raw)
            #expect(stripped != raw, "\(site.path): the comment stripper removed nothing")
            #expect(stripped.count == raw.count, "\(site.path): the stripper changed the length")

            for name in site.functions {
                let body = try #require(
                    CadenceSourceScan.functionBody(named: name, in: stripped),
                    "\(site.path) has no \(name)()"
                )
                #expect(
                    body.contains("CadencePendingChangePersistence.commitCascade("),
                    "\(site.path): \(name)() does not pair the cascade with its commit"
                )
                #expect(
                    CadenceSourceScan.matchCount(#"try\?"#, in: body) == 0,
                    "\(site.path): \(name)() still swallows a save over the cascade"
                )
            }
        }
    }

    /// macOS reports the failure rather than dismissing through it, which is the half of T-291 the
    /// iOS confirmation already had. Both editor sheets and the settings page hold the same
    /// sentence the iOS sheet shows.
    @Test func theMacOSDeleteSurfacesShowTheFailureNotice() throws {
        for path in [
            "Cadence/macOS/Sheets/EditListSheet.swift",
            "Cadence/macOS/Views/SettingsView.swift"
        ] {
            let stripped = CadenceSourceScan.strippingComments(try CadenceSourceScan.sourceFile(path))
            #expect(
                stripped.contains("@State private var deleteFailureNotice: String?"),
                "\(path) has nowhere to put a failure"
            )
            #expect(
                stripped.contains("CadenceInlineFailureNotice(text: deleteFailureNotice)"),
                "\(path) holds a failure it never draws"
            )
            #expect(
                CadenceSourceScan.matchCount(
                    #"deleteFailureNotice = (CadenceListDeletionKind\.\w+|kind)\.deleteFailureNotice"#,
                    in: stripped
                ) >= 1,
                "\(path) never sets the notice from the shared sentence"
            )
        }

        // Settings names the kind once, in the helper the three deletes funnel through, rather
        // than three times at three call sites.
        let settings = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsView.swift")
        )
        #expect(settings.contains("private func report(_ kind: CadenceListDeletionKind, cascade: () -> Bool)"))
        #expect(
            CadenceSourceScan.matchCount(#"deleteFailureNotice = kind\.deleteFailureNotice"#, in: settings) == 1,
            "Settings sets the notice from somewhere other than the one helper"
        )
        for spelling in ["report(.area)", "report(.project)", "report(.context)"] {
            #expect(settings.contains(spelling), "Settings' \(spelling) delete does not report")
        }

        // The editor sheet only closes on the success path; the failure returns before `dismiss()`.
        let sheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/EditListSheet.swift")
        )
        for name in ["deleteArea", "deleteProject"] {
            let body = try #require(CadenceSourceScan.functionBody(named: name, in: sheet))
            let failure = try #require(
                body.range(of: "deleteFailureNotice = CadenceListDeletionKind"),
                "\(name)(): no failure branch"
            )
            let dismissal = try #require(body.range(of: "dismiss()"), "\(name)(): never closes")
            #expect(
                dismissal.lowerBound > failure.upperBound,
                "\(name)(): the sheet closes on the failure path too"
            )
            // Position alone is not control flow: the notice has to `return` out, or the very next
            // statements run anyway and the sheet dismisses over the failure it just set.
            #expect(
                CadenceSourceScan.matchCount(
                    #"deleteFailureNotice = CadenceListDeletionKind\.\w+\.deleteFailureNotice\s*return"#,
                    in: body
                ) == 1,
                "\(name)(): the failure branch falls through to the dismissal"
            )
        }
    }

    /// Non-vacuity for the scans above, and the self-check the regex needle needs.
    @Test func theSourceScanActuallyReadsTheListDeleteSurfaces() throws {
        let sheet = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Sheets/EditListSheet.swift")
        )
        #expect(sheet.contains("struct EditAreaSheet: View"))
        #expect(sheet.contains("modelContext.deleteArea(area)"))

        let settings = CadenceSourceScan.strippingComments(
            try CadenceSourceScan.sourceFile("Cadence/macOS/Views/SettingsView.swift")
        )
        #expect(settings.contains("struct SettingsView: View"))
        #expect(settings.contains("modelContext.deleteContext(context)"))
        #expect(
            CadenceSourceScan.matchCount(#"try\?"#, in: settings) > 0,
            "SettingsView has no try? left, so the scoped absence checks prove nothing"
        )

        let needle = #"deleteFailureNotice = CadenceListDeletionKind\.\w+\.deleteFailureNotice"#
        #expect(
            CadenceSourceScan.matchCount(
                needle,
                in: "deleteFailureNotice = CadenceListDeletionKind.area.deleteFailureNotice"
            ) == 1,
            "the needle does not match the spelling it is hunting"
        )
        #expect(
            CadenceSourceScan.matchCount(needle, in: "deleteFailureNotice = nil") == 0,
            "the needle matches the reset as well as the assignment"
        )

        let shared = #"deleteFailureNotice = (CadenceListDeletionKind\.\w+|kind)\.deleteFailureNotice"#
        #expect(
            CadenceSourceScan.matchCount(shared, in: "deleteFailureNotice = kind.deleteFailureNotice") == 1,
            "the shared-sentence needle misses the Settings spelling"
        )
        #expect(
            CadenceSourceScan.matchCount(
                shared,
                in: "deleteFailureNotice = \"Couldn't delete this area. Nothing was removed.\""
            ) == 0,
            "the shared-sentence needle matches a hand-written copy of the sentence"
        )

        let returning = #"deleteFailureNotice = CadenceListDeletionKind\.\w+\.deleteFailureNotice\s*return"#
        #expect(
            CadenceSourceScan.matchCount(
                returning,
                in: "deleteFailureNotice = CadenceListDeletionKind.area.deleteFailureNotice\n            return"
            ) == 1,
            "the return needle does not match the spelling it is hunting"
        )
        #expect(
            CadenceSourceScan.matchCount(
                returning,
                in: "deleteFailureNotice = CadenceListDeletionKind.area.deleteFailureNotice\n        }\n        dismiss()"
            ) == 0,
            "the return needle matches a failure branch that falls through"
        )
    }
}
