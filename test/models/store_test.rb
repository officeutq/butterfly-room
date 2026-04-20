# frozen_string_literal: true

require "test_helper"

class StoreTest < ActiveSupport::TestCase
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
