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

  # --- Layout helpers (Issue #212) ---

  def role_badge(user)
    return "" if user.blank?

    label = user.role.to_s
    content_tag(:span, label, class: "badge text-bg-secondary")
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
end
