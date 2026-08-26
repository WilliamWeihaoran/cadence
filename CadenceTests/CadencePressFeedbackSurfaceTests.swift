import Foundation
import Testing
@testable import Cadence

// MARK: - T-289: iOS does not wear macOS's hover wash

/// **`.cadencePlain` is a hover style, and touch has no hover.**
///
/// `CadencePlainButtonStyle` paints a `Theme.blue` fill and stroke at radius 10, keyed on a
/// `CadenceHoverTracking` modifier whose `onHover` is `#if os(macOS)`-fenced. On iOS the tracking
/// never fires, so the only state that can reach the wash is `isPressed` — and the control lights
/// up as a blue rounded rectangle on touch, which no other iOS control draws. iOS's own press
/// feedback is `iOSPressableButtonStyle` (a 0.97 scale and a 0.62 dim), used 85 times across 37
/// files, and its own doc comment already calls itself "the press translation of macOS's
/// `.cadencePlain` hover wash".
///
/// **The ticket said two call sites; it is more than two, and that is why the fix is in the style.**
/// `iOSDateJumpTitle` held the only two spellings under `Cadence/iOS/`, but `.cadencePlain` is also
/// applied *unconditionally* by two shared components that iOS renders — `CadenceDatePicker` (its
/// trigger button plus `MonthCalendarPanel` and `CadenceQuickDatePopover`, reached from about ten
/// iOS call sites) and `EstimatePickerControl`, whose five call sites are **all** under
/// `Cadence/iOS/`. Fencing each caller would have been nine fences and would not have stopped the
/// tenth. So `CadencePlainButtonStyle` itself degrades to the platform's press feedback instead,
/// macOS untouched.
///
/// **Everything here is a source scan, and it has to be.** `CadenceTests` builds for macOS, where
/// `iOSPressableButtonStyle` does not exist (`iOSDesignSystem.swift` is a whole-file
/// `#if os(iOS)`), so the iOS branch of the style cannot be evaluated, never mind asserted on. The
/// assertions are therefore written as negatives over stripped source — the shape has to be absent
/// everywhere, which no amount of correct code elsewhere can satisfy.
@MainActor
struct CadencePressFeedbackSurfaceTests {

    /// No file under `Cadence/iOS/` applies macOS's hover style. Comments are stripped, because two
    /// files there explain *why* they do not use it and deleting the explanation is not the fix.
    @Test func noIOSSurfaceWearsTheHoverWash() throws {
        var scanned = 0
        var offenders: [String] = []

        for path in try pressFeedbackSwiftFiles(under: "Cadence/iOS") {
            scanned += 1
            let code = try pressFeedbackStrippingComments(pressFeedbackSourceFile(path))
            if code.contains("cadencePlain") { offenders.append(path) }
        }

        // Non-vacuity: `swiftFiles` returning [] on a path mistake is how a sweep like this passes
        // forever. The directory held 98 files when this was written.
        #expect(scanned > 80, "scanned only \(scanned) files under Cadence/iOS")
        #expect(
            offenders.isEmpty,
            "macOS hover style under Cadence/iOS: \(offenders.sorted().joined(separator: ", "))"
        )
    }

    /// The two sites the ticket named read iOS's style, and read it *by name* — the point being
    /// that a file under `Cadence/iOS/` should spell the iOS vocabulary even now that
    /// `.cadencePlain` would resolve to the same thing.
    @Test func theDateJumpTitleReadsTheIOSPressStyle() throws {
        let code = try pressFeedbackStrippingComments(
            pressFeedbackSourceFile("Cadence/iOS/iOSDateJumpTitle.swift")
        )
        #expect(code.contains("struct iOSDateJumpTitle"), "non-vacuity: still the date control's file")
        #expect(code.components(separatedBy: ".buttonStyle(.iosPressable)").count - 1 == 2)
        #expect(!code.contains("cadencePlain"))
    }

    /// The style's own body. The blue wash lives inside a macOS fence, and the other branch hands
    /// the configuration to iOS's press style rather than re-spelling 0.97 / 0.62 — the numbers
    /// being in one place is the reason `.iosPressable` and this branch cannot drift.
    @Test func theHoverWashIsFencedAndTouchGetsPressFeedback() throws {
        let code = try pressFeedbackStrippingComments(
            pressFeedbackSourceFile("Cadence/Shared/CadenceHoverStyles.swift")
        )
        #expect(code.contains("struct CadencePlainButtonBody"), "non-vacuity: still the style's file")

        // The wash is drawn once, and only under the fence.
        let body = try #require(code.range(of: "struct CadencePlainButtonBody"))
        let fenced = code[body.lowerBound...]
        let fenceStart = try #require(fenced.range(of: "#if os(macOS)"))
        let fenceElse = try #require(fenced.range(of: "#else"))
        let wash = try #require(fenced.range(of: "Theme.blue.opacity(backgroundOpacity)"))
        #expect(fenceStart.lowerBound < wash.lowerBound)
        #expect(wash.upperBound < fenceElse.lowerBound)

        // And the touch branch delegates rather than duplicating.
        #expect(code.contains("iOSPressableButtonStyle().makeBody(configuration: configuration)"))
        #expect(!code.contains("0.97"))
        #expect(!code.contains("0.62"))
    }

    /// The shared components that made this bigger than two sites still apply `.cadencePlain` —
    /// which is now correct on both platforms and is the whole point of fixing the style rather
    /// than the callers. Pinned so a later "cleanup" that fences these individually has to argue
    /// with a test rather than quietly reintroduce nine spellings of one platform check.
    @Test func theSharedPickersKeepOneUnfencedStyle() throws {
        for path in [
            "Cadence/Shared/Components/CadenceDatePicker.swift",
            "Cadence/Shared/Components/EstimatePickerControl.swift"
        ] {
            let code = try pressFeedbackStrippingComments(pressFeedbackSourceFile(path))
            #expect(code.contains(".buttonStyle(.cadencePlain)"), "\(path)")
            #expect(!code.contains("iosPressable"), "\(path) re-spells the platform split")
        }
    }
}

private func pressFeedbackRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func pressFeedbackSwiftFiles(under relativeDirectory: String) throws -> [String] {
    let directory = pressFeedbackRepositoryRoot().appendingPathComponent(relativeDirectory)
    guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { return [] }
    return enumerator.compactMap { element in
        guard let relativePath = element as? String, relativePath.hasSuffix(".swift") else { return nil }
        return "\(relativeDirectory)/\(relativePath)"
    }
}

private func pressFeedbackSourceFile(_ relativePath: String) throws -> String {
    try String(
        contentsOf: pressFeedbackRepositoryRoot().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

/// Blanks `//` and `/* */` comments so these assertions read code rather than the design notes this
/// repo keeps. Crude on purpose — a `//` inside a string literal is blanked too, which can only
/// make the checks stricter about what counts as a comment.
private func pressFeedbackStrippingComments(_ source: String) throws -> String {
    var result = source
    for pattern in ["//[^\n]*", "/\\*(?s:.)*?\\*/"] {
        while let range = result.range(of: pattern, options: .regularExpression) {
            result.replaceSubrange(
                range,
                with: String(repeating: " ", count: result.distance(from: range.lowerBound, to: range.upperBound))
            )
        }
    }
    return result
}
