#if os(macOS)
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Data Safety on the Mac: the route *back in*.
///
/// The exporter has shipped since T-19 and the engine that reads its file since T-274; between them
/// there was no control, so a user with an archive and a wiped store could not use it. This is that
/// control, and it is deliberately the same shape as `SettingsDataExportCard` directly above it —
/// same card, same tile, same trailing button — because keeping a copy and reading one back are the
/// two halves of one promise.
///
/// Every word it draws is `CadenceArchiveImportPresentation`'s and every decision about *when the
/// store is touched* is `CadenceArchiveImportFlow`'s, so iOS's section cannot come to describe a
/// different operation or write at a different moment. What is left here is chrome.
///
/// **Nothing is written until the preview is confirmed.** Choosing a file reads, decodes and fully
/// validates it and then shows what it would do; the store is untouched until **Import**.
struct SettingsArchiveImportCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var flow = CadenceArchiveImportFlow()
    @State private var isChoosingFile = false

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.blue.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "square.and.arrow.down.on.square.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.blue)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(CadenceArchiveImportPresentation.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(CadenceArchiveImportPresentation.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let statusMessage = flow.statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                SettingsActionButton(tone: .tinted(Theme.blue)) {
                    isChoosingFile = true
                } label: {
                    Label(CadenceArchiveImportPresentation.buttonTitle, systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
            flow.preview(result, in: modelContext.container)
        }
        .sheet(isPresented: previewBinding) {
            if let plan = flow.plan {
                SettingsArchiveImportPreviewSheet(
                    plan: plan,
                    mode: $flow.mode,
                    isWriting: flow.isWriting,
                    onCancel: { flow.cancel() },
                    onConfirm: { flow.confirm() }
                )
            }
        }
    }

    /// The sheet is presented by the flow's own state, so dismissing it by any route — Escape,
    /// click-away, the Cancel button — drops the archive rather than leaving one this flow would
    /// still import.
    private var previewBinding: Binding<Bool> {
        Binding(
            get: { flow.isPreviewing },
            set: { if !$0 { flow.cancel() } }
        )
    }
}

/// What the file would do, before it does it.
///
/// The mode picker is inside this sheet rather than on the card because the choice only means
/// something against a set of counts: "Overwrite what matches" over an archive that matches nothing
/// is the same import as "Add what's missing", and the numbers are what say so.
private struct SettingsArchiveImportPreviewSheet: View {
    let plan: CadenceArchiveImportPlan
    @Binding var mode: CadenceArchiveImportMode
    let isWriting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var isChoosingMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionEyebrowLabel(text: CadenceArchiveImportPresentation.title)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 14) {
                SettingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text(CadenceArchiveImportPresentation.modeQuestion)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.text)

                            Spacer(minLength: 12)

                            // The app's one "pick one of these", not `Picker(.segmented)` — see
                            // `CadenceArchiveImportPresentation.modeRows()` for why, and
                            // `SettingsCalendarWorkHoursSection` for the same swap made first.
                            CadenceChoiceValueButton(
                                title: CadenceArchiveImportPresentation.modeTitle(mode),
                                color: Theme.blue,
                                minHeight: CadenceSettingsRowMetrics.rowHeight
                            ) {
                                isChoosingMode = true
                            }
                            .popover(isPresented: $isChoosingMode) {
                                CadenceChoicePopoverList(
                                    rows: CadenceArchiveImportPresentation.modeRows(),
                                    selection: $mode,
                                    isPresented: $isChoosingMode,
                                    width: 320
                                )
                            }
                        }

                        Text(CadenceArchiveImportPresentation.modeExplanation(mode))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsCard {
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

                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                                        HStack(spacing: 12) {
                                            Text(line.title)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Theme.text)
                                            Spacer(minLength: 12)
                                            Text(line.detail)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Theme.dim)
                                        }
                                        .padding(.vertical, 6)
                                        if index < lines.count - 1 {
                                            CadenceRowDivider()
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 190)
                        }

                        if let note = CadenceArchiveImportPresentation.unreadableKindsNote(plan) {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // **T-1084.** Dim rather than amber: an archive's calendar links are not a
                        // kind of record this build cannot store, they are one whose meaning is
                        // local to the device that wrote them. Nothing is lost and nothing needs
                        // acting on, so it reads as a fact about the file and not as a warning.
                        if let note = CadenceArchiveImportPresentation.calendarLinksNote(plan) {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // The correction, above the button that acts on it. An import is not an undo, and
                // this is the last moment the reader can learn that from the app rather than from
                // the result.
                Text(CadenceArchiveImportPresentation.neverDeletesNote)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            CadenceRowDivider()

            HStack(spacing: 8) {
                Spacer(minLength: 12)
                CadenceActionButton(
                    title: CadenceArchiveImportPresentation.cancelButtonTitle,
                    role: .ghost,
                    size: .compact,
                    action: onCancel
                )
                CadenceActionButton(
                    title: CadenceArchiveImportPresentation.confirmButtonTitle,
                    systemImage: "square.and.arrow.down",
                    role: .primary,
                    size: .compact,
                    isDisabled: isWriting || !plan.changesAnything,
                    action: onConfirm
                )
            }
            .padding(16)
        }
        .frame(width: 480)
        .background(Theme.surface)
    }
}
#endif
