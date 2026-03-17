# frozen_string_literal: true

module Cast
  class BaseController < ApplicationController
    before_action -> { require_at_least!(:cast) }
    after_action :store_cast_return_to

    helper_method :current_booth

    private

    # cast領域の「直前ページ」をsessionに保存（Issue #304）
    #
    # - GET / HEAD の HTML のみ対象
    # - 200 OK のときだけ保存
    # - /cast/booths（選択画面）と /cast/current_booth（選択POST）では保存しない
    # - 保存値は /cast/ で始まる相対パスのみ
    def store_cast_return_to
      return unless request.get? || request.head?
      return unless request.format.html?
      return unless response.status == 200
      return unless request.fullpath.start_with?("/cast/")

      # 選択画面 / 選択POST では保存しない
      return if request.path == "/cast/booths"
      return if request.path == "/cast/current_booth"

      fullpath = request.fullpath.to_s

      # open redirect / 不正URL対策：/cast/ で始まり、// を含まないものだけ
      return unless fullpath.start_with?("/cast/")
      return if fullpath.start_with?("//")
      return if fullpath.include?("\n") || fullpath.include?("\r")
      return if fullpath.include?("\0")

      session[:cast_return_to] = fullpath
    end

    # session → params → fallback の順で current_booth を解決する。
    # ※ session 改ざん対策：毎回「操作可能booth」チェック（system_admin は例外）
    def current_booth
      return nil unless current_user.present?

      booth_id =
        session[:current_booth_id].presence ||
        params[:booth_id].presence ||
        params[:id].presence

      booth = resolve_operable_booth_by_id(booth_id)
      return booth if booth.present?

      fallback = resolve_fallback_booth
      return fallback if fallback.present?

      nil
    end

    def resolve_operable_booth_by_id(booth_id)
      return nil if booth_id.blank?

      booth = Booth.find_by(id: booth_id)
      return nil if booth.blank?

      return booth if current_user.system_admin?

      # store_admin：自分の store の booth なら cast 画面で操作可能
      if current_user.at_least?(:store_admin) && current_user.admin_of_store?(booth.store_id)
        return booth
      end

      # cast：所属 booth のみ
      return booth if BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)

      # 不正（操作できない booth を指している）
      session.delete(:current_booth_id)
      nil
    end

    def resolve_fallback_booth
      return nil if current_user.system_admin?

      # store_admin：自分の store の booth を優先（最小id）
      if current_user.at_least?(:store_admin)
        booth =
          Booth.joins(store: :store_memberships)
               .where(store_memberships: { user_id: current_user.id, membership_role: :admin })
               .order(:id)
               .first
        return booth if booth.present?
      end

      # cast：所属 booth（最小id）
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
