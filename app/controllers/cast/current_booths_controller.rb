# frozen_string_literal: true

module Cast
  class CurrentBoothsController < Cast::BaseController
    def create
      booth_id = params.require(:booth_id)

      booth = Booth.find_by(id: booth_id)
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

      path = booth.offline? ? cast_booth_path(booth) : live_cast_booth_path(booth)
      redirect_to path, notice: "ブースを選択しました"
    rescue ActionController::ParameterMissing
      redirect_to cast_booths_path, alert: "ブースを選択してください"
    end
  end
end
