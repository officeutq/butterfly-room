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

  def drink_item_display(drink_item, icon_size: 40, klass: "")
    content_tag(
      :div,
      class: class_names(
        "drink-item-display",
        drink_item_display_tone_class(drink_item&.price_points),
        klass
      )
    ) do
      safe_join(
        [
          content_tag(:div, drink_icon(drink_item, size: icon_size, klass: "drink-item-display-icon")),
          content_tag(:div, class: "drink-item-display-body") do
            safe_join(
              [
                content_tag(:div, drink_item_display_name(drink_item), class: "drink-item-display-name"),
                content_tag(:div, drink_item_display_points(drink_item), class: "drink-item-display-points")
              ]
            )
          end
        ]
      )
    end
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

  def drink_item_display_name(drink_item)
    name = drink_item&.name.to_s.strip
    name.presence || "未設定"
  end

  def drink_item_display_points(drink_item)
    points = normalize_drink_item_points(drink_item&.price_points)
    return "" if points.nil?

    "#{points} pt"
  end

  def drink_item_display_tone_class(price_points)
    points = normalize_drink_item_points(price_points)
    return "drink-item-display-tone-default" if points.nil?

    if points >= 100_000
      "drink-item-display-tone-red"
    elsif points >= 50_000
      "drink-item-display-tone-magenta"
    elsif points >= 20_000
      "drink-item-display-tone-orange"
    elsif points >= 10_000
      "drink-item-display-tone-yellow"
    elsif points >= 5_000
      "drink-item-display-tone-green"
    elsif points >= 2_000
      "drink-item-display-tone-cyan"
    else
      "drink-item-display-tone-default"
    end
  end

  def normalize_drink_item_points(value)
    points = Integer(value, exception: false)
    return nil if points.nil? || points <= 0

    points
  end
end
