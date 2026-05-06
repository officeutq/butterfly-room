# frozen_string_literal: true

require "uri"

module ApplicationHelper
  def seconds_to_human_time(seconds)
    s = seconds.to_i
    return "0分" if s <= 0
    return "1分未満" if s < 60

    h = s / 3600
    m = (s % 3600) / 60

    if h.positive?
      "#{h}時間#{m}分"
    else
      "#{m}分"
    end
  end

  def safe_external_url(url)
    value = url.to_s.strip
    return nil if value.blank?

    uri = URI.parse(value)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def format_phone_number_for_display(phone_number)
    value = phone_number.to_s.strip
    return "" if value.blank?

    digits = value.gsub(/\D/, "")

    if digits.start_with?("81") && digits.length == 12
      local = "0#{digits.delete_prefix("81")}"
      return "#{local[0, 3]}-#{local[3, 4]}-#{local[7, 4]}"
    end

    if digits.start_with?("0") && digits.length == 11
      return "#{digits[0, 3]}-#{digits[3, 4]}-#{digits[7, 4]}"
    end

    value
  end

  def booth_status_badge(booth)
    return "" if booth.blank?

    live_like = booth.live? || booth.away?

    label = live_like ? "配信中" : "オフライン"
    klass = live_like ? "text-bg-danger" : "text-bg-secondary"

    content_tag(:span, label, class: "badge #{klass}")
  end

  def display_name_or_anonymous(user)
    return "" if user.blank?

    user.display_name.presence || "ななしさん"
  end

  def display_name_or_email(user)
    return "" if user.blank?

    user.display_name.presence || user.email
  end

  def user_avatar_badge(user, size: 24, klass: "")
    return "" if user.blank?

    if user.avatar.attached?
      image_tag(
        user.avatar,
        class: [ "rounded-circle border", klass ].join(" ").strip,
        style: "width: #{size}px; height: #{size}px; object-fit: cover;",
        alt: "avatar"
      )
    else
      label = display_name_or_anonymous(user).to_s
      initial = label.strip.presence ? label.strip[0] : "?"
      content_tag(
        :span,
        initial,
        class: [ "rounded-circle border text-muted d-inline-flex align-items-center justify-content-center", klass ].join(" ").strip,
        style: "width: #{size}px; height: #{size}px; font-size: #{(size * 0.45).round}px; line-height: 1;",
        aria: { label: "avatar" },
        title: label
      )
    end
  end

  # --- Layout helpers (Issue #212) ---

  def role_badge(user)
    return "" if user.blank?

    label = user.role.to_s
    content_tag(:span, label, class: "badge text-bg-secondary")
  end

  def header_role_label(user)
    return "" if user.blank?
    return "" if user.customer?

    case user.role.to_sym
    when :cast
      "CAST"
    when :store_admin
      "STORE"
    when :system_admin
      "ADMIN"
    else
      user.role.to_s.upcase
    end
  end

  def user_role_label(user)
    return "" if user.blank?

    case user.role.to_sym
    when :customer
      "視聴者"
    when :cast
      "配信者"
    when :store_admin
      "店舗管理者"
    when :system_admin
      "運営"
    else
      user.role.to_s.upcase
    end
  end
  def dashboard_path_for(_user)
    dashboard_path
  end

  # 参照表示用：可能な範囲で current_store / current_booth を解決する（副作用なし）
  def layout_current_store
    return nil unless user_signed_in?

    # admin配下では既存の整合ロジックを優先
    return current_store if respond_to?(:current_store)

    # ★booth優先（07設計どおり）
    booth = layout_current_booth
    return booth.store if booth.present?

    # fallback: session store（参照のみ）
    store_id = session[:current_store_id]
    return nil if store_id.blank?

    store = Store.find_by(id: store_id)
    return nil if store.blank?

    return store if current_user.system_admin?
    return store if current_user.at_least?(:store_admin) && current_user.admin_of_store?(store.id)

    nil
  end

  def layout_current_booth
    return nil unless user_signed_in?

    # cast配下では既存メソッドがあるのでそれを優先（操作可能チェックも内包）
    return current_booth if respond_to?(:current_booth)

    booth_id = session[:current_booth_id]
    return nil if booth_id.blank?

    booth = Booth.find_by(id: booth_id)
    return nil if booth.blank?

    # system_admin は参照のみOK
    return booth if current_user.system_admin?

    # store_admin は自分の store の booth を参照OK
    if current_user.at_least?(:store_admin) && current_user.admin_of_store?(booth.store_id)
      return booth
    end

    # cast は所属 booth のみ参照OK
    return booth if current_user.at_least?(:cast) && BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)

    nil
  end

  def layout_wallet_points
    return 0 unless user_signed_in?

    current_user.wallet&.available_points || 0
  end

  def enter_booth_switch_confirm_message(target_booth)
    return nil unless user_signed_in?
    return nil unless current_user.at_least?(:cast)
    return nil if target_booth.blank?

    current = layout_current_booth
    return nil if current.blank?
    return nil if current.id == target_booth.id
    return nil unless current.live? || current.away?

    "配信中（または離席中）のブースから切り替えます。よろしいですか？"
  end

  def footer_nav_item_classes(active: false, extra: nil)
    [ "app-footer-nav-item", ("is-active" if active), extra ].compact.join(" ")
  end

  def footer_home_active?
    current_page?(root_path)
  end

  def footer_favorites_active?
    controller_path.start_with?("favorites/")
  end

  def footer_dashboard_active?
    current_page?(dashboard_path_for(current_user))
  end

  def lp_ref_code
    params[:ref].presence || "0000"
  end

  def settlement_status_label(settlement)
    return "" if settlement.blank?

    case settlement.status.to_sym
    when :draft
      "未確定"
    when :confirmed
      "確定済み"
    when :exported
      "振込処理中"
    when :paid
      "支払済み"
    else
      settlement.status.to_s
    end
  end
end
