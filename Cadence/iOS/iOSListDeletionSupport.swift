#if os(iOS)
import SwiftData
import SwiftUI

/// The one thing an iOS delete confirmation can be about.
///
/// It carries the model object rather than an id because the confirmation needs the list's own
/// name, icon and `colorHex` to identify *which* list is going, and because the delete itself
/// takes the object.
enum iOSListDeletionTarget: Identifiable {
    case area(Area)
    case project(Project)
    case context(Context)

    var id: String {
        switch self {
        case .area(let area): return "area-\(area.id)"
        case .project(let project): return "project-\(project.id)"
        case .context(let context): return "context-\(context.id)"
        }
    }

    var kind: CadenceListDeletionKind {
        switch self {
        case .area: return .area
        case .project: return .project
        case .context: return .context
        }
    }

    /// The real name, or the same "Untitled …" fallback the settings rows use — a confirmation
    /// with a blank name in it does not say what is about to be deleted.
    var name: String {
        let raw: String
        switch self {
        case .area(let area): raw = area.name
        case .project(let project): raw = project.name
        case .context(let context): raw = context.name
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled \(kind.noun)" : raw
    }

    var icon: String {
        switch self {
        case .area(let area): return area.icon
        case .project(let project): return project.icon
        case .context(let context): return context.icon
        }
    }

    var colorHex: String {
        switch self {
        case .area(let area): return area.colorHex
        case .project(let project): return project.colorHex
        case .context(let context): return context.colorHex
        }
    }

    var summary: CadenceListDeletionSummary {
        switch self {
        case .area(let area): return .forArea(area)
        case .project(let project): return .forProject(project)
        case .context(let context): return .forContext(context)
        }
    }
}

extension View {
    /// Attaches the one list-delete confirmation and the one delete call site.
    ///
    /// Every iOS surface that offers a delete — the Lists page on iPhone, the same page's iPad
    /// pane, Settings → Lists, Settings → Contexts — sets this binding and nothing else. The
    /// cascade is reached from exactly one place in `Cadence/iOS/`, which is the property
    /// `CadenceListDeletionSurfaceTests` pins.
    func iOSListDeletion(target: Binding<iOSListDeletionTarget?>) -> some View {
        modifier(iOSListDeletionModifier(target: target))
    }
}

private struct iOSListDeletionModifier: ViewModifier {
    @Binding var target: iOSListDeletionTarget?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.sheet(item: $target) { target in
            iOSListDeleteConfirmationSheet(target: target) { perform(target) }
        }
    }

    /// The shared cascades, called and not re-implemented. `ModelContext.deleteArea` recurses into
    /// nested projects; `deleteContext` recurses into everything under the context.
    private func perform(_ target: iOSListDeletionTarget) {
        switch target {
        case .area(let area):
            modelContext.deleteArea(area)
        case .project(let project):
            modelContext.deleteProject(project)
        case .context(let context):
            modelContext.deleteContext(context)
        }
        try? modelContext.save()
    }
}

/// The destructive menu row, so the four call sites cannot spell the title or the glyph
/// differently from each other.
struct iOSListDeleteMenuButton: View {
    let target: iOSListDeletionTarget
    let request: (iOSListDeletionTarget) -> Void

    var body: some View {
        Button(role: .destructive) {
            request(target)
        } label: {
            Label("Delete \(target.kind.noun)", systemImage: "trash")
        }
    }
}

/// The confirmation. One view for iPhone and iPad — they differ in the width it is handed, not in
/// what it says or how it is armed.
///
/// **Why a modal sheet and not a `confirmationDialog`.** macOS gates these deletes behind a
/// window-modal dialog. The literal iOS translation of that is a bottom action sheet, i.e. one
/// thumb-reachable tap under the finger that just long-pressed the row — strictly *weaker* than
/// the desktop bar for an irreversible recursive delete. `iOSDataResetSettingsSection` solved the
/// same problem by keeping the destructive control off the originating screen entirely, and that is
/// what this does: the row's menu only *presents*; the button that deletes exists only inside a
/// modal you have to read past, with Cancel in the navigation bar and the destructive button at the
/// bottom of the content rather than under the thumb.
///
/// **Why no typed phrase.** The privacy reset requires typing `DELETE` because it is
/// unrecoverable and total — there is no scope to report, so friction is the only signal
/// available. A list delete is scoped, and the scope is knowable: the enumeration below says
/// exactly how many tasks, notes, links and nested projects go with it. Counting is the stronger
/// signal here, and a typed phrase on a routine cleanup is friction users learn to type without
/// reading. So this confirmation is *more* informative than macOS's and no more ceremonious.
struct iOSListDeleteConfirmationSheet: View {
    let target: iOSListDeletionTarget
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var summary: CadenceListDeletionSummary {
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
                                    systemImage: "exclamationmark.triangle.fill",
                                    color: Theme.red,
                                    size: 34,
                                    iconSize: 16
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This cannot be undone")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.text)

                                    Text(target.kind.cascadeSentence)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.subdued)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }

                            iOSRowDivider()

                            Text("Cadence syncs through your private iCloud database, so this deletion reaches your other devices.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    CadenceSettingsSectionLabel(text: "What Goes With It")

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

                            if summary.isEmpty {
                                Text("Nothing else is filed under this \(target.kind.noun.lowercased()) — no tasks, notes or saved links will be lost.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.subdued)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                VStack(alignment: .leading, spacing: 7) {
                                    ForEach(summary.lostItemLines, id: \.self) { line in
                                        HStack(spacing: 8) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(Theme.red)

                                            Text(line)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(Theme.text)

                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    iOSActionButton(
                        title: "Delete \(target.kind.noun)",
                        systemImage: "trash.fill",
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
            .navigationTitle("Delete \(target.kind.noun)")
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
