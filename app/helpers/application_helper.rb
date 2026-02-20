# frozen_string_literal: true

module ApplicationHelper
  def booth_status_badge(booth)
    return "" if booth.blank?

    live_like = booth.live? || booth.away?

    label = live_like ? "配信中" : "オフライン"
    klass = live_like ? "text-bg-danger" : "text-bg-secondary"

    content_tag(:span, label, class: "badge #{klass}")
  end

  def display_name_or_email(user)
    return "" if user.blank?

    user.display_name.presence || user.email
  end
end
