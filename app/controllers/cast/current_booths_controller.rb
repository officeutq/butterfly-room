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
        redirect_to live_cast_booth_path(result.booth), notice: "ブースを選択しました"
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
  end
end
