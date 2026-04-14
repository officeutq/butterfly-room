# frozen_string_literal: true

require "test_helper"

class PhoneVerificationTest < ActiveSupport::TestCase
  test "purpose must be included in PURPOSES" do
    phone_verification = PhoneVerification.new(
      phone_number: "+819012345678",
      purpose: "unknown",
      otp_code_digest: "digest",
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      attempts_count: 0
    )

    assert_not phone_verification.valid?
    assert_includes phone_verification.errors.details[:purpose], { error: :inclusion, value: "unknown" }
  end

  test "attempts_count must be non negative" do
    phone_verification = PhoneVerification.new(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: "digest",
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      attempts_count: -1
    )

    assert_not phone_verification.valid?
    assert_includes phone_verification.errors.details[:attempts_count], { error: :greater_than_or_equal_to, value: -1, count: 0 }
  end

  test "active? returns false when invalidated" do
    phone_verification = PhoneVerification.new(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: "digest",
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      invalidated_at: Time.current
    )

    assert_not phone_verification.active?
  end
end
