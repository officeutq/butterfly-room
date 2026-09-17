# 保存済み接続1件に限定した運用復旧。通常は表示のみ、--apply指定時だけ1回切断する。
require "optparse"
require "json"

options = {}
OptionParser.new do |parser|
  parser.on("--connection-id ID", Integer) { |value| options[:id] = value }
  parser.on("--apply") { options[:apply] = true }
  parser.on("--environment NAME") { |value| options[:environment] = value }
  parser.on("--database NAME") { |value| options[:database] = value }
  parser.on("--request-id UUID") { |value| options[:request_id] = value }
  parser.on("--participant-id ID") { |value| options[:participant_id] = value }
  parser.on("--stage-arn ARN") { |value| options[:stage_arn] = value }
end.parse!(ARGV)

abort "--connection-id を指定してください" unless options[:id]&.positive?
connection = StreamPublisherConnection.find(options[:id])
database = ApplicationRecord.connection_db_config.database

if options[:apply]
  unless options.values_at(:environment, :database, :request_id, :participant_id, :stage_arn) ==
      [ Rails.env.to_s, database, connection.request_id, connection.ivs_participant_id, connection.ivs_stage_arn ]
    abort "環境・DB・保存済み接続の指定が一致しません。表示のみで対象を確認してください"
  end
  connection = Ivs::DisconnectPublisherConnectionService.new(connection_id: connection.id).recover_once(
    request_id: options[:request_id], participant_id: options[:participant_id])
end

puts JSON.pretty_generate({ environment: Rails.env.to_s, database: database, applied: !!options[:apply],
  connection_id: connection.id, request_id: connection.request_id, stage_arn: connection.ivs_stage_arn,
  participant_id: connection.ivs_participant_id, stream_session_id: connection.stream_session_id,
  booth_id: connection.booth_id, user_id: connection.user_id, state: connection.disconnect_state,
  reason: connection.disconnect_reason, attempts: connection.disconnect_attempts,
  failed_at: connection.disconnect_failed_at, in_flight_at: connection.disconnect_in_flight_at,
  released_at: connection.released_at, last_error: connection.last_disconnect_error })
exit 1 if options[:apply] && connection.disconnect_state != "disconnected"
