# frozen_string_literal: true

class EmailChangesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user = current_user
    render :edit, layout: "account_modal" if turbo_frame_request?
  end

  def update
    @user = current_user

    if Accounts::ChangeEmailService.new(user: @user, attributes: email_change_params).call
      bypass_sign_in(@user)
      if turbo_frame_request?
        render turbo_stream: [
          turbo_stream.replace("profile-account-email", partial: "profiles/account_email", locals: { user: @user }),
          turbo_stream.update("profile-account-notice", html: "メールアドレスを変更しました"),
          turbo_stream.append("modal", partial: "shared/account_modal_complete")
        ]
      else
        redirect_to edit_profile_path, notice: "メールアドレスを変更しました"
      end
    else
      render :edit, formats: [ :html ], layout: (turbo_frame_request? ? "account_modal" : "application"),
                    status: :unprocessable_entity
    end
  end

  private

  def email_change_params
    params.require(:user).permit(:email, :current_password)
  end
end
