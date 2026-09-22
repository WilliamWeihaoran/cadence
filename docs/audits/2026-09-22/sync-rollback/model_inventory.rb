# Read-only source inventory for the declaration shapes reviewed at d819a4c.
# Not a Swift parser or a compiler-generated CloudKit schema validator.
require "json"

root = File.expand_path(ARGV.fetch(0, "."))
models = []
Dir[File.join(root, "Cadence/Models/*.swift")].sort.each do |path|
  current = nil
  annotation = nil
  File.readlines(path).each_with_index do |line, offset|
    if (match = line.match(/^@Model final class (\w+) \{/))
      current = { name: match[1], file: path.delete_prefix(root + "/"), line: offset + 1, fields: [] }
      models << current
    elsif line.start_with?("}")
      current = nil
    end
    next unless current
    annotation = line.strip if line.match?(/^    @Relationship/)
    next unless (match = line.match(/^    (?:@\w+\([^\n]*\)\s+)?var (\w+):\s*([^=\n{]+?)\s*=\s*(.*)/))
    current[:fields] << {
      name: match[1], type: match[2].strip, default: match[3].strip,
      line: offset + 1, relationship_annotation: annotation
    }
    annotation = nil
  end
end
names = models.map { |model| model[:name] }
schema = File.read(File.join(root, "Cadence/Services/CadenceSchema.swift")).scan(/\b(\w+)\.self/).flatten
relationships = []
models.each do |model|
  model[:schema_listed] = schema.include?(model[:name])
  model[:fields].each do |field|
    destination = field[:type].delete("[]?")
    field[:relationship] = names.include?(destination)
    next unless field[:relationship]
    field[:destination] = destination
    explicit = field[:relationship_annotation].to_s.match(/inverse:\s*\\(\w+)\.(\w+)/)
    field[:explicit_inverse] = explicit ? "#{explicit[1]}.#{explicit[2]}" : nil
    relationships << [model[:name], field]
  end
end
# Resolve the one-sided explicit annotations first, then list possible inferred pairs.
relationships.each do |owner, field|
  reverse = relationships.select do |other_owner, other|
    other_owner == field[:destination] && other[:destination] == owner &&
      !(owner == other_owner && field[:name] == other[:name])
  end
  paired = reverse.select { |_, other| other[:explicit_inverse] == "#{owner}.#{field[:name]}" }
  field[:inverse_candidates] = reverse.map { |other_owner, other| "#{other_owner}.#{other[:name]}" }
  field[:inverse_source] = field[:explicit_inverse] || paired.first&.then { |o, f| "#{o}.#{f[:name]}" }
end
summary = {
  model_count: models.size,
  stored_declarations_with_defaults: models.sum { |m| m[:fields].size },
  relationship_endpoints: relationships.size,
  to_many_endpoints: relationships.count { |_, f| f[:type].start_with?("[") },
  nonoptional_relationships: relationships.reject { |_, f| f[:type].end_with?("?") }.map { |o, f| "#{o}.#{f[:name]}" },
  missing_explicit_schema_entries: names - schema,
  schema_entries_without_model: schema - names,
  inferred_inverse_endpoints: relationships.reject { |_, f| f[:inverse_source] }.map { |o, f| "#{o}.#{f[:name]}" }
}
puts JSON.pretty_generate(summary: summary, models: models)
