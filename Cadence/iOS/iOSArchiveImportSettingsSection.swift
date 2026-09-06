#if os(iOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Data Safety on iPhone and iPad: the route *back in*.
///
/// The phone has been able to write an archive since T-19 and has never been able to read one. That
/// asymmetry mattered more here than on the Mac: iOS has no backup list, no reveal-in-Finder and no
/// staged store restore, so a file chosen through the document picker is the only copy of a
/// Cadence store this platform can act on at all.
///
/// Every word is `CadenceArchiveImportPresentation`'s and every decision about when the store is
/// touched is `CadenceArchiveImportFlow`'s — the same two types `SettingsArchiveImportCard` reads.
/// The platforms differ in chrome and in nothing else, which is the property that stops one of them
/// quietly acquiring a second meaning for "import".
///
/// **Nothing is written until the preview is confirmed.** Choosing a file reads, decodes and fully
/// validates it and then shows what it would do; the store is untouched until **Import**.
struct iOSArchiveImportSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var flow = CadenceArchiveImportFlow()
    @State private var isChoosingFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Import")

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "square.and.arrow.down.on.square.fill",
                            color: Theme.blue,
                            size: 34,
                            iconSize: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(CadenceArchiveImportPresentation.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.text)

                            Text(CadenceArchiveImportPresentation.description)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            if let statusMessage = flow.statusMessage {
                                Text(statusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    iOSActionButton(
                        title: CadenceArchiveImportPresentation.buttonTitle,
                        systemImage: "square.and.arrow.down",
                        size: .compact,
                        tint: Theme.blue,
                        action: { isChoosingFile = true }
                    )
                }
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
            flow.preview(result, in: modelContext.container)
        }
        .sheet(isPresented: previewBinding) {
            if let plan = flow.plan {
                iOSArchiveImportPreviewSheet(
                    plan: plan,
                    mode: $flow.mode,
                    isWriting: flow.isWriting,
                    onCancel: { flow.cancel() },
                    onConfirm: { flow.confirm() }
                )
            }
        }
    }

    /// The sheet is presented by the flow's own state, so dismissing it by any route — the drag
    /// gesture included — drops the archive rather than leaving one this flow would still import.
    private var previewBinding: Binding<Bool> {
        Binding(
            get: { flow.isPreviewing },
            set: { if !$0 { flow.cancel() } }
        )
    }
}

/// What the file would do, before it does it.
private struct iOSArchiveImportPreviewSheet: View {
    let plan: CadenceArchiveImportPlan
    @Binding var mode: CadenceArchiveImportMode
    let isWriting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("", selection: $mode) {
                                ForEach(CadenceArchiveImportMode.allCases, id: \.self) { candidate in
                                    Text(CadenceArchiveImportPresentation.modeTitle(candidate)).tag(candidate)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Text(CadenceArchiveImportPresentation.modeExplanation(mode))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(CadenceArchiveImportPresentation.planSummary(plan))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)

                            let lines = CadenceArchiveImportPresentation.planLines(plan)
                            if !lines.isEmpty {
                                Text(CadenceArchiveImportPresentation.previewTitle)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.muted)

                                VStack(spacing: 0) {
                                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                        HStack(spacing: 12) {
                                            Text(line.title)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Theme.text)
                                            Spacer(minLength: 12)
                                            Text(line.detail)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Theme.subdued)
                                        }
                                        .padding(.vertical, 7)
                                        if index < lines.count - 1 {
                                            iOSRowDivider()
                                        }
                                    }
                                }
                            }

                            if let note = CadenceArchiveImportPresentation.unreadableKindsNote(plan) {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // The correction, above the button that acts on it. An import is not an undo,
                    // and this is the last moment the reader can learn that from the app rather
                    // than from the result.
                    Text(CadenceArchiveImportPresentation.neverDeletesNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    iOSActionButton(
                        title: CadenceArchiveImportPresentation.confirmButtonTitle,
                        systemImage: "square.and.arrow.down",
                        role: .primary,
                        size: .regular,
                        tint: Theme.blue,
                        fullWidth: true,
                        isDisabled: isWriting || !plan.changesAnything,
                        action: onConfirm
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(CadenceArchiveImportPresentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CadenceArchiveImportPresentation.cancelButtonTitle, action: onCancel)
                        .tint(Theme.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
