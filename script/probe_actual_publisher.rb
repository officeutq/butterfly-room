# frozen_string_literal: true

# probe_actual_publisher.cjs の子プロセス。test DBの専用データだけを作り、終了時に削除する。
# 参加者トークンを含む応答は親プロセスとのパイプ専用。ファイル・ログへ保存しない。
abort "test environment required" unless Rails.env.test? && StreamSessions::PublisherControl.enabled?
STDOUT.sync = true
setup = JSON.parse(STDIN.gets)
run_id = setup.fetch("run_id")
abort "probe run required" unless run_id.match?(/\Aissue1298-[0-9a-f-]{36}\z/)
stage_arn = setup.fetch("stage_arn")
stage = Aws::IVSRealTime::Client.new(region: "ap-northeast-1").get_stage(arn: stage_arn).stage
unless stage.name == "br-local-#{run_id}" && stage.tags["probe_run"] == run_id && stage.tags["env"] == "local-probe" && stage.tags["issue"] == "1298"
  abort "isolated probe stage required"
end
store = creator = publisher = booth = stream_session = nil

def reply(body, status: 200)
  puts "BR_PROBE #{JSON.generate({ status: status, body: body })}"
end

begin
  store = Store.create!(name: "Publisher probe #{run_id}", published: true)
  creator = User.create!(email: "creator-#{run_id}@example.com", password: SecureRandom.hex(24), role: :cast)
  publisher = User.create!(email: "publisher-#{run_id}@example.com", password: SecureRandom.hex(24), role: :store_admin)
  StoreMembership.create!(store: store, user: publisher, membership_role: :admin)
  booth = Booth.create!(store: store, name: run_id, status: :standby, ivs_stage_arn: stage_arn)
  BoothCast.create!(booth: booth, cast_user: creator)
  stream_session = StreamSession.create!(store: store, booth: booth, started_by_cast_user: creator,
    status: :live, started_at: 10.minutes.ago, title: "未開始の準備", ivs_stage_arn: stage_arn)
  booth.update!(current_stream_session: stream_session)
  reply({ ready: true, stream_session_id: stream_session.id, creator_id: creator.id, publisher_id: publisher.id })

  while (line = STDIN.gets)
    input = JSON.parse(line)
    break if input["operation"] == "quit"

    begin
      session = StreamSession.find(stream_session.id)
      result = case input.fetch("operation")
      when "token"
        StreamSessions::IssuePublisherConnectionService.new(stream_session: session, actor: publisher,
          request_id: input["request_id"], expected_generation: input["expected_generation"]).call
      when "confirm"
        StreamSessions::ConfirmPublisherService.new(stream_session: session, actor: publisher,
          request_id: input["request_id"], generation: input["generation"]).call
      when "state"
        StreamSessions::PublisherStateService.new(stream_session: session, actor: publisher, request_id: input["request_id"]).call
      when "cancel"
        StreamSessions::CancelPublisherConnectionService.new(stream_session: session, actor: publisher,
          request_id: input["request_id"], generation: input["generation"]).call
      when "snapshot"
        { session_id: session.id, creator_id: session.started_by_cast_user_id, publisher_id: session.actual_publisher_user_id,
          source: session.actual_publisher_source, broadcast_started_at: session.broadcast_started_at, booth_status: session.booth.status,
          connections: session.stream_publisher_connections.count, confirmed_at: session.current_publisher_connection&.confirmed_at }
      when "status"
        updated = StreamSessions::StatusService.new(booth: session.booth, actor: publisher, to_status: input["to"],
          stream_session_id: session.id, request_id: input["request_id"], generation: input["generation"]).call
        { ok: true, booth_status: updated.status }
      when "repeat_old_disconnect"
        previous = session.stream_publisher_connections.find_by!(request_id: input["request_id"])
        raise "replacement required" unless previous.disconnect_reason == "replace" && previous.released_at && previous.ivs_stage_arn == stage_arn
        Aws::IVSRealTime::Client.new(region: "ap-northeast-1").disconnect_participant(stage_arn: stage_arn, participant_id: previous.ivs_participant_id)
        { disconnected_participant_id: previous.ivs_participant_id }
      when "external"
        snapshot = Ivs::ParticipantSnapshotService.new(stage_arn: stage_arn).call
        { participants: snapshot.participants.map { |participant| { participant_id: participant.participant_id, state: participant.state, published: participant.published } } }
      else
        raise ArgumentError, "unknown probe operation"
      end
      reply(result)
    rescue StreamSessions::PublisherControl::Error => error
      reply({ error: error.code, message: error.message }, status: Rack::Utils.status_code(error.status))
    rescue => error
      reply({ error: error.class.name }, status: 500)
    end
  end
ensure
  if store
    # この実行で作成したtest DBの行だけを削除する。開発・本番の履歴は対象にしない。
    Booth.where(store_id: store.id).update_all(current_stream_session_id: nil)
    StreamSession.where(store_id: store.id).update_all(current_publisher_connection_id: nil)
    StreamPublisherConnection.where(booth_id: booth&.id).delete_all if booth
    StreamSession.where(store_id: store.id).delete_all
    BoothCast.where(booth_id: booth&.id).delete_all if booth
    Booth.where(store_id: store.id).delete_all
    StoreMembership.where(store_id: store.id).delete_all
    User.where(id: [ creator&.id, publisher&.id ].compact).delete_all
    Store.where(id: store.id).delete_all
    reply({ test_data_removed: !Store.exists?(store.id) })
  end
end
