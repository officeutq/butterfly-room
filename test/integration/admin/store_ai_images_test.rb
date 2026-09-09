# frozen_string_literal: true

require "test_helper"

class Admin::StoreAiImagesTest < ActionDispatch::IntegrationTest
  setup do
    Admin::StoreAiAutofillsController::RATE_LIMIT_STORE.clear
    @store = Store.create!(name: "既存店舗画像", published: false)
    @other_store = Store.create!(name: "別店舗画像", published: false)
    @admin = User.create!(email: "ai-image-admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "ai-image-system@example.com", password: "password", role: :system_admin)
    @membership = StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    sign_in @admin, scope: :user
  end

  test "existing and newly added managers can retrieve images without pending registration or changing data" do
    original = @store.attributes
    assert_no_difference -> { ActiveStorage::Blob.count } do
      post_image(@store, token_for(@store, @admin))
    end
    assert_response :no_content
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_nil @request.session[ApplicationController::STORE_REGISTRATION_PENDING_SESSION_KEY]
    assert_equal original, @store.reload.attributes

    added = User.create!(email: "ai-image-added@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: added, membership_role: :admin)
    sign_in added, scope: :user
    post_image(@store, token_for(@store, added))
    assert_response :no_content
  end

  test "a system admin can use any store but tokens remain bound to the actor and store" do
    sign_in @system_admin, scope: :user
    post_image(@other_store, token_for(@other_store, @system_admin))
    assert_response :no_content
    post_image(@store, token_for(@store, @admin))
    assert_response :unprocessable_entity
    post_image(@other_store, token_for(@store, @system_admin))
    assert_response :unprocessable_entity
  end

  test "missing expired and tampered tokens are rejected" do
    token = token_for(@store, @admin)
    [ nil, "#{token}tampered" ].each do |invalid|
      post_image(@store, invalid)
      assert_response :unprocessable_entity
    end
    travel 6.minutes do
      post_image(@store, token)
      assert_response :unprocessable_entity
    end
  end

  test "another store and a revoked membership cannot use otherwise valid tokens" do
    post_image(@other_store, token_for(@other_store, @admin))
    assert_response :forbidden
    token = token_for(@store, @admin)
    @membership.destroy!
    post_image(@store, token)
    assert_response :forbidden
  end

  test "image limits are shared across stores and remain separate from AI searches" do
    StoreMembership.create!(store: @other_store, user: @admin, membership_role: :admin)
    10.times do |index|
      store = index.even? ? @store : @other_store
      post_image(store, token_for(store, @admin))
      assert_response :no_content
    end
    post_image(@store, token_for(@store, @admin))
    assert_response :too_many_requests

    # A search validation response proves that image requests did not consume
    # the independent ten-search quota, without making an external AI call.
    10.times do
      post admin_store_ai_autofill_path(@store), params: { store_ai_autofill: { store_name: " " } }, as: :json
      assert_response :unprocessable_entity
    end
    post admin_store_ai_autofill_path(@store), as: :json
    assert_response :too_many_requests
    sign_in @system_admin, scope: :user
    post_image(@store, token_for(@store, @system_admin))
    assert_response :no_content
    sign_in @admin, scope: :user
    travel 10.minutes + 1.second do
      post_image(@store, token_for(@store, @admin))
      assert_response :no_content
    end
  end

  test "store selection does not override the authorized store in the image URL" do
    StoreMembership.create!(store: @other_store, user: @admin, membership_role: :admin)
    post admin_current_store_path, params: { store_id: @other_store.id, return_to_key: "store_edit" }
    assert_redirected_to edit_admin_store_path(@other_store)
    post_image(@store, token_for(@store, @admin))
    assert_response :no_content
    assert_equal @other_store.id, @request.session[:current_store_id].to_i
  end

  test "unauthenticated image requests are rejected" do
    sign_out @admin
    post_image(@store, token_for(@store, @admin))
    assert_response :unauthorized
  end

  private

  def post_image(store, token)
    post image_admin_store_ai_autofill_path(store), params: { image_token: token }, as: :json
  end

  def token_for(store, actor)
    # An authenticated empty source list exercises authorization and token
    # validation without fetching an external website.
    Stores::AiAutofill::ImageSources.verifier.generate(
      { "store_id" => store.id, "user_id" => actor.id, "sources" => [] },
      purpose: Stores::AiAutofill::ImageSources::PURPOSE, expires_in: 5.minutes
    )
  end
end
