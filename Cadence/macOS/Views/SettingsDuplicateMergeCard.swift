#if os(macOS)
import SwiftData
import SwiftUI

/// Settings → Data Safety on the Mac: **Merge Duplicates** ([[T-6481]]).
///
/// The same shape as `SettingsDataExportCard` and `SettingsArchiveImportCard` above it — tile,
/// title, description, status line, trailing button — and every word and the sequence it runs are
/// `CadenceDuplicateMergePresentation`'s, which `iOSDuplicateMergeSettingsSection` reads too. What
/// is left here is chrome.
struct SettingsDuplicateMergeCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirming = false
    @State private var statusMessage: String?

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.purple.opacity(0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.purple)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(CadenceDuplicateMergePresentation.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(CadenceDuplicateMergePresentation.description)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                SettingsActionButton(tone: .tinted(Theme.purple)) {
                    isConfirming = true
                } label: {
                    Label(CadenceDuplicateMergePresentation.buttonTitle, systemImage: "arrow.triangle.merge")
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
