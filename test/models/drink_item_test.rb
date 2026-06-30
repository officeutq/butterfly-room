# frozen_string_literal: true

require "test_helper"
require "stringio"

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

  test "custom_icon allows jpeg png and webp" do
    DrinkItem::CUSTOM_ICON_ALLOWED_CONTENT_TYPES.each do |content_type|
      drink_item = build_drink_item
      attach_custom_icon(drink_item, content_type: content_type)

      assert drink_item.valid?, "#{content_type} should be valid"
    end
  end

  test "custom_icon rejects svg" do
    drink_item = build_drink_item
    attach_custom_icon(drink_item, content_type: "image/svg+xml", filename: "icon.svg")

    assert_not drink_item.valid?
    assert_not_empty drink_item.errors.details[:custom_icon]
  end

  test "custom_icon rejects files larger than two megabytes" do
    drink_item = build_drink_item
    attach_custom_icon(
      drink_item,
      content_type: "image/png",
      byte_size: DrinkItem::CUSTOM_ICON_MAX_BYTE_SIZE + 1
    )

    assert_not drink_item.valid?
    assert_not_empty drink_item.errors.details[:custom_icon]
  end

  private

  def build_drink_item
    DrinkItem.new(
      store: @store,
      name: "テストドリンク",
      price_points: 100,
      position: 0,
      enabled: true
    )
  end

  def attach_custom_icon(drink_item, content_type:, filename: "icon.png", byte_size: 16)
    drink_item.custom_icon.attach(
      io: StringIO.new("a" * byte_size),
      filename: filename,
      content_type: content_type
    )
  end
end
