# frozen_string_literal: true

class ProfilesController < ApplicationController
  include RemovableImageAttachment
  include AttachmentPersistenceChecker

  before_action :authenticate_user!

  def edit
    @user = current_user
    @pending_phone_number = nil
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

  def send_phone_otp
    @user = current_user
    @pending_phone_number = phone_otp_params[:phone_number]

    PhoneVerifications::IssueOtpService.new(
      phone_number: @pending_phone_number,
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      user: @user
    ).call!

    redirect_to edit_profile_path(phone_number: @pending_phone_number),
                notice: "認証コードをSMSで送信しました"
  rescue PhoneVerifications::PhoneNumberNormalizer::InvalidPhoneNumber
    redirect_to edit_profile_path, alert: "電話番号の形式が正しくありません"
  rescue PhoneVerifications::IssueOtpService::ResendRestricted
    redirect_to edit_profile_path(phone_number: @pending_phone_number),
                alert: "認証コードの再送は60秒後にお試しください"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_profile_path, alert: e.record.errors.full_messages.join(" / ")
  end

  def verify_phone_otp
    @user = current_user
    @pending_phone_number = verify_phone_otp_params[:phone_number]

    result = PhoneVerifications::VerifyOtpService.new(
      phone_number: @pending_phone_number,
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code: verify_phone_otp_params[:otp_code]
    ).call!

    phone_number = result.phone_verification.phone_number

    if User.where.not(id: @user.id).exists?(phone_number: phone_number)
      return redirect_to edit_profile_path(phone_number: phone_number),
                         alert: "この電話番号はすでに他のユーザーに登録されています"
    end

    @user.update!(
      phone_number: phone_number,
      phone_verified_at: Time.current
    )

    redirect_to edit_profile_path, notice: "電話番号を認証して登録しました"
  rescue PhoneVerifications::PhoneNumberNormalizer::InvalidPhoneNumber
    redirect_to edit_profile_path, alert: "電話番号の形式が正しくありません"
  rescue PhoneVerifications::VerifyOtpService::NotFound,
         PhoneVerifications::VerifyOtpService::InvalidCode
    redirect_to edit_profile_path(phone_number: @pending_phone_number),
                alert: "認証コードが正しくありません"
  rescue PhoneVerifications::VerifyOtpService::Expired
    redirect_to edit_profile_path(phone_number: @pending_phone_number),
                alert: "認証コードの有効期限が切れています"
  rescue PhoneVerifications::VerifyOtpService::AttemptsExceeded
    redirect_to edit_profile_path(phone_number: @pending_phone_number),
                alert: "認証コードの試行回数が上限に達しました"
  rescue PhoneVerifications::VerifyOtpService::AlreadyCompleted
    redirect_to edit_profile_path(phone_number: @pending_phone_number),
                alert: "この認証コードはすでに使用されています"
  end

  private

  def profile_params
    params.require(:user).permit(:display_name, :bio, :avatar)
  end

  def phone_otp_params
    params.permit(:phone_number)
  end

  def verify_phone_otp_params
    params.permit(:phone_number, :otp_code)
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
