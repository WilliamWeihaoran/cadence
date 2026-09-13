# Read-only inventory. Run from the repository root; emits JSON to stdout.
require "json"
require "open3"

def git(*args)
  output, error, status = Open3.capture3("git", *args)
  abort(error) unless status.success?
  output
end

requested = ARGV.fetch(0, "HEAD")
tree = git("rev-parse", "--verify", "--end-of-options", "#{requested}^{commit}").strip
todo = git("show", "#{tree}:docs/TODO.md")
done = git("show", "#{tree}:docs/TODO_DONE.md")
commits = git("log", tree, "--format=%H%x00%s%x00%b%x00%x1e").split("\x1e").map do |raw|
  # String#strip also removes NULs, dropping commits with an empty body.
  parts = raw.sub(/\A\s+/, "").split("\x00", -1)
  next if parts.length < 3
  {
    "sha" => parts[0],
    "subject" => parts[1],
    "ids" => (parts[1] + "\n" + parts[2]).scan(/\bT-\d+\b/).uniq
  }
end.compact

def ordered(ids)
  ids.uniq.sort_by { |id| [id.sub("T-", "").to_i, id] }
end

todo_ids = todo.scan(/^\s*- \[(T-\d+)\]/).flatten
done_ids = done.scan(/^\s*- \[(T-\d+)\]/).flatten
commit_ids = ordered(commits.flat_map { |c| c["ids"] })
missing_todo = ordered(commit_ids - todo_ids)
missing_both = ordered(commit_ids - todo_ids - done_ids)
modern = missing_both.select { |id| id.sub("T-", "").to_i >= 700 }
details = commits.map do |commit|
  missing = commit["ids"] & modern
  next if missing.empty?
  { "sha" => commit["sha"], "subject" => commit["subject"], "missing" => missing }
end.compact

puts JSON.pretty_generate({
  "tree" => git("rev-parse", "--short", tree).strip,
  "history_scope" => "ancestors reachable from audited HEAD, including merge history; not dangling/unmerged refs",
  "commits" => commits.length,
  "commit_ids" => commit_ids.length,
  "todo_entries" => todo_ids.length,
  "todo_unique" => todo_ids.uniq.length,
  "done_entries" => done_ids.length,
  "missing_from_todo" => missing_todo,
  "missing_from_both" => missing_both,
  "todo_without_commit" => ordered(todo_ids - commit_ids),
  "duplicate_todo" => todo_ids.group_by { |id| id }.transform_values(&:length).select { |_, count| count > 1 },
  "recent_missing_details" => details
})
