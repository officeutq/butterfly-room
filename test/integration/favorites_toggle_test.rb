# frozen_string_literal: true

require "test_helper"

class FavoritesToggleTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")
    @booth = Booth.create!(store: @store, name: "booth1", status: :offline)
    @user  = User.create!(email: "customer@example.com", password: "password", role: :customer)
  end

  test "booth favorite create/destroy (turbo_stream)" do
    sign_in @user, scope: :user

    assert_difference("FavoriteBooth.count", +1) do
      post booth_favorite_path(@booth),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, 'id="booth_favorite_button"'
    assert_includes response.body, %(id="booth_#{@booth.id}_favorite_button")

    assert_difference("FavoriteBooth.count", -1) do
      delete booth_favorite_path(@booth),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, 'id="booth_favorite_button"'
    assert_includes response.body, %(id="booth_#{@booth.id}_favorite_button")
  end

  test "booth favorite is idempotent (double create does not break)" do
    sign_in @user, scope: :user

    post booth_favorite_path(@booth),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, 'id="booth_favorite_button"'
    assert_includes response.body, %(id="booth_#{@booth.id}_favorite_button")

    assert_no_difference("FavoriteBooth.count") do
      post booth_favorite_path(@booth),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, 'id="booth_favorite_button"'
    assert_includes response.body, %(id="booth_#{@booth.id}_favorite_button")
  end

  test "store favorite create/destroy (turbo_stream)" do
    sign_in @user, scope: :user

    assert_difference("FavoriteStore.count", +1) do
      post store_favorite_path(@store),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, 'id="store_favorite_button"'
    assert_includes response.body, %(id="store_#{@store.id}_favorite_button")

    assert_difference("FavoriteStore.count", -1) do
      delete store_favorite_path(@store),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, 'id="store_favorite_button"'
    assert_includes response.body, %(id="store_#{@store.id}_favorite_button")
  end

  test "store favorite is idempotent (double create does not break)" do
    sign_in @user, scope: :user

    post store_favorite_path(@store),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes response.body, 'id="store_favorite_button"'
    assert_includes response.body, %(id="store_#{@store.id}_favorite_button")

    assert_no_difference("FavoriteStore.count") do
      post store_favorite_path(@store),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, 'id="store_favorite_button"'
    assert_includes response.body, %(id="store_#{@store.id}_favorite_button")
  end
end
