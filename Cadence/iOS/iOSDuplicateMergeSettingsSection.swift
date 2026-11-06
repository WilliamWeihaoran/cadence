#if os(iOS)
import SwiftData
import SwiftUI

/// Settings > Data Safety on iPhone and iPad: **Merge Duplicates** ([[T-6481]]).
///
/// The phone half of `SettingsDuplicateMergeCard`: the same words, the same confirmation and the
/// same sequence, all `CadenceDuplicateMergePresentation`'s, in this platform's card chrome — the
/// shape `iOSDataExportSettingsSection` and `iOSArchiveImportSettingsSection` above it take. One
/// view for both size classes: iPhone and iPad differ in the width this is handed, not in how the
/// card looks.
struct iOSDuplicateMergeSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirming = false
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CadenceSettingsSectionLabel(text: "Duplicates")

            iOSSettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
                        iOSIconTile(
                            systemImage: "square.on.square",
                            color: Theme.purple,
                            size: 34,
                            iconSize: 16
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(CadenceDuplicateMergePresentation.title)
                                .cadenceFont(.rowTitle, base: 15, weight: .semibold)
                                .foregroundStyle(Theme.text)

                            Text(CadenceDuplicateMergePresentation.description)
                                .cadenceFont(.metadata, base: 12, weight: .regular)
                                .foregroundStyle(Theme.subdued)
                                .fixedSize(horizontal: false, vertical: true)

                            if let statusMessage {
                                Text(statusMessage)
                                    .cadenceFont(.metadata, base: 11, weight: .regular)
                                    .foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    iOSActionButton(
                        title: CadenceDuplicateMergePresentation.buttonTitle,
                        systemImage: "arrow.triangle.merge",
                        size: .compact,
                        tint: Theme.purple,
                        action: { isConfirming = true }
                    )
                }
            }
        }
        .confirmationDialog(
            CadenceDuplicateMergePresentation.confirmationTitle,
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button(CadenceDuplicateMergePresentation.confirmButtonTitle, role: .destructive) {
                statusMessage = CadenceDuplicateMergePresentation.run(in: modelContext)
            }
            Button(CadenceDuplicateMergePresentation.cancelButtonTitle, role: .cancel) {}
        } message: {
            Text(CadenceDuplicateMergePresentation.confirmationMessage)
        }
    }
}
#endif
