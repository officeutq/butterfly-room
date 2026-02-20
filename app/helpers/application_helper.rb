# frozen_string_literal: true

module ApplicationHelper
  def booth_status_badge(booth)
    return "" if booth.blank?

    label, klass =
      case booth.status&.to_sym
      when :live
        [ "配信中", "text-bg-danger" ]
      when :standby
        [ "スタンバイ", "text-bg-info" ]
      when :away
        [ "離席中", "text-bg-warning" ]
      else
        [ "オフライン", "text-bg-secondary" ]
      end

    content_tag(:span, label, class: "badge #{klass}")
  end

  def display_name_or_email(user)
    return "" if user.blank?

    user.display_name.presence || user.email
  end
end
