import Observation

/// **A request to raise the search field, honoured once** ([[T-8791]]).
///
/// iPad Cmd+K ([[T-8766]]) landed on Search with the field unfocused, so a hardware-keyboard user
/// still had to tap before typing — the Mac's Cmd+K opens a palette ready to type. The fix is a
/// *request*, not focus-on-appear: Search reached from the sidebar or the More list must not raise
/// the soft keyboard on an iPhone unasked, so only the act that means "I am about to type" asks.
///
/// A generation counter rather than a `Bool`, so a second Cmd+K while Search is already up is a
/// change the view can observe, and `take()` so one request is honoured by exactly one appearance.
@Observable
final class CadenceSearchFocusRequest {
    /// Bumped by every request; the search screen observes it.
    private(set) var generation = 0
    /// The last generation a search screen honoured.
    @ObservationIgnored private var honoured = 0

    /// Ask the search screen to focus its field the next time it is on screen.
    func request() {
        generation += 1
    }

    /// Whether a request is outstanding; consumes it. `false` for every call after the first, so a
    /// later appearance reached some other way (a sidebar tap) does not focus the field.
    func take() -> Bool {
        guard honoured < generation else { return false }
        honoured = generation
        return true
    }
}
