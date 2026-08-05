# frozen_string_literal: true

module Users
  class PasswordsController < Devise::PasswordsController
    protected

    def require_no_authentication
      if password_email_link?
        sign_out(resource_name) if warden.authenticated?(resource_name)
      else
        super
      end
    end

    def password_email_link?
      return false unless action_name.in?(%w[edit new])

      token = params[:reset_password_token].to_s
      token.present? && resource_class.with_reset_password_token(token).present?
    end
  end
end
