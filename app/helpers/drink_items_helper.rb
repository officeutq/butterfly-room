# frozen_string_literal: true

module DrinkItemsHelper
  def drink_icon(drink_item, size: 40, klass: "")
    image_tag(
      drink_item_icon_path(drink_item),
      alt: drink_item_icon_label(drink_item),
      title: drink_item_icon_label(drink_item),
      class: class_names("rounded-circle", klass),
      style: "width: #{size}px; height: #{size}px; object-fit: cover;"
    )
  end

  private

  def drink_item_icon_path(drink_item)
    drink_item_icon_option(drink_item)[:path]
  end

  def drink_item_icon_label(drink_item)
    drink_item_icon_option(drink_item)[:label]
  end

  def drink_item_icon_option(drink_item)
    drink_icon_option_by_key(drink_item&.icon_key)
  end

  def drink_icon_option_by_key(icon_key)
    return { label: "未設定", path: "drink_icons/drink_unset.jpg" } if icon_key.blank?

    DrinkItem::ICON_OPTIONS.fetch(icon_key, { label: "未設定", path: "drink_icons/drink_unset.jpg" })
  end
end
