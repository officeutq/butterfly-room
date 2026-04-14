# frozen_string_literal: true

require "test_helper"

class DrinkItemTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "drink-item-test-store")
  end

  test "icon_key allows blank" do
    drink_item = DrinkItem.new(
      store: @store,
      name: "テストドリンク",
      price_points: 100,
      position: 0,
      enabled: true,
      icon_key: nil
    )

    assert drink_item.valid?
  end

  test "icon_key allows values defined in ICON_OPTIONS" do
    DrinkItem::ICON_OPTIONS.each_key do |icon_key|
      drink_item = DrinkItem.new(
        store: @store,
        name: "テストドリンク",
        price_points: 100,
        position: 0,
        enabled: true,
        icon_key: icon_key
      )

      assert drink_item.valid?, "#{icon_key} should be valid"
    end
  end

  test "icon_key rejects values not defined in ICON_OPTIONS" do
    drink_item = DrinkItem.new(
      store: @store,
      name: "テストドリンク",
      price_points: 100,
      position: 0,
      enabled: true,
      icon_key: "invalid_icon"
    )

    assert_not drink_item.valid?
    assert drink_item.errors.details[:icon_key].any? { |detail| detail[:error] == :inclusion }
  end
end
