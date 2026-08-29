# frozen_string_literal: true

require "test_helper"

class GuestReadOnlyViewingTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Guest Read Only Store", published: true)
    @cast = User.create!(
      email: "guest-read-only-cast@example.com",
      password: "password",
      role: :cast,
      display_name: "Guest Read Only Cast"
    )
    @customer = User.create!(
      email: "guest-read-only-customer@example.com",
      password: "password",
      role: :customer,
      display_name: "Guest Read Only Customer"
    )
    @booth = Booth.create!(store: @store, name: "Guest Read Only Booth", status: :live)
    BoothCast.create!(booth: @booth, cast_user: @cast)
    @stream_session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/guestReadOnly"
    )
    @booth.update!(current_stream_session: @stream_session)
    @comment = Comment.create!(
      stream_session: @stream_session,
      booth: @booth,
      user: @customer,
      body: "未ログインでも読めるコメント"
    )
    DrinkItem.create!(
      store: @store,
      name: "Guest Read Only Drink",
      price_points: 100,
      position: 0,
      enabled: true
    )
  end

  test "guest can view live booth and comments without presence or write forms" do
    assert_no_difference "Presence.count" do
      get booth_path(@booth)
    end

    assert_response :success
    assert_select "[data-controller~='ivs-viewer']", count: 1
    assert_select "turbo-cable-stream-source", minimum: 4
    assert_select "#comments", text: /未ログインでも読めるコメント/
    assert_select "#comment_#{@comment.id} .comment-author a", count: 0

    assert_select "[data-controller~='presence-poll']", count: 0
    assert_select "[data-presence-poll-ping-url-value]", count: 0
    assert_select "[data-presence-poll-summary-url-value]", count: 0
    assert_select ".meta-count", count: 0

    assert_select "#comment_form a[href=?][data-turbo-frame='modal']",
                  guest_auth_prompt_path,
                  count: 1
    assert_select "form[action=?]", stream_session_comments_path(@stream_session), count: 0
    assert_select "form[action=?]",
                  report_stream_session_comment_path(@stream_session, @comment),
                  count: 0
    assert_select "a[href=?][data-turbo-frame='modal']",
                  guest_auth_prompt_path,
                  text: "このコメントを通報"

    assert_select "a.viewer-ops-btn[href=?][data-turbo-frame='modal']",
                  guest_auth_prompt_path,
                  count: 1
    assert_select "[data-action='ivs-viewer#toggleMute']", count: 1
    assert_select "turbo-frame#viewer_drink_menu", count: 0
  end

  test "guest write and presence endpoints remain authenticated" do
    assert_no_difference "Comment.count" do
      post stream_session_comments_path(@stream_session), params: { comment: { body: "投稿不可" } }
    end
    assert_redirected_to new_user_session_path

    assert_no_difference "Presence.count" do
      post ping_stream_session_presence_path(@stream_session)
    end
    assert_redirected_to new_user_session_path

    get presence_summary_stream_session_path(@stream_session)
    assert_redirected_to new_user_session_path

    get viewer_drink_menu_booth_path(@booth)
    assert_redirected_to new_user_session_path
  end

  test "guest profile access is limited to active cast and store admin" do
    get user_path(@cast)
    assert_response :success
    assert_select "h1", text: @cast.display_name
    assert_select "a.viewer-favorite-btn[href=?][data-turbo-frame='modal']",
                  guest_auth_prompt_path,
                  minimum: 1
    assert_includes response.body, @booth.name
    refute_includes response.body, @cast.email

    store_admin = User.create!(
      email: "guest-read-only-admin@example.com",
      password: "password",
      role: :store_admin,
      display_name: "Guest Read Only Admin"
    )
    StoreMembership.create!(store: @store, user: store_admin, membership_role: :admin)

    get user_path(store_admin)
    assert_response :success
    assert_includes response.body, @store.name
    refute_includes response.body, store_admin.email

    get user_path(@customer)
    assert_response :not_found

    @cast.update!(deleted_at: Time.current)
    get user_path(@cast)
    assert_response :not_found

    private_store_admin = User.create!(
      email: "guest-private-admin@example.com",
      password: "password",
      role: :store_admin
    )
    get user_path(private_store_admin)
    assert_response :not_found

    sales_support_store = Store.create!(
      name: "Guest Sales Support Store",
      published: true,
      sales_support_company: true
    )
    Booth.create!(store: sales_support_store, name: "Guest Sales Support Booth")
    sales_support_admin = User.create!(
      email: "guest-sales-support-admin@example.com",
      password: "password",
      role: :store_admin
    )
    StoreMembership.create!(
      store: sales_support_store,
      user: sales_support_admin,
      membership_role: :admin
    )

    get user_path(sales_support_admin)
    assert_response :not_found
  end

  test "authenticated profile keeps the existing favorite state" do
    @customer.favorite_users.create!(target_user: @cast)
    sign_in @customer, scope: :user

    get user_path(@cast)

    assert_response :success
    assert_select "#user_favorite_button form[action=?] button.viewer-favorite-btn.is-active",
                  user_favorite_path(@cast),
                  count: 1
  end

  test "guest cannot view unpublished or archived booths" do
    @store.update!(published: false)
    get booth_path(@booth)
    assert_response :not_found

    @store.update!(published: true)
    @booth.update!(archived_at: Time.current)
    get booth_path(@booth)
    assert_response :not_found
  end
end
