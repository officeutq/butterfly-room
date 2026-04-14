# frozen_string_literal: true

require "digest"

module PhoneVerifications
  class VerifyOtpService
    class InvalidPurpose < StandardError; end
    class NotFound < StandardError; end
    class Expired < StandardError; end
    class AttemptsExceeded < StandardError; end
    class InvalidCode < StandardError; end
    class AlreadyCompleted < StandardError; end

    MAX_ATTEMPTS = 5

    Result = Struct.new(:phone_verification, keyword_init: true)

    def initialize(phone_number:, purpose:, otp_code:)
      @raw_phone_number = phone_number
      @purpose = purpose.to_s
      @otp_code = otp_code.to_s
    end

    def call!
      validate_purpose!

      normalized_phone_number = PhoneNumberNormalizer.call(@raw_phone_number)

      phone_verification = PhoneVerification
                             .for_phone_and_purpose(normalized_phone_number, @purpose)
                             .recent_first
                             .lock
                             .first

      raise NotFound if phone_verification.blank?
      raise AlreadyCompleted unless phone_verification.active?
      raise Expired if phone_verification.expired?
      raise AttemptsExceeded if phone_verification.attempts_exceeded?(max_attempts: MAX_ATTEMPTS)

      if secure_match?(phone_verification.otp_code_digest, digest_for(@otp_code))
        now = Time.current

        phone_verification.update!(
          verified_at: now,
          consumed_at: now
        )

        return Result.new(phone_verification:)
      end

      phone_verification.increment!(:attempts_count)

      if phone_verification.reload.attempts_exceeded?(max_attempts: MAX_ATTEMPTS)
        raise AttemptsExceeded
      end

      raise InvalidCode
    end

    private

    def validate_purpose!
      raise InvalidPurpose unless PhoneVerification::PURPOSES.include?(@purpose)
    end

    def digest_for(code)
      Digest::SHA256.hexdigest(code.to_s)
    end

    def secure_match?(left, right)
      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
