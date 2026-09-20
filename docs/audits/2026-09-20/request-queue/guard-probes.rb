require 'open3'
require 'tmpdir'

root = ARGV.fetch(0)
script = File.read(File.join(root, 'scripts/ledger-lag-check.sh'))
awk = script.split("AWK_PROG=$(cat <<'AWK'\n", 2).fetch(1).split("\nAWK\n", 2).first
Dir.mktmpdir('cadence-r50-fixtures-') do |dir|
  files = %w[todo done log].map { |name| File.join(dir, name) }
  File.write(files[0], "## Done\n- [T-10] **CLOSED 2026-09-20** Done.\n")
  File.write(files[2], "\x01abc\x1f2026-09-19\x1fT-10 implementation\nCadence/File.swift\n")
  { 'nonempty archive' => "# Archive\n", 'empty archive' => '' }.each do |label, archive|
    File.write(files[1], archive)
    out, status = Open3.capture2e('awk', '-v', 'min_commits=1', '-v', 'min_entries=1', '-v', 'min_examined=1', '-v', 'todo=fixture', awk, *files)
    puts "#{label}: exit=#{status.exitstatus}\n#{out}"
  end
  File.write(files[1], "# Archive\n")
  File.write(files[0], "## Open\n- [T-10] Reopened because the earlier implementation was incomplete.\n")
  out, status = Open3.capture2e('awk', '-v', 'min_commits=1', '-v', 'min_entries=1', '-v', 'min_examined=1', '-v', 'todo=fixture', awk, *files)
  puts "legitimate reopen over historical code: exit=#{status.exitstatus}\n#{out}"
end

# Actual production shell comparison, with ordinary overlapping agent names.
out, status = Open3.capture2e('/bin/zsh', '-fc', 'for id in sync async; do name=msg-async.txt; if [[ "$name" == *"$id"* ]]; then print "$id: accepts $name"; fi; done')
puts out
abort "shell probe failed" unless status.success?
