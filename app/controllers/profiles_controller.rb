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
        return respond_profile_update_error(@user.errors.full_messages)
      end

      purge_attachment_if_requested(
        record: @user,
        attachment_name: :avatar,
        remove_param_name: :remove_avatar
      )

      redirect_to root_path, notice: "プロフィールを更新しました"
    else
      respond_profile_update_error(@user.errors.full_messages)
    end
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :bio, :avatar)
  end

  def respond_profile_update_error(messages)
    message = messages.join(" / ")

    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message

        render turbo_stream: turbo_stream.update(
          "flash_inner",
          partial: "shared/flash_message",
          locals: { level: "danger", message: flash.now[:alert] }
        ), status: :unprocessable_entity
      end

      format.html do
        redirect_to edit_profile_path, alert: message
      end
    end
  end
end
