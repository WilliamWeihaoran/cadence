import Foundation

let root = CommandLine.arguments[1]
func source(_ path: String) throws -> String {
    try String(contentsOfFile: root + "/" + path, encoding: .utf8)
}
func stringLiterals(_ text: String) throws -> [String] {
    let regex = try NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)
    return try regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
        let range = Range($0.range, in: text)!
        return try JSONDecoder().decode(String.self, from: Data(text[range].utf8))
    }
}
let radiusSource = try source("CadenceTests/CadenceRadiusControlSweepTests.swift")
let radiusTail = radiusSource.components(separatedBy: "static let literalRadiusTenPattern =")[1]
let patternLine = radiusTail.components(separatedBy: "\n")[1]
let radius = try NSRegularExpression(pattern: stringLiterals(patternLine).first!)
for sample in ["cornerRadius: 10", "cornerRadius:\n    10", "let cornerRadius: CGFloat = 10", "cornerRadius: Theme.radiusControl"] {
    let count = sample.components(separatedBy: "\n").reduce(0) {
        $0 + radius.numberOfMatches(in: $1, range: NSRange($1.startIndex..., in: $1))
    }
    print("radius: \(sample.debugDescription) => \(count)")
}
let defaultsSource = try source("CadenceTests/CadenceDefaultsRoutingSweepTests.swift")
let array = defaultsSource.components(separatedBy: "static let unroutedNeedles = [")[1].components(separatedBy: "]")[0]
let needles = try stringLiterals(array)
for sample in ["let d = UserDefaults.standard", "let d = UserDefaults\n    .standard", "let d: UserDefaults = .standard", "let d: UserDefaults =\n    .standard", "let d = CadenceDefaults.store"] {
    print("defaults: \(sample.debugDescription) => \(needles.contains(where: sample.contains))")
}
