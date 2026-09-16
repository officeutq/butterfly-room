require "test_helper"

class PresenceSelectionCookieTest < ActionDispatch::IntegrationTest
  setup do
    @actor = User.create!(email: "presence-selection@example.com", password: "password", role: :store_admin)
    @store = Store.create!(name: "選択の競合確認", published: true)
    StoreMembership.create!(store: @store, user: @actor, membership_role: :admin)
    @a = Booth.create!(store: @store, name: "A", status: :standby)
    @b = Booth.create!(store: @store, name: "B")
    @stream = StreamSession.create!(store: @store, booth: @a, started_by_cast_user: @actor, status: :live, started_at: Time.current)
    @a.update!(current_stream_session: @stream)
    sign_in @actor
    post cast_current_booth_path, params: { booth_id: @a.id }
    get dashboard_path
  end

  test "古い視聴者数応答が選択変更後に届いてもCookieでAへ巻き戻さない" do
    delayed = open_session
    cookies.to_hash.each { |key, value| delayed.cookies[key] = value }
    delayed.get presence_summary_stream_session_path(@stream), as: :json
    assert_equal 200, delayed.response.status

    post cast_current_booth_path, params: { booth_id: @b.id }, as: :json
    assert_response :success
    assert_equal "B", response.parsed_body["booth_name"]
    refute delayed.response.headers.key?("set-cookie"), "背景の参照応答で選択前のセッションを再発行しない"

    get cast_booth_path(@b)
    assert_response :success
    assert_equal @b.id, session[:current_booth_id]
  end

  test "生存通知はDBを更新してもブラウザーの選択Cookieを上書きしない" do
    assert_difference "Presence.count", 1 do
      post ping_stream_session_presence_path(@stream), as: :json
    end
    assert_response :no_content
    refute response.headers.key?("set-cookie")
  end

  test "BANされた視聴者は定期取得と生存通知の両方で拒否する" do
    viewer = User.create!(email: "presence-banned@example.com", password: "password", role: :customer)
    StoreBan.create!(store: @store, customer_user: viewer, created_by_store_admin_user: @actor)
    sign_out @actor
    sign_in viewer
    get dashboard_path

    get presence_summary_stream_session_path(@stream), as: :json
    assert_response :forbidden
    assert_equal "banned", response.parsed_body["error"]
    refute response.headers.key?("set-cookie")
    assert_no_difference "Presence.count" do
      post ping_stream_session_presence_path(@stream), as: :json
    end
    assert_response :forbidden
    refute response.headers.key?("set-cookie")
  end
end
