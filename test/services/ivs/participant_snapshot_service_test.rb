require "test_helper"

class Ivs::ParticipantSnapshotServiceTest < ActiveSupport::TestCase
  setup do
    @stage_arn = "arn:aws:ivs:ap-northeast-1:123456789012:stage/snapshot"
    @session_id = "st-1234567890123"
    @client = Aws::IVSRealTime::Client.new(stub_responses: true)
    @client.stub_responses(:get_stage, { stage: { arn: @stage_arn, active_session_id: @session_id } })
    @service = Ivs::ParticipantSnapshotService.new(stage_arn: @stage_arn, client: @client)
  end

  test "空のStageでも前後を確認しアプリのセッションIDを照会へ渡さない" do
    @client.stub_responses(:get_stage, { stage: { arn: @stage_arn } })
    snapshot = @service.call
    assert_nil snapshot.session_id
    assert_empty snapshot.participants
    assert_equal %i[get_stage get_stage], operations
    assert_equal [ { arn: @stage_arn }, { arn: @stage_arn } ], @client.api_requests.map { |r| r[:params] }
  end

  test "全ページを取得してから接続中の参加者詳細を確認する" do
    @client.stub_responses(:list_participants, [
      { participants: [ { participant_id: "old", state: "DISCONNECTED", published: true } ], next_token: "next" },
      { participants: [ { participant_id: "current", state: "CONNECTED", published: false } ] }
    ])
    @client.stub_responses(:get_participant, { participant: { participant_id: "current", state: "CONNECTED",
      published: false, attributes: { "role" => "publisher", "stream_session_id" => "42", "user_id" => "7" } } })

    snapshot = @service.call
    assert_equal @session_id, snapshot.session_id
    assert_equal [ "current" ], snapshot.participants.map(&:participant_id)
    assert_equal "7", snapshot.participants.first.attributes["user_id"]
    assert_equal false, snapshot.participants.first.published
    assert_equal %i[get_stage list_participants list_participants get_participant get_stage], operations
    lists = @client.api_requests.select { |r| r[:operation_name] == :list_participants }.map { |r| r[:params] }
    assert_equal [ nil, "next" ], lists.map { |r| r[:next_token] }
    assert lists.all? { |r| r[:stage_arn] == @stage_arn && r[:session_id] == @session_id }
  end

  test "公開履歴のpublished=trueだけで切断済みの人を配信中にしない" do
    @client.stub_responses(:list_participants, { participants: [ { participant_id: "old", state: "DISCONNECTED", published: true } ] })
    assert_empty @service.call.participants
    assert_not_includes operations, :get_participant
  end

  test "途中のページが失敗したら一部の一覧を成功として返さない" do
    @client.stub_responses(:list_participants, [
      { participants: [ { participant_id: "first", state: "CONNECTED" } ], next_token: "next" },
      "AccessDeniedException"
    ])
    assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    assert_not_includes operations, :get_participant
  end

  test "前後のIVSセッションが変わったら空きと扱わない" do
    @client.stub_responses(:get_stage, [
      { stage: { arn: @stage_arn } },
      { stage: { arn: @stage_arn, active_session_id: @session_id } }
    ])
    error = assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    assert_equal "stage_session_changed", error.message
  end

  test "Stageの消失も参加者詳細404も確認不能にする" do
    @client.stub_responses(:get_stage, "ResourceNotFoundException")
    assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    @client.stub_responses(:get_stage, { stage: { arn: @stage_arn, active_session_id: @session_id } })
    @client.stub_responses(:list_participants, { participants: [ { participant_id: "missing", state: "CONNECTED" } ] })
    @client.stub_responses(:get_participant, "ResourceNotFoundException")
    assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
  end

  test "参加者の照会中に接続状態が変わった場合は再確認にする" do
    @client.stub_responses(:list_participants, { participants: [ { participant_id: "changed", state: "CONNECTED" } ] })
    @client.stub_responses(:get_participant, { participant: { participant_id: "changed", state: "DISCONNECTED" } })
    error = assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    assert_equal "participant_changed", error.message
  end

  test "状態不明や反復ページで推測や無限再試行をしない" do
    @client.stub_responses(:list_participants, { participants: [ { participant_id: "unknown" } ] })
    assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    @client.stub_responses(:list_participants, { participants: [], next_token: "repeat" })
    error = assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    assert_equal "repeated_page_token", error.message
  end

  test "通信エラーは安全な例外クラスだけで確認不能にする" do
    @client.stub_responses(:get_stage, Seahorse::Client::NetworkingError.new(IOError.new("private detail")))
    error = assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    assert_equal "Seahorse::Client::NetworkingError", error.message
    refute_includes error.message, "private detail"
  end

  test "認証情報が取得できない場合も空きではなく確認不能にする" do
    @client.stub_responses(:get_stage, Aws::Errors::MissingCredentialsError.new)
    error = assert_raises(Ivs::ParticipantSnapshotService::Unavailable) { @service.call }
    assert_equal "Aws::Errors::MissingCredentialsError", error.message
  end

  private

  def operations
    @client.api_requests.map { |r| r[:operation_name] }
  end
end
