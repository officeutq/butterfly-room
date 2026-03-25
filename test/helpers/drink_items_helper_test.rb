require "test_helper"

class DrinkItemsHelperTest < ActionView::TestCase
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
end
