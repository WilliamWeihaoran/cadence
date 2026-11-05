import Foundation
import Testing

@testable import Cadence

/// **[[T-11751]] — the iOS markdown editor must not change first responder inside a graph update.**
///
/// The defect this pins was a permanent hang, not a glitch. `iOSMarkdownEditor.updateUIView`
/// called `textView.resignFirstResponder()` straight from its body. UIKit answers that by walking
/// the responder chain asking each candidate `canBecomeFirstResponder`; inside the iPad Today
/// page's nested pane host that reaches `_UIHostingView.canBecomeFirstResponder`, which reads
/// `ViewGraphRootValueUpdater.responderNode` and re-enters the AttributeGraph update still on the
/// stack. AttributeGraph finds the cycle and spins forever in `print_cycle`: ~99% CPU, state `R`,
/// the sheet that dropped focus never draws, and every later touch and keystroke is lost. Measured
/// on `Cadence-iPadPro11` from the Notes pane's "Outline" and "Unlinked Mentions", whose actions
/// each set `isFocused = false` and raise a sheet in one turn. Reachable since 2026-05-27.
///
/// **These are source scans, and they are the right instrument here.** `Cadence/iOS/` is entirely
/// inside `#if os(iOS)` and this target builds for macOS, so no `UITextView` exists to measure
/// against; the thing that has to stay true is a property of *where the call sits*, which is
/// exactly what a scan can hold (`Cadence/Shared/AGENTS.md`, "Source-Scanning Tests"). The
/// behavioural proof is the screen: the recipe above, re-run after the fix, draws the sheet with
/// the app at ~0% CPU.
///
/// The scan is **transitive**, not a single-body needle count. A one-body check is blind to the
/// one edit most likely to reintroduce this — moving the call down into a helper that
/// `updateUIView` still reaches on every pass — which is the hole `cadenceFunctionBody`'s own note
/// warns about.
@Suite("iOS markdown editor graph-update safety")
struct CadenceMarkdownEditorGraphUpdateSafetyTests {
    private static let editorPath = "Cadence/iOS/iOSMarkdownEditor.swift"
    private static let responderNeedles = ["becomeFirstResponder()", "resignFirstResponder()"]

    private func editorSource() throws -> String {
        let source = CadenceSourceScan.codeOnly(try cadenceTestSource(Self.editorPath))
        // The vacuity guard: a read that returned nothing passes every "does not contain" below.
        #expect(source.count > 20_000, "\(Self.editorPath) read as \(source.count) code characters")
        return source
    }

    /// The seam itself. Nothing in `updateUIView`'s own body touches first responder.
    @Test("updateUIView never changes first responder in its own body")
    func updateUIViewDoesNotChangeFirstResponderDirectly() throws {
        let body = try cadenceFunctionBody(
            "func updateUIView(_ textView: UITextView, context: UIViewRepresentableContext<iOSMarkdownEditor>)",
            in: try editorSource()
        )
        for needle in Self.responderNeedles {
            #expect(!body.contains(needle), "updateUIView calls \(needle) synchronously -- [[T-11751]]")
        }
    }

    /// …and it still synchronizes focus, rather than having simply dropped the responsibility. A
    /// deferred resign that never fires is a worse bug than the synchronous one it replaced.
    @Test("updateUIView hands the first-responder change to the coordinator")
    func updateUIViewDelegatesTheFirstResponderChange() throws {
        let body = try cadenceFunctionBody(
            "func updateUIView(_ textView: UITextView, context: UIViewRepresentableContext<iOSMarkdownEditor>)",
            in: try editorSource()
        )
        #expect(
            body.contains("context.coordinator.synchronizeFirstResponder(of: textView, focused: isFocused)"),
            "updateUIView no longer synchronizes focus at all"
        )
    }

    /// The hop is load-bearing, so it is asserted as a hop: both responder calls sit **after** the
    /// `DispatchQueue.main.async` opening, and the function has no third one outside it.
    ///
    /// Written as an ordering relation rather than a count, because a `becomeFirstResponder()`
    /// moved above the hop would keep every count in this file unchanged and restore the hang.
    @Test("The coordinator performs the change off the graph update")
    func theCoordinatorDefersTheFirstResponderChange() throws {
        let body = try cadenceFunctionBody(
            "func synchronizeFirstResponder(of textView: UITextView, focused: Bool)",
            in: try editorSource()
        )
        let hop = try #require(
            body.range(of: "DispatchQueue.main.async"),
            "synchronizeFirstResponder no longer hops off the graph update -- [[T-11751]]"
        )
        for needle in Self.responderNeedles {
            let occurrences = body.ranges(of: needle)
            #expect(occurrences.count == 1, "\(needle) appears \(occurrences.count) times")
            for occurrence in occurrences {
                #expect(
                    hop.upperBound < occurrence.lowerBound,
                    "\(needle) runs before the main-queue hop, i.e. still inside the graph update"
                )
            }
        }
        // The desired state is re-read at fire time; several graph updates can run before the hop
        // and the host is allowed to change its mind in any of them.
        #expect(body.contains("self.parent.isFocused"), "the hop no longer re-reads the host's focus")
    }

    /// **The transitive half.** Every function `updateUIView` calls on its coordinator is read, and
    /// none of them may change first responder synchronously either — `synchronizeFirstResponder`
    /// excepted, which the test above holds to the stricter ordering rule.
    @Test("No helper reached from updateUIView changes first responder synchronously")
    func noHelperReachedFromUpdateUIViewChangesFirstResponder() throws {
        let source = try editorSource()
        let body = try cadenceFunctionBody(
            "func updateUIView(_ textView: UITextView, context: UIViewRepresentableContext<iOSMarkdownEditor>)",
            in: source
        )

        let called = try coordinatorCalls(in: body)
        #expect(called.count >= 4, "updateUIView reached only \(called.count) coordinator helpers: \(called)")
        #expect(called.contains("synchronizeFirstResponder"), "the focus synchronizer is not among \(called)")

        // `CadenceSourceScan.declarationBody` rather than `CadenceCommitSurfaceScan`'s
        // `declarationBody(named:)`: that one records an `#expect` of its own on a miss, which
        // would turn a helper this scan simply cannot resolve into a failure about the wrong thing.
        for name in called.sorted() where name != "synchronizeFirstResponder" {
            guard let helper = CadenceSourceScan.declarationBody("func \(name)(", in: source) else { continue }
            for needle in Self.responderNeedles {
                #expect(
                    !helper.contains(needle),
                    "\(name), reached from updateUIView on every pass, calls \(needle) -- [[T-11751]]"
                )
            }
        }
    }

    /// `context.coordinator.foo(` → `foo`, over one function body.
    private func coordinatorCalls(in body: String) throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"context\.coordinator\.([A-Za-z_][A-Za-z0-9_]*)\("#)
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var names: Set<String> = []
        for match in pattern.matches(in: body, range: range) {
            guard let captured = Range(match.range(at: 1), in: body) else { continue }
            names.insert(String(body[captured]))
        }
        return names
    }
}
