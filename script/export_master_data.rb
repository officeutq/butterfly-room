require "yaml"
require "fileutils"

output_dir = Rails.root.join("db", "seed_exports")
FileUtils.mkdir_p(output_dir)

EXPORT_TARGETS = [
  {
    name: :effects,
    model: Effect,
    order: :id,
    columns: %i[name key zip_filename icon_path enabled position]
  }
].freeze

EXPORT_TARGETS.each do |target|
  rows = target[:model].order(target[:order]).map do |record|
    target[:columns].each_with_object({}) do |column, attrs|
      attrs[column] = record.public_send(column) if record.respond_to?(column)
    end
  end

  path = output_dir.join("#{target[:name]}.yml")
  File.write(path, rows.to_yaml)
  puts "exported #{target[:name]}: #{rows.size} -> #{path}"
end
