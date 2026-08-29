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
    ///
    /// **Scoped to one function body, and it has to be.** The first version of this test sliced
    /// from `struct CadencePlainButtonBody` to the end of the file and asked `range(of:)` for the
    /// *first* wash. That found the fenced one and stopped, so adding a second `Theme.blue` wash
    /// to the `#else` branch — keeping the delegation, so every positive assertion still held —
    /// compiled on iOS and passed this suite. Both branches are now cut out of the body and
    /// asserted separately, and the paint is counted rather than located.
    @Test func theHoverWashIsFencedAndTouchGetsPressFeedback() throws {
        let raw = try pressFeedbackSourceFile("Cadence/Shared/CadenceHoverStyles.swift")
        let code = try pressFeedbackStrippingComments(raw)
        #expect(code.contains("struct CadencePlainButtonBody"), "non-vacuity: still the style's file")
        // The stripper ran, and it blanks rather than deletes — so these offsets mean something.
        #expect(code != raw)
        #expect(code.count == raw.count)

        let styleBody = try cadenceFunctionBody("private struct CadencePlainButtonBody: View", in: code)
        let viewBody = try cadenceFunctionBody("var body: some View", in: styleBody)
        let fence = try #require(viewBody.range(of: "#else"))
        let pointerBranch = String(viewBody[viewBody.startIndex..<fence.lowerBound])
        let touchBranch = String(viewBody[fence.upperBound...])

        // The pointer keeps the wash — both halves of it — and the hover tracking that drives it.
        #expect(pointerBranch.contains("#if os(macOS)"))
        #expect(pointerBranch.contains("Theme.blue.opacity(backgroundOpacity)"))
        #expect(pointerBranch.contains("Theme.blue.opacity(strokeOpacity)"))
        #expect(pointerBranch.contains("CadenceHoverTracking(isHovered: $isHovered)"))

        // The finger draws nothing of its own. It delegates, and the only thing it adds back is the
        // hit area, which is shape rather than paint.
        #expect(touchBranch.contains("iOSPressableButtonStyle().makeBody(configuration: configuration)"))
        #expect(touchBranch.contains(".contentShape(RoundedRectangle(cornerRadius: 10))"))
        for paint in ["Theme.", ".background(", ".overlay", ".fill(", "strokeBorder", "opacity("] {
            #expect(touchBranch.contains(paint) == false, "the touch branch paints \(paint)")
        }

        // Counted over the whole body, so the wash cannot be drawn twice under either branch.
        #expect(viewBody.components(separatedBy: "Theme.blue").count - 1 == 2)
        #expect(viewBody.components(separatedBy: ".background(").count - 1 == 1)

        // One level up: `makeBody` hands the configuration straight to the body above, so a wash
        // cannot be reintroduced on the wrapper instead.
        let makeBody = try cadenceFunctionBody("func makeBody(configuration: Configuration) -> some View", in: code)
        #expect(makeBody.contains("CadencePlainButtonBody(configuration: configuration)"))
        #expect(makeBody.contains("#if") == false)
        #expect(makeBody.contains("Theme.") == false)

        // The numbers stay in one place: iOS's press feedback is not re-spelled here.
        #expect(!code.contains("0.97"))
        #expect(!code.contains("0.62"))
    }

    /// The shared components that made this bigger than two sites still apply `.cadencePlain` —
    /// which is now correct on both platforms and is the whole point of fixing the style rather
    /// than the callers. Pinned so a later "cleanup" that fences these individually has to argue
    /// with a test rather than quietly reintroduce nine spellings of one platform check.
    @Test func theSharedPickersKeepOneUnfencedStyle() throws {
        // All five files that spell the style, not the two the ticket happened to name.
        // `CadenceDatePicker` and `EstimatePickerControl` are the two shared ones that genuinely
        // reach iOS. `CadenceButtons` and `CadenceContextPicker` were whole-file `#if os(macOS)`
        // under `Shared/Components/` when this was written; T-288 moved them to `macOS/Views/`,
        // which is why they are listed apart from the sweep below rather than inside it. What is
        // pinned for all four is the same: the style is applied straight, and no caller re-spells
        // the platform split the style now handles.
        let sharedStraight = [
            "Cadence/Shared/Components/CadenceDatePicker.swift",
            "Cadence/Shared/Components/EstimatePickerControl.swift"
        ]
        let desktopStraight = [
            "Cadence/macOS/Views/CadenceButtons.swift",
            "Cadence/macOS/Views/CadenceContextPicker.swift"
        ]
        for path in sharedStraight + desktopStraight {
            let code = try pressFeedbackStrippingComments(pressFeedbackSourceFile(path))
            #expect(code.contains(".buttonStyle(.cadencePlain)"), "\(path)")
            #expect(!code.contains("iosPressable"), "\(path) re-spells the platform split")
        }

        // `CadenceTagChip` is the one deliberate fork, and says so in its own comment: the chip's
        // *style* is the genuine platform difference. One of each, so the fork stays a fork.
        let chipPath = "Cadence/Shared/Components/CadenceTagChip.swift"
        let chip = try pressFeedbackStrippingComments(pressFeedbackSourceFile(chipPath))
        #expect(chip.components(separatedBy: ".buttonStyle(.cadencePlain)").count - 1 == 1, "\(chipPath)")
        #expect(chip.components(separatedBy: ".buttonStyle(.iosPressable)").count - 1 == 1, "\(chipPath)")

        // And the sweep, so the list above cannot silently stop being all of them. A sixth file
        // spelling the style is fine; one of these *losing* it is a caller being fenced by hand,
        // which is the thing this pins.
        var scanned = 0
        var spelling: Set<String> = []
        for path in try pressFeedbackSwiftFiles(under: "Cadence/Shared") {
            scanned += 1
            let code = try pressFeedbackStrippingComments(pressFeedbackSourceFile(path))
            if code.contains(".buttonStyle(.cadencePlain)") { spelling.insert(path) }
        }
        // Non-vacuity: the folder held 117 files when this was written.
        #expect(scanned > 90, "scanned only \(scanned) files under Cadence/Shared")
        let expected = Set(sharedStraight + [chipPath])
        #expect(spelling.isSuperset(of: expected), "missing: \(expected.subtracting(spelling).sorted())")

        // The other half of T-288's move: the two desktop files are no longer under
        // `Cadence/Shared`, so putting either of them back has to argue with this line.
        #expect(spelling.isDisjoint(with: Set(desktopStraight)))
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
