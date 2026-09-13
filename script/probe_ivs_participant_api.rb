# frozen_string_literal: true

# #1298 の調査用。Rails/DB は起動せず、AWS SDK の代替応答だけを使用する。
# AWS の実接続・トークン失効・応答反映時間を検証するものではない。
require "aws-sdk-ivsrealtime"
require_relative "../app/services/ivs/client"

sdk = Aws::IVSRealTime::Client.new(
  region: "ap-northeast-1",
  credentials: Aws::Credentials.new("research-only", "research-only"),
  stub_responses: true
)
wrapper = Ivs::Client.allocate
wrapper.instance_variable_set(:@client, sdk)

stage_arn = "arn:aws:ivs:ap-northeast-1:000000000000:stage/research-only"
stage_session_id = "st-0000000000000"
participant_id = "research-participant"

puts "aws-sdk-ivsrealtime #{Gem.loaded_specs.fetch('aws-sdk-ivsrealtime').version}"
puts "stub_responses=#{sdk.config.stub_responses}; Rails/DB/network not used"

def expect_argument_error(label, expected)
  yield
  abort "#{label}: expected ArgumentError"
rescue ArgumentError => e
  raise unless e.message.include?(expected)

  puts "#{label}: #{e.message}"
end

expect_argument_error("current list_participants", "missing required parameter params[:session_id]") do
  wrapper.list_participants(stage_arn: stage_arn)
end

expect_argument_error("current disconnect_participant", "unexpected value at params[:stage_session_id]") do
  wrapper.disconnect_participant(
    stage_arn: stage_arn, session_id: stage_session_id, participant_id: participant_id
  )
end

sdk.stub_responses(:get_stage, stage: { arn: stage_arn, active_session_id: stage_session_id })
stage = sdk.get_stage(arn: stage_arn).stage
abort "active session mismatch" unless stage.active_session_id == stage_session_id
puts "get_stage(arn:) -> stage.active_session_id: OK"

sdk.stub_responses(:list_participants, participants: [
  { participant_id: participant_id, state: "CONNECTED", published: true }
])
summary = sdk.list_participants(stage_arn: stage_arn, session_id: stage_session_id).participants.fetch(0)
abort "unexpected summary shape" if summary.respond_to?(:attributes) || summary.respond_to?(:stage_session_id)
puts "list_participants(stage_arn:, session_id:) -> ParticipantSummary without attributes/stage_session_id: OK"

sdk.stub_responses(:get_participant, participant: {
  participant_id: participant_id, state: "CONNECTED", published: true,
  attributes: { "role" => "publisher", "stream_session_id" => "123", "user_id" => "456" }
})
participant = sdk.get_participant(
  stage_arn: stage_arn, session_id: stage_session_id, participant_id: participant_id
).participant
abort "attribute mismatch" unless participant.attributes.fetch("user_id") == "456"
puts "get_participant(stage_arn:, session_id:, participant_id:) -> attributes: OK"

sdk.disconnect_participant(stage_arn: stage_arn, participant_id: participant_id)
puts "disconnect_participant(stage_arn:, participant_id:) accepted by SDK validation: OK"

sdk.stub_responses(:create_participant_token, participant_token: {
  participant_id: participant_id, expiration_time: Time.utc(2026, 9, 14, 12), token: "not-a-real-token"
})
token_response = sdk.create_participant_token(stage_arn: stage_arn).participant_token
abort "token metadata missing" unless token_response.participant_id == participant_id && token_response.expiration_time.is_a?(Time)
puts "create_participant_token -> participant_id/expiration_time available: OK (token not printed)"
