# frozen_string_literal: true

module Cast
  class CurrentBoothsController < Cast::BaseController
    def create
      booth_id = params.require(:booth_id)

      booth = Booth.active.find_by(id: booth_id)
      if booth.blank?
        session.delete(:current_booth_id)
        redirect_to cast_booths_path, alert: "ブースが見つかりません"
        return
      end

      allowed =
        if current_user.system_admin?
          true
        elsif current_user.at_least?(:store_admin)
          current_user.admin_of_store?(booth.store_id)
        else
          BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)
        end

      unless allowed
        session.delete(:current_booth_id)
        redirect_to cast_booths_path, alert: "選択できないブースです"
        return
      end

      session[:current_booth_id] = booth.id

      result = ::Booths::EnterAsCastService.new(
        booth: booth,
        actor: current_user
      ).call

      case result.action
      when :redirect_live
        redirect_to resolve_redirect_path(result.booth), notice: "ブースを選択しました"
      when :occupied_by_other
        redirect_to cast_booths_path, alert: "このブースはすでに配信中です"
      else
        redirect_to cast_booths_path, alert: "ブースを開けませんでした"
      end
    rescue ::Booths::EnterAsCastService::NotAuthorized
      session.delete(:current_booth_id)
      redirect_to cast_booths_path, alert: "選択できないブースです"
    rescue ActionController::ParameterMissing
      redirect_to cast_booths_path, alert: "ブースを選択してください"
    end

    private

    # Issue #304: ブース選択後の遷移先決定
    #
    # 1) return_to_key（allowlist）
    # 2) return_to（安全な相対パスのみ）
    # 3) session[:cast_return_to]（/cast/ 直前ページ）
    # 4) dashboard_path
    #
    # 特例:
    # - /cast/booths 画面からのPOSTは session 戻りを使わない
    def resolve_redirect_path(booth)
      key = params[:return_to_key].presence
      if key.present?
        path = resolve_return_to_key(key, booth)
        return path if path.present?
      end

      rt = safe_return_to(params[:return_to])
      return rt if rt.present?

      if request.referer.to_s.start_with?(cast_booths_url)
        return dashboard_path
      end

      session_rt = safe_return_to(session[:cast_return_to])
      return session_rt if session_rt.present?

      dashboard_path
    end

    def resolve_return_to_key(key, booth)
      return nil if booth.blank?

      case key.to_s
      when "booth_edit"
        edit_cast_booth_path(booth)
      when "booth_live"
        live_cast_booth_path(booth)
      else
        nil
      end
    end

    # open redirect対策：安全な相対パスのみ許可
    def safe_return_to(value)
      s = value.to_s
      return nil if s.blank?

      return nil unless s.start_with?("/")
      return nil if s.start_with?("//")
      return nil if s.include?("\n") || s.include?("\r")
      return nil if s.include?("\0")

      # ループ/ノイズ防止：選択画面と選択POSTには戻さない
      return nil if s == "/cast/booths"
      return nil if s == "/cast/current_booth"

      s
    end
  end
end
