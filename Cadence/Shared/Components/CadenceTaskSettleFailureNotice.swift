import SwiftUI

/// A presented surface saying a refused settle **itself**, so that the shell does not dismiss it in
/// order to say the same sentence — [[T-642]].
///
/// **The defect, driven rather than reasoned.** On an iPhone 17 Pro (iOS 26.5), against a build
/// whose `CadenceTaskStatusEditing.toggleCompletion` refuses every commit: ticking a task row's
/// circle on Today shows `iOSRootView`'s alert, which is correct and is the positive control.
/// Ticking the circle **inside `iOSTaskDetailSheet`** shows the *same* alert — on Today, with the
/// sheet gone. SwiftUI dismisses the presented sheet in order to present the root's alert and does
/// not bring it back, so the one moment the app has something to apologise for is the moment it
/// throws away what the user was doing.
///
/// **Two shapes were eliminated before this one.** A second `.alert` inside the sheet bound to the
/// same flag is *worse*, measured in a minimal app with the identical modifier order: the sheet is
/// still dismissed and neither alert renders, so the sentence is lost entirely. And leaving the
/// shell to say it "once the sheet is gone" is the defect restated. What is left is the shape
/// `TaskEmbedFieldEditorPopover` already uses for a refused field edit — an inline
/// `CadenceInlineFailureNotice` where the user is — plus a way for the shell to know to stay quiet,
/// which is `CadenceTaskSettleFailureCenter`'s claim stack.
///
/// **Applied to the sheet's whole content, not to the control.** The circle is drawn by
/// `iOSTaskEditorTitleCard` and the status well by `statusActionsSection`; a notice owned by either
/// would be missing from the other, which is the reasoning T-636(a) used to put the sentence at the
/// shell in the first place. One notice per *surface* is the smallest thing that keeps that
/// property while moving the sentence nearer.
///
/// The store is correct under all of this — `CadenceTaskMutationSupport.commitSettle` has already
/// put the status, the timestamp and the successor back before anything is recorded, so the circle
/// re-draws open on its own. This is a "where was I" fix, not a data one.
struct CadenceTaskSettleFailureNoticeModifier: ViewModifier {
    /// Stable for this surface's lifetime, which is what makes "the innermost claim" mean "the
    /// sheet on top" rather than "whichever body ran last".
    @State private var claim = UUID()

    private var centre: CadenceTaskSettleFailureCenter { .shared }

    func body(content: Content) -> some View {
        content
            // `safeAreaInset` rather than an overlay: the sentence must not sit on top of the field
            // the user is about to correct, and a sheet's content is a `ScrollView` that should be
            // able to scroll clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if centre.settleFailed, centre.ownsTheSentence(claim) {
                    // Dismissible, because there is no next attempt to clear it: a *successful*
                    // settle writes nothing to this centre, so the sentence would otherwise stay
                    // under a tick that has since landed.
                    CadenceInlineFailureNotice(text: CadencePendingChangePersistence.editFailureNotice) {
                        centre.clear()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.surface)
                }
            }
            .onAppear { centre.claimSentence(claim) }
            .onDisappear { centre.relinquishSentence(claim) }
    }
}

extension View {
    /// Marks this surface as the one that names a refused settle while it is on screen, and draws
    /// that sentence inside it.
    ///
    /// Apply it to a **presented** surface that can settle a task — a sheet, not a page. A page is
    /// not torn down by the shell's alert, so it has nothing to gain and would only move a sentence
    /// the shell says perfectly well.
    func cadenceSaysItsOwnTaskSettleFailure() -> some View {
        modifier(CadenceTaskSettleFailureNoticeModifier())
    }
}
