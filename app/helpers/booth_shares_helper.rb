# frozen_string_literal: true

require "uri"

module BoothSharesHelper
  X_SHARE_HASHTAG_TEXT = "#Butterflyve #バタフライブ"

  def public_share_display_name(user)
    return if user.blank? || user.deleted?

    user.display_name.to_s.strip.presence
  end

  def booth_share_og_description(user)
    display_name = public_share_display_name(user)
    return "ライブ配信をButterflyveで楽しもう" if display_name.blank?

    "#{display_name}のライブ配信をButterflyveで楽しもう"
  end

  def booth_web_share_text(primary_cast_user)
    display_name = public_share_display_name(primary_cast_user)
    return "Butterflyveのブースはこちら🦋" if display_name.blank?

    "#{display_name}のブースはこちら🦋"
  end

  def stream_session_web_share_text(stream_session)
    display_name = public_share_display_name(stream_session.started_by_cast_user)
    return "配信はここから！遊びに来てね🦋" if display_name.blank?

    "#{display_name}の配信はここから！遊びに来てね🦋"
  end

  def x_share_intent_url(text:, url:)
    query = URI.encode_www_form(
      text: "#{text}\n\n#{X_SHARE_HASHTAG_TEXT}",
      url: url
    )

    "https://x.com/intent/tweet?#{query}"
  end

  def line_share_url(text:, url:)
    "https://social-plugins.line.me/lineit/share?#{URI.encode_www_form(text: text, url: url)}"
  end
end
