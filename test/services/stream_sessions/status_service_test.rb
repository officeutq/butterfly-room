# frozen_string_literal: true

require "test_helper"

class StreamSessions::StatusServiceTest < ActiveSupport::TestCase
  test "cannot change standby booth to live when own other booth is live" do
    store = Store.create!(name: "Test Store")
    cast = User.create!(email: "status_live@example.com", password: "password", role: :cast)

    live_booth = Booth.create!(
      store: store,
      name: "Live Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/live-status"
    )
    standby_booth = Booth.create!(
      store: store,
      name: "Standby Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/standby-status"
    )

    BoothCast.create!(booth: live_booth, cast_user: cast)
    BoothCast.create!(booth: standby_booth, cast_user: cast)

    StreamSessions::StartService.new(booth: live_booth, actor: cast).call
    live_booth.update!(status: :live)

    standby_session = StreamSession.create!(
      booth: standby_booth,
      store: store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: cast,
      ivs_stage_arn: standby_booth.ivs_stage_arn
    )
    standby_booth.update!(
      status: :standby,
      current_stream_session_id: standby_session.id
    )

    assert standby_booth.reload.standby?

    err = assert_raises(StreamSessions::StatusService::AnotherBoothAlreadyLive) do
      StreamSessions::StatusService.new(booth: standby_booth, actor: cast, to_status: :live).call
    end

    assert_equal "他のブースで配信中のため開始できません", err.message
  end

  test "cannot change standby booth to live when own other booth is away" do
    store = Store.create!(name: "Test Store")
    cast = User.create!(email: "status_away@example.com", password: "password", role: :cast)

    away_booth = Booth.create!(
      store: store,
      name: "Away Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/away-status"
    )
    standby_booth = Booth.create!(
      store: store,
      name: "Standby Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/standby-status-2"
    )

    BoothCast.create!(booth: away_booth, cast_user: cast)
    BoothCast.create!(booth: standby_booth, cast_user: cast)

    StreamSessions::StartService.new(booth: away_booth, actor: cast).call
    away_booth.update!(status: :away)

    standby_session = StreamSession.create!(
      booth: standby_booth,
      store: store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: cast,
      ivs_stage_arn: standby_booth.ivs_stage_arn
    )
    standby_booth.update!(
      status: :standby,
      current_stream_session_id: standby_session.id
    )

    assert standby_booth.reload.standby?

    err = assert_raises(StreamSessions::StatusService::AnotherBoothAlreadyLive) do
      StreamSessions::StatusService.new(booth: standby_booth, actor: cast, to_status: :live).call
    end

    assert_equal "他のブースで配信中のため開始できません", err.message
  end

  test "can switch same booth from live to away and away to live" do
    store = Store.create!(name: "Test Store")
    cast = User.create!(email: "status_same_booth@example.com", password: "password", role: :cast)

    booth = Booth.create!(
      store: store,
      name: "Test Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/same-booth"
    )

    BoothCast.create!(booth: booth, cast_user: cast)

    StreamSessions::StartService.new(booth: booth, actor: cast).call
    booth.reload

    StreamSessions::StatusService.new(booth: booth, actor: cast, to_status: :live).call
    assert booth.reload.live?

    StreamSessions::StatusService.new(booth: booth, actor: cast, to_status: :away).call
    assert booth.reload.away?

    StreamSessions::StatusService.new(booth: booth, actor: cast, to_status: :live).call
    assert booth.reload.live?
  end
end
