# frozen_string_literal: true

module Admin
  class CurrentStoresController < Admin::BaseController
    def create
      store_id = params.require(:store_id)

      if current_user.system_admin?
        unless Store.exists?(id: store_id)
          session.delete(:current_store_id)
          redirect_to admin_stores_path, alert: "選択できない店舗です"
          return
        end
      else
        # session 改ざん対策：必ず membership チェック
        unless StoreMembership.exists?(
          user_id: current_user.id,
          store_id: store_id,
          membership_role: StoreMembership.membership_roles[:admin]
        )
          session.delete(:current_store_id)
          redirect_to admin_stores_path, alert: "選択できない店舗です"
          return
        end
      end

      session[:current_store_id] = store_id
      session.delete(:current_booth_id)

      redirect_to resolve_redirect_path(store_id), notice: "店舗を切り替えました"
    rescue ActionController::ParameterMissing
      redirect_to admin_stores_path, alert: "店舗を選択してください"
    end

    private

    # Issue #270: 店舗選択後の遷移先決定
    #
    # 1) return_to_key（allowlist）
    # 2) return_to（/admin/ の安全な相対パスのみ）
    # 3) session[:admin_return_to]（同上）
    # 4) dashboard_path（既存UX/既存テストと整合）
    def resolve_redirect_path(store_id)
      store = Store.find_by(id: store_id)

      # 1) return_to_key
      key = params[:return_to_key].presence
      if key.present?
        path = resolve_return_to_key(key, store)
        return path if path.present?
      end

      # 2) return_to
      rt = safe_return_to(params[:return_to])
      return rt if rt.present?

      # ★A: 選択画面（/admin/stores）からのPOSTは session 戻りを使わない
      if request.referer.to_s.start_with?(admin_stores_url)
        return dashboard_path
      end

      # 3) session（直前ページ）
      session_rt = safe_return_to(session[:admin_return_to])
      return session_rt if session_rt.present?

      # 4) fallback
      dashboard_path
    end

    # allowlist方式（推奨）
    def resolve_return_to_key(key, store)
      return nil if store.blank?

      case key.to_s
      when "payout_account_edit"
        edit_admin_payout_account_path
      when "store_edit"
        edit_admin_store_path(store)
      else
        nil
      end
    end

    # open redirect対策：/admin/ で始まる相対パスのみ許可
    def safe_return_to(value)
      s = value.to_s
      return nil if s.blank?

      # 相対パスのみ許可（open redirect対策）
      return nil unless s.start_with?("/")
      return nil if s.start_with?("//")
      return nil if s.include?("\n") || s.include?("\r")
      return nil if s.include?("\0")

      # ループ/ノイズ防止：選択画面と選択POSTには戻さない
      return nil if s == "/admin/stores"
      return nil if s == "/admin/current_store"

      s
    end
  end
end
