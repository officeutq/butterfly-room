# frozen_string_literal: true

require "json"
require "puma"

database = ApplicationRecord.connection_db_config.database
raise "isolated test DB required" unless Rails.env.test? && database.match?(/\Abutterfly_room_members1359_[0-9a-f]{8}\z/)
raise "empty DB required" if User.exists? || Store.exists?

STDOUT.sync = true
ActiveJob::Base.queue_adapter = :test
password = SecureRandom.hex(16)
scenarios = %i[store_admin system_admin].product([ 1440, 390 ]).map do |role, width|
  admin = User.create!(email: "members-#{role}-#{width}@example.test", password: password, role: role, display_name: "確認用店舗管理者")
  cast = User.create!(email: "cast-#{role}-#{width}@example.test", password: password, role: :cast, display_name: "確認用キャスト")
  store = Store.create!(name: "所属者確認店舗 #{role} #{width}", onboarding_step: :completed)
  StoreMembership.create!(store: store, user: admin, membership_role: :admin)
  StoreMembership.create!(store: store, user: cast, membership_role: :cast)
  { email: admin.email, role: role, width: width, store_id: store.id }
end
server = Puma::Server.new(Rails.application)
server.add_tcp_listener("0.0.0.0", 3016)
server.run
puts "MEMBERS1359 #{JSON.generate(password: password, scenarios: scenarios,
  icon_stylesheet: ActionController::Base.helpers.asset_path('bootstrap-icons/bootstrap-icons.css'))}"
begin
  raise "verification not completed" unless STDIN.gets&.strip == "quit"
  steps = ActiveRecord::Base.uncached { Store.order(:id).pluck(:onboarding_step) }
  raise "onboarding changed: #{steps.inspect}" unless steps == Array.new(scenarios.size, "completed")
  puts "MEMBERS1359 #{JSON.generate(onboarding_unchanged: true,
    admin_shared: StoreAdminInvitation.where.not(shared_at: nil).count,
    admin_cancelled: StoreAdminInvitation.where.not(cancelled_at: nil).count,
    cast_shared: StoreCastInvitation.where.not(shared_at: nil).count)}"
ensure
  server.stop(true)
end
