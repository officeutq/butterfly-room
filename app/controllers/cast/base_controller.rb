# frozen_string_literal: true

module Cast
  class BaseController < ApplicationController
    before_action -> { require_role!(:cast, :system_admin) }

    helper_method :current_booth

    private

    # session → params → fallback の順で current_booth を解決する。
    # ※ session 改ざん対策：毎回 BoothCast で所有チェック（system_admin は例外）
    def current_booth
      return nil unless current_user.present?

      booth_id =
        session[:current_booth_id].presence ||
        params[:booth_id].presence ||
        params[:id].presence

      booth = resolve_owned_booth_by_id(booth_id)
      return booth if booth.present?

      fallback = resolve_fallback_booth
      return fallback if fallback.present?

      nil
    end

    def resolve_owned_booth_by_id(booth_id)
      return nil if booth_id.blank?

      booth = Booth.find_by(id: booth_id)
      return nil if booth.blank?

      return booth if current_user.system_admin?
      return booth if BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)

      # 不正（所有していない booth を指している）
      session.delete(:current_booth_id)
      nil
    end

    def resolve_fallback_booth
      return nil if current_user.system_admin?

      Booth.joins(:booth_casts)
           .where(booth_casts: { cast_user_id: current_user.id })
           .order(:id)
           .first
    end

    # current_booth が解決できない / 不正だった場合は一覧へ戻す
    def require_current_booth!
      return if current_booth.present?

      redirect_to cast_booths_path, alert: "操作対象のブースが選択されていません"
    end
  end
end
