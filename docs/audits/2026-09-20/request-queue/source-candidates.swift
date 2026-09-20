import Foundation
import SwiftParser
import SwiftSyntax

let root = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
let markers = ["CadenceSourceScan", "CadenceCommitSurfaceScan", "CadenceScanInstrument", "sourceFile(", "String(contentsOf:", "cadenceTestSource(", "repositoryRoot("]
let shapes = [".contains(", "matchCount(", ".count", ".isEmpty", ".range(", "occurrences("]
var rows = [[String]]()
var scanned = 0
var sourceFiles = 0

final class Expectations: SyntaxVisitor {
    var items = [MacroExpansionExprSyntax]()
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "expect" { items.append(node) }
        return .visitChildren
    }
}

final class Tests: SyntaxVisitor {
    let path: String
    let converter: SourceLocationConverter
    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        converter = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Test" }) else { return .visitChildren }
        guard let body = node.body else { return .skipChildren }
        let assertions = Expectations()
        assertions.walk(body)
        for assertion in assertions.items {
            guard let expression = assertion.arguments.first?.expression.trimmedDescription else { continue }
            let detected = shapes.filter { expression.contains($0) }
            guard !detected.isEmpty else { continue }
            rows.append([path, String(converter.location(for: assertion.positionAfterSkippingLeadingTrivia).line), node.name.text, detected.joined(separator: ";"), expression.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")])
        }
        return .skipChildren
    }
}

for path in try FileManager.default.contentsOfDirectory(atPath: root + "/CadenceTests").sorted() where path.hasSuffix(".swift") {
    scanned += 1
    let relative = "CadenceTests/" + path
    let source = try String(contentsOfFile: root + "/" + relative, encoding: .utf8)
    guard markers.contains(where: source.contains) else { continue }
    sourceFiles += 1
    let tree = Parser.parse(source: source)
    let visitor = Tests(path: relative, tree: tree)
    visitor.walk(tree)
}
let text = (["file\tline\ttest\tshape\texpression"] + rows.map { $0.joined(separator: "\t") }).joined(separator: "\n") + "\n"
try text.write(toFile: destination, atomically: true, encoding: .utf8)
print("Swift files: \(scanned); source-marker files: \(sourceFiles); candidate assertions: \(rows.count); candidate tests: \(Set(rows.map { $0[0] + ":" + $0[2] }).count)")
print("Candidate list only: file-level source markers are not expression-level data flow; indirect or differently spelled readers may be missed.")
