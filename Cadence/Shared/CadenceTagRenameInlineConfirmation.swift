import Foundation
import SwiftUI

/// **The one question a tag rename asks before it edits anybody's prose**, and the one place the
/// three rename editors get it from ([[T-6261]]).
///
/// A note carries a tag twice: in the frontmatter `tags:` line Cadence wrote, and — if the user
/// typed it — as an inline `#work` in the body. `TagSupport.rename` rewrites the first without
/// asking, because it is Cadence's own bookkeeping. The second is the user's sentence. Rewriting
/// it silently edits their words; leaving it silently splits the tag in two, because the next
/// `syncNoteTagsFromMarkdown` reads `#work` back and mints the old name again.
///
/// The owner's decision was neither: **warn, say how many notes it is, and let the user choose.**
/// Both answers are real. "Rewrite" keeps the tag one thing; "Leave Text Alone" accepts the split
/// knowingly. Cancel abandons the rename entirely.
///
/// There is no prompt for zero notes — `prompt(for:renamedTo:)` answers `nil` — and that is
/// structural rather than a check each editor remembers to make: a confirmation that appears on
/// every save is one the user learns to click through, and then it is not a confirmation.
nonisolated enum CadenceTagRenameInlineMentions {

    /// What one editor is waiting on: the names as the dialog will say them, and the real count.
    ///
    /// `newInlineName` is the text that will actually be written into the body
    /// (`TagSupport.inlineTagBody(for:)`), not the display name, so the dialog cannot promise a
    /// `#Day Job` that the body can never hold.
    struct Prompt: Equatable, Identifiable {
        let oldName: String
        let newInlineName: String
        let count: Int

        var id: String { "\(oldName)\u{2192}\(newInlineName)#\(count)" }
    }

    /// The prompt a rename of `tag` to `newName` needs, or `nil` when it needs none.
    ///
    /// `nil` means "save now, nothing in anyone's prose is affected" — either no note mentions the
    /// tag inline, or the rename does not move the slug and so cannot split anything.
    static func prompt(for tag: Tag, renamedTo newName: String) -> Prompt? {
        let count = TagSupport.inlineMentionCount(of: tag, renamedTo: newName)
        guard count > 0 else { return nil }
        return Prompt(
            oldName: tag.name,
            newInlineName: TagSupport.inlineTagBody(for: newName),
            count: count
        )
    }

    /// The title says what is being asked about, with both names in it, because the body of the
    /// dialog is where the consequence is argued and a title that said only "Are you sure?" would
    /// make the user read it to find out what it is about.
    static func title(for prompt: Prompt) -> String {
        "Rewrite #\(prompt.oldName) to #\(prompt.newInlineName) in note text?"
    }

    /// **The count is the whole point of this sentence**, so it leads, and both outcomes are named
    /// rather than only the one the buttons make sound safe. Singular and plural are spelled out
    /// because "1 notes mention" is the sort of thing an RC gets screenshotted for.
    static func message(for prompt: Prompt) -> String {
        let one = prompt.count == 1
        let subject = one
            ? "1 note mentions #\(prompt.oldName) in its text"
            : "\(prompt.count) notes mention #\(prompt.oldName) in their text"
        let object = one ? "it" : "them"
        let reread = one ? "that note is read" : "those notes are read"
        return "\(subject). Rewriting \(object) keeps this as one tag. Leaving \(object) alone "
            + "splits #\(prompt.oldName) back out as a separate tag the next time \(reread)."
    }

    static let confirmTitle = "Rewrite Mentions"
    static let declineTitle = "Leave Text Alone"
}

extension View {
    /// Presents the inline-mention confirmation and reports the answer.
    ///
    /// `onDecision(true)` is "rewrite the prose too"; `onDecision(false)` is "rename anyway and
    /// let the tag split". Cancelling calls neither, which leaves the draft open and the tag
    /// unchanged — the only one of the three that is not a rename.
    ///
    /// One modifier rather than three copies of the dialog: a rename that warns in Settings and
    /// splits silently in the tag picker would be worse than today's consistent split, and the
    /// three editors drifting apart is the specific way that happens.
    func cadenceTagRenameInlineConfirmation(
        _ prompt: Binding<CadenceTagRenameInlineMentions.Prompt?>,
        onDecision: @escaping (Bool) -> Void
    ) -> some View {
        confirmationDialog(
            prompt.wrappedValue.map(CadenceTagRenameInlineMentions.title(for:)) ?? "",
            isPresented: Binding(
                get: { prompt.wrappedValue != nil },
                set: { if !$0 { prompt.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: prompt.wrappedValue
        ) { _ in
            Button(CadenceTagRenameInlineMentions.confirmTitle) {
                prompt.wrappedValue = nil
                onDecision(true)
            }
            Button(CadenceTagRenameInlineMentions.declineTitle) {
                prompt.wrappedValue = nil
                onDecision(false)
            }
            Button("Cancel", role: .cancel) {
                prompt.wrappedValue = nil
            }
        } message: { pending in
            Text(CadenceTagRenameInlineMentions.message(for: pending))
        }
    }
}
