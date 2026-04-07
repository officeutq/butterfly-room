# frozen_string_literal: true

class ProfilesController < ApplicationController
  include RemovableImageAttachment
  include AttachmentPersistenceChecker

  before_action :authenticate_user!

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    success = @user.update(profile_params)

    if success
      unless ensure_attachment_persisted!(record: @user, attachment_name: :avatar)
        return render :edit, status: :unprocessable_entity
      end

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
