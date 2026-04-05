# frozen_string_literal: true

require "test_helper"

class StreamSessions::StartServiceTest < ActiveSupport::TestCase
  test "cast cannot start stream when not belong to booth" do
    store = Store.create!(name: "Test Store")

    booth = Booth.create!(
      store: store,
      name: "Test Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/abc"
    )

    cast = User.create!(email: "cast1@example.com", password: "password", role: :cast)
    other_cast = User.create!(email: "cast2@example.com", password: "password", role: :cast)

    # cast は booth に紐付けるが、other_cast は紐付けない
    BoothCast.create!(booth: booth, cast_user: cast)

    err = assert_raises(StreamSessions::StartService::NotAuthorized) do
      StreamSessions::StartService.new(booth: booth, actor: other_cast).call
    end
    assert_equal "選択できないブースです", err.message
  end

  test "cast can start stream when belong to booth" do
    store = Store.create!(name: "Test Store")

    booth = Booth.create!(
      store: store,
      name: "Test Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/abc"
    )

    cast = User.create!(email: "cast@example.com", password: "password", role: :cast)
    BoothCast.create!(booth: booth, cast_user: cast)

    session = StreamSessions::StartService.new(booth: booth, actor: cast).call

    assert session.persisted?
    assert_equal booth.id, session.booth_id
    assert_equal store.id, session.store_id
    assert_equal cast.id, session.started_by_cast_user_id

    booth.reload
    assert booth.standby?
    assert_equal session.id, booth.current_stream_session_id
  end

  test "cast cannot start another booth when own other booth is live" do
    store = Store.create!(name: "Test Store")
    cast = User.create!(email: "cast_live@example.com", password: "password", role: :cast)

    live_booth = Booth.create!(
      store: store,
      name: "Live Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/live"
    )
    other_booth = Booth.create!(
      store: store,
      name: "Other Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/other"
    )

    BoothCast.create!(booth: live_booth, cast_user: cast)
    BoothCast.create!(booth: other_booth, cast_user: cast)

    StreamSessions::StartService.new(booth: live_booth, actor: cast).call
    live_booth.update!(status: :live)

    err = assert_raises(StreamSessions::StartService::AnotherBoothAlreadyLive) do
      StreamSessions::StartService.new(booth: other_booth, actor: cast).call
    end

    assert_equal "他のブースで配信中のため開始できません", err.message
  end

  test "cast cannot start another booth when own other booth is away" do
    store = Store.create!(name: "Test Store")
    cast = User.create!(email: "cast_away@example.com", password: "password", role: :cast)

    away_booth = Booth.create!(
      store: store,
      name: "Away Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/away"
    )
    other_booth = Booth.create!(
      store: store,
      name: "Other Booth",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/other2"
    )

    BoothCast.create!(booth: away_booth, cast_user: cast)
    BoothCast.create!(booth: other_booth, cast_user: cast)

    StreamSessions::StartService.new(booth: away_booth, actor: cast).call
    away_booth.update!(status: :away)

    err = assert_raises(StreamSessions::StartService::AnotherBoothAlreadyLive) do
      StreamSessions::StartService.new(booth: other_booth, actor: cast).call
    end

    assert_equal "他のブースで配信中のため開始できません", err.message
  end
end
