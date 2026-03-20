# frozen_string_literal: true

class ProfilesController < ApplicationController
  include RemovableImageAttachment

  before_action :authenticate_user!

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    begin
      success = @user.update(profile_params)
    rescue NormalizedImageAttachment::InvalidImageAttachment => e
      @user.assign_attributes(profile_params.except(:avatar))
      @user.errors.add(:avatar, e.message)
      success = false
    end

    if success
      purge_attachment_if_requested(
        record: @user,
        attachment_name: :avatar,
        remove_param_name: :remove_avatar
      )

      redirect_to edit_profile_path, notice: "プロフィールを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :bio, :avatar)
  end
end
