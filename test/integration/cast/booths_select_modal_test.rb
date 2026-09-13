# frozen_string_literal: true

require "test_helper"

class Cast::BoothsSelectModalTest < ActionDispatch::IntegrationTest
  def create_store!(name:)
    Store.create!(name: name)
  end

  def create_booth!(store:, name:)
    Booth.create!(
      store: store,
      name: name,
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{SecureRandom.hex(4)}"
    )
  end

  def create_cast_with_booths!(booths:)
    user = User.create!(email: "cast_#{SecureRandom.hex}@example.com", password: "password", role: :cast)
    booths.each do |b|
      BoothCast.create!(booth: b, cast_user: user)
    end
    user
  end

  test "2件以上: turbo_frame で modal 表示" do
    store = create_store!(name: "s")
    b1 = create_booth!(store: store, name: "b1")
    b2 = create_booth!(store: store, name: "b2")

    cast = create_cast_with_booths!(booths: [ b1, b2 ])
    sign_in cast, scope: :user

    get select_modal_cast_booths_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
  end

  test "配信中ブースがある場合: 2件以上でも modal を出さず live に遷移" do
    store = create_store!(name: "s")
    live_booth = create_booth!(store: store, name: "live")
    other_booth = create_booth!(store: store, name: "other")

    cast = create_cast_with_booths!(booths: [ live_booth, other_booth ])
    sign_in cast, scope: :user

    session = StreamSessions::StartService.new(booth: live_booth, actor: cast).call
    live_booth.update!(status: :live)

    assert_no_difference "StreamSession.count" do
      get select_modal_cast_booths_path(return_to_key: "booth_live")
    end

    assert_response :redirect
    assert_redirected_to live_cast_booth_path(live_booth)

    assert_equal live_booth.id, @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]
    assert_equal session.id, live_booth.reload.current_stream_session_id
  end

  test "1件: 自動選択され live に遷移" do
    store = create_store!(name: "s")
    booth = create_booth!(store: store, name: "b")

    cast = create_cast_with_booths!(booths: [ booth ])
    sign_in cast, scope: :user

    assert_difference "StreamSession.count", 1 do
      get select_modal_cast_booths_path(return_to_key: "booth_live")
    end

    assert_response :redirect
    assert_redirected_to live_cast_booth_path(booth)

    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]
  end

  test "0件: modal 表示" do
    cast = User.create!(email: "cast_zero@example.com", password: "password", role: :cast)
    sign_in cast, scope: :user

    get select_modal_cast_booths_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
  end
end
