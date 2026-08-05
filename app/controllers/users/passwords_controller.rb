# frozen_string_literal: true

module Users
  class PasswordsController < Devise::PasswordsController
    protected

    def require_no_authentication
      if action_name == "edit" && params[:reset_password_token].present?
        sign_out(resource_name) if warden.authenticated?(resource_name)
      else
        super
      end
    end
  end
end
