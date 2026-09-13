require "test_helper"

class StagingHeaderBadgeTest < ActionDispatch::IntegrationTest
  test "staging badge appears above both logo and title headers" do
    with_env("APP_ENV" => "staging", "BASIC_AUTH_ENABLED" => "false") do
      get root_path
      assert_response :success
      assert_select "#app_header .header-logo", count: 1
      assert_badge

      cast = User.create!(email: "staging-header@example.com", password: "password", role: :cast)
      sign_in cast
      get cast_booths_path
      assert_response :success
      assert_select "#app_header .header-title", text: "ブース一覧"
      assert_badge
    end
  end

  test "other app environments do not display a badge" do
    [ nil, "production", "development", "test" ].each do |environment|
      with_env("APP_ENV" => environment) do
        get root_path
        assert_response :success
        assert_select "#app_header .header-logo", count: 1
        assert_select ".header-environment-badge", count: 0
      end
    end
  end

  test "staging badge appears on publisher and viewer screens" do
    store = Store.create!(name: "Badge Store", published: true)
    cast = User.create!(email: "staging-live-header@example.com", password: "password", role: :cast)
    booth = Booth.create!(store: store, name: "Badge Booth", status: :live)
    BoothCast.create!(booth: booth, cast_user: cast)
    stream_session = StreamSession.create!(
      booth: booth, store: store, status: :live, started_at: Time.current,
      started_by_cast_user: cast, ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/badge"
    )
    booth.update!(current_stream_session: stream_session)

    with_env("APP_ENV" => "staging", "BASIC_AUTH_ENABLED" => "false") do
      get booth_path(booth)
      assert_response :success
      assert_select "body.viewer-layout"
      assert_badge

      sign_in cast
      get live_cast_booth_path(booth)
      assert_response :success
      assert_select "body.cast-live-layout"
      assert_badge
    end
  end

  private

  def assert_badge
    assert_select "#app_header > .app-header > .header-environment-badge", text: "staging", count: 1
    assert_select "#app_header .header-wallet", count: 1
    assert_select "#app_header .header-trigger", count: 1
  end
end
