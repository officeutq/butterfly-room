require "test_helper"

class IvsClientTest < ActiveSupport::TestCase
  test "looks up active session and paginates participant details using valid SDK arguments" do
    sdk = Aws::IVSRealTime::Client.new(stub_responses: true, region: "ap-northeast-1")
    sdk.stub_responses(:get_stage, { stage: { arn: "stage-arn", active_session_id: "active-session" } })
    sdk.stub_responses(:list_participants, [
      { participants: [ { participant_id: "p1" } ], next_token: "next-page" },
      { participants: [ { participant_id: "p2" } ] }
    ])
    sdk.stub_responses(:get_participant, [
      { participant: { participant_id: "p1", attributes: { "role" => "publisher" } } },
      { participant: { participant_id: "p2", attributes: { "role" => "viewer" } } }
    ])
    client = Ivs::Client.new(client: sdk)
    participants = client.list_participants(stage_arn: "stage-arn")
    assert_equal %w[p1 p2], participants.map(&:participant_id)
    assert_equal "publisher", participants.first.attributes["role"]
    requests = sdk.api_requests.select { |r| r[:operation_name] == :list_participants }
    assert_equal [ nil, "next-page" ], requests.map { |r| r[:params][:next_token] }
    assert requests.all? { |r| r[:params][:session_id] == "active-session" }
    client.disconnect_participant(stage_arn: "stage-arn", participant_id: "p1")
    assert_equal({ stage_arn: "stage-arn", participant_id: "p1" }, sdk.api_requests.last[:params])
  end

  test "historical stage sessions are paginated and attributes are read in the specified session" do
    sdk = Aws::IVSRealTime::Client.new(stub_responses: true, region: "ap-northeast-1")
    sdk.stub_responses(:list_stage_sessions, [ { stage_sessions: [ { session_id: "old-1" } ], next_token: "more" },
      { stage_sessions: [ { session_id: "old-2" } ] } ])
    sdk.stub_responses(:list_participants, { participants: [] })
    client = Ivs::Client.new(client: sdk)
    assert_equal %w[old-1 old-2], client.list_stage_sessions(stage_arn: "stage-arn").map(&:session_id)
    assert_empty client.list_participants(stage_arn: "stage-arn", session_id: "old-1")
    assert_equal "old-1", sdk.api_requests.last[:params][:session_id]
    refute sdk.api_requests.any? { |r| r[:operation_name] == :get_stage }
  end
end
