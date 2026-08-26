import Foundation

/// Reading Swift source as text, for the handful of rules that live inside a private method on a
/// SwiftUI view and can therefore never be called by a test.
///
/// **Use this rather than writing a second copy.** Both moving parts below have a spelling that is
/// wrong in a way that still looks right:
///
/// - the comment stripper must be `(?<!:)//`, not `//`. A stripper that blanks from the slashes in
///   `"https://example.com"` to the end of the line eats that line's `{` and leaves its `}`, so the
///   brace matching below closes the enclosing function early and the scan silently reads a body
///   that stops short of the code it exists to check. `LinksView.addLink()` contains exactly that
///   literal.
/// - the stripper replaces comments with spaces of equal length, so the stripped string is never
///   *shorter* than the raw one. Assert `stripped != raw`; `stripped.count < raw.count` is a test
///   that passes by never being true.
///
/// A scan must also be scoped to a **function body**. Scoping it to the enclosing struct passes on
/// an unrelated line elsewhere in the file, which is not the thing being pinned.
enum CadenceSourceScan {
    /// The repository root, from this file's own path.
    static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Blanks `//` line comments and `/* */` block comments with spaces of equal length, so
    /// assertions read code rather than prose and the string keeps its length.
    static func strippingComments(_ source: String) -> String {
        var result = source
        for pattern in ["(?<!:)//[^\n]*", "/\\*(?s:.)*?\\*/"] {
            while let range = result.range(of: pattern, options: .regularExpression) {
                let width = result.distance(from: range.lowerBound, to: range.upperBound)
                result.replaceSubrange(range, with: String(repeating: " ", count: width))
            }
        }
        return result
    }

    /// The text between the braces of `func <name>(`, found by brace matching from the first `{`
    /// after the signature. Returns `nil` when the function is absent or its braces never balance.
    static func functionBody(named name: String, in source: String) -> String? {
        guard let signature = source.range(of: "func \(name)(") else { return nil }
        guard let open = source.range(of: "{", range: signature.upperBound..<source.endIndex) else {
            return nil
        }

        var depth = 0
        var index = open.lowerBound
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[source.index(after: open.lowerBound)..<index])
                }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// The number of matches for `pattern`, or `-1` when the pattern itself does not compile — a
    /// value no `== 0` assertion can pass by accident.
    static func matchCount(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return -1 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
