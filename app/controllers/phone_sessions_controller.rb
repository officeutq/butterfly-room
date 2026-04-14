# frozen_string_literal: true

class PhoneSessionsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def new
    @phone_number = session[:pending_phone_login_number]
  end

  def create
    normalized_phone_number = PhoneVerifications::PhoneNumberNormalizer.call(params[:phone_number].to_s)

    session[:pending_phone_login_number] = normalized_phone_number

    user = User.find_by(phone_number: normalized_phone_number)

    if user&.phone_verified? && user.active_for_authentication?
      PhoneVerifications::IssueOtpService.new(
        phone_number: normalized_phone_number,
        purpose: PhoneVerification::PURPOSE_LOGIN,
        user: user
      ).call!
    end

    redirect_to confirm_phone_session_path, notice: "認証コードを送信しました（登録済みの場合）"
  rescue PhoneVerifications::PhoneNumberNormalizer::InvalidPhoneNumber
    redirect_to phone_session_path, alert: "電話番号の形式が正しくありません"
  rescue PhoneVerifications::IssueOtpService::ResendRestricted
    redirect_to confirm_phone_session_path, alert: "認証コードの再送は60秒後にお試しください"
  end

  def confirm
    @phone_number = session[:pending_phone_login_number]

    return if @phone_number.present?

    redirect_to phone_session_path, alert: "先に電話番号を入力してください"
  end

  def verify
    phone_number = session[:pending_phone_login_number].to_s
    otp_code = params[:otp_code].to_s

    if phone_number.blank?
      return redirect_to phone_session_path, alert: "先に電話番号を入力してください"
    end

    result = PhoneVerifications::VerifyOtpService.new(
      phone_number:,
      purpose: PhoneVerification::PURPOSE_LOGIN,
      otp_code:
    ).call!

    user = User.find_by(phone_number: result.phone_verification.phone_number)

    unless user&.phone_verified? && user.active_for_authentication?
      return redirect_to phone_session_path, alert: "電話番号または認証コードが正しくありません"
    end

    session.delete(:pending_phone_login_number)
    sign_in(user)

    redirect_to after_sign_in_path_for(user), notice: "ログインしました"
  rescue PhoneVerifications::VerifyOtpService::NotFound,
         PhoneVerifications::VerifyOtpService::InvalidCode,
         PhoneVerifications::VerifyOtpService::AlreadyCompleted
    redirect_to confirm_phone_session_path, alert: "電話番号または認証コードが正しくありません"
  rescue PhoneVerifications::VerifyOtpService::Expired
    redirect_to confirm_phone_session_path, alert: "認証コードの有効期限が切れています"
  rescue PhoneVerifications::VerifyOtpService::AttemptsExceeded
    redirect_to confirm_phone_session_path, alert: "認証コードの試行回数が上限に達しました"
  end
end
