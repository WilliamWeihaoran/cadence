# Read-only lexical inventory, not an AST or linked-binary audit.
require 'pathname'

root = Pathname.new(ARGV.fetch(0, Dir.pwd)).expand_path
files = %w[Cadence CadenceWidgets CadenceMCPServer].flat_map do |directory|
  Dir[root.join(directory, '**', '*.swift').to_s]
end.sort
patterns = {
  query: /@Query\b/,
  fetch_construction: /FetchDescriptor\s*(?:<[^>\n]+>)?\s*\(/,
  fetch_limit_assignment: /fetchLimit\s*=/,
  app_storage: /@AppStorage\s*\(/
}
patterns.each do |name, pattern|
  raw = files.sum { |file| File.read(file).scan(pattern).size }
  filtered = files.sum do |file|
    File.readlines(file).reject { |line| line.lstrip.start_with?('//') }.join.scan(pattern).size
  end
  puts "#{name}: raw=#{raw}, excluding full-line // comments=#{filtered}"
end

categories = {
  file_timestamp: /\b(?:creationDateKey|contentModificationDateKey|fileModificationDate|getattrlist|getattrlistbulk|fgetattrlist|getattrlistat|stat|fstat|fstatat|lstat)\b|\.(?:creationDate|modificationDate)\b/,
  boot_time: /\b(?:systemUptime|mach_absolute_time)\b/,
  disk_space: /\b(?:volumeAvailableCapacity(?:ForImportantUsage|ForOpportunisticUsage)?(?:Key)?|volumeTotalCapacity(?:Key)?|systemFreeSize|systemSize|statfs|statvfs|fstatfs|fstatvfs)\b/,
  active_keyboards: /\bactiveInputModes\b/,
  fetch_limit: /fetchLimit\s*=/,
  cascade_rule: /deleteRule:\s*\.cascade/
}
categories.each do |name, pattern|
  hits = files.flat_map do |file|
    File.readlines(file).each_with_index.map do |line, index|
      next if line.lstrip.start_with?('//') || !line.match?(pattern)
      "#{Pathname.new(file).relative_path_from(root)}:#{index + 1}: #{line.strip}"
    end.compact
  end
  puts "\n#{name}: #{hits.length} matching source lines"
  puts hits
end
