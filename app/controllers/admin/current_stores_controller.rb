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

    def resolve_redirect_path(store_id)
      store = Store.find_by(id: store_id)

      key = params[:return_to_key].presence
      if key.present?
        path = resolve_return_to_key(key, store)
        return path if path.present?
      end

      rt = safe_return_to(params[:return_to])
      return rt if rt.present?

      if request.referer.to_s.start_with?(admin_stores_url)
        return dashboard_path
      end

      session_rt = safe_return_to(session[:admin_return_to])
      return session_rt if session_rt.present?

      dashboard_path
    end

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

    def safe_return_to(value)
      s = value.to_s
      return nil if s.blank?

      return nil unless s.start_with?("/")
      return nil if s.start_with?("//")
      return nil if s.include?("\n") || s.include?("\r")
      return nil if s.include?("\0")

      return nil if s == "/admin/current_store"
      return nil if s == "/admin/stores/select_modal"

      s
    end
  end
end
