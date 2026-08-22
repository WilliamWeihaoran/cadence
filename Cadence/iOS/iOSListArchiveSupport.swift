#if os(iOS)
import SwiftData
import SwiftUI

/// The one thing an iOS archive confirmation can be about.
///
/// Areas and projects only — a context is not archivable from any iOS surface, and a kanban column
/// is archived by a toggle in the list editor rather than by an action on a row (`docs/TODO.md`
/// T-247). It carries the model object for the same reason `iOSListDeletionTarget` does: the
/// confirmation has to identify *which* list is going quiet, and the archive itself takes the
/// object.
enum iOSListArchiveTarget: Identifiable {
    case area(Area)
    case project(Project)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id)"
        case .project(let project): return "project-\(project.id)"
        }
    }

    /// Title-cased, because every use is a button title or a sheet title. Deliberately not read off
    /// `CadenceListDeletionKind` — that enum is the delete cascade's vocabulary and its third case
    /// (`context`) is not a thing this action can be about.
    var noun: String {
        switch self {
        case .area: return "Area"
        case .project: return "Project"
        }
    }

    /// The real name, or the same "Untitled …" fallback the delete confirmation uses — a
    /// confirmation with a blank name in it does not say what is about to be archived.
    var name: String {
        let raw: String
        switch self {
        case .area(let area): raw = area.name
        case .project(let project): raw = project.name
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled \(noun)" : raw
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        }
    }

    var colorHex: String {
        switch self {
        case .area(let area): return area.colorHex
        case .project(let project): return project.colorHex
        }
    }

    var summary: CadenceListArchiveSummary {
        switch self {
        case .area(let area): return .forArea(area)
        case .project(let project): return .forProject(project)
        }
    }
}

extension ModelContext {
    /// The one place iOS archives a list, and the reason T-215 exists.
    ///
    /// Archiving is a **wind-down**, not a status flip: macOS has cancelled the list's remaining
    /// active tasks since long before this file, through exactly this service, and iOS wrote
    /// `status = .archived` and nothing else — so the same list left different open work behind
    /// depending on which device the swipe happened on, and the Mac's All Tasks kept surfacing
    /// tasks the phone had "archived".
    ///
    /// `includingChildProjects: true` matches `EditAreaSheet.apply(_:)`. An area's child projects
    /// keep their own `status`, so their tasks are still reachable from All Tasks after the parent
    /// is filed away — which is precisely why the wind-down has to reach them.
    func archiveList(_ target: iOSListArchiveTarget) {
        switch target {
        case .area(let area):
            area.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(
                in: area,
                includingChildProjects: true,
                in: self
            )
        case .project(let project):
            project.status = .archived
            TaskContainerLifecycleService.cancelRemainingActiveTasks(in: project, in: self)
        }
        try? save()
    }
}

extension View {
    /// Attaches the one archive confirmation.
    ///
    /// Its host sets the binding only when `CadenceListArchiveSummary.requiresConfirmation` says
    /// the archive would cancel something; an empty list is archived on the spot. Both the iPhone
    /// list and the iPad pane route their swipe and their context menu through that one decision,
    /// so the two cannot answer it differently.
    func iOSListArchive(target: Binding<iOSListArchiveTarget?>) -> some View {
        modifier(iOSListArchiveModifier(target: target))
    }
}

private struct iOSListArchiveModifier: ViewModifier {
    @Binding var target: iOSListArchiveTarget?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            iOSListArchiveConfirmationSheet(target: target) {
                modelContext.archiveList(target)
            }
        }
    }
}

/// The confirmation. One view for iPhone and iPad — they differ in the width it is handed, not in
/// what it says or how it is armed.
///
/// **Why a confirmation at all, when macOS has none.** macOS's archive lives in the footer of an
/// edit sheet you had to open; iOS's is a row swipe and a long-press menu item. The cancellation
/// underneath them is identical, so the ceremony has to come from somewhere, and here it is the
/// only place it can. It is deliberately *conditional*: `requiresConfirmation` is false when the
/// list has no open work, and then the swipe just archives. A sheet that appears every time —
/// including over a list where the answer is "nothing happens" — is a sheet people learn to
/// dismiss without reading, which is the same argument the delete confirmation makes against a
/// typed phrase.
///
/// **Why no typed phrase here either.** Archiving is scoped, the scope is knowable, and it is
/// stated: N open tasks. The list itself is recoverable from Archived; what is not is the
/// cancellation, and saying so plainly is a better signal than making someone type a word.
struct iOSListArchiveConfirmationSheet: View {
    let target: iOSListArchiveTarget
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var summary: CadenceListArchiveSummary {
        target.summary
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                                iOSIconTile(
                                    systemImage: "archivebox.fill",
                                    color: Theme.amber,
                                    size: 34,
                                    iconSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Archiving settles what is left")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.text)

                                    Text("The \(target.noun.lowercased()) moves to Archived and can be restored from there. Restoring it does not reopen the work cancelled below.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.subdued)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }

                            iOSRowDivider()

                            Text("Cadence syncs through your private iCloud database, so this reaches your other devices.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    CadenceSettingsSectionLabel(text: "What Gets Cancelled")

                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                                iOSIconTile(
                                    systemImage: target.icon,
                                    color: Color(hex: target.colorHex),
                                    size: iOSSettingsMetrics.glyphSlot,
                                    iconSize: 15
                                )

                                Text(target.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(2)

                                Spacer(minLength: 0)
                            }

                            iOSRowDivider()

                            if let line = summary.settledLine {
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.red)

                                    Text(line)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Theme.text)

                                    Spacer(minLength: 0)
                                }
                            } else {
                                Text("Nothing is still open in this \(target.noun.lowercased()) — archiving it cancels no work.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subdued)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    iOSActionButton(
                        title: "Archive \(target.noun)",
                        systemImage: "archivebox.fill",
                        role: .destructive,
                        size: .regular,
                        fullWidth: true,
                        action: {
                            dismiss()
                            onConfirm()
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Archive \(target.noun)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .tint(Theme.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
