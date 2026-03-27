# frozen_string_literal: true

require "test_helper"
require "ostruct"

class StreamSessions::ForceEndServiceTest < ActiveSupport::TestCase
  class FakeIvsClient
    attr_reader :list_participants_calls, :disconnect_participant_calls

    def initialize(participants: [], error: nil)
      @participants = participants
      @error = error
      @list_participants_calls = []
      @disconnect_participant_calls = []
    end

    def list_participants(stage_arn:)
      @list_participants_calls << { stage_arn: stage_arn }
      raise @error if @error

      @participants
    end

    def disconnect_participant(stage_arn:, session_id:, participant_id:)
      @disconnect_participant_calls << {
        stage_arn: stage_arn,
        session_id: session_id,
        participant_id: participant_id
      }
      nil
    end
  end

  setup do
    Ivs::Client.reset_factory!

    @store = Store.create!(name: "Test Store")

    @booth = Booth.create!(
      store: @store,
      name: "Test Booth",
      status: :live,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/test"
    )

    @actor = User.create!(email: "admin@example.com", password: "password", role: :system_admin)

    @stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      started_by_cast_user: @actor,
      status: :live,
      started_at: Time.current,
      ivs_stage_arn: @booth.ivs_stage_arn
    )

    @booth.update!(current_stream_session_id: @stream_session.id)
  end

  teardown do
    Ivs::Client.reset_factory!
  end

  test "disconnects publisher and ends session when participant exists" do
    participant = OpenStruct.new(
      attributes: {
        "stream_session_id" => @stream_session.id.to_s,
        "role" => "publisher"
      },
      stage_session_id: "stage-session-1",
      participant_id: "participant-1"
    )

    fake_client = FakeIvsClient.new(participants: [ participant ])
    Ivs::Client.factory = ->(region:) { fake_client }

    StreamSessions::ForceEndService.new(
      stream_session: @stream_session,
      actor: @actor
    ).call

    assert_equal 1, fake_client.list_participants_calls.size
    assert_equal 1, fake_client.disconnect_participant_calls.size

    disconnect_call = fake_client.disconnect_participant_calls.first
    assert_equal @booth.ivs_stage_arn, disconnect_call[:stage_arn]
    assert_equal "stage-session-1", disconnect_call[:session_id]
    assert_equal "participant-1", disconnect_call[:participant_id]

    @stream_session.reload
    @booth.reload

    assert_equal "ended", @stream_session.status
    assert @stream_session.ended_at.present?
    assert @booth.offline?
    assert_nil @booth.current_stream_session_id
  end

  test "ends session even if participant not found" do
    fake_client = FakeIvsClient.new(participants: [])
    Ivs::Client.factory = ->(region:) { fake_client }

    StreamSessions::ForceEndService.new(
      stream_session: @stream_session,
      actor: @actor
    ).call

    assert_equal 1, fake_client.list_participants_calls.size
    assert_equal 0, fake_client.disconnect_participant_calls.size

    @stream_session.reload
    @booth.reload

    assert_equal "ended", @stream_session.status
    assert @stream_session.ended_at.present?
    assert @booth.offline?
    assert_nil @booth.current_stream_session_id
  end

  test "ends session even if IVS raises error" do
    fake_client = FakeIvsClient.new(error: StandardError.new("ivs error"))
    Ivs::Client.factory = ->(region:) { fake_client }

    StreamSessions::ForceEndService.new(
      stream_session: @stream_session,
      actor: @actor
    ).call

    assert_equal 1, fake_client.list_participants_calls.size
    assert_equal 0, fake_client.disconnect_participant_calls.size

    @stream_session.reload
    @booth.reload

    assert_equal "ended", @stream_session.status
    assert @stream_session.ended_at.present?
    assert @booth.offline?
    assert_nil @booth.current_stream_session_id
  end
end
