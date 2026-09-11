# frozen_string_literal: true

module PhoneVerifications
  class RegisterPhoneService
    class NumberTaken < StandardError; end

    def initialize(user:, phone_number:, otp_code:)
      @user = user
      @phone_number = PhoneNumberNormalizer.call(phone_number)
      @otp_code = otp_code
    end

    def call!
      verification_error = nil
      @user.with_lock do
        begin
          VerifyOtpService.new(
            phone_number: @phone_number,
            purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
            otp_code: @otp_code,
            user: @user
          ).call!
        rescue VerifyOtpService::NotFound, VerifyOtpService::InvalidCode,
               VerifyOtpService::Expired, VerifyOtpService::AttemptsExceeded,
               VerifyOtpService::AlreadyCompleted => error
          # 誤入力回数を確定してから呼び出し元へエラーを返す。
          verification_error = error
        end

        unless verification_error
          if User.active.where.not(id: @user.id).exists?(phone_number: @phone_number)
            raise NumberTaken
          end
          @user.update!(phone_number: @phone_number, phone_verified_at: Time.current)
        end
      end

      raise verification_error if verification_error

      @user
    rescue ActiveRecord::RecordNotUnique
      raise NumberTaken
    end
  end
end
