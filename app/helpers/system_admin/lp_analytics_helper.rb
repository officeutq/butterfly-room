# frozen_string_literal: true

module SystemAdmin::LpAnalyticsHelper
  EVENT_LABELS = {
    "lp_view" => "LP表示",
    "scroll_reached" => "スクロール到達",
    "section_reached" => "セクション到達",
    "cta_reached" => "CTA位置到達",
    "cta_clicked" => "CTAクリック",
    "faq_opened" => "FAQを開く",
    "store_registration_form_view" => "登録フォーム表示",
    "store_registration_complete" => "店舗登録完了",
    "store_contact_form_view" => "お問い合わせフォーム表示",
    "store_contact_complete" => "お問い合わせ完了"
  }.freeze

  DEVICE_LABELS = {
    "pc" => "PC",
    "smartphone" => "スマートフォン",
    "tablet" => "タブレット"
  }.freeze

  def lp_analytics_percentage(value)
    number_to_percentage(value, precision: 2, strip_insignificant_zeros: true)
  end

  def lp_analytics_traffic_value(value)
    value.presence || "直接・流入元不明"
  end

  def lp_analytics_device_label(value)
    DEVICE_LABELS.fetch(value, value.presence || "-")
  end

  def lp_analytics_event_label(event)
    label = EVENT_LABELS.fetch(event.event_type, event.event_type)
    event.event_value.present? ? "#{label}: #{event.event_value}" : label
  end

  def lp_analytics_conversion_label(event)
    event.event_type == "store_registration_complete" ? "店舗登録" : "お問い合わせ"
  end

  def lp_analytics_cta_kind_label(kind)
    kind == :registration ? "店舗登録" : "お問い合わせ"
  end
end
