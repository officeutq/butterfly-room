# frozen_string_literal: true

require "test_helper"

class StorePublicationTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "publication-customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "publication-cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "publication-admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "publication-system@example.com", password: "password", role: :system_admin)

    @published_store = Store.create!(name: "Published Store", published: true)
    @unpublished_store = Store.create!(name: "Hidden Store", published: false)
    @published_booth = Booth.create!(store: @published_store, name: "Published Booth", status: :offline)
    @unpublished_booth = Booth.create!(store: @unpublished_store, name: "Hidden Booth", status: :live)
    BoothCast.create!(booth: @unpublished_booth, cast_user: @cast)

    @stream_session = StreamSession.create!(
      booth: @unpublished_booth,
      store: @unpublished_store,
      started_by_cast_user: @cast,
      status: :live,
      started_at: Time.current
    )
    @unpublished_booth.update!(current_stream_session: @stream_session)

    StoreMembership.create!(store: @published_store, user: @store_admin, membership_role: :admin)
    StoreMembership.create!(store: @unpublished_store, user: @store_admin, membership_role: :admin)
  end

  test "unpublished stores and booths are hidden from public lists and favorites" do
    FavoriteStore.create!(user: @customer, store: @unpublished_store)
    FavoriteBooth.create!(user: @customer, booth: @unpublished_booth)
    sign_in @customer, scope: :user

    get root_path, params: { mode: "stores" }
    assert_includes response.body, @published_store.name
    assert_not_includes response.body, @unpublished_store.name

    get root_path, params: { mode: "booths" }
    assert_includes response.body, @published_booth.name
    assert_not_includes response.body, @unpublished_booth.name

    get favorites_stores_path
    assert_not_includes response.body, @unpublished_store.name

    get favorites_booths_path
    assert_not_includes response.body, @unpublished_booth.name

    get user_path(@cast)
    assert_not_includes response.body, @unpublished_booth.name

    get user_path(@store_admin)
    assert_includes response.body, @published_store.name
    assert_not_includes response.body, @unpublished_store.name
  end

  test "direct public and viewer endpoint access to unpublished records returns 404" do
    sign_in @customer, scope: :user

    get store_path(@unpublished_store)
    assert_response :not_found

    sign_in @customer, scope: :user
    get booth_path(@unpublished_booth)
    assert_response :not_found

    sign_in @customer, scope: :user
    get viewer_drink_menu_booth_path(@unpublished_booth)
    assert_response :not_found

    sign_in @customer, scope: :user
    post stream_session_ivs_participant_tokens_path(@stream_session), params: { role: "viewer" }
    assert_response :not_found

    sign_in @customer, scope: :user
    post stream_session_comments_path(@stream_session), params: { comment: { body: "hidden" } }
    assert_response :not_found

    sign_in @customer, scope: :user
    post stream_session_drink_orders_path(@stream_session), params: { drink_item_id: 0 }
    assert_response :not_found

    sign_in @customer, scope: :user
    post ping_stream_session_presence_path(@stream_session)
    assert_response :not_found

    sign_in @customer, scope: :user
    get presence_summary_stream_session_path(@stream_session)
    assert_response :not_found
  end

  test "public records become visible after a store admin publishes the store" do
    sign_in @store_admin, scope: :user

    patch admin_store_path(@unpublished_store), params: {
      store: { name: @unpublished_store.name, published: "true" }
    }
    assert_redirected_to dashboard_path
    assert @unpublished_store.reload.published?

    get root_path, params: { mode: "stores" }
    assert_includes response.body, @unpublished_store.name
  end

  test "system_admin can change publication state" do
    sign_in @system_admin, scope: :user

    patch admin_store_path(@unpublished_store), params: {
      store: { name: @unpublished_store.name, published: "true" }
    }

    assert_redirected_to dashboard_path
    assert @unpublished_store.reload.published?
  end
end
