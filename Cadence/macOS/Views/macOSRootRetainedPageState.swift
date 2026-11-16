#if os(macOS)
import Observation
import SwiftUI

/// Page state that outlives `macOSRootView.refreshAppData()`'s rebuild ([[T-18162]]).
///
/// `refreshAppData()` swaps the model context and bumps `dataRefreshID`, the `.id()` on the main
/// shell, and that rebuild is load-bearing: it is what stops any view's `@State` from holding a
/// model object out of the retired context, where a write would be lost in silence ([[T-3098]]).
/// The cost was every *value* the owner had picked as well -- the Notes tab and the note open in
/// it, the Settings category, the Calendar month -- reset to its default on every MCP tool call
/// and every desktop-widget tick.
///
/// So the store holds **values only, never model objects** (an id, an enum, an index): a value
/// means the same thing in either context, which is the whole reason it is safe to carry across.
/// It is owned by `macOSRootView` above the `.id()`, so the rebuild does not reach it.
///
/// Values are kept per root page (`scope`): the root drops a page's scope when the sidebar
/// selection leaves it, so navigating away and back still opens the page on its defaults, exactly
/// as it did before. Only a rebuild in place keeps them.
@MainActor
final class macOSRootRetainedPageState {
    /// One retained value. Observable per key, so a write re-renders that key's readers only.
    @MainActor @Observable
    final class Box {
        /// Wrapped, so a stored `nil` of an optional value reads back as that `nil` rather than
        /// as "never set".
        struct Stored { let value: Any }
        var stored: Stored?
    }

    private var boxes: [String: Box] = [:]

    /// The box for `key` in `scope`, made on first ask. Making one mutates nothing observed, so it
    /// is safe from a `body` read.
    func box(for key: String, in scope: String) -> Box {
        let composite = Self.compositeKey(key, in: scope)
        if let box = boxes[composite] { return box }
        let box = Box()
        boxes[composite] = box
        return box
    }

    /// Forgets every value `scope` holds whose key starts with `keyPrefix` (all of them for "").
    func removeValues(in scope: String, keyPrefix: String = "") {
        let prefix = Self.compositeKey(keyPrefix, in: scope)
        boxes = boxes.filter { !$0.key.hasPrefix(prefix) }
    }

    var storedKeyCount: Int { boxes.count }

    /// The scope a root sidebar selection keeps its pages' values under.
    nonisolated static func scope(for selection: SidebarItem?) -> String {
        selection.map { String(describing: $0) } ?? "none"
    }

    private nonisolated static func compositeKey(_ key: String, in scope: String) -> String {
        "\(scope)\u{1F}\(key)"
    }
}

/// What a page reads its retained values through: the root's store and the scope of the page the
/// root is showing. `nil` outside `macOSRootView` (a preview, a hosted test probe), where
/// `@RootRetained` behaves exactly like `@State`.
struct macOSRootRetainedPageScope {
    let store: macOSRootRetainedPageState
    let scope: String

    @MainActor
    func box(for key: String) -> macOSRootRetainedPageState.Box {
        store.box(for: key, in: scope)
    }

    @MainActor
    func removeValues(keyPrefix: String) {
        store.removeValues(in: scope, keyPrefix: keyPrefix)
    }
}

extension EnvironmentValues {
    @Entry var cadenceRootRetainedPageScope: macOSRootRetainedPageScope? = nil
}

/// `@State` for a page value that must survive the root's data-refresh rebuild ([[T-18162]]).
/// Value types only -- see `macOSRootRetainedPageState` for why a model object never goes here.
@MainActor @propertyWrapper
struct RootRetained<Value>: DynamicProperty {
    @Environment(\.cadenceRootRetainedPageScope) private var retainedScope
    /// Used when no root store is in the environment, which makes the wrapper plain `@State`.
    @State private var localBox = macOSRootRetainedPageState.Box()
    private let key: String
    private let initialValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.initialValue = wrappedValue
    }

    private var box: macOSRootRetainedPageState.Box {
        retainedScope?.box(for: key) ?? localBox
    }

    var wrappedValue: Value {
        get { (box.stored?.value as? Value) ?? initialValue }
        nonmutating set { box.stored = .init(value: newValue) }
    }

    var projectedValue: Binding<Value> {
        let box = box
        let initialValue = initialValue
        return Binding(
            get: { (box.stored?.value as? Value) ?? initialValue },
            set: { box.stored = .init(value: $0) }
        )
    }
}
#endif
