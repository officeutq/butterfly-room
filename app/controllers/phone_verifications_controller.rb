# frozen_string_literal: true

class PhoneVerificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user

  def new
    @phone_number = session[:pending_phone_verification_number].presence || @user.phone_number
    step = session[:pending_phone_verification_number].present? && params[:edit] != "1" ? :confirm : :new
    render_step(step)
  end

  def create
    @phone_number = params[:phone_number].to_s
    result = PhoneVerifications::IssueOtpService.new(
      phone_number: @phone_number,
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      user: @user
    ).call!

    session[:pending_phone_verification_number] = @phone_number = result.phone_number
    respond_step(:confirm, message: "認証コードをSMSで送信しました")
  rescue PhoneVerifications::PhoneNumberNormalizer::InvalidPhoneNumber
    respond_step(:new, error: "電話番号の形式が正しくありません")
  rescue PhoneVerifications::IssueOtpService::ResendRestricted
    session[:pending_phone_verification_number] = @phone_number =
      PhoneVerifications::PhoneNumberNormalizer.call(@phone_number)
    respond_step(:confirm, error: "認証コードの再送は60秒後にお試しください")
  rescue ActiveRecord::RecordInvalid => error
    message = error.record.errors.full_messages.join(" / ")
    @user.reload
    respond_step(:new, error: message)
  rescue Sms::Sender::Error, Aws::SNS::Errors::ServiceError, Seahorse::Client::NetworkingError
    respond_step(:new, error: "認証コードを送信できませんでした。時間をおいて再度お試しください。")
  end

  def confirm
    @phone_number = session[:pending_phone_verification_number]
    return respond_step(:new, error: "先に電話番号を入力してください") if @phone_number.blank?

    render_step(:confirm)
  end

  def verify
    @phone_number = session[:pending_phone_verification_number].to_s
    return respond_step(:new, error: "先に電話番号を入力してください") if @phone_number.blank?

    PhoneVerifications::RegisterPhoneService.new(
      user: @user, phone_number: @phone_number, otp_code: params[:otp_code].to_s
    ).call!
    session.delete(:pending_phone_verification_number)

    if turbo_frame_request?
      render turbo_stream: [
        turbo_stream.replace("profile-account-phone", partial: "profiles/account_phone", locals: { user: @user }),
        turbo_stream.update("profile-account-phone-notice", html: "✓ 電話番号を認証して保存しました"),
        turbo_stream.append("modal", partial: "shared/account_modal_complete")
      ]
    else
      redirect_to edit_profile_path, notice: "✓ 電話番号を認証して保存しました"
    end
  rescue PhoneVerifications::RegisterPhoneService::NumberTaken
    respond_step(:new, error: "この電話番号はすでに他のユーザーに登録されています")
  rescue PhoneVerifications::PhoneNumberNormalizer::InvalidPhoneNumber
    respond_step(:new, error: "電話番号の形式が正しくありません")
  rescue ActiveRecord::RecordInvalid => error
    message = error.record.errors.full_messages.join(" / ")
    @user.reload
    respond_step(:new, error: message)
  rescue PhoneVerifications::VerifyOtpService::NotFound, PhoneVerifications::VerifyOtpService::InvalidCode
    respond_step(:confirm, error: "認証コードが正しくありません")
  rescue PhoneVerifications::VerifyOtpService::Expired
    respond_step(:confirm, error: "認証コードの有効期限が切れています")
  rescue PhoneVerifications::VerifyOtpService::AttemptsExceeded
    respond_step(:confirm, error: "認証コードの試行回数が上限に達しました")
  rescue PhoneVerifications::VerifyOtpService::AlreadyCompleted
    respond_step(:confirm, error: "この認証コードはすでに使用されています")
  end

  private

  def set_user
    @user = current_user
  end

  def render_step(step, status: :ok)
    render step, formats: [ :html ], layout: (turbo_frame_request? ? "account_modal" : "application"), status:
  end

  def respond_step(step, message: nil, error: nil)
    if turbo_frame_request?
      @message = message
      @error = error
      render_step(step, status: error ? :unprocessable_entity : :ok)
    else
      destination = step == :confirm ? confirm_phone_verification_path : phone_verification_path(edit: "1")
      redirect_to destination, notice: message, alert: error
    end
  end
end
