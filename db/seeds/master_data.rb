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
    attrs = attrs.symbolize_keys
    finder = target[:find_by].to_h { |k| [ k, attrs.fetch(k) ] }
    record = target[:model].find_or_initialize_by(finder)
    record.update!(attrs)
  end

  puts "seeded #{target[:name]}: #{rows.size}"
end

system_admin_email = ENV["SYSTEM_ADMIN_EMAIL"]
system_admin_password = ENV["SYSTEM_ADMIN_PASSWORD"]

if system_admin_email.present? && system_admin_password.present?
  admin = User.find_or_initialize_by(email: system_admin_email)
  admin.role = :system_admin
  admin.password = system_admin_password
  admin.password_confirmation = system_admin_password
  admin.save!

  puts "seeded system_admin: #{system_admin_email}"
else
  puts "skip system_admin: SYSTEM_ADMIN_EMAIL or SYSTEM_ADMIN_PASSWORD is not set"
end
