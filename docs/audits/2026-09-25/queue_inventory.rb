# Read-only source/history inventory. Generated JSON is written only when an output is supplied.
# Run from repo root: ruby docs/audits/2026-09-25/queue_inventory.rb SNAPSHOT_ROOT SHA [OUTPUT]
require "json"
require "open3"

root, tree, output = ARGV
abort "usage: queue_inventory.rb SNAPSHOT_ROOT SHA [OUTPUT]" unless root && tree

def git(*args)
  result, error, status = Open3.capture3("git", *args)
  abort error unless status.success?
  result
end

sha = git("rev-parse", "--verify", "#{tree}^{commit}").strip
files = Dir.glob(File.join(root, "Cadence/**/*.swift")).sort
patterns = {
  "system_size" => /\.system\(size:/,
  "numeric_system_size" => /\.system\(size:\s*[0-9]+(?:\.[0-9]+)?/,
  "scaled_metric" => /\bScaledMetric\b/,
  "dynamic_type_size" => /\bdynamicTypeSize\b/,
  "accessibility_label_modifier" => /\.accessibilityLabel\b/,
  "direct_semantic_font" => /\.font\(\.(?:body|headline|subheadline|caption2?|title[23]?|footnote|largeTitle)\)/
}
counts = patterns.transform_values { 0 }
declarations = []
grouping = []
files.each do |path|
  relative = path.delete_prefix(root + "/")
  lines = File.readlines(path)
  lines.each_with_index do |line, i|
    patterns.each { |key, regex| counts[key] += line.scan(regex).length }
    if line.match?(/\bclass\s+\w+\s*:\s*NS(?:View|TextView|ScrollView|Control|Button|ClipView|HostingView)\b|\bstruct\s+\w+\s*:\s*NSViewRepresentable\b/)
      declarations << { path: relative, line: i + 1, source: line.strip }
    end
    next unless line.match?(/\.padding\(\.(?:top|bottom|vertical)|(?:VStack|LazyVStack)\s*\(.*spacing:|(?:header|label|section).*Spacing|labelToNamedBlock/i)
    grouping << { path: relative, line: i + 1, source: line.strip,
                  comment_line: line.lstrip.start_with?("//"),
                  context: lines[[i - 2, 0].max..[i + 2, lines.length - 1].min].map(&:chomp) }
  end
end
manifest = File.readlines(File.join(root, "CadenceTests/CadenceRealTreeSweepManifest.txt"))
  .map(&:strip).reject { |s| s.empty? || s.start_with?("#") }
test_sources = Dir.glob(File.join(root, "CadenceTests/**/*.swift")).map { |p| File.read(p) }.join("\n")
missing_names = manifest.reject { |entry| test_sources.match?(/\bfunc\s+#{Regexp.escape(entry.split('/').last)}\s*\(/) }
ledger_raw, error, status = Open3.capture3("ruby", "docs/audits/2026-09-05/ledger-inventory.rb", sha)
abort error unless status.success?
ledger = JSON.parse(ledger_raw)
commits_by_id = Hash.new { |hash, key| hash[key] = [] }
git("log", sha, "--format=%H%x00%s%x00%b%x00%x1e").split("\x1e").each do |raw|
  parts = raw.sub(/\A\s+/, "").split("\x00", -1)
  next if parts.length < 3
  (parts[1] + "\n" + parts[2]).scan(/\bT-\d+\b/).uniq.each do |id|
    commits_by_id[id] << { sha: parts[0], subject: parts[1] }
  end
end
result = {
  tree: sha, dirty_files_at_capture: 23,
  scope: "Committed snapshot only; raw lexical counts include comments and strings. Not SwiftSyntax or rendered geometry.",
  history_scope: "All ancestors of audited HEAD, including merges; not unmerged refs or unreachable objects.",
  counts: counts,
  manifest: { entries: manifest.length, distinct: manifest.uniq.length, missing_bare_functions: missing_names },
  appkit_declarations: declarations,
  grouping_candidates: grouping,
  ledger: ledger,
  repeated_id_commit_subjects: commits_by_id.select { |_, commits| commits.length > 1 }.sort.to_h,
  limitations: ["Bare-name presence does not execute the manifest classifier or establish suite-qualified ownership.",
    "Repeated ticket mentions are candidates, not proof of unrelated allocation.",
    "Spacing candidates do not classify semantic ownership, conditional composition or painted glyph distances."]
}
json = JSON.pretty_generate(result) + "\n"
if output
  File.write(output, json)
  puts JSON.pretty_generate({ counts: counts, manifest: result[:manifest],
    appkit_declarations: declarations.length, grouping_candidates: grouping.length,
    ledger: ledger.reject { |key, _| %w[missing_from_todo missing_from_both].include?(key) },
    missing_from_todo: ledger["missing_from_todo"].length,
    missing_from_both: ledger["missing_from_both"].length })
else
  puts json
end
