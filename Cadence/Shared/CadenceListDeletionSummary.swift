import Foundation

/// Which cascade a delete confirmation is about to run.
///
/// The three sentences are the ones macOS's `confirmationDialog`s already showed, lifted here so
/// the two platforms cannot come to describe the same cascade differently. They are deliberately
/// *categorical* ("its tasks, projects, documents, and links") — `CadenceListDeletionSummary`
/// supplies the counts, and the two are shown together.
enum CadenceListDeletionKind: String, CaseIterable, Sendable {
    case area
    case project
    case context

    /// Title-cased, because every use is a button title or a sheet title.
    var noun: String {
        switch self {
        case .area: return "Area"
        case .project: return "Project"
        case .context: return "Context"
        }
    }

    /// Shown **inside** the still-open confirmation when the delete could not be completed
    /// (T-320). It names the kind for the same reason `cascadeSentence` does: the sheet is one
    /// view used for three deletes, and "Couldn't delete this list" is not a thing the app calls
    /// anything.
    ///
    /// **It says "Nothing was removed", and it is the same promise the note delete makes.** It did
    /// not always: `CadenceTaskMutationSupport.deleteTasks` used to commit with
    /// `try? modelContext.save()` part-way through the cascade, so a refused delete left the
    /// list's tasks gone from the store while the list itself came back, and this sentence had to
    /// hedge — "Couldn't finish… some of it may already be gone." T-291 made the cascade defer
    /// that commit (`commitsImmediately: false`), so the whole tree is now one pending change and
    /// one `rollback()` undoes all of it, whether the cascade aborted half-way or the commit was
    /// refused. `CadenceDeleteConfirmationCommitTests` measures the restored tree; if a commit
    /// ever creeps back inside the cascade, that test goes red *before* this sentence starts
    /// lying.
    ///
    /// The one thing rollback does not restore is a cancelled local notification, which the next
    /// reconcile re-schedules. "Nothing was removed" is about the user's data, and none of it is.
    var deleteFailureNotice: String {
        "Couldn't delete this \(noun.lowercased()). Nothing was removed."
    }

    var cascadeSentence: String {
        switch self {
        case .area:
            return "This permanently deletes the area and its tasks, projects, documents, and links."
        case .project:
            return "This permanently deletes the project and its tasks, documents, and links."
        case .context:
            return "This permanently deletes the context and all its areas, projects, tasks, milestones, and habits."
        }
    }
}

/// What a list delete is about to take with it, counted before the fact.
///
/// **Why counts at all.** Deleting an area is recursive — it takes its tasks, its list notes, its
/// links, its legacy documents *and its nested projects*, and a context takes every area and
/// project under it plus their goals and habits. macOS's confirmation names those *categories*;
/// it cannot tell you that this particular area is holding 140 tasks. The iOS confirmation shows
/// both, which is the one respect in which it is deliberately stronger than the desktop dialog.
///
/// **The counts mirror `ModelContext.deleteArea/deleteProject/deleteContext` exactly**, including
/// the two things a naive count would get wrong:
/// - notes are filtered to `.list` kind, because the cascade only deletes list notes; a daily or
///   permanent note attached to the list survives it.
/// - tasks are deduped by id, because an area's task set and its projects' task sets can name the
///   same row (and under a context, so can a goal's).
///
/// A summary that over-promised would be worse than no summary: the user would authorise the
/// deletion of work that is not actually going anywhere, or fail to authorise work that is.
struct CadenceListDeletionSummary: Equatable, Sendable {
    var tasks = 0
    var notes = 0
    var links = 0
    var projects = 0
    var areas = 0
    var goals = 0
    var habits = 0

    var isEmpty: Bool {
        tasks == 0 && notes == 0 && links == 0 && projects == 0 && areas == 0 && goals == 0 && habits == 0
    }

    /// One line per non-zero kind, in cascade order: the containers first, then the work inside
    /// them. Zero-count kinds are omitted rather than shown as "0 notes" — a list of zeroes reads
    /// as a form, and the thing the user needs to see is what is actually at stake.
    var lostItemLines: [String] {
        [
            Self.line(areas, "area", "areas"),
            Self.line(projects, "project", "projects"),
            Self.line(goals, "goal", "goals"),
            Self.line(habits, "habit", "habits"),
            Self.line(tasks, "task", "tasks"),
            Self.line(notes, "note", "notes"),
            Self.line(links, "saved link", "saved links")
        ].compactMap { $0 }
    }

    private static func line(_ count: Int, _ singular: String, _ plural: String) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : plural)"
    }

    static func forProject(_ project: Project) -> Self {
        var summary = Self()
        summary.tasks = uniqueCount(project.tasks ?? [], by: \.id)
        summary.notes = listNoteCount(project.notes ?? [])
        summary.links = uniqueCount(project.links ?? [], by: \.id)
        return summary
    }

    static func forArea(_ area: Area) -> Self {
        let projects = area.projects ?? []
        var summary = Self()
        summary.projects = uniqueCount(projects, by: \.id)
        summary.tasks = uniqueCount((area.tasks ?? []) + projects.flatMap { $0.tasks ?? [] }, by: \.id)
        summary.notes = listNoteCount((area.notes ?? []) + projects.flatMap { $0.notes ?? [] })
        summary.links = uniqueCount((area.links ?? []) + projects.flatMap { $0.links ?? [] }, by: \.id)
        return summary
    }

    static func forContext(_ context: Context) -> Self {
        let areas = context.areas ?? []
        let goals = context.goals ?? []
        let habits = context.habits ?? []
        // An area's projects and the context's own projects overlap in practice — a project has
        // both an `area` and a `context` — so this is one deduped set, exactly as the cascade
        // builds it.
        let projects = dedupe(areas.flatMap { $0.projects ?? [] } + (context.projects ?? []), by: \.id)

        var summary = Self()
        summary.areas = areas.count
        summary.projects = projects.count
        summary.goals = goals.count
        summary.habits = habits.count
        summary.tasks = uniqueCount(
            areas.flatMap { $0.tasks ?? [] }
                + projects.flatMap { $0.tasks ?? [] }
                + (context.tasks ?? [])
                + goals.flatMap { $0.tasks ?? [] },
            by: \.id
        )
        summary.notes = listNoteCount(areas.flatMap { $0.notes ?? [] } + projects.flatMap { $0.notes ?? [] })
        summary.links = uniqueCount(
            areas.flatMap { $0.links ?? [] } + projects.flatMap { $0.links ?? [] },
            by: \.id
        )
        return summary
    }

    private static func listNoteCount(_ notes: [Note]) -> Int {
        dedupe(notes, by: \.id).filter { $0.kind == .list }.count
    }

    private static func uniqueCount<T>(_ models: [T], by id: KeyPath<T, UUID>) -> Int {
        dedupe(models, by: id).count
    }

    private static func dedupe<T>(_ models: [T], by id: KeyPath<T, UUID>) -> [T] {
        var seen = Set<UUID>()
        return models.filter { seen.insert($0[keyPath: id]).inserted }
    }
}
