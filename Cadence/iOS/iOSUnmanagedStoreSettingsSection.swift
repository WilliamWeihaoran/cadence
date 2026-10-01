#if os(iOS)
import SwiftUI

/// Settings → Data Safety on iPhone and iPad: the store folders Cadence is **not** using.
///
/// **[[T-1841]].** [[T-1680]] gave the Mac this list and taught both of its reset sentences to
/// name what the reset leaves behind. iOS said the older thing — five items and a full stop — and
/// had no screen to point a reader at. The service layer never needed porting: everything this
/// view reads is in `Cadence/Services/PersistenceController.swift`, unfenced, and has compiled on
/// this platform all along. What was missing was a surface.
///
/// **The row carries no action at all, and that is a decision rather than an omission.** macOS's
/// `UnmanagedStoreDirectoryRow` takes `directory` and `onReveal` and nothing else, so a delete
/// cannot be handed to a path the app does not own. That rule survives the crossing; the **Reveal**
/// button does not. iOS ships no Files route into Cadence's container — there is no
/// `UIFileSharingEnabled` and no `LSSupportsOpeningDocumentsInPlace` in `Cadence/Info.plist` — so
/// a reveal here would have nowhere to go, and `NSWorkspace` does not exist to take it there. The
/// iOS row therefore takes `directory` and nothing else, which is the macOS structural rule in its
/// stronger form, and the copy says plainly that there is nowhere to go rather than borrowing a
/// Mac sentence that would be false here. Sharing the *row* would have meant parameterising the
/// one member that does not survive; sharing the *copy* that must not drift is
/// `CadenceUnmanagedStoreCopy`, and that is what is shared.
///
/// **There is no "Other Backup Folders" section here**, and that half of the ticket is refuted
/// rather than skipped. `StoreBackupManager` only ever writes into the **live** store directory's
/// own `Cadence Store Backups`, and `unmanagedBackupDirectories` excludes exactly that one by
/// construction; its other candidates are the legacy store locations, which on iOS resolve under
/// the app's own sandbox — `Library/Containers/…` cannot exist here at all, and nothing on this
/// platform has ever kept a store outside the app group. So the section could hold a row only if
/// iOS had once used a second store directory, and it has not. A permanently empty section is a
/// claim this screen cannot keep. Pinned by
/// `CadenceUnmanagedStoreDirectoryTests.theOnlyBackupRootAnIPhoneWritesIsTheOneTheListExcludes`.
///
/// One view for both size classes, like every other section on this screen: iPhone and iPad differ
/// in the width this is handed, not in how a card or a row inside it looks.
struct iOSUnmanagedStoreSettingsSection: View {
    @State private var directories: [UnmanagedStoreDirectory] = []

    var body: some View {
        Group {
            if !directories.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CadenceSettingsSectionLabel(text: CadenceUnmanagedStoreCopy.sectionTitle)

                    iOSSettingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.explanation)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 12)

                            ForEach(Array(directories.enumerated()), id: \.element.id) { index, directory in
                                iOSUnmanagedStoreDirectoryRow(directory: directory)
                                if index < directories.count - 1 {
                                    iOSRowDivider(leadingInset: iOSSettingsMetrics.rowTextInset)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    /// The two shared claims, then the one sentence that is this platform's own. See the type
    /// comment on `CadenceUnmanagedStoreCopy` for why the third is not shared.
    static let explanation =
        CadenceUnmanagedStoreCopy.whatTheyAre
        + " " + CadenceUnmanagedStoreCopy.whatCadenceDoesNotDo
        + " iOS has no Files route into Cadence's container, so unlike on a Mac there is nowhere to"
        + " go and remove them by hand; deleting Cadence from this device takes them with it."

    /// Read-only from end to end, which is a property of
    /// `StoreBackupManager.unmanagedStoreDirectories` rather than of this caller: it lists and
    /// sizes, and nothing on the path creates, moves or removes. It is the only call on this
    /// screen that reaches outside the store this launch has open, and one of the folders it
    /// reaches is the only copy of whatever a degraded launch recorded ([[T-1680]]).
    private func refresh() {
        directories = StoreBackupManager.unmanagedStoreDirectories()
    }
}

/// One folder of Cadence store files the app is not using, with the path that makes it nameable.
///
/// **One member, no action.** macOS's row is `directory` plus `onReveal`; this one drops the
/// second rather than stubbing it, for the reason in `iOSUnmanagedStoreSettingsSection`'s comment.
/// A row that cannot be handed an action cannot grow a destructive one by accident, which is the
/// rule [[T-1532]] and [[T-1680]] both enforce through the shape of the view rather than through a
/// convention somebody has to remember.
private struct iOSUnmanagedStoreDirectoryRow: View {
    let directory: UnmanagedStoreDirectory

    var body: some View {
        HStack(alignment: .top, spacing: iOSSettingsMetrics.glyphLabelSpacing) {
            iOSIconTile(
                systemImage: "internaldrive",
                color: Theme.dim,
                size: iOSSettingsMetrics.glyphSlot,
                iconSize: 13
            )

            VStack(alignment: .leading, spacing: 3) {
                // The path in full, for the reason macOS shows one: it is the only thing that
                // makes the folder nameable, and none of these are guessable. Selectable because
                // on a phone quoting it to someone is the only thing a reader can do with it.
                Text(directory.url.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // Kind, size and when a store file in it was last written — the shared string, so
                // the two platforms cannot come to describe the same folder differently.
                Text(directory.displayDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}
#endif
