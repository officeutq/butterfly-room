require "test_helper"

class DrinkItemsHelperTest < ActionView::TestCase
  setup do
    @store = Store.create!(name: "drink-items-helper-store")
  end

  test "drink_item_display renders name and points" do
    drink_item = DrinkItem.new(name: "シャンパン", price_points: 12_000, icon_key: "champagne")

    html = drink_item_display(drink_item)

    assert_includes html, "シャンパン"
    assert_includes html, "12000 pt"
    assert_includes html, "drink-item-display"
    assert_includes html, "drink-item-display-tone-yellow"
  end

  test "drink_item_display falls back safely for nil" do
    html = drink_item_display(nil)

    assert_includes html, "未設定"
    assert_includes html, "drink-item-display"
    assert_includes html, "drink-item-display-tone-default"
  end

  test "drink_item_display uses default tone for invalid points" do
    drink_item = DrinkItem.new(name: "未設定ドリンク", price_points: nil)

    html = drink_item_display(drink_item)

    assert_includes html, "drink-item-display-tone-default"
    refute_includes html, " pt"
  end

  test "drink_item_display merges custom class into wrapper" do
    drink_item = DrinkItem.new(name: "マイク", price_points: 2_500, icon_key: "microphone")

    html = drink_item_display(drink_item, klass: "custom-preview-class")

    assert_includes html, "custom-preview-class"
    assert_includes html, "drink-item-display-tone-cyan"
  end

  test "drink_icon prefers custom_icon over icon_key" do
    drink_item = DrinkItem.create!(
      store: @store,
      name: "カスタム",
      price_points: 3_000,
      position: 1,
      enabled: true,
      icon_key: "mug"
    )
    attach_custom_icon(drink_item)

    html = drink_icon(drink_item)

    assert_includes html, "rails/active_storage"
    refute_includes html, "drink_mug.jpg"
  end

  test "drink_icon uses icon_key when custom_icon is missing" do
    drink_item = DrinkItem.new(name: "シャンパン", price_points: 12_000, icon_key: "champagne")

    html = drink_icon(drink_item)

    assert_includes html, "drink_icons/drink_champagne.jpg"
  end

  test "drink_icon falls back to unset image when icon_key is invalid" do
    drink_item = DrinkItem.new(name: "不明", price_points: 100, icon_key: "invalid_icon")

    html = drink_icon(drink_item)

    assert_includes html, "drink_icons/drink_unset.jpg"
  end

  private

  def attach_custom_icon(drink_item)
    File.open(Rails.root.join("test/fixtures/files/thumb.png"), "rb") do |file|
      drink_item.custom_icon.attach(
        io: file,
        filename: "custom.png",
        content_type: "image/png"
      )
    end
  end
end
