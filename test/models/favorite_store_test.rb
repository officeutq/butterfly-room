# frozen_string_literal: true

require "test_helper"

class FavoriteStoreTest < ActiveSupport::TestCase
  test "user_id + store_id is unique at DB level" do
    store = Store.create!(name: "store")
    user  = User.create!(email: "u3@example.com", password: "password", role: :customer)

    FavoriteStore.create!(user: user, store: store)

    assert_raises(ActiveRecord::RecordNotUnique) do
      FavoriteStore.create!(user: user, store: store)
    end
  end

  test "user can access favorite_stores" do
    store = Store.create!(name: "store")
    user  = User.create!(email: "u4@example.com", password: "password", role: :customer)

    FavoriteStore.create!(user: user, store: store)

    assert_equal 1, user.favorite_stores.count
    assert_equal store.id, user.favorite_stores.first.store_id
  end
end
