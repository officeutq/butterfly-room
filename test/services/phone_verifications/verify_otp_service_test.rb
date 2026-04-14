# frozen_string_literal: true

require "test_helper"

class PhoneVerifications::VerifyOtpServiceTest < ActiveSupport::TestCase
  test "verifies correct otp" do
    issue_result = PhoneVerifications::IssueOtpService.new(
      phone_number: "09012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      sms_sender: fake_sms_sender
    ).call!

    result = PhoneVerifications::VerifyOtpService.new(
      phone_number: "09012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code: issue_result.otp_code
    ).call!

    phone_verification = result.phone_verification.reload

    assert phone_verification.verified_at.present?
    assert phone_verification.consumed_at.present?
  end

  test "raises when otp is expired" do
    phone_verification = PhoneVerification.create!(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: Digest::SHA256.hexdigest("123456"),
      expires_at: 1.second.ago,
      last_sent_at: 6.minutes.ago,
      attempts_count: 0
    )

    assert_raises(PhoneVerifications::VerifyOtpService::Expired) do
      PhoneVerifications::VerifyOtpService.new(
        phone_number: phone_verification.phone_number,
        purpose: phone_verification.purpose,
        otp_code: "123456"
      ).call!
    end
  end

  test "raises when attempts are exceeded" do
    phone_verification = PhoneVerification.create!(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: Digest::SHA256.hexdigest("123456"),
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      attempts_count: 5
    )

    assert_raises(PhoneVerifications::VerifyOtpService::AttemptsExceeded) do
      PhoneVerifications::VerifyOtpService.new(
        phone_number: phone_verification.phone_number,
        purpose: phone_verification.purpose,
        otp_code: "123456"
      ).call!
    end
  end

  test "increments attempts_count when otp is invalid" do
    phone_verification = PhoneVerification.create!(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: Digest::SHA256.hexdigest("123456"),
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      attempts_count: 0
    )

    assert_raises(PhoneVerifications::VerifyOtpService::InvalidCode) do
      PhoneVerifications::VerifyOtpService.new(
        phone_number: phone_verification.phone_number,
        purpose: phone_verification.purpose,
        otp_code: "999999"
      ).call!
    end

    assert_equal 1, phone_verification.reload.attempts_count
  end

  test "raises attempts exceeded on fifth invalid attempt" do
    phone_verification = PhoneVerification.create!(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: Digest::SHA256.hexdigest("123456"),
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      attempts_count: 4
    )

    assert_raises(PhoneVerifications::VerifyOtpService::AttemptsExceeded) do
      PhoneVerifications::VerifyOtpService.new(
        phone_number: phone_verification.phone_number,
        purpose: phone_verification.purpose,
        otp_code: "999999"
      ).call!
    end

    assert_equal 5, phone_verification.reload.attempts_count
  end

  private

  def fake_sms_sender
    Struct.new(:deliver!) do
      def deliver!(*); end
    end.new
  end
end
