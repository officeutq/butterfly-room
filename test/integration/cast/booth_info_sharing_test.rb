# frozen_string_literal: true

require "test_helper"

class Cast::BoothInfoSharingTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "ブース共有店舗", published: true)
    @cast = User.create!(
      email: "booth-info-sharing-cast@example.com",
      password: "password",
      role: :cast,
      display_name: "ブース共有キャスト"
    )
    @booth = Booth.create!(store: @store, name: "ブース共有対象", status: :offline)
    BoothCast.create!(booth: @booth, cast_user: @cast)

    sign_in @cast, scope: :user
  end

  test "booth info shares the booth URL and primary cast message" do
    get cast_booth_path(@booth)

    assert_response :success
    assert_select "button[data-controller='share']" do |buttons|
      button = buttons.first
      assert_equal "Butterflyve", button["data-share-title"]
      assert_equal "ブース共有キャストのブースはこちら🦋", button["data-share-text"]
      assert_equal share_booth_url(@booth), button["data-share-url"]
      assert_equal "ブースを共有", button.text.strip
    end
  end

  test "booth info sharing never adds a stream query for any booth status" do
    stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast
    )

    %i[offline standby live away].each do |status|
      @booth.update!(
        status: status,
        current_stream_session: (stream_session unless status == :offline)
      )

      get cast_booth_path(@booth)

      assert_response :success
      button = Nokogiri::HTML(response.body).at_css("button[data-controller='share']")
      assert_equal share_booth_url(@booth), button["data-share-url"]
      refute_includes button["data-share-url"], "stream="
    end
  end

  test "blank or deleted primary cast display name uses the fixed message" do
    @cast.update!(display_name: " ")
    get cast_booth_path(@booth)
    assert_response :success
    assert_share_text "Butterflyveのブースはこちら🦋"

    @cast.update!(display_name: "削除済みキャスト", deleted_at: Time.current)
    store_admin = User.create!(
      email: "deleted-cast-sharing-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)
    sign_in store_admin, scope: :user

    get cast_booth_path(@booth)
    assert_response :success
    assert_share_text "Butterflyveのブースはこちら🦋"
    refute_includes response.body, @cast.email
  end

  test "booth without a primary cast uses the fixed message" do
    store_admin = User.create!(
      email: "booth-info-sharing-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)
    booth_without_cast = Booth.create!(store: @store, name: "キャスト未設定ブース")
    sign_in store_admin, scope: :user

    get cast_booth_path(booth_without_cast)

    assert_response :success
    assert_share_text "Butterflyveのブースはこちら🦋"
    button = Nokogiri::HTML(response.body).at_css("button[data-controller='share']")
    assert_equal share_booth_url(booth_without_cast), button["data-share-url"]
  end

  private

  def assert_share_text(expected)
    button = Nokogiri::HTML(response.body).at_css("button[data-controller='share']")
    assert_equal expected, button["data-share-text"]
  end
end
