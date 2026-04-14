# frozen_string_literal: true

require "digest"

module PhoneVerifications
  class IssueOtpService
    class ResendRestricted < StandardError; end
    class InvalidPurpose < StandardError; end

    Result = Struct.new(
      :phone_verification,
      :phone_number,
      :otp_code,
      keyword_init: true
    )

    OTP_LENGTH = 6
    EXPIRES_IN = 5.minutes
    RESEND_INTERVAL = 60.seconds

    def initialize(phone_number:, purpose:, user: nil, sms_sender: Sms::Sender.new)
      @raw_phone_number = phone_number
      @purpose = purpose.to_s
      @user = user
      @sms_sender = sms_sender
    end

    def call!
      validate_purpose!

      normalized_phone_number = PhoneNumberNormalizer.call(@raw_phone_number)
      now = Time.current

      phone_verification = nil
      otp_code = generate_otp_code

      ApplicationRecord.transaction do
        latest_active = PhoneVerification
                          .for_phone_and_purpose(normalized_phone_number, @purpose)
                          .active
                          .recent_first
                          .lock
                          .first

        if latest_active.present? && latest_active.last_sent_at > now - RESEND_INTERVAL
          raise ResendRestricted
        end

        PhoneVerification
          .for_phone_and_purpose(normalized_phone_number, @purpose)
          .active
          .lock
          .update_all(invalidated_at: now, updated_at: now)

        phone_verification = PhoneVerification.create!(
          user: @user,
          phone_number: normalized_phone_number,
          purpose: @purpose,
          otp_code_digest: digest_for(otp_code),
          expires_at: now + EXPIRES_IN,
          last_sent_at: now,
          attempts_count: 0
        )
      end

      @sms_sender.deliver!(
        phone_number: normalized_phone_number,
        message: sms_message(otp_code)
      )

      Result.new(
        phone_verification:,
        phone_number: normalized_phone_number,
        otp_code:
      )
    end

    private

    def validate_purpose!
      raise InvalidPurpose unless PhoneVerification::PURPOSES.include?(@purpose)
    end

    def generate_otp_code
      format("%06d", SecureRandom.random_number(10**OTP_LENGTH))
    end

    def digest_for(code)
      Digest::SHA256.hexdigest(code.to_s)
    end

    def sms_message(otp_code)
      brand_name = ENV["SMS_OTP_BRAND_NAME"].presence ||
                   Rails.application.credentials.dig(:sms, :otp_brand_name).presence ||
                   "Butterflyve"

      "#{brand_name} の認証コードは #{otp_code} です。有効期限は5分です。"
    end
  end
end
