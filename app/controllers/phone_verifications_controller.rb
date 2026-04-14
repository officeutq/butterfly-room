# frozen_string_literal: true

class PhoneVerificationsController < ApplicationController
  before_action :authenticate_user!

  def new
    @user = current_user
    @phone_number = session[:pending_phone_verification_number].presence || @user.phone_number
  end

  def create
    @user = current_user
    phone_number = params[:phone_number].to_s

    result = PhoneVerifications::IssueOtpService.new(
      phone_number:,
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      user: @user
    ).call!

    session[:pending_phone_verification_number] = result.phone_number

    redirect_to confirm_phone_verification_path, notice: "認証コードをSMSで送信しました"
  rescue PhoneVerifications::PhoneNumberNormalizer::InvalidPhoneNumber
    redirect_to phone_verification_path, alert: "電話番号の形式が正しくありません"
  rescue PhoneVerifications::IssueOtpService::ResendRestricted
    session[:pending_phone_verification_number] = phone_number
    redirect_to confirm_phone_verification_path, alert: "認証コードの再送は60秒後にお試しください"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to phone_verification_path, alert: e.record.errors.full_messages.join(" / ")
  end

  def confirm
    @user = current_user
    @phone_number = session[:pending_phone_verification_number]

    if @phone_number.blank?
      redirect_to phone_verification_path, alert: "先に電話番号を入力してください"
    end
  end

  def verify
    @user = current_user
    phone_number = session[:pending_phone_verification_number].to_s
    otp_code = params[:otp_code].to_s

    if phone_number.blank?
      return redirect_to phone_verification_path, alert: "先に電話番号を入力してください"
    end

    result = PhoneVerifications::VerifyOtpService.new(
      phone_number:,
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code:
    ).call!

    normalized_phone_number = result.phone_verification.phone_number

    if User.where.not(id: @user.id).exists?(phone_number: normalized_phone_number)
      return redirect_to phone_verification_path,
                         alert: "この電話番号はすでに他のユーザーに登録されています"
    end

    @user.update!(
      phone_number: normalized_phone_number,
      phone_verified_at: Time.current
    )

    session.delete(:pending_phone_verification_number)

    redirect_to dashboard_path, notice: "電話番号を認証して登録しました"
  rescue PhoneVerifications::VerifyOtpService::NotFound,
         PhoneVerifications::VerifyOtpService::InvalidCode
    redirect_to confirm_phone_verification_path, alert: "認証コードが正しくありません"
  rescue PhoneVerifications::VerifyOtpService::Expired
    redirect_to confirm_phone_verification_path, alert: "認証コードの有効期限が切れています"
  rescue PhoneVerifications::VerifyOtpService::AttemptsExceeded
    redirect_to confirm_phone_verification_path, alert: "認証コードの試行回数が上限に達しました"
  rescue PhoneVerifications::VerifyOtpService::AlreadyCompleted
    redirect_to confirm_phone_verification_path, alert: "この認証コードはすでに使用されています"
  end
end
