# frozen_string_literal: true

require "test_helper"

class PhoneVerifications::IssueOtpServiceTest < ActiveSupport::TestCase
  FakeSmsSender = Struct.new(:deliveries) do
    def deliver!(phone_number:, message:)
      deliveries << { phone_number:, message: }
    end
  end

  setup do
    @sms_sender = FakeSmsSender.new([])
  end

  test "issues otp and sends sms" do
    result = PhoneVerifications::IssueOtpService.new(
      phone_number: "09012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      sms_sender: @sms_sender
    ).call!

    phone_verification = result.phone_verification

    assert_equal "+819012345678", result.phone_number
    assert_equal "+819012345678", phone_verification.phone_number
    assert_equal PhoneVerification::PURPOSE_VERIFY_PHONE, phone_verification.purpose
    assert_equal 0, phone_verification.attempts_count
    assert phone_verification.expires_at > Time.current
    assert_equal 1, @sms_sender.deliveries.size
    assert_equal "+819012345678", @sms_sender.deliveries.first[:phone_number]
    assert_match(/\A\d{6}\z/, result.otp_code)
    assert_not_equal result.otp_code, phone_verification.otp_code_digest
  end

  test "raises when resend is restricted" do
    PhoneVerification.create!(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: Digest::SHA256.hexdigest("123456"),
      expires_at: 5.minutes.from_now,
      last_sent_at: Time.current,
      attempts_count: 0
    )

    assert_raises(PhoneVerifications::IssueOtpService::ResendRestricted) do
      PhoneVerifications::IssueOtpService.new(
        phone_number: "09012345678",
        purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
        sms_sender: @sms_sender
      ).call!
    end
  end

  test "invalidates previous active otp when issuing a new one" do
    old = PhoneVerification.create!(
      phone_number: "+819012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      otp_code_digest: Digest::SHA256.hexdigest("123456"),
      expires_at: 5.minutes.from_now,
      last_sent_at: 2.minutes.ago,
      attempts_count: 0
    )

    result = PhoneVerifications::IssueOtpService.new(
      phone_number: "09012345678",
      purpose: PhoneVerification::PURPOSE_VERIFY_PHONE,
      sms_sender: @sms_sender
    ).call!

    assert old.reload.invalidated_at.present?
    assert result.phone_verification.active?
  end
end
