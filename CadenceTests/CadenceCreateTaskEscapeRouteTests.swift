import Testing
@testable import Cadence

#if os(macOS)
/// **[[T-16041]] and [[T-16043]]: what Escape does in the Mac composer.**
///
/// T-16041: with the Due panel open, Escape closed the whole composer and discarded the draft;
/// the same key on the Do panel closed only the panel. T-16043: the ⌃Space-opened composer took
/// two presses to close where the Cmd+N one took one. `CreateTaskEscapeRoute` is the decision the
/// composer's key monitor and its hidden `.cancelAction` button both apply.
///
/// **What this does NOT claim.** Which window AppKit hands the key to, and whether the monitor
/// sees the first press after ⌃Space, are not things a unit test can observe; the wiring is pinned
/// by source in `CadenceCreateTaskSheetEscapeTests`, and delivery is owed to a sighting.
struct CadenceCreateTaskEscapeRouteTests {
    @Test func escapeWithAPanelOpenClosesOnlyThePanel() {
        #expect(CreateTaskEscapeRoute.route(
            isEscape: true, isComposerWindow: true, hasOpenField: true, isComposingText: false
        ) == .closeField)
    }

    @Test func escapeWithNoPanelOpenClosesTheComposerOnTheFirstPress() {
        #expect(CreateTaskEscapeRoute.route(
            isEscape: true, isComposerWindow: true, hasOpenField: false, isComposingText: false
        ) == .dismissComposer)
    }

    /// Cancelling a Pinyin candidate must not discard the task.
    @Test func textBeingComposedKeepsItsEscape() {
        for hasOpenField in [false, true] {
            #expect(CreateTaskEscapeRoute.route(
                isEscape: true, isComposerWindow: true, hasOpenField: hasOpenField, isComposingText: true
            ) == .pass)
        }
    }

    /// The quick panel keeps its monitor alive while hidden, and an in-window composer can stand
    /// behind it: a key for another window is not this composer's.
    @Test func aKeyForAnotherWindowIsNotTheComposers() {
        for hasOpenField in [false, true] {
            #expect(CreateTaskEscapeRoute.route(
                isEscape: true, isComposerWindow: false, hasOpenField: hasOpenField, isComposingText: false
            ) == .pass)
        }
    }

    @Test func aKeyThatIsNotEscapeIsNotTheComposers() {
        for hasOpenField in [false, true] {
            #expect(CreateTaskEscapeRoute.route(
                isEscape: false, isComposerWindow: true, hasOpenField: hasOpenField, isComposingText: false
            ) == .pass)
        }
    }
}
#endif
