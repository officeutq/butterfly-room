# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @user = current_user
  end

  def update
    @user = current_user

    attributes = profile_params.to_h.symbolize_keys
    upload = attributes.delete(:avatar)
    remove_avatar = attributes.delete(:remove_avatar)

    begin
      Profiles::UpdateService.new(
        user: @user,
        attributes:,
        image_updates: image_pair_payloads,
        legacy_avatar_upload: upload,
        remove_legacy_avatar: remove_avatar
      ).call
    rescue Profiles::UpdateService::StaleImageError
      return respond_profile_update_error(
        @user.errors.full_messages,
        status: :conflict,
        code: "image_pair_stale"
      )
    rescue Profiles::UpdateService::ImageUploadError
      return respond_profile_update_error(
        @user.errors.full_messages,
        status: :service_unavailable,
        code: "image_upload_failed",
        retryable: true
      )
    rescue ActiveRecord::RecordInvalid, Profiles::UpdateService::Error
      return respond_profile_update_error(@user.errors.full_messages)
    rescue ActionController::ParameterMissing, ImageAttachments::MultipartPayload::Invalid => error
      @user.errors.add(:base, error.message)
      return respond_profile_update_error(@user.errors.full_messages)
    end

    destination = if session.delete(:redirect_to_booth_edit_after_profile_update)
      booth = current_booth_for_invitation_flow

      if booth.present?
        # ★追加：初回プロフィール入力時のみブース名を補完
        if booth.name == "ななしさんのブース" && @user.display_name.present?
          booth.update!(name: "#{@user.display_name}のブース")
        end

        session[:redirect_to_home_after_cast_booth_update] = true
        edit_cast_booth_path(booth)
      else
        root_path
      end
    else
      root_path
    end

    respond_to do |format|
      format.html { redirect_to destination, notice: "プロフィールを更新しました" }
      format.json do
        flash[:notice] = "プロフィールを更新しました"
        render json: { state: "complete", redirect_url: destination }
      end
    end
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :bio, :avatar, :remove_avatar)
  end

  def image_pair_payloads
    {
      avatar: :avatar_image_pair,
      cover: :cover_image_pair
    }.filter_map do |purpose, root|
      next if params.dig(root, :operation).blank?

      [ purpose, ImageAttachments::MultipartPayload.from_params(params, root:) ]
    end.to_h
  rescue TypeError
    raise ImageAttachments::MultipartPayload::Invalid, "画像送信パラメータが不正です。"
  end

  def current_booth_for_invitation_flow
    booth_id = session[:current_booth_id]
    return nil if booth_id.blank?

    Booth.active.joins(:booth_casts)
         .find_by(id: booth_id, booth_casts: { cast_user_id: current_user.id })
  end

  def respond_profile_update_error(
    messages,
    status: :unprocessable_entity,
    code: "profile_update_invalid",
    retryable: false
  )
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

      format.json do
        render json: { error: code, message:, retryable: }, status:
      end
    end
  end
end
