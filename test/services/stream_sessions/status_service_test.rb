require "test_helper"

class StreamSessions::StatusServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Status")
    @actor = User.create!(email: "status@example.test", password: "password", role: :system_admin)
    @booth = Booth.create!(store: @store, name: "Status", status: :offline, ivs_stage_arn: "stage-status")
    @session = StreamSessions::StartService.new(booth: @booth, actor: @actor).call
  end

  test "standby cannot become live without confirmed publication" do
    assert_raises(StreamSessions::StatusService::NotAuthorized) { change(:live) }
    assert @booth.reload.standby?
    assert_nil @session.reload.broadcast_started_at
  end

  test "same publisher can go away and back and retains first start" do
    @attempt = record_confirmed_broadcast!(@session, user: @actor)
    @booth.update!(status: :live)
    first_start = @session.broadcast_started_at
    %i[away live live].each do |status|
      freeze_time do
        change(status)
        assert_equal status.to_s, @booth.reload.status
        assert_equal Time.current, @booth.last_online_at
        assert_equal first_start, @session.reload.broadcast_started_at
      end
    end
  end

  test "missing or cancelled attempt cannot update status" do
    attempt = record_confirmed_broadcast!(@session, user: @actor)
    @booth.update!(status: :live)
    assert_raises(StreamSessions::StatusService::NotAuthorized) { change(:away) }
    @attempt = attempt
    attempt.update!(cancelled_at: Time.current)
    assert_raises(StreamSessions::StatusService::NotAuthorized) { change(:away) }
    assert @booth.reload.live?
  end

  test "archived booth rejects a stale status update" do
    @attempt = record_confirmed_broadcast!(@session, user: @actor)
    @booth.update!(status: :live, archived_at: Time.current)
    assert_raises(StreamSessions::PublisherControl::NotAuthorized) { change(:away) }
  end

  def change(status)
    StreamSessions::StatusService.new(booth: @booth, actor: @actor, to_status: status, attempt_id: @attempt&.request_id).call
  end
end
