require "test_helper"
require "ostruct"

class StreamSessions::PublishServiceTest < ActiveSupport::TestCase
  class FakeIvs
    attr_accessor :participants, :error, :issue_error
    attr_reader :tokens, :disconnects

    def initialize
      @participants, @tokens, @disconnects = [], [], []
    end

    def list_participants(stage_arn:)
      raise error if error
      participants
    end

    def create_participant_token(**options)
      @tokens << options
      raise issue_error if issue_error
      OpenStruct.new(token: "opaque-token", participant_id: "participant-#{@tokens.size}", expiration_time: 1.minute.from_now)
    end

    def disconnect_participant(stage_arn:, participant_id:)
      raise error if error
      @disconnects << participant_id
      @participants.reject! { |p| p.participant_id == participant_id }
    end

    def publish_last!
      token = @tokens.last
      @participants = [ OpenStruct.new(participant_id: "participant-#{@tokens.size}", state: "CONNECTED",
        published: true, user_id: token[:user_id], attributes: token[:attributes]) ]
    end
  end

  setup do
    @store = Store.create!(name: "Publish Test")
    @x = User.create!(email: "prepare@example.test", password: "password", role: :system_admin)
    @y = User.create!(email: "publish@example.test", password: "password", role: :system_admin)
    @booth = Booth.create!(store: @store, name: "Publish", status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/publish")
    @session = StreamSessions::StartService.new(booth: @booth, actor: @x).call
    @client = FakeIvs.new
    @id = SecureRandom.uuid
  end

  def service(user = @y, id = @id)
    StreamSessions::PublishService.new(stream_session: @session, actor: user, attempt_id: id, client: @client)
  end

  test "X prepares Y publishes only after matching IVS confirmation" do
    assert_nil @session.broadcast_started_by_user_id
    result = service.issue_token
    assert_equal @id, result.attempt_id
    assert_nil @session.reload.broadcast_started_at
    assert @booth.reload.standby?
    assert_raises(StreamSessions::PublishService::PublicationPending) { service.confirm }
    @client.publish_last!
    service.confirm
    assert @session.reload.broadcaster?(@y)
    assert_equal @x.id, @session.started_by_cast_user_id
    assert_equal "ivs_confirmed", @session.broadcast_identity_source
    assert @booth.reload.live?
    first_start = @session.broadcast_started_at
    travel 10.seconds do
      service.confirm
      assert_equal first_start, @session.reload.broadcast_started_at
    end
    assert_raises(StreamSessions::PublisherControl::Conflict) { service(@x, SecureRandom.uuid).issue_token }
    assert_raises(StreamSessions::PublisherControl::Conflict) { service(@x).confirm }
    assert_equal 1, @client.tokens.size
  end

  test "issuing alone excludes another user and same user on another booth" do
    service.issue_token
    assert_raises(StreamSessions::PublisherControl::Conflict) { service(@x, SecureRandom.uuid).issue_token }
    other = Booth.create!(store: @store, name: "Other", status: :offline, ivs_stage_arn: "other-stage")
    assert_raises(StreamSessions::StartService::AnotherBoothAlreadyLive) do
      StreamSessions::StartService.new(booth: other, actor: @y).call
    end
    assert StreamSessions::PublisherControl.busy_elsewhere?(@y, booth: other)
    refute StreamSessions::PublisherControl.busy_elsewhere?(@x, booth: other)
    assert_nil @session.reload.broadcast_started_by_user_id
  end

  test "uncertain token response keeps the reservation and failure is recoverable after expiry and IVS check" do
    @client.issue_error = IOError.new("response lost")
    assert_raises(IOError) { service.issue_token }
    assert_equal @y.id, @session.stream_publish_attempts.open.sole.user_id
    assert_raises(StreamSessions::PublisherControl::Conflict) { service(@x, SecureRandom.uuid).issue_token }
    @client.issue_error = nil
    travel 2.minutes do
      service(@x, SecureRandom.uuid).issue_token
      assert_equal @x.id, @session.stream_publish_attempts.open.sole.user_id
    end
  end

  test "cancelled token cannot confirm and remains reserved until expiry" do
    service.issue_token
    @client.publish_last!
    service.cancel
    assert_equal [ "participant-1" ], @client.disconnects
    assert_raises(StreamSessions::PublisherControl::Conflict) { service.confirm }
    assert_raises(StreamSessions::PublisherControl::Conflict) { service(@x, SecureRandom.uuid).issue_token }
    assert_nil @session.reload.broadcast_started_by_user_id
  end

  test "reconnect preserves original identity and old finish and cancel do not affect the new attempt" do
    service.issue_token
    @client.publish_last!
    service.confirm
    first_start = @session.reload.broadcast_started_at
    service.cancel
    new_id = SecureRandom.uuid
    travel 2.minutes do
      service(@y, new_id).issue_token
      @client.publish_last!
      service(@y, new_id).confirm
      assert_equal first_start, @session.reload.broadcast_started_at
      assert_raises(StreamSessions::EndService::NotAuthorized) do
        StreamSessions::EndService.new(stream_session: @session, actor: @y, attempt_id: @id, client: @client).call
      end
      service.cancel
      assert_equal 1, @client.disconnects.size
      assert @booth.reload.live?
      StreamSessions::EndService.new(stream_session: @session, actor: @y, attempt_id: new_id, client: @client).call
      assert @session.reload.ended?
      assert @session.broadcaster?(@y)
    end
  end

  test "API failure cannot release a reservation even after expiry" do
    service.issue_token
    @client.error = IOError.new("unavailable")
    travel 2.minutes do
      assert_raises(IOError) { service(@x, SecureRandom.uuid).issue_token }
      assert_equal @y.id, @session.stream_publish_attempts.open.sole.user_id
    end
  end

  test "old and foreign IVS attributes cannot confirm a new publisher" do
    service.issue_token
    @client.publish_last!
    %w[user_id role stream_session_id publish_attempt_id].each do |key|
      original = @client.participants.first.attributes[key]
      @client.participants.first.attributes[key] = "stale"
      assert_raises(StreamSessions::PublishService::PublicationPending) { service.confirm }
      assert_nil @session.reload.broadcast_started_at
      @client.participants.first.attributes[key] = original
    end
  end

  test "connected publisher is never displaced just because its token expired" do
    service.issue_token
    @client.publish_last!
    travel 2.minutes do
      assert_raises(StreamSessions::PublisherControl::Conflict) { service(@y, SecureRandom.uuid).issue_token }
      assert_empty @client.disconnects
    end
  end

  test "archived current and legacy sessions cannot issue or confirm" do
    @booth.update!(archived_at: Time.current)
    assert_raises(StreamSessions::PublisherControl::NotAuthorized) { service.issue_token }
    @booth.update!(archived_at: nil)
    @session.update!(publisher_protocol: nil)
    assert_raises(StreamSessions::PublisherControl::Conflict) { service.issue_token }
    assert_empty @client.tokens
  end

  test "stale end cannot clear a newer current session" do
    other = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @x, started_at: Time.current, status: :live)
    @booth.update!(current_stream_session: other)
    assert_raises(StreamSessions::PublisherControl::Conflict) do
      StreamSessions::EndService.new(stream_session: @session, actor: @x, force: true, client: @client).call
    end
    assert_equal other.id, @booth.reload.current_stream_session_id
  end

  test "unknown legacy session elsewhere is not treated as an available publisher" do
    @session.update!(publisher_protocol: nil)
    other = Booth.create!(store: @store, name: "Legacy Other", status: :offline, ivs_stage_arn: "legacy-other")
    assert_raises(StreamSessions::StartService::AnotherBoothAlreadyLive) do
      StreamSessions::StartService.new(booth: other, actor: @y).call
    end
    assert_nil @session.reload.broadcast_started_by_user_id
  end
end
