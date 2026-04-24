# frozen_string_literal: true

class EmailChangesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    if @user.update_with_password(email_change_params)
      bypass_sign_in(@user)
      redirect_to edit_profile_path, notice: "メールアドレスを変更しました"
    else
      @user.email = current_user.email
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def email_change_params
    params.require(:user).permit(:email, :current_password)
  end
end
