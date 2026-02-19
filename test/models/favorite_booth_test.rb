# frozen_string_literal: true

require "test_helper"

class FavoriteBoothTest < ActiveSupport::TestCase
  test "user_id + booth_id is unique at DB level" do
    store = Store.create!(name: "store")
    booth = Booth.create!(store: store, name: "booth", status: :offline)
    user  = User.create!(email: "u1@example.com", password: "password", role: :customer)

    FavoriteBooth.create!(user: user, booth: booth)

    assert_raises(ActiveRecord::RecordNotUnique) do
      FavoriteBooth.create!(user: user, booth: booth)
    end
  end

  test "user can access favorite_booths" do
    store = Store.create!(name: "store")
    booth = Booth.create!(store: store, name: "booth", status: :offline)
    user  = User.create!(email: "u2@example.com", password: "password", role: :customer)

    FavoriteBooth.create!(user: user, booth: booth)

    assert_equal 1, user.favorite_booths.count
    assert_equal booth.id, user.favorite_booths.first.booth_id
  end
end
