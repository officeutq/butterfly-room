# frozen_string_literal: true

require "json"
require "puma"

database = ApplicationRecord.connection_db_config.database
raise "isolated test DB required" unless Rails.env.test? && database.match?(/\Abutterfly_room_booth1294_[0-9a-f]{8}\z/)
raise "empty DB required" if User.exists? || Store.exists?

STDOUT.sync = true
ActiveJob::Base.queue_adapter = :test
Aws.config.update(stub_responses: true, credentials: Aws::Credentials.new("verification", "verification"))
client = Aws::IVSRealTime::Client.new(stub_responses: true)
Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| client }
password = SecureRandom.hex(16)
pending_ids = []
scenarios = %i[cast store_admin system_admin].product([ 1440, 390 ]).map do |role, width|
  user = User.create!(email: "capture-#{role}-#{width}@example.test", password: password, role: role, display_name: "撮影用利用者")
  publisher = User.create!(email: "publisher-#{role}-#{width}@example.test", password: password, role: :cast, display_name: "撮影用キャスト")
  store = Store.create!(name: "撮影用店舗 #{role} #{width}", published: true, onboarding_step: :completed)
  StoreMembership.create!(store: store, user: user, membership_role: role == :cast ? :cast : :admin)
  booth = Booth.create!(store: store, name: "メインブース", status: role == :cast ? :offline : :live,
    description: "店舗のメインブースです。配信履歴と現在の状態を確認できます。",
    ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/capture#{user.id}")
  caster = role == :cast ? user : publisher
  BoothCast.create!(booth: booth, cast_user: caster)
  secondary = Booth.create!(store: store, name: "サブブース", status: :offline)
  BoothCast.create!(booth: secondary, cast_user: caster)
  stream = nil
  unless role == :cast
    stream = StreamSession.create!(booth: booth, store: store, started_by_cast_user: publisher, status: :live,
      started_at: 15.minutes.ago, broadcast_started_at: 10.minutes.ago, actual_publisher_user: publisher,
      actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: 10.minutes.ago,
      publisher_generation: 1, title: "本日の配信", ivs_stage_arn: booth.ivs_stage_arn)
    connection = StreamPublisherConnection.create!(booth: booth, stream_session: stream, user: publisher,
      request_id: SecureRandom.uuid, generation: 1, ivs_stage_arn: booth.ivs_stage_arn,
      ivs_participant_id: "capture-participant-#{booth.id}", token_expires_at: 1.hour.from_now, confirmed_at: 10.minutes.ago)
    stream.update!(current_publisher_connection: connection)
    booth.update!(current_stream_session: stream)
  end
  closed = %w[retrying failed empty].map do |state|
    target = Booth.create!(store: store, name: "閉鎖済みブース #{state}", status: :offline, archived_at: Time.current)
    BoothCast.create!(booth: target, cast_user: caster)
    unless state == "empty"
      history = StreamSession.create!(booth: target, store: store, started_by_cast_user: caster, status: :ended,
        started_at: 15.minutes.ago, broadcast_started_at: 10.minutes.ago, ended_at: 1.minute.ago,
        actual_publisher_user: publisher, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: 10.minutes.ago,
        title: "過去の配信")
      pending_user = User.create!(email: "pending-#{state}-#{user.id}@example.test", password: password, role: :cast)
      pending = StreamPublisherConnection.create!(booth: target, stream_session: history, user: pending_user,
        request_id: SecureRandom.uuid, generation: 1, ivs_stage_arn: booth.ivs_stage_arn,
        disconnect_requested_at: Time.current, disconnect_reason: "end", disconnect_attempts: state == "failed" ? 4 : 1,
        disconnect_failed_at: state == "failed" ? Time.current : nil)
      pending_ids << pending.id
    end
    { state: state, booth: target.id }
  end
  { role: role, width: width, email: user.email, booth: booth.id, stream: stream&.id, store: store.name, closed: closed }
end
pending_before = StreamPublisherConnection.where(id: pending_ids).order(:id).map(&:attributes)
history_before = StreamSession.ended.order(:id).map(&:attributes)
counts_before = [ Booth.count, StreamSession.count, StreamPublisherConnection.count ]
server = Puma::Server.new(Rails.application)
server.add_tcp_listener("0.0.0.0", 3015)
server.run
puts "PREVIEW1294 #{JSON.generate(password: password, scenarios: scenarios,
  icon_stylesheet: ActionController::Base.helpers.asset_path('bootstrap-icons/bootstrap-icons.css'))}"
begin
  raise "verification not completed" unless STDIN.gets&.strip == "quit"
  managers = scenarios.reject { |item| item[:role] == :cast }
  raise "management flow incomplete" unless managers.all? { |item| Booth.find(item[:booth]).archived? && StreamSession.find(item[:stream]).ended? }
  raise "pending records changed" unless pending_before == StreamPublisherConnection.where(id: pending_ids).order(:id).map(&:attributes)
  raise "old history changed" unless history_before == StreamSession.where(id: history_before.pluck("id")).order(:id).map(&:attributes)
  raise "unexpected new record" unless counts_before == [ Booth.count, StreamSession.count, StreamPublisherConnection.count ]
  operations = client.api_requests.map { |request| request[:operation_name] }
  raise "unexpected IVS call" unless operations == Array.new(4, :disconnect_participant)
  puts "PREVIEW1294 #{JSON.generate(records_unchanged: true, force_end_and_close: 4, stubbed_disconnects: operations.size)}"
ensure
  server.stop(true)
end
