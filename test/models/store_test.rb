# frozen_string_literal: true

require "test_helper"

class StoreTest < ActiveSupport::TestCase
  test "new stores are unpublished by default and scopes separate publication state" do
    unpublished_store = Store.create!(name: "unpublished")
    published_store = Store.create!(name: "published", published: true)

    assert_not unpublished_store.published?
    assert_equal [ published_store ], Store.published.where(id: [ unpublished_store.id, published_store.id ]).to_a
    assert_equal [ unpublished_store ], Store.unpublished.where(id: [ unpublished_store.id, published_store.id ]).to_a
  end

  test "new stores are not sales support companies by default" do
    store = Store.create!(name: "regular store")

    assert_not store.sales_support_company?
  end

  test "name is required" do
    store = Store.new(name: nil)

    assert_not store.valid?
    assert_includes store.errors.details[:name], { error: :blank }
  end

  test "description has maximum length 1000" do
    store = Store.new(name: "store", description: "a" * 1001)

    assert_not store.valid?
    assert store.errors.details[:description].any? { |detail| detail[:error] == :too_long }
  end

  test "area has maximum length 50" do
    store = Store.new(name: "store", area: "a" * 51)

    assert_not store.valid?
    assert store.errors.details[:area].any? { |detail| detail[:error] == :too_long }
  end
end
