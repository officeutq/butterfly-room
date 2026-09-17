# #1340 の隔離DB・代替AWS応答用。verify_publisher_retry.cjs からのみ起動する。
# 復旧操作は標準入力だけで受け付け、アプリのHTTP経路は追加しない。
require "json"
require "stringio"
require "puma"

database = ApplicationRecord.connection_db_config.database
raise "isolated test DB required" unless Rails.env.test? && database.match?(/\Abutterfly_room_retry1340_[0-9a-f]{8}\z/)
raise "publisher control required" unless StreamSessions::PublisherControl.enabled?
raise "empty verification DB required" if User.exists? || StreamSession.exists?

STDOUT.sync = true
ActiveJob::Base.queue_adapter = :test
Aws.config.update(stub_responses: true, credentials: Aws::Credentials.new("verification", "verification"))
client = Aws::IVSRealTime::Client.new(region: "ap-northeast-1")
Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| client }
participants = {}
disconnect_calls = []
failures = 0
client.stub_responses(:get_stage, ->(context) {
  arn = context.params.fetch(:arn)
  raise "foreign stage" unless arn.include?(":000000000000:stage/retry1340-")
  { stage: { arn: arn, active_session_id: "verification-session" } }
})
client.stub_responses(:create_participant_token, ->(context) {
  id = "verification-#{SecureRandom.hex(8)}"
  participants[id] = { participant_id: id, state: "CONNECTED", published: true,
    attributes: context.params.fetch(:attributes), stage_arn: context.params.fetch(:stage_arn) }
  { participant_token: { token: "verification-token-#{id}", participant_id: id, expiration_time: 1.hour.from_now } }
})
client.stub_responses(:list_participants, ->(context) {
  { participants: participants.values.select { |entry| entry[:stage_arn] == context.params[:stage_arn] }
    .map { |entry| entry.except(:attributes, :stage_arn) } }
})
client.stub_responses(:get_participant, ->(context) {
  { participant: participants.fetch(context.params.fetch(:participant_id)).except(:stage_arn) }
})
client.stub_responses(:disconnect_participant, ->(context) {
  disconnect_calls << { participant_id: context.params.fetch(:participant_id), time: Time.current.to_f }
  if failures.positive?
    failures -= 1
    "AccessDeniedException"
  else
    participants.delete(context.params.fetch(:participant_id))
    {}
  end
})

password = SecureRandom.hex(24)
suffix = database.delete_prefix("butterfly_room_retry1340_")
users = %w[cast store_admin system_admin customer].to_h do |role|
  [ role, User.create!(email: "retry1340-#{suffix}-#{role}@example.invalid", password: password,
    display_name: "検証 #{role}", role: role) ]
end
store = Store.create!(name: "再試行検証 #{suffix}", published: true)
StoreMembership.create!(store: store, user: users.fetch("store_admin"), membership_role: :admin)
StoreMembership.create!(store: store, user: users.fetch("cast"), membership_role: :cast)
wallet = Wallet.create!(customer_user: users.fetch("customer"), available_points: 10_000, reserved_points: 0)
item = DrinkItem.create!(store: store, name: "検証ドリンク", price_points: 100)
fixtures = {}

def runner(connection, apply:)
  args = [ "--connection-id", connection.id.to_s ]
  if apply
    args += [ "--apply", "--environment", Rails.env.to_s, "--database", ApplicationRecord.connection_db_config.database,
      "--request-id", connection.request_id, "--participant-id", connection.ivs_participant_id, "--stage-arn", connection.ivs_stage_arn ]
  end
  original_argv = ARGV.dup
  original_stdout = $stdout
  $stdout = StringIO.new
  ARGV.replace(args)
  load Rails.root.join("script/recover_publisher_disconnect.rb")
  JSON.parse($stdout.string)
ensure
  ARGV.replace(original_argv)
  $stdout = original_stdout
end

def reply(body)
  puts "RETRY1340 #{JSON.generate(body)}"
end

server = Puma::Server.new(Rails.application)
server.add_tcp_listener("0.0.0.0", 3014)
server.run
reply(ready: true, database: database, password: password, users: users.transform_values { |user| { id: user.id, email: user.email } }, store_id: store.id)

begin
  while (line = STDIN.gets)
    input = JSON.parse(line)
    break if input["operation"] == "quit"

    result = Rails.application.executor.wrap do
      fixture = fixtures[input["key"]]
      case input.fetch("operation")
      when "prepare"
        key = input.fetch("key")
        raise "duplicate fixture" if fixtures.key?(key)
        booth = Booth.create!(store: store, name: "再試行 #{key}", status: :offline,
          ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:000000000000:stage/retry1340-#{suffix}-#{key}")
        BoothCast.create!(booth: booth, cast_user: users.fetch("cast"))
        session = StreamSessions::StartService.new(booth: booth, actor: users.fetch("cast")).call
        fixtures[key] = { booth: booth, session: session, role: input.fetch("role") }
        { booth_id: booth.id, session_id: session.id, creator_id: session.started_by_cast_user_id }
      when "failures"
        failures = Integer(input.fetch("count"))
        { failures: failures }
      when "drinks"
        2.times do
          DrinkOrders::CreateService.new(stream_session: fixture.fetch(:session).reload,
            customer_user: users.fetch("customer"), drink_item: item).call!
        end
        { created: 2 }
      when "tick"
        # 実際の待機予定を過ぎたジョブだけ実行する。時刻や回数は書き換えない。
        queue = ActiveJob::Base.queue_adapter.enqueued_jobs
        jobs = queue.select { |job| job[:job] == DisconnectPublisherConnectionJob && (!job[:at] || job[:at] <= Time.current.to_f) }
        jobs.each do |job|
          queue.delete(job)
          ActiveJob::Base.execute(job.except(:job, :args, :queue, :priority, :at))
        end
        { performed: jobs.size }
      when "collect"
        RetryPendingPublisherDisconnectsJob.perform_now
        fixture.fetch(:session).stream_publisher_connections.each { |connection| DisconnectPublisherConnectionJob.perform_now(connection.id) }
        { collected: true }
      when "snapshot"
        session = fixture.fetch(:session).reload
        connections = session.stream_publisher_connections.order(:id)
        orders = DrinkOrder.where(stream_session: session).order(:id)
        { session: session.attributes, booth_status: fixture.fetch(:booth).reload.status,
          connections: connections.map { |entry| entry.attributes.except("participant_token") },
          calls: disconnect_calls.select { |call| connections.pluck(:ivs_participant_id).include?(call[:participant_id]) },
          orders: orders.map(&:attributes), wallet: wallet.reload.attributes,
          transactions: WalletTransaction.where(ref_type: "DrinkOrder", ref_id: orders.select(:id)).order(:id).map(&:attributes),
          ledgers: StoreLedgerEntry.where(stream_session: session).order(:id).map(&:attributes),
          errors: ErrorLog.where(stream_session_id: session.id).order(:id).map(&:attributes) }
      when "recover"
        connection = fixture.fetch(:session).stream_publisher_connections.sole
        runner(connection, apply: input.fetch("apply", false))
      when "restart"
        session = StreamSessions::StartService.new(booth: fixture.fetch(:booth).reload, actor: users.fetch(fixture.fetch(:role))).call
        fixture[:next_session] = session
        { session_id: session.id, generation: session.publisher_generation }
      when "cleanup"
        # 専用データも履歴は残し、保存済み接続だけを解放する。
        failures = 0
        StreamSession.where(store: store, ended_at: nil).find_each do |session|
          StreamSessions::ForceEndService.new(stream_session: session, actor: users.fetch("system_admin"), generation: session.publisher_generation).call
        end
        deadline = 40.seconds.from_now
        while StreamPublisherConnection.unreleased.exists? && Time.current < deadline
          StreamPublisherConnection.unreleased.find_each do |connection|
            if connection.disconnect_state == "failed"
              runner(connection, apply: true)
            else
              DisconnectPublisherConnectionJob.perform_now(connection.id)
            end
          end
          sleep 0.25 if StreamPublisherConnection.unreleased.exists?
        end
        { unreleased: StreamPublisherConnection.unreleased.count, live: StreamSession.where(store: store, ended_at: nil).count,
          retained_sessions: StreamSession.where(store: store).count }
      else
        raise "unknown verification command"
      end
    rescue StreamSessions::PublisherControl::Error => error
      { error: error.code }
    end
    reply(result)
  end
ensure
  server.stop(true)
end
