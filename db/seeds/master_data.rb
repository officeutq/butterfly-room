require "yaml"

seed_dir = Rails.root.join("db", "seed_exports")

SEED_TARGETS = [
  {
    name: :effects,
    model: Effect,
    file: "effects.yml",
    find_by: %i[key]
  }
].freeze

SEED_TARGETS.each do |target|
  path = seed_dir.join(target[:file])
  next unless File.exist?(path)

  rows = YAML.load_file(path) || []

  rows.each do |attrs|
    finder = target[:find_by].to_h { |k| [k, attrs.fetch(k)] }
    record = target[:model].find_or_initialize_by(finder)
    record.update!(attrs)
  end

  puts "seeded #{target[:name]}: #{rows.size}"
end
