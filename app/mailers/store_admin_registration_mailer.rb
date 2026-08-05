# frozen_string_literal: true

class StoreAdminRegistrationMailer < ApplicationMailer
  def new_user_instructions
    set_common_values
    mail(to: @user.email, subject: "【Butterflyve】店舗管理者アカウントのパスワードを設定してください")
  end

  def existing_user_instructions
    set_common_values
    mail(to: @user.email, subject: "【Butterflyve】店舗管理者として追加されました")
  end

  private

  def set_common_values
    @user = params.fetch(:user)
    @store = params.fetch(:store)
    actor = params.fetch(:actor)
    @registration_status = params.fetch(:registration_status)
    reset_password_token = params.fetch(:reset_password_token)
    @registration_actor_name = actor.display_name.presence || "営業支援担当者"
    @password_url = edit_user_password_url(reset_password_token: reset_password_token)
    @login_url = new_user_session_url
    @password_request_url = new_user_password_url(reset_password_token: reset_password_token)
    @password_url_expiration_hours = Devise.reset_password_within.in_hours.to_i
  end
end
