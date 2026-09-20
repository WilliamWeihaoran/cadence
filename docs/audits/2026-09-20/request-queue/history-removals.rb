require 'open3'
require 'set'
require 'json'

# Replay the current guard's nonempty-line membership rule, not diff --numstat.
rev = ARGV.fetch(0, '231a7a8')
commits = IO.popen(['git', 'rev-list', '--parents', rev], &:read).lines.map(&:split)
input, output, waiter = Open3.popen2('git', 'cat-file', '--batch')
cache = {}
blob = lambda do |oid|
  return [] if oid.match?(/\A0+\z/)
  cache[oid] ||= begin
    input.puts oid
    input.flush
    header = output.gets.split
    bytes = output.read(Integer(header.fetch(2)))
    output.read(1)
    bytes.b.split("\n", -1).tap { |lines| lines.pop if lines.last == '' }
  end
end
result = { tree: rev, total: commits.size, merges: 0, evaluated_nonmerge: 0,
           triggered: 0, binary_commits_excluded: 0, last_100_triggered: 0,
           last_100_evaluated: 0 }
commits.each do |row|
  if row.size > 2
    result[:merges] += 1
    next
  end
  raw = IO.popen(['git', 'diff-tree', '--root', '--no-commit-id', '--no-renames', '-r', '--raw', '--no-abbrev', row[0]], &:read)
  removals = 0
  binary = false
  raw.each_line do |line|
    fields = line.split(/\s+/, 6)
    old_oid, new_oid = fields[2], fields[3]
    next if old_oid.match?(/\A0+\z/)
    old = blob.call(old_oid)
    newer = blob.call(new_oid)
    if old.any? { |s| s.include?("\0") } || newer.any? { |s| s.include?("\0") }
      binary = true
      next
    end
    new_set = newer.to_set
    removals += old.count { |s| !s.empty? && !new_set.include?(s) }
  end
  if binary
    result[:binary_commits_excluded] += 1
  else
    result[:evaluated_nonmerge] += 1
    result[:triggered] += 1 if removals > 0
    if result[:last_100_evaluated] < 100
      result[:last_100_evaluated] += 1
      result[:last_100_triggered] += 1 if removals > 0
    end
  end
  cache.clear if cache.size > 3000
end
input.close
output.close
waiter.value
result[:trigger_percent] = (100.0 * result[:triggered] / result[:evaluated_nonmerge]).round(2)
puts JSON.pretty_generate(result)
