import Foundation

/// **What a list page says when the list it shows is not active** ([[T-17906]]).
///
/// Search reaches completed, archived, paused and canceled lists once a query is typed
/// (`CadenceListSearchSupport.isSearchable`), and the row it draws already names the status. The
/// page that row opens -- `iOSListDetailView` on iPhone and iPad, `ListDetailView` on the Mac --
/// used to draw exactly as an active list's does, so the status was forgotten one tap later. Both
/// pages now read this one decision, under [[T-8201]]:
///
/// - the header's eyebrow leads with `statusLabel`, the word the search row and Settings > Lists
///   already show (`CadenceListSearchLifecycle.statusLabel`);
/// - an inline notice offers `actionTitle`, the verb the Settings > Lists row offers for the same
///   list: "Unarchive" for an archived one (`CadenceListVocabularyCopy.unarchiveActionTitle`),
///   "Reopen" for a completed, paused or canceled one -- `ListLifecycleRow`'s own rule on both
///   platforms. The action itself is `CadenceSidebarLists.reopen`, the path Settings takes.
///
/// An active list gets no notice at all (`nil`), so its page is unchanged.
///
/// Whether an inactive list should still accept new tasks is an owner call recorded on its own
/// ledger entry; this type decides only what the page SAYS.
nonisolated struct CadenceInactiveListNotice: Equatable {
    let lifecycle: CadenceListSearchLifecycle

    /// The header eyebrow's word: "Completed", "Archived", "Paused" or "Canceled".
    var statusLabel: String { lifecycle.statusLabel }

    /// The notice's button: the Settings > Lists row's verb for this list.
    var actionTitle: String {
        lifecycle == .archived ? CadenceListVocabularyCopy.unarchiveActionTitle : "Reopen"
    }

    /// The notice's sentence. Every inactive list is left off the sidebar and All Tasks
    /// (`AppTask.isInActiveContainer`, `CadenceTaskQuerySupport.allTasksScope`), whatever its status.
    var message: String { Self.hiddenMessage }

    /// Settings > Lists tints a completed list's status green and every other inactive one amber
    /// (`ListLifecycleRow`); the notice keeps that pairing.
    var usesCompletedTint: Bool { lifecycle == .completed }

    static let hiddenMessage = "Hidden from the sidebar and All Tasks."

    /// `nil` for an active list: nothing to say.
    static func notice(for lifecycle: CadenceListSearchLifecycle) -> CadenceInactiveListNotice? {
        lifecycle.isActive ? nil : CadenceInactiveListNotice(lifecycle: lifecycle)
    }

    /// The page's list, area or project, through the one mapping Search and Settings use.
    static func notice(area: Area?, project: Project?) -> CadenceInactiveListNotice? {
        if let area { return notice(for: CadenceListSearchSupport.lifecycle(of: area)) }
        if let project { return notice(for: CadenceListSearchSupport.lifecycle(of: project)) }
        return nil
    }

    /// The header eyebrow for a page whose own eyebrow is `baseEyebrow` (iOS's context path; the
    /// Mac header has none). Active: unchanged. Inactive: the status word leads and the base
    /// eyebrow, if any, follows as the eyebrow's detail clause.
    static func eyebrow(
        baseEyebrow: String?,
        notice: CadenceInactiveListNotice?
    ) -> (eyebrow: String?, detail: String?) {
        guard let notice else { return (baseEyebrow, nil) }
        let base = baseEyebrow?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (notice.statusLabel, base.isEmpty ? nil : base)
    }

    /// Brings the list back as Settings > Lists does: `CadenceSidebarLists.reopen`, which also
    /// keeps its sidebar section's order ([[T-16658]]). The caller commits. Main-actor, as
    /// `CadenceSidebarLists.reopen` is.
    @MainActor
    static func reopen(area: Area?, project: Project?) {
        if let area { CadenceSidebarLists.reopen(area) }
        else if let project { CadenceSidebarLists.reopen(project) }
    }
}
